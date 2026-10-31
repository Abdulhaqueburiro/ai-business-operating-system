-- Migration 013: daily limit for AI assistant questions.
-- Every question must first call consume_ai_quota(). Limits are fixed on the
-- server: 30 questions per user and 100 per business in any 24 hours.
-- The table cannot be read or written by the app directly.

create table if not exists public.ai_requests (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists ai_requests_user_idx
  on public.ai_requests (user_id, created_at desc);
create index if not exists ai_requests_business_idx
  on public.ai_requests (business_id, created_at desc);

alter table public.ai_requests enable row level security;
revoke all on public.ai_requests from anon, authenticated;

create or replace function public.consume_ai_quota(p_business_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_user_count int;
  v_business_count int;
  c_user_limit constant int := 30;
  c_business_limit constant int := 100;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not exists (
    select 1 from public.business_members bm
    where bm.business_id = p_business_id and bm.user_id = v_user and bm.status = 'active'
  ) then
    raise exception 'You are not an active member of this business.';
  end if;

  -- One question at a time per user, so two requests cannot both pass the check.
  perform pg_advisory_xact_lock(hashtext(v_user::text));

  select count(*) into v_user_count
  from public.ai_requests
  where user_id = v_user and created_at > now() - interval '24 hours';
  if v_user_count >= c_user_limit then
    raise exception 'Daily AI question limit reached. Please try again tomorrow.';
  end if;

  select count(*) into v_business_count
  from public.ai_requests
  where business_id = p_business_id and created_at > now() - interval '24 hours';
  if v_business_count >= c_business_limit then
    raise exception 'Your business reached its daily AI question limit. Please try again tomorrow.';
  end if;

  insert into public.ai_requests (business_id, user_id) values (p_business_id, v_user);

  return c_user_limit - v_user_count - 1;
end;
$$;

revoke all on function public.consume_ai_quota(uuid) from public, anon;
grant execute on function public.consume_ai_quota(uuid) to authenticated;
