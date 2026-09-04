create function public.bulk_import_inventory(p_entries jsonb, p_location text default 'pantry')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry jsonb;
  product_row public.products%rowtype;
  package_count numeric;
  lot_id uuid;
  created_ids uuid[] := array[]::uuid[];
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may import inventory' using errcode = '42501';
  end if;
  if jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) = 0 then
    raise exception 'entries must be a non-empty array';
  end if;

  for entry in select value from jsonb_array_elements(p_entries)
  loop
    select * into product_row
    from public.products
    where id = (entry ->> 'productId')::uuid and archived_at is null;
    if not found then raise exception 'Unknown active product: %', entry ->> 'productId'; end if;

    package_count := (entry ->> 'packages')::numeric;
    if package_count <= 0 or package_count <> trunc(package_count) then
      raise exception 'Package count must be a positive whole number';
    end if;

    insert into public.inventory_lots(
      product, initial_qty, remaining_qty, total_cost, out_of_pocket_cost, paid_by,
      cost_is_estimated, cost_source, price_as_of, use_by, location, acquired_at,
      acquired_time_precision, acquisition_type, is_external, note
    ) values (
      product_row.id, product_row.package_qty_base * package_count, product_row.package_qty_base * package_count,
      coalesce(product_row.estimated_cost, 0) * package_count, coalesce(product_row.estimated_cost, 0) * package_count, 'self',
      true, coalesce(nullif(product_row.cost_source, ''), 'Bulk barcode import estimate'),
      coalesce(product_row.cost_as_of, (now() at time zone (select time_zone from public.app_settings where singleton))::date),
      nullif(entry ->> 'bestBy', '')::date, coalesce(nullif(p_location, ''), 'pantry'), now(),
      'exact', 'grocery', false, 'Added with mobile bulk barcode import'
    ) returning id into lot_id;
    created_ids := array_append(created_ids, lot_id);
  end loop;

  return jsonb_build_object('status', 'created', 'lotIds', created_ids);
end;
$$;

revoke all on function public.bulk_import_inventory(jsonb, text) from public, anon;
grant execute on function public.bulk_import_inventory(jsonb, text) to authenticated, service_role;
