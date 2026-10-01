-- Synthetic fixtures only. Every row and JWT setting is rolled back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare
  unit_id uuid;
  known_food uuid := gen_random_uuid();
  unknown_food uuid := gen_random_uuid();
  output_food uuid := gen_random_uuid();
  known_product uuid := gen_random_uuid();
  unknown_product uuid := gen_random_uuid();
  recipe_id uuid := gen_random_uuid();
  prep_id uuid;
  lot_id uuid;
  nutrition jsonb;
  imported jsonb;
  imported_id uuid;
begin
  select id into strict unit_id from public.measure_conversions where short_name = 'g';
  insert into public.base_foods(id,name,measure_style,display_unit,nutrition_basis_qty,kcal,protein_g,sodium_mg)
  values (known_food,'QA known nutrition','weight',unit_id,100,100,10,0),
    (unknown_food,'QA incomplete nutrition','weight',unit_id,100,null,20,0),
    (output_food,'QA output','weight',unit_id,100,null,null,null);
  insert into public.products(id,food,name,package_qty_base,package_unit,serving_qty_base,nutrition_basis_qty,kcal,protein_g,sodium_mg,nutrition_is_estimated,nutrition_source)
  values (known_product,known_food,'QA known product',200,unit_id,100,100,100,10,0,true,'QA ingredient estimate'),
    (unknown_product,unknown_food,'QA unknown calories',200,unit_id,100,100,null,20,0,false,'QA label');
  insert into public.inventory_lots(product,initial_qty,remaining_qty,total_cost,out_of_pocket_cost,paid_by,cost_source,price_as_of,acquisition_type,location)
  values (known_product,200,200,2,2,'self','QA fixture',current_date,'grocery','pantry'),
    (unknown_product,200,200,2,2,'self','QA fixture',current_date,'grocery','pantry');
  insert into public.recipes(id,name,servings,output_food,yield_qty,instructions)
  values (recipe_id,'QA mixed nutrition recipe',2,output_food,2,'[]');
  insert into public.recipe_ingredients(recipe,ingredient,qty,unit)
  values (recipe_id,known_food,100,unit_id),(recipe_id,unknown_food,100,unit_id);
  prep_id := public.cook_recipe(recipe_id,1,2,'fridge');
  perform public.refresh_prepared_lot_provenance(prep_id);
  select id into strict lot_id from public.inventory_lots where prep = prep_id;
  nutrition := public.lot_nutrition_json(lot_id);
  if (nutrition->>'kcal') is not null then raise exception 'Unknown ingredient calories were silently omitted: %', nutrition; end if;
  if (nutrition->>'protein_g')::numeric <> 15 then raise exception 'Known protein should remain 15g per serving: %', nutrition; end if;
  if (nutrition->>'sodium_mg')::numeric <> 0 then raise exception 'Known zero sodium must remain zero'; end if;
  if not (select nutrition_is_estimated from public.preps where id=prep_id) then raise exception 'Estimated ingredient provenance lost'; end if;
  if (select nutrition_source from public.preps where id=prep_id) not like '%QA ingredient estimate%' then raise exception 'Ingredient source lost'; end if;
  -- Missing import prices must survive the deferred provenance check, not become free food.
  imported := public.bulk_import_inventory(jsonb_build_array(jsonb_build_object('productId',unknown_product,'packages',1)),'pantry');
  imported_id := (imported #>> '{lotIds,0}')::uuid;
  if not exists(select 1 from public.inventory_lots where id=imported_id and total_cost is null and out_of_pocket_cost is null and cost_is_estimated) then raise exception 'Unknown import price became zero or lost estimate flag'; end if;
  -- Known prices still require dated provenance even for estimates.
  begin
    update public.inventory_lots set total_cost=1, price_as_of=null where id=imported_id;
    set constraints all immediate;
    raise exception 'Undated known price unexpectedly accepted';
  exception when check_violation then
    null;
  end;
  -- Recipe override remains an explicit complete source for that nutrient only.
  update public.recipes set override_kcal=400, override_basis_qty=2 where id=recipe_id;
  nutrition := public.lot_nutrition_json(lot_id);
  if (nutrition->>'kcal')::numeric <> 200 then raise exception 'Explicit recipe override was lost'; end if;
end;
$$;
set constraints all immediate;
select 'Prepared nutrition uncertainty checks passed' as result;
rollback;
