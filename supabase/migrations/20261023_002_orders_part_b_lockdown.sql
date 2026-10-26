-- Migration 002 (Part B): lock client-side writes.
-- Apply ONLY after the app uses the RPCs (create_sales_order, confirm_sales_order,
-- cancel_sales_order, adjust_stock) and archives products instead of deleting them.
-- After this, orders, order items and stock can only change through those functions.
-- Rollback: recreate the dropped policies and re-grant insert/update/delete.

drop policy if exists "Members can create sales orders" on public.sales_orders;
drop policy if exists "Members can update sales orders" on public.sales_orders;
drop policy if exists "Members can add order items" on public.sales_order_items;
drop policy if exists "Members can update order items" on public.sales_order_items;
drop policy if exists "Members can delete order items" on public.sales_order_items;
drop policy if exists "Active members can add inventory" on public.inventory;
drop policy if exists "Active members can update inventory" on public.inventory;
drop policy if exists "Members can delete business products" on public.products;

revoke insert, update, delete, truncate
  on public.sales_orders, public.sales_order_items, public.inventory
  from anon, authenticated;

revoke delete, truncate on public.products from anon, authenticated;

-- Signed-out visitors get no access at all to business tables.
revoke all on public.sales_orders, public.sales_order_items,
              public.inventory, public.products, public.stock_movements
  from anon;
