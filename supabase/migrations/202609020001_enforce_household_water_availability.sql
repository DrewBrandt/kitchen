create or replace function public.enforce_household_water_availability()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if lower(btrim(new.name)) = 'water' then
    new.always_available := true;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_household_water_availability on public.base_foods;
create trigger enforce_household_water_availability
before insert or update of name, always_available on public.base_foods
for each row execute function public.enforce_household_water_availability();

update public.base_foods
set always_available = true,
    updated_at = now()
where lower(btrim(name)) = 'water'
  and not always_available;

delete from public.shopping_items
where source = 'generated'
  and food in (
    select id
    from public.base_foods
    where lower(btrim(name)) = 'water'
  );

comment on function public.enforce_household_water_availability() is
  'Keeps canonical household water available without inventory lots or grocery shortages.';
