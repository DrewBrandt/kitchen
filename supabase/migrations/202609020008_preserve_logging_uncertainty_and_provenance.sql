-- Preserve the distinctions that conversational backfills actually contain:
-- exact versus approximate times, point estimates versus honest ranges,
-- menu/retail value versus the owner's out-of-pocket spend, and reusable
-- products versus manually prepared leftovers. Also make duplicate definitions
-- mergeable instead of forcing callers to create replacements.

alter table public.base_foods
  add column archived_at timestamptz,
  add column merged_into uuid references public.base_foods(id);

alter table public.products
  add column serving_unit uuid references public.measure_conversions(id),
  add column serving_label text,
  add column servings_per_package numeric check (servings_per_package > 0),
  add column archived_at timestamptz,
  add column merged_into uuid references public.products(id);

alter table public.food_logs
  add column time_precision text not null default 'exact'
    check (time_precision in ('exact', 'estimated', 'dateOnly')),
  add column nutrition_estimate jsonb
    check (nutrition_estimate is null or jsonb_typeof(nutrition_estimate) = 'object'),
  add column components jsonb not null default '[]'::jsonb
    check (jsonb_typeof(components) = 'array'),
  add column acquisition_type text
    check (acquisition_type is null or acquisition_type in ('grocery', 'restaurant', 'takeout', 'office', 'gift', 'home', 'other')),
  add column total_price numeric(10, 2) check (total_price >= 0),
  add column out_of_pocket_cost numeric(10, 2) check (out_of_pocket_cost >= 0),
  add column paid_by text,
  add column price_as_of date;

alter table public.inventory_lots
  add column acquisition_type text
    check (acquisition_type is null or acquisition_type in ('grocery', 'restaurant', 'takeout', 'office', 'gift', 'home', 'other')),
  add column out_of_pocket_cost numeric(10, 2) check (out_of_pocket_cost >= 0),
  add column paid_by text,
  add column price_as_of date,
  add column acquired_time_precision text not null default 'exact'
    check (acquired_time_precision in ('exact', 'estimated', 'dateOnly'));

alter table public.preps
  alter column recipe drop not null,
  add column label text,
  add column emoji text,
  add column time_precision text not null default 'exact'
    check (time_precision in ('exact', 'estimated', 'dateOnly')),
  add column kcal numeric check (kcal >= 0),
  add column protein_g numeric check (protein_g >= 0),
  add column carbs_g numeric check (carbs_g >= 0),
  add column fat_g numeric check (fat_g >= 0),
  add column fiber_g numeric check (fiber_g >= 0),
  add column sugar_g numeric check (sugar_g >= 0),
  add column sodium_mg numeric check (sodium_mg >= 0),
  add column nutrition_source text,
  add column nutrition_is_estimated boolean not null default false,
  add column nutrition_estimate jsonb
    check (nutrition_estimate is null or jsonb_typeof(nutrition_estimate) = 'object'),
  add column components jsonb not null default '[]'::jsonb
    check (jsonb_typeof(components) = 'array'),
  add constraint preps_recipe_or_manual_label check (
    recipe is not null or nullif(trim(label), '') is not null
  );

comment on column public.products.serving_qty_base is
  'Printed label serving quantity converted to the canonical base unit.';
comment on column public.products.servings_per_package is
  'The label servings-per-container value. When present it is authoritative for proportional package consumption despite rounded net-weight serving sizes.';
comment on column public.food_logs.time_precision is
  'Whether occurred_at is exact, an estimated time, or a noon sorting anchor for a date-only recollection.';
comment on column public.food_logs.nutrition_estimate is
  'Structured estimate metadata: confidence, rationale, and optional per-nutrient min/max ranges.';
comment on column public.food_logs.total_price is
  'Full menu, retail, or estimated value represented by this event, regardless of who paid.';
comment on column public.food_logs.out_of_pocket_cost is
  'Amount the owner personally paid. This is distinct from total_price.';
comment on column public.inventory_lots.total_cost is
  'Full acquisition price or estimated value for the lot, regardless of who paid.';
comment on column public.inventory_lots.out_of_pocket_cost is
  'Amount the owner personally paid for the lot.';

-- Preserve the old records' meanings before the API begins returning the new
-- fields. Inventory lots used total_cost as both price and owner spend. Manual
-- logs used cost as owner spend, except explicitly covered/free events.
update public.inventory_lots
set acquisition_type = case when is_external then 'restaurant' else 'grocery' end,
    out_of_pocket_cost = total_cost,
    paid_by = case when total_cost is null then null else 'self' end,
    price_as_of = (acquired_at at time zone (select time_zone from public.app_settings where singleton))::date;

update public.food_logs
set acquisition_type = case
      when kind = 'manual' and lower(coalesce(cost_source, '')) like '%office%' then 'office'
      when kind = 'manual' and lower(coalesce(cost_source, '')) like '%parent%' then 'restaurant'
      when kind = 'manual' then 'home'
      else null
    end,
    total_price = case
      when kind = 'manual' and coalesce(cost, 0) > 0 then cost
      else null
    end,
    out_of_pocket_cost = case when kind = 'manual' then cost else null end,
    paid_by = case
      when kind = 'manual' and lower(coalesce(cost_source, '')) like '%office%' then 'employer'
      when kind = 'manual' and lower(coalesce(cost_source, '')) like '%parent%' then 'parents'
      when kind = 'manual' and cost is not null then 'self'
      else null
    end,
    price_as_of = case when kind = 'manual' and cost is not null
      then (occurred_at at time zone (select time_zone from public.app_settings where singleton))::date
      else null end;

-- Existing products did not retain the entered serving unit. Do not invent it
-- from packageUnit: a 9 oz package can have a printed 28 g serving. The numeric
-- base quantity remains usable, while future writes retain the explicit unit.
update public.products
set servings_per_package = package_qty_base / serving_qty_base
where serving_qty_base is not null and serving_qty_base > 0;

