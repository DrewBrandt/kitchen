-- Include pending source preparations when forecasting linked leftovers.
-- No historical repair DML, row deletion, grants, or schema changes. Existing
-- reconciliation retains row IDs, checks, notes, quantities, receipts and pins.
create or replace function public.reconcile_shopping_demand(p_from date,p_through date,p_food uuid default null)
returns integer language plpgsql set search_path = '' as $$
declare shortage record; item public.shopping_items%rowtype; unit_id uuid;
  current_base numeric; target_base numeric; auto_quantity boolean; changed_count integer:=0;
  dependency_from date; dependency_through date;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode='42501'; end if;
  if p_from is null or p_through is null or not isfinite(p_from) or not isfinite(p_through) or p_through < p_from then raise exception 'Choose a valid plan range'; end if;
  lock table public.shopping_items in share row exclusive mode;
  -- A leftover meal depends on its pending source preparation, even across weeks.
  -- Expand the existing single forecast range; count each preparation once via
  -- the normal demands CTE, never as another recipe cook for each leftover.
  loop
    select least(p_from,min(source.plan_date)),greatest(p_through,max(source.plan_date))
      into dependency_from,dependency_through
    from public.meal_plans leftover
    join public.planned_consumptions pc on pc.meal_plan=leftover.id and pc.status='planned'
    join public.meal_plans source on source.recipe=leftover.recipe and source.intent='prepare' and source.status='planned'
      and (source.id=leftover.source_meal_plan or (leftover.source_meal_plan is null and source.group_id=leftover.leftover_of_group_id))
    where leftover.plan_date between p_from and p_through
      and leftover.intent='leftover' and leftover.status in ('planned','made');
    exit when dependency_from=p_from and dependency_through=p_through;
    p_from:=dependency_from; p_through:=dependency_through;
  end loop;
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
