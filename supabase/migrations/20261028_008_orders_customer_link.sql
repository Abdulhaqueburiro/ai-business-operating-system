-- Migration 008: link orders to customers (step 3 of 3).
-- Adds sales_orders.customer_id (optional) and an optional customer id to
-- create_sales_order. The customer's name is copied onto the order at creation
-- time, so old orders keep their name even if the customer is edited or removed.
-- Calls without a customer id keep working exactly as before.

alter table public.sales_orders
  add column if not exists customer_id uuid
  references public.customers(id) on delete set null;

create index if not exists sales_orders_customer_idx
  on public.sales_orders (business_id, customer_id)
  where customer_id is not null;

-- Replace the 5-argument version with a 6-argument one (new optional argument last).
drop function if exists public.create_sales_order(uuid, jsonb, text, text, uuid);

create or replace function public.create_sales_order(
  p_business_id uuid,
  p_items jsonb,
  p_customer_name text default null,
  p_notes text default null,
  p_idempotency_key uuid default null,
  p_customer_id uuid default null
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
      (business_id, customer_id, customer_name, notes, created_by, status, total_amount, idempotency_key)
    values
      (p_business_id, p_customer_id,
       coalesce(v_customer_name, nullif(trim(p_customer_name), '')),
       nullif(trim(p_notes), ''),
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

revoke all on function public.create_sales_order(uuid, jsonb, text, text, uuid, uuid) from public, anon;
grant execute on function public.create_sales_order(uuid, jsonb, text, text, uuid, uuid) to authenticated;
