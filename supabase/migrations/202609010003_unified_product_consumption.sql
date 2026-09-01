-- Products are definitions. Whether a purchase came from pantry stock or was
-- bought for immediate consumption belongs to the lot, not the product.
alter table public.inventory_lots
  add column is_external boolean not null default false;

comment on column public.inventory_lots.is_external is
  'True when this lot was acquired away from home rather than through ordinary grocery stocking.';

-- Preserve the old classification on any real lots before removing it from the
-- reusable product definition.
update public.inventory_lots lot
set is_external = true
from public.products product
where product.id = lot.product
  and product.is_external;

-- Turn legacy direct external/custom food logs into the same product -> lot ->
-- eaten-event ledger used by every other purchased product. Historical rows do
-- not invent a price: a known product estimate is used when available.
do $$
declare
  log_row public.food_logs%rowtype;
  product_row public.products%rowtype;
  food_id uuid;
  product_id uuid;
  lot_id uuid;
  count_unit uuid;
  quantity numeric;
  per_serving numeric;
  migrated_cost numeric;
begin
  select id into count_unit
  from public.measure_conversions
  where measure_style = 'discrete' and base_to_this_ratio = 1
  order by full_name
  limit 1;

  if count_unit is null then raise exception 'A count unit is required to migrate food logs'; end if;

  for log_row in
    select log.*
    from public.food_logs log
    where log.kind in ('external', 'custom')
      and not exists (
        select 1 from public.inventory_events event where event.food_log = log.id
      )
    order by log.occurred_at, log.id
  loop
    quantity := coalesce(log_row.servings, 1);
    if quantity <= 0 then quantity := 1; end if;
    product_id := log_row.product;

    if product_id is null then
      select food.id into food_id
      from public.base_foods food
      where lower(food.name) = lower(log_row.label)
      limit 1;

      if food_id is null then
        insert into public.base_foods(
          name, plural, measure_style, display_unit, nutrition_basis_qty,
          kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
          nutrition_is_estimated
        ) values (
          log_row.label, log_row.label, 'discrete', count_unit, 1,
          coalesce(log_row.kcal, 0) / quantity,
          coalesce(log_row.protein_g, 0) / quantity,
          coalesce(log_row.carbs_g, 0) / quantity,
          coalesce(log_row.fat_g, 0) / quantity,
          coalesce(log_row.fiber_g, 0) / quantity,
          coalesce(log_row.sugar_g, 0) / quantity,
          coalesce(log_row.sodium_mg, 0) / quantity,
          log_row.nutrition_is_estimated
        ) returning id into food_id;
      end if;

      select product.id into product_id
      from public.products product
      where product.food = food_id
        and lower(product.name) = lower(log_row.label)
      order by product.created_at
      limit 1;

      if product_id is null then
        insert into public.products(
          food, name, package_qty_base, package_unit, serving_qty_base,
          nutrition_basis_qty, kcal, protein_g, carbs_g, fat_g, fiber_g,
          sugar_g, sodium_mg, nutrition_is_estimated
        ) values (
          food_id, log_row.label, 1, count_unit, 1, 1,
          coalesce(log_row.kcal, 0) / quantity,
          coalesce(log_row.protein_g, 0) / quantity,
          coalesce(log_row.carbs_g, 0) / quantity,
          coalesce(log_row.fat_g, 0) / quantity,
          coalesce(log_row.fiber_g, 0) / quantity,
          coalesce(log_row.sugar_g, 0) / quantity,
          coalesce(log_row.sodium_mg, 0) / quantity,
          log_row.nutrition_is_estimated
        ) returning id into product_id;
      end if;

      update public.food_logs set product = product_id where id = log_row.id;
    end if;

    select * into product_row from public.products where id = product_id;
    per_serving := case
      when product_row.estimated_cost is not null and product_row.package_qty_base > 0
        then product_row.estimated_cost / product_row.package_qty_base
      else null
    end;
    migrated_cost := case when per_serving is null then null else per_serving * quantity end;

    insert into public.inventory_lots(
      product, initial_qty, remaining_qty, total_cost, cost_is_estimated,
      cost_source, acquired_at, is_external, note
    ) values (
      product_id, quantity, quantity, migrated_cost, migrated_cost is not null,
      case when migrated_cost is null then null else coalesce(product_row.cost_source, 'Migrated product estimate') end,
      log_row.occurred_at, true, 'Migrated from legacy direct food log'
    ) returning id into lot_id;

    insert into public.inventory_events(lot, quantity_delta, reason, food_log, occurred_at, note)
    values (lot_id, -quantity, 'eaten', log_row.id, log_row.occurred_at, log_row.note);
  end loop;
end;
$$;

-- Existing linked events inherit the legacy external classification, then every
-- legacy direct kind becomes the ordinary inventory kind backed by its event.
update public.inventory_lots lot
set is_external = true
from public.inventory_events event
join public.food_logs log on log.id = event.food_log
where event.lot = lot.id
  and log.kind in ('external', 'custom');

update public.food_logs
set kind = 'inventory'
where kind in ('external', 'custom');

alter table public.food_logs
  drop constraint food_logs_kind_check,
  add constraint food_logs_kind_check check (
    kind in ('inventory', 'recipe', 'meal', 'prepared')
  );

drop function public.gpt_save_external_food(jsonb);

