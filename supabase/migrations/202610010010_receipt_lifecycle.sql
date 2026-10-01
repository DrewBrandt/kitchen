-- One receipt per shopping row. Reconciliation retains row identity and user edits.
alter table public.shopping_items
  add column generated_active boolean not null default true,
  add column generated_qty_base numeric,
  add column generated_shortage_base numeric,
  add column generated_demand_changed boolean not null default false,
  add column received_qty_base numeric not null default 0 check (received_qty_base >= 0);

create function public.receive_shopping_item(p_request_id uuid, p_item uuid, p_receipt jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  prior jsonb; result jsonb; item public.shopping_items%rowtype;
  product_row public.products%rowtype; food_row public.base_foods%rowtype;
  unit_id uuid; quantity numeric; base_qty numeric; price numeric; lot_id uuid;
  bad_key text; acquired timestamptz; after_item public.shopping_items%rowtype;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior := public.claim_mutation_payload(p_request_id, 'receive_shopping_item', jsonb_build_object('item',p_item,'receipt',p_receipt));
  if prior is not null then return prior; end if;
  if p_receipt is null or jsonb_typeof(p_receipt) <> 'object' then raise exception 'Receipt must be an object'; end if;
  select key into bad_key from jsonb_object_keys(p_receipt) key
  where key <> all(array['productId','foodId','quantity','unit','totalPrice','location','bestBy','note','acquiredAt']);
  if bad_key is not null then raise exception 'Unsupported receipt field: %', bad_key; end if;
  -- Use the same lock order as reconcile/undo. No receipt can be overwritten.
  lock table public.shopping_items in share row exclusive mode;
  select * into item from public.shopping_items where id=p_item for update;
  if not found then raise exception 'Shopping item no longer exists'; end if;
  if item.lot is not null then raise exception 'This row already has a receipt. Undo it first, or add a separate shopping row for another purchase.'; end if;
  if nullif(p_receipt->>'productId','') is not null then
    select * into product_row from public.products where id=(p_receipt->>'productId')::uuid and archived_at is null;
    if not found then raise exception 'Choose an active product'; end if;
    if item.food is not null and product_row.food <> item.food then raise exception 'Choose a product for this food; add unrelated substitutions as a separate shopping item'; end if;
    select * into food_row from public.base_foods where id=product_row.food and archived_at is null;
  else
    select * into food_row from public.base_foods where id=coalesce(item.food,nullif(p_receipt->>'foodId','')::uuid) and archived_at is null;
  end if;
  if food_row.id is null then raise exception 'Choose the food you actually acquired'; end if;
  unit_id := public.resolve_measure_conversion(p_receipt->>'unit');
  quantity := (p_receipt->>'quantity')::numeric;
  if quantity is null or quantity <= 0 or quantity::text in ('NaN','Infinity','-Infinity') then raise exception 'Actual acquired quantity must be positive and finite'; end if;
  base_qty := public.to_base_quantity(food_row.id,quantity,unit_id);
  if base_qty is null or base_qty <= 0 or base_qty::text in ('NaN','Infinity','-Infinity') then raise exception 'Choose a suitable quantity and unit'; end if;
  price := nullif(p_receipt->>'totalPrice','')::numeric;
  if price < 0 or price::text in ('NaN','Infinity','-Infinity') then raise exception 'Price must be nonnegative and finite, or left unknown'; end if;
  acquired := coalesce(nullif(p_receipt->>'acquiredAt','')::timestamptz,now());
  if not isfinite(acquired) then raise exception 'Choose a finite acquired time'; end if;
  if product_row.id is null then
    -- Explicit new plain definition; do not guess equivalence with branded catalog records.
    insert into public.products(food,name,package_qty_base,package_unit)
    values(food_row.id,food_row.name || ' (unbranded)',base_qty,unit_id) returning * into product_row;
  end if;
  insert into public.inventory_lots(product,initial_qty,remaining_qty,total_cost,out_of_pocket_cost,paid_by,
    cost_is_estimated,cost_source,price_as_of,location,use_by,acquired_at,acquisition_type,is_external,note)
  values(product_row.id,base_qty,base_qty,price,price,'self',price is null,
    case when price is null then 'Shopping receipt: price unknown' else 'Shopping receipt' end,
    case when price is not null then (acquired at time zone (select time_zone from public.app_settings where singleton))::date end,
    coalesce(nullif(p_receipt->>'location',''),'pantry'),nullif(p_receipt->>'bestBy','')::date,acquired,'grocery',false,nullif(p_receipt->>'note',''))
  returning id into lot_id;
  -- Checking is a shopping preference, not evidence of receipt. Preserve it exactly.
  update public.shopping_items set lot=lot_id, received_qty_base=base_qty,
    generated_shortage_base=greatest(0,generated_shortage_base-base_qty)
  where id=p_item returning * into after_item;
  insert into public.record_edits(resource,record_id,before_state,after_state)
  values('inventory_lot',lot_id,jsonb_build_object('shoppingItem',to_jsonb(item)),
    jsonb_build_object('action','receive_shopping_item','shoppingItem',to_jsonb(after_item),'productId',product_row.id));
  result := jsonb_build_object('lotId',lot_id,'itemId',p_item,'quantityBase',base_qty);
  perform public.gpt_complete_request(p_request_id,result);
  return result;
end;
$$;
revoke all on function public.receive_shopping_item(uuid,uuid,jsonb) from public,anon,authenticated,service_role;

create function public.undo_inventory_receipt(p_request_id uuid, p_lot uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  prior jsonb; result jsonb; lot_row public.inventory_lots%rowtype; item public.shopping_items%rowtype;
  receipt public.record_edits%rowtype; event_id uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior := public.claim_mutation_payload(p_request_id,'undo_inventory_receipt',jsonb_build_object('lot',p_lot));
  if prior is not null then return prior; end if;
  lock table public.shopping_items in share row exclusive mode;
  select * into receipt from public.record_edits where resource='inventory_lot' and record_id=p_lot
    and after_state->>'action'='receive_shopping_item' order by edited_at desc limit 1;
  if not found then raise exception 'This lot was not created by a shopping receipt'; end if;
  select * into item from public.shopping_items where id=(receipt.before_state#>>'{shoppingItem,id}')::uuid for update;
  if not found then raise exception 'The source shopping item was removed; receipt cannot be undone safely'; end if;
  select * into lot_row from public.inventory_lots where id=p_lot for update;
  if lot_row.acquisition_void_event is not null and exists(select 1 from public.inventory_events where id=lot_row.acquisition_void_event and voided_at is null) then
    result := jsonb_build_object('lotId',p_lot,'status','already undone');
    perform public.gpt_complete_request(p_request_id,result); return result;
  end if;
  if item.lot is distinct from p_lot then raise exception 'Shopping receipt association has changed'; end if;
  if exists(select 1 from public.inventory_events where lot=p_lot and voided_at is null)
    or lot_row.remaining_qty is distinct from lot_row.initial_qty then
    raise exception 'This stock has been used or adjusted. Undo those dependent actions before undoing its receipt.';
  end if;
  if exists(select 1 from public.meal_plans where inventory_lot=p_lot and status='planned') then
    raise exception 'This stock is assigned to a planned meal. Remove that plan before undoing its receipt.';
  end if;
  insert into public.inventory_events(lot,quantity_delta,reason,note)
  values(p_lot,-lot_row.initial_qty,'adjust','Shopping receipt undone') returning id into event_id;
  update public.inventory_lots set acquisition_void_event=event_id where id=p_lot;
  -- Receipt never changes quantity/check/note/product preferences; undo must not overwrite later edits.
  update public.shopping_items set lot=null,received_qty_base=0,generated_active=true where id=item.id;
  insert into public.record_edits(resource,record_id,before_state,after_state)
  values('inventory_lot',p_lot,to_jsonb(lot_row),jsonb_build_object('action','undo_inventory_receipt','voidEvent',event_id,'shoppingItemId',item.id));
  result := jsonb_build_object('lotId',p_lot,'itemId',item.id,'status','undone');
  perform public.gpt_complete_request(p_request_id,result); return result;
end;
$$;
revoke all on function public.undo_inventory_receipt(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.rebuild_shopping_from_plan(p_from date default current_date,p_through date default current_date+6)
returns integer language plpgsql set search_path = '' as $$
declare shortage record; item public.shopping_items%rowtype; unit_id uuid;
  current_base numeric; target_base numeric; auto_quantity boolean; changed_count integer:=0;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode='42501'; end if;
  if p_from is null or p_through is null or p_through < p_from then raise exception 'Choose a valid plan range'; end if;
  lock table public.shopping_items in share row exclusive mode;
  -- Retain inactive rows, including checks, notes, pinned products, and manual quantities.
  update public.shopping_items set generated_active=false,generated_shortage_base=0 where source='generated';
  for shortage in
  with planned_ingredients as (
    select
      ingredient.ingredient as food,
      sum(public.to_base_quantity(
        ingredient.ingredient,
        ingredient.qty * plan.scale_factor,
        ingredient.unit
      )) as needed_base,
      min(plan.plan_date) as first_needed_date
    from public.meal_plans plan
    join public.recipe_ingredients ingredient on ingredient.recipe = plan.recipe
    join public.base_foods food on food.id = ingredient.ingredient
    where plan.plan_date between p_from and p_through
      and plan.status = 'planned'
      and plan.intent = 'prepare'
      and not food.always_available
    group by ingredient.ingredient
  ), available_inventory as (
    select
      coalesce(product.food, prepared_recipe.output_food) as food,
      sum(lot.remaining_qty) as available_base
    from public.inventory_lots lot
    left join public.products product on product.id = lot.product
    left join public.preps prep on prep.id = lot.prep and prep.voided_at is null
    left join public.recipes prepared_recipe on prepared_recipe.id = prep.recipe
    where lot.remaining_qty > 0
    group by coalesce(product.food, prepared_recipe.output_food)
  ), shortages as (
    select
      planned.food,
      greatest(planned.needed_base - coalesce(stock.available_base, 0), 0) as shortage_base,
      planned.first_needed_date
    from planned_ingredients planned
    left join available_inventory stock on stock.food = planned.food
  ) select * from shortages where shortage_base > 0.0000001
  loop
    select * into item from public.shopping_items where source='generated' and food=shortage.food
      order by created_at,id limit 1 for update;
    if item.id is null then
      select coalesce(food.display_unit,conversion.id) into unit_id from public.base_foods food
        join lateral(select id from public.measure_conversions where measure_style=food.measure_style and base_to_this_ratio=1 order by id limit 1) conversion on true
        where food.id=shortage.food;
      insert into public.shopping_items(food,qty_needed,unit,source,first_needed_date,generated_qty_base,generated_shortage_base)
      values(shortage.food,public.from_base_quantity(shortage.food,shortage.shortage_base,unit_id),unit_id,'generated',shortage.first_needed_date,shortage.shortage_base,shortage.shortage_base);
    else
      current_base := case when item.qty_needed is not null and item.unit is not null then public.to_base_quantity(item.food,item.qty_needed,item.unit) end;
      target_base := shortage.shortage_base+item.received_qty_base;
      auto_quantity := item.checked_at is null and item.generated_qty_base is not null and current_base=item.generated_qty_base;
      update public.shopping_items set generated_active=true,first_needed_date=shortage.first_needed_date,
        generated_shortage_base=shortage.shortage_base,
        generated_demand_changed=not coalesce(auto_quantity,false) and current_base is distinct from target_base,
        qty_needed=case when auto_quantity then public.from_base_quantity(item.food,target_base,item.unit) else qty_needed end,
        quantity_label=case when auto_quantity then null else quantity_label end,
        generated_qty_base=case when auto_quantity then target_base else generated_qty_base end
      where id=item.id;
    end if;
    changed_count:=changed_count+1;
  end loop;
  return changed_count;
end;
$$;
