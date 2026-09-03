-- Product prices are current package estimates, while inventory lots retain the
-- exact historical purchase. Use the newest normalized lot price only when a
-- product has no estimate at all, and keep its provenance explicit.
create or replace function public.seed_missing_product_cost_from_lot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.product is null or new.total_cost is null or new.initial_qty <= 0 then
    return new;
  end if;

  update public.products product
  set estimated_cost = round(new.total_cost * product.package_qty_base / new.initial_qty, 2),
      cost_source = concat(
        'Latest recorded purchase (used as current estimate)',
        case when nullif(trim(coalesce(new.cost_source, '')), '') is null
          then '' else ' · ' || trim(new.cost_source) end
      ),
      cost_as_of = coalesce(
        new.price_as_of,
        (new.acquired_at at time zone (select time_zone from public.app_settings where singleton))::date
      )
  where product.id = new.product
    and product.estimated_cost is null;

  return new;
end;
$$;

revoke all on function public.seed_missing_product_cost_from_lot() from public, anon, authenticated;

create trigger inventory_lots_seed_missing_product_cost
after insert or update of product, initial_qty, total_cost, cost_source, price_as_of, acquired_at
on public.inventory_lots
for each row execute function public.seed_missing_product_cost_from_lot();

with latest_priced_lot as (
  select distinct on (lot.product)
    lot.product,
    round(lot.total_cost * product.package_qty_base / lot.initial_qty, 2) as package_cost,
    concat(
      'Latest recorded purchase (used as current estimate)',
      case when nullif(trim(coalesce(lot.cost_source, '')), '') is null
        then '' else ' · ' || trim(lot.cost_source) end
    ) as source,
    coalesce(
      lot.price_as_of,
      (lot.acquired_at at time zone (select time_zone from public.app_settings where singleton))::date
    ) as as_of
  from public.inventory_lots lot
  join public.products product on product.id = lot.product
  where product.archived_at is null
    and product.estimated_cost is null
    and lot.total_cost is not null
    and lot.initial_qty > 0
  order by lot.product,
    coalesce(
      lot.price_as_of,
      (lot.acquired_at at time zone (select time_zone from public.app_settings where singleton))::date
    ) desc,
    lot.created_at desc
)
update public.products product
set estimated_cost = latest.package_cost,
    cost_source = latest.source,
    cost_as_of = latest.as_of
from latest_priced_lot latest
where product.id = latest.product
  and product.estimated_cost is null;
