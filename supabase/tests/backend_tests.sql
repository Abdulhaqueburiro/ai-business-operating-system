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
  o1 uuid; o2 uuid; e1 uuid;
  v text; v2 text;
  d0 jsonb; d jsonb;
  items1 text; items10 text;
  k1 uuid := gen_random_uuid(); k2 uuid := gen_random_uuid(); k3 uuid := gen_random_uuid();
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
