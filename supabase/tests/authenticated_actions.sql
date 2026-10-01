-- ISOLATED TEST DATABASE ONLY. Synthetic auth rows, actual database roles, rollback grants.
begin;
do $$ begin
  if to_regclass('isolated_test.marker') is null then raise exception 'This test requires the disposable isolated test harness'; end if;
end $$;
grant execute on function public.log_manual_consumption(text,text,timestamptz,text,jsonb,jsonb,jsonb,text,numeric,numeric,text,boolean,text,date,uuid,text) to authenticated;
grant execute on function public.consume_product_purchase(uuid,numeric,numeric,text,text,numeric,numeric,text,boolean,text,date,uuid,text,timestamptz,text,text,text) to authenticated;
grant execute on function public.gpt_add_grocery_lots(jsonb,text,uuid) to authenticated;
grant execute on function public.consume_inventory_lot(uuid,uuid,numeric,timestamptz) to authenticated;
grant execute on function public.consume_prepared_lot(uuid,uuid,numeric,timestamptz) to authenticated;
grant execute on function public.consume_planned_meals(uuid,uuid[],numeric[],timestamptz) to authenticated;
grant execute on function public.prepare_recipe(uuid,uuid,numeric,numeric,text,uuid,numeric,timestamptz) to authenticated;
grant execute on function public.prepare_recipe(uuid,jsonb,uuid,numeric,numeric,text,uuid,numeric,timestamptz) to authenticated;
grant execute on function public.cook_recipes(uuid,uuid[]) to authenticated;
grant execute on function public.set_inventory_lot_quantity(uuid,uuid,numeric,boolean) to authenticated;
create temporary table authorization_cases(name text, statement text);
insert into authorization_cases values
('manual', $s$select public.log_manual_consumption('QA role meal','bowl','2026-10-01T12:00:00Z','exact',null,null,'[{"label":"QA"}]','gift',null,0,'other',false,'Unknown food value',null,'98000000-0000-0000-0000-000000000010',null)$s$),
('purchase', $s$select public.consume_product_purchase('98000000-0000-0000-0000-000000000003',4,1,'oz','grocery',10,10,'self',false,'QA receipt','2026-10-01',gen_random_uuid(),'pantry','2026-10-01T12:00:00Z','exact','QA purchase',null)$s$),
('haul', $s$select public.gpt_add_grocery_lots('[]','QA',gen_random_uuid())$s$),
('raw eating', $s$select public.consume_inventory_lot(gen_random_uuid(),gen_random_uuid(),1,now())$s$),
('prepared eating', $s$select public.consume_prepared_lot(gen_random_uuid(),gen_random_uuid(),1,now())$s$),
('planned eating', $s$select public.consume_planned_meals(gen_random_uuid(),array[gen_random_uuid()],array[1::numeric],now())$s$),
('preparation', $s$select public.prepare_recipe(p_request_id=>gen_random_uuid(),p_recipe=>gen_random_uuid())$s$),
('piece preparation', $s$select public.prepare_recipe(p_recipe=>gen_random_uuid(),p_piece_inputs=>'[]'::jsonb,p_request_id=>gen_random_uuid())$s$),
('combined cooking', $s$select public.cook_recipes(gen_random_uuid(),array[gen_random_uuid()])$s$),
('adjustment', $s$select public.set_inventory_lot_quantity(gen_random_uuid(),gen_random_uuid(),1,false)$s$);

do $$ declare owner_email text; begin
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into owner_email;
  if owner_email is null then raise exception 'Owner configuration could not be resolved for synthetic fixture'; end if;
  insert into auth.users(id,email,email_confirmed_at) values
    ('98000000-0000-0000-0000-000000000001',owner_email,now()),
    ('98000000-0000-0000-0000-000000000002','unrelated@example.test',now());
  insert into auth.sessions(id,user_id) values
    ('98000000-0000-0000-0000-000000000011','98000000-0000-0000-0000-000000000001'),
    ('98000000-0000-0000-0000-000000000012','98000000-0000-0000-0000-000000000002');
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"98000000-0000-0000-0000-000000000001","session_id":"98000000-0000-0000-0000-000000000011"}',true);
set local role authenticated;

