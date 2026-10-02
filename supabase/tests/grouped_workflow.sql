-- Synthetic, rollback-only integration scenario using actual authenticated RPCs.
begin;
do $$ declare email text; begin
  if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict email;
  insert into auth.users(id,email,email_confirmed_at) values('98700000-0000-0000-0000-000000000001',email,now());
  insert into auth.sessions(id,user_id) values('98700000-0000-0000-0000-000000000011','98700000-0000-0000-0000-000000000001');
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"98700000-0000-0000-0000-000000000001","session_id":"98700000-0000-0000-0000-000000000011"}',true);
set local role authenticated;
do $$ declare
  u uuid; f uuid:=gen_random_uuid(); product_id uuid:=gen_random_uuid(); raw uuid:=gen_random_uuid();
  a uuid; b uuid; source_a uuid; source_b uuid; other_plan uuid;
  left_a uuid; left_b uuid; second_leftovers uuid[]; group_key text:=gen_random_uuid()::text;
  prep_a jsonb; prep_b jsonb; result jsonb; snapshot jsonb; old_prep uuid:=gen_random_uuid(); old_lot uuid:=gen_random_uuid();
  log_ids uuid[]; n bigint; request uuid:=gen_random_uuid();
  eaten_at timestamptz:=now()-interval '1 minute';
