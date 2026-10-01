-- Explicit future preparation references; already cooked food uses inventory_lot.
-- Historical text groups are not guessed/backfilled. RESTRICT prevents deleting
-- a source while future leftover plans still depend on its preparation.
alter table public.meal_plans add column source_meal_plan uuid
  references public.meal_plans(id) on delete restrict;
alter table public.meal_plans add constraint meal_plans_leftover_source_check
  check (source_meal_plan is null or (intent = 'leftover' and source_meal_plan <> id));
create index meal_plans_source_meal_plan_idx on public.meal_plans(source_meal_plan)
  where source_meal_plan is not null;

create or replace function public.consume_planned_meals(
  p_meal_plans uuid[],
  p_servings numeric[],
  p_occurred_at timestamptz default now()
)
returns uuid[]
language plpgsql
set search_path = ''
as $$
declare
  plan_id uuid;
  eaten_servings numeric;
  plan_row public.meal_plans%rowtype;
  consumption_row public.planned_consumptions%rowtype;
  selected_lot public.inventory_lots%rowtype;
  product_row public.products%rowtype;
  product_snapshot jsonb;
  quantity_to_consume numeric;
  log_id uuid;
  log_ids uuid[] := array[]::uuid[];
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may consume planned items' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_meal_plans), 0) = 0 then raise exception 'Choose at least one planned item'; end if;
  if cardinality(p_meal_plans) <> coalesce(cardinality(p_servings), 0) then
    raise exception 'Every planned item needs an eaten serving quantity';
  end if;

  for plan_index in 1..cardinality(p_meal_plans) loop
    plan_id := p_meal_plans[plan_index];
    eaten_servings := p_servings[plan_index];
    if eaten_servings is null or eaten_servings <= 0 then raise exception 'Eaten servings must be positive'; end if;

    select * into plan_row from public.meal_plans where id = plan_id for update;
    if not found then raise exception 'Planned item does not exist'; end if;
    select * into consumption_row from public.planned_consumptions where meal_plan = plan_id for update;
    if not found then raise exception 'Planned consumption does not exist'; end if;
    if consumption_row.status = 'fulfilled' then
      raise exception 'The planned portion of % has already been eaten', coalesce(plan_row.name, plan_row.recipe::text, plan_row.product::text, plan_row.inventory_lot::text);
    end if;

    if plan_row.intent = 'consume' then
      if plan_row.product is not null and plan_row.consume_from_inventory is false then
        select * into product_row from public.products
        where id = plan_row.product and archived_at is null;
        if not found then raise exception 'The planned product is no longer available'; end if;
        product_snapshot := public.product_portion_snapshot(product_row.id, eaten_servings);

        insert into public.food_logs(
          label, kind, product, servings, occurred_at,
          kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
          nutrition_is_estimated, nutrition_source,
          cost, cost_is_estimated, cost_source, price_as_of, note
        ) values (
          coalesce(plan_row.name, concat_ws(' · ', nullif(product_row.brand, ''), product_row.name)),
          'product', product_row.id, eaten_servings, p_occurred_at,
          nullif(product_snapshot #>> '{nutrition,calories}', '')::numeric,
          nullif(product_snapshot #>> '{nutrition,proteinG}', '')::numeric,
          nullif(product_snapshot #>> '{nutrition,carbsG}', '')::numeric,
          nullif(product_snapshot #>> '{nutrition,fatG}', '')::numeric,
          nullif(product_snapshot #>> '{nutrition,fiberG}', '')::numeric,
          nullif(product_snapshot #>> '{nutrition,sugarG}', '')::numeric,
          nullif(product_snapshot #>> '{nutrition,sodiumMg}', '')::numeric,
          coalesce((product_snapshot ->> 'nutritionEstimated')::boolean, false),
          nullif(product_snapshot ->> 'nutritionSource', ''),
          nullif(product_snapshot ->> 'estimatedCost', '')::numeric,
          coalesce((product_snapshot ->> 'costIsEstimated')::boolean, false),
          nullif(product_snapshot ->> 'costSource', ''),
          nullif(product_snapshot ->> 'priceAsOf', '')::date,
          plan_row.note
        ) returning id into log_id;

        update public.products set use_count = use_count + 1, last_used_at = p_occurred_at
        where id = product_row.id;
        update public.planned_consumptions
        set status = 'fulfilled', food_log = log_id, updated_at = now()
        where id = consumption_row.id;
        log_ids := array_append(log_ids, log_id);
        product_row := null;
        continue;
      end if;

      if plan_row.inventory_lot is not null then
        select * into selected_lot from public.inventory_lots
        where id = plan_row.inventory_lot for update;
        if found and selected_lot.prep is not null then
          log_id := public.consume_prepared_batch(selected_lot.id, eaten_servings, plan_id, p_occurred_at);
          log_ids := array_append(log_ids, log_id);
          selected_lot := null;
          continue;
        end if;
        if not found or selected_lot.product is null then raise exception 'The selected inventory lot is no longer available'; end if;
        select * into product_row from public.products
        where id = selected_lot.product and archived_at is null;
      else
        select * into product_row from public.products
        where id = plan_row.product and archived_at is null;
        if not found then raise exception 'The planned product is no longer available'; end if;
        quantity_to_consume := case
          when product_row.servings_per_package is not null and product_row.servings_per_package > 0
            and product_row.package_qty_base > 0 and product_row.serving_qty_base is not null
            and product_row.nutrition_basis_qty is not null
            and abs(product_row.nutrition_basis_qty - product_row.serving_qty_base) < 0.000001
            then eaten_servings * product_row.package_qty_base / product_row.servings_per_package
          else eaten_servings * coalesce(nullif(product_row.serving_qty_base, 0), 1) end;
        select lot.* into selected_lot from public.inventory_lots lot
        where lot.product = product_row.id and lot.prep is null
          and lot.remaining_qty >= quantity_to_consume
        order by lot.use_by asc nulls last, lot.acquired_at, lot.id
        limit 1 for update of lot;
      end if;

      if selected_lot.id is null or product_row.id is null then
        raise exception 'No available lot has enough for this planned portion';
      end if;
      if quantity_to_consume is null then
        quantity_to_consume := case
          when product_row.servings_per_package is not null and product_row.servings_per_package > 0
            and product_row.package_qty_base > 0 and product_row.serving_qty_base is not null
            and product_row.nutrition_basis_qty is not null
            and abs(product_row.nutrition_basis_qty - product_row.serving_qty_base) < 0.000001
            then eaten_servings * product_row.package_qty_base / product_row.servings_per_package
          else eaten_servings * coalesce(nullif(product_row.serving_qty_base, 0), 1) end;
      end if;
      if selected_lot.remaining_qty < quantity_to_consume then
        raise exception 'The selected lot has only % servings remaining', public.product_servings_for_quantity(product_row.id, selected_lot.remaining_qty);
      end if;

      log_id := public.consume_inventory_lot(selected_lot.id, quantity_to_consume, p_occurred_at);
      update public.planned_consumptions
      set status = 'fulfilled', food_log = log_id, updated_at = now()
      where id = consumption_row.id;
      log_ids := array_append(log_ids, log_id);
      quantity_to_consume := null; selected_lot := null; product_row := null;
      continue;
    end if;

    if plan_row.status <> 'made' and plan_row.intent <> 'leftover' then
      raise exception 'Prepare the planned recipe before logging it as eaten';
    end if;
    selected_lot := null;
    if plan_row.intent = 'leftover' then
      select lot.* into selected_lot
      from public.inventory_lots lot
      join public.preps prep on prep.id = lot.prep and prep.voided_at is null
      join public.meal_plans source_plan on source_plan.id = prep.meal_plan
      where (source_plan.id = plan_row.source_meal_plan
          or (plan_row.source_meal_plan is null and source_plan.group_id = plan_row.leftover_of_group_id))
        and source_plan.recipe = plan_row.recipe and lot.remaining_qty >= eaten_servings
      order by prep.prepped_at desc, lot.id limit 1 for update of lot;
    else
      select lot.* into selected_lot
      from public.inventory_lots lot
      join public.preps prep on prep.id = lot.prep and prep.voided_at is null
      where prep.meal_plan = plan_id and lot.remaining_qty >= eaten_servings
      order by prep.prepped_at desc, lot.id limit 1 for update of lot;
    end if;
    if selected_lot.id is null then raise exception 'No prepared batch has enough servings for the amount eaten'; end if;
    log_id := public.consume_prepared_batch(selected_lot.id, eaten_servings, plan_id, p_occurred_at);
    log_ids := array_append(log_ids, log_id);
  end loop;
  return log_ids;
end;
$$;


create or replace function public.gpt_save_plan(
  p_mode text,
  p_week_start date,
  p_entries jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry jsonb;
  plan_id uuid;
  source_type text;
  plan_intent text;
  consume_inventory boolean;
  entry_date date;
  inserted_ids uuid[] := array[]::uuid[];
  inserted_count integer := 0;
  grocery_count integer := 0;
  first_date date;
  last_date date;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if p_mode not in ('append', 'replaceWeek') then raise exception 'mode must be append or replaceWeek'; end if;
  if jsonb_typeof(p_entries) <> 'array' then raise exception 'entries must be an array'; end if;
  if p_mode = 'replaceWeek' and p_week_start is null then raise exception 'weekStart is required for replaceWeek'; end if;
  if p_mode = 'append' and jsonb_array_length(p_entries) = 0 then raise exception 'append requires at least one entry'; end if;

  if p_mode = 'replaceWeek' then
    delete from public.meal_plans where plan_date between p_week_start and p_week_start + 6;
  end if;

  for entry in select value from jsonb_array_elements(p_entries)
  loop
    entry_date := (entry ->> 'date')::date;
    if entry_date is null then raise exception 'Every plan entry needs a date'; end if;
    if p_mode = 'replaceWeek' and entry_date not between p_week_start and p_week_start + 6 then
      raise exception 'Plan entry date is outside the requested week';
    end if;
    if coalesce((entry ->> 'plannedServings')::numeric, 0) <= 0 then
      raise exception 'plannedServings must be positive';
    end if;
    if coalesce((entry ->> 'scaleFactor')::numeric, 0) <= 0 then
      raise exception 'scaleFactor must be positive';
    end if;

    source_type := entry ->> 'source';
    if source_type not in ('recipe', 'meal', 'product', 'inventoryLot') then
      raise exception 'source must be recipe, meal, product, or inventoryLot';
    end if;
    plan_intent := coalesce(nullif(entry ->> 'intent', ''),
      case when source_type in ('product', 'inventoryLot') then 'consume' else 'prepare' end);

    if source_type = 'product' then
      if not entry ? 'consumeFromInventory' or jsonb_typeof(entry -> 'consumeFromInventory') <> 'boolean' then
        raise exception 'A product plan requires consumeFromInventory';
      end if;
      consume_inventory := (entry ->> 'consumeFromInventory')::boolean;
    elsif source_type = 'inventoryLot' then
      if entry ? 'consumeFromInventory' and (
        jsonb_typeof(entry -> 'consumeFromInventory') <> 'boolean'
        or (entry ->> 'consumeFromInventory')::boolean is not true
      ) then
        raise exception 'An exact inventory lot must consume from inventory';
      end if;
      consume_inventory := true;
    else
      if entry ? 'consumeFromInventory' then
        raise exception 'Recipe and meal plans cannot set consumeFromInventory';
      end if;
      consume_inventory := null;
    end if;

    if source_type in ('product', 'inventoryLot') and plan_intent <> 'consume' then
      raise exception 'Product and inventory-lot plans require consume intent';
    end if;
    if source_type in ('recipe', 'meal') and plan_intent not in ('prepare', 'leftover') then
      raise exception 'Recipe and meal plans require prepare or leftover intent';
    end if;

    if plan_intent = 'leftover' and not exists (
      select 1 from public.meal_plans source
      where source.id = nullif(entry ->> 'sourceMealPlanId', '')::uuid
        and source.intent = 'prepare' and source.recipe = (entry ->> 'sourceId')::uuid
    ) then
      raise exception 'Choose an explicit sourceMealPlanId for this recipe; already cooked food should use inventoryLot';
    end if;

    insert into public.meal_plans(
      plan_date, daypart, scheduled_time, meal, recipe, product, inventory_lot,
      consume_from_inventory, scale_factor, status, name, emoji, group_id,
      leftover_of_group_id, source_meal_plan, intent, preparation_tasks, note
    ) values (
      entry_date, (entry ->> 'slot')::public.daypart,
      nullif(entry ->> 'scheduledTime', '')::time,
      case when source_type = 'meal' then (entry ->> 'sourceId')::uuid end,
      case when source_type = 'recipe' then (entry ->> 'sourceId')::uuid end,
      case when source_type = 'product' then (entry ->> 'sourceId')::uuid end,
      case when source_type = 'inventoryLot' then (entry ->> 'sourceId')::uuid end,
      consume_inventory, (entry ->> 'scaleFactor')::numeric, 'planned',
      nullif(entry ->> 'name', ''), nullif(entry ->> 'emoji', ''),
      coalesce(nullif(entry ->> 'groupId', ''), gen_random_uuid()::text),
      nullif(entry ->> 'leftoverOfGroupId', ''), nullif(entry ->> 'sourceMealPlanId', '')::uuid, plan_intent,
      coalesce(entry -> 'preparationTasks', '[]'::jsonb), nullif(entry ->> 'note', '')
    ) returning id into plan_id;

    update public.planned_consumptions
    set servings = (entry ->> 'plannedServings')::numeric
    where meal_plan = plan_id;
    inserted_ids := array_append(inserted_ids, plan_id);
    inserted_count := inserted_count + 1;
    first_date := least(coalesce(first_date, entry_date), entry_date);
    last_date := greatest(coalesce(last_date, entry_date), entry_date);
  end loop;

  if p_mode = 'replaceWeek' then
    grocery_count := public.rebuild_shopping_from_plan(p_week_start, p_week_start + 6);
  elsif first_date is not null then
    grocery_count := public.rebuild_shopping_from_plan(
      first_date - (extract(isodow from first_date)::integer - 1),
      last_date + (7 - extract(isodow from last_date)::integer)
    );
  end if;

  return jsonb_build_object(
    'status', case when p_mode = 'replaceWeek' then 'replaced' else 'added' end,
    'entries', inserted_count,
    'planIds', to_jsonb(inserted_ids),
    'generatedGroceries', grocery_count
  );
end;
$$;



create or replace function public.gpt_preview_daily_nutrition(
  p_date date,
  p_candidate jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  candidate_type text;
  candidate_servings numeric;
  candidate_nutrition jsonb;
  candidate_snapshot jsonb;
  plan_row record;
  plan_snapshot jsonb;
  product_id uuid;
  batch_nutrients jsonb;
  batch_lot uuid;
  logged_kcal numeric := 0; logged_protein numeric := 0; logged_carbs numeric := 0;
  logged_fat numeric := 0; logged_fiber numeric := 0; logged_sugar numeric := 0; logged_sodium numeric := 0;
  logged_entries integer := 0; logged_incomplete integer := 0;
  planned_kcal numeric := 0; planned_protein numeric := 0; planned_carbs numeric := 0;
  planned_fat numeric := 0; planned_fiber numeric := 0; planned_sugar numeric := 0; planned_sodium numeric := 0;
  planned_entries integer := 0; planned_incomplete integer := 0;
  candidate_kcal numeric := 0; candidate_protein numeric := 0; candidate_carbs numeric := 0;
  candidate_fat numeric := 0; candidate_fiber numeric := 0; candidate_sugar numeric := 0; candidate_sodium numeric := 0;
  bad_key text;
  settings public.personal_settings%rowtype;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if p_date is null then raise exception 'date is required'; end if;
  if jsonb_typeof(p_candidate) <> 'object' then raise exception 'candidate must be an object'; end if;

  candidate_type := p_candidate ->> 'sourceType';
  candidate_servings := nullif(p_candidate ->> 'servings', '')::numeric;
  if candidate_type not in ('product', 'recipe', 'custom') then
    raise exception 'candidate.sourceType must be product, recipe, or custom';
  end if;
  if candidate_servings is null or candidate_servings <= 0 then
    raise exception 'candidate.servings must be positive';
  end if;

  if candidate_type = 'product' then
    candidate_snapshot := public.product_portion_snapshot((p_candidate ->> 'sourceId')::uuid, candidate_servings);
  elsif candidate_type = 'recipe' then
    candidate_snapshot := public.recipe_portion_snapshot((p_candidate ->> 'sourceId')::uuid, candidate_servings);
  else
    candidate_nutrition := p_candidate -> 'nutritionPerServing';
    if jsonb_typeof(candidate_nutrition) <> 'object' then
      raise exception 'A custom candidate requires nutritionPerServing';
    end if;
    select key into bad_key
    from jsonb_object_keys(candidate_nutrition) key
    where key <> all(array['calories','proteinG','carbsG','fatG','fiberG','sugarG','sodiumMg','estimated','source'])
    limit 1;
    if bad_key is not null then raise exception 'Unsupported candidate nutrition field: %', bad_key; end if;
    if nullif(trim(coalesce(candidate_nutrition ->> 'source', '')), '') is null then
      raise exception 'nutritionPerServing.source is required for a custom candidate';
    end if;
    if jsonb_typeof(candidate_nutrition -> 'estimated') <> 'boolean' then
      raise exception 'nutritionPerServing.estimated must be a boolean';
    end if;
    if exists (
      select 1
      from jsonb_each_text(candidate_nutrition) nutrient
      where nutrient.key = any(array['calories','proteinG','carbsG','fatG','fiberG','sugarG','sodiumMg'])
        and case
          when nutrient.key = any(array['calories','proteinG','carbsG','fatG','fiberG','sugarG','sodiumMg'])
            then nutrient.value::numeric < 0
          else false
        end
    ) then raise exception 'Candidate nutrients must be nonnegative'; end if;
    if num_nonnulls(
      nullif(candidate_nutrition ->> 'calories', ''), nullif(candidate_nutrition ->> 'proteinG', ''),
      nullif(candidate_nutrition ->> 'carbsG', ''), nullif(candidate_nutrition ->> 'fatG', ''),
      nullif(candidate_nutrition ->> 'fiberG', ''), nullif(candidate_nutrition ->> 'sugarG', ''),
      nullif(candidate_nutrition ->> 'sodiumMg', '')
    ) = 0 then raise exception 'nutritionPerServing needs at least one known nutrient'; end if;
    if p_candidate ? 'estimatedCostPerServing' and not (p_candidate ? 'costSource' and p_candidate ? 'priceAsOf') then
      raise exception 'costSource and priceAsOf are required with estimatedCostPerServing';
    end if;
    if nullif(p_candidate ->> 'estimatedCostPerServing', '')::numeric < 0 then
      raise exception 'estimatedCostPerServing must be nonnegative';
    end if;

    candidate_snapshot := jsonb_build_object(
      'label', nullif(trim(coalesce(p_candidate ->> 'label', '')), ''),
      'sourceType', 'custom',
      'sourceId', null,
      'servings', candidate_servings,
      'nutrition', jsonb_build_object(
        'calories', nullif(candidate_nutrition ->> 'calories', '')::numeric * candidate_servings,
        'proteinG', nullif(candidate_nutrition ->> 'proteinG', '')::numeric * candidate_servings,
        'carbsG', nullif(candidate_nutrition ->> 'carbsG', '')::numeric * candidate_servings,
        'fatG', nullif(candidate_nutrition ->> 'fatG', '')::numeric * candidate_servings,
        'fiberG', nullif(candidate_nutrition ->> 'fiberG', '')::numeric * candidate_servings,
        'sugarG', nullif(candidate_nutrition ->> 'sugarG', '')::numeric * candidate_servings,
        'sodiumMg', nullif(candidate_nutrition ->> 'sodiumMg', '')::numeric * candidate_servings
      ),
      'nutritionStatus', case
        when num_nonnulls(
          nullif(candidate_nutrition ->> 'calories', ''), nullif(candidate_nutrition ->> 'proteinG', ''),
          nullif(candidate_nutrition ->> 'carbsG', ''), nullif(candidate_nutrition ->> 'fatG', ''),
          nullif(candidate_nutrition ->> 'fiberG', ''), nullif(candidate_nutrition ->> 'sugarG', ''),
          nullif(candidate_nutrition ->> 'sodiumMg', '')
        ) = 7 then 'complete' else 'partial' end,
      'nutritionEstimated', (candidate_nutrition ->> 'estimated')::boolean,
      'nutritionSource', candidate_nutrition ->> 'source',
      'estimatedCost', nullif(p_candidate ->> 'estimatedCostPerServing', '')::numeric * candidate_servings,
      'costIsEstimated', p_candidate ? 'estimatedCostPerServing',
      'costSource', nullif(p_candidate ->> 'costSource', ''),
      'priceAsOf', nullif(p_candidate ->> 'priceAsOf', '')::date
    );
  end if;

  if candidate_snapshot is null or candidate_snapshot ->> 'label' is null then
    raise exception 'Candidate source does not exist or has no label';
  end if;

  select
    coalesce(sum(log.kcal), 0), coalesce(sum(log.protein_g), 0), coalesce(sum(log.carbs_g), 0),
    coalesce(sum(log.fat_g), 0), coalesce(sum(log.fiber_g), 0), coalesce(sum(log.sugar_g), 0),
    coalesce(sum(log.sodium_mg), 0), count(*), count(*) filter (where log.nutrition_status <> 'complete')
  into logged_kcal, logged_protein, logged_carbs, logged_fat, logged_fiber, logged_sugar,
       logged_sodium, logged_entries, logged_incomplete
  from public.food_logs log
  cross join public.personal_settings zone
  where zone.singleton and log.voided_at is null
    and (log.occurred_at at time zone zone.time_zone)::date = p_date;

  for plan_row in
    select plan.*, consumption.servings
    from public.meal_plans plan
    join public.planned_consumptions consumption on consumption.meal_plan = plan.id
    where plan.plan_date = p_date and plan.status in ('planned', 'made')
      and consumption.status = 'planned'
  loop
    plan_snapshot := null;
    if plan_row.product is not null then
      plan_snapshot := public.product_portion_snapshot(plan_row.product, plan_row.servings);
    elsif plan_row.inventory_lot is not null then
      select lot.product into product_id from public.inventory_lots lot where lot.id = plan_row.inventory_lot;
      if product_id is not null then
        plan_snapshot := public.product_portion_snapshot(product_id, plan_row.servings);
      end if;
    elsif plan_row.recipe is not null then
      plan_snapshot := public.recipe_portion_snapshot(plan_row.recipe, plan_row.servings);
    end if;
    batch_lot := plan_row.inventory_lot;
    if batch_lot is null and (plan_row.source_meal_plan is not null or plan_row.status = 'made') then
      select lot.id into batch_lot from public.inventory_lots lot
      join public.preps prep on prep.id = lot.prep and prep.voided_at is null
      where prep.meal_plan = coalesce(plan_row.source_meal_plan, plan_row.id)
      order by prep.prepped_at desc, lot.id limit 1;
    end if;
    if batch_lot is not null and exists (select 1 from public.inventory_lots where id = batch_lot and prep is not null) then
      batch_nutrients := public.lot_nutrition_json(batch_lot);
      plan_snapshot := jsonb_build_object(
        'nutritionStatus', case when exists (select 1 from jsonb_each(batch_nutrients) n where n.value = 'null'::jsonb) then 'partial' else 'complete' end,
        'nutrition', jsonb_build_object(
          'calories', (batch_nutrients ->> 'kcal')::numeric * plan_row.servings,
          'proteinG', (batch_nutrients ->> 'protein_g')::numeric * plan_row.servings,
          'carbsG', (batch_nutrients ->> 'carbs_g')::numeric * plan_row.servings,
          'fatG', (batch_nutrients ->> 'fat_g')::numeric * plan_row.servings,
          'fiberG', (batch_nutrients ->> 'fiber_g')::numeric * plan_row.servings,
          'sugarG', (batch_nutrients ->> 'sugar_g')::numeric * plan_row.servings,
          'sodiumMg', (batch_nutrients ->> 'sodium_mg')::numeric * plan_row.servings));
    end if;
    if plan_snapshot is null then
      planned_incomplete := planned_incomplete + 1;
      continue;
    end if;
    planned_entries := planned_entries + 1;
    planned_incomplete := planned_incomplete + case when plan_snapshot ->> 'nutritionStatus' = 'complete' then 0 else 1 end;
    planned_kcal := planned_kcal + coalesce((plan_snapshot #>> '{nutrition,calories}')::numeric, 0);
    planned_protein := planned_protein + coalesce((plan_snapshot #>> '{nutrition,proteinG}')::numeric, 0);
    planned_carbs := planned_carbs + coalesce((plan_snapshot #>> '{nutrition,carbsG}')::numeric, 0);
    planned_fat := planned_fat + coalesce((plan_snapshot #>> '{nutrition,fatG}')::numeric, 0);
    planned_fiber := planned_fiber + coalesce((plan_snapshot #>> '{nutrition,fiberG}')::numeric, 0);
    planned_sugar := planned_sugar + coalesce((plan_snapshot #>> '{nutrition,sugarG}')::numeric, 0);
    planned_sodium := planned_sodium + coalesce((plan_snapshot #>> '{nutrition,sodiumMg}')::numeric, 0);
  end loop;

  candidate_kcal := coalesce((candidate_snapshot #>> '{nutrition,calories}')::numeric, 0);
  candidate_protein := coalesce((candidate_snapshot #>> '{nutrition,proteinG}')::numeric, 0);
  candidate_carbs := coalesce((candidate_snapshot #>> '{nutrition,carbsG}')::numeric, 0);
  candidate_fat := coalesce((candidate_snapshot #>> '{nutrition,fatG}')::numeric, 0);
  candidate_fiber := coalesce((candidate_snapshot #>> '{nutrition,fiberG}')::numeric, 0);
  candidate_sugar := coalesce((candidate_snapshot #>> '{nutrition,sugarG}')::numeric, 0);
  candidate_sodium := coalesce((candidate_snapshot #>> '{nutrition,sodiumMg}')::numeric, 0);
  select * into settings from public.personal_settings where singleton;

  return jsonb_build_object(
    'date', p_date,
    'logged', jsonb_build_object('calories', logged_kcal, 'proteinG', logged_protein,
      'carbsG', logged_carbs, 'fatG', logged_fat, 'fiberG', logged_fiber,
      'sugarG', logged_sugar, 'sodiumMg', logged_sodium,
      'entryCount', logged_entries, 'incompleteEntries', logged_incomplete),
    'planned', jsonb_build_object('calories', planned_kcal, 'proteinG', planned_protein,
      'carbsG', planned_carbs, 'fatG', planned_fat, 'fiberG', planned_fiber,
      'sugarG', planned_sugar, 'sodiumMg', planned_sodium,
      'entryCount', planned_entries, 'incompleteEntries', planned_incomplete),
    'baseline', jsonb_build_object('calories', logged_kcal + planned_kcal,
      'proteinG', logged_protein + planned_protein, 'carbsG', logged_carbs + planned_carbs,
      'fatG', logged_fat + planned_fat, 'fiberG', logged_fiber + planned_fiber,
      'sugarG', logged_sugar + planned_sugar, 'sodiumMg', logged_sodium + planned_sodium),
    'candidate', candidate_snapshot,
    'after', jsonb_build_object('calories', logged_kcal + planned_kcal + candidate_kcal,
      'proteinG', logged_protein + planned_protein + candidate_protein,
      'carbsG', logged_carbs + planned_carbs + candidate_carbs,
      'fatG', logged_fat + planned_fat + candidate_fat,
      'fiberG', logged_fiber + planned_fiber + candidate_fiber,
      'sugarG', logged_sugar + planned_sugar + candidate_sugar,
      'sodiumMg', logged_sodium + planned_sodium + candidate_sodium),
    'targets', jsonb_build_object('calories', settings.nutrition_calories,
      'proteinG', settings.nutrition_protein_g, 'carbsG', settings.nutrition_carbs_g,
      'fatG', settings.nutrition_fat_g, 'fiberG', settings.nutrition_fiber_g,
      'sodiumMg', settings.nutrition_sodium_mg),
    'incompleteEntriesAfter', logged_incomplete + planned_incomplete
      + case when candidate_snapshot ->> 'nutritionStatus' = 'complete' then 0 else 1 end
  );
end;
$$;