-- Generic grocery and reconciliation paths now accept every product definition.
create or replace function public.gpt_add_grocery_lots(p_items jsonb, p_source text default null)
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
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'items must be a non-empty array';
  end if;

  for item in select value from jsonb_array_elements(p_items)
  loop
    select * into product_row from public.products where id = (item ->> 'productId')::uuid;
    if not found then raise exception 'Unknown product: %', item ->> 'productId'; end if;
    unit_id := public.resolve_measure_conversion(item ->> 'unit');
    base_quantity := public.to_base_quantity(product_row.food, (item ->> 'quantity')::numeric, unit_id);
    insert into public.inventory_lots(product, initial_qty, remaining_qty, total_cost, cost_is_estimated, cost_source, use_by, location, note)
    values (
      product_row.id, base_quantity, base_quantity,
      nullif(item ->> 'totalCost', '')::numeric,
      coalesce((item ->> 'costIsEstimated')::boolean, false), p_source,
      nullif(item ->> 'bestBy', '')::date,
      coalesce(nullif(item ->> 'location', ''), 'pantry'),
      nullif(item ->> 'note', '')
    ) returning id into lot_id;
    created_ids := created_ids || lot_id;
  end loop;
  return jsonb_build_object('status', 'created', 'lotIds', created_ids);
end;
$$;

create or replace function public.gpt_reconcile_inventory(p_replacements jsonb, p_source text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  replacement jsonb;
  replacement_lot jsonb;
  lot_row public.inventory_lots%rowtype;
  created jsonb := '[]'::jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_replacements) <> 'array' then raise exception 'replacements must be an array'; end if;

  for replacement in select value from jsonb_array_elements(p_replacements)
  loop
    if not exists (select 1 from public.base_foods where id = (replacement ->> 'foodId')::uuid) then
      raise exception 'Unknown food: %', replacement ->> 'foodId';
    end if;
    for replacement_lot in select value from jsonb_array_elements(coalesce(replacement -> 'lots', '[]'::jsonb))
    loop
      if not exists (
        select 1 from public.products
        where id = (replacement_lot ->> 'productId')::uuid
          and food = (replacement ->> 'foodId')::uuid
      ) then
        raise exception 'Replacement product % does not belong to food %', replacement_lot ->> 'productId', replacement ->> 'foodId';
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
      created := created || public.gpt_add_grocery_lots(replacement -> 'lots', p_source);
    end if;
  end loop;
  return jsonb_build_object('status', 'reconciled');
end;
$$;

-- Buying a product and eating any portion of it is one transaction: acquire a
-- classified lot, consume the reported portion through the standard ledger,
-- and retain the remainder at its reported storage location.
create function public.consume_product_purchase(
  p_product uuid,
  p_purchased_quantity numeric,
  p_consumed_quantity numeric,
  p_location text default null,
  p_occurred_at timestamptz default now(),
  p_total_cost numeric default null,
  p_cost_is_estimated boolean default false,
  p_cost_source text default null,
  p_label text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  product_row public.products%rowtype;
  lot_id uuid;
  log_id uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if p_purchased_quantity <= 0 then raise exception 'Purchased quantity must be positive'; end if;
  if p_consumed_quantity < 0 then raise exception 'Consumed quantity cannot be negative'; end if;
  if p_consumed_quantity > p_purchased_quantity then raise exception 'Consumed quantity cannot exceed purchased quantity'; end if;
  if p_consumed_quantity < p_purchased_quantity and nullif(p_location, '') is null then
    raise exception 'A location is required when purchased food remains';
  end if;
  if p_total_cost is not null and p_total_cost < 0 then raise exception 'Total cost cannot be negative'; end if;

  select * into product_row from public.products where id = p_product for update;
  if not found then raise exception 'Product does not exist'; end if;

  insert into public.inventory_lots(
    product, initial_qty, remaining_qty, total_cost, cost_is_estimated,
    cost_source, acquired_at, is_external, location, note
  ) values (
    p_product, p_purchased_quantity, p_purchased_quantity, p_total_cost, p_cost_is_estimated,
    p_cost_source, p_occurred_at, true, nullif(p_location, ''), p_note
  ) returning id into lot_id;

  if p_consumed_quantity > 0 then
    log_id := public.consume_inventory_lot(lot_id, p_consumed_quantity, p_occurred_at);
    update public.food_logs
    set label = coalesce(nullif(p_label, ''), label), note = p_note
    where id = log_id;
  end if;

  update public.products
  set use_count = use_count + case when p_consumed_quantity > 0 then 1 else 0 end,
      last_used_at = case when p_consumed_quantity > 0 then p_occurred_at else last_used_at end,
      estimated_cost = case
        when p_total_cost is null then estimated_cost
        else round(p_total_cost * package_qty_base / p_purchased_quantity, 2)
      end,
      cost_source = case when p_total_cost is null then cost_source else coalesce(nullif(p_cost_source, ''), 'Immediate purchase') end,
      cost_as_of = case
        when p_total_cost is null then cost_as_of
        else (p_occurred_at at time zone (select time_zone from public.app_settings where singleton))::date
      end
  where id = p_product;

  return jsonb_build_object(
    'status', case when p_consumed_quantity > 0 then 'consumed' else 'acquired' end,
    'lotId', lot_id,
    'logId', log_id,
    'remainingQuantity', p_purchased_quantity - p_consumed_quantity,
    'location', nullif(p_location, '')
  );
end;
$$;

revoke all on function public.consume_product_purchase(uuid, numeric, numeric, text, timestamptz, numeric, boolean, text, text, text) from public, anon;
grant execute on function public.consume_product_purchase(uuid, numeric, numeric, text, timestamptz, numeric, boolean, text, text, text) to authenticated, service_role;

alter table public.products drop column is_external;
