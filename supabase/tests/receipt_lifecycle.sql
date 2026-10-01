-- Disposable PostgreSQL harness only; synthetic owner sessions, real DB roles.
begin;
do $$ begin if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if; end $$;
do $$ declare owner_email text; begin
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict owner_email;
  insert into auth.users(id,email,email_confirmed_at) values
    ('99200000-0000-0000-0000-000000000001',owner_email,now()),
    ('99200000-0000-0000-0000-000000000002','not-owner@example.test',now());
  insert into auth.sessions(id,user_id) values
    ('99200000-0000-0000-0000-000000000011','99200000-0000-0000-0000-000000000001'),
    ('99200000-0000-0000-0000-000000000012','99200000-0000-0000-0000-000000000002');
  if has_function_privilege('anon','public.receive_shopping_item(uuid,uuid,jsonb)','execute')
    or has_function_privilege('service_role','public.receive_shopping_item(uuid,uuid,jsonb)','execute')
    or has_function_privilege('anon','public.undo_inventory_receipt(uuid,uuid)','execute')
    or has_function_privilege('service_role','public.undo_inventory_receipt(uuid,uuid)','execute') then raise exception 'Unexpected receipt privileges'; end if;
end $$;
create temporary table saved_receipt(request uuid,item uuid,payload jsonb,lot uuid);
grant all on saved_receipt to authenticated;
create function pg_temp.reject_receipt_audit() returns trigger language plpgsql as $$ begin
  if current_setting('test.reject_receipt_audit',true)='on' then raise exception 'Injected audit failure'; end if;
  return new;
end $$;
create trigger test_receipt_audit before insert on public.record_edits for each row execute function pg_temp.reject_receipt_audit();
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99200000-0000-0000-0000-000000000001","session_id":"99200000-0000-0000-0000-000000000011"}',true);
set local role authenticated;
do $$
#variable_conflict use_variable
declare u uuid; food uuid:=gen_random_uuid(); other_food uuid:=gen_random_uuid(); product uuid:=gen_random_uuid(); other_product uuid:=gen_random_uuid();
  recipe uuid:=gen_random_uuid(); plan uuid:=gen_random_uuid(); item uuid; payload jsonb; result jsonb; request uuid:=gen_random_uuid(); lot uuid;
  old_check timestamptz:=now()-interval '2 days'; before_count bigint; event uuid; undo_request uuid:=gen_random_uuid(); new_item uuid:=gen_random_uuid(); plain_product uuid;
  prep jsonb; dependent_plan uuid:=gen_random_uuid();
