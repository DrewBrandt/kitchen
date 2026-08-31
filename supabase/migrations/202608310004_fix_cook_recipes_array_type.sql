create or replace function public.cook_recipes(p_recipes uuid[])
returns uuid[]
language plpgsql
set search_path = ''
as $$
declare
  recipe_id uuid;
  prep_ids uuid[] := array[]::uuid[];
begin
  if coalesce(array_length(p_recipes, 1), 0) = 0 then
    raise exception 'Select at least one recipe';
  end if;
  foreach recipe_id in array p_recipes loop
    prep_ids := prep_ids || public.cook_recipe(recipe_id, 1, null, 'fridge');
  end loop;
  return prep_ids;
end;
$$;
