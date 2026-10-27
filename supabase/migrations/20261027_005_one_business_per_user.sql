-- Migration 005: one active business per user (MVP rule).
create unique index if not exists business_members_one_active_per_user
  on public.business_members (user_id)
  where status = 'active';

create or replace function public.create_business(
  p_name text,
  p_business_type text default 'other'::text,
  p_currency_code text default 'PKR'::text,
  p_timezone text default 'Asia/Karachi'::text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_business_id uuid;
  v_name text := trim(coalesce(p_name, ''));
  v_currency text := upper(trim(coalesce(p_currency_code, 'PKR')));
  v_timezone text := trim(coalesce(p_timezone, 'Asia/Karachi'));
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if length(v_name) < 1 or length(v_name) > 120 then
    raise exception 'Business name must be between 1 and 120 characters' using errcode = '22023';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Currency code must be a three-letter ISO-style code' using errcode = '22023';
  end if;
  if v_timezone = '' then
    raise exception 'Timezone cannot be empty' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.business_members bm
    where bm.user_id = v_user_id and bm.status = 'active'
  ) then
    raise exception 'You already have a business.' using errcode = '23505';
  end if;

  insert into public.businesses (name, business_type, currency_code, timezone, created_by)
  values (
    v_name,
    coalesce(nullif(trim(p_business_type), ''), 'other'),
    v_currency,
    v_timezone,
    v_user_id
  )
  returning id into v_business_id;

  insert into public.business_members (business_id, user_id, role, status)
  values (v_business_id, v_user_id, 'owner', 'active');

  return v_business_id;
end;
$function$;
