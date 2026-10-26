-- Migration 003: expenses (operating costs). Writes only through RPCs.
-- Amounts are numeric(12,2) in the business currency (PKR).

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  category text not null check (category in
    ('Rent','Salary','Utilities','Transport','Supplies','Marketing','Other')),
  amount numeric(12,2) not null check (amount > 0),
  expense_date date not null,
  description text,
  idempotency_key uuid,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  archived_at timestamptz
);

create index if not exists expenses_business_date_idx
  on public.expenses (business_id, expense_date desc);

create unique index if not exists expenses_business_idem_key
  on public.expenses (business_id, idempotency_key)
  where idempotency_key is not null;

alter table public.expenses enable row level security;

drop policy if exists "Members can view expenses" on public.expenses;
create policy "Members can view expenses"
  on public.expenses for select to authenticated
  using (public.is_active_business_member(business_id));

revoke all on public.expenses from anon, authenticated;
grant select on public.expenses to authenticated;

create or replace function public.create_expense(
  p_business_id uuid,
  p_category text,
  p_amount numeric,
  p_expense_date date,
  p_description text default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
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

  if p_category is null or p_category not in
     ('Rent','Salary','Utilities','Transport','Supplies','Marketing','Other') then
    raise exception 'Choose a valid category.';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 9999999999.99 then
    raise exception 'Amount must be greater than zero.';
  end if;
  if p_expense_date is null then
    raise exception 'Choose a date.';
  end if;
  if p_expense_date > current_date + 1 then
    raise exception 'Date cannot be in the future.';
  end if;

  if p_idempotency_key is not null then
    select id into v_id from public.expenses
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
    if found then
      return v_id;
    end if;
  end if;

  begin
    insert into public.expenses
      (business_id, category, amount, expense_date, description, idempotency_key, created_by)
    values
      (p_business_id, p_category, round(p_amount, 2), p_expense_date,
       nullif(trim(p_description), ''), p_idempotency_key, v_user)
    returning id into v_id;
  exception when unique_violation then
    select id into v_id from public.expenses
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
  end;

  return v_id;
end;
$$;

create or replace function public.archive_expense(p_expense_id uuid)
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

  select e.business_id into v_business_id
  from public.expenses e where e.id = p_expense_id;

  if v_business_id is null or not exists (
    select 1 from public.business_members bm
    where bm.business_id = v_business_id and bm.user_id = v_user and bm.status = 'active'
  ) then
    raise exception 'Expense not found.';
  end if;

  update public.expenses set archived_at = now()
  where id = p_expense_id and archived_at is null;
end;
$$;

revoke all on function public.create_expense(uuid, text, numeric, date, text, uuid) from public, anon;
revoke all on function public.archive_expense(uuid) from public, anon;
grant execute on function public.create_expense(uuid, text, numeric, date, text, uuid) to authenticated;
grant execute on function public.archive_expense(uuid) to authenticated;
