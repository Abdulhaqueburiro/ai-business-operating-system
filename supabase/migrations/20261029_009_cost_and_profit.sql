-- Migration 009: cost price and profit.
-- products.cost_price (optional) is what the shop paid for one unit.
-- When an order is CONFIRMED, the cost in force at that moment is copied onto
-- each order item (sales_order_items.unit_cost), so later cost changes never
-- rewrite old profit. Items with no known cost are counted separately.

alter table public.products
  add column if not exists cost_price numeric(12,2)
  check (cost_price is null or cost_price >= 0);

alter table public.sales_order_items
  add column if not exists unit_cost numeric(12,2)
  check (unit_cost is null or unit_cost >= 0);

-- Confirm: same rules as before, plus lock the cost onto the items.
create or replace function public.confirm_sales_order(p_order_id uuid)
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
  v_stock numeric;
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

  select so.status into v_status
  from public.sales_orders so where so.id = p_order_id for update;

  if v_status <> 'pending' then
    raise exception 'Only pending orders can be confirmed.';
  end if;

  if not exists (select 1 from public.sales_order_items where order_id = p_order_id) then
    raise exception 'Add at least one product before confirming.';
  end if;

  for v_item in
    select oi.product_id, sum(oi.quantity) as quantity, max(p.name) as name
    from public.sales_order_items oi
    join public.products p on p.id = oi.product_id
    where oi.order_id = p_order_id
    group by oi.product_id
    order by oi.product_id
  loop
    select i.quantity into v_stock
    from public.inventory i
    where i.business_id = v_business_id and i.product_id = v_item.product_id
    for update;

    if not found then
      raise exception 'No stock record for "%".', v_item.name;
    end if;
    if v_stock < v_item.quantity then
      raise exception 'Insufficient stock for "%". Available: %, required: %.',
        v_item.name, v_stock, v_item.quantity;
    end if;

    update public.inventory
    set quantity = quantity - v_item.quantity, updated_at = now()
    where business_id = v_business_id and product_id = v_item.product_id;

    insert into public.stock_movements
      (business_id, product_id, movement_type, quantity_delta, reason,
       reference_type, reference_id, created_by)
    values
      (v_business_id, v_item.product_id, 'sale', -v_item.quantity, 'Order confirmed',
       'sales_order', p_order_id, v_user);
  end loop;

  -- Lock the cost in force right now onto each item (null if no cost is set).
  update public.sales_order_items oi
  set unit_cost = p.cost_price
  from public.products p
  where oi.order_id = p_order_id and p.id = oi.product_id;

  update public.sales_orders set status = 'confirmed', updated_at = now()
  where id = p_order_id;
end;
$$;

-- Dashboard: old keys unchanged; new keys for cost and profit.
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
    'items_missing_cost', v_missing
  );
end;
$$;

revoke all on function public.confirm_sales_order(uuid) from public, anon;
grant execute on function public.confirm_sales_order(uuid) to authenticated;
revoke all on function public.get_dashboard_summary(uuid) from public, anon;
grant execute on function public.get_dashboard_summary(uuid) to authenticated;