do $$
declare unit_id uuid; food_id uuid:=gen_random_uuid(); product_id uuid:='98000000-0000-0000-0000-000000000003'; raw_id uuid:=gen_random_uuid(); recipe_id uuid:=gen_random_uuid(); ingredient_id uuid:=gen_random_uuid(); plan_id uuid:=gen_random_uuid();
  purchase_request uuid:=gen_random_uuid(); prep_request uuid:=gen_random_uuid(); raw_request uuid:=gen_random_uuid(); planned_request uuid:=gen_random_uuid(); adjust_request uuid:=gen_random_uuid();
  purchased jsonb; replay jsonb; prepared jsonb; pieces jsonb; haul jsonb; log_id uuid; repeated_id uuid; planned_logs uuid[]; adjustment uuid; remaining numeric; oz_ratio numeric; before_lots integer;
begin
  if current_user <> 'authenticated' or not public.is_app_owner() then raise exception 'Owner role setup failed'; end if;
  perform public.log_manual_consumption('QA role meal','bowl','2026-10-01T12:00:00Z','exact',null,null,'[{"label":"QA"}]','gift',null,0,'other',false,'Unknown food value',null,'98000000-0000-0000-0000-000000000010',null);
  select id into strict unit_id from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit) values(food_id,'QA role ingredient','weight',unit_id);
  insert into public.products(id,food,name,package_qty_base,package_unit,serving_qty_base,nutrition_basis_qty,kcal) values(product_id,food_id,'QA role pack',3000,unit_id,100,100,200);
  insert into public.inventory_lots(id,product,initial_qty,remaining_qty,total_cost,out_of_pocket_cost,paid_by,cost_source,price_as_of,acquisition_type,location)
    values(raw_id,product_id,3000,3000,30,30,'self','QA receipt',current_date,'grocery','pantry');
  insert into public.recipes(id,name,servings,instructions) values(recipe_id,'QA role recipe',2,'[]');
  insert into public.recipe_ingredients(id,recipe,ingredient,qty,unit) values(ingredient_id,recipe_id,food_id,100,unit_id);
  purchased:=public.consume_product_purchase(product_id,4,1,'oz','grocery',10,10,'self',false,'QA receipt','2026-10-01',purchase_request,'pantry','2026-10-01T12:00:00Z','exact','QA purchase',null);
  select count(*) into before_lots from public.inventory_lots;
  update public.products set archived_at=now() where id=product_id;
  select base_to_this_ratio into oz_ratio from public.measure_conversions where short_name='oz';
  update public.measure_conversions set base_to_this_ratio=oz_ratio*2 where short_name='oz';
  replay:=public.consume_product_purchase(product_id,4,1,'oz','grocery',10,10,'self',false,'QA receipt','2026-10-01',purchase_request,'pantry','2026-10-01T12:00:00Z','exact','QA purchase',null);
  if replay is distinct from purchased or (select count(*) from public.inventory_lots)<>before_lots then raise exception 'Purchase replay depended on mutable product/conversion or duplicated stock'; end if;
  begin
    perform public.consume_product_purchase(product_id,4,2,'oz','grocery',10,10,'self',false,'QA receipt','2026-10-01',purchase_request,'pantry','2026-10-01T12:00:00Z','exact','QA purchase',null);
    raise exception 'Changed purchase payload was accepted';
  exception when others then if sqlerrm not like 'This request ID belongs%' then raise; end if; end;
  update public.products set archived_at=null where id=product_id;
  update public.measure_conversions set base_to_this_ratio=oz_ratio where short_name='oz';
  haul:=public.gpt_add_grocery_lots(jsonb_build_array(jsonb_build_object('productId',product_id,'quantity',100,'unit','g','totalPrice',1,'outOfPocketCost',1,'costIsEstimated',false,'paidBy','self','priceAsOf',current_date,'location','pantry')),'QA receipt',gen_random_uuid());
  log_id:=public.consume_inventory_lot(raw_request,raw_id,50,'2026-10-01T12:00:00Z');
  repeated_id:=public.consume_inventory_lot(raw_request,raw_id,50,'2026-10-01T12:00:00Z');
  if log_id<>repeated_id or (select remaining_qty from public.inventory_lots where id=raw_id)<>2950 then raise exception 'Raw eating retry duplicated deduction'; end if;
  prepared:=public.prepare_recipe(prep_request,recipe_id,1,3,'fridge',null,0,'2026-10-01T12:00:00Z');
  if public.prepare_recipe(prep_request,recipe_id,1,3,'fridge',null,0,'2026-10-01T12:00:00Z') is distinct from prepared then raise exception 'Preparation retry changed output'; end if;
  log_id:=public.consume_prepared_lot(gen_random_uuid(),(prepared->>'lotId')::uuid,0.5,'2026-10-01T12:00:00Z');
  insert into public.meal_plans(id,inventory_lot,plan_date,daypart,intent,consume_from_inventory) values(plan_id,(prepared->>'lotId')::uuid,current_date,'lunch','consume',true);
  planned_logs:=public.consume_planned_meals(planned_request,array[plan_id],array[1::numeric],'2026-10-01T12:00:00Z');
  if public.consume_planned_meals(planned_request,array[plan_id],array[1::numeric],'2026-10-01T12:00:00Z') is distinct from planned_logs then raise exception 'Planned eating retry changed output'; end if;
  select remaining_qty into remaining from public.inventory_lots where id=raw_id;
  pieces:=public.prepare_recipe(recipe_id,jsonb_build_array(jsonb_build_object('ingredientId',ingredient_id,'lotId',raw_id,'pieces',0.5,'lotPieces',12,'expectedRemaining',remaining)),gen_random_uuid(),1,3,'fridge',null,0,'2026-10-01T12:00:00Z');
  perform public.cook_recipes(gen_random_uuid(),array[recipe_id]);
  select remaining_qty into remaining from public.inventory_lots where id=raw_id;
  adjustment:=public.set_inventory_lot_quantity(adjust_request,raw_id,remaining-10,false);
  if public.set_inventory_lot_quantity(adjust_request,raw_id,remaining-10,false) is distinct from adjustment or (select remaining_qty from public.inventory_lots where id=raw_id)<>remaining-10 then raise exception 'Adjustment retry duplicated stock correction'; end if;
  set constraints all immediate;
