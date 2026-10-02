-- Disposable database only. Actual API roles, synthetic owner and sessions.
begin;
do $$ declare email text; begin
  if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict email;
  insert into auth.users(id,email,email_confirmed_at) values
    ('99500000-0000-0000-0000-000000000001',email,now()),
    ('99500000-0000-0000-0000-000000000002','not-owner@example.test',now());
  insert into auth.sessions(id,user_id) values
    ('99500000-0000-0000-0000-000000000011','99500000-0000-0000-0000-000000000001'),
    ('99500000-0000-0000-0000-000000000012','99500000-0000-0000-0000-000000000002');
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99500000-0000-0000-0000-000000000001","session_id":"99500000-0000-0000-0000-000000000011"}',true);
set local role authenticated;

do $$ declare recipe_id uuid; prep_id uuid; lot_id uuid; request uuid:=gen_random_uuid(); event_id uuid; before_nutrition jsonb; before_eaten numeric; before_logs integer; price numeric; food_id uuid; product_id uuid; source_id uuid; unit_id uuid; begin
 recipe_id:=(public.owner_create_recipe(gen_random_uuid(),'{"name":"Discard test","servings":4,"ingredients":[]}')->>'id')::uuid;
 foreach price in array array[12::numeric,0::numeric,null::numeric] loop
 select id into strict unit_id from public.measure_conversions where short_name='g';
 insert into public.base_foods(name,measure_style,display_unit) values('Discard ingredient '||gen_random_uuid(),'weight',unit_id) returning id into food_id;
 insert into public.products(food,name,package_qty_base,package_unit,serving_qty_base,nutrition_basis_qty,kcal) values(food_id,'Test food '||gen_random_uuid(),400,unit_id,100,100,200) returning id into product_id;
 insert into public.inventory_lots(product,initial_qty,remaining_qty,total_cost,location) values(product_id,400,400,price,'fridge') returning id into source_id;
 insert into public.preps(recipe,actual_yield_qty) values(recipe_id,4) returning id into prep_id;
 insert into public.inventory_events(lot,quantity_delta,reason,prep) values(source_id,-400,'prep',prep_id);
 insert into public.inventory_lots(prep,initial_qty,remaining_qty,total_cost,location) values(prep_id,4,4,price,'fridge') returning id into lot_id;
 select coalesce(jsonb_agg(to_jsonb(n)),'[]') into before_nutrition from public.daily_nutrition n;
 select sum(cost) into before_eaten from public.inventory_event_costs where reason='eaten' and voided_at is null;
 select count(*) into before_logs from public.food_logs;
 request:=gen_random_uuid();
 event_id:=public.set_inventory_lot_quantity(request,lot_id,3,true,'Dropped on floor');
 if public.set_inventory_lot_quantity(request,lot_id,3,true,'Dropped on floor') is distinct from event_id then raise exception 'Retry changed event'; end if;
 if (select remaining_qty from public.inventory_lots where id=lot_id)<>3 then raise exception 'Discard did not reduce stock once'; end if;
 if not exists(select 1 from public.inventory_events where id=event_id and quantity_delta=-1 and reason='waste' and note='Dropped on floor' and food_log is null) then raise exception 'Waste event incorrect'; end if;
 if (select cost from public.inventory_event_costs where inventory_event_id=event_id) is distinct from price/4 then raise exception 'Waste value or unknown/zero distinction lost'; end if;
 if (select coalesce(jsonb_agg(to_jsonb(n)),'[]') from public.daily_nutrition n) is distinct from before_nutrition or (select sum(cost) from public.inventory_event_costs where reason='eaten' and voided_at is null) is distinct from before_eaten or (select count(*) from public.food_logs)<>before_logs then raise exception 'Discard changed consumption'; end if;
 perform public.undo_inventory_adjustment(event_id);
 perform public.undo_inventory_adjustment(event_id);
 if (select remaining_qty from public.inventory_lots where id=lot_id)<>4 or exists(select 1 from public.inventory_event_costs where inventory_event_id=event_id and voided_at is null) then raise exception 'Undo did not restore stock and remove active waste'; end if;
 end loop;
end $$;
rollback;
select 'PASS: partial prepared waste, price/zero/unknown, unchanged consumption, retry and undo';
