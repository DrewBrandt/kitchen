-- Keep the purchase transaction free of unused row state so database linting
-- remains a useful signal.
create or replace function public.consume_product_purchase(
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

  perform 1 from public.products where id = p_product for update;
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
