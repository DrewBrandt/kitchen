-- Synthetic, rollback-only integration scenario using actual authenticated RPCs.
begin;
do $$ declare email text; begin
  if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict email;
  insert into auth.users(id,email,email_confirmed_at) values('98390000-0000-0000-0000-000000000001',email,now());
  insert into auth.sessions(id,user_id) values('98390000-0000-0000-0000-000000000011','98390000-0000-0000-0000-000000000001');
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"98390000-0000-0000-0000-000000000001","session_id":"98390000-0000-0000-0000-000000000011"}',true);
set local role authenticated;

-- Typed invalid input and non-finite/null/reversed ranges must reject before any row mutation.
do $$ declare v record; via_wrapper boolean; rejected boolean; snapshot jsonb; begin
 select coalesce(jsonb_agg(to_jsonb(s) order by id),'[]') into snapshot from public.shopping_items s;
 for v in select * from (values
  (null::text,'2026-10-09'),('2026-10-03',null),('2026-10-09','2026-10-03'),
  ('infinity','infinity'),('-infinity','2026-10-09'),('2026-10-03','infinity'),
  ('-infinity','infinity'),('2026-10-03','-infinity'),('not-a-date','2026-10-09')
 ) ranges(first_date,last_date) loop
  foreach via_wrapper in array array[false,true] loop
   rejected:=false;
   begin
    if via_wrapper then perform public.rebuild_shopping_from_plan(v.first_date::date,v.last_date::date);
    else perform public.reconcile_shopping_demand(v.first_date::date,v.last_date::date); end if;
   exception when raise_exception then
    if sqlerrm<>'Choose a valid plan range' then raise; end if; rejected:=true;
   when invalid_datetime_format then
    if v.first_date is distinct from 'not-a-date' then raise; end if; rejected:=true;
   end;
   if not rejected then raise exception 'Invalid range accepted: %, %',v.first_date,v.last_date; end if;
   if snapshot is distinct from (select coalesce(jsonb_agg(to_jsonb(s) order by id),'[]') from public.shopping_items s)
    then raise exception 'Invalid range changed shopping rows'; end if;
  end loop;
 end loop;
end $$;

do $$ declare
 u uuid; f uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); lot uuid:=gen_random_uuid();
 recipe_id uuid; recipe_plan uuid; plans uuid[]:='{}'; pid uuid; item uuid; generic uuid; response jsonb; receipt uuid;
 n numeric; ids uuid[]; checked timestamptz:=now()-interval '1 day'; x record; other_food uuid; other_product uuid;
