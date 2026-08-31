revoke execute on function public.inventory_events_refresh_lot()
  from public, anon, authenticated;

create index base_foods_display_unit_idx
  on public.base_foods(display_unit);
create index base_foods_grocery_category_idx
  on public.base_foods(grocery_category);
create index cook_sessions_meal_idx
  on public.cook_sessions(meal);
create index inventory_events_cook_session_idx
  on public.inventory_events(cook_session);
create index inventory_lots_location_idx
  on public.inventory_lots(location);
create index meal_plans_cook_session_idx
  on public.meal_plans(cook_session);
create index meal_plans_meal_idx
  on public.meal_plans(meal);
create index meal_plans_recipe_idx
  on public.meal_plans(recipe);
create index meal_recipes_recipe_idx
  on public.meal_recipes(recipe);
create index preps_parent_prep_idx
  on public.preps(parent_prep);
create index products_package_unit_idx
  on public.products(package_unit);
create index recipe_ingredients_pinned_product_idx
  on public.recipe_ingredients(pinned_product);
create index recipe_ingredients_unit_idx
  on public.recipe_ingredients(unit);
create index recipes_output_food_idx
  on public.recipes(output_food);
create index shopping_items_food_idx
  on public.shopping_items(food);
create index shopping_items_lot_idx
  on public.shopping_items(lot);
create index shopping_items_pinned_product_idx
  on public.shopping_items(pinned_product);
create index shopping_items_unit_idx
  on public.shopping_items(unit);
