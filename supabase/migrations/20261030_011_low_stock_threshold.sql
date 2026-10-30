-- Migration 011: low-stock alert level per product.
-- products.low_stock_threshold is optional. When empty the old rule (5) applies.
-- A product counts as "low" when its quantity is at or below its own level.
-- get_dashboard_summary uses it and lists the level for each low item.
-- The low-stock count now counts ALL low products (it used to stop at 10).

alter table public.products
  add column if not exists low_stock_threshold numeric(12,3)
  check (low_stock_threshold is null or low_stock_threshold >= 0);

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

revoke all on function public.get_dashboard_summary(uuid) from public, anon;
grant execute on function public.get_dashboard_summary(uuid) to authenticated;
