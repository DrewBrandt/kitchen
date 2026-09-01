update public.base_foods food
set display_unit = unit.id
from public.measure_conversions unit
where unit.short_name = case food.measure_style
  when 'weight' then 'oz'
  when 'volume' then 'cup'
  else 'ct'
end;

create function public.set_us_display_unit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  current_short_name text;
begin
  select short_name into current_short_name
  from public.measure_conversions
  where id = new.display_unit;

  if new.display_unit is null
     or (new.measure_style = 'weight' and current_short_name in ('g', 'kg'))
     or (new.measure_style = 'volume' and current_short_name in ('mL', 'L')) then
    select id into new.display_unit
    from public.measure_conversions
    where short_name = case new.measure_style
      when 'weight' then 'oz'
      when 'volume' then 'cup'
      else 'ct'
    end;
  end if;
  return new;
end;
$$;

create trigger base_foods_us_display_unit
before insert or update of measure_style, display_unit on public.base_foods
for each row execute function public.set_us_display_unit();

alter table public.meal_plans
  drop constraint meal_plans_made_session,
  add column made_at timestamptz;

update public.meal_plans
set made_at = updated_at
where status = 'made' and made_at is null;

create function public.consume_inventory_lot(
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
  nutrition_multiplier numeric;
  new_log uuid;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may consume inventory' using errcode = '42501';
  end if;
  if p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;

  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found or lot_row.product is null then raise exception 'Inventory lot does not exist'; end if;
  if lot_row.remaining_qty < p_quantity then raise exception 'Lot has only % remaining', lot_row.remaining_qty; end if;

  select * into product_row from public.products where id = lot_row.product;
  nutrition_multiplier := p_quantity / coalesce(nullif(product_row.nutrition_basis_qty, 0), 1);

  insert into public.food_logs(
    label, kind, product, servings, occurred_at,
    kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
    nutrition_is_estimated
  ) values (
    concat_ws(' · ', product_row.brand, product_row.name), 'inventory', product_row.id,
    p_quantity / coalesce(nullif(product_row.serving_qty_base, 0), 1), p_occurred_at,
    coalesce(product_row.kcal, 0) * nutrition_multiplier,
    coalesce(product_row.protein_g, 0) * nutrition_multiplier,
    coalesce(product_row.carbs_g, 0) * nutrition_multiplier,
    coalesce(product_row.fat_g, 0) * nutrition_multiplier,
    coalesce(product_row.fiber_g, 0) * nutrition_multiplier,
    coalesce(product_row.sugar_g, 0) * nutrition_multiplier,
    coalesce(product_row.sodium_mg, 0) * nutrition_multiplier,
    product_row.nutrition_is_estimated
  ) returning id into new_log;

  insert into public.inventory_events(lot, quantity_delta, reason, food_log, occurred_at)
  values (p_lot, -p_quantity, 'eaten', new_log, p_occurred_at);
  return new_log;
end;
$$;

create function public.set_inventory_lot_quantity(
  p_lot uuid,
  p_remaining numeric,
  p_discard boolean default false
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  quantity_change numeric;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may adjust inventory' using errcode = '42501';
  end if;
  if p_remaining < 0 then raise exception 'Remaining quantity cannot be negative'; end if;

  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found then raise exception 'Inventory lot does not exist'; end if;
  quantity_change := p_remaining - lot_row.remaining_qty;
  if quantity_change = 0 then return; end if;
  if p_discard and p_remaining <> 0 then raise exception 'Discarding a lot must set it to zero'; end if;

  insert into public.inventory_events(lot, quantity_delta, reason, note)
  values (p_lot, quantity_change, (case when p_discard then 'waste' else 'adjust' end)::public.inventory_event_reason, case when p_discard then 'Discarded from lot details' else 'Adjusted from lot details' end);
end;
$$;

revoke all on function public.consume_inventory_lot(uuid, numeric, timestamptz) from public, anon;
grant execute on function public.consume_inventory_lot(uuid, numeric, timestamptz) to authenticated;
revoke all on function public.set_inventory_lot_quantity(uuid, numeric, boolean) from public, anon;
grant execute on function public.set_inventory_lot_quantity(uuid, numeric, boolean) to authenticated;