begin
  if current_user<>'authenticated' or not public.is_app_owner() then raise exception 'Owner-role fixture required'; end if;
  select id into strict u from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit) values(food,'Receipt QA food','weight',u),(other_food,'Other receipt QA food','weight',u);
  insert into public.products(id,food,name,package_qty_base,package_unit) values(product,food,'Receipt QA product',1000,u),(other_product,other_food,'Unrelated QA',1000,u);
  insert into public.recipes(id,name,servings) values(recipe,'Receipt QA recipe',2);
  insert into public.recipe_ingredients(recipe,ingredient,qty,unit) values(recipe,food,100,u);
  insert into public.meal_plans(id,recipe,plan_date,daypart) values(plan,recipe,current_date,'dinner');
  perform public.rebuild_shopping_from_plan();
  select id into strict item from public.shopping_items where shopping_items.food=food and source='generated';
  update public.shopping_items set checked_at=old_check,note='Keep this note',pinned_product=product,qty_needed=125 where id=item;
  update public.meal_plans set scale_factor=2 where id=plan;
  perform public.rebuild_shopping_from_plan();
  if not exists(select 1 from public.shopping_items where id=item and checked_at=old_check and note='Keep this note' and pinned_product=product and qty_needed=125 and generated_shortage_base=200 and generated_demand_changed) then raise exception 'Rebuild discarded user state or hid changed demand'; end if;
  update public.meal_plans set status='skipped' where id=plan;
  perform public.rebuild_shopping_from_plan();
  if not exists(select 1 from public.shopping_items where id=item and not generated_active and checked_at=old_check) then raise exception 'Zero demand deleted user state'; end if;
  update public.meal_plans set status='planned' where id=plan;
  perform public.rebuild_shopping_from_plan();
  payload:=jsonb_build_object('productId',product,'quantity',40,'unit',u,'totalPrice',null,'acquiredAt','2026-10-01T12:00:00Z');
  result:=public.receive_shopping_item(request,item,payload); lot:=(result->>'lotId')::uuid;
  if public.receive_shopping_item(request,item,payload) is distinct from result then raise exception 'Receipt replay changed result'; end if;
  begin perform public.receive_shopping_item(request,item,payload||'{"quantity":41}'); raise exception 'Different retry payload accepted'; exception when raise_exception then if sqlerrm='Different retry payload accepted' then raise; end if; end;
  begin perform public.receive_shopping_item(gen_random_uuid(),item,payload); raise exception 'Second receipt accepted'; exception when raise_exception then if sqlerrm='Second receipt accepted' then raise; end if; end;
  if not exists(select 1 from public.inventory_lots where id=lot and initial_qty=40 and remaining_qty=40 and total_cost is null and out_of_pocket_cost is null) then raise exception 'Unknown price or receipt amount corrupted'; end if;
  if not exists(select 1 from public.shopping_items where id=item and checked_at=old_check and qty_needed=125 and received_qty_base=40) then raise exception 'Partial receipt changed demand/check'; end if;
  perform public.rebuild_shopping_from_plan();
  if not exists(select 1 from public.shopping_items where id=item and generated_shortage_base=160 and qty_needed=125) then raise exception 'Partial stock did not reduce shortage correctly'; end if;
  insert into public.inventory_events(lot,quantity_delta,reason) values(lot,-1,'adjust') returning id into event;
  begin perform public.undo_inventory_receipt(gen_random_uuid(),lot); raise exception 'Dependent receipt undo accepted'; exception when raise_exception then if sqlerrm='Dependent receipt undo accepted' then raise; end if; end;
  update public.inventory_events set voided_at=now() where id=event;
  update public.shopping_items set qty_needed=130,note='Later edit' where id=item;
  result:=public.undo_inventory_receipt(undo_request,lot);
  if public.undo_inventory_receipt(undo_request,lot) is distinct from result then raise exception 'Undo replay changed result'; end if;
  if not exists(select 1 from public.inventory_lots where id=lot and remaining_qty=0 and acquisition_void_event is not null) then raise exception 'Undo left acquired stock'; end if;
  if not exists(select 1 from public.shopping_items where id=item and shopping_items.lot is null and qty_needed=130 and note='Later edit' and checked_at=old_check) then raise exception 'Undo overwrote later edits'; end if;
  insert into public.shopping_items(id,food,qty_needed,unit) values(new_item,food,100,u);
  begin perform public.receive_shopping_item(gen_random_uuid(),new_item,payload||jsonb_build_object('productId',other_product)); raise exception 'Unrelated product accepted'; exception when raise_exception then if sqlerrm='Unrelated product accepted' then raise; end if; end;
  select count(*) into before_count from public.products;
  perform set_config('test.reject_receipt_audit','on',true);
  begin perform public.receive_shopping_item(gen_random_uuid(),new_item,payload-'productId'); raise exception 'Audit failure accepted'; exception when raise_exception then if sqlerrm='Audit failure accepted' then raise; end if; end;
  perform set_config('test.reject_receipt_audit','off',true);
  if (select count(*) from public.products)<>before_count or (select shopping_items.lot from public.shopping_items where id=new_item) is not null then raise exception 'Failed receipt partially committed'; end if;
  request:=gen_random_uuid();payload:=payload-'productId'||jsonb_build_object('totalPrice',0);
  result:=public.receive_shopping_item(request,new_item,payload); lot:=(result->>'lotId')::uuid;
  select inventory_lots.product into plain_product from public.inventory_lots where id=lot;
  if not exists(select 1 from public.inventory_lots where id=lot and total_cost=0 and out_of_pocket_cost=0) then raise exception 'Free price became unknown'; end if;
  perform public.undo_inventory_receipt(gen_random_uuid(),lot);
  if not exists(select 1 from public.products where id=plain_product and brand is null and barcode is null and kcal is null) then raise exception 'Undo removed or invented catalog metadata'; end if;
  insert into saved_receipt values(request,new_item,payload,lot);
  result:=public.receive_shopping_item(gen_random_uuid(),new_item,payload||jsonb_build_object('quantity',300,'productId',product));
  lot:=(result->>'lotId')::uuid;
  insert into public.meal_plans(id,inventory_lot,plan_date,daypart,intent,consume_from_inventory) values(dependent_plan,lot,current_date,'lunch','consume',true);
  begin perform public.undo_inventory_receipt(gen_random_uuid(),lot); raise exception 'Planned receipt undo accepted'; exception when raise_exception then if sqlerrm='Planned receipt undo accepted' then raise; end if; end;
  delete from public.meal_plans where id=dependent_plan;
  prep:=public.prepare_recipe(p_request_id=>gen_random_uuid(),p_recipe=>recipe,p_scale=>1,p_servings=>2,p_location=>'fridge',p_eaten_servings=>0);
  begin perform public.undo_inventory_receipt(gen_random_uuid(),lot); raise exception 'Prepared receipt undo accepted'; exception when raise_exception then if sqlerrm='Prepared receipt undo accepted' then raise; end if; end;
  perform public.undo_prep((prep->>'prepId')::uuid);
  perform public.undo_prep((prep->>'prepId')::uuid);
  if (select remaining_qty from public.inventory_lots where id=lot)<>300 then raise exception 'Prep undo did not restore inputs exactly once'; end if;
  perform public.undo_inventory_receipt(gen_random_uuid(),lot);
  set constraints all immediate;
end $$;
reset role;
-- Revoked session blocks even successful retries; non-owner cannot invoke either action.
delete from auth.sessions where id='99200000-0000-0000-0000-000000000011';
set local role authenticated;
do $$ declare row saved_receipt%rowtype; begin
  select * into row from saved_receipt;
  begin perform public.receive_shopping_item(row.request,row.item,row.payload); raise exception 'Revoked session replay accepted'; exception when insufficient_privilege then null; end;
  begin perform public.undo_inventory_receipt(gen_random_uuid(),row.lot); raise exception 'Revoked session undo accepted'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99200000-0000-0000-0000-000000000002","session_id":"99200000-0000-0000-0000-000000000012"}',true);
do $$ begin
  begin perform public.receive_shopping_item(gen_random_uuid(),gen_random_uuid(),'{}'); raise exception 'Non-owner accepted'; exception when insufficient_privilege then null; end;
  begin perform public.undo_inventory_receipt(gen_random_uuid(),gen_random_uuid()); raise exception 'Non-owner undo accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
