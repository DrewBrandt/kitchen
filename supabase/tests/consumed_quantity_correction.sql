-- Disposable harness only: this transaction grants the candidate solely for testing.
begin;
do $$ begin if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if; end $$;
do $$ begin
  if has_function_privilege('authenticated','public.correct_consumed_quantity(uuid,uuid,numeric,numeric)','execute')
    or has_function_privilege('anon','public.correct_consumed_quantity(uuid,uuid,numeric,numeric)','execute')
    or has_function_privilege('service_role','public.correct_consumed_quantity(uuid,uuid,numeric,numeric)','execute') then
    raise exception 'Candidate must be ungranted';
  end if;
end $$;
grant execute on function public.correct_consumed_quantity(uuid,uuid,numeric,numeric) to authenticated;
do $$ declare owner_email text; begin
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict owner_email;
  insert into auth.users(id,email,email_confirmed_at) values
    ('99000000-0000-0000-0000-000000000001',owner_email,now()),
    ('99000000-0000-0000-0000-000000000002','other@example.test',now());
  insert into auth.sessions(id,user_id) values
    ('99000000-0000-0000-0000-000000000011','99000000-0000-0000-0000-000000000001'),
    ('99000000-0000-0000-0000-000000000012','99000000-0000-0000-0000-000000000002');
end $$;
create temporary table correction_result(original uuid,replacement uuid,request uuid,result jsonb);
grant all on correction_result to authenticated;
create function pg_temp.fail_correction_audit() returns trigger language plpgsql as $$ begin
  if current_setting('test.fail_correction_audit',true)='on' then raise exception 'Injected final audit failure'; end if;
  return new;
end $$;
create trigger test_correction_final_failure before insert on public.record_edits for each row execute function pg_temp.fail_correction_audit();
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99000000-0000-0000-0000-000000000001","session_id":"99000000-0000-0000-0000-000000000011"}',true);
set local role authenticated;
do $$
declare
  unit_id uuid; food_id uuid:=gen_random_uuid(); product_id uuid:=gen_random_uuid(); lot_id uuid:=gen_random_uuid();
  log_id uuid; new_id uuid; final_id uuid; request_id uuid:=gen_random_uuid(); result jsonb; old_row public.food_logs%rowtype; new_row public.food_logs%rowtype;
  before_logs bigint; before_audits bigint; bad numeric; recipe_id uuid:=gen_random_uuid(); prep jsonb; prepared_lot uuid; prepared_log uuid; corrected_prepared uuid; plan_id uuid:=gen_random_uuid();
  purchased jsonb; purchase_log uuid; volume_food uuid:=gen_random_uuid(); volume_product uuid:=gen_random_uuid(); volume_lot uuid:=gen_random_uuid(); volume_log uuid;
