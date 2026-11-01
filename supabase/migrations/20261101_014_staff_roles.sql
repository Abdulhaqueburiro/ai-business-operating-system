-- Migration 014: staff roles.
-- Two kinds of people in a business: owner/admin (managers) and staff.
-- Managers can do everything. Staff can sell (create and confirm orders),
-- add and edit customers, take customer payments and look at products and
-- stock. Staff can NOT: cancel orders, void payments, adjust stock, archive
-- customers, see or write expenses, open the dashboard or reports, use the
-- AI assistant, or manage staff.
-- NOTE: hiding cost prices from staff is a separate step (migration 015),
-- because the app has to change with it.

create or replace function public.is_business_manager(p_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.business_members bm
    where bm.business_id = p_business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
      and bm.role in ('owner', 'admin')
  );
$$;

revoke all on function public.is_business_manager(uuid) from public, anon;
grant execute on function public.is_business_manager(uuid) to authenticated;

-- Staff must not read expenses straight from the table either.
drop policy if exists "Members can view expenses" on public.expenses;
create policy "Managers can view expenses"
  on public.expenses for select to authenticated
  using (public.is_business_manager(business_id));


-- ---------------------------------------------------------------
-- Manager-only versions of existing functions. Each one is the current
-- definition plus one extra check right after the membership check.
-- ---------------------------------------------------------------

