-- Backend self-check: orders, stock, expenses, dashboard, isolation.
-- Safe to run on the real database: everything happens inside one
-- transaction that is rolled back on purpose. The run ENDS with an error
-- that contains the test report. That error is expected.
begin;

create or replace function pg_temp.val_as(p_uid uuid, p_stmt text)
returns text language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then ''
         else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  execute case when p_uid is null then 'set local role anon'
               else 'set local role authenticated' end;
  begin
    execute p_stmt into v;
  exception when others then
    v := 'ERROR: ' || sqlerrm;
  end;
  execute 'reset role';
  return v;
end $f$;

create or replace function pg_temp.l(p_name text, p_ok boolean, p_detail text default null)
returns text language sql as $f$
  select case when coalesce(p_ok, false) then 'PASS  ' else 'FAIL  ' end
         || p_name || coalesce('  -> ' || p_detail, '') || E'\n';
$f$;

do $t$
declare
  ua uuid; ub uuid; ba uuid; bb uuid;
  pa uuid; pb uuid;
  o1 uuid; o2 uuid; e1 uuid; c1 uuid; c2 uuid; c3 uuid; cf uuid; o3 uuid; o4 uuid; o5 uuid; pc uuid; d1 jsonb; items_c text;
  v text; v2 text;
  aq text; aq2 text; rp0 jsonb; rp jsonb; rpp0 jsonb; rpp jsonb; orp uuid; erp uuid; dl0 jsonb; dl jsonb; cu uuid; ocr uuid; ocash uuid; pay1 uuid; pay2 uuid; dr0 jsonb; dr jsonb; led jsonb;
  d0 jsonb; d jsonb;
  items1 text; items10 text;
  k1 uuid := gen_random_uuid(); k2 uuid := gen_random_uuid(); k3 uuid := gen_random_uuid(); k4 uuid := gen_random_uuid();
  res text := '';
  err text := null;
