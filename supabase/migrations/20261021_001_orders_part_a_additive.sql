-- Migration 001 (Part A): additive only. Does NOT remove any existing policy or
-- privilege, so the current Flutter app keeps working after this is applied.
-- Assumed rule: stock is deducted when an order is CONFIRMED.

-- 1. Product archive flag (instead of hard delete)
alter table public.products
  add column if not exists is_active boolean not null default true;

-- 2. Idempotency key for order creation (blocks duplicate submits)
alter table public.sales_orders
  add column if not exists idempotency_key uuid;

create unique index if not exists sales_orders_business_idem_key
  on public.sales_orders (business_id, idempotency_key)
  where idempotency_key is not null;

-- 3. Stock movement history
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  movement_type text not null check (movement_type in
    ('opening','sale','restock','adjustment','cancellation_restore')),
  quantity_delta numeric not null check (quantity_delta <> 0),
  reason text,
  reference_type text,
  reference_id uuid,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists stock_movements_product_idx
  on public.stock_movements (business_id, product_id, created_at desc);

alter table public.stock_movements enable row level security;

drop policy if exists "Members can view stock movements" on public.stock_movements;
create policy "Members can view stock movements"
  on public.stock_movements for select to authenticated
  using (public.is_active_business_member(business_id));

-- Clients may only read; all writes go through the functions below.
revoke all on public.stock_movements from anon, authenticated;
grant select on public.stock_movements to authenticated;

-- Opening balance so that sum(movements) = current inventory for existing data.
insert into public.stock_movements
  (business_id, product_id, movement_type, quantity_delta, reason)
select i.business_id, i.product_id, 'opening', i.quantity, 'Opening balance (migration)'
from public.inventory i
where i.quantity > 0
  and not exists (
    select 1 from public.stock_movements m
    where m.business_id = i.business_id and m.product_id = i.product_id
  );

-- 4. Atomic order creation. Prices and totals come from the database.
create or replace function public.create_sales_order(
  p_business_id uuid,
  p_items jsonb,
  p_customer_name text default null,
  p_notes text default null,
  p_idempotency_key uuid default null
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
      (business_id, customer_name, notes, created_by, status, total_amount, idempotency_key)
    values
      (p_business_id, nullif(trim(p_customer_name), ''), nullif(trim(p_notes), ''),
       v_user, 'pending', 0, p_idempotency_key)
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

-- 5. Confirm: membership first, deduct stock, write movements, all in one transaction.
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

  update public.sales_orders set status = 'confirmed', updated_at = now()
  where id = p_order_id;
end;
$$;

-- 6. Cancel: pending -> cancelled (no stock effect); confirmed -> cancelled + restore once.
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

-- 7. Manual stock adjustment with history (replaces direct inventory writes).
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

  begin
    insert into public.inventory (business_id, product_id, quantity)
    values (v_business_id, p_product_id, p_delta)
    on conflict (business_id, product_id)
    do update set quantity = public.inventory.quantity + p_delta, updated_at = now()
    returning quantity into v_new;
  exception when check_violation then
    raise exception 'Not enough stock to remove that quantity.';
  end;

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

-- 8. Function privileges: logged-in users only.
revoke all on function public.create_sales_order(uuid, jsonb, text, text, uuid) from public, anon;
revoke all on function public.confirm_sales_order(uuid) from public, anon;
revoke all on function public.cancel_sales_order(uuid) from public, anon;
revoke all on function public.adjust_stock(uuid, numeric, text) from public, anon;
grant execute on function public.create_sales_order(uuid, jsonb, text, text, uuid) to authenticated;
grant execute on function public.confirm_sales_order(uuid) to authenticated;
grant execute on function public.cancel_sales_order(uuid) to authenticated;
grant execute on function public.adjust_stock(uuid, numeric, text) to authenticated;