-- create_expense
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

  if not exists (
    select 1 from public.business_members bm
    where bm.business_id = p_business_id and bm.user_id = v_user and bm.status = 'active'
      and bm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the business owner can do this.';
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

-- archive_expense
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

  if not exists (
    select 1 from public.business_members bm
    where bm.business_id = v_business_id and bm.user_id = v_user and bm.status = 'active'
      and bm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the business owner can do this.';
  end if;

  update public.expenses set archived_at = now()
  where id = p_expense_id and archived_at is null;
end;
$$;

-- adjust_stock
create or replace function public.adjust_stock(
  p_product_id uuid,
  p_delta numeric,
  p_reason text default null
) returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_business_id uuid;
  v_current numeric;
  v_new numeric;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_delta is null or p_delta = 0 then
    raise exception 'Quantity change must not be zero.';
  end if;

  select p.business_id into v_business_id from public.products p where p.id = p_product_id;

  if v_business_id is null or not exists (
    select 1 from public.business_members bm
    where bm.business_id = v_business_id and bm.user_id = v_user and bm.status = 'active'
  ) then
    raise exception 'Product not found.';
  end if;

  if not exists (
    select 1 from public.business_members bm
    where bm.business_id = v_business_id and bm.user_id = v_user and bm.status = 'active'
      and bm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the business owner can do this.';
  end if;

  select i.quantity into v_current
  from public.inventory i
  where i.business_id = v_business_id and i.product_id = p_product_id
  for update;

  if not found then
    if p_delta < 0 then
      raise exception 'Not enough stock to remove that quantity.';
    end if;
    begin
      insert into public.inventory (business_id, product_id, quantity)
      values (v_business_id, p_product_id, p_delta)
      returning quantity into v_new;
    exception when unique_violation then
      -- another request created the row at the same moment: add to it
      update public.inventory
      set quantity = quantity + p_delta, updated_at = now()
      where business_id = v_business_id and product_id = p_product_id
      returning quantity into v_new;
    end;
  else
    if v_current + p_delta < 0 then
      raise exception 'Not enough stock to remove that quantity.';
    end if;
    update public.inventory
    set quantity = quantity + p_delta, updated_at = now()
    where business_id = v_business_id and product_id = p_product_id
    returning quantity into v_new;
  end if;

  insert into public.stock_movements
    (business_id, product_id, movement_type, quantity_delta, reason,
     reference_type, created_by)
  values
    (v_business_id, p_product_id,
     case when p_delta > 0 then 'restock' else 'adjustment' end,
     p_delta, nullif(trim(p_reason), ''), 'manual', v_user);

  return v_new;
end;
$$;

-- cancel_sales_order
create or replace function public.cancel_sales_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_business_id uuid;
  v_status text;
  v_item record;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select so.business_id into v_business_id
  from public.sales_orders so where so.id = p_order_id;

  if v_business_id is null or not exists (
    select 1 from public.business_members bm
    where bm.business_id = v_business_id and bm.user_id = v_user and bm.status = 'active'
  ) then
    raise exception 'Order not found.';
  end if;

  if not exists (
    select 1 from public.business_members bm
    where bm.business_id = v_business_id and bm.user_id = v_user and bm.status = 'active'
      and bm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the business owner can do this.';
  end if;

  select so.status into v_status
  from public.sales_orders so where so.id = p_order_id for update;

  if v_status = 'cancelled' then
    return; -- already cancelled: no second restore
  end if;
  if v_status not in ('pending', 'confirmed') then
    raise exception 'This order cannot be cancelled.';
  end if;

  if v_status = 'confirmed' then
    for v_item in
      select oi.product_id, sum(oi.quantity) as quantity
      from public.sales_order_items oi
      where oi.order_id = p_order_id
      group by oi.product_id
      order by oi.product_id
    loop
      insert into public.inventory (business_id, product_id, quantity)
      values (v_business_id, v_item.product_id, v_item.quantity)
      on conflict (business_id, product_id)
      do update set quantity = public.inventory.quantity + excluded.quantity,
                    updated_at = now();

      insert into public.stock_movements
        (business_id, product_id, movement_type, quantity_delta, reason,
         reference_type, reference_id, created_by)
      values
        (v_business_id, v_item.product_id, 'cancellation_restore', v_item.quantity,
         'Order cancelled', 'sales_order', p_order_id, v_user);
    end loop;
  end if;

  update public.sales_orders set status = 'cancelled', updated_at = now()
  where id = p_order_id;
end;
$$;

-- void_customer_payment
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

  if not exists (
    select 1 from public.business_members bm
    where bm.business_id = v_business and bm.user_id = v_user and bm.status = 'active'
      and bm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the business owner can do this.';
  end if;

  update public.customer_payments
  set voided_at = now()
  where id = p_payment_id and voided_at is null;

  return 'ok';
end;
$$;

-- get_dashboard_summary
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

  if not exists (
    select 1 from public.business_members bm
    where bm.business_id = p_business_id and bm.user_id = v_user and bm.status = 'active'
      and bm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the business owner can do this.';
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

  select count(*) into v_low_count
  from public.products p
  join public.inventory i on i.product_id = p.id and i.business_id = p.business_id
  where p.business_id = p_business_id and p.is_active
    and i.quantity <= coalesce(p.low_stock_threshold, 5);

  select coalesce(jsonb_agg(jsonb_build_object('name', x.name, 'quantity', x.quantity, 'unit', x.unit, 'threshold', x.threshold) order by x.quantity, x.name), '[]'::jsonb)
  into v_low_items
  from (
    select p.name, p.unit, i.quantity, coalesce(p.low_stock_threshold, 5) as threshold
    from public.products p
    join public.inventory i on i.product_id = p.id and i.business_id = p.business_id
    where p.business_id = p_business_id and p.is_active
      and i.quantity <= coalesce(p.low_stock_threshold, 5)
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

-- get_sales_report
create or replace function public.get_sales_report(
  p_business_id uuid,
  p_from date,
  p_to date
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_from_ts timestamptz;
  v_to_ts timestamptz;
  v_sales numeric;
  v_orders int;
  v_cogs numeric;
  v_sales_known numeric;
  v_missing int;
  v_expenses numeric;
  v_days jsonb;
  v_products jsonb;
  v_customers jsonb;
  v_categories jsonb;
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
    select 1 from public.business_members bm
    where bm.business_id = p_business_id and bm.user_id = v_user and bm.status = 'active'
      and bm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the business owner can do this.';
  end if;

  if p_from is null or p_to is null then
    raise exception 'Choose a start and an end date.';
  end if;
  if p_from > p_to then
    raise exception 'The start date must not be after the end date.';
  end if;
  if p_to - p_from > 365 then
    raise exception 'Choose a range of 366 days or less.';
  end if;

  v_from_ts := p_from::timestamp at time zone 'Asia/Karachi';
  v_to_ts := (p_to + 1)::timestamp at time zone 'Asia/Karachi';

  select coalesce(sum(so.total_amount), 0), count(*)
  into v_sales, v_orders
  from public.sales_orders so
  where so.business_id = p_business_id and so.status = 'confirmed'
    and so.created_at >= v_from_ts and so.created_at < v_to_ts;

  select coalesce(sum(oi.quantity * oi.unit_cost), 0),
         coalesce(sum(oi.line_total) filter (where oi.unit_cost is not null), 0),
         count(*) filter (where oi.unit_cost is null)
  into v_cogs, v_sales_known, v_missing
  from public.sales_order_items oi
  join public.sales_orders so on so.id = oi.order_id
  where so.business_id = p_business_id and so.status = 'confirmed'
    and so.created_at >= v_from_ts and so.created_at < v_to_ts;

  select coalesce(sum(e.amount), 0) into v_expenses
  from public.expenses e
  where e.business_id = p_business_id and e.archived_at is null
    and e.expense_date >= p_from and e.expense_date <= p_to;

  select coalesce(jsonb_agg(jsonb_build_object('date', d.day, 'sales', d.sales, 'orders', d.orders) order by d.day), '[]'::jsonb)
  into v_days
  from (
    select g.day::date as day,
           coalesce(sum(so.total_amount), 0) as sales,
           count(so.id) as orders
    from generate_series(p_from, p_to, interval '1 day') as g(day)
    left join public.sales_orders so
      on so.business_id = p_business_id and so.status = 'confirmed'
     and (so.created_at at time zone 'Asia/Karachi')::date = g.day::date
    group by g.day
  ) d;

  select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'unit', t.unit, 'quantity', t.qty, 'sales', t.sales) order by t.sales desc, t.name), '[]'::jsonb)
  into v_products
  from (
    select p.name, p.unit, sum(oi.quantity) as qty, sum(oi.line_total) as sales
    from public.sales_order_items oi
    join public.sales_orders so on so.id = oi.order_id
    join public.products p on p.id = oi.product_id
    where so.business_id = p_business_id and so.status = 'confirmed'
      and so.created_at >= v_from_ts and so.created_at < v_to_ts
    group by p.id, p.name, p.unit
    order by sum(oi.line_total) desc, p.name
    limit 10
  ) t;

  select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'orders', t.orders, 'sales', t.sales) order by t.sales desc, t.name), '[]'::jsonb)
  into v_customers
  from (
    select c.name, count(*) as orders, sum(so.total_amount) as sales
    from public.sales_orders so
    join public.customers c on c.id = so.customer_id
    where so.business_id = p_business_id and so.status = 'confirmed'
      and so.created_at >= v_from_ts and so.created_at < v_to_ts
    group by c.id, c.name
    order by sum(so.total_amount) desc, c.name
    limit 10
  ) t;

  select coalesce(jsonb_agg(jsonb_build_object('category', t.category, 'amount', t.amount) order by t.amount desc, t.category), '[]'::jsonb)
  into v_categories
  from (
    select e.category, sum(e.amount) as amount
    from public.expenses e
    where e.business_id = p_business_id and e.archived_at is null
      and e.expense_date >= p_from and e.expense_date <= p_to
    group by e.category
  ) t;

  return jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'sales', v_sales,
    'orders', v_orders,
    'cost_of_goods', v_cogs,
    'gross_profit', v_sales_known - v_cogs,
    'net_profit', (v_sales_known - v_cogs) - v_expenses,
    'expenses', v_expenses,
    'items_missing_cost', v_missing,
    'by_day', v_days,
    'top_products', v_products,
    'top_customers', v_customers,
    'expenses_by_category', v_categories
  );
end;
$$;

-- consume_ai_quota
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

  if not exists (
    select 1 from public.business_members bm
    where bm.business_id = p_business_id and bm.user_id = v_user and bm.status = 'active'
      and bm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the business owner can do this.';
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

-- archive_customer
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

  if not exists (
    select 1 from public.business_members bm
    where bm.business_id = v_business_id and bm.user_id = v_user and bm.status = 'active'
      and bm.role in ('owner', 'admin')
  ) then
    raise exception 'Only the business owner can do this.';
  end if;

  update public.customers set archived_at = now(), updated_at = now()
  where id = p_customer_id and archived_at is null;
end;
$$;

-- ---------------------------------------------------------------
-- Staff management
-- ---------------------------------------------------------------

create or replace function public.get_my_role(p_business_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select bm.role into v_role
  from public.business_members bm
  where bm.business_id = p_business_id and bm.user_id = v_user and bm.status = 'active';

  if v_role is null then
    raise exception 'You are not an active member of this business.';
  end if;

  return v_role;
end;
$$;

create or replace function public.list_business_staff(p_business_id uuid)
returns jsonb
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
  if not public.is_business_manager(p_business_id) then
    raise exception 'Only the business owner can do this.';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'user_id', bm.user_id,
        'email', u.email,
        'role', bm.role,
        'is_me', bm.user_id = v_user
      )
      order by (bm.role = 'staff'), u.email
    )
    from public.business_members bm
    join auth.users u on u.id = bm.user_id
    where bm.business_id = p_business_id and bm.status = 'active'
  ), '[]'::jsonb);
