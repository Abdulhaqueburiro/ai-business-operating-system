-- Migration 004: dashboard summary computed in the database.
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
    'low_stock_items', v_low_items
  );
end;
$$;

revoke all on function public.get_dashboard_summary(uuid) from public, anon;
grant execute on function public.get_dashboard_summary(uuid) to authenticated;