begin
 select id into strict u from public.measure_conversions where short_name='ct';
 insert into public.base_foods(id,name,measure_style,display_unit) values(f,'Weekly yogurt','discrete',u);
 insert into public.products(id,food,name,package_qty_base,package_unit,serving_qty_base,nutrition_basis_qty,servings_per_package)
 values(a,f,'Required yogurt',1,u,1,1,1),(b,f,'Alternative yogurt',1,u,1,1,1);
 insert into public.inventory_lots(id,product,initial_qty,remaining_qty,location,acquisition_type,out_of_pocket_cost,paid_by,cost_source,total_cost,price_as_of) values(lot,a,2,2,'fridge','gift',0,'Fixture','Synthetic gift',0,current_date);
 for i in 0..4 loop
  pid:=(public.owner_append_plan(gen_random_uuid(),jsonb_build_object('intent','consume','product',a,'planned_servings',1,'plan_date',date '2026-10-03'+i,'daypart','lunch'))#>>'{planIds,0}')::uuid;
  plans:=array_append(plans,pid);
 end loop;
 perform public.rebuild_shopping_from_plan('2026-10-03','2026-10-09');
 select id into strict item from public.shopping_items where food=f and generated_product=a and generated_active;
 if (select generated_shortage_base from public.shopping_items where id=item)<>3 then raise exception 'Five occasions minus two stock must need three'; end if;
 perform public.rebuild_shopping_from_plan('2026-10-03','2026-10-09');
 if (select count(*) from public.shopping_items where food=f)<>1 then raise exception 'Repeated rebuild duplicated scope'; end if;
 recipe_id:=(public.owner_create_recipe(gen_random_uuid(),jsonb_build_object('name','Yogurt recipe','servings',4,'ingredients',jsonb_build_array(jsonb_build_object('ingredient',f,'qty',4,'unit',u))))->>'id')::uuid;
 recipe_plan:=(public.owner_append_plan(gen_random_uuid(),jsonb_build_object('recipe',recipe_id,'scale_factor',1,'planned_servings',1,'plan_date','2026-10-03','daypart','dinner'))#>>'{planIds,0}')::uuid;
 perform public.rebuild_shopping_from_plan('2026-10-03','2026-10-09');
 select id into strict generic from public.shopping_items where food=f and generated_product is null and generated_active;
 if (select generated_shortage_base from public.shopping_items where id=generic)<>4 then raise exception 'Shared stock spent twice'; end if;
 update public.shopping_items set pinned_product=b,note='Keep generic preference' where id=generic;
 update public.shopping_items set pinned_product=b,note='Keep required preference',checked_at=checked,qty_needed=99,quantity_label='My quantity' where id=item;
 perform public.rebuild_shopping_from_plan('2026-10-03','2026-10-09');
 if (select sum(generated_shortage_base) from public.shopping_items where food=f and generated_active)<>7 then raise exception 'Shopping preference changed allocation'; end if;
 -- Different-product receipt records the truth but cannot satisfy required-product demand.
 response:=public.receive_shopping_item(gen_random_uuid(),item,jsonb_build_object('productId',b,'quantity',3,'unit','ct','totalPrice',3));receipt:=(response->>'lotId')::uuid;
 if (select generated_shortage_base from public.shopping_items where id=item)<>3 or (select generated_shortage_base from public.shopping_items where id=generic)<>1 then raise exception 'Wrong-product receipt misallocated'; end if;
 perform public.undo_inventory_receipt(gen_random_uuid(),receipt);
 if (select generated_shortage_base from public.shopping_items where id=generic)<>4 or not exists(select 1 from public.shopping_items where id=item and generated_shortage_base=3 and checked_at=checked and note='Keep required preference' and qty_needed=99 and quantity_label='My quantity' and pinned_product=b and shopping_items.lot is null) then raise exception 'Undo lost forecast or manual state'; end if;
 response:=public.receive_shopping_item(gen_random_uuid(),item,jsonb_build_object('productId',a,'quantity',3,'unit','ct','totalPrice',0));receipt:=(response->>'lotId')::uuid;
 if (select generated_active from public.shopping_items where id=item) or (select generated_shortage_base from public.shopping_items where id=generic)<>4 then raise exception 'Matching receipt did not satisfy only required demand'; end if;
 perform public.undo_inventory_receipt(gen_random_uuid(),receipt);
 perform public.undo_inventory_receipt(gen_random_uuid(),receipt);
 if (select generated_shortage_base from public.shopping_items where id=item)<>3 then raise exception 'Repeated receipt undo changed shortage'; end if;
 -- Recipe ingredient pin is a hard requirement, unlike the shopping preference.
 update public.recipe_ingredients set pinned_product=b where recipe_ingredients.recipe=recipe_id;
 perform public.rebuild_shopping_from_plan('2026-10-03','2026-10-09');
 if not exists(select 1 from public.shopping_items where food=f and generated_product=b and generated_shortage_base=4 and generated_active) or (select generated_active from public.shopping_items where id=generic) then raise exception 'Recipe pin not respected'; end if;
 update public.recipe_ingredients set pinned_product=null where recipe_ingredients.recipe=recipe_id;
 -- Actual fulfillment removes its portion and its consumed stock together.
 ids:=public.consume_planned_meals(gen_random_uuid(),array[plans[1]],array[1::numeric],now());
 update public.planned_consumptions set status='cancelled' where meal_plan=plans[2];
 update public.meal_plans set consume_from_inventory=false where id=plans[3];
 update public.meal_plans set status='skipped' where id=plans[4];
 perform public.rebuild_shopping_from_plan('2026-10-03','2026-10-09');
 if (select generated_active from public.shopping_items where id=item) or (select generated_shortage_base from public.shopping_items where id=generic)<>4 then raise exception 'Fulfilled/cancelled/external/skipped counted'; end if;
 -- Exact lot claims use their own stock once; their deficit is not a substitute purchase.
 delete from public.meal_plans where id=plans[5];
 perform public.owner_append_plan(gen_random_uuid(),jsonb_build_object('intent','consume','inventory_lot',lot,'planned_servings',5,'plan_date','2026-10-03','daypart','snack'));
 perform public.rebuild_shopping_from_plan('2026-10-03','2026-10-09');
 if (select generated_shortage_base from public.shopping_items where id=generic)<>4 or (select generated_active from public.shopping_items where id=item) then raise exception 'Exact source silently substituted or stock spent twice'; end if;
 -- Prepared leftovers don't generate ingredients again.
 perform public.owner_append_plan(gen_random_uuid(),jsonb_build_object('intent','leftover','source_group_id',(select group_id from public.meal_plans where id=recipe_plan),'planned_servings',2,'plan_date','2026-10-04','daypart','dinner'));
 perform public.rebuild_shopping_from_plan('2026-10-03','2026-10-09');
 if (select generated_shortage_base from public.shopping_items where id=generic)<>4 then raise exception 'Leftovers expanded'; end if;
 insert into public.inventory_events(lot,quantity_delta,reason,note) values(lot,6,'adjust','Synthetic preparation stock');
 response:=public.prepare_recipe(gen_random_uuid(),recipe_id,1,4,'fridge',recipe_plan,0,now());
 perform public.owner_append_plan(gen_random_uuid(),jsonb_build_object('intent','consume','inventory_lot',(response->>'lotId')::uuid,'planned_servings',2,'plan_date','2026-10-05','daypart','snack'));
 perform public.rebuild_shopping_from_plan('2026-10-03','2026-10-09');
 if exists(select 1 from public.shopping_items where food=f and generated_active) then raise exception 'Prepared source or exact prepared lot expanded ingredients'; end if;
 for x in select * from (values('weight','g',150::numeric,300::numeric),('volume','fl oz',8::numeric,16::numeric)) v(style,unit,portion,stock) loop
  other_food:=gen_random_uuid();other_product:=gen_random_uuid();select id into strict u from public.measure_conversions where short_name=x.unit;
  insert into public.base_foods(id,name,measure_style,display_unit) values(other_food,'Forecast unit '||x.style,x.style::public.measure_style,u);
  insert into public.products(id,food,name,package_qty_base,package_unit,serving_qty_base,nutrition_basis_qty,servings_per_package) values(other_product,other_food,'Unit product',x.portion*4,u,x.portion,x.portion,4);
  insert into public.inventory_lots(product,initial_qty,remaining_qty,acquisition_type,out_of_pocket_cost,paid_by,cost_source,total_cost,price_as_of) values(other_product,x.stock,x.stock,'gift',0,'Fixture','Synthetic gift',0,current_date);
  for i in 0..4 loop perform public.owner_append_plan(gen_random_uuid(),jsonb_build_object('intent','consume','product',other_product,'planned_servings',1,'plan_date',date '2026-10-03'+i,'daypart','lunch'));end loop;
  perform public.rebuild_shopping_from_plan('2026-10-03','2026-10-09');
  if not exists(select 1 from public.shopping_items where food=other_food and generated_product=other_product and generated_shortage_base=5*x.portion-x.stock and abs(public.to_base_quantity(food,qty_needed,unit)-(5*x.portion-x.stock))<0.0000001) then raise exception 'Canonical/display unit mismatch: %, expected %, rows %',x.style,5*x.portion-x.stock,(select jsonb_agg(to_jsonb(si)) from public.shopping_items si where food=other_food); end if;
 end loop;
 set constraints all immediate;
end $$;
rollback;
select 'PASS: weekly pantry forecasts, source identity, shared stock, preferences, receipts/undo, exclusions and units';
