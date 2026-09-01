create table public.planned_consumptions (
  id uuid primary key default gen_random_uuid(),
  meal_plan uuid not null unique references public.meal_plans(id) on delete cascade,
  servings numeric not null check (servings > 0),
  status text not null default 'planned' check (status in ('planned', 'fulfilled', 'cancelled')),
  food_log uuid unique references public.food_logs(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint planned_consumptions_fulfillment check (
    (status = 'fulfilled') = (food_log is not null)
  )
);

comment on table public.planned_consumptions is
  'Expected portions associated with meal-plan components. These drive nutrition projections but are not actual consumption history.';
comment on column public.planned_consumptions.servings is
  'Recipe or reusable-meal servings expected to be eaten, independent of the meal plan preparation scale.';

create index planned_consumptions_status_idx
  on public.planned_consumptions(status)
  where status = 'planned';

create trigger planned_consumptions_set_updated_at
before update on public.planned_consumptions
for each row execute function public.set_updated_at();

alter table public.planned_consumptions enable row level security;
create policy owner_full_access on public.planned_consumptions
for all to authenticated
using ((select public.is_app_owner()))
with check ((select public.is_app_owner()));
grant select, insert, update, delete on public.planned_consumptions to authenticated;

-- Existing plans never recorded an expected eaten portion. One serving per
-- component is the conservative migration: it avoids treating an entire batch
-- as consumed and can be corrected explicitly in the planner.
insert into public.planned_consumptions(meal_plan, servings)
select id, 1
from public.meal_plans;

create function public.create_default_planned_consumption()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.planned_consumptions(meal_plan, servings)
  values (new.id, 1)
  on conflict (meal_plan) do nothing;
  return new;
end;
$$;

create trigger meal_plans_create_planned_consumption
after insert on public.meal_plans
for each row execute function public.create_default_planned_consumption();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'planned_consumptions'
     ) then
    alter publication supabase_realtime add table public.planned_consumptions;
  end if;
end
$$;

create or replace function public.gpt_replace_weekly_plan(p_week_start date, p_entries jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry jsonb;
  plan_id uuid;
  inserted_count integer := 0;
  grocery_count integer;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_entries) <> 'array' then raise exception 'entries must be an array'; end if;
  delete from public.meal_plans where plan_date between p_week_start and p_week_start + 6;
  for entry in select value from jsonb_array_elements(p_entries)
  loop
    if (entry ->> 'date')::date not between p_week_start and p_week_start + 6 then
      raise exception 'Plan entry date is outside the requested week';
    end if;
    if coalesce((entry ->> 'plannedServings')::numeric, 0) <= 0 then
      raise exception 'plannedServings must be positive';
    end if;
    insert into public.meal_plans(
      plan_date, daypart, scheduled_time, meal, recipe, scale_factor, status, name, emoji,
      group_id, leftover_of_group_id, intent, preparation_tasks, note
    ) values (
      (entry ->> 'date')::date, (entry ->> 'slot')::public.daypart,
      nullif(entry ->> 'scheduledTime', '')::time,
      case when entry ->> 'source' = 'meal' then (entry ->> 'sourceId')::uuid else null end,
      case when entry ->> 'source' = 'recipe' then (entry ->> 'sourceId')::uuid else null end,
      coalesce((entry ->> 'scaleFactor')::numeric, 1), 'planned', nullif(entry ->> 'name', ''),
      nullif(entry ->> 'emoji', ''), nullif(entry ->> 'groupId', ''),
      nullif(entry ->> 'leftoverOfGroupId', ''), coalesce(nullif(entry ->> 'intent', ''), 'prepare'),
      coalesce(entry -> 'preparationTasks', '[]'::jsonb), nullif(entry ->> 'note', '')
    ) returning id into plan_id;

    update public.planned_consumptions
    set servings = (entry ->> 'plannedServings')::numeric
    where meal_plan = plan_id;
    inserted_count := inserted_count + 1;
  end loop;
  grocery_count := public.rebuild_shopping_from_plan(p_week_start, p_week_start + 6);
  return jsonb_build_object('status', 'replaced', 'entries', inserted_count, 'generatedGroceries', grocery_count);
end;
$$;

revoke all on function public.create_default_planned_consumption() from public, anon, authenticated;
