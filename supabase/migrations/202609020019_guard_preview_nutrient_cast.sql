-- Migration 018 was deployed before its custom-candidate test exposed that SQL
-- predicate evaluation order is not a short-circuit guarantee. Patch the stored
-- function body so metadata values such as a source citation are never cast to
-- numeric. The guarded expression is already present in 018 for clean installs.
do $migration$
declare
  original_definition text;
  repaired_definition text;
begin
  select pg_get_functiondef(
    'public.gpt_preview_daily_nutrition(date,jsonb)'::regprocedure
  ) into original_definition;

  repaired_definition := replace(
    original_definition,
    'and nutrient.value::numeric < 0',
    'and case
          when nutrient.key = any(array[''calories'',''proteinG'',''carbsG'',''fatG'',''fiberG'',''sugarG'',''sodiumMg''])
            then nutrient.value::numeric < 0
          else false
        end'
  );

  if repaired_definition = original_definition then
    raise exception 'Expected preview nutrient guard was not found';
  end if;
  execute repaired_definition;
end;
$migration$;