begin
  if current_user <> 'authenticated' or not public.is_app_owner() then raise exception 'Real owner-role fixture required'; end if;
  select id into strict unit_id from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit) values(food_id,'QA correction food','weight',unit_id);
  insert into public.products(id,food,name,package_qty_base,package_unit,serving_qty_base,nutrition_basis_qty,kcal)
  values(product_id,food_id,'QA correction product',3000,unit_id,100,100,200);
  insert into public.inventory_lots(id,product,initial_qty,remaining_qty,total_cost,out_of_pocket_cost,paid_by,cost_source,price_as_of,acquisition_type,location)
  values(lot_id,product_id,3000,3000,null,0,'gift','Unknown value',null,'gift','pantry');
  log_id:=public.consume_inventory_lot(gen_random_uuid(),lot_id,200,'2026-09-04T12:00:00Z');
  update public.food_logs set time_precision='dateOnly',kcal=400,protein_g=null,sodium_mg=0,nutrition_source='Recorded source',nutrition_is_estimated=true,
    nutrition_estimate='{"rationale":"Original estimate"}',components='[{"label":"Original food"}]',cost=4,total_price=null,out_of_pocket_cost=0,cost_is_estimated=true,note='Original note'
  where id=log_id;
  select * into old_row from public.food_logs where id=log_id;
  -- Mutable definitions must not overwrite historical nutrition.
  update public.products set kcal=999 where id=product_id;
  result:=public.correct_consumed_quantity(request_id,log_id,200,100);
  new_id:=(result->>'id')::uuid;
  insert into correction_result values(log_id,new_id,request_id,result);
  select * into new_row from public.food_logs where id=new_id;
  if new_row.kcal<>200 or new_row.protein_g is not null or new_row.sodium_mg<>0 or new_row.cost<>2 or new_row.total_price is not null or new_row.out_of_pocket_cost<>0 then raise exception 'Historical ratio/null/zero cost or nutrition failed'; end if;
  if new_row.occurred_at<>old_row.occurred_at or new_row.time_precision<>old_row.time_precision or new_row.components<>old_row.components
    or new_row.nutrition_estimate<>old_row.nutrition_estimate or new_row.nutrition_source<>old_row.nutrition_source or new_row.note<>old_row.note
    or not new_row.nutrition_is_estimated or not new_row.cost_is_estimated then raise exception 'Historical provenance changed'; end if;
  if (select remaining_qty from public.inventory_lots where id=lot_id)<>2900 or (select voided_at from public.food_logs where id=log_id) is null then raise exception 'Ledger correction failed'; end if;
  if not exists(select 1 from public.food_log_replacements where original_log=log_id and replacement_log=new_id) or not exists(select 1 from public.record_edits where record_id=log_id) then raise exception 'Audit missing'; end if;
  if public.correct_consumed_quantity(request_id,log_id,200,100)<>result then raise exception 'Lost-response replay failed'; end if;
  begin perform public.correct_consumed_quantity(request_id,log_id,200,150); raise exception 'Changed retry accepted'; exception when others then if sqlerrm not like 'This request ID belongs%' then raise; end if; end;
  begin perform public.restore_food_log(log_id); raise exception 'Obsolete original restored'; exception when others then if sqlerrm not like '%cannot be restored%' then raise; end if; end;
  select count(*) into before_logs from public.food_logs; select count(*) into before_audits from public.record_edits;
  result:=public.correct_consumed_quantity(gen_random_uuid(),new_id,100,100);
  if result->>'status'<>'unchanged' or (select count(*) from public.food_logs)<>before_logs or (select count(*) from public.record_edits)<>before_audits then raise exception 'No-op generated history'; end if;
  begin perform public.correct_consumed_quantity(gen_random_uuid(),new_id,200,100); raise exception 'Stale old quantity accepted'; exception when others then if sqlerrm not like 'Consumed quantity changed%' then raise; end if; end;
  begin perform public.correct_consumed_quantity(gen_random_uuid(),new_id,100,4000); raise exception 'Insufficient stock accepted'; exception when others then if sqlerrm not like 'Insufficient stock%' then raise; end if; end;
  foreach bad in array array[0,-1,'NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric,null::numeric] loop
    begin perform public.correct_consumed_quantity(gen_random_uuid(),new_id,100,bad); raise exception 'Bad quantity accepted'; exception when others then if sqlerrm not like 'Quantities must be finite%' then raise; end if; end;
  end loop;
  if (select count(*) from public.food_logs)<>before_logs or (select remaining_qty from public.inventory_lots where id=lot_id)<>2900 then raise exception 'Failure was not atomic'; end if;
  -- Fail after original void, replacement insert, ledger deduction, and link creation.
  perform set_config('test.fail_correction_audit','on',true);
  begin perform public.correct_consumed_quantity(gen_random_uuid(),new_id,100,150); raise exception 'Injected failure missing'; exception when others then if sqlerrm<>'Injected final audit failure' then raise; end if; end;
  perform set_config('test.fail_correction_audit','off',true);
  if (select count(*) from public.food_logs)<>before_logs or (select remaining_qty from public.inventory_lots where id=lot_id)<>2900
    or (select voided_at from public.food_logs where id=new_id) is not null or exists(select 1 from public.food_log_replacements where original_log=new_id) then raise exception 'Mid-transaction failure left partial correction'; end if;
  final_id:=(public.correct_consumed_quantity(gen_random_uuid(),new_id,100,150)->>'id')::uuid;
  begin perform public.restore_food_log(new_id); raise exception 'Intermediate restored'; exception when others then if sqlerrm not like '%cannot be restored%' then raise; end if; end;
  perform public.void_food_log(final_id);
  if (select remaining_qty from public.inventory_lots where id=lot_id)<>3000 then raise exception 'Latest void failed'; end if;
  perform public.restore_food_log(final_id);
  if (select remaining_qty from public.inventory_lots where id=lot_id)<>2850 then raise exception 'Latest restore failed'; end if;
  -- Additional ledger events are rejected, without guessing how to redistribute quantities.
  insert into public.inventory_events(lot,quantity_delta,reason,food_log) values(lot_id,-1,'eaten',final_id);
  begin perform public.correct_consumed_quantity(gen_random_uuid(),final_id,150,100); raise exception 'Ambiguous entry accepted'; exception when others then if sqlerrm not like 'Correction requires exactly one%' then raise; end if; end;
  purchased:=public.consume_product_purchase(product_id,100,50,'g','grocery',10,10,'self',false,'Receipt',current_date,gen_random_uuid(),'pantry',now(),'exact',null,null);
  purchase_log:=(purchased->>'logId')::uuid;
  begin perform public.correct_consumed_quantity(gen_random_uuid(),purchase_log,50,25); raise exception 'Purchase accepted'; exception when others then if sqlerrm not like 'Only an existing single-lot%' then raise; end if; end;
  -- Canonical volume is fluid ounces in this schema, not milliliters.
  select id into strict unit_id from public.measure_conversions where short_name='fl oz';
  insert into public.base_foods(id,name,measure_style,display_unit) values(volume_food,'QA volume','volume',unit_id);
  insert into public.products(id,food,name,package_qty_base,package_unit,serving_qty_base) values(volume_product,volume_food,'QA milk',8,unit_id,8);
  insert into public.inventory_lots(id,product,initial_qty,remaining_qty,total_cost,out_of_pocket_cost,paid_by,cost_source,acquisition_type,location)
  values(volume_lot,volume_product,8,8,null,0,'gift','Unknown value','gift','fridge');
  volume_log:=public.consume_inventory_lot(gen_random_uuid(),volume_lot,4,'2026-09-04T12:00:00Z');
  result:=public.correct_consumed_quantity(gen_random_uuid(),volume_log,4,2);
  if result->>'unit'<>'fl oz' or (select remaining_qty from public.inventory_lots where id=volume_lot)<>6
    or (select portion_label from public.food_logs where id=(result->>'id')::uuid)<>'2 fl oz' then raise exception 'Canonical volume correction failed'; end if;
  select id into strict unit_id from public.measure_conversions where short_name='g';
  insert into public.recipes(id,name,servings,instructions) values(recipe_id,'QA prepared correction',4,'[]');
  insert into public.recipe_ingredients(recipe,ingredient,qty,unit) values(recipe_id,food_id,200,unit_id);
  prep:=public.prepare_recipe(gen_random_uuid(),recipe_id,1,4,'fridge',null,0,'2026-09-04T12:00:00Z');
  prepared_lot:=(prep->>'lotId')::uuid;
  insert into public.meal_plans(id,recipe,plan_date,daypart,intent) values(plan_id,recipe_id,current_date,'lunch','prepare');
  prepared_log:=public.consume_prepared_batch(prepared_lot,2,plan_id,'2026-09-04T12:00:00Z');
  corrected_prepared:=(public.correct_consumed_quantity(gen_random_uuid(),prepared_log,2,1)->>'id')::uuid;
  if (select remaining_qty from public.inventory_lots where id=prepared_lot)<>3
    or not exists(select 1 from public.planned_consumptions where meal_plan=plan_id and food_log=corrected_prepared and status='fulfilled') then raise exception 'Prepared stock or plan transfer failed'; end if;
  begin perform public.undo_prep((prep->>'prepId')::uuid); raise exception 'Consumed prep undo accepted'; exception when others then if sqlerrm not like '%already been eaten%' then raise; end if; end;
  perform public.void_food_log(corrected_prepared);
  perform public.restore_food_log(corrected_prepared);
  if (select remaining_qty from public.inventory_lots where id=prepared_lot)<>3 then raise exception 'Prepared latest restore failed'; end if;
  perform public.void_food_log(corrected_prepared);
  perform public.undo_prep((prep->>'prepId')::uuid);
  begin perform public.restore_food_log(corrected_prepared); raise exception 'Restored consumption after prep undo'; exception when others then if sqlerrm='Restored consumption after prep undo' then raise; end if; end;
  set constraints all immediate;
  raise notice 'Owner quantity correction, replay, rollback, chain, plan, and prep reversal checks passed';
end $$;
reset role;
-- Owner guard must precede successful-request replay; no role may bypass a revoked session.
delete from auth.sessions where id='99000000-0000-0000-0000-000000000011';
do $$ declare scenario integer; result_row record; denied integer:=0; begin
  select * into result_row from correction_result limit 1;
  for scenario in 1..5 loop
    perform set_config('request.jwt.claims',case scenario
      when 1 then '{"role":"anon"}'
      when 2 then '{"role":"authenticated","sub":"99000000-0000-0000-0000-000000000002","session_id":"99000000-0000-0000-0000-000000000012"}'
      when 3 then '{"role":"authenticated","sub":"99000000-0000-0000-0000-000000000001"}'
      when 4 then '{"role":"authenticated","sub":"99000000-0000-0000-0000-000000000001","session_id":"99000000-0000-0000-0000-000000000011"}'
      else '{}' end,true);
    if scenario=1 then set local role anon; else set local role authenticated; end if;
    begin perform public.correct_consumed_quantity(result_row.request,result_row.original,200,100); exception when insufficient_privilege then denied:=denied+1; end;
    reset role;
  end loop;
  if denied<>5 then raise exception 'Authorization failure: % denied',denied; end if;
  raise notice 'Five unauthorized role/session scenarios rejected, including replay';
end $$;
rollback;