-- Every consequential create/consume action carries a stable request UUID.
-- Claim, mutation, and stored response happen in one database transaction, so
-- an HTTP or model retry returns the first result instead of repeating a write.
create table public.gpt_action_requests (
  request_id uuid primary key,
  operation text not null,
  result jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

alter table public.gpt_action_requests enable row level security;
revoke all on table public.gpt_action_requests from public, anon, authenticated;

create function public.gpt_claim_request(p_request_id uuid, p_operation text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_count integer;
  existing_operation text;
  existing_result jsonb;
begin
  if p_request_id is null then raise exception 'requestId is required'; end if;
  if nullif(trim(coalesce(p_operation, '')), '') is null then raise exception 'operation is required'; end if;
  insert into public.gpt_action_requests(request_id, operation)
  values (p_request_id, p_operation)
  on conflict (request_id) do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 1 then return null; end if;

  select operation, result into existing_operation, existing_result
  from public.gpt_action_requests where request_id = p_request_id;
  if existing_operation <> p_operation then
    raise exception 'requestId was already used for a different operation';
  end if;
  if existing_result is null then raise exception 'requestId is still in progress; retry'; end if;
  return existing_result;
end;
$$;

create function public.gpt_complete_request(p_request_id uuid, p_result jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.gpt_action_requests
  set result = p_result, completed_at = now()
  where request_id = p_request_id;
$$;

revoke all on function public.gpt_claim_request(uuid, text) from public, anon, authenticated;
revoke all on function public.gpt_complete_request(uuid, jsonb) from public, anon, authenticated;

create index base_foods_merged_into_idx on public.base_foods(merged_into) where merged_into is not null;
create index products_merged_into_idx on public.products(merged_into) where merged_into is not null;

-- Index exact active product identities, including duplicates split across two
-- accidentally-created canonical foods. Migration 009 repairs the pre-existing
-- duplicate before replacing this with a unique index.
create index products_active_normalized_identity_idx
  on public.products (
    lower(regexp_replace(coalesce(brand, ''), '[^a-zA-Z0-9]+', '', 'g')),
    lower(regexp_replace(name, '[^a-zA-Z0-9]+', '', 'g')),
    package_qty_base
  )
  where archived_at is null;

create unique index products_active_barcode_key
  on public.products(barcode)
  where barcode is not null and archived_at is null;

-- A label serving count and a rounded net weight can disagree slightly. Use the
-- explicit package count when available so eating a whole package produces the
-- label's whole-package totals.
create or replace function public.product_servings_for_quantity(
  p_product uuid,
  p_quantity numeric
)
returns numeric
language sql
stable
set search_path = ''
as $$
  select case
    when product.servings_per_package is not null
      and product.package_qty_base > 0
      and product.serving_qty_base is not null
      and product.nutrition_basis_qty is not null
      and abs(product.nutrition_basis_qty - product.serving_qty_base) < 0.000001
      then p_quantity / product.package_qty_base * product.servings_per_package
    else p_quantity / coalesce(nullif(product.serving_qty_base, 0), 1)
  end
  from public.products product
  where product.id = p_product
$$;

create or replace function public.product_nutrition_multiplier(
  p_product uuid,
  p_quantity numeric
)
returns numeric
language sql
stable
set search_path = ''
as $$
  select case
    when product.servings_per_package is not null
      and product.package_qty_base > 0
      and product.serving_qty_base is not null
      and product.nutrition_basis_qty is not null
      and abs(product.nutrition_basis_qty - product.serving_qty_base) < 0.000001
      then p_quantity / product.package_qty_base * product.servings_per_package
    else p_quantity / coalesce(nullif(product.nutrition_basis_qty, 0), 1)
  end
  from public.products product
  where product.id = p_product
$$;

create or replace function public.lot_nutrition_json(
  p_lot uuid,
  p_path uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  lot_product uuid;
  lot_prep uuid;
  prep_row public.preps%rowtype;
  prep_yield numeric;
  result jsonb;
  derived jsonb;
begin
  if p_lot = any(p_path) then
    raise exception 'Prepared-lot nutrition graph contains a cycle at lot %', p_lot;
  end if;

  select product, prep into lot_product, lot_prep
  from public.inventory_lots where id = p_lot;
  if not found then raise exception 'Inventory lot % does not exist', p_lot; end if;

  if lot_product is not null then
    select jsonb_build_object(
      'kcal', case when product.kcal is null then food.kcal / nullif(food.nutrition_basis_qty, 0) else product.kcal * public.product_nutrition_multiplier(product.id, 1) end,
      'protein_g', case when product.protein_g is null then food.protein_g / nullif(food.nutrition_basis_qty, 0) else product.protein_g * public.product_nutrition_multiplier(product.id, 1) end,
      'carbs_g', case when product.carbs_g is null then food.carbs_g / nullif(food.nutrition_basis_qty, 0) else product.carbs_g * public.product_nutrition_multiplier(product.id, 1) end,
      'fat_g', case when product.fat_g is null then food.fat_g / nullif(food.nutrition_basis_qty, 0) else product.fat_g * public.product_nutrition_multiplier(product.id, 1) end,
      'fiber_g', case when product.fiber_g is null then food.fiber_g / nullif(food.nutrition_basis_qty, 0) else product.fiber_g * public.product_nutrition_multiplier(product.id, 1) end,
      'sugar_g', case when product.sugar_g is null then food.sugar_g / nullif(food.nutrition_basis_qty, 0) else product.sugar_g * public.product_nutrition_multiplier(product.id, 1) end,
      'sodium_mg', case when product.sodium_mg is null then food.sodium_mg / nullif(food.nutrition_basis_qty, 0) else product.sodium_mg * public.product_nutrition_multiplier(product.id, 1) end
    ) into result
    from public.products product
    join public.base_foods food on food.id = product.food
    where product.id = lot_product;
    return result;
  end if;

  select * into prep_row from public.preps prep where prep.id = lot_prep and prep.voided_at is null;
  prep_yield := prep_row.actual_yield_qty;
  if prep_yield is null or prep_yield <= 0 then
    raise exception 'Prep % needs an actual yield before nutrition can resolve', lot_prep;
  end if;

  if prep_row.recipe is null then
    return jsonb_build_object(
      'kcal', prep_row.kcal,
      'protein_g', prep_row.protein_g,
      'carbs_g', prep_row.carbs_g,
      'fat_g', prep_row.fat_g,
      'fiber_g', prep_row.fiber_g,
      'sugar_g', prep_row.sugar_g,
      'sodium_mg', prep_row.sodium_mg
    );
  end if;

  select jsonb_build_object(
    'kcal', sum(-event.quantity_delta * (nutrients.value ->> 'kcal')::numeric),
    'protein_g', sum(-event.quantity_delta * (nutrients.value ->> 'protein_g')::numeric),
    'carbs_g', sum(-event.quantity_delta * (nutrients.value ->> 'carbs_g')::numeric),
    'fat_g', sum(-event.quantity_delta * (nutrients.value ->> 'fat_g')::numeric),
    'fiber_g', sum(-event.quantity_delta * (nutrients.value ->> 'fiber_g')::numeric),
    'sugar_g', sum(-event.quantity_delta * (nutrients.value ->> 'sugar_g')::numeric),
    'sodium_mg', sum(-event.quantity_delta * (nutrients.value ->> 'sodium_mg')::numeric)
  ) into derived
  from public.inventory_events event
  cross join lateral (
    select public.lot_nutrition_json(event.lot, p_path || p_lot) as value
  ) nutrients
  where event.prep = lot_prep and event.reason = 'prep' and event.voided_at is null;

  select jsonb_build_object(
    'kcal', coalesce(recipe.override_kcal / recipe.override_basis_qty, (derived ->> 'kcal')::numeric / prep_yield),
    'protein_g', coalesce(recipe.override_protein_g / recipe.override_basis_qty, (derived ->> 'protein_g')::numeric / prep_yield),
    'carbs_g', coalesce(recipe.override_carbs_g / recipe.override_basis_qty, (derived ->> 'carbs_g')::numeric / prep_yield),
    'fat_g', coalesce(recipe.override_fat_g / recipe.override_basis_qty, (derived ->> 'fat_g')::numeric / prep_yield),
    'fiber_g', coalesce(recipe.override_fiber_g / recipe.override_basis_qty, (derived ->> 'fiber_g')::numeric / prep_yield),
    'sugar_g', coalesce(recipe.override_sugar_g / recipe.override_basis_qty, (derived ->> 'sugar_g')::numeric / prep_yield),
    'sodium_mg', coalesce(recipe.override_sodium_mg / recipe.override_basis_qty, (derived ->> 'sodium_mg')::numeric / prep_yield)
  ) into result
  from public.recipes recipe where recipe.id = prep_row.recipe;
  return result;
end;
$$;

create or replace function public.consume_inventory_lot(
  p_lot uuid,
  p_quantity numeric,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  product_row public.products%rowtype;
  food_row public.base_foods%rowtype;
  nutrients jsonb;
  new_log uuid;
begin
  if not public.is_app_owner() then raise exception 'Only the app owner may consume inventory' using errcode = '42501'; end if;
  if p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;
  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found or lot_row.product is null then raise exception 'Inventory lot does not exist'; end if;
  if lot_row.remaining_qty < p_quantity then raise exception 'Lot has only % remaining', lot_row.remaining_qty; end if;
  select * into product_row from public.products where id = lot_row.product and archived_at is null;
  if not found then raise exception 'Active product does not exist'; end if;
  select * into food_row from public.base_foods where id = product_row.food;
  nutrients := public.lot_nutrition_json(p_lot);

  insert into public.food_logs(
    label, kind, product, servings, occurred_at,
    kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
    nutrition_is_estimated, nutrition_source
  ) values (
    concat_ws(' · ', product_row.brand, product_row.name), 'inventory', product_row.id,
    public.product_servings_for_quantity(product_row.id, p_quantity), p_occurred_at,
    (nutrients ->> 'kcal')::numeric * p_quantity,
    (nutrients ->> 'protein_g')::numeric * p_quantity,
    (nutrients ->> 'carbs_g')::numeric * p_quantity,
    (nutrients ->> 'fat_g')::numeric * p_quantity,
    (nutrients ->> 'fiber_g')::numeric * p_quantity,
    (nutrients ->> 'sugar_g')::numeric * p_quantity,
    (nutrients ->> 'sodium_mg')::numeric * p_quantity,
    product_row.nutrition_is_estimated or (product_row.kcal is null and food_row.nutrition_is_estimated),
    coalesce(product_row.nutrition_source, food_row.nutrition_source)
  ) returning id into new_log;

  insert into public.inventory_events(lot, quantity_delta, reason, food_log, occurred_at)
  values (p_lot, -p_quantity, 'eaten', new_log, p_occurred_at);
  return new_log;
end;
$$;

drop function public.gpt_consume_inventory(uuid, numeric, text, timestamptz, text, text, uuid);

create function public.gpt_consume_inventory(
  p_food uuid,
  p_quantity numeric,
  p_unit text,
  p_occurred_at timestamptz,
  p_time_precision text,
  p_request_id uuid,
  p_label text default null,
  p_note text default null,
  p_lot uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_base numeric;
  needed numeric;
  taken numeric;
  total_servings numeric := 0;
  lot_row public.inventory_lots%rowtype;
  nutrients jsonb;
  totals jsonb;
  deductions jsonb := '[]'::jsonb;
  food_name text;
  exact_product uuid;
  log_id uuid;
  nutrition_estimated boolean;
  nutrition_source text;
  prior_result jsonb;
  action_result jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior_result := public.gpt_claim_request(p_request_id, 'consumeInventory');
  if prior_result is not null then return prior_result; end if;
  if p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;
  if p_time_precision not in ('exact', 'estimated', 'dateOnly') then raise exception 'Invalid timePrecision'; end if;
  select name into food_name from public.base_foods where id = p_food and archived_at is null;
  if food_name is null then raise exception 'Active food does not exist'; end if;
  requested_base := public.to_base_quantity(p_food, p_quantity, public.resolve_measure_conversion(p_unit));
  needed := requested_base;

  if p_lot is not null then
    select lot.* into lot_row
    from public.inventory_lots lot
    join public.products product on product.id = lot.product and product.archived_at is null
    where lot.id = p_lot and product.food = p_food
    for update of lot;
    if not found then raise exception 'Inventory lot does not exist for this food'; end if;
    if lot_row.remaining_qty < needed then raise exception 'Lot has only % remaining', lot_row.remaining_qty; end if;
    exact_product := lot_row.product;
    taken := needed;
    total_servings := public.product_servings_for_quantity(lot_row.product, taken);
    deductions := jsonb_build_array(jsonb_build_object('lot', lot_row.id, 'quantity', taken));
    needed := 0;
  else
    for lot_row in
      select lot.*
      from public.inventory_lots lot
      join public.products product on product.id = lot.product and product.archived_at is null
      where product.food = p_food and lot.remaining_qty > 0
      order by lot.use_by asc nulls last, lot.acquired_at, lot.id
      for update of lot
    loop
      exit when needed <= 0.0000001;
      taken := least(needed, lot_row.remaining_qty);
      total_servings := total_servings + public.product_servings_for_quantity(lot_row.product, taken);
      deductions := deductions || jsonb_build_array(jsonb_build_object('lot', lot_row.id, 'quantity', taken));
      needed := needed - taken;
    end loop;
  end if;
  if needed > 0.0000001 then raise exception 'Not enough inventory for %', food_name; end if;

  select jsonb_build_object(
    'kcal', case when bool_and(n.value ->> 'kcal' is not null) then sum((d.value ->> 'quantity')::numeric * (n.value ->> 'kcal')::numeric) end,
    'protein_g', case when bool_and(n.value ->> 'protein_g' is not null) then sum((d.value ->> 'quantity')::numeric * (n.value ->> 'protein_g')::numeric) end,
    'carbs_g', case when bool_and(n.value ->> 'carbs_g' is not null) then sum((d.value ->> 'quantity')::numeric * (n.value ->> 'carbs_g')::numeric) end,
    'fat_g', case when bool_and(n.value ->> 'fat_g' is not null) then sum((d.value ->> 'quantity')::numeric * (n.value ->> 'fat_g')::numeric) end,
    'fiber_g', case when bool_and(n.value ->> 'fiber_g' is not null) then sum((d.value ->> 'quantity')::numeric * (n.value ->> 'fiber_g')::numeric) end,
    'sugar_g', case when bool_and(n.value ->> 'sugar_g' is not null) then sum((d.value ->> 'quantity')::numeric * (n.value ->> 'sugar_g')::numeric) end,
    'sodium_mg', case when bool_and(n.value ->> 'sodium_mg' is not null) then sum((d.value ->> 'quantity')::numeric * (n.value ->> 'sodium_mg')::numeric) end
  ) into totals
  from jsonb_array_elements(deductions) d
  cross join lateral (select public.lot_nutrition_json((d.value ->> 'lot')::uuid) value) n;

  select bool_or(product.nutrition_is_estimated or (product.kcal is null and food.nutrition_is_estimated)),
         string_agg(distinct coalesce(product.nutrition_source, food.nutrition_source), '; ')
  into nutrition_estimated, nutrition_source
  from jsonb_array_elements(deductions) d
  join public.inventory_lots lot on lot.id = (d.value ->> 'lot')::uuid
  join public.products product on product.id = lot.product
  join public.base_foods food on food.id = product.food;

  insert into public.food_logs(
    label, kind, product, servings, occurred_at, time_precision,
    kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
    nutrition_is_estimated, nutrition_source, note
  ) values (
    coalesce(nullif(p_label,''), food_name), 'inventory', exact_product, total_servings, p_occurred_at, p_time_precision,
    (totals->>'kcal')::numeric, (totals->>'protein_g')::numeric, (totals->>'carbs_g')::numeric,
    (totals->>'fat_g')::numeric, (totals->>'fiber_g')::numeric, (totals->>'sugar_g')::numeric,
    (totals->>'sodium_mg')::numeric, coalesce(nutrition_estimated, false), nutrition_source, p_note
  ) returning id into log_id;

  for nutrients in select value from jsonb_array_elements(deductions)
  loop
    insert into public.inventory_events(lot, quantity_delta, reason, food_log, occurred_at, note)
    values ((nutrients->>'lot')::uuid, -(nutrients->>'quantity')::numeric, 'eaten', log_id, p_occurred_at, p_note);
  end loop;
  action_result := jsonb_build_object('status','consumed','id',log_id,'deductions',deductions);
  perform public.gpt_complete_request(p_request_id, action_result);
  return action_result;
end;
$$;

revoke all on function public.gpt_consume_inventory(uuid, numeric, text, timestamptz, text, uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.gpt_consume_inventory(uuid, numeric, text, timestamptz, text, uuid, text, text, uuid) to service_role;

drop function public.consume_product_purchase(uuid, numeric, numeric, text, numeric, boolean, text, text, timestamptz, text, text);

create function public.consume_product_purchase(
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
  prior_result := public.gpt_claim_request(p_request_id, 'consumeProductPurchase');
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

revoke all on function public.consume_product_purchase(uuid, numeric, numeric, text, numeric, numeric, text, boolean, text, date, uuid, text, timestamptz, text, text, text) from public, anon, authenticated;
grant execute on function public.consume_product_purchase(uuid, numeric, numeric, text, numeric, numeric, text, boolean, text, date, uuid, text, timestamptz, text, text, text) to service_role;

drop function public.gpt_add_grocery_lots(jsonb, text);

create function public.gpt_add_grocery_lots(p_items jsonb, p_source text, p_request_id uuid)
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
    prior_result := public.gpt_claim_request(p_request_id, 'addGroceryHaul');
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

revoke all on function public.gpt_add_grocery_lots(jsonb, text, uuid) from public, anon, authenticated;
grant execute on function public.gpt_add_grocery_lots(jsonb, text, uuid) to service_role;

drop function public.gpt_reconcile_inventory(jsonb, text);

create function public.gpt_reconcile_inventory(
  p_replacements jsonb,
  p_source text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  replacement jsonb;
  replacement_lot jsonb;
  lot_row public.inventory_lots%rowtype;
  prior_result jsonb;
  action_result jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior_result := public.gpt_claim_request(p_request_id, 'reconcilePantryInventory');
  if prior_result is not null then return prior_result; end if;
  if jsonb_typeof(p_replacements) <> 'array' then raise exception 'replacements must be an array'; end if;

  for replacement in select value from jsonb_array_elements(p_replacements)
  loop
    if not exists (select 1 from public.base_foods where id = (replacement ->> 'foodId')::uuid and archived_at is null) then
      raise exception 'Unknown active food: %', replacement ->> 'foodId';
    end if;
    for replacement_lot in select value from jsonb_array_elements(coalesce(replacement -> 'lots', '[]'::jsonb))
    loop
      if not exists (
        select 1 from public.products
        where id = (replacement_lot ->> 'productId')::uuid
          and food = (replacement ->> 'foodId')::uuid
          and archived_at is null
      ) then
        raise exception 'Replacement product % does not belong to active food %', replacement_lot ->> 'productId', replacement ->> 'foodId';
      end if;
    end loop;
    for lot_row in
      select lot.* from public.inventory_lots lot
      join public.products product on product.id = lot.product
      where product.food = (replacement ->> 'foodId')::uuid and lot.remaining_qty > 0
      for update of lot
    loop
      insert into public.inventory_events(lot, quantity_delta, reason, note)
      values (lot_row.id, -lot_row.remaining_qty, 'adjust', coalesce(p_source, 'GPT inventory reconciliation'));
    end loop;
    if jsonb_array_length(coalesce(replacement -> 'lots', '[]'::jsonb)) > 0 then
      perform public.gpt_add_grocery_lots(replacement -> 'lots', p_source, null);
    end if;
  end loop;
  action_result := jsonb_build_object('status', 'reconciled');
  perform public.gpt_complete_request(p_request_id, action_result);
  return action_result;
end;
$$;

revoke all on function public.gpt_reconcile_inventory(jsonb, text, uuid) from public, anon, authenticated;
grant execute on function public.gpt_reconcile_inventory(jsonb, text, uuid) to service_role;

drop function public.gpt_prepare_recipe(uuid, numeric, text, date, text, timestamptz);

create function public.gpt_prepare_recipe(
  p_recipe uuid,
  p_servings numeric,
  p_location text,
  p_use_by date,
  p_note text,
  p_prepared_at timestamptz,
  p_time_precision text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipe_row public.recipes%rowtype;
  prep_id uuid;
  lot_id uuid;
  prior_result jsonb;
  action_result jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior_result := public.gpt_claim_request(p_request_id, 'prepareFoodBatch');
  if prior_result is not null then return prior_result; end if;
  select * into recipe_row from public.recipes where id = p_recipe;
  if not found then raise exception 'Recipe does not exist'; end if;
  if p_servings <= 0 then raise exception 'servings must be positive'; end if;
  if p_prepared_at is null then raise exception 'preparedAt cannot be null'; end if;
  if p_time_precision not in ('exact', 'estimated', 'dateOnly') then raise exception 'Invalid timePrecision'; end if;
  prep_id := public.cook_recipe(p_recipe, p_servings / recipe_row.servings, p_servings, p_location);
  update public.preps set prepped_at = p_prepared_at, time_precision = p_time_precision, note = p_note where id = prep_id;
  update public.inventory_events set occurred_at = p_prepared_at where prep = prep_id;
  select id into lot_id from public.inventory_lots where prep = prep_id;
  update public.inventory_lots
  set use_by = p_use_by, acquired_at = p_prepared_at, acquired_time_precision = p_time_precision,
      acquisition_type = 'home', out_of_pocket_cost = 0, paid_by = 'household',
      cost_is_estimated = false, cost_source = 'Prepared from stocked ingredients', note = p_note
  where id = lot_id;
  action_result := jsonb_build_object('status', 'prepared', 'prepId', prep_id, 'lotId', lot_id, 'preparedAt', p_prepared_at, 'timePrecision', p_time_precision);
  perform public.gpt_complete_request(p_request_id, action_result);
  return action_result;
end;
$$;

revoke all on function public.gpt_prepare_recipe(uuid, numeric, text, date, text, timestamptz, text, uuid) from public, anon, authenticated;
grant execute on function public.gpt_prepare_recipe(uuid, numeric, text, date, text, timestamptz, text, uuid) to service_role;

drop function public.log_manual_consumption(text, text, timestamptz, jsonb, numeric, boolean, text, text);

create function public.log_manual_consumption(
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
  prior_result := public.gpt_claim_request(p_request_id, 'logManualConsumption');
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
    p_out_of_pocket_cost, p_cost_is_estimated, trim(p_cost_source), nullif(trim(coalesce(p_note, '')), '')
  ) returning * into log_row;

  action_result := jsonb_build_object('status', 'logged', 'id', log_row.id, 'nutritionStatus', log_row.nutrition_status);
  perform public.gpt_complete_request(p_request_id, action_result);
  return action_result;
end;
$$;

revoke all on function public.log_manual_consumption(text, text, timestamptz, text, jsonb, jsonb, jsonb, text, numeric, numeric, text, boolean, text, date, uuid, text) from public, anon, authenticated;
grant execute on function public.log_manual_consumption(text, text, timestamptz, text, jsonb, jsonb, jsonb, text, numeric, numeric, text, boolean, text, date, uuid, text) to service_role;

create or replace function public.gpt_update_product(p_product uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  product_row public.products%rowtype;
  updated_row public.products%rowtype;
  bad_key text;
  package_unit_id uuid;
  serving_unit_id uuid;
  package_base numeric;
  serving_base numeric;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'patch must be a non-empty object'; end if;
  select key into bad_key from jsonb_object_keys(p_patch) key
  where key <> all(array[
    'name','brand','barcode','emoji','aliases','packageQuantity','packageUnit',
    'servingQuantity','servingUnit','servingLabel','servingsPerPackage',
    'nutrition','estimatedCost','costSource','costAsOf'
  ]) limit 1;
  if bad_key is not null then raise exception 'Unsupported product edit field: %', bad_key; end if;
  if (p_patch ? 'packageQuantity') <> (p_patch ? 'packageUnit') then raise exception 'packageQuantity and packageUnit must be edited together'; end if;
  if (p_patch ? 'servingQuantity') <> (p_patch ? 'servingUnit') then raise exception 'servingQuantity and servingUnit must be edited together'; end if;
  if p_patch ? 'aliases' and jsonb_typeof(p_patch -> 'aliases') <> 'array' then raise exception 'aliases must be an array'; end if;
  if p_patch ? 'nutrition' and p_patch -> 'nutrition' <> 'null'::jsonb and jsonb_typeof(p_patch -> 'nutrition') <> 'object' then raise exception 'nutrition must be an object or null'; end if;

  select * into product_row from public.products where id = p_product and archived_at is null for update;
  if not found then raise exception 'Active product does not exist'; end if;
  if p_patch ? 'name' and trim(coalesce(p_patch ->> 'name', '')) = '' then raise exception 'name cannot be empty'; end if;
  package_unit_id := case when p_patch ? 'packageUnit' then public.resolve_measure_conversion(p_patch ->> 'packageUnit') else product_row.package_unit end;
  package_base := case when p_patch ? 'packageQuantity' then public.to_base_quantity(product_row.food, (p_patch ->> 'packageQuantity')::numeric, package_unit_id) else product_row.package_qty_base end;
  serving_unit_id := case when p_patch ? 'servingUnit' then public.resolve_measure_conversion(p_patch ->> 'servingUnit') else product_row.serving_unit end;
  serving_base := case when p_patch ? 'servingQuantity' then
    case when p_patch -> 'servingQuantity' = 'null'::jsonb then null else public.to_base_quantity(product_row.food, (p_patch ->> 'servingQuantity')::numeric, serving_unit_id) end
    else product_row.serving_qty_base end;

  update public.products set
    name = case when p_patch ? 'name' then trim(p_patch ->> 'name') else name end,
    brand = case when p_patch ? 'brand' then nullif(p_patch ->> 'brand', '') else brand end,
    barcode = case when p_patch ? 'barcode' then nullif(p_patch ->> 'barcode', '') else barcode end,
    emoji = case when p_patch ? 'emoji' then nullif(p_patch ->> 'emoji', '') else emoji end,
    aliases = case when p_patch ? 'aliases' then array(select jsonb_array_elements_text(p_patch -> 'aliases')) else aliases end,
    package_qty_base = package_base,
    package_unit = package_unit_id,
    serving_qty_base = serving_base,
    serving_unit = serving_unit_id,
    serving_label = case when p_patch ? 'servingLabel' then nullif(trim(coalesce(p_patch ->> 'servingLabel', '')), '') else serving_label end,
    servings_per_package = case when p_patch ? 'servingsPerPackage' then nullif(p_patch ->> 'servingsPerPackage', '')::numeric else servings_per_package end,
    nutrition_basis_qty = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,basisQuantity}', '')::numeric else nutrition_basis_qty end,
    kcal = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,calories}', '')::numeric else kcal end,
    protein_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,proteinG}', '')::numeric else protein_g end,
    carbs_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,carbsG}', '')::numeric else carbs_g end,
    fat_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fatG}', '')::numeric else fat_g end,
    fiber_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fiberG}', '')::numeric else fiber_g end,
    sugar_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sugarG}', '')::numeric else sugar_g end,
    sodium_mg = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sodiumMg}', '')::numeric else sodium_mg end,
    nutrition_source = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,source}', '') else nutrition_source end,
    nutrition_is_estimated = case when p_patch ? 'nutrition' then coalesce((p_patch #>> '{nutrition,estimated}')::boolean, false) else nutrition_is_estimated end,
    estimated_cost = case when p_patch ? 'estimatedCost' then nullif(p_patch ->> 'estimatedCost', '')::numeric else estimated_cost end,
    cost_source = case when p_patch ? 'costSource' then nullif(p_patch ->> 'costSource', '') else cost_source end,
    cost_as_of = case when p_patch ? 'costAsOf' then nullif(p_patch ->> 'costAsOf', '')::date else cost_as_of end,
    updated_at = now()
  where id = p_product returning * into updated_row;

  if updated_row.servings_per_package is not null and updated_row.package_qty_base is null then raise exception 'servingsPerPackage requires package quantity'; end if;
  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('product', p_product, to_jsonb(product_row), to_jsonb(updated_row));
  return jsonb_build_object('status', 'updated', 'id', p_product);
end;
$$;

create or replace function public.gpt_update_inventory_lot(p_lot uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  updated_row public.inventory_lots%rowtype;
  bad_key text;
  acquisition text;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'patch must be a non-empty object'; end if;
  select key into bad_key from jsonb_object_keys(p_patch) key
  where key <> all(array[
    'remainingQuantity','location','bestBy','acquiredAt','acquiredTimePrecision',
    'totalPrice','outOfPocketCost','paidBy','costIsEstimated','costSource','priceAsOf',
    'acquisitionType','note'
  ]) limit 1;
  if bad_key is not null then raise exception 'Unsupported inventory-lot edit field: %', bad_key; end if;
  if p_patch ? 'acquisitionType' then
    acquisition := p_patch ->> 'acquisitionType';
    if acquisition not in ('grocery', 'restaurant', 'takeout', 'office', 'gift', 'home', 'other') then raise exception 'Invalid acquisitionType'; end if;
  end if;
  if p_patch ? 'acquiredTimePrecision' and p_patch ->> 'acquiredTimePrecision' not in ('exact', 'estimated', 'dateOnly') then raise exception 'Invalid acquiredTimePrecision'; end if;

  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found then raise exception 'Inventory lot does not exist'; end if;
  if p_patch ? 'remainingQuantity' then
    if (p_patch ->> 'remainingQuantity')::numeric < 0 then raise exception 'remainingQuantity cannot be negative'; end if;
    perform public.set_inventory_lot_quantity(p_lot, (p_patch ->> 'remainingQuantity')::numeric, false);
  end if;
  update public.inventory_lots set
    location = case when p_patch ? 'location' then nullif(p_patch ->> 'location', '') else location end,
    use_by = case when p_patch ? 'bestBy' then nullif(p_patch ->> 'bestBy', '')::date else use_by end,
    acquired_at = case when p_patch ? 'acquiredAt' then (p_patch ->> 'acquiredAt')::timestamptz else acquired_at end,
    acquired_time_precision = case when p_patch ? 'acquiredTimePrecision' then p_patch ->> 'acquiredTimePrecision' else acquired_time_precision end,
    total_cost = case when p_patch ? 'totalPrice' then nullif(p_patch ->> 'totalPrice', '')::numeric else total_cost end,
    out_of_pocket_cost = case when p_patch ? 'outOfPocketCost' then nullif(p_patch ->> 'outOfPocketCost', '')::numeric else out_of_pocket_cost end,
    paid_by = case when p_patch ? 'paidBy' then nullif(trim(coalesce(p_patch ->> 'paidBy', '')), '') else paid_by end,
    cost_is_estimated = case when p_patch ? 'costIsEstimated' then (p_patch ->> 'costIsEstimated')::boolean else cost_is_estimated end,
    cost_source = case when p_patch ? 'costSource' then nullif(p_patch ->> 'costSource', '') else cost_source end,
    price_as_of = case when p_patch ? 'priceAsOf' then nullif(p_patch ->> 'priceAsOf', '')::date else price_as_of end,
    acquisition_type = case when p_patch ? 'acquisitionType' then acquisition else acquisition_type end,
    is_external = case when p_patch ? 'acquisitionType' then acquisition in ('restaurant', 'takeout') else is_external end,
    note = case when p_patch ? 'note' then nullif(p_patch ->> 'note', '') else note end
  where id = p_lot returning * into updated_row;
  if updated_row.total_cost is not null and updated_row.price_as_of is null then raise exception 'priceAsOf is required with totalPrice'; end if;
  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('inventory_lot', p_lot, to_jsonb(lot_row), to_jsonb(updated_row));
  return jsonb_build_object('status', 'updated', 'id', p_lot, 'acquisitionType', updated_row.acquisition_type, 'remainingQuantity', updated_row.remaining_qty);
end;
$$;

create or replace function public.gpt_update_consumption(p_food_log uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  log_row public.food_logs%rowtype;
  updated_row public.food_logs%rowtype;
  lot_row public.inventory_lots%rowtype;
  updated_lot public.inventory_lots%rowtype;
  bad_key text;
  bad_nutrition_key text;
  before_state jsonb;
  after_state jsonb;
  edits_purchase boolean;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'patch must be a non-empty object'; end if;
  select key into bad_key from jsonb_object_keys(p_patch) key
  where key <> all(array[
    'label','portionLabel','timestamp','timePrecision','note','nutrition','nutritionEstimate','components',
    'acquisitionType','totalPrice','outOfPocketCost','paidBy','priceAsOf',
    'purchaseTotalPrice','purchaseOutOfPocketCost','purchasePaidBy','purchasePriceAsOf',
    'costIsEstimated','costSource'
  ]) limit 1;
  if bad_key is not null then raise exception 'Unsupported consumption edit field: %', bad_key; end if;
  if p_patch ? 'nutrition' and p_patch -> 'nutrition' <> 'null'::jsonb and jsonb_typeof(p_patch -> 'nutrition') <> 'object' then raise exception 'nutrition must be an object or null'; end if;
  select key into bad_nutrition_key from jsonb_object_keys(case when jsonb_typeof(p_patch -> 'nutrition') = 'object' then p_patch -> 'nutrition' else '{}'::jsonb end) key
  where key <> all(array['calories','proteinG','carbsG','fatG','fiberG','sugarG','sodiumMg','estimated','source']) limit 1;
  if bad_nutrition_key is not null then raise exception 'Unsupported nutrition field: %', bad_nutrition_key; end if;
  if p_patch ? 'nutritionEstimate' and p_patch -> 'nutritionEstimate' <> 'null'::jsonb and jsonb_typeof(p_patch -> 'nutritionEstimate') <> 'object' then raise exception 'nutritionEstimate must be an object or null'; end if;
  if p_patch ? 'components' and jsonb_typeof(p_patch -> 'components') <> 'array' then raise exception 'components must be an array'; end if;
  if p_patch ? 'timePrecision' and p_patch ->> 'timePrecision' not in ('exact', 'estimated', 'dateOnly') then raise exception 'Invalid timePrecision'; end if;
  if p_patch ? 'acquisitionType' and p_patch ->> 'acquisitionType' not in ('grocery', 'restaurant', 'takeout', 'office', 'gift', 'home', 'other') then raise exception 'Invalid acquisitionType'; end if;

  select * into log_row from public.food_logs where id = p_food_log for update;
  if not found then raise exception 'Consumption event does not exist'; end if;
  if log_row.voided_at is not null then raise exception 'Voided consumption events cannot be edited'; end if;
  edits_purchase := p_patch ?| array['purchaseTotalPrice','purchaseOutOfPocketCost','purchasePaidBy','purchasePriceAsOf'];
  if edits_purchase then
    select * into lot_row from public.inventory_lots where acquisition_food_log = p_food_log for update;
    if not found then raise exception 'Purchase correction requires an originating purchase lot'; end if;
  end if;
  before_state := jsonb_build_object('consumption', to_jsonb(log_row), 'purchaseLot', case when lot_row.id is null then null else to_jsonb(lot_row) end);

  update public.food_logs set
    label = case when p_patch ? 'label' then trim(p_patch ->> 'label') else label end,
    portion_label = case when p_patch ? 'portionLabel' then nullif(trim(coalesce(p_patch ->> 'portionLabel', '')), '') else portion_label end,
    occurred_at = case when p_patch ? 'timestamp' then (p_patch ->> 'timestamp')::timestamptz else occurred_at end,
    time_precision = case when p_patch ? 'timePrecision' then p_patch ->> 'timePrecision' else time_precision end,
    note = case when p_patch ? 'note' then nullif(p_patch ->> 'note', '') else note end,
    kcal = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,calories}', '')::numeric else kcal end,
    protein_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,proteinG}', '')::numeric else protein_g end,
    carbs_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,carbsG}', '')::numeric else carbs_g end,
    fat_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fatG}', '')::numeric else fat_g end,
    fiber_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fiberG}', '')::numeric else fiber_g end,
    sugar_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sugarG}', '')::numeric else sugar_g end,
    sodium_mg = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sodiumMg}', '')::numeric else sodium_mg end,
    nutrition_is_estimated = case when p_patch ? 'nutrition' then coalesce((p_patch #>> '{nutrition,estimated}')::boolean, false) else nutrition_is_estimated end,
    nutrition_source = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,source}', '') else nutrition_source end,
    nutrition_estimate = case when p_patch ? 'nutritionEstimate' then p_patch -> 'nutritionEstimate' else nutrition_estimate end,
    components = case when p_patch ? 'components' then p_patch -> 'components' else components end,
    acquisition_type = case when p_patch ? 'acquisitionType' then p_patch ->> 'acquisitionType' else acquisition_type end,
    total_price = case when p_patch ? 'totalPrice' then nullif(p_patch ->> 'totalPrice', '')::numeric else total_price end,
    out_of_pocket_cost = case when p_patch ? 'outOfPocketCost' then nullif(p_patch ->> 'outOfPocketCost', '')::numeric else out_of_pocket_cost end,
    paid_by = case when p_patch ? 'paidBy' then nullif(trim(coalesce(p_patch ->> 'paidBy', '')), '') else paid_by end,
    price_as_of = case when p_patch ? 'priceAsOf' then nullif(p_patch ->> 'priceAsOf', '')::date else price_as_of end,
    cost = case when p_patch ? 'outOfPocketCost' then nullif(p_patch ->> 'outOfPocketCost', '')::numeric else cost end,
    cost_is_estimated = case when p_patch ? 'costIsEstimated' then (p_patch ->> 'costIsEstimated')::boolean else cost_is_estimated end,
    cost_source = case when p_patch ? 'costSource' then nullif(p_patch ->> 'costSource', '') else cost_source end
  where id = p_food_log returning * into updated_row;

  if p_patch ? 'timestamp' then
    update public.inventory_events set occurred_at = updated_row.occurred_at where food_log = p_food_log;
    update public.inventory_lots set acquired_at = updated_row.occurred_at where acquisition_food_log = p_food_log;
  end if;
  if lot_row.id is not null then
    update public.inventory_lots set
      total_cost = case when p_patch ? 'purchaseTotalPrice' then nullif(p_patch ->> 'purchaseTotalPrice', '')::numeric else total_cost end,
      out_of_pocket_cost = case when p_patch ? 'purchaseOutOfPocketCost' then nullif(p_patch ->> 'purchaseOutOfPocketCost', '')::numeric else out_of_pocket_cost end,
      paid_by = case when p_patch ? 'purchasePaidBy' then nullif(trim(coalesce(p_patch ->> 'purchasePaidBy', '')), '') else paid_by end,
      price_as_of = case when p_patch ? 'purchasePriceAsOf' then nullif(p_patch ->> 'purchasePriceAsOf', '')::date else price_as_of end,
      cost_is_estimated = case when p_patch ? 'costIsEstimated' then (p_patch ->> 'costIsEstimated')::boolean else cost_is_estimated end,
      cost_source = case when p_patch ? 'costSource' then nullif(p_patch ->> 'costSource', '') else cost_source end
    where id = lot_row.id returning * into updated_lot;
  end if;
  after_state := jsonb_build_object('consumption', to_jsonb(updated_row), 'purchaseLot', case when updated_lot.id is null then null else to_jsonb(updated_lot) end);
  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('consumption', p_food_log, before_state, after_state);
  return jsonb_build_object('status', 'updated', 'id', p_food_log, 'lotId', case when updated_lot.id is null then null else updated_lot.id end);
end;
$$;

create function public.gpt_create_manual_prepared_batch(
  p_label text,
  p_servings numeric,
  p_location text,
  p_prepared_at timestamptz,
  p_time_precision text,
  p_use_by date,
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
  prep_id uuid;
  lot_id uuid;
  prior_result jsonb;
  action_result jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior_result := public.gpt_claim_request(p_request_id, 'prepareFoodBatch');
  if prior_result is not null then return prior_result; end if;
  if nullif(trim(coalesce(p_label, '')), '') is null then raise exception 'label is required'; end if;
  if p_servings <= 0 then raise exception 'servings must be positive'; end if;
  if nullif(trim(coalesce(p_location, '')), '') is null then raise exception 'location is required'; end if;
  if p_time_precision not in ('exact', 'estimated', 'dateOnly') then raise exception 'Invalid timePrecision'; end if;
  if p_nutrition is not null and jsonb_typeof(p_nutrition) <> 'object' then raise exception 'nutrition must be an object or null'; end if;
  if p_nutrition_estimate is not null and jsonb_typeof(p_nutrition_estimate) <> 'object' then raise exception 'nutritionEstimate must be an object or null'; end if;
  if coalesce(jsonb_typeof(p_components), 'array') <> 'array' then raise exception 'components must be an array'; end if;
  if p_acquisition_type not in ('grocery', 'restaurant', 'takeout', 'office', 'gift', 'home', 'other') then raise exception 'Invalid acquisitionType'; end if;
  if p_total_price is not null and p_total_price < 0 then raise exception 'totalPrice cannot be negative'; end if;
  if p_out_of_pocket_cost is null or p_out_of_pocket_cost < 0 then raise exception 'outOfPocketCost must be stated and nonnegative'; end if;
  if nullif(trim(coalesce(p_paid_by, '')), '') is null then raise exception 'paidBy is required'; end if;
  if p_cost_is_estimated is null then raise exception 'costIsEstimated is required'; end if;
  if nullif(trim(coalesce(p_cost_source, '')), '') is null then raise exception 'costSource is required'; end if;
  if p_total_price is not null and p_price_as_of is null then raise exception 'priceAsOf is required with totalPrice'; end if;

  insert into public.preps(
    recipe, label, actual_yield_qty, prepped_at, time_precision,
    kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
    nutrition_source, nutrition_is_estimated, nutrition_estimate, components, note
  ) values (
    null, trim(p_label), p_servings, p_prepared_at, p_time_precision,
    nullif(p_nutrition ->> 'calories', '')::numeric,
    nullif(p_nutrition ->> 'proteinG', '')::numeric,
    nullif(p_nutrition ->> 'carbsG', '')::numeric,
    nullif(p_nutrition ->> 'fatG', '')::numeric,
    nullif(p_nutrition ->> 'fiberG', '')::numeric,
    nullif(p_nutrition ->> 'sugarG', '')::numeric,
    nullif(p_nutrition ->> 'sodiumMg', '')::numeric,
    nullif(trim(coalesce(p_nutrition ->> 'source', '')), ''),
    coalesce((p_nutrition ->> 'estimated')::boolean, false),
    p_nutrition_estimate, coalesce(p_components, '[]'::jsonb), p_note
  ) returning id into prep_id;

  insert into public.inventory_lots(
    prep, initial_qty, remaining_qty, total_cost, out_of_pocket_cost, paid_by,
    cost_is_estimated, cost_source, price_as_of, use_by, location, acquired_at,
    acquired_time_precision, acquisition_type, is_external, note
  ) values (
    prep_id, p_servings, p_servings, p_total_price, p_out_of_pocket_cost, trim(p_paid_by),
    p_cost_is_estimated, trim(p_cost_source), p_price_as_of, p_use_by, p_location, p_prepared_at,
    p_time_precision, p_acquisition_type, p_acquisition_type in ('restaurant', 'takeout'), p_note
  ) returning id into lot_id;

  action_result := jsonb_build_object('status', 'prepared', 'prepId', prep_id, 'batchId', lot_id, 'servingsRemaining', p_servings);
  perform public.gpt_complete_request(p_request_id, action_result);
  return action_result;
end;
$$;

revoke all on function public.gpt_create_manual_prepared_batch(text, numeric, text, timestamptz, text, date, jsonb, jsonb, jsonb, text, numeric, numeric, text, boolean, text, date, uuid, text) from public, anon, authenticated;
grant execute on function public.gpt_create_manual_prepared_batch(text, numeric, text, timestamptz, text, date, jsonb, jsonb, jsonb, text, numeric, numeric, text, boolean, text, date, uuid, text) to service_role;

drop function public.gpt_consume_prepared(uuid, numeric, timestamptz, text, text);

create function public.gpt_consume_prepared(
  p_lot uuid,
  p_quantity numeric,
  p_occurred_at timestamptz,
  p_time_precision text,
  p_request_id uuid,
  p_label text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  prep_row public.preps%rowtype;
  recipe_row public.recipes%rowtype;
  nutrients jsonb;
  log_id uuid;
  prior_result jsonb;
  action_result jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior_result := public.gpt_claim_request(p_request_id, 'consumePreparedFood');
  if prior_result is not null then return prior_result; end if;
  if p_time_precision not in ('exact', 'estimated', 'dateOnly') then raise exception 'Invalid timePrecision'; end if;
  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found or lot_row.prep is null then raise exception 'Prepared lot does not exist'; end if;
  if p_quantity <= 0 or lot_row.remaining_qty < p_quantity then raise exception 'Invalid prepared quantity'; end if;
  select * into prep_row from public.preps where id = lot_row.prep and voided_at is null;
  if not found then raise exception 'Preparation does not exist'; end if;
  if prep_row.recipe is not null then select * into recipe_row from public.recipes where id = prep_row.recipe; end if;
  nutrients := public.lot_nutrition_json(p_lot);
  insert into public.food_logs(
    label, kind, recipe, servings, occurred_at, time_precision,
    kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
    nutrition_is_estimated, nutrition_source, nutrition_estimate, components,
    acquisition_type, total_price, out_of_pocket_cost, paid_by, price_as_of, note
  ) values (
    coalesce(nullif(p_label, ''), recipe_row.name, prep_row.label), 'prepared', prep_row.recipe, p_quantity, p_occurred_at, p_time_precision,
    (nutrients ->> 'kcal')::numeric * p_quantity,
    (nutrients ->> 'protein_g')::numeric * p_quantity,
    (nutrients ->> 'carbs_g')::numeric * p_quantity,
    (nutrients ->> 'fat_g')::numeric * p_quantity,
    (nutrients ->> 'fiber_g')::numeric * p_quantity,
    (nutrients ->> 'sugar_g')::numeric * p_quantity,
    (nutrients ->> 'sodium_mg')::numeric * p_quantity,
    prep_row.nutrition_is_estimated, prep_row.nutrition_source, prep_row.nutrition_estimate, prep_row.components,
    lot_row.acquisition_type,
    case when lot_row.total_cost is null then null else round(lot_row.total_cost * p_quantity / lot_row.initial_qty, 2) end,
    case when lot_row.out_of_pocket_cost is null then null else round(lot_row.out_of_pocket_cost * p_quantity / lot_row.initial_qty, 2) end,
    lot_row.paid_by, lot_row.price_as_of, p_note
  ) returning id into log_id;
  insert into public.inventory_events(lot, quantity_delta, reason, food_log, occurred_at, note)
  values (p_lot, -p_quantity, 'eaten', log_id, p_occurred_at, p_note);
  action_result := jsonb_build_object('status', 'consumed', 'id', log_id, 'batchId', p_lot, 'servingsRemaining', lot_row.remaining_qty - p_quantity);
  perform public.gpt_complete_request(p_request_id, action_result);
  return action_result;
end;
$$;

revoke all on function public.gpt_consume_prepared(uuid, numeric, timestamptz, text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.gpt_consume_prepared(uuid, numeric, timestamptz, text, uuid, text, text) to service_role;

-- Merge preserves all historical references and archives the duplicate. It can
-- also archive an emptied source food when that canonical definition was itself
-- created only because lookup failed.
create function public.gpt_merge_products(
  p_source uuid,
  p_target uuid,
  p_archive_source_food boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_row public.products%rowtype;
  target_row public.products%rowtype;
  source_food public.base_foods%rowtype;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if p_source = p_target then raise exception 'sourceProductId and targetProductId must differ'; end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'reason is required'; end if;
  select * into source_row from public.products where id = p_source and archived_at is null for update;
  if not found then raise exception 'Active source product does not exist'; end if;
  select * into target_row from public.products where id = p_target and archived_at is null for update;
  if not found then raise exception 'Active target product does not exist'; end if;
  select * into source_food from public.base_foods where id = source_row.food for update;

  update public.inventory_lots set product = p_target where product = p_source;
  update public.food_logs set product = p_target where product = p_source;
  update public.products set archived_at = now(), merged_into = p_target, updated_at = now() where id = p_source;
  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('product', p_source, to_jsonb(source_row), jsonb_build_object('archivedAt', now(), 'mergedInto', p_target, 'reason', trim(p_reason)));

  if p_archive_source_food and source_row.food <> target_row.food then
    if exists (select 1 from public.products where food = source_row.food and archived_at is null) then
      raise exception 'Source food still has active products';
    end if;
    if exists (select 1 from public.recipe_ingredients where ingredient = source_row.food) then
      raise exception 'Source food is still used by recipes';
    end if;
    update public.base_foods set archived_at = now(), merged_into = target_row.food, updated_at = now() where id = source_row.food;
    insert into public.record_edits(resource, record_id, before_state, after_state)
    values ('food', source_row.food, to_jsonb(source_food), jsonb_build_object('archivedAt', now(), 'mergedInto', target_row.food, 'reason', trim(p_reason)));
  end if;

  return jsonb_build_object('status', 'merged', 'sourceProductId', p_source, 'targetProductId', p_target, 'sourceFoodArchived', p_archive_source_food and source_row.food <> target_row.food);
end;
$$;

revoke all on function public.gpt_merge_products(uuid, uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.gpt_merge_products(uuid, uuid, boolean, text) to service_role;

create function public.gpt_archive_definition(
  p_resource text,
  p_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  before_state jsonb;
  after_state jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if p_resource not in ('food', 'product') then raise exception 'resource must be food or product'; end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'reason is required'; end if;
  if p_resource = 'product' then
    select to_jsonb(product) into before_state from public.products product where id = p_id and archived_at is null for update;
    if before_state is null then raise exception 'Active product does not exist'; end if;
    if exists (select 1 from public.inventory_lots where product = p_id and remaining_qty > 0) then raise exception 'Product still has positive inventory; merge or reconcile it first'; end if;
    update public.products set archived_at = now(), updated_at = now() where id = p_id returning to_jsonb(products) into after_state;
  else
    select to_jsonb(food) into before_state from public.base_foods food where id = p_id and archived_at is null for update;
    if before_state is null then raise exception 'Active food does not exist'; end if;
    if exists (select 1 from public.products where food = p_id and archived_at is null) or exists (select 1 from public.recipe_ingredients where ingredient = p_id) then
      raise exception 'Food still has active references; merge or archive them first';
    end if;
    update public.base_foods set archived_at = now(), updated_at = now() where id = p_id returning to_jsonb(base_foods) into after_state;
  end if;
  insert into public.record_edits(resource, record_id, before_state, after_state)
  values (p_resource, p_id, before_state, after_state || jsonb_build_object('archiveReason', trim(p_reason)));
  return jsonb_build_object('status', 'archived', 'resource', p_resource, 'id', p_id);
end;
$$;

revoke all on function public.gpt_archive_definition(text, uuid, text) from public, anon, authenticated;
grant execute on function public.gpt_archive_definition(text, uuid, text) to service_role;
