create or replace function public.rebuild_shopping_from_plan(
  p_from date default current_date,
  p_through date default current_date + 6
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  inserted_count integer;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may rebuild shopping items' using errcode = '42501';
  end if;
  if p_through < p_from then raise exception 'Plan end date precedes start date'; end if;

  -- Generated items are a projection of the current plan, not shopping history.
  -- Rebuilding replaces that projection wholesale, even when an old row was checked.
  delete from public.shopping_items
  where source = 'generated'
    and lot is null;

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
    where plan.plan_date between p_from and p_through
      and plan.status = 'planned'
      and plan.intent = 'prepare'
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
  ), display_shortages as (
    select
      shortage.food,
      shortage.first_needed_date,
      coalesce(food.display_unit, base_unit.id) as unit,
      public.from_base_quantity(
        shortage.food,
        shortage.shortage_base,
        coalesce(food.display_unit, base_unit.id)
      ) as quantity
    from shortages shortage
    join public.base_foods food on food.id = shortage.food
    join lateral (
      select conversion.id
      from public.measure_conversions conversion
      where conversion.measure_style = food.measure_style
        and conversion.base_to_this_ratio = 1
      limit 1
    ) base_unit on true
    where shortage.shortage_base > 0.0000001
  )
  insert into public.shopping_items(
    food, qty_needed, unit, source, first_needed_date, quantity_label
  )
  select
    shortage.food,
    shortage.quantity,
    shortage.unit,
    'generated',
    shortage.first_needed_date,
    trim(to_char(shortage.quantity, 'FM999999990.##')) || ' ' || conversion.short_name
  from display_shortages shortage
  join public.measure_conversions conversion on conversion.id = shortage.unit;

  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

revoke all on function public.rebuild_shopping_from_plan(date, date) from public, anon;
grant execute on function public.rebuild_shopping_from_plan(date, date) to authenticated;