begin
  select id into strict u from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit,nutrition_basis_qty,kcal)
    values(f,'Grouped workflow rice','weight',u,100,360);
  insert into public.products(id,food,name,package_qty_base,package_unit)
    values(product_id,f,'Grouped rice product',100,u);
  insert into public.inventory_lots(id,product,initial_qty,remaining_qty,location)
    values(raw,product_id,100,100,'pantry');
  a:=(public.owner_create_recipe(gen_random_uuid(),jsonb_build_object('name','Grouped rice A','servings',4,
    'ingredients',jsonb_build_array(jsonb_build_object('ingredient',f,'unit',u,'qty',180))))->>'id')::uuid;
  b:=(public.owner_create_recipe(gen_random_uuid(),jsonb_build_object('name','Grouped rice B','servings',2,
    'ingredients',jsonb_build_array(jsonb_build_object('ingredient',f,'unit',u,'qty',120))))->>'id')::uuid;
  other_plan:=(public.owner_append_plan(gen_random_uuid(),jsonb_build_object('recipe',b,'scale_factor',2,
    'plan_date','2026-10-16','daypart','dinner','planned_servings',1))#>>'{planIds,0}')::uuid;
  perform public.rebuild_shopping_from_plan('2026-10-16','2026-10-22');
  if not exists(select 1 from public.shopping_items where food=f and generated_active and generated_shortage_base=140) then
    raise exception 'Other-week demand should be 240 minus 100'; end if;
  select jsonb_agg(to_jsonb(s) order by id) into snapshot from public.shopping_items s;

  source_a:=(public.owner_append_plan(gen_random_uuid(),jsonb_build_object('recipe',a,'scale_factor',0.5,
    'plan_date','2026-10-02','daypart','dinner','planned_servings',1))#>>'{planIds,0}')::uuid;
  source_b:=(public.owner_append_plan(gen_random_uuid(),jsonb_build_object('recipe',b,'scale_factor',1,
    'plan_date','2026-10-02','daypart','dinner','planned_servings',1))#>>'{planIds,0}')::uuid;
  -- Seed an existing grouped dinner via existing owner CRUD. The browser's
  -- append form creates individual groups, not a new multi-dish composer.
  update public.meal_plans set group_id=group_key where id in(source_a,source_b);
  result:=public.owner_append_plan(gen_random_uuid(),jsonb_build_object('intent','leftover','source_group_id',group_key,
    'plan_date','2026-10-03','daypart','lunch','planned_servings',1));
  select p.id into strict left_a from public.meal_plans p where p.source_meal_plan=source_a;
  select p.id into strict left_b from public.meal_plans p where p.source_meal_plan=source_b;
  if jsonb_array_length(result->'planIds')<>2 or
    (select count(distinct group_id) from public.meal_plans where id in(left_a,left_b))<>1 then raise exception 'Dinner grouping lost'; end if;
  result:=public.owner_append_plan(gen_random_uuid(),jsonb_build_object('intent','leftover','source_group_id',group_key,
    'plan_date','2026-10-04','daypart','lunch','planned_servings',0.5));
  select array_agg(value::uuid) into second_leftovers from jsonb_array_elements_text(result->'planIds');
  if (select jsonb_agg(to_jsonb(s) order by id) from public.shopping_items s) is distinct from snapshot then
    raise exception 'Browser append rebuilt or deactivated other-week groceries'; end if;
  perform public.rebuild_shopping_from_plan('2026-10-02','2026-10-08');
  if not exists(select 1 from public.shopping_items where food=f and generated_active and generated_shortage_base=110)
    or (select count(*) from public.shopping_items where food=f and source='generated' and generated_active)<>1 then
    raise exception 'Shared ingredient demand should sum 90+120-100, excluding leftovers'; end if;

  -- An older same-recipe batch must never satisfy a future source reference.
  insert into public.preps(id,recipe,actual_yield_qty) values(old_prep,a,2);
  insert into public.inventory_lots(id,prep,initial_qty,remaining_qty,location) values(old_lot,old_prep,2,2,'fridge');
  begin
    perform public.consume_planned_meals(gen_random_uuid(),array[left_a,left_b],array[1::numeric,0.5],eaten_at);
    raise exception 'Unprepared group used unrelated old stock';
  exception when raise_exception then if sqlerrm<>'No prepared batch has enough servings for the amount eaten' then raise; end if; end;
  prep_a:=public.prepare_recipe(gen_random_uuid(),a,0.5,2,'fridge',source_a,0,eaten_at);
  if (select remaining_qty from public.inventory_lots where id=raw)<>10 then raise exception 'Half batch should consume 90g'; end if;
  n:=(select count(*) from public.food_logs);
  begin
    perform public.consume_planned_meals(gen_random_uuid(),array[left_a,left_b],array[1::numeric,0.5],eaten_at);
    raise exception 'Partially prepared group consumed';
  exception when raise_exception then if sqlerrm<>'No prepared batch has enough servings for the amount eaten' then raise; end if; end;
  if (select count(*) from public.food_logs)<>n or
    (select remaining_qty from public.inventory_lots where id=(prep_a->>'lotId')::uuid)<>2 or
    exists(select 1 from public.planned_consumptions where meal_plan in(left_a,left_b) and status<>'planned') then
    raise exception 'Failed second component partially consumed first'; end if;
  n:=(select count(*) from public.preps);
  begin
    perform public.prepare_recipe(gen_random_uuid(),b,1,2,'fridge',source_b,0,eaten_at);
    raise exception 'Insufficient shared raw stock accepted';
  exception when raise_exception then if sqlerrm not like 'Not enough inventory for ingredient%' then raise; end if; end;
  if (select count(*) from public.preps)<>n or (select remaining_qty from public.inventory_lots where id=raw)<>10 then
    raise exception 'Failed preparation partially consumed stock'; end if;
  insert into public.inventory_events(lot,quantity_delta,reason,note) values(raw,200,'adjust','Synthetic test restock');
  prep_b:=public.prepare_recipe(gen_random_uuid(),b,1,2,'fridge',source_b,0,eaten_at);
  log_ids:=public.consume_planned_meals(request,array[left_a,left_b],array[1::numeric,0.5],eaten_at);
  if public.consume_planned_meals(request,array[left_a,left_b],array[1::numeric,0.5],eaten_at)<>log_ids then
    raise exception 'Grouped consumption replay changed log IDs'; end if;
  if cardinality(log_ids)<>2 or (select count(*) from public.food_logs where id=any(log_ids) and occurred_at=eaten_at)<>2
    or (select remaining_qty from public.inventory_lots where id=(prep_a->>'lotId')::uuid)<>1
    or (select remaining_qty from public.inventory_lots where id=(prep_b->>'lotId')::uuid)<>1.5
    or (select remaining_qty from public.inventory_lots where id=old_lot)<>2 then raise exception 'Wrong quantities, source, or occurred date'; end if;
  begin perform public.undo_prep((prep_a->>'prepId')::uuid); raise exception 'Active consumption allowed source undo';
  exception when raise_exception then if sqlerrm<>'This batch has already been eaten from and can no longer be undone' then raise; end if; end;
  perform public.void_food_log(log_ids[1]);
  if (select status from public.planned_consumptions where meal_plan=left_a)<>'planned'
    or (select status from public.planned_consumptions where meal_plan=left_b)<>'fulfilled' then raise exception 'Voiding one dish affected another'; end if;
  perform public.void_food_log(log_ids[2]);
  perform public.undo_prep((prep_a->>'prepId')::uuid);
  if (select remaining_qty from public.inventory_lots where id=raw)<>180
    or (select status from public.meal_plans where id=source_a)<>'planned'
    or (select status from public.meal_plans where id=source_b)<>'made' then raise exception 'Partial source undo affected other dish'; end if;
  perform public.undo_prep((prep_b->>'prepId')::uuid);
  if (select remaining_qty from public.inventory_lots where id=raw)<>300
    or (select remaining_qty from public.inventory_lots where id=old_lot)<>2
    or exists(select 1 from public.meal_plans where id in(source_a,source_b) and (status<>'planned' or made_at is not null))
    or exists(select 1 from public.preps where id in((prep_a->>'prepId')::uuid,(prep_b->>'prepId')::uuid) and voided_at is null)
    or exists(select 1 from public.food_logs where id=any(log_ids) and voided_at is null) then raise exception 'Undo failed to restore canonical state'; end if;
  -- The dependent made flags are historical; the UI must derive readiness from
  -- the now-voided sources (covered by PlanStatus.test.tsx), not those flags.
  if exists(select 1 from public.planned_consumptions where meal_plan in(left_a,left_b) and status<>'planned') then raise exception 'Consumption flags not reset'; end if;
  begin delete from public.meal_plans where id=source_a; raise exception 'Source deleted before dependencies'; exception when foreign_key_violation then null; end;
  delete from public.meal_plans where id in(left_a,left_b) or id=any(second_leftovers);
  delete from public.meal_plans where id in(source_a,source_b,other_plan);
  if exists(select 1 from public.planned_consumptions where meal_plan in(left_a,left_b,source_a,source_b)) then raise exception 'Cleanup left portions'; end if;
end $$;
reset role;
select 'PASS: grouped shared-ingredient dinner, future leftovers, atomic failure, exact consumption, void/undo, dependency cleanup';
rollback;
