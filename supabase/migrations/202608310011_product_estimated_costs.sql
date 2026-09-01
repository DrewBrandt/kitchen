alter table public.products
  add column estimated_cost numeric(10, 2) check (estimated_cost >= 0),
  add column cost_source text,
  add column cost_as_of date;

comment on column public.products.estimated_cost is
  'Current estimated price for one product package; actual purchase prices remain on inventory lots.';

-- Seed the estimate from the best user-specific signal already available. This is
-- intentionally separate from inventory_lots.total_cost, which remains immutable
-- purchase history.
with latest_cost as (
  select distinct on (lot.product)
    lot.product,
    lot.total_cost,
    lot.created_at::date as purchased_on
  from public.inventory_lots lot
  where lot.product is not null
    and lot.total_cost is not null
    and lot.total_cost > 0
  order by lot.product, lot.created_at desc
)
update public.products product
set estimated_cost = latest_cost.total_cost,
    cost_source = 'Latest recorded purchase (used as current estimate)',
    cost_as_of = current_date
from latest_cost
where product.id = latest_cost.product
  and product.estimated_cost is null;

