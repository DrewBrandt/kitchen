-- Independent-review regressions. Never run outside the disposable harness.
begin;
do $$ declare owner_email text; begin
  if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict owner_email;
  insert into auth.users(id,email,email_confirmed_at) values('99400000-0000-0000-0000-000000000001',owner_email,now());
  insert into auth.sessions(id,user_id) values('99400000-0000-0000-0000-000000000011','99400000-0000-0000-0000-000000000001');
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99400000-0000-0000-0000-000000000001","session_id":"99400000-0000-0000-0000-000000000011"}',true);
set local role authenticated;
do $$
declare
  v_unit uuid; v_food uuid:=gen_random_uuid(); v_product uuid:=gen_random_uuid(); v_item uuid:=gen_random_uuid();
  v_lot uuid; v_event uuid; v_log uuid; v_payload jsonb; v_result jsonb; v_expected numeric; v_nutrition jsonb;
  v_recipe uuid:=gen_random_uuid(); v_plan uuid:=gen_random_uuid(); v_generated uuid; v_checked timestamptz:=now()-interval '1 day';
begin
  select id into strict v_unit from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit) values(v_food,'Receipt regression food','weight',v_unit);
  insert into public.products(id,food,name,package_qty_base,package_unit,nutrition_basis_qty,kcal,protein_g)
  values(v_product,v_food,'Receipt regression product',100,v_unit,100,200,20);
  insert into public.shopping_items(id,food,qty_needed,unit) values(v_item,v_food,300,v_unit);
  v_payload:=jsonb_build_object('productId',v_product,'quantity',300,'unit','g','totalPrice',0,'acquiredAt','2026-10-01T12:00:00Z');
  v_result:=public.receive_shopping_item(gen_random_uuid(),v_item,v_payload);v_lot:=(v_result->>'lotId')::uuid;
  if (select estimated_cost from public.products where id=v_product) is distinct from 0 then raise exception 'Free receipt did not seed price fixture'; end if;
  perform public.undo_inventory_receipt(gen_random_uuid(),v_lot);
  if (select estimated_cost from public.products where id=v_product) is not null then raise exception 'Canceled free receipt left authoritative price'; end if;
  select acquisition_void_event into v_event from public.inventory_lots where id=v_lot;
  begin
    perform public.undo_inventory_adjustment(v_event);
    raise exception 'Generic undo resurrected canceled acquisition';
  exception when raise_exception then
    if sqlerrm not like 'An acquisition reversal cannot be undone%' then raise; end if;
  end;
  if (select remaining_qty from public.inventory_lots where id=v_lot)<>0 or (select lot from public.shopping_items where id=v_item) is not null then raise exception 'Canceled acquisition state changed'; end if;
  update public.inventory_lots set cost_source='Edited canceled receipt source' where id=v_lot;
  if (select estimated_cost from public.products where id=v_product) is not null then raise exception 'Canceled lot metadata reseeded product price'; end if;

  -- Explicit later catalog pricing wins, even after receipt undo.
  v_result:=public.receive_shopping_item(gen_random_uuid(),v_item,v_payload||'{"totalPrice":6}');v_lot:=(v_result->>'lotId')::uuid;
  perform public.gpt_update_product(v_product,jsonb_build_object('estimatedCost',9,'costSource','Later user price','costAsOf',current_date));
  perform public.undo_inventory_receipt(gen_random_uuid(),v_lot);
  if not exists(select 1 from public.products where id=v_product and estimated_cost=9 and cost_source='Later user price') then raise exception 'Undo overwrote later user price'; end if;
  perform public.gpt_update_product(v_product,'{"estimatedCost":null,"costSource":null,"costAsOf":null}');

  -- Converted units, positive price, proportional nutrition/cost, and reversible dependency.
  v_expected:=public.to_base_quantity(v_food,4,(select id from public.measure_conversions where short_name='oz'));
  v_result:=public.receive_shopping_item(gen_random_uuid(),v_item,v_payload||'{"quantity":4,"unit":"oz","totalPrice":8}');v_lot:=(v_result->>'lotId')::uuid;
  if not exists(select 1 from public.inventory_lots where id=v_lot and initial_qty=v_expected and remaining_qty=v_expected and total_cost=8 and out_of_pocket_cost=8) then raise exception 'Converted receipt quantity or price incorrect'; end if;
  if (select estimated_cost from public.products where id=v_product) is distinct from round(8*100/v_expected,2) then raise exception 'Converted catalog package price incorrect'; end if;
  v_nutrition:=public.lot_nutrition_json(v_lot);
  if (v_nutrition->>'kcal')::numeric<>2 or (v_nutrition->>'protein_g')::numeric<>0.2 or v_nutrition->>'carbs_g' is not null then raise exception 'Receipt changed per-unit nutrition or unknown nutrient'; end if;
  v_log:=public.consume_inventory_lot(gen_random_uuid(),v_lot,25,'2026-10-01T13:00:00Z');
  if not exists(select 1 from public.food_logs where id=v_log and kcal=50 and protein_g=5) then raise exception 'Consumed receipt lost proportional nutrition'; end if;
  if not exists(select 1 from public.inventory_event_costs costs join public.inventory_events event on event.id=costs.inventory_event_id where event.food_log=v_log and abs(costs.cost-8*25/v_expected)<0.01) then raise exception 'Consumed receipt lost proportional cost'; end if;
  perform public.void_food_log(v_log);
  perform public.gpt_update_product(v_product,'{"name":"Later name edit"}');
  perform public.undo_inventory_receipt(gen_random_uuid(),v_lot);
  if not exists(select 1 from public.products where id=v_product and estimated_cost is null and name='Later name edit' and kcal=200 and protein_g=20) then raise exception 'Price restoration lost unrelated later product edit'; end if;

  -- Keep custom rebuild range and user edits; compute shortage after canceled stock.
  insert into public.recipes(id,name,servings) values(v_recipe,'Demand regression recipe',2);
  insert into public.recipe_ingredients(recipe,ingredient,qty,unit) values(v_recipe,v_food,200,v_unit);
  insert into public.meal_plans(id,recipe,plan_date,daypart) values(v_plan,v_recipe,current_date+15,'dinner');
  perform public.rebuild_shopping_from_plan(current_date+14,current_date+20);
  select id into strict v_generated from public.shopping_items where food=v_food and source='generated';
  update public.shopping_items set checked_at=v_checked,qty_needed=175,note='Keep edited demand',pinned_product=v_product where id=v_generated;
  v_result:=public.receive_shopping_item(gen_random_uuid(),v_generated,v_payload||'{"quantity":40,"totalPrice":null}');v_lot:=(v_result->>'lotId')::uuid;
  perform public.rebuild_shopping_from_plan(current_date+14,current_date+20);
  if (select generated_shortage_base from public.shopping_items where id=v_generated)<>160 then raise exception 'Shortage fixture incorrect'; end if;
  perform public.undo_inventory_receipt(gen_random_uuid(),v_lot);
  if not exists(select 1 from public.shopping_items where id=v_generated and generated_shortage_base=200 and generated_active and generated_demand_changed and received_qty_base=0 and qty_needed=175 and note='Keep edited demand' and checked_at=v_checked and pinned_product=v_product) then raise exception 'Undo kept stale shortage or destroyed user edits'; end if;
  v_result:=public.receive_shopping_item(gen_random_uuid(),v_generated,v_payload||'{"quantity":40,"totalPrice":null}');v_lot:=(v_result->>'lotId')::uuid;
  update public.meal_plans set status='skipped' where id=v_plan;
  perform public.undo_inventory_receipt(gen_random_uuid(),v_lot);
  if not exists(select 1 from public.shopping_items where id=v_generated and generated_shortage_base=0 and not generated_active and not generated_demand_changed and checked_at=v_checked and qty_needed=175) then raise exception 'Undo reactivated removed demand'; end if;
  set constraints all immediate;
end $$;
reset role;
rollback;
