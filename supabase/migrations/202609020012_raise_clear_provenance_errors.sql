-- Surface actionable domain errors before PostgreSQL's generic CHECK messages.
-- The CHECK constraints remain the final integrity backstop.

create or replace function public.raise_clear_food_log_provenance_errors()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.kind <> 'manual' then
    return new;
  end if;

  if new.acquisition_type in ('grocery', 'restaurant', 'takeout')
    and new.total_price is null
  then
    raise exception 'Purchased manual food cannot omit its full price';
  end if;

  if jsonb_typeof(new.components) <> 'array'
    or jsonb_array_length(new.components) = 0
  then
    raise exception 'Manual consumption cannot omit meaningful components';
  end if;

  if new.nutrition_is_estimated and new.nutrition_estimate is null then
    raise exception 'Estimated manual nutrition requires structured confidence metadata';
  end if;

  return new;
end;
$$;

revoke all on function public.raise_clear_food_log_provenance_errors()
  from public, anon, authenticated, service_role;

create trigger food_logs_clear_provenance_errors
before insert or update on public.food_logs
for each row
execute function public.raise_clear_food_log_provenance_errors();

create or replace function public.raise_clear_product_cost_provenance_errors()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.estimated_cost is not null
    and nullif(trim(new.cost_source), '') is null
  then
    raise exception 'costSource is required with estimatedCost';
  end if;

  if new.estimated_cost is not null and new.cost_as_of is null then
    raise exception 'costAsOf is required with estimatedCost';
  end if;

  return new;
end;
$$;

revoke all on function public.raise_clear_product_cost_provenance_errors()
  from public, anon, authenticated, service_role;

create trigger products_clear_cost_provenance_errors
before insert or update on public.products
for each row
execute function public.raise_clear_product_cost_provenance_errors();
