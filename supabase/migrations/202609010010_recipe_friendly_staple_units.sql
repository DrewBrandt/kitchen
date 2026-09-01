-- Weight remains the inventory base for packaged dry goods, but recipes should
-- describe these household staples with the cups and spoons used to cook them.
with staple_density(name, grams_per_fluid_ounce) as (
  values
    ('All-purpose flour', 15::numeric),
    ('All-vegetable shortening', 25.5::numeric),
    ('Baking soda', 28.8::numeric),
    ('Butter-flavored shortening', 25.5::numeric),
    ('Chili powder', 16.2::numeric),
    ('Chocolate syrup', 38::numeric),
    ('Clover honey', 42::numeric),
    ('Creamy peanut butter', 32::numeric),
    ('Dark brown sugar', 24::numeric),
    ('Double-acting baking powder', 28.8::numeric),
    ('Dried basil', 4.2::numeric),
    ('Dried oregano', 3::numeric),
    ('Garlic powder', 18.6::numeric),
    ('Granulated sugar', 25::numeric),
    ('Ground cinnamon', 15.6::numeric),
    ('Ground cumin', 12.6::numeric),
    ('Ground nutmeg', 13.2::numeric),
    ('Hazelnut cocoa spread', 37::numeric),
    ('Long-grain white rice', 22.5::numeric),
    ('Onion powder', 14.4::numeric),
    ('Peanut butter and chocolate spread', 34::numeric),
    ('Salt', 36::numeric),
    ('Salted butter', 28.35::numeric),
    ('Semisweet chocolate chip', 21.25::numeric)
)
update public.base_foods food
set ingredient_role = 'staple',
    g_per_fl_oz = density.grams_per_fluid_ounce,
    updated_at = now()
from staple_density density
where lower(food.name) = lower(density.name)
  and food.measure_style = 'weight';

with converted as (
  select
    ingredient.id,
    food.id as food_id,
    food.name,
    public.to_base_quantity(food.id, ingredient.qty, ingredient.unit) as grams,
    public.to_base_quantity(food.id, ingredient.qty, ingredient.unit) / food.g_per_fl_oz as fluid_ounces
  from public.recipe_ingredients ingredient
  join public.base_foods food on food.id = ingredient.ingredient
  where food.measure_style = 'weight'
    and food.ingredient_role = 'staple'
    and food.g_per_fl_oz is not null
), target as (
  select
    converted.*,
    case
      when converted.fluid_ounces >= 2 then 'cup'
      when converted.name in ('Salted butter', 'All-vegetable shortening', 'Butter-flavored shortening') then 'tbsp'
      when converted.fluid_ounces >= 0.5 then 'tbsp'
      else 'tsp'
    end as short_name
  from converted
), target_unit as (
  select target.*, unit.id as unit_id
  from target
  join public.measure_conversions unit on unit.short_name = target.short_name
)
update public.recipe_ingredients ingredient
set qty = public.from_base_quantity(target.food_id, target.grams, target.unit_id),
    unit = target.unit_id
from target_unit target
where ingredient.id = target.id;
