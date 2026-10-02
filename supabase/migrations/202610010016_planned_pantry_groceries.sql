-- Weekly grocery forecasts include pending pantry consumption. Existing records remain generic.
alter table public.shopping_items add column generated_product uuid references public.products(id);
comment on column public.shopping_items.generated_product is 'Generated demand identity: null means any product of the food; a product means a hard plan requirement. Independent of the editable pinned_product shopping preference.';

create or replace function public.reconcile_shopping_demand(p_from date,p_through date,p_food uuid default null)
returns integer language plpgsql set search_path = '' as $$
declare shortage record; item public.shopping_items%rowtype; unit_id uuid;
  current_base numeric; target_base numeric; auto_quantity boolean; changed_count integer:=0;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode='42501'; end if;
  if p_from is null or p_through is null or not isfinite(p_from) or not isfinite(p_through) or p_through < p_from then raise exception 'Choose a valid plan range'; end if;
  lock table public.shopping_items in share row exclusive mode;
  -- Retain inactive rows, including checks, notes, pinned products, and manual quantities.
  update public.shopping_items set generated_active=false,generated_demand_changed=false,generated_shortage_base=0,generated_from=p_from,generated_through=p_through where source='generated' and (p_food is null or food=p_food);
  for shortage in
  -- Forecast only: no stock is reserved and no expiry dates are inferred.
  with exact_claims as (
    select plan.inventory_lot as lot,
      sum(case when lot.prep is not null then pc.servings
        when product.servings_per_package>0 and product.package_qty_base>0
          and product.serving_qty_base is not null and product.nutrition_basis_qty is not null
          and abs(product.nutrition_basis_qty-product.serving_qty_base)<0.000001
        then pc.servings*product.package_qty_base/product.servings_per_package
        else pc.servings*coalesce(nullif(product.serving_qty_base,0),1) end) as quantity
    from public.meal_plans plan join public.planned_consumptions pc on pc.meal_plan=plan.id
    join public.inventory_lots lot on lot.id=plan.inventory_lot
    left join public.products product on product.id=lot.product
    where plan.plan_date between p_from and p_through and plan.status in ('planned','made')
      and plan.intent='consume' and pc.status='planned'
    group by plan.inventory_lot
  ), stock as (
    select coalesce(product.food,recipe.output_food) as food,lot.product,
      sum(greatest(lot.remaining_qty-coalesce(claim.quantity,0),0)) as quantity
    from public.inventory_lots lot left join public.products product on product.id=lot.product
    left join public.preps prep on prep.id=lot.prep and prep.voided_at is null
    left join public.recipes recipe on recipe.id=prep.recipe
    left join exact_claims claim on claim.lot=lot.id
    where lot.remaining_qty>0 and (lot.product is not null or prep.id is not null)
    group by coalesce(product.food,recipe.output_food),lot.product
  ), demands as (
    select ingredient.ingredient as food,ingredient.pinned_product as product,
      public.to_base_quantity(ingredient.ingredient,ingredient.qty*plan.scale_factor,ingredient.unit) as quantity,
      plan.plan_date
    from public.meal_plans plan join public.recipe_ingredients ingredient on ingredient.recipe=plan.recipe
    join public.base_foods food on food.id=ingredient.ingredient
    where plan.plan_date between p_from and p_through and plan.status='planned'
      and plan.intent='prepare' and not food.always_available
    union all
    select product.food,product.id,
      case when product.servings_per_package>0 and product.package_qty_base>0
        and product.serving_qty_base is not null and product.nutrition_basis_qty is not null
        and abs(product.nutrition_basis_qty-product.serving_qty_base)<0.000001
      then pc.servings*product.package_qty_base/product.servings_per_package
      else pc.servings*coalesce(nullif(product.serving_qty_base,0),1) end,
      plan.plan_date
    from public.meal_plans plan join public.planned_consumptions pc on pc.meal_plan=plan.id
    join public.products product on product.id=plan.product
    where plan.plan_date between p_from and p_through and plan.status in ('planned','made')
      and plan.intent='consume' and plan.consume_from_inventory and pc.status='planned'
  ), demand as (
    select food,product,sum(quantity) as quantity,min(plan_date) as first_needed_date
    from demands where p_food is null or food=p_food group by food,product
  ), residual_stock as (
    -- Hard product requirements use their stock first. Shopping pins never enter this calculation.
    select stock.food,sum(greatest(stock.quantity-coalesce(demand.quantity,0),0)) as quantity
    from stock left join demand on demand.food=stock.food and demand.product=stock.product
    group by stock.food
  ), shortages as (
    select demand.food,demand.product,demand.first_needed_date,
      greatest(demand.quantity-coalesce(case when demand.product is null then residual.quantity else stock.quantity end,0),0) as shortage_base
    from demand left join stock on stock.food=demand.food and stock.product=demand.product
    left join residual_stock residual on residual.food=demand.food
  ) select * from shortages where shortage_base>0.0000001 order by food,product nulls first
  loop
    select * into item from public.shopping_items where source='generated' and food=shortage.food and generated_product is not distinct from shortage.product
      order by created_at,id limit 1 for update;
    if item.id is null then
      select coalesce(food.display_unit,conversion.id) into unit_id from public.base_foods food
        join lateral(select id from public.measure_conversions where measure_style=food.measure_style and base_to_this_ratio=1 order by id limit 1) conversion on true
        where food.id=shortage.food;
      insert into public.shopping_items(generated_product,food,qty_needed,unit,source,first_needed_date,generated_qty_base,generated_shortage_base,generated_from,generated_through)
      values(shortage.product,shortage.food,public.from_base_quantity(shortage.food,shortage.shortage_base,unit_id),unit_id,'generated',shortage.first_needed_date,shortage.shortage_base,shortage.shortage_base,p_from,p_through);
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


