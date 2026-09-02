-- Run after the residue-repair transaction has completed so PostgreSQL has no
-- pending inventory trigger events while it validates the table.
alter table public.inventory_lots
  add constraint inventory_lots_no_quantity_residue
  check (remaining_qty = 0 or remaining_qty > 0.000001) not valid;
alter table public.inventory_lots validate constraint inventory_lots_no_quantity_residue;
