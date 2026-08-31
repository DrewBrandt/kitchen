create or replace function public.is_app_owner()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(
    auth.jwt() ->> 'email' = 'xdrewbrandtx@gmail.com'
      and (auth.jwt() ->> 'email_verified')::boolean,
    false
  );
$$;

revoke all on function public.is_app_owner() from public, anon;
grant execute on function public.is_app_owner() to authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'measure_conversions',
    'grocery_categories',
    'locations',
    'base_foods',
    'products',
    'recipes',
    'recipe_ingredients',
    'meals',
    'meal_recipes',
    'cook_sessions',
    'preps',
    'inventory_lots',
    'inventory_events',
    'meal_plans',
    'shopping_items',
    'app_settings',
    'food_logs',
    'personal_settings'
  ] loop
    execute format('drop policy if exists authenticated_full_access on public.%I', table_name);
    execute format('drop policy if exists owner_full_access on public.%I', table_name);
    execute format(
      'create policy owner_full_access on public.%I for all to authenticated using ((select public.is_app_owner())) with check ((select public.is_app_owner()))',
      table_name
    );
  end loop;
end;
$$;