end $$;
reset role;

-- Revoke the fixture session so successful request replay must still fail the owner guard.
delete from auth.sessions where id='98000000-0000-0000-0000-000000000011';
do $$
declare test_case record; scenario integer; claims jsonb; denied integer:=0; previous_requests integer; previous_logs integer;
begin
  select count(*) into previous_requests from public.gpt_action_requests;
  select count(*) into previous_logs from public.food_logs;
  for scenario in 1..5 loop
    claims:=case scenario
      when 1 then '{"role":"anon","sub":"98000000-0000-0000-0000-000000000001","session_id":"98000000-0000-0000-0000-000000000011"}'::jsonb
      when 2 then '{"role":"authenticated","sub":"98000000-0000-0000-0000-000000000002","session_id":"98000000-0000-0000-0000-000000000012"}'::jsonb
      when 3 then '{"role":"authenticated","sub":"98000000-0000-0000-0000-000000000001"}'::jsonb
      when 4 then '{"role":"authenticated","sub":"98000000-0000-0000-0000-000000000001","session_id":"98000000-0000-0000-0000-000000000011"}'::jsonb
      else '{}'::jsonb end;
    perform set_config('request.jwt.claims',claims::text,true);
    for test_case in select * from authorization_cases loop
      if scenario=1 then set local role anon; else set local role authenticated; end if;
      begin
        execute test_case.statement;
        raise exception 'Unauthorized action succeeded: % / %',scenario,test_case.name;
      exception when insufficient_privilege then denied:=denied+1;
      end;
      reset role;
    end loop;
  end loop;
  if denied<>50 then raise exception 'Expected 50 denied attempts; got %',denied; end if;
  if (select count(*) from public.gpt_action_requests)<>previous_requests or (select count(*) from public.food_logs)<>previous_logs then raise exception 'Denied actions mutated state'; end if;
  if has_function_privilege('authenticated','public.claim_mutation_payload(uuid,text,jsonb)','execute') or has_function_privilege('authenticated','public.gpt_complete_request(uuid,jsonb)','execute') or has_table_privilege('authenticated','public.gpt_action_requests','select') then raise exception 'Private request implementation exposed'; end if;
end $$;
select '10 owner actions + 50 denied role/session attempts + mutable-purchase replay passed' as result;
rollback;