-- Invoker permissions and the owner check match rebuild. This helper also reconciles receipt-affected foods.
revoke all on function public.reconcile_shopping_demand(date,date,uuid) from public,anon,service_role;
grant execute on function public.reconcile_shopping_demand(date,date,uuid) to authenticated;

create or replace function public.rebuild_shopping_from_plan(p_from date default current_date,p_through date default current_date+6)
returns integer language plpgsql set search_path = '' as $$
begin
  return public.reconcile_shopping_demand(p_from,p_through);
end;
$$;

create or replace function public.receive_shopping_item(p_request_id uuid, p_item uuid, p_receipt jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  prior jsonb; result jsonb; item public.shopping_items%rowtype;
  product_row public.products%rowtype; priced_product public.products%rowtype; food_row public.base_foods%rowtype;
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
    select * into product_row from public.products where id=(p_receipt->>'productId')::uuid and archived_at is null for update;
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
  select * into priced_product from public.products where id=product_row.id;
  -- Checking is a shopping preference, not evidence of receipt. Preserve it exactly.
  update public.shopping_items set lot=lot_id, received_qty_base=base_qty,
    generated_shortage_base=greatest(0,generated_shortage_base-base_qty)
  where id=p_item returning * into after_item;
  if item.source='generated' then
    perform public.reconcile_shopping_demand(coalesce(item.generated_from,current_date),coalesce(item.generated_through,current_date+6),food_row.id);
    select * into after_item from public.shopping_items where id=p_item;
  end if;
  insert into public.record_edits(resource,record_id,before_state,after_state)
  values('inventory_lot',lot_id,jsonb_build_object('shoppingItem',to_jsonb(item),
      'productPrice',jsonb_build_object('estimated_cost',product_row.estimated_cost,'cost_source',product_row.cost_source,'cost_as_of',product_row.cost_as_of)),
    jsonb_build_object('action','receive_shopping_item','shoppingItem',to_jsonb(after_item),'productId',product_row.id,
      'productPrice',jsonb_build_object('estimated_cost',priced_product.estimated_cost,'cost_source',priced_product.cost_source,'cost_as_of',priced_product.cost_as_of)));
  result := jsonb_build_object('lotId',lot_id,'itemId',p_item,'quantityBase',base_qty);
  perform public.gpt_complete_request(p_request_id,result);
  return result;
end;
$$;

create or replace function public.undo_inventory_receipt(p_request_id uuid, p_lot uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  prior jsonb; result jsonb; lot_row public.inventory_lots%rowtype; item public.shopping_items%rowtype;
  receipt public.record_edits%rowtype; event_id uuid;
  product_row public.products%rowtype; restored_product public.products%rowtype; current_price jsonb;
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
  -- Reverse only the catalog price actually seeded by this receipt, comparing all
  -- pricing fields so later user prices survive. Other product fields are untouched.
  select * into product_row from public.products where id=lot_row.product for update;
  current_price:=jsonb_build_object('estimated_cost',product_row.estimated_cost,'cost_source',product_row.cost_source,'cost_as_of',product_row.cost_as_of);
  if receipt.before_state->'productPrice' is distinct from receipt.after_state->'productPrice'
    and current_price=receipt.after_state->'productPrice' then
    update public.products set
      estimated_cost=(receipt.before_state#>>'{productPrice,estimated_cost}')::numeric,
      cost_source=receipt.before_state#>>'{productPrice,cost_source}',
      cost_as_of=(receipt.before_state#>>'{productPrice,cost_as_of}')::date
    where id=product_row.id returning * into restored_product;
    insert into public.record_edits(resource,record_id,before_state,after_state)
    values('product',product_row.id,to_jsonb(product_row),to_jsonb(restored_product));
  end if;
  -- Receipt never changes quantity/check/note/product preferences; undo must not overwrite later edits.
  update public.shopping_items set lot=null,received_qty_base=0 where id=item.id;
  if item.source='generated' and item.food is not null then
    perform public.reconcile_shopping_demand(coalesce(item.generated_from,current_date),coalesce(item.generated_through,current_date+6),item.food);
  end if;
  insert into public.record_edits(resource,record_id,before_state,after_state)
  values('inventory_lot',p_lot,to_jsonb(lot_row),jsonb_build_object('action','undo_inventory_receipt','voidEvent',event_id,'shoppingItemId',item.id));
  result := jsonb_build_object('lotId',p_lot,'itemId',item.id,'status','undone');
  perform public.gpt_complete_request(p_request_id,result); return result;
end;
$$;
