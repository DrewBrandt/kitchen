-- Narrow two-append regression. Disposable synthetic records, rolled back.
begin;
do $$ begin if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if; end $$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$ declare
  grams uuid; count_unit uuid; chicken uuid; oregano uuid; naan uuid; product uuid; naan_product uuid;
  recipe uuid; prep_plan uuid; leftover_plan uuid; naan_plan uuid; manual uuid; chicken_item uuid; oregano_item uuid;
  result jsonb; manual_before jsonb; naan_before jsonb; progress_before jsonb; total_before bigint;
begin
  select id into strict grams from public.measure_conversions where short_name='g';
  select id into strict count_unit from public.measure_conversions where short_name='ct';
  insert into public.base_foods(name,measure_style,display_unit) values('Boundary chicken','weight',grams) returning id into chicken;
  insert into public.base_foods(name,measure_style,display_unit) values('Boundary oregano','weight',grams) returning id into oregano;
  insert into public.base_foods(name,measure_style,display_unit) values('Boundary naan','discrete',count_unit) returning id into naan;
  insert into public.products(food,name,package_qty_base,package_unit) values(chicken,'Boundary chicken pack',900,grams) returning id into product;
  insert into public.products(food,name,package_qty_base,package_unit,serving_qty_base) values(naan,'Boundary naan pack',1,count_unit,1) returning id into naan_product;
  insert into public.inventory_lots(product,initial_qty,remaining_qty,location) values(product,900,900,'freezer'),(naan_product,1,1,'freezer');
  insert into public.recipes(name,servings,instructions) values('Boundary dinner',6,'[]') returning id into recipe;
  insert into public.recipe_ingredients(recipe,ingredient,qty,unit) values(recipe,chicken,1000,grams),(recipe,oregano,0.3,grams);
  insert into public.meal_plans(plan_date,daypart,product,scale_factor,intent,consume_from_inventory)
    values('2026-10-05','dinner',naan_product,1,'consume',true) returning id into naan_plan;
  update public.planned_consumptions set servings=1.5 where meal_plan=naan_plan;
  select to_jsonb(p) into naan_before from public.meal_plans p where id=naan_plan;
  insert into public.shopping_items(free_text,source,note) values('Keep manual item','manual','Do not overwrite') returning id into manual;
  select to_jsonb(s) into manual_before from public.shopping_items s where id=manual;
  result:=public.gpt_save_plan('append',null,jsonb_build_array(jsonb_build_object('date','2026-10-04','slot','dinner','source','recipe','sourceId',recipe,'intent','prepare','scaleFactor',1,'plannedServings',2)));
  prep_plan:=(result#>>'{planIds,0}')::uuid;
  select id into strict chicken_item from public.shopping_items where food=chicken and generated_active;
  select id into strict oregano_item from public.shopping_items where food=oregano and generated_active;
  update public.shopping_items set checked_at=now(),note='Keep checked progress',pinned_product=product,qty_needed=123,quantity_label='My amount' where id=chicken_item;
  select jsonb_build_object('id',id,'checked',checked_at,'note',note,'pin',pinned_product,'qty',qty_needed,'label',quantity_label,'received',received_qty_base,'lot',lot) into progress_before from public.shopping_items where id=chicken_item;
  result:=public.gpt_save_plan('append',null,jsonb_build_array(jsonb_build_object('date','2026-10-05','slot','dinner','source','recipe','sourceId',recipe,'intent','leftover','sourceMealPlanId',prep_plan,'scaleFactor',1,'plannedServings',2)));
  leftover_plan:=(result#>>'{planIds,0}')::uuid;
  if not exists(select 1 from public.shopping_items where id=chicken_item and generated_active and generated_shortage_base=100 and generated_from='2026-10-04' and generated_through='2026-10-11')
    or not exists(select 1 from public.shopping_items where id=oregano_item and generated_active and generated_shortage_base=0.3)
    or not exists(select 1 from public.shopping_items where food=naan and generated_active and generated_shortage_base=0.5) then raise exception 'Cross-week source shortages missing or double-counted'; end if;
  if progress_before is distinct from (select jsonb_build_object('id',id,'checked',checked_at,'note',note,'pin',pinned_product,'qty',qty_needed,'label',quantity_label,'received',received_qty_base,'lot',lot) from public.shopping_items where id=chicken_item)
    or manual_before is distinct from (select to_jsonb(s) from public.shopping_items s where id=manual)
    or naan_before is distinct from (select to_jsonb(p) from public.meal_plans p where id=naan_plan) then raise exception 'Existing progress/manual item/plan changed'; end if;
  select count(*) into total_before from public.shopping_items;
  perform public.rebuild_shopping_from_plan('2026-10-05','2026-10-11');
  if (select count(*) from public.shopping_items)<>total_before then raise exception 'Rebuild duplicated or deleted rows'; end if;
  -- Made source preparations must not generate raw ingredients again; retained
  -- inactive rows continue carrying checks/notes/quantity and receipt identity.
  update public.meal_plans set status='made',made_at=now() where id=prep_plan;
  perform public.rebuild_shopping_from_plan('2026-10-05','2026-10-11');
  if exists(select 1 from public.shopping_items where id in(chicken_item,oregano_item) and generated_active)
    or (select count(*) from public.shopping_items)<>total_before
    or not exists(select 1 from public.shopping_items where id=chicken_item and checked_at is not null and note='Keep checked progress' and qty_needed=123) then raise exception 'Made source regenerated ingredients or lost retained history'; end if;
  raise notice 'PASS: Sunday preparation/Monday leftovers retain source shortages, manual rows, progress and existing plans without duplicate demand';
end $$;
rollback;
