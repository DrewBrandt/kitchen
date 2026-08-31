alter table public.base_foods
  add column aliases text[] not null default '{}',
  add column ingredient_role text,
  add column store_aisle text,
  add column sugar_g numeric check (sugar_g >= 0),
  add column nutrition_source text,
  add column nutrition_is_estimated boolean not null default false,
  add column legacy_firebase_id text unique;

alter table public.products
  add column aliases text[] not null default '{}',
  add column sugar_g numeric check (sugar_g >= 0),
  add column nutrition_source text,
  add column nutrition_is_estimated boolean not null default false,
  add column legacy_firebase_id text unique;

alter table public.products
  drop constraint products_nutrition_basis_required,
  add constraint products_nutrition_basis_required check (
    nutrition_basis_qty is not null
    or num_nonnulls(kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg) = 0
  );

alter table public.recipes
  add column portions jsonb not null default '[]'::jsonb
    check (jsonb_typeof(portions) = 'array'),
  add column preparation_rules jsonb not null default '[]'::jsonb
    check (jsonb_typeof(preparation_rules) = 'array'),
  add column source_url text,
  add column source_note text,
  add column prompt_for_feedback boolean not null default true,
  add column override_sugar_g numeric check (override_sugar_g >= 0),
  add column legacy_firebase_id text unique;

alter table public.recipes
  drop constraint recipes_override_basis_required,
  add constraint recipes_override_basis_required check (
    override_basis_qty is not null
    or num_nonnulls(
      override_kcal,
      override_protein_g,
      override_carbs_g,
      override_fat_g,
      override_fiber_g,
      override_sugar_g,
      override_sodium_mg
    ) = 0
  );

alter table public.meals
  add column notes text,
  add column legacy_firebase_id text unique;

alter table public.preps
  add column legacy_firebase_id text unique;

alter table public.inventory_lots
  add column cost_is_estimated boolean not null default false,
  add column cost_source text,
  add column legacy_firebase_id text unique;

create table public.food_logs (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  kind text not null check (
    kind in ('inventory', 'recipe', 'meal', 'external', 'prepared', 'custom')
  ),
  recipe uuid references public.recipes(id),
  product uuid references public.products(id),
  servings numeric check (servings > 0),
  occurred_at timestamptz not null default now(),
  voided_at timestamptz,
  kcal numeric check (kcal >= 0),
  protein_g numeric check (protein_g >= 0),
  carbs_g numeric check (carbs_g >= 0),
  fat_g numeric check (fat_g >= 0),
  fiber_g numeric check (fiber_g >= 0),
  sugar_g numeric check (sugar_g >= 0),
  sodium_mg numeric check (sodium_mg >= 0),
  nutrition_is_estimated boolean not null default false,
  note text,
  legacy_firebase_id text unique,
  created_at timestamptz not null default now(),
  check (voided_at is null or voided_at >= occurred_at)
);

create index food_logs_occurred_at_idx
  on public.food_logs(occurred_at)
  where voided_at is null;
create index food_logs_recipe_idx on public.food_logs(recipe);
create index food_logs_product_idx on public.food_logs(product);

alter table public.inventory_events
  add column food_log uuid references public.food_logs(id);

create index inventory_events_food_log_idx
  on public.inventory_events(food_log)
  where food_log is not null;

alter table public.meal_plans
  add column name text,
  add column emoji text,
  add column group_id text,
  add column leftover_of_group_id text,
  add column intent text not null default 'prepare'
    check (intent in ('prepare', 'leftover')),
  add column preparation_tasks jsonb not null default '[]'::jsonb
    check (jsonb_typeof(preparation_tasks) = 'array'),
  add column legacy_firebase_id text unique;

alter table public.shopping_items
  add column first_needed_date date,
  add column quantity_label text,
  add column legacy_firebase_id text unique;

create table public.personal_settings (
  singleton boolean primary key default true check (singleton),
  nutrition_calories numeric not null default 2000 check (nutrition_calories > 0),
  nutrition_protein_g numeric not null default 50 check (nutrition_protein_g >= 0),
  nutrition_carbs_g numeric not null default 275 check (nutrition_carbs_g >= 0),
  nutrition_fat_g numeric not null default 78 check (nutrition_fat_g >= 0),
  nutrition_fiber_g numeric not null default 28 check (nutrition_fiber_g >= 0),
  nutrition_sodium_mg numeric not null default 2300 check (nutrition_sodium_mg >= 0),
  nutrition_label text,
  allergies text[] not null default '{}',
  dislikes text[] not null default '{}',
  favorites text[] not null default '{}',
  dietary_rules text[] not null default '{}',
  planning_notes text,
  time_zone text not null default 'America/New_York',
  routine_days jsonb not null default '{}'::jsonb
    check (jsonb_typeof(routine_days) = 'object'),
  dinner_start time not null default '18:00',
  dinner_end time not null default '20:30',
  commute_minutes integer not null default 0 check (commute_minutes >= 0),
  preparation_buffer_minutes integer not null default 30
    check (preparation_buffer_minutes >= 0),
  default_thaw_hours numeric not null default 24 check (default_thaw_hours >= 0),
  routine_notes text,
  calendar_settings jsonb not null default '{}'::jsonb
    check (jsonb_typeof(calendar_settings) = 'object'),
  updated_at timestamptz not null default now(),
  check (dinner_end > dinner_start)
);

insert into public.personal_settings(singleton) values (true);

create trigger personal_settings_set_updated_at
before update on public.personal_settings
for each row execute function public.set_updated_at();

create trigger personal_settings_validate_time_zone
before insert or update of time_zone on public.personal_settings
for each row execute function public.validate_time_zone();

drop view public.daily_nutrition;

create view public.daily_nutrition
with (security_invoker = true)
as
select
  (log.occurred_at at time zone settings.time_zone)::date as local_date,
  sum(log.kcal) as kcal,
  sum(log.protein_g) as protein_g,
  sum(log.carbs_g) as carbs_g,
  sum(log.fat_g) as fat_g,
  sum(log.fiber_g) as fiber_g,
  sum(log.sugar_g) as sugar_g,
  sum(log.sodium_mg) as sodium_mg
from public.food_logs log
cross join public.app_settings settings
where log.voided_at is null
group by (log.occurred_at at time zone settings.time_zone)::date;

alter table public.food_logs enable row level security;
create policy authenticated_full_access
  on public.food_logs for all to authenticated
  using (true) with check (true);
grant select, insert, update, delete on public.food_logs to authenticated;

alter table public.personal_settings enable row level security;
create policy authenticated_full_access
  on public.personal_settings for all to authenticated
  using (true) with check (true);
grant select, insert, update, delete on public.personal_settings to authenticated;
grant select on public.daily_nutrition to authenticated;
