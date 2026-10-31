-- Migration 012: sales report for a date range (read only).
-- get_sales_report(business, from, to) returns one JSON document with totals,
-- sales per day, top products, top customers and expenses per category.
-- Only confirmed orders count as sales. Dates follow Pakistan time.
-- Range is limited to 366 days. Members of the business only.

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

revoke all on function public.get_sales_report(uuid, date, date) from public, anon;
grant execute on function public.get_sales_report(uuid, date, date) to authenticated;
