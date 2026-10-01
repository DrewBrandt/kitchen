-- Preserve retry payload identity and prepared-food uncertainty. Existing public RPC ACLs are retained.
-- No historical facts or account privileges are changed.
alter table public.gpt_action_requests add column request_payload jsonb;

create function public.claim_mutation_payload(p_request_id uuid, p_operation text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare prior jsonb; stored jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior := public.gpt_claim_request(p_request_id, p_operation);
  if prior is null then
    update public.gpt_action_requests set request_payload = p_payload where request_id = p_request_id;
  else
    select request_payload into stored from public.gpt_action_requests where request_id = p_request_id;
    if stored is distinct from p_payload then raise exception 'This request ID belongs to different or older input. Review the saved event before submitting a new request.'; end if;
  end if;
  return prior;
end;
$$;
revoke all on function public.claim_mutation_payload(uuid, text, jsonb) from public, anon, authenticated, service_role;

create or replace function public.log_manual_consumption(
  p_label text,
  p_portion_label text,
  p_occurred_at timestamptz,
  p_time_precision text,
  p_nutrition jsonb,
  p_nutrition_estimate jsonb,
  p_components jsonb,
  p_acquisition_type text,
  p_total_price numeric,
  p_out_of_pocket_cost numeric,
  p_paid_by text,
  p_cost_is_estimated boolean,
  p_cost_source text,
  p_price_as_of date,
  p_request_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  bad_key text;
  log_row public.food_logs%rowtype;
  prior_result jsonb;
  action_result jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior_result := public.claim_mutation_payload(p_request_id, 'logManualConsumption', jsonb_build_object('p_label', p_label, 'p_portion_label', p_portion_label, 'p_occurred_at', p_occurred_at, 'p_time_precision', p_time_precision, 'p_nutrition', p_nutrition, 'p_nutrition_estimate', p_nutrition_estimate, 'p_components', p_components, 'p_acquisition_type', p_acquisition_type, 'p_total_price', p_total_price, 'p_out_of_pocket_cost', p_out_of_pocket_cost, 'p_paid_by', p_paid_by, 'p_cost_is_estimated', p_cost_is_estimated, 'p_cost_source', p_cost_source, 'p_price_as_of', p_price_as_of, 'p_note', p_note));
  if prior_result is not null then return prior_result; end if;
  if trim(coalesce(p_label, '')) = '' then raise exception 'label is required'; end if;
  if p_time_precision not in ('exact', 'estimated', 'dateOnly') then raise exception 'Invalid timePrecision'; end if;
  if p_nutrition is not null and jsonb_typeof(p_nutrition) <> 'object' then raise exception 'nutrition must be an object or null'; end if;
  select key into bad_key from jsonb_object_keys(coalesce(p_nutrition, '{}'::jsonb)) key
  where key <> all(array['calories','proteinG','carbsG','fatG','fiberG','sugarG','sodiumMg','estimated','source']) limit 1;
  if bad_key is not null then raise exception 'Unsupported nutrition field: %', bad_key; end if;
  if p_nutrition_estimate is not null and jsonb_typeof(p_nutrition_estimate) <> 'object' then raise exception 'nutritionEstimate must be an object or null'; end if;
  if coalesce(jsonb_typeof(p_components), 'array') <> 'array' then raise exception 'components must be an array'; end if;
  if p_acquisition_type not in ('grocery', 'restaurant', 'takeout', 'office', 'gift', 'home', 'other') then raise exception 'Invalid acquisitionType'; end if;
  if p_total_price is not null and p_total_price < 0 then raise exception 'totalPrice cannot be negative'; end if;
  if p_out_of_pocket_cost is not null and p_out_of_pocket_cost < 0 then raise exception 'outOfPocketCost cannot be negative'; end if;
  if p_out_of_pocket_cost is null then raise exception 'outOfPocketCost must be stated, including zero'; end if;
  if nullif(trim(coalesce(p_paid_by, '')), '') is null then raise exception 'paidBy is required'; end if;
  if p_cost_is_estimated is null then raise exception 'costIsEstimated is required'; end if;
  if nullif(trim(coalesce(p_cost_source, '')), '') is null then raise exception 'costSource is required'; end if;
  if p_total_price is not null and p_price_as_of is null then raise exception 'priceAsOf is required with totalPrice'; end if;

  insert into public.food_logs(
    label, kind, portion_label, occurred_at, time_precision,
    kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
    nutrition_is_estimated, nutrition_source, nutrition_estimate, components,
    acquisition_type, total_price, out_of_pocket_cost, paid_by, price_as_of,
    cost, cost_is_estimated, cost_source, note
  ) values (
    trim(p_label), 'manual', nullif(trim(coalesce(p_portion_label, '')), ''), p_occurred_at, p_time_precision,
    nullif(p_nutrition ->> 'calories', '')::numeric,
    nullif(p_nutrition ->> 'proteinG', '')::numeric,
    nullif(p_nutrition ->> 'carbsG', '')::numeric,
    nullif(p_nutrition ->> 'fatG', '')::numeric,
    nullif(p_nutrition ->> 'fiberG', '')::numeric,
    nullif(p_nutrition ->> 'sugarG', '')::numeric,
    nullif(p_nutrition ->> 'sodiumMg', '')::numeric,
    coalesce((p_nutrition ->> 'estimated')::boolean, false),
    nullif(trim(coalesce(p_nutrition ->> 'source', '')), ''),
    p_nutrition_estimate, coalesce(p_components, '[]'::jsonb),
    p_acquisition_type, p_total_price, p_out_of_pocket_cost, trim(p_paid_by), p_price_as_of,
    p_total_price, p_cost_is_estimated, trim(p_cost_source), nullif(trim(coalesce(p_note, '')), '')
  ) returning * into log_row;

  action_result := jsonb_build_object('status', 'logged', 'id', log_row.id, 'nutritionStatus', log_row.nutrition_status);
  perform public.gpt_complete_request(p_request_id, action_result);
  return action_result;
end;
$$;

create or replace function public.consume_product_purchase(
  p_product uuid,
  p_purchased_quantity numeric,
  p_consumed_quantity numeric,
  p_acquisition_type text,
  p_total_price numeric,
  p_out_of_pocket_cost numeric,
  p_paid_by text,
  p_cost_is_estimated boolean,
  p_cost_source text,
  p_price_as_of date,
  p_request_id uuid,
  p_location text default null,
  p_occurred_at timestamptz default now(),
  p_time_precision text default 'exact',
  p_label text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  lot_id uuid;
  log_id uuid;
  prior_result jsonb;
  action_result jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior_result := public.claim_mutation_payload(p_request_id, 'consumeProductPurchase', jsonb_build_object('p_product', p_product, 'p_purchased_quantity', p_purchased_quantity, 'p_consumed_quantity', p_consumed_quantity, 'p_acquisition_type', p_acquisition_type, 'p_total_price', p_total_price, 'p_out_of_pocket_cost', p_out_of_pocket_cost, 'p_paid_by', p_paid_by, 'p_cost_is_estimated', p_cost_is_estimated, 'p_cost_source', p_cost_source, 'p_price_as_of', p_price_as_of, 'p_location', p_location, 'p_occurred_at', p_occurred_at, 'p_time_precision', p_time_precision, 'p_label', p_label, 'p_note', p_note));
  if prior_result is not null then return prior_result; end if;
  if p_purchased_quantity <= 0 then raise exception 'Purchased quantity must be positive'; end if;
  if p_consumed_quantity < 0 or p_consumed_quantity > p_purchased_quantity then raise exception 'Consumed quantity must be between zero and purchased quantity'; end if;
  if p_acquisition_type not in ('grocery', 'restaurant', 'takeout', 'office', 'gift', 'home', 'other') then raise exception 'Invalid acquisitionType'; end if;
  if p_time_precision not in ('exact', 'estimated', 'dateOnly') then raise exception 'Invalid timePrecision'; end if;
  if p_consumed_quantity < p_purchased_quantity and nullif(p_location, '') is null then raise exception 'A location is required when purchased food remains'; end if;
  if p_total_price is not null and p_total_price < 0 then raise exception 'totalPrice cannot be negative'; end if;
  if p_out_of_pocket_cost is not null and p_out_of_pocket_cost < 0 then raise exception 'outOfPocketCost cannot be negative'; end if;
  if p_acquisition_type in ('grocery', 'restaurant', 'takeout') and p_total_price is null then raise exception 'totalPrice is required for purchased food'; end if;
  if p_out_of_pocket_cost is null then raise exception 'outOfPocketCost must be stated, including zero'; end if;
  if nullif(trim(coalesce(p_paid_by, '')), '') is null then raise exception 'paidBy is required'; end if;
  if p_cost_is_estimated is null then raise exception 'costIsEstimated is required'; end if;
  if nullif(trim(coalesce(p_cost_source, '')), '') is null then raise exception 'costSource is required'; end if;
  if p_total_price is not null and p_price_as_of is null then raise exception 'priceAsOf is required with totalPrice'; end if;

  perform 1 from public.products where id = p_product and archived_at is null for update;
  if not found then raise exception 'Active product does not exist'; end if;

  insert into public.inventory_lots(
    product, initial_qty, remaining_qty, total_cost, out_of_pocket_cost,
    paid_by, cost_is_estimated, cost_source, price_as_of, acquired_at,
    acquired_time_precision, acquisition_type, is_external, location, note
  ) values (
    p_product, p_purchased_quantity, p_purchased_quantity, p_total_price, p_out_of_pocket_cost,
    trim(p_paid_by), p_cost_is_estimated, trim(p_cost_source), p_price_as_of, p_occurred_at,
    p_time_precision, p_acquisition_type, p_acquisition_type in ('restaurant', 'takeout'), nullif(p_location, ''), p_note
  ) returning id into lot_id;

  if p_consumed_quantity > 0 then
    log_id := public.consume_inventory_lot(lot_id, p_consumed_quantity, p_occurred_at);
    update public.food_logs
    set label = coalesce(nullif(p_label, ''), label),
        note = p_note,
        time_precision = p_time_precision,
        acquisition_type = p_acquisition_type,
        total_price = case when p_total_price is null then null else round(p_total_price * p_consumed_quantity / p_purchased_quantity, 2) end,
        out_of_pocket_cost = round(p_out_of_pocket_cost * p_consumed_quantity / p_purchased_quantity, 2),
        paid_by = trim(p_paid_by),
        price_as_of = p_price_as_of
    where id = log_id;
    update public.inventory_lots set acquisition_food_log = log_id where id = lot_id;
  end if;

  -- A historical purchase is usage history, not a new observation of the
  -- product's current market estimate. Never overwrite product price provenance.
  update public.products
  set use_count = use_count + case when p_consumed_quantity > 0 then 1 else 0 end,
      last_used_at = case when p_consumed_quantity > 0 then p_occurred_at else last_used_at end
  where id = p_product;

  action_result := jsonb_build_object(
    'status', case when p_consumed_quantity > 0 then 'consumed' else 'acquired' end,
    'lotId', lot_id,
    'logId', log_id,
    'acquisitionType', p_acquisition_type,
    'remainingQuantity', p_purchased_quantity - p_consumed_quantity,
    'location', nullif(p_location, '')
  );
  perform public.gpt_complete_request(p_request_id, action_result);
  return action_result;
end;
$$;

create or replace function public.gpt_add_grocery_lots(p_items jsonb, p_source text, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  item jsonb;
  product_row public.products%rowtype;
  unit_id uuid;
  base_quantity numeric;
  lot_id uuid;
  created_ids uuid[] := array[]::uuid[];
  prior_result jsonb;
  action_result jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if p_request_id is not null then
    prior_result := public.claim_mutation_payload(p_request_id, 'addGroceryHaul', jsonb_build_object('p_items', p_items, 'p_source', p_source));
    if prior_result is not null then return prior_result; end if;
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'items must be a non-empty array'; end if;
  if nullif(trim(coalesce(p_source, '')), '') is null then raise exception 'source is required'; end if;
  for item in select value from jsonb_array_elements(p_items)
  loop
    select * into product_row from public.products where id = (item ->> 'productId')::uuid and archived_at is null;
    if not found then raise exception 'Unknown active product: %', item ->> 'productId'; end if;
    if nullif(item ->> 'totalPrice', '')::numeric is null then raise exception 'totalPrice is required for grocery lots'; end if;
    if nullif(item ->> 'outOfPocketCost', '')::numeric is null then raise exception 'outOfPocketCost is required for grocery lots'; end if;
    if nullif(trim(coalesce(item ->> 'paidBy', '')), '') is null then raise exception 'paidBy is required for grocery lots'; end if;
    if nullif(item ->> 'priceAsOf', '')::date is null then raise exception 'priceAsOf is required for grocery lots'; end if;
    unit_id := public.resolve_measure_conversion(item ->> 'unit');
    base_quantity := public.to_base_quantity(product_row.food, (item ->> 'quantity')::numeric, unit_id);
    insert into public.inventory_lots(
      product, initial_qty, remaining_qty, total_cost, out_of_pocket_cost, paid_by,
      cost_is_estimated, cost_source, price_as_of, use_by, location, acquired_at,
      acquired_time_precision, acquisition_type, is_external, note
    ) values (
      product_row.id, base_quantity, base_quantity,
      (item ->> 'totalPrice')::numeric, (item ->> 'outOfPocketCost')::numeric, trim(item ->> 'paidBy'),
      (item ->> 'costIsEstimated')::boolean, trim(p_source), (item ->> 'priceAsOf')::date,
      nullif(item ->> 'bestBy', '')::date, coalesce(nullif(item ->> 'location', ''), 'pantry'),
      coalesce(nullif(item ->> 'acquiredAt', '')::timestamptz, now()),
      coalesce(nullif(item ->> 'acquiredTimePrecision', ''), 'exact'), 'grocery', false,
      nullif(item ->> 'note', '')
    ) returning id into lot_id;
    created_ids := created_ids || lot_id;
  end loop;
  action_result := jsonb_build_object('status', 'created', 'lotIds', created_ids);
  if p_request_id is not null then perform public.gpt_complete_request(p_request_id, action_result); end if;
  return action_result;
end;
$$;

create or replace function public.consume_prepared_batch(
  p_lot uuid,
  p_quantity numeric,
  p_meal_plan uuid default null,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  prep_row public.preps%rowtype;
  recipe_row public.recipes%rowtype;
  nutrients jsonb;
  linked_plan uuid;
  new_log uuid;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may consume inventory' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;

  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found or lot_row.prep is null then raise exception 'Prepared lot does not exist'; end if;
  if lot_row.remaining_qty < p_quantity then
    raise exception 'Prepared lot has only % servings remaining', lot_row.remaining_qty;
  end if;

  select * into prep_row from public.preps where id = lot_row.prep and voided_at is null;
  if not found then raise exception 'Preparation does not exist'; end if;
  select * into recipe_row from public.recipes where id = prep_row.recipe;
  nutrients := public.lot_nutrition_json(p_lot);

  insert into public.food_logs(
    label, kind, recipe, servings, occurred_at,
    kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
    nutrition_is_estimated, nutrition_source, nutrition_estimate, components
  ) values (
    coalesce(recipe_row.name, prep_row.label, 'Prepared food'), 'prepared', prep_row.recipe, p_quantity, p_occurred_at,
    (nutrients ->> 'kcal')::numeric * p_quantity,
    (nutrients ->> 'protein_g')::numeric * p_quantity,
    (nutrients ->> 'carbs_g')::numeric * p_quantity,
    (nutrients ->> 'fat_g')::numeric * p_quantity,
    (nutrients ->> 'fiber_g')::numeric * p_quantity,
    (nutrients ->> 'sugar_g')::numeric * p_quantity,
    (nutrients ->> 'sodium_mg')::numeric * p_quantity,
    prep_row.nutrition_is_estimated, prep_row.nutrition_source, prep_row.nutrition_estimate, prep_row.components
  ) returning id into new_log;

  insert into public.inventory_events(lot, quantity_delta, reason, food_log, occurred_at)
  values (p_lot, -p_quantity, 'eaten', new_log, p_occurred_at);

  linked_plan := coalesce(p_meal_plan, prep_row.meal_plan);
  if linked_plan is not null then
    update public.meal_plans
    set status = 'made', made_at = coalesce(made_at, prep_row.prepped_at)
    where id = linked_plan;

    update public.planned_consumptions
    set status = 'fulfilled', food_log = new_log
    where meal_plan = linked_plan and status = 'planned';
  end if;

  return new_log;
end;
$$;


create or replace function public.consume_product_purchase(
  p_product uuid,
  p_purchased_quantity numeric,
  p_consumed_quantity numeric,
  p_quantity_unit text,
  p_acquisition_type text,
  p_total_price numeric,
  p_out_of_pocket_cost numeric,
  p_paid_by text,
  p_cost_is_estimated boolean,
  p_cost_source text,
  p_price_as_of date,
  p_request_id uuid,
  p_location text default null,
  p_occurred_at timestamptz default now(),
  p_time_precision text default 'exact',
  p_label text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  product_food uuid;
  unit_id uuid;
  purchased_base numeric;
  consumed_base numeric;
  action_result jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if nullif(trim(coalesce(p_quantity_unit, '')), '') is null then
    raise exception 'quantityUnit is required';
  end if;
  select food into product_food
  from public.products
  where id = p_product and archived_at is null;
  if not found then raise exception 'Active product does not exist'; end if;
  unit_id := public.resolve_measure_conversion(p_quantity_unit);
  purchased_base := public.to_base_quantity(product_food, p_purchased_quantity, unit_id);
  consumed_base := case when p_consumed_quantity = 0 then 0
    else public.to_base_quantity(product_food, p_consumed_quantity, unit_id) end;

  action_result := public.consume_product_purchase(
    p_product, purchased_base, consumed_base, p_acquisition_type,
    p_total_price, p_out_of_pocket_cost, p_paid_by, p_cost_is_estimated,
    p_cost_source, p_price_as_of, p_request_id, p_location, p_occurred_at,
    p_time_precision, p_label, p_note
  );
  return (action_result - 'remainingQuantity') || jsonb_build_object(
    'remainingQuantity', p_purchased_quantity - p_consumed_quantity,
    'quantityUnit', trim(p_quantity_unit)
  );
end;
$$;
