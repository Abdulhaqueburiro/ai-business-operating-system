-- Migration 007: customers (step 1 of 3: database only; orders are linked later).
-- Writes only through RPCs. Archive instead of delete.

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  phone text check (phone is null or phone ~ '^[0-9+() -]{5,20}$'),
  notes text check (notes is null or length(notes) <= 500),
  idempotency_key uuid,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create index if not exists customers_business_name_idx
  on public.customers (business_id, name);

create unique index if not exists customers_business_idem_key
  on public.customers (business_id, idempotency_key)
  where idempotency_key is not null;

-- One active customer per phone number inside a business.
create unique index if not exists customers_business_phone_active
  on public.customers (business_id, phone)
  where phone is not null and archived_at is null;

alter table public.customers enable row level security;

drop policy if exists "Members can view customers" on public.customers;
create policy "Members can view customers"
  on public.customers for select to authenticated
  using (public.is_active_business_member(business_id));

revoke all on public.customers from anon, authenticated;
grant select on public.customers to authenticated;

create or replace function public.create_customer(
  p_business_id uuid,
  p_name text,
  p_phone text default null,
  p_notes text default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_name text := trim(coalesce(p_name, ''));
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
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

  if length(v_name) < 1 or length(v_name) > 120 then
    raise exception 'Customer name must be between 1 and 120 characters.';
  end if;
  if v_phone is not null and v_phone !~ '^[0-9+() -]{5,20}$' then
    raise exception 'Enter a valid phone number.';
  end if;
  if v_notes is not null and length(v_notes) > 500 then
    raise exception 'Notes must be 500 characters or fewer.';
  end if;

  if p_idempotency_key is not null then
    select id into v_id from public.customers
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
    if found then
      return v_id;
    end if;
  end if;

  if v_phone is not null and exists (
    select 1 from public.customers c
    where c.business_id = p_business_id and c.phone = v_phone and c.archived_at is null
  ) then
    raise exception 'A customer with this phone number already exists.';
  end if;

  begin
    insert into public.customers
      (business_id, name, phone, notes, idempotency_key, created_by)
    values
      (p_business_id, v_name, v_phone, v_notes, p_idempotency_key, v_user)
    returning id into v_id;
  exception when unique_violation then
    select id into v_id from public.customers
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
    if v_id is null then
      raise exception 'A customer with this phone number already exists.';
    end if;
  end;

  return v_id;
end;
$$;

create or replace function public.update_customer(
  p_customer_id uuid,
  p_name text,
  p_phone text default null,
  p_notes text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_business_id uuid;
  v_name text := trim(coalesce(p_name, ''));
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select c.business_id into v_business_id
  from public.customers c where c.id = p_customer_id and c.archived_at is null;

  if v_business_id is null or not exists (
    select 1 from public.business_members bm
    where bm.business_id = v_business_id and bm.user_id = v_user and bm.status = 'active'
  ) then
    raise exception 'Customer not found.';
  end if;

  if length(v_name) < 1 or length(v_name) > 120 then
    raise exception 'Customer name must be between 1 and 120 characters.';
  end if;
  if v_phone is not null and v_phone !~ '^[0-9+() -]{5,20}$' then
    raise exception 'Enter a valid phone number.';
  end if;
  if v_notes is not null and length(v_notes) > 500 then
    raise exception 'Notes must be 500 characters or fewer.';
  end if;

  if v_phone is not null and exists (
    select 1 from public.customers c
    where c.business_id = v_business_id and c.phone = v_phone
      and c.archived_at is null and c.id <> p_customer_id
  ) then
    raise exception 'A customer with this phone number already exists.';
  end if;

  update public.customers
  set name = v_name, phone = v_phone, notes = v_notes, updated_at = now()
  where id = p_customer_id;
end;
$$;

create or replace function public.archive_customer(p_customer_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_business_id uuid;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select c.business_id into v_business_id
  from public.customers c where c.id = p_customer_id;

  if v_business_id is null or not exists (
    select 1 from public.business_members bm
    where bm.business_id = v_business_id and bm.user_id = v_user and bm.status = 'active'
  ) then
    raise exception 'Customer not found.';
  end if;

  update public.customers set archived_at = now(), updated_at = now()
  where id = p_customer_id and archived_at is null;
end;
$$;

revoke all on function public.create_customer(uuid, text, text, text, uuid) from public, anon;
revoke all on function public.update_customer(uuid, text, text, text) from public, anon;
revoke all on function public.archive_customer(uuid) from public, anon;
grant execute on function public.create_customer(uuid, text, text, text, uuid) to authenticated;
grant execute on function public.update_customer(uuid, text, text, text) to authenticated;
grant execute on function public.archive_customer(uuid) to authenticated;
