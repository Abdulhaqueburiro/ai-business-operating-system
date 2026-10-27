-- Migration 006: fix adjust_stock for stock-out.
-- Bug: INSERT ... ON CONFLICT checks the CHECK constraint (quantity >= 0) on the
-- proposed row BEFORE it resolves the conflict, so a negative change on an
-- existing stock row always failed with "Not enough stock".
-- Fix: lock the row, check the result, then UPDATE (or INSERT only for stock-in
-- when no row exists yet).
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
