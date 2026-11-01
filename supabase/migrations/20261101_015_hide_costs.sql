-- Migration 015: staff must not see cost prices, and only managers write products.
-- * products.cost_price and sales_order_items.unit_cost can no longer be read
--   straight from the tables by the app (column privileges). Anything that needs
--   them goes through a manager-only function.
-- * get_product_costs(business) gives managers the cost price of every product.
-- * Only owners and admins can add or change products.
-- IMPORTANT for later: when a new column is added to products or
-- sales_order_items, it must be granted again, for example:
--   grant select (new_column) on public.products to authenticated;

do $$
declare
  v_cols text;
begin
  select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position)
    into v_cols
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'products'
    and c.column_name <> 'cost_price';
  revoke select on public.products from authenticated;
  execute format('grant select (%s) on public.products to authenticated', v_cols);

  select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position)
    into v_cols
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'sales_order_items'
    and c.column_name <> 'unit_cost';
  revoke select on public.sales_order_items from authenticated;
  execute format('grant select (%s) on public.sales_order_items to authenticated', v_cols);
end
$$;

drop policy if exists "Members can add business products" on public.products;
drop policy if exists "Members can update business products" on public.products;
drop policy if exists "Managers can add business products" on public.products;
drop policy if exists "Managers can update business products" on public.products;

create policy "Managers can add business products"
  on public.products for insert to authenticated
  with check (public.is_business_manager(business_id));

create policy "Managers can update business products"
  on public.products for update to authenticated
  using (public.is_business_manager(business_id))
  with check (public.is_business_manager(business_id));

create or replace function public.get_product_costs(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not public.is_business_manager(p_business_id) then
    raise exception 'Only the business owner can do this.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'cost_price', p.cost_price))
    from public.products p
    where p.business_id = p_business_id and p.cost_price is not null
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_product_costs(uuid) from public, anon;
grant execute on function public.get_product_costs(uuid) to authenticated;
