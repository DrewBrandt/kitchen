-- Disposable transaction: existing preparation provenance and undo, no migrations.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$ declare food uuid:=gen_random_uuid(); product uuid:=gen_random_uuid(); recipe uuid:=gen_random_uuid(); ingredient uuid:=gen_random_uuid(); source_lot uuid:=gen_random_uuid(); unit uuid; result jsonb; prepared uuid; eaten uuid; begin
 select id into strict unit from public.measure_conversions where short_name='g';
 insert into public.base_foods(id,name,measure_style,display_unit) values(food,'Paid cost test','weight',unit);
 insert into public.products(id,food,name,package_qty_base,package_unit,serving_qty_base,nutrition_basis_qty,kcal) values(product,food,'Paid ingredient',400,unit,100,100,200);
 insert into public.inventory_lots(id,product,initial_qty,remaining_qty,location,total_cost,out_of_pocket_cost,paid_by,cost_source,price_as_of,acquisition_type) values(source_lot,product,400,400,'fridge',20,8,'self','Test receipt',current_date,'grocery');
 insert into public.recipes(id,name,servings,instructions) values(recipe,'Paid leftovers',4,'[]');
 insert into public.recipe_ingredients(id,recipe,ingredient,qty,unit) values(ingredient,recipe,food,200,unit);
 result:=public.prepare_recipe(gen_random_uuid(),recipe,1,4,'fridge',null,0,now());
 prepared:=(result->>'lotId')::uuid;
 if not exists(select 1 from public.inventory_lots where id=prepared and out_of_pocket_cost=4 and total_cost=10 and initial_qty=4) then raise exception 'Ingredient paid cost was not carried forward separately from full value'; end if;
 eaten:=public.consume_prepared_batch(prepared,1,null,now());
 if (select sum(-e.quantity_delta*l.out_of_pocket_cost/l.initial_qty) from public.inventory_events e join public.inventory_lots l on l.id=e.lot where e.food_log=eaten and e.reason='eaten' and e.voided_at is null)<>1 then raise exception 'Leftover portion paid cost incorrect'; end if;
 if (select out_of_pocket_cost from public.inventory_lots where id=source_lot)<>8 then raise exception 'Consumption rewrote purchase payment'; end if;
 perform public.void_food_log(eaten);
 if exists(select 1 from public.inventory_events where food_log=eaten and voided_at is null) or (select remaining_qty from public.inventory_lots where id=prepared)<>4 then raise exception 'Undo did not remove consumption and restore stock'; end if;
end $$;
set constraints all immediate;
rollback;
select 'PASS: ingredient paid cost carried into leftovers, allocated per portion, payment unchanged, undo';