end;
$$;

create or replace function public.add_staff_member(p_business_id uuid, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_email text := lower(trim(coalesce(p_email, '')));
  v_target uuid;
  v_existing_business uuid;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not public.is_business_manager(p_business_id) then
    raise exception 'Only the business owner can do this.';
  end if;
  if v_email = '' or position('@' in v_email) < 2 then
    raise exception 'Type a valid email address.';
  end if;

  if (select count(*) from public.business_members bm
      where bm.business_id = p_business_id and bm.status = 'active') >= 20 then
    raise exception 'A business can have at most 20 people.';
  end if;

  select u.id into v_target from auth.users u where lower(u.email) = v_email limit 1;
  if v_target is null then
    raise exception 'No account found with this email. Ask your staff member to sign up in the app first, then add them here.';
  end if;

  select bm.business_id into v_existing_business
  from public.business_members bm
  where bm.user_id = v_target and bm.status = 'active'
  limit 1;

  if v_existing_business is not null then
    if v_existing_business = p_business_id then
      raise exception 'This person is already in your business.';
    end if;
    raise exception 'This person already belongs to another business.';
  end if;

  insert into public.business_members (business_id, user_id, role, status)
  values (p_business_id, v_target, 'staff', 'active');

  return jsonb_build_object('user_id', v_target, 'email', v_email, 'role', 'staff');
end;
$$;

create or replace function public.remove_staff_member(p_business_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_deleted int;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not public.is_business_manager(p_business_id) then
    raise exception 'Only the business owner can do this.';
  end if;
  if p_user_id = v_user then
    raise exception 'You cannot remove yourself.';
  end if;

  delete from public.business_members bm
  where bm.business_id = p_business_id
    and bm.user_id = p_user_id
    and bm.role = 'staff';
  get diagnostics v_deleted = row_count;

  if v_deleted = 0 then
    raise exception 'Staff member not found.';
  end if;
end;
$$;

revoke all on function public.get_my_role(uuid) from public, anon;
revoke all on function public.list_business_staff(uuid) from public, anon;
revoke all on function public.add_staff_member(uuid, text) from public, anon;
revoke all on function public.remove_staff_member(uuid, uuid) from public, anon;
grant execute on function public.get_my_role(uuid) to authenticated;
grant execute on function public.list_business_staff(uuid) to authenticated;
grant execute on function public.add_staff_member(uuid, text) to authenticated;
grant execute on function public.remove_staff_member(uuid, uuid) to authenticated;
