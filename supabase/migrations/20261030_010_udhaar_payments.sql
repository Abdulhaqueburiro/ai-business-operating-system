-- Migration 010: udhaar (credit sales) and customer payments.
-- * sales_orders.on_credit: a sale to a saved customer that is not paid now.
-- * customer_payments: money received later. Void instead of delete.
-- * Balance of a customer = confirmed credit orders - active payments.
-- * create_sales_order gets a 7th optional argument p_on_credit.
-- * get_dashboard_summary gets a new key "receivable" (total udhaar still to collect).
-- Writes only through RPCs.

alter table public.sales_orders
  add column if not exists on_credit boolean not null default false;

create table if not exists public.customer_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  amount numeric(12,2) not null check (amount > 0),
  paid_on date not null,
  note text check (note is null or length(note) <= 300),
  idempotency_key uuid,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  voided_at timestamptz
);

create index if not exists customer_payments_customer_idx
  on public.customer_payments (business_id, customer_id);

create unique index if not exists customer_payments_idem_key
  on public.customer_payments (business_id, idempotency_key)
  where idempotency_key is not null;

alter table public.customer_payments enable row level security;

drop policy if exists "Members can view customer payments" on public.customer_payments;
create policy "Members can view customer payments"
  on public.customer_payments for select to authenticated
  using (public.is_active_business_member(business_id));

revoke all on public.customer_payments from anon, authenticated;
grant select on public.customer_payments to authenticated;

-- Replace the 6-argument create_sales_order with a 7-argument one.
drop function if exists public.create_sales_order(uuid, jsonb, text, text, uuid, uuid);

