create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;

create type public.measure_style as enum ('discrete', 'weight', 'volume');
create type public.inventory_event_reason as enum (
  'eaten',
  'prep',
  'waste',
  'adjust',
  'gave_away'
);
create type public.daypart as enum (
  'breakfast',
  'brunch',
  'lunch',
  'dinner',
  'snack',
  'dessert'
);
create type public.plan_status as enum ('planned', 'made', 'skipped', 'moved');
create type public.shopping_source as enum ('generated', 'manual', 'staple');

create table public.measure_conversions (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  short_name text not null,
  measure_style public.measure_style not null,
  base_to_this_ratio numeric not null check (base_to_this_ratio > 0),
  created_at timestamptz not null default now()
);

create unique index measure_conversions_full_name_key
  on public.measure_conversions (lower(full_name));
create unique index measure_conversions_short_name_key
  on public.measure_conversions (lower(short_name));

create table public.grocery_categories (
  category text primary key,
  sort_order integer not null unique check (sort_order >= 0)
);

create table public.locations (
  location text primary key,
  sort_order integer not null unique check (sort_order >= 0)
);

create table public.base_foods (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  plural text,
  measure_style public.measure_style not null,
  emoji text,
  grocery_category text references public.grocery_categories(category),
  display_unit uuid references public.measure_conversions(id),
  g_per_fl_oz numeric check (g_per_fl_oz > 0),
  g_per_count numeric check (g_per_count > 0),
  nutrition_basis_qty numeric not null default 100 check (nutrition_basis_qty > 0),
  kcal numeric check (kcal >= 0),
  protein_g numeric check (protein_g >= 0),
  carbs_g numeric check (carbs_g >= 0),
  fat_g numeric check (fat_g >= 0),
  fiber_g numeric check (fiber_g >= 0),
  sodium_mg numeric check (sodium_mg >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index base_foods_name_key on public.base_foods (lower(name));

create table public.products (
  id uuid primary key default gen_random_uuid(),
  food uuid not null references public.base_foods(id),
  barcode text unique,
  name text not null,
  brand text,
  package_qty_base numeric not null check (package_qty_base > 0),
  package_unit uuid not null references public.measure_conversions(id),
  serving_qty_base numeric check (serving_qty_base > 0),
  nutrition_basis_qty numeric check (nutrition_basis_qty > 0),
  kcal numeric check (kcal >= 0),
  protein_g numeric check (protein_g >= 0),
  carbs_g numeric check (carbs_g >= 0),
  fat_g numeric check (fat_g >= 0),
  fiber_g numeric check (fiber_g >= 0),
  sodium_mg numeric check (sodium_mg >= 0),
  emoji text,
  is_external boolean not null default false,
  last_used_at timestamptz,
  use_count integer not null default 0 check (use_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_nutrition_basis_required check (
    nutrition_basis_qty is not null
    or num_nonnulls(kcal, protein_g, carbs_g, fat_g, fiber_g, sodium_mg) = 0
  )
);

create index products_food_idx on public.products(food);
create index products_search_idx
  on public.products using gin ((coalesce(brand, '') || ' ' || name) extensions.gin_trgm_ops);

create table public.recipes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  emoji text,
  servings numeric not null default 1 check (servings > 0),
  output_food uuid references public.base_foods(id),
  yield_qty numeric check (yield_qty > 0),
  instructions jsonb not null default '[]'::jsonb
    check (jsonb_typeof(instructions) = 'array'),
  override_basis_qty numeric check (override_basis_qty > 0),
  override_kcal numeric check (override_kcal >= 0),
  override_protein_g numeric check (override_protein_g >= 0),
  override_carbs_g numeric check (override_carbs_g >= 0),
  override_fat_g numeric check (override_fat_g >= 0),
  override_fiber_g numeric check (override_fiber_g >= 0),
  override_sodium_mg numeric check (override_sodium_mg >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recipes_output_pair check (
    (output_food is null and yield_qty is null)
    or (output_food is not null and yield_qty is not null)
  ),
  constraint recipes_override_basis_required check (
    override_basis_qty is not null
    or num_nonnulls(
      override_kcal,
      override_protein_g,
      override_carbs_g,
      override_fat_g,
      override_fiber_g,
      override_sodium_mg
    ) = 0
  )
);

create unique index recipes_name_key on public.recipes(lower(name));

create table public.recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe uuid not null references public.recipes(id) on delete cascade,
  ingredient uuid not null references public.base_foods(id),
  pinned_product uuid references public.products(id),
  qty numeric not null check (qty > 0),
  unit uuid not null references public.measure_conversions(id),
  sort_order integer not null default 0 check (sort_order >= 0),
  note text
);

create index recipe_ingredients_recipe_idx
  on public.recipe_ingredients(recipe, sort_order);
create index recipe_ingredients_food_idx on public.recipe_ingredients(ingredient);

create table public.meals (
  id uuid primary key default gen_random_uuid(),
  emoji text,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index meals_name_key on public.meals(lower(name));

create table public.meal_recipes (
  meal uuid not null references public.meals(id) on delete cascade,
  recipe uuid not null references public.recipes(id),
  scale_factor numeric not null default 1 check (scale_factor > 0),
  sort_order integer not null default 0 check (sort_order >= 0),
  primary key (meal, recipe)
);

create table public.cook_sessions (
  id uuid primary key default gen_random_uuid(),
  meal uuid references public.meals(id),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  note text,
  check (completed_at is null or completed_at >= started_at)
);

create table public.preps (
  id uuid primary key default gen_random_uuid(),
  recipe uuid not null references public.recipes(id),
  cook_session uuid references public.cook_sessions(id),
  parent_prep uuid references public.preps(id),
  scale_factor numeric not null default 1 check (scale_factor > 0),
  actual_yield_qty numeric check (actual_yield_qty > 0),
  prepped_at timestamptz not null default now(),
  voided_at timestamptz,
  note text,
  check (parent_prep is null or parent_prep <> id)
);

create index preps_recipe_idx on public.preps(recipe);
create index preps_cook_session_idx on public.preps(cook_session);

create table public.inventory_lots (
  id uuid primary key default gen_random_uuid(),
  product uuid references public.products(id),
  prep uuid references public.preps(id),
  initial_qty numeric not null check (initial_qty > 0),
  remaining_qty numeric not null check (remaining_qty >= 0),
  total_cost numeric(10, 2) check (total_cost >= 0),
  use_by date,
  location text references public.locations(location),
  acquired_at timestamptz not null default now(),
  note text,
  created_at timestamptz not null default now(),
  constraint inventory_lots_one_source check (num_nonnulls(product, prep) = 1)
);

create index inventory_lots_product_idx on public.inventory_lots(product);
create index inventory_lots_prep_idx on public.inventory_lots(prep);
create index inventory_lots_open_idx
  on public.inventory_lots(use_by, acquired_at)
  where remaining_qty > 0;

create table public.inventory_events (
  id uuid primary key default gen_random_uuid(),
  lot uuid not null references public.inventory_lots(id),
  quantity_delta numeric not null check (quantity_delta <> 0),
  reason public.inventory_event_reason not null,
  prep uuid references public.preps(id),
  cook_session uuid references public.cook_sessions(id),
  occurred_at timestamptz not null default now(),
  voided_at timestamptz,
  note text,
  created_at timestamptz not null default now(),
  constraint inventory_events_prep_link check (
    (reason = 'prep') = (prep is not null)
  ),
  constraint inventory_events_reason_sign check (
    reason = 'adjust'
    or quantity_delta < 0
  )
);

create index inventory_events_lot_idx on public.inventory_events(lot);
create index inventory_events_prep_idx on public.inventory_events(prep)
  where prep is not null;
create index inventory_events_eaten_at_idx on public.inventory_events(occurred_at)
  where reason = 'eaten' and voided_at is null;

create table public.meal_plans (
  id uuid primary key default gen_random_uuid(),
  plan_date date not null,
  daypart public.daypart not null,
  scheduled_time time,
  meal uuid references public.meals(id),
  recipe uuid references public.recipes(id),
  scale_factor numeric not null default 1 check (scale_factor > 0),
  status public.plan_status not null default 'planned',
  cook_session uuid references public.cook_sessions(id),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint meal_plans_one_source check (num_nonnulls(meal, recipe) = 1),
  constraint meal_plans_made_session check (
    (status = 'made') = (cook_session is not null)
  )
);

create index meal_plans_date_idx on public.meal_plans(plan_date, daypart);

create table public.shopping_items (
  id uuid primary key default gen_random_uuid(),
  food uuid references public.base_foods(id),
  pinned_product uuid references public.products(id),
  free_text text,
  qty_needed numeric check (qty_needed > 0),
  unit uuid references public.measure_conversions(id),
  source public.shopping_source not null default 'manual',
  checked_at timestamptz,
  lot uuid references public.inventory_lots(id),
  note text,
  created_at timestamptz not null default now(),
  constraint shopping_items_description check (
    num_nonnulls(food, free_text) >= 1
  )
);

create index shopping_items_open_idx on public.shopping_items(source, checked_at)
  where lot is null;

create table public.app_settings (
  singleton boolean primary key default true check (singleton),
  time_zone text not null default 'America/New_York',
  updated_at timestamptz not null default now()
);

insert into public.app_settings(singleton) values (true);

insert into public.grocery_categories(category, sort_order) values
  ('Produce & deli meats', 0),
  ('Seafood, bread & international', 1),
  ('Baking & fresh meats', 2),
  ('Snacks, chips & sports drinks', 3),
  ('Seasonal & cards', 4),
  ('Laundry, cleaning & pets', 5),
  ('Dairy & frozen dinners', 6),
  ('Frozen foods & treats', 7),
  ('Eggs, yogurt, cheese & dough', 8),
  ('Deli, bakery & desserts', 9),
  ('Pantry & other', 10);

insert into public.locations(location, sort_order) values
  ('pantry', 0),
  ('fridge', 1),
  ('freezer', 2);

insert into public.measure_conversions(
  full_name,
  short_name,
  measure_style,
  base_to_this_ratio
) values
  ('count', 'ct', 'discrete', 1),
  ('gram', 'g', 'weight', 1),
  ('kilogram', 'kg', 'weight', 0.001),
  ('ounce', 'oz', 'weight', 0.03527396195),
  ('pound', 'lb', 'weight', 0.00220462262),
  ('fluid ounce', 'fl oz', 'volume', 1),
  ('teaspoon', 'tsp', 'volume', 6),
  ('tablespoon', 'tbsp', 'volume', 2),
  ('cup', 'cup', 'volume', 0.125),
  ('pint', 'pt', 'volume', 0.0625),
  ('quart', 'qt', 'volume', 0.03125),
  ('gallon', 'gal', 'volume', 0.0078125),
  ('milliliter', 'mL', 'volume', 29.5735295625),
  ('liter', 'L', 'volume', 0.0295735295625);

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger base_foods_set_updated_at
before update on public.base_foods
for each row execute function public.set_updated_at();

create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

create trigger recipes_set_updated_at
before update on public.recipes
for each row execute function public.set_updated_at();

create trigger meals_set_updated_at
before update on public.meals
for each row execute function public.set_updated_at();

create trigger meal_plans_set_updated_at
before update on public.meal_plans
for each row execute function public.set_updated_at();

create trigger app_settings_set_updated_at
before update on public.app_settings
for each row execute function public.set_updated_at();

create function public.prevent_measure_style_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.measure_style is distinct from old.measure_style then
    raise exception 'measure_style is immutable; migrate dependent quantities explicitly';
  end if;
  return new;
end;
$$;

create trigger measure_conversions_immutable_style
before update of measure_style on public.measure_conversions
for each row execute function public.prevent_measure_style_change();

create trigger base_foods_immutable_style
before update of measure_style on public.base_foods
for each row execute function public.prevent_measure_style_change();

create function public.validate_base_food()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  unit_style public.measure_style;
begin
  if new.display_unit is null then
    return new;
  end if;

  select measure_style into unit_style
  from public.measure_conversions
  where id = new.display_unit;

  if unit_style is distinct from new.measure_style then
    raise exception 'Display unit must use the food measure style';
  end if;

  return new;
end;
$$;

create trigger base_foods_validate
before insert or update on public.base_foods
for each row execute function public.validate_base_food();

create function public.validate_product()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  food_style public.measure_style;
  unit_style public.measure_style;
begin
  select measure_style into food_style
  from public.base_foods
  where id = new.food;

  select measure_style into unit_style
  from public.measure_conversions
  where id = new.package_unit;

  if food_style is distinct from unit_style then
    raise exception 'Package unit must use the product food measure style';
  end if;

  return new;
end;
$$;

create trigger products_validate
before insert or update on public.products
for each row execute function public.validate_product();

create function public.food_accepts_unit(p_food uuid, p_unit uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when food.measure_style = unit.measure_style then true
    when array[food.measure_style, unit.measure_style] <@ array[
      'weight'::public.measure_style,
      'volume'::public.measure_style
    ] then food.g_per_fl_oz is not null
    when array[food.measure_style, unit.measure_style] <@ array[
      'weight'::public.measure_style,
      'discrete'::public.measure_style
    ] then food.g_per_count is not null
    when array[food.measure_style, unit.measure_style] <@ array[
      'volume'::public.measure_style,
      'discrete'::public.measure_style
    ] then food.g_per_fl_oz is not null and food.g_per_count is not null
    else false
  end
  from public.base_foods food
  cross join public.measure_conversions unit
  where food.id = p_food and unit.id = p_unit;
$$;

create function public.validate_recipe_ingredient()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  product_food uuid;
begin
  if not coalesce(public.food_accepts_unit(new.ingredient, new.unit), false) then
    raise exception 'Ingredient unit cannot be converted to the food stock measure';
  end if;

  if new.pinned_product is not null then
    select food into product_food
    from public.products
    where id = new.pinned_product;

    if product_food is distinct from new.ingredient then
      raise exception 'Pinned product must belong to the ingredient food';
    end if;
  end if;

  return new;
end;
$$;

create trigger recipe_ingredients_validate
before insert or update on public.recipe_ingredients
for each row execute function public.validate_recipe_ingredient();

create function public.reject_recipe_cycles()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  has_cycle boolean;
begin
  with recursive edges as (
    select recipe.output_food as parent_food, ingredient.ingredient as child_food
    from public.recipes recipe
    join public.recipe_ingredients ingredient on ingredient.recipe = recipe.id
    where recipe.output_food is not null
  ), walk(root_food, current_food, path, cycle) as (
    select
      parent_food,
      child_food,
      array[parent_food, child_food],
      parent_food = child_food
    from edges
    union all
    select
      walk.root_food,
      edges.child_food,
      walk.path || edges.child_food,
      edges.child_food = any(walk.path)
    from walk
    join edges on edges.parent_food = walk.current_food
    where not walk.cycle
  )
  select coalesce(bool_or(cycle), false) into has_cycle from walk;

  if has_cycle then
    raise exception 'Recipe output and ingredient graph contains a cycle';
  end if;

  return null;
end;
$$;

create constraint trigger recipes_reject_cycles
after insert or update of output_food or delete on public.recipes
deferrable initially deferred
for each row execute function public.reject_recipe_cycles();

create constraint trigger recipe_ingredients_reject_cycles
after insert or update or delete on public.recipe_ingredients
deferrable initially deferred
for each row execute function public.reject_recipe_cycles();

create function public.reject_prep_cycles()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  creates_cycle boolean;
begin
  if new.parent_prep is null then
    return new;
  end if;

  with recursive ancestors(id, parent_prep) as (
    select prep.id, prep.parent_prep
    from public.preps prep
    where prep.id = new.parent_prep
    union all
    select prep.id, prep.parent_prep
    from public.preps prep
    join ancestors on prep.id = ancestors.parent_prep
  )
  select exists(select 1 from ancestors where id = new.id)
  into creates_cycle;

  if creates_cycle then
    raise exception 'Prep parent graph contains a cycle';
  end if;

  return new;
end;
$$;

create trigger preps_reject_cycles
before insert or update of parent_prep on public.preps
for each row execute function public.reject_prep_cycles();

create function public.initialize_inventory_lot()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.remaining_qty = new.initial_qty;
  return new;
end;
$$;

create trigger inventory_lots_initialize
before insert on public.inventory_lots
for each row execute function public.initialize_inventory_lot();

create function public.prevent_inventory_cache_edit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.initial_qty is distinct from old.initial_qty
    and exists (
      select 1 from public.inventory_events where lot = old.id
    ) then
    raise exception 'initial_qty cannot change after inventory events exist';
  end if;

  if current_setting('pantry.refreshing_inventory_lot', true) is distinct from 'on' then
    if new.initial_qty is distinct from old.initial_qty then
      new.remaining_qty = new.initial_qty;
    else
      new.remaining_qty = old.remaining_qty;
    end if;
  end if;

  return new;
end;
$$;

create trigger inventory_lots_protect_cache
before update on public.inventory_lots
for each row execute function public.prevent_inventory_cache_edit();

create function public.refresh_inventory_lot(p_lot uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_remaining numeric;
begin
  perform 1
  from public.inventory_lots
  where id = p_lot
  for update;

  select
    lot.initial_qty + coalesce(sum(event.quantity_delta) filter (
      where event.voided_at is null
    ), 0)
  into next_remaining
  from public.inventory_lots lot
  left join public.inventory_events event on event.lot = lot.id
  where lot.id = p_lot
  group by lot.initial_qty;

  if next_remaining is null then
    raise exception 'Inventory lot % does not exist', p_lot;
  end if;

  if next_remaining < 0 then
    raise exception 'Inventory event would make lot % negative', p_lot;
  end if;

  perform set_config('pantry.refreshing_inventory_lot', 'on', true);
  update public.inventory_lots
  set remaining_qty = next_remaining
  where id = p_lot;
  perform set_config('pantry.refreshing_inventory_lot', 'off', true);
end;
$$;

create function public.inventory_events_refresh_lot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.refresh_inventory_lot(old.lot);
  end if;

  if tg_op in ('INSERT', 'UPDATE') and (tg_op <> 'UPDATE' or new.lot <> old.lot) then
    perform public.refresh_inventory_lot(new.lot);
  end if;

  return null;
end;
$$;

create trigger inventory_events_refresh_lot
after insert or update or delete on public.inventory_events
for each row execute function public.inventory_events_refresh_lot();

create function public.validate_time_zone()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from pg_catalog.pg_timezone_names where name = new.time_zone
  ) then
    raise exception 'Unknown IANA time zone: %', new.time_zone;
  end if;
  return new;
end;
$$;

create trigger app_settings_validate_time_zone
before insert or update of time_zone on public.app_settings
for each row execute function public.validate_time_zone();

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
    'app_settings'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'create policy authenticated_full_access on public.%I for all to authenticated using (true) with check (true)',
      table_name
    );
    execute format(
      'grant select, insert, update, delete on public.%I to authenticated',
      table_name
    );
  end loop;
end;
$$;

grant usage on schema public to authenticated;
grant execute on function public.food_accepts_unit(uuid, uuid) to authenticated;
revoke execute on function public.refresh_inventory_lot(uuid) from public, anon, authenticated;