begin
  begin
  -- ---------- setup (two different real users and businesses) ----------
  select user_id, business_id into ua, ba from public.business_members
   where status = 'active' order by user_id limit 1;
  select user_id, business_id into ub, bb from public.business_members
   where status = 'active' and user_id <> ua order by user_id limit 1;
  if ua is null or ub is null then
    raise exception 'Need two users with an active business to run these tests.';
  end if;

  d0 := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;

  insert into public.products (business_id, name, unit, price)
    values (ba, 'ZZ test soap', 'pcs', 100) returning id into pa;
  insert into public.products (business_id, name, unit, price)
    values (bb, 'ZZ other business item', 'pcs', 5) returning id into pb;
  insert into public.inventory (business_id, product_id, quantity) values (ba, pa, 5);
  -- Real data may already use the phone numbers this test uses; free them
  -- inside this transaction only (everything is rolled back at the end).
  update public.customers set archived_at = now()
   where archived_at is null
     and phone in ('0300-1234567', '0311-7654321', '0322-1111111', '0333-2222222');
  insert into public.stock_movements (business_id, product_id, movement_type, quantity_delta, reason)
    values (ba, pa, 'opening', 5, 'test opening');

  items1  := jsonb_build_array(jsonb_build_object('product_id', pa, 'quantity', 2))::text;
  items10 := jsonb_build_array(jsonb_build_object('product_id', pa, 'quantity', 10))::text;

  d := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('DASH: low stock counts the new 5-unit product',
    (d->>'low_stock_count')::int = (d0->>'low_stock_count')::int + 1);

  -- ---------- ORDERS: create ----------
  v := pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb, 'Test','n',%L)::text$q$, ba, items1, k1));
  res := res || pg_temp.l('ORDER: create succeeds', v not like 'ERROR%', v);
  o1 := v::uuid;
  res := res || pg_temp.l('ORDER: total is price x qty from DB (200) and status pending',
    (select total_amount = 200 and status = 'pending' from public.sales_orders where id = o1));

  v2 := pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb, 'Test','n',%L)::text$q$, ba, items1, k1));
  res := res || pg_temp.l('ORDER: same idempotency key returns same order', v2 = o1::text, v2);
  res := res || pg_temp.l('ORDER: no duplicate row created',
    (select count(*) = 1 from public.sales_orders where business_id = ba and idempotency_key = k1));

  res := res || pg_temp.l('ORDER: empty item list rejected',
    pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, '[]'::jsonb)::text$q$, ba)) like 'ERROR%');
  res := res || pg_temp.l('ORDER: quantity 0 rejected',
    pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb)::text$q$, ba,
      jsonb_build_array(jsonb_build_object('product_id', pa, 'quantity', 0))::text)) like 'ERROR%');
  res := res || pg_temp.l('ORDER: negative quantity rejected',
    pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb)::text$q$, ba,
      jsonb_build_array(jsonb_build_object('product_id', pa, 'quantity', -1))::text)) like 'ERROR%');
  res := res || pg_temp.l('ORDER: product of another business rejected',
    pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb)::text$q$, ba,
      jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1))::text)) like 'ERROR%');
  res := res || pg_temp.l('ORDER: non-member cannot create order in someone else''s business',
    pg_temp.val_as(ub, format($q$select public.create_sales_order(%L, %L::jsonb)::text$q$, ba, items1)) like '%not an active member%');

  res := res || pg_temp.l('ORDER: other user cannot confirm',
    pg_temp.val_as(ub, format($q$select 'ok' from (select public.confirm_sales_order(%L)) s$q$, o1)) like '%Order not found%');
  res := res || pg_temp.l('ORDER: other user cannot cancel',
    pg_temp.val_as(ub, format($q$select 'ok' from (select public.cancel_sales_order(%L)) s$q$, o1)) like '%Order not found%');

  -- ---------- ORDERS: stock rules ----------
  v := pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb, 'Big','n',%L)::text$q$, ba, items10, k2));
  o2 := v::uuid;
  res := res || pg_temp.l('ORDER: confirm with too little stock fails',
    pg_temp.val_as(ua, format($q$select 'ok' from (select public.confirm_sales_order(%L)) s$q$, o2)) like '%Insufficient stock%');
  res := res || pg_temp.l('ORDER: failed confirm leaves stock at 5 and order pending',
    (select i.quantity = 5 from public.inventory i where i.product_id = pa)
    and (select status = 'pending' from public.sales_orders where id = o2));

  d := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('DASH: pending count includes the 2 new orders',
    (d->>'pending_orders')::int = (d0->>'pending_orders')::int + 2);

  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.confirm_sales_order(%L)) s$q$, o1));
  res := res || pg_temp.l('ORDER: confirm succeeds', v = 'ok', v);
  res := res || pg_temp.l('ORDER: confirm deducts stock (5 -> 3)',
    (select quantity = 3 from public.inventory where product_id = pa));
  res := res || pg_temp.l('ORDER: confirm writes a sale movement of -2',
    (select count(*) = 1 from public.stock_movements
      where product_id = pa and movement_type = 'sale' and quantity_delta = -2 and reference_id = o1));
  res := res || pg_temp.l('ORDER: second confirm is rejected',
    pg_temp.val_as(ua, format($q$select 'ok' from (select public.confirm_sales_order(%L)) s$q$, o1)) like '%Only pending%');
  res := res || pg_temp.l('ORDER: second confirm does not deduct again (still 3)',
    (select quantity = 3 from public.inventory where product_id = pa));

  d := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('DASH: confirmed sales rose by exactly 200',
    (d->>'confirmed_sales')::numeric = (d0->>'confirmed_sales')::numeric + 200);
  res := res || pg_temp.l('DASH: confirmed order count rose by 1',
    (d->>'confirmed_orders')::int = (d0->>'confirmed_orders')::int + 1);
  res := res || pg_temp.l('DASH: pending fell by 1 after confirm',
    (d->>'pending_orders')::int = (d0->>'pending_orders')::int + 1);

  -- ---------- ORDERS: cancel ----------
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.cancel_sales_order(%L)) s$q$, o1));
  res := res || pg_temp.l('ORDER: cancel confirmed order succeeds', v = 'ok', v);
  res := res || pg_temp.l('ORDER: cancel restores stock (3 -> 5)',
    (select quantity = 5 from public.inventory where product_id = pa));
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.cancel_sales_order(%L)) s$q$, o1));
  res := res || pg_temp.l('ORDER: cancelling twice is harmless', v = 'ok', v);
  res := res || pg_temp.l('ORDER: stock restored only once (still 5, one restore movement)',
    (select quantity = 5 from public.inventory where product_id = pa)
    and (select count(*) = 1 from public.stock_movements
          where product_id = pa and movement_type = 'cancellation_restore' and reference_id = o1));
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.cancel_sales_order(%L)) s$q$, o2));
  res := res || pg_temp.l('ORDER: cancel pending order succeeds', v = 'ok', v);
  res := res || pg_temp.l('ORDER: cancelling a pending order does not change stock',
    (select quantity = 5 from public.inventory where product_id = pa));

  d := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('DASH: after cancels, sales and pending are back to start',
    (d->>'confirmed_sales')::numeric = (d0->>'confirmed_sales')::numeric
    and (d->>'pending_orders')::int = (d0->>'pending_orders')::int);

  -- ---------- STOCK adjust ----------
  res := res || pg_temp.l('STOCK: removing more than available is rejected',
    pg_temp.val_as(ua, format('select public.adjust_stock(%L, -100, %L)::text', pa, 'x')) like '%Not enough stock%');
  res := res || pg_temp.l('STOCK: stock in +10 gives 15',
    pg_temp.val_as(ua, format('select public.adjust_stock(%L, 10, %L)::text', pa, 'restock'))::numeric = 15);
  d := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('DASH: product no longer low at 15',
    (d->>'low_stock_count')::int = (d0->>'low_stock_count')::int);
  res := res || pg_temp.l('STOCK: other business user cannot adjust',
    pg_temp.val_as(ub, format('select public.adjust_stock(%L, 1, %L)::text', pa, 'x')) like '%Product not found%');
  res := res || pg_temp.l('STOCK: stock out -10 gives 5',
    pg_temp.val_as(ua, format('select public.adjust_stock(%L, -10, %L)::text', pa, 'sold'))::numeric = 5);
  res := res || pg_temp.l('STOCK: zero change rejected',
    pg_temp.val_as(ua, format('select public.adjust_stock(%L, 0, %L)::text', pa, 'x')) like 'ERROR%');
  res := res || pg_temp.l('STOCK: history adds up to current inventory (difference 0)',
    (select i.quantity - coalesce((select sum(m.quantity_delta) from public.stock_movements m
        where m.product_id = i.product_id and m.business_id = i.business_id), 0) = 0
     from public.inventory i where i.product_id = pa));

  -- ---------- EXPENSES ----------
  v := pg_temp.val_as(ua, format($q$select public.create_expense(%L, 'Rent', 150.5, current_date, 'test', %L)::text$q$, ba, k3));
  res := res || pg_temp.l('EXPENSE: create succeeds', v not like 'ERROR%', v);
  e1 := v::uuid;
  res := res || pg_temp.l('EXPENSE: same idempotency key returns same expense',
    pg_temp.val_as(ua, format($q$select public.create_expense(%L, 'Rent', 150.5, current_date, 'test', %L)::text$q$, ba, k3)) = e1::text);
  res := res || pg_temp.l('EXPENSE: saved once with amount 150.50',
    (select count(*) = 1 and max(amount) = 150.50 from public.expenses where business_id = ba and idempotency_key = k3));
  res := res || pg_temp.l('EXPENSE: amount 0 rejected',
    pg_temp.val_as(ua, format($q$select public.create_expense(%L, 'Rent', 0, current_date)::text$q$, ba)) like '%greater than zero%');
  res := res || pg_temp.l('EXPENSE: negative amount rejected',
    pg_temp.val_as(ua, format($q$select public.create_expense(%L, 'Rent', -5, current_date)::text$q$, ba)) like 'ERROR%');
  res := res || pg_temp.l('EXPENSE: unknown category rejected',
    pg_temp.val_as(ua, format($q$select public.create_expense(%L, 'Bogus', 5, current_date)::text$q$, ba)) like '%valid category%');
  res := res || pg_temp.l('EXPENSE: future date rejected',
    pg_temp.val_as(ua, format($q$select public.create_expense(%L, 'Rent', 5, current_date + 10)::text$q$, ba)) like '%future%');
  res := res || pg_temp.l('EXPENSE: missing date rejected',
    pg_temp.val_as(ua, format($q$select public.create_expense(%L, 'Rent', 5, null)::text$q$, ba)) like 'ERROR%');
  res := res || pg_temp.l('EXPENSE: other business user cannot create in this business',
    pg_temp.val_as(ub, format($q$select public.create_expense(%L, 'Rent', 5, current_date)::text$q$, ba)) like '%not an active member%');
  res := res || pg_temp.l('EXPENSE: other business user cannot archive it',
    pg_temp.val_as(ub, format($q$select 'ok' from (select public.archive_expense(%L)) s$q$, e1)) like '%Expense not found%');

  d := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('DASH: expenses rose by exactly 150.50 and net fell by 150.50',
    (d->>'expenses')::numeric = (d0->>'expenses')::numeric + 150.5
    and (d->>'net')::numeric = (d0->>'net')::numeric - 150.5);

  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.archive_expense(%L)) s$q$, e1));
  res := res || pg_temp.l('EXPENSE: archive succeeds', v = 'ok', v);
  res := res || pg_temp.l('EXPENSE: archived expense is marked archived, not deleted',
    (select archived_at is not null from public.expenses where id = e1));
  d := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('DASH: archived expense no longer counted',
    (d->>'expenses')::numeric = (d0->>'expenses')::numeric);

  -- ---------- DASHBOARD access ----------
  res := res || pg_temp.l('DASH: other business user cannot read this dashboard',
    pg_temp.val_as(ub, format('select public.get_dashboard_summary(%L)::text', ba)) like '%not an active member%');
  res := res || pg_temp.l('DASH: signed-out user cannot call it',
    pg_temp.val_as(null, format('select public.get_dashboard_summary(%L)::text', ba)) like 'ERROR%');

  -- ---------- LOCKDOWN: direct writes ----------
  res := res || pg_temp.l('LOCK: client cannot update sales_orders',
    pg_temp.val_as(ua, format($q$update public.sales_orders set status = 'confirmed' where id = %L returning 'x'$q$, o2)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('LOCK: client cannot insert sales_orders',
    pg_temp.val_as(ua, format($q$insert into public.sales_orders(business_id, status, total_amount) values (%L, 'confirmed', 1) returning 'x'$q$, ba)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('LOCK: client cannot change order item prices',
    pg_temp.val_as(ua, format($q$update public.sales_order_items set unit_price = 0 where order_id = %L returning 'x'$q$, o1)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('LOCK: client cannot delete order items',
    pg_temp.val_as(ua, format($q$delete from public.sales_order_items where order_id = %L returning 'x'$q$, o1)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('LOCK: client cannot update inventory',
    pg_temp.val_as(ua, format($q$update public.inventory set quantity = 999 where product_id = %L returning 'x'$q$, pa)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('LOCK: client cannot insert inventory',
    pg_temp.val_as(ua, format($q$insert into public.inventory(business_id, product_id, quantity) values (%L, %L, 1) returning 'x'$q$, ba, pb)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('LOCK: client cannot delete products',
    pg_temp.val_as(ua, format($q$delete from public.products where id = %L returning 'x'$q$, pa)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('LOCK: client cannot write stock history',
    pg_temp.val_as(ua, format($q$insert into public.stock_movements(business_id, product_id, movement_type, quantity_delta) values (%L, %L, 'adjustment', 1) returning 'x'$q$, ba, pa)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('LOCK: client cannot insert expenses directly',
    pg_temp.val_as(ua, format($q$insert into public.expenses(business_id, category, amount, expense_date) values (%L, 'Rent', 1, current_date) returning 'x'$q$, ba)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('LOCK: client cannot update expenses directly',
    pg_temp.val_as(ua, format($q$update public.expenses set amount = 1 where id = %L returning 'x'$q$, e1)) like 'ERROR: permission denied%');

  -- ---------- signed-out access ----------
  res := res || pg_temp.l('ANON: cannot confirm orders',
    pg_temp.val_as(null, format($q$select 'ok' from (select public.confirm_sales_order(%L)) s$q$, o1)) like 'ERROR%');
  res := res || pg_temp.l('ANON: cannot create expenses',
    pg_temp.val_as(null, format($q$select public.create_expense(%L, 'Rent', 5, current_date)::text$q$, ba)) like 'ERROR%');
  res := res || pg_temp.l('ANON: cannot read orders',
    pg_temp.val_as(null, 'select count(*)::text from public.sales_orders') like 'ERROR%');
  res := res || pg_temp.l('ANON: cannot read expenses',
    pg_temp.val_as(null, 'select count(*)::text from public.expenses') like 'ERROR%');

  -- ---------- ISOLATION: the other business sees nothing ----------
  res := res || pg_temp.l('ISOLATION: other user sees none of these orders',
    pg_temp.val_as(ub, format($q$select count(*)::text from public.sales_orders where business_id = %L$q$, ba)) = '0');
  res := res || pg_temp.l('ISOLATION: other user sees none of these products',
    pg_temp.val_as(ub, format($q$select count(*)::text from public.products where business_id = %L$q$, ba)) = '0');
  res := res || pg_temp.l('ISOLATION: other user sees none of this stock',
    pg_temp.val_as(ub, format($q$select count(*)::text from public.inventory where business_id = %L$q$, ba)) = '0');
  res := res || pg_temp.l('ISOLATION: other user sees none of this stock history',
    pg_temp.val_as(ub, format($q$select count(*)::text from public.stock_movements where business_id = %L$q$, ba)) = '0');
  res := res || pg_temp.l('ISOLATION: other user sees none of these expenses',
    pg_temp.val_as(ub, format($q$select count(*)::text from public.expenses where business_id = %L$q$, ba)) = '0');
  res := res || pg_temp.l('ISOLATION: owner does see own expense and order',
    pg_temp.val_as(ua, format($q$select count(*)::text from public.expenses where id = %L$q$, e1)) = '1'
    and pg_temp.val_as(ua, format($q$select count(*)::text from public.sales_orders where id = %L$q$, o1)) = '1');

  -- ---------- CUSTOMERS ----------
  v := pg_temp.val_as(ua, format($q$select public.create_customer(%L, 'ZZ Ali', '0300-1234567', 'note', %L)::text$q$, ba, k4));
  res := res || pg_temp.l('CUSTOMER: create succeeds', v not like 'ERROR%', v);
  c1 := v::uuid;
  res := res || pg_temp.l('CUSTOMER: same idempotency key returns same customer',
    pg_temp.val_as(ua, format($q$select public.create_customer(%L, 'ZZ Ali', '0300-1234567', 'note', %L)::text$q$, ba, k4)) = c1::text);
  res := res || pg_temp.l('CUSTOMER: saved once',
    (select count(*) = 1 from public.customers where business_id = ba and idempotency_key = k4));
  res := res || pg_temp.l('CUSTOMER: empty name rejected',
    pg_temp.val_as(ua, format($q$select public.create_customer(%L, '   ')::text$q$, ba)) like '%between 1 and 120%');
  res := res || pg_temp.l('CUSTOMER: name over 120 characters rejected',
    pg_temp.val_as(ua, format($q$select public.create_customer(%L, repeat('x', 121))::text$q$, ba)) like '%between 1 and 120%');
  res := res || pg_temp.l('CUSTOMER: invalid phone rejected',
    pg_temp.val_as(ua, format($q$select public.create_customer(%L, 'ZZ Bad', 'abc')::text$q$, ba)) like '%valid phone%');
  res := res || pg_temp.l('CUSTOMER: duplicate phone in same business rejected',
    pg_temp.val_as(ua, format($q$select public.create_customer(%L, 'ZZ Other', '0300-1234567')::text$q$, ba)) like '%already exists%');
  res := res || pg_temp.l('CUSTOMER: same phone allowed in a different business',
    pg_temp.val_as(ub, format($q$select public.create_customer(%L, 'ZZ Same phone', '0300-1234567')::text$q$, bb)) not like 'ERROR%');
  res := res || pg_temp.l('CUSTOMER: other business user cannot create here',
    pg_temp.val_as(ub, format($q$select public.create_customer(%L, 'ZZ Intruder')::text$q$, ba)) like '%not an active member%');

  v := pg_temp.val_as(ua, format($q$select public.create_customer(%L, 'ZZ Sara', '0311-7654321')::text$q$, ba));
  c2 := v::uuid;
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.update_customer(%L, 'ZZ Ali Khan', '0300-1234567', 'vip')) s$q$, c1));
  res := res || pg_temp.l('CUSTOMER: update succeeds', v = 'ok', v);
  res := res || pg_temp.l('CUSTOMER: update changed the saved name and notes',
    (select name = 'ZZ Ali Khan' and notes = 'vip' from public.customers where id = c1));
  res := res || pg_temp.l('CUSTOMER: cannot update to another customer''s phone',
    pg_temp.val_as(ua, format($q$select 'ok' from (select public.update_customer(%L, 'ZZ Sara', '0300-1234567')) s$q$, c2)) like '%already exists%');
  res := res || pg_temp.l('CUSTOMER: other business user cannot update',
    pg_temp.val_as(ub, format($q$select 'ok' from (select public.update_customer(%L, 'Hacked')) s$q$, c1)) like '%Customer not found%');
  res := res || pg_temp.l('CUSTOMER: other business user cannot archive',
    pg_temp.val_as(ub, format($q$select 'ok' from (select public.archive_customer(%L)) s$q$, c1)) like '%Customer not found%');

  res := res || pg_temp.l('CUSTOMER: other business user sees none of these customers',
    pg_temp.val_as(ub, format($q$select count(*)::text from public.customers where business_id = %L$q$, ba)) = '0');
  res := res || pg_temp.l('CUSTOMER: owner sees own customers',
    pg_temp.val_as(ua, format($q$select count(*)::text from public.customers where id = %L$q$, c1)) = '1');
  res := res || pg_temp.l('CUSTOMER: client cannot insert directly',
    pg_temp.val_as(ua, format($q$insert into public.customers(business_id, name) values (%L, 'x') returning 'x'$q$, ba)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('CUSTOMER: client cannot update directly',
    pg_temp.val_as(ua, format($q$update public.customers set name = 'x' where id = %L returning 'x'$q$, c1)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('CUSTOMER: client cannot delete directly',
    pg_temp.val_as(ua, format($q$delete from public.customers where id = %L returning 'x'$q$, c1)) like 'ERROR: permission denied%');
  res := res || pg_temp.l('CUSTOMER: signed-out user cannot read or create',
    pg_temp.val_as(null, 'select count(*)::text from public.customers') like 'ERROR%'
    and pg_temp.val_as(null, format($q$select public.create_customer(%L, 'x')::text$q$, ba)) like 'ERROR%');

  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.archive_customer(%L)) s$q$, c1));
  res := res || pg_temp.l('CUSTOMER: archive succeeds', v = 'ok', v);
  res := res || pg_temp.l('CUSTOMER: archived customer is kept, marked archived',
    (select archived_at is not null from public.customers where id = c1));
  v := pg_temp.val_as(ua, format($q$select public.create_customer(%L, 'ZZ New owner of number', '0300-1234567')::text$q$, ba));
  res := res || pg_temp.l('CUSTOMER: phone of an archived customer can be reused', v not like 'ERROR%', v);

  -- ---------- ORDERS LINKED TO CUSTOMERS ----------
  v := pg_temp.val_as(ua, format($q$select public.create_customer(%L, 'ZZ Buyer', '0322-1111111')::text$q$, ba));
  c3 := v::uuid;
  v := pg_temp.val_as(ub, format($q$select public.create_customer(%L, 'ZZ Foreign', '0333-2222222')::text$q$, bb));
  cf := v::uuid;
  v := pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb, 'Typed name', 'n', %L, %L)::text$q$, ba, items1, gen_random_uuid(), c3));
  res := res || pg_temp.l('LINK: order with a saved customer succeeds', v not like 'ERROR%', v);
  o3 := v::uuid;
  res := res || pg_temp.l('LINK: order stores the customer id',
    (select customer_id = c3 from public.sales_orders where id = o3));
  res := res || pg_temp.l('LINK: server copies the saved name (typed name is ignored)',
    (select customer_name = 'ZZ Buyer' from public.sales_orders where id = o3));
  res := res || pg_temp.l('LINK: customer of another business rejected',
    pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb, null, null, null, %L)::text$q$, ba, items1, cf)) like '%Customer not found%');
  res := res || pg_temp.l('LINK: archived customer rejected',
    pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb, null, null, null, %L)::text$q$, ba, items1, c1)) like '%Customer not found%');
  v := pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb, 'Walk-in Ahmed')::text$q$, ba, items1));
  res := res || pg_temp.l('LINK: order without a customer id still works', v not like 'ERROR%', v);
  res := res || pg_temp.l('LINK: typed name is kept when no customer is chosen',
    (select count(*) = 1 from public.sales_orders where business_id = ba and customer_name = 'Walk-in Ahmed' and customer_id is null));
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.archive_customer(%L)) s$q$, c3));
  res := res || pg_temp.l('LINK: archive of the buyer succeeds', v = 'ok', v);
  res := res || pg_temp.l('LINK: archiving the customer keeps the order''s name and link',
    (select customer_name = 'ZZ Buyer' and customer_id = c3 from public.sales_orders where id = o3));
  res := res || pg_temp.l('LINK: signed-out user cannot call the 6-argument create_sales_order',
    pg_temp.val_as(null, format($q$select public.create_sales_order(%L, %L::jsonb, null, null, null, %L)::text$q$, ba, items1, c3)) like 'ERROR%');

  -- ---------- COST AND PROFIT ----------
  insert into public.products (business_id, name, unit, price)
    values (ba, 'ZZ no cost item', 'pcs', 50) returning id into pc;
  insert into public.inventory (business_id, product_id, quantity) values (ba, pc, 5);
  insert into public.stock_movements (business_id, product_id, movement_type, quantity_delta, reason)
    values (ba, pc, 'opening', 5, 'test opening');
  items_c := jsonb_build_array(jsonb_build_object('product_id', pc, 'quantity', 1))::text;

  res := res || pg_temp.l('COST: owner can set a cost price',
    pg_temp.val_as(ua, format($q$update public.products set cost_price = 60 where id = %L returning 'x'$q$, pa)) = 'x');
  res := res || pg_temp.l('COST: negative cost price rejected',
    pg_temp.val_as(ua, format($q$update public.products set cost_price = -1 where id = %L returning 'x'$q$, pa)) like 'ERROR%');
  res := res || pg_temp.l('COST: other business user cannot change the cost',
    pg_temp.val_as(ub, format($q$update public.products set cost_price = 1 where id = %L returning 'x'$q$, pa)) is null);
  res := res || pg_temp.l('COST: cost price stayed 60',
    (select cost_price = 60 from public.products where id = pa));

  d1 := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  v := pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb)::text$q$, ba, items1));
  o4 := v::uuid;
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.confirm_sales_order(%L)) s$q$, o4));
  res := res || pg_temp.l('COST: confirm of an order with a known cost succeeds', v = 'ok', v);
  res := res || pg_temp.l('COST: confirm locks the cost (60) onto the items',
    (select bool_and(unit_cost = 60) from public.sales_order_items where order_id = o4));
  d := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('PROFIT: cost of goods rose by 120 (2 x 60)',
    (d->>'cost_of_goods')::numeric = (d1->>'cost_of_goods')::numeric + 120);
  res := res || pg_temp.l('PROFIT: gross profit rose by 80 (200 - 120)',
    (d->>'gross_profit')::numeric = (d1->>'gross_profit')::numeric + 80);
  res := res || pg_temp.l('PROFIT: net profit rose by 80 and old net unchanged formula',
    (d->>'net_profit')::numeric = (d1->>'net_profit')::numeric + 80
    and (d->>'net')::numeric = (d1->>'net')::numeric + 200);
  res := res || pg_temp.l('PROFIT: no item is missing a cost yet',
    (d->>'items_missing_cost')::int = (d1->>'items_missing_cost')::int);

  res := res || pg_temp.l('COST: changing the cost later works',
    pg_temp.val_as(ua, format($q$update public.products set cost_price = 70 where id = %L returning 'x'$q$, pa)) = 'x');
  res := res || pg_temp.l('COST: old order keeps the locked cost (still 60)',
    (select bool_and(unit_cost = 60) from public.sales_order_items where order_id = o4));

  v := pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb)::text$q$, ba, items_c));
  o5 := v::uuid;
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.confirm_sales_order(%L)) s$q$, o5));
  res := res || pg_temp.l('COST: confirm of an order with no cost succeeds', v = 'ok', v);
  res := res || pg_temp.l('COST: item with no cost stays unknown (null)',
    (select bool_and(unit_cost is null) from public.sales_order_items where order_id = o5));
  d := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('PROFIT: sales rose by 250 but cost and gross profit ignore the unknown item',
    (d->>'confirmed_sales')::numeric = (d1->>'confirmed_sales')::numeric + 250
    and (d->>'cost_of_goods')::numeric = (d1->>'cost_of_goods')::numeric + 120
    and (d->>'gross_profit')::numeric = (d1->>'gross_profit')::numeric + 80);
  res := res || pg_temp.l('PROFIT: dashboard counts 1 item with missing cost',
    (d->>'items_missing_cost')::int = (d1->>'items_missing_cost')::int + 1);

  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.cancel_sales_order(%L)) s$q$, o4));
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.cancel_sales_order(%L)) s$q$, o5));
  d := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('PROFIT: after cancelling both, profit numbers are back to start',
    (d->>'cost_of_goods')::numeric = (d1->>'cost_of_goods')::numeric
    and (d->>'gross_profit')::numeric = (d1->>'gross_profit')::numeric
    and (d->>'items_missing_cost')::int = (d1->>'items_missing_cost')::int);
  -- ---------- LOW-STOCK LEVEL PER PRODUCT ----------
  dl0 := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  v := pg_temp.val_as(ua, format($q$update public.products set low_stock_threshold = 2 where id = %L returning 'x'$q$, pa));
  res := res || pg_temp.l('LOWSTOCK: owner can set a level of 2', v = 'x', v);
  dl := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('LOWSTOCK: product with 5 left and level 2 is no longer low',
    (dl->>'low_stock_count')::int = (dl0->>'low_stock_count')::int - 1);
  v := pg_temp.val_as(ua, format($q$update public.products set low_stock_threshold = 5 where id = %L returning 'x'$q$, pa));
  dl := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('LOWSTOCK: level 5 with 5 left counts as low (at or below)',
    (dl->>'low_stock_count')::int = (dl0->>'low_stock_count')::int);
  v := pg_temp.val_as(ua, format($q$update public.products set low_stock_threshold = 100 where id = %L returning 'x'$q$, pa));
  dl := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('LOWSTOCK: a high level keeps the product low',
    (dl->>'low_stock_count')::int = (dl0->>'low_stock_count')::int);
  v := pg_temp.val_as(ua, format($q$update public.products set low_stock_threshold = 0 where id = %L returning 'x'$q$, pa));
  dl := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('LOWSTOCK: level 0 means only an empty product is low',
    (dl->>'low_stock_count')::int = (dl0->>'low_stock_count')::int - 1);
  v := pg_temp.val_as(ua, format($q$update public.products set low_stock_threshold = null where id = %L returning 'x'$q$, pa));
  dl := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('LOWSTOCK: no level falls back to the old rule (5)',
    (dl->>'low_stock_count')::int = (dl0->>'low_stock_count')::int);
  res := res || pg_temp.l('LOWSTOCK: negative level rejected',
    pg_temp.val_as(ua, format($q$update public.products set low_stock_threshold = -1 where id = %L returning 'x'$q$, pa)) like 'ERROR%');
  res := res || pg_temp.l('LOWSTOCK: other business user cannot change the level',
    pg_temp.val_as(ub, format($q$update public.products set low_stock_threshold = 1 where id = %L returning 'x'$q$, pa)) is null);

  dl0 := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  with np as (
    insert into public.products (business_id, name, unit, price)
    select ba, 'ZZ low ' || g, 'pcs', 1 from generate_series(1, 11) g returning id
  )
  insert into public.inventory (business_id, product_id, quantity) select ba, id, 0 from np;
  dl := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('LOWSTOCK: count is not capped at 10 (11 new empty products)',
    (dl->>'low_stock_count')::int = (dl0->>'low_stock_count')::int + 11,
    (dl->>'low_stock_count') || ' vs ' || (dl0->>'low_stock_count'));
  res := res || pg_temp.l('LOWSTOCK: the list still shows at most 10 items',
    jsonb_array_length(dl->'low_stock_items') = 10);

  -- ---------- UDHAAR (credit sales and payments) ----------
  v := pg_temp.val_as(ua, format($q$select public.create_customer(%L, 'ZZ Udhaar Buyer')::text$q$, ba));
  res := res || pg_temp.l('UDHAAR: create the test customer', v not like 'ERROR%', v);
  cu := v::uuid;
  dr0 := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;

  res := res || pg_temp.l('UDHAAR: credit sale without a saved customer is rejected',
    pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb, 'Typed', null, null, null, true)::text$q$, ba, items1)) like '%needs a saved customer%');
  v := pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb, null, null, null, %L, true)::text$q$, ba, items1, cu));
  res := res || pg_temp.l('UDHAAR: credit sale with a saved customer succeeds', v not like 'ERROR%', v);
  ocr := v::uuid;
  res := res || pg_temp.l('UDHAAR: order is flagged on_credit',
    (select on_credit from public.sales_orders where id = ocr));
  v := pg_temp.val_as(ua, format($q$select balance::text from public.get_customer_balances(%L) where customer_id = %L$q$, ba, cu));
  res := res || pg_temp.l('UDHAAR: a pending credit order does not count yet', v is null or v::numeric = 0, v);

  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.confirm_sales_order(%L)) s$q$, ocr));
  res := res || pg_temp.l('UDHAAR: confirm credit order succeeds', v = 'ok', v);
  v := pg_temp.val_as(ua, format($q$select balance::text from public.get_customer_balances(%L) where customer_id = %L$q$, ba, cu));
  res := res || pg_temp.l('UDHAAR: balance is 200 after confirm', v::numeric = 200, v);
  dr := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('UDHAAR: dashboard receivable rose by 200',
    (dr->>'receivable')::numeric = (dr0->>'receivable')::numeric + 200);

  v := pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb, null, null, null, %L)::text$q$, ba, items1, cu));
  ocash := v::uuid;
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.confirm_sales_order(%L)) s$q$, ocash));
  v := pg_temp.val_as(ua, format($q$select balance::text from public.get_customer_balances(%L) where customer_id = %L$q$, ba, cu));
  res := res || pg_temp.l('UDHAAR: a cash sale to the same customer does not add udhaar', v::numeric = 200, v);

  v := pg_temp.val_as(ua, format($q$select public.record_customer_payment(%L, %L, 80, null, 'first part', %L)::text$q$, ba, cu, k4));
  res := res || pg_temp.l('UDHAAR: payment of 80 succeeds', v not like 'ERROR%', v);
  pay1 := v::uuid;
  v2 := pg_temp.val_as(ua, format($q$select public.record_customer_payment(%L, %L, 80, null, 'first part', %L)::text$q$, ba, cu, k4));
  res := res || pg_temp.l('UDHAAR: same idempotency key returns same payment', v2 = pay1::text, v2);
  res := res || pg_temp.l('UDHAAR: payment saved once',
    (select count(*) = 1 from public.customer_payments where business_id = ba and idempotency_key = k4));
  v := pg_temp.val_as(ua, format($q$select balance::text from public.get_customer_balances(%L) where customer_id = %L$q$, ba, cu));
  res := res || pg_temp.l('UDHAAR: balance is 120 after paying 80', v::numeric = 120, v);

  led := pg_temp.val_as(ua, format('select public.get_customer_ledger(%L, %L)::text', ba, cu))::jsonb;
  res := res || pg_temp.l('UDHAAR: ledger shows credit 200, paid 80, balance 120',
    (led->>'credit_total')::numeric = 200 and (led->>'paid_total')::numeric = 80 and (led->>'balance')::numeric = 120);
  res := res || pg_temp.l('UDHAAR: ledger lists the sale and the payment',
    jsonb_array_length(led->'entries') = 2);

  res := res || pg_temp.l('UDHAAR: amount 0 rejected',
    pg_temp.val_as(ua, format($q$select public.record_customer_payment(%L, %L, 0)::text$q$, ba, cu)) like '%greater than zero%');
  res := res || pg_temp.l('UDHAAR: negative amount rejected',
    pg_temp.val_as(ua, format($q$select public.record_customer_payment(%L, %L, -5)::text$q$, ba, cu)) like '%greater than zero%');
  res := res || pg_temp.l('UDHAAR: payment above the balance rejected',
    pg_temp.val_as(ua, format($q$select public.record_customer_payment(%L, %L, 120.01)::text$q$, ba, cu)) like '%more than the customer owes%');
  res := res || pg_temp.l('UDHAAR: future date rejected',
    pg_temp.val_as(ua, format($q$select public.record_customer_payment(%L, %L, 10, current_date + 5)::text$q$, ba, cu)) like '%future%');
  res := res || pg_temp.l('UDHAAR: customer of another business rejected',
    pg_temp.val_as(ua, format($q$select public.record_customer_payment(%L, %L, 10)::text$q$, ba, cf)) like '%Customer not found%');
  res := res || pg_temp.l('UDHAAR: other business user cannot record a payment here',
    pg_temp.val_as(ub, format($q$select public.record_customer_payment(%L, %L, 10)::text$q$, ba, cu)) like '%not an active member%');
  res := res || pg_temp.l('UDHAAR: other business user cannot read balances',
    pg_temp.val_as(ub, format($q$select count(*)::text from public.get_customer_balances(%L)$q$, ba)) like 'ERROR%');
  res := res || pg_temp.l('UDHAAR: other business user cannot read the ledger',
    pg_temp.val_as(ub, format($q$select public.get_customer_ledger(%L, %L)::text$q$, ba, cu)) like 'ERROR%');
  res := res || pg_temp.l('UDHAAR: other business user sees no payments',
    pg_temp.val_as(ub, format($q$select count(*)::text from public.customer_payments where customer_id = %L$q$, cu)) = '0');
  res := res || pg_temp.l('UDHAAR: client cannot insert a payment directly',
    pg_temp.val_as(ua, format($q$insert into public.customer_payments (business_id, customer_id, amount, paid_on) values (%L, %L, 1, current_date) returning 'x'$q$, ba, cu)) like 'ERROR%');
  res := res || pg_temp.l('UDHAAR: client cannot update a payment directly',
    pg_temp.val_as(ua, format($q$update public.customer_payments set amount = 1 where id = %L returning 'x'$q$, pay1)) like 'ERROR%');
  res := res || pg_temp.l('UDHAAR: client cannot delete a payment directly',
    pg_temp.val_as(ua, format($q$delete from public.customer_payments where id = %L returning 'x'$q$, pay1)) like 'ERROR%');
  res := res || pg_temp.l('UDHAAR: signed-out user cannot record a payment',
    pg_temp.val_as(null, format($q$select public.record_customer_payment(%L, %L, 10)::text$q$, ba, cu)) like 'ERROR%');
  res := res || pg_temp.l('UDHAAR: signed-out user cannot read balances',
    pg_temp.val_as(null, format($q$select count(*)::text from public.get_customer_balances(%L)$q$, ba)) like 'ERROR%');

  res := res || pg_temp.l('UDHAAR: other business user cannot void a payment',
    pg_temp.val_as(ub, format($q$select public.void_customer_payment(%L)$q$, pay1)) like '%not an active member%');
  v := pg_temp.val_as(ua, format($q$select public.void_customer_payment(%L)$q$, pay1));
  res := res || pg_temp.l('UDHAAR: owner can void the payment', v = 'ok', v);
  v2 := pg_temp.val_as(ua, format($q$select public.void_customer_payment(%L)$q$, pay1));
  res := res || pg_temp.l('UDHAAR: voiding twice is harmless', v2 = 'ok', v2);
  res := res || pg_temp.l('UDHAAR: voided payment is kept, not deleted',
    (select voided_at is not null from public.customer_payments where id = pay1));
  v := pg_temp.val_as(ua, format($q$select balance::text from public.get_customer_balances(%L) where customer_id = %L$q$, ba, cu));
  res := res || pg_temp.l('UDHAAR: balance is back to 200 after voiding', v::numeric = 200, v);
  dr := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('UDHAAR: dashboard receivable is again +200',
    (dr->>'receivable')::numeric = (dr0->>'receivable')::numeric + 200);

  v := pg_temp.val_as(ua, format($q$select public.record_customer_payment(%L, %L, 200, null, 'full')::text$q$, ba, cu));
  res := res || pg_temp.l('UDHAAR: paying the full 200 succeeds', v not like 'ERROR%', v);
  pay2 := v::uuid;
  dr := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('UDHAAR: receivable back to start when fully paid',
    (dr->>'receivable')::numeric = (dr0->>'receivable')::numeric);
  res := res || pg_temp.l('UDHAAR: nothing more can be paid once settled',
    pg_temp.val_as(ua, format($q$select public.record_customer_payment(%L, %L, 1)::text$q$, ba, cu)) like '%more than the customer owes%');

  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.cancel_sales_order(%L)) s$q$, ocr));
  res := res || pg_temp.l('UDHAAR: cancel of the credit order succeeds', v = 'ok', v);
  v := pg_temp.val_as(ua, format($q$select balance::text from public.get_customer_balances(%L) where customer_id = %L$q$, ba, cu));
  res := res || pg_temp.l('UDHAAR: cancelled credit order leaves the customer ahead by 200 (balance -200)', v::numeric = -200, v);
  dr := pg_temp.val_as(ua, format('select public.get_dashboard_summary(%L)::text', ba))::jsonb;
  res := res || pg_temp.l('UDHAAR: a customer who is ahead does not reduce receivable',
    (dr->>'receivable')::numeric = (dr0->>'receivable')::numeric);
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.cancel_sales_order(%L)) s$q$, ocash));

  -- ---------- REPORTS ----------
  rp0 := pg_temp.val_as(ua, format($q$select public.get_sales_report(%L, (now() at time zone 'Asia/Karachi')::date, (now() at time zone 'Asia/Karachi')::date)::text$q$, ba))::jsonb;
  rpp0 := pg_temp.val_as(ua, format($q$select public.get_sales_report(%L, (now() at time zone 'Asia/Karachi')::date - 10, (now() at time zone 'Asia/Karachi')::date - 1)::text$q$, ba))::jsonb;
  v := pg_temp.val_as(ua, format($q$select public.create_sales_order(%L, %L::jsonb)::text$q$, ba, items1));
  orp := v::uuid;
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.confirm_sales_order(%L)) s$q$, orp));
  res := res || pg_temp.l('REPORT: confirm of the report test order succeeds', v = 'ok', v);
  v := pg_temp.val_as(ua, format($q$select public.create_expense(%L, 'Transport', 75, (now() at time zone 'Asia/Karachi')::date, 'report test')::text$q$, ba));
  erp := v::uuid;
  rp := pg_temp.val_as(ua, format($q$select public.get_sales_report(%L, (now() at time zone 'Asia/Karachi')::date, (now() at time zone 'Asia/Karachi')::date)::text$q$, ba))::jsonb;
  res := res || pg_temp.l('REPORT: today sales rose by 200 and orders by 1',
    (rp->>'sales')::numeric = (rp0->>'sales')::numeric + 200 and (rp->>'orders')::int = (rp0->>'orders')::int + 1);
  res := res || pg_temp.l('REPORT: cost of goods rose by 140 (2 x 70) and gross profit by 60',
    (rp->>'cost_of_goods')::numeric = (rp0->>'cost_of_goods')::numeric + 140
    and (rp->>'gross_profit')::numeric = (rp0->>'gross_profit')::numeric + 60);
  res := res || pg_temp.l('REPORT: expenses rose by 75',
    (rp->>'expenses')::numeric = (rp0->>'expenses')::numeric + 75);
  res := res || pg_temp.l('REPORT: net profit = gross profit - expenses',
    (rp->>'net_profit')::numeric = (rp->>'gross_profit')::numeric - (rp->>'expenses')::numeric);
  res := res || pg_temp.l('REPORT: one day gives one by_day row with the same sales',
    jsonb_array_length(rp->'by_day') = 1 and ((rp->'by_day'->0)->>'sales')::numeric = (rp->>'sales')::numeric);
  res := res || pg_temp.l('REPORT: top products lists the test soap with quantity 2 or more',
    exists (select 1 from jsonb_array_elements(rp->'top_products') e
            where e->>'name' = 'ZZ test soap' and (e->>'quantity')::numeric >= 2));
  res := res || pg_temp.l('REPORT: expenses by category lists Transport with at least 75',
    exists (select 1 from jsonb_array_elements(rp->'expenses_by_category') e
            where e->>'category' = 'Transport' and (e->>'amount')::numeric >= 75));
  rpp := pg_temp.val_as(ua, format($q$select public.get_sales_report(%L, (now() at time zone 'Asia/Karachi')::date - 10, (now() at time zone 'Asia/Karachi')::date - 1)::text$q$, ba))::jsonb;
  res := res || pg_temp.l('REPORT: a range that ends yesterday does not include today',
    (rpp->>'sales')::numeric = (rpp0->>'sales')::numeric and jsonb_array_length(rpp->'by_day') = 10);
  res := res || pg_temp.l('REPORT: start after end is rejected',
    pg_temp.val_as(ua, format($q$select public.get_sales_report(%L, current_date, current_date - 1)::text$q$, ba)) like '%must not be after%');
  res := res || pg_temp.l('REPORT: range over 366 days is rejected',
    pg_temp.val_as(ua, format($q$select public.get_sales_report(%L, current_date - 400, current_date)::text$q$, ba)) like '%366 days%');
  res := res || pg_temp.l('REPORT: missing dates are rejected',
    pg_temp.val_as(ua, format($q$select public.get_sales_report(%L, null, null)::text$q$, ba)) like '%Choose a start%');
  res := res || pg_temp.l('REPORT: other business user cannot read this report',
    pg_temp.val_as(ub, format($q$select public.get_sales_report(%L, current_date, current_date)::text$q$, ba)) like '%not an active member%');
  res := res || pg_temp.l('REPORT: signed-out user cannot read a report',
    pg_temp.val_as(null, format($q$select public.get_sales_report(%L, current_date, current_date)::text$q$, ba)) like 'ERROR%');
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.cancel_sales_order(%L)) s$q$, orp));
  v := pg_temp.val_as(ua, format($q$select 'ok' from (select public.archive_expense(%L)) s$q$, erp));
  rp := pg_temp.val_as(ua, format($q$select public.get_sales_report(%L, (now() at time zone 'Asia/Karachi')::date, (now() at time zone 'Asia/Karachi')::date)::text$q$, ba))::jsonb;
  res := res || pg_temp.l('REPORT: after cancel and archive the numbers are back to start',
    (rp->>'sales')::numeric = (rp0->>'sales')::numeric and (rp->>'expenses')::numeric = (rp0->>'expenses')::numeric
    and (rp->>'cost_of_goods')::numeric = (rp0->>'cost_of_goods')::numeric);

  -- ---------- AI QUESTION LIMIT ----------
  delete from public.ai_requests where business_id = ba or user_id = ua or user_id = ub;
  aq := pg_temp.val_as(ua, format($q$select public.consume_ai_quota(%L)::text$q$, ba));
  res := res || pg_temp.l('AIQUOTA: first question is allowed and 29 remain', aq = '29', aq);
  aq2 := pg_temp.val_as(ua, format($q$select public.consume_ai_quota(%L)::text$q$, ba));
  res := res || pg_temp.l('AIQUOTA: second question leaves 28', aq2 = '28', aq2);
  res := res || pg_temp.l('AIQUOTA: other business user cannot use this business',
    pg_temp.val_as(ub, format($q$select public.consume_ai_quota(%L)::text$q$, ba)) like '%not an active member%');
  res := res || pg_temp.l('AIQUOTA: signed-out user is rejected',
    pg_temp.val_as(null, format($q$select public.consume_ai_quota(%L)::text$q$, ba)) like 'ERROR%');
  res := res || pg_temp.l('AIQUOTA: client cannot read the usage table',
    pg_temp.val_as(ua, $q$select count(*)::text from public.ai_requests$q$) like 'ERROR%');
  res := res || pg_temp.l('AIQUOTA: client cannot write the usage table',
    pg_temp.val_as(ua, format($q$insert into public.ai_requests (business_id, user_id) values (%L, %L) returning 'x'$q$, ba, ua)) like 'ERROR%');
  insert into public.ai_requests (business_id, user_id)
    select ba, ua from generate_series(1, 28);
  aq := pg_temp.val_as(ua, format($q$select public.consume_ai_quota(%L)::text$q$, ba));
  res := res || pg_temp.l('AIQUOTA: the 31st question in 24 hours is refused',
    aq like '%Daily AI question limit%', aq);
  delete from public.ai_requests where user_id = ua;
  insert into public.ai_requests (business_id, user_id, created_at)
    select ba, ua, now() - interval '25 hours' from generate_series(1, 40);
  aq := pg_temp.val_as(ua, format($q$select public.consume_ai_quota(%L)::text$q$, ba));
  res := res || pg_temp.l('AIQUOTA: questions older than 24 hours do not count', aq = '29', aq);
  delete from public.ai_requests where business_id = ba;
  insert into public.ai_requests (business_id, user_id)
    select ba, ub from generate_series(1, 100);
  aq := pg_temp.val_as(ua, format($q$select public.consume_ai_quota(%L)::text$q$, ba));
  res := res || pg_temp.l('AIQUOTA: business-wide limit of 100 stops further questions',
    aq like '%business reached its daily%', aq);
  delete from public.ai_requests where business_id = ba;

  -- ---------- ONE BUSINESS PER USER ----------
  begin
    insert into public.business_members (business_id, user_id, role, status)
      values (bb, ua, 'staff', 'active');
    res := res || pg_temp.l('RULE: a user cannot become active member of a second business', false,
      'second active membership was accepted');
  exception when unique_violation then
    res := res || pg_temp.l('RULE: a user cannot become active member of a second business', true);
  end;
  res := res || pg_temp.l('RULE: create_business refuses a user who already has one',
    pg_temp.val_as(ua, $q$select public.create_business('ZZ second shop')::text$q$) like '%already have a business%');

  exception when others then
    err := sqlerrm;
  end;

  declare
    n_pass int := (length(res) - length(replace(res, 'PASS  ', ''))) / 6;
    n_fail int := (length(res) - length(replace(res, 'FAIL  ', ''))) / 6;
  begin
    if err is not null then
      n_fail := n_fail + 1;
      res := res || 'FAIL  UNEXPECTED ERROR, run stopped early  -> ' || err || E'\n';
    end if;
    raise exception E'%\n\n%(This error is expected. It rolls back all test data.)',
      case when n_fail = 0 then 'ALL TESTS PASSED ' else 'SOME TESTS FAILED ' end
        || n_pass || '/' || (n_pass + n_fail),
      res;
  end;
end
$t$;