create or replace function public.create_sales_order(
  p_business_id uuid,
  p_items jsonb,
  p_customer_name text default null,
  p_notes text default null,
  p_idempotency_key uuid default null,
  p_customer_id uuid default null,
  p_on_credit boolean default false
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_order_id uuid;
  v_count int;
  v_found int;
  v_items jsonb;
  v_customer_name text;
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

  if p_idempotency_key is not null then
    select id into v_order_id from public.sales_orders
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
    if found then
      return v_order_id;
    end if;
  end if;

  if coalesce(p_on_credit, false) and p_customer_id is null then
    raise exception 'A credit (udhaar) sale needs a saved customer.';
  end if;

  if p_customer_id is not null then
    select c.name into v_customer_name
    from public.customers c
    where c.id = p_customer_id
      and c.business_id = p_business_id
      and c.archived_at is null;
    if not found then
      raise exception 'Customer not found.';
    end if;
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 50 then
    raise exception 'Order must contain between 1 and 50 items.';
  end if;

  -- Merge duplicate products; validate quantities.
  select coalesce(jsonb_agg(jsonb_build_object('product_id', product_id, 'quantity', quantity)), '[]'::jsonb)
  into v_items
  from (
    select (e->>'product_id')::uuid as product_id,
           sum((e->>'quantity')::numeric) as quantity
    from jsonb_array_elements(p_items) e
    group by 1
  ) g;

  if exists (
    select 1 from jsonb_to_recordset(v_items) as t(product_id uuid, quantity numeric)
    where t.product_id is null or t.quantity is null or t.quantity <= 0
  ) then
    raise exception 'Every quantity must be greater than zero.';
  end if;

  select count(*) into v_count
  from jsonb_to_recordset(v_items) as t(product_id uuid, quantity numeric);
  select count(*) into v_found
  from jsonb_to_recordset(v_items) as t(product_id uuid, quantity numeric)
  join public.products p on p.id = t.product_id
   and p.business_id = p_business_id and p.is_active;
  if v_found <> v_count then
    raise exception 'One or more products are missing or not available.';
  end if;

  begin
    insert into public.sales_orders
      (business_id, customer_id, customer_name, notes, created_by, status, total_amount, idempotency_key, on_credit)
    values
      (p_business_id, p_customer_id,
       coalesce(v_customer_name, nullif(trim(p_customer_name), '')),
       nullif(trim(p_notes), ''),
       v_user, 'pending', 0, p_idempotency_key, coalesce(p_on_credit, false))
    returning id into v_order_id;
  exception when unique_violation then
    select id into v_order_id from public.sales_orders
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
    return v_order_id;
  end;

  insert into public.sales_order_items (order_id, product_id, quantity, unit_price)
  select v_order_id, t.product_id, t.quantity, p.price
  from jsonb_to_recordset(v_items) as t(product_id uuid, quantity numeric)
  join public.products p on p.id = t.product_id;

  update public.sales_orders
  set total_amount = (select coalesce(sum(line_total), 0)
                      from public.sales_order_items where order_id = v_order_id),
      updated_at = now()
  where id = v_order_id;

  return v_order_id;
end;
$$;

revoke all on function public.create_sales_order(uuid, jsonb, text, text, uuid, uuid, boolean) from public, anon;
grant execute on function public.create_sales_order(uuid, jsonb, text, text, uuid, uuid, boolean) to authenticated;

-- Record money received from a customer.
create or replace function public.record_customer_payment(
  p_business_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_paid_on date default null,
  p_note text default null,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_amount numeric(12,2);
  v_today date := (now() at time zone 'Asia/Karachi')::date;
  v_date date := coalesce(p_paid_on, (now() at time zone 'Asia/Karachi')::date);
  v_balance numeric;
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

  if p_idempotency_key is not null then
    select id into v_id from public.customer_payments
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
    if found then
      return v_id;
    end if;
  end if;

  -- Lock the customer row so two payments cannot both pass the balance check.
  perform 1 from public.customers c
  where c.id = p_customer_id and c.business_id = p_business_id
  for update;
  if not found then
    raise exception 'Customer not found.';
  end if;

  if p_amount is null or p_amount <= 0 or p_amount >= 1000000000 then
    raise exception 'Amount must be greater than zero.';
  end if;
  v_amount := round(p_amount, 2);
  if v_amount <= 0 then
    raise exception 'Amount must be greater than zero.';
  end if;

  if v_date > v_today then
    raise exception 'Date cannot be in the future.';
  end if;

  select coalesce(sum(t.delta), 0) into v_balance
  from (
    select so.total_amount as delta
    from public.sales_orders so
    where so.business_id = p_business_id and so.customer_id = p_customer_id
      and so.status = 'confirmed' and so.on_credit
    union all
    select -cp.amount
    from public.customer_payments cp
    where cp.business_id = p_business_id and cp.customer_id = p_customer_id
      and cp.voided_at is null
  ) t;

  if v_amount > v_balance then
    raise exception 'Payment is more than the customer owes.';
  end if;

  begin
    insert into public.customer_payments
      (business_id, customer_id, amount, paid_on, note, idempotency_key, created_by)
    values
      (p_business_id, p_customer_id, v_amount, v_date,
       nullif(trim(coalesce(p_note, '')), ''), p_idempotency_key, v_user)
    returning id into v_id;
  exception when unique_violation then
    select id into v_id from public.customer_payments
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
  end;

  return v_id;
end;
$$;

revoke all on function public.record_customer_payment(uuid, uuid, numeric, date, text, uuid) from public, anon;
grant execute on function public.record_customer_payment(uuid, uuid, numeric, date, text, uuid) to authenticated;

-- Void a payment entered by mistake (kept in history, no longer counted).
create or replace function public.void_customer_payment(p_payment_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_business uuid;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select cp.business_id into v_business
  from public.customer_payments cp where cp.id = p_payment_id;
  if not found then
    raise exception 'Payment not found.';
  end if;

  if not exists (
    select 1 from public.business_members bm
    where bm.business_id = v_business and bm.user_id = v_user and bm.status = 'active'
  ) then
    raise exception 'You are not an active member of this business.';
  end if;

  update public.customer_payments
  set voided_at = now()
  where id = p_payment_id and voided_at is null;

  return 'ok';
end;
$$;

revoke all on function public.void_customer_payment(uuid) from public, anon;
grant execute on function public.void_customer_payment(uuid) to authenticated;

-- Balances for every customer who has credit or payment history.
create or replace function public.get_customer_balances(p_business_id uuid)
returns table (customer_id uuid, credit_total numeric, paid_total numeric, balance numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
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

  return query
  select t.cid,
         coalesce(sum(t.credit), 0),
         coalesce(sum(t.paid), 0),
         coalesce(sum(t.credit), 0) - coalesce(sum(t.paid), 0)
  from (
    select so.customer_id as cid, so.total_amount as credit, 0::numeric as paid
    from public.sales_orders so
    where so.business_id = p_business_id and so.status = 'confirmed'
      and so.on_credit and so.customer_id is not null
    union all
    select cp.customer_id, 0::numeric, cp.amount
    from public.customer_payments cp
    where cp.business_id = p_business_id and cp.voided_at is null
  ) t
  group by t.cid;
end;
$$;

revoke all on function public.get_customer_balances(uuid) from public, anon;
grant execute on function public.get_customer_balances(uuid) to authenticated;

-- Statement for one customer: credit sales (+) and payments (-), newest first.
create or replace function public.get_customer_ledger(p_business_id uuid, p_customer_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_entries jsonb;
  v_credit numeric;
  v_paid numeric;
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

  if not exists (
    select 1 from public.customers c
    where c.id = p_customer_id and c.business_id = p_business_id
  ) then
    raise exception 'Customer not found.';
  end if;

  select coalesce(sum(so.total_amount), 0) into v_credit
  from public.sales_orders so
  where so.business_id = p_business_id and so.customer_id = p_customer_id
    and so.status = 'confirmed' and so.on_credit;

  select coalesce(sum(cp.amount), 0) into v_paid
  from public.customer_payments cp
  where cp.business_id = p_business_id and cp.customer_id = p_customer_id
    and cp.voided_at is null;

  select coalesce(jsonb_agg(e.j order by e.at desc), '[]'::jsonb) into v_entries
  from (
    select so.created_at as at,
           jsonb_build_object('type', 'sale', 'id', so.id, 'at', so.created_at,
                              'amount', so.total_amount,
                              'note', 'Order #' || so.order_number) as j
    from public.sales_orders so
    where so.business_id = p_business_id and so.customer_id = p_customer_id
      and so.status = 'confirmed' and so.on_credit
    union all
    select cp.created_at,
           jsonb_build_object('type', 'payment', 'id', cp.id, 'at', cp.created_at,
                              'paid_on', cp.paid_on, 'amount', -cp.amount, 'note', cp.note)
    from public.customer_payments cp
    where cp.business_id = p_business_id and cp.customer_id = p_customer_id
      and cp.voided_at is null
    order by 1 desc
    limit 200
  ) e;

  return jsonb_build_object(
    'credit_total', v_credit,
    'paid_total', v_paid,
    'balance', v_credit - v_paid,
    'entries', v_entries
  );
end;
$$;

revoke all on function public.get_customer_ledger(uuid, uuid) from public, anon;
grant execute on function public.get_customer_ledger(uuid, uuid) to authenticated;

create or replace function public.get_dashboard_summary(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_start timestamptz;
  v_sales numeric;
  v_sales_count int;
  v_expenses numeric;
  v_pending int;
  v_low_count int;
  v_low_items jsonb;
  v_cogs numeric;
  v_sales_known numeric;
  v_missing int;
  v_receivable numeric;
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

  v_start := date_trunc('month', now() at time zone 'Asia/Karachi') at time zone 'Asia/Karachi';

  select coalesce(sum(so.total_amount), 0), count(*)
  into v_sales, v_sales_count
  from public.sales_orders so
  where so.business_id = p_business_id
    and so.status = 'confirmed'
    and so.created_at >= v_start;

  select coalesce(sum(oi.quantity * oi.unit_cost), 0),
         coalesce(sum(oi.line_total) filter (where oi.unit_cost is not null), 0),
         count(*) filter (where oi.unit_cost is null)
  into v_cogs, v_sales_known, v_missing
  from public.sales_order_items oi
  join public.sales_orders so on so.id = oi.order_id
  where so.business_id = p_business_id
    and so.status = 'confirmed'
    and so.created_at >= v_start;

  select coalesce(sum(x.bal), 0) into v_receivable
  from (
    select t.customer_id, sum(t.delta) as bal
    from (
      select so.customer_id, so.total_amount as delta
      from public.sales_orders so
      where so.business_id = p_business_id and so.status = 'confirmed'
        and so.on_credit and so.customer_id is not null
      union all
      select cp.customer_id, -cp.amount
      from public.customer_payments cp
      where cp.business_id = p_business_id and cp.voided_at is null
    ) t
    group by t.customer_id
    having sum(t.delta) > 0
  ) x;

  select coalesce(sum(e.amount), 0)
  into v_expenses
  from public.expenses e
  where e.business_id = p_business_id
    and e.archived_at is null
    and e.expense_date >= (v_start at time zone 'Asia/Karachi')::date;

  select count(*) into v_pending
  from public.sales_orders so
  where so.business_id = p_business_id and so.status = 'pending';

  select count(*), coalesce(jsonb_agg(jsonb_build_object('name', x.name, 'quantity', x.quantity, 'unit', x.unit) order by x.quantity, x.name), '[]'::jsonb)
  into v_low_count, v_low_items
  from (
    select p.name, p.unit, i.quantity
    from public.products p
    join public.inventory i on i.product_id = p.id and i.business_id = p.business_id
    where p.business_id = p_business_id and p.is_active and i.quantity <= 5
    order by i.quantity, p.name
    limit 10
  ) x;

  return jsonb_build_object(
    'confirmed_sales', v_sales,
    'confirmed_orders', v_sales_count,
    'expenses', v_expenses,
    'net', v_sales - v_expenses,
    'pending_orders', v_pending,
    'low_stock_count', v_low_count,
    'low_stock_items', v_low_items,
    'cost_of_goods', v_cogs,
    'gross_profit', v_sales_known - v_cogs,
    'net_profit', (v_sales_known - v_cogs) - v_expenses,
    'items_missing_cost', v_missing,
    'receivable', v_receivable
  );
end;
$$;

revoke all on function public.get_dashboard_summary(uuid) from public, anon;
grant execute on function public.get_dashboard_summary(uuid) to authenticated;
