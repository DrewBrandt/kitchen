-- Let GPT inventory consumption target a known physical lot instead of always
-- falling back to FEFO, and make food_logs.servings mean nutritional servings
-- rather than the caller's arbitrary input quantity.

drop function public.gpt_consume_inventory(uuid, numeric, text, timestamptz, text, text);

create function public.gpt_consume_inventory(
  p_food uuid,
  p_quantity numeric,
  p_unit text,
  p_occurred_at timestamptz default now(),
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
  serving_size numeric;
  total_servings numeric := 0;
  lot_row public.inventory_lots%rowtype;
  nutrients jsonb;
  totals jsonb := jsonb_build_object('kcal',0,'protein_g',0,'carbs_g',0,'fat_g',0,'fiber_g',0,'sugar_g',0,'sodium_mg',0);
  deductions jsonb := '[]'::jsonb;
  food_name text;
  exact_product uuid;
  log_id uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;

  select name into food_name from public.base_foods where id = p_food;
  if food_name is null then raise exception 'Food does not exist'; end if;

  requested_base := public.to_base_quantity(p_food, p_quantity, public.resolve_measure_conversion(p_unit));
  needed := requested_base;

  if p_lot is not null then
    select lot.* into lot_row
    from public.inventory_lots lot
    join public.products product on product.id = lot.product
    where lot.id = p_lot and product.food = p_food
    for update of lot;

    if not found then raise exception 'Inventory lot does not exist for this food'; end if;
    if lot_row.remaining_qty < needed then
      raise exception 'Lot has only % remaining', lot_row.remaining_qty;
    end if;

    exact_product := lot_row.product;
    taken := needed;
    nutrients := public.lot_nutrition_json(lot_row.id);
    select coalesce(product.serving_qty_base, product.nutrition_basis_qty, food.nutrition_basis_qty)
      into serving_size
    from public.products product
    join public.base_foods food on food.id = product.food
    where product.id = lot_row.product;
    total_servings := taken / serving_size;
    totals := jsonb_build_object(
      'kcal', coalesce((nutrients ->> 'kcal')::numeric,0) * taken,
      'protein_g', coalesce((nutrients ->> 'protein_g')::numeric,0) * taken,
      'carbs_g', coalesce((nutrients ->> 'carbs_g')::numeric,0) * taken,
      'fat_g', coalesce((nutrients ->> 'fat_g')::numeric,0) * taken,
      'fiber_g', coalesce((nutrients ->> 'fiber_g')::numeric,0) * taken,
      'sugar_g', coalesce((nutrients ->> 'sugar_g')::numeric,0) * taken,
      'sodium_mg', coalesce((nutrients ->> 'sodium_mg')::numeric,0) * taken
    );
    deductions := jsonb_build_array(jsonb_build_object('lot', lot_row.id, 'quantity', taken));
    needed := 0;
  else
    for lot_row in
      select lot.*
      from public.inventory_lots lot
      join public.products product on product.id = lot.product
      where product.food = p_food and lot.remaining_qty > 0
      order by lot.use_by asc nulls last, lot.acquired_at, lot.id
      for update of lot
    loop
      exit when needed <= 0.0000001;
      taken := least(needed, lot_row.remaining_qty);
      nutrients := public.lot_nutrition_json(lot_row.id);
      select coalesce(product.serving_qty_base, product.nutrition_basis_qty, food.nutrition_basis_qty)
        into serving_size
      from public.products product
      join public.base_foods food on food.id = product.food
      where product.id = lot_row.product;
      total_servings := total_servings + taken / serving_size;
      totals := jsonb_build_object(
        'kcal', (totals ->> 'kcal')::numeric + coalesce((nutrients ->> 'kcal')::numeric,0) * taken,
        'protein_g', (totals ->> 'protein_g')::numeric + coalesce((nutrients ->> 'protein_g')::numeric,0) * taken,
        'carbs_g', (totals ->> 'carbs_g')::numeric + coalesce((nutrients ->> 'carbs_g')::numeric,0) * taken,
        'fat_g', (totals ->> 'fat_g')::numeric + coalesce((nutrients ->> 'fat_g')::numeric,0) * taken,
        'fiber_g', (totals ->> 'fiber_g')::numeric + coalesce((nutrients ->> 'fiber_g')::numeric,0) * taken,
        'sugar_g', (totals ->> 'sugar_g')::numeric + coalesce((nutrients ->> 'sugar_g')::numeric,0) * taken,
        'sodium_mg', (totals ->> 'sodium_mg')::numeric + coalesce((nutrients ->> 'sodium_mg')::numeric,0) * taken
      );
      deductions := deductions || jsonb_build_array(jsonb_build_object('lot', lot_row.id, 'quantity', taken));
      needed := needed - taken;
    end loop;
  end if;

  if needed > 0.0000001 then raise exception 'Not enough inventory for %', food_name; end if;

  insert into public.food_logs(
    label, kind, product, servings, occurred_at,
    kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, note
  ) values (
    coalesce(nullif(p_label,''), food_name), 'inventory', exact_product, total_servings, p_occurred_at,
    (totals->>'kcal')::numeric, (totals->>'protein_g')::numeric, (totals->>'carbs_g')::numeric,
    (totals->>'fat_g')::numeric, (totals->>'fiber_g')::numeric, (totals->>'sugar_g')::numeric,
    (totals->>'sodium_mg')::numeric, p_note
  ) returning id into log_id;

  for nutrients in select value from jsonb_array_elements(deductions)
  loop
    insert into public.inventory_events(lot, quantity_delta, reason, food_log, occurred_at, note)
    values ((nutrients->>'lot')::uuid, -(nutrients->>'quantity')::numeric, 'eaten', log_id, p_occurred_at, p_note);
  end loop;

  return jsonb_build_object('status','consumed','id',log_id,'deductions',deductions);
end;
$$;

revoke all on function public.gpt_consume_inventory(uuid,numeric,text,timestamptz,text,text,uuid) from public, anon, authenticated;
grant execute on function public.gpt_consume_inventory(uuid,numeric,text,timestamptz,text,text,uuid) to service_role;

-- Older food-only inventory logs stored crackers, slices, and other base units
-- directly in servings. Recompute them from the product serving sizes recorded
-- by their immutable lot deductions. Product-targeted logs were already correct.
with normalized as (
  select
    log.id,
    sum(
      abs(event.quantity_delta)
      / coalesce(product.serving_qty_base, product.nutrition_basis_qty, food.nutrition_basis_qty)
    ) as servings
  from public.food_logs log
  join public.inventory_events event
    on event.food_log = log.id
   and event.reason = 'eaten'
  join public.inventory_lots lot on lot.id = event.lot
  join public.products product on product.id = lot.product
  join public.base_foods food on food.id = product.food
  where log.kind = 'inventory'
    and log.product is null
  group by log.id
)
update public.food_logs log
set servings = normalized.servings
from normalized
where log.id = normalized.id;
