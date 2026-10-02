-- Disposable integration: legacy POST edits after grouped owner planning.
begin;
do $$ declare email text; u uuid; begin
  if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict email;
  insert into auth.users(id,email,email_confirmed_at) values('98600000-0000-0000-0000-000000000001',email,now());
  insert into auth.sessions(id,user_id) values('98600000-0000-0000-0000-000000000011','98600000-0000-0000-0000-000000000001');
  select id into strict u from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit) values('98600000-0000-0000-0000-000000000021','Grouped POST rice','weight',u);
  insert into public.products(id,food,name,package_qty_base,package_unit) values('98600000-0000-0000-0000-000000000022','98600000-0000-0000-0000-000000000021','Grouped POST product',100,u);
end $$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select public.gpt_save_recipe('{"id":"98600000-0000-0000-0000-000000000031","name":"Grouped POST recipe","servings":2,"sourceNote":"Keep provenance","nutrition":{"calories":400},"ingredients":[{"foodId":"98600000-0000-0000-0000-000000000021","quantity":10,"unit":"g","note":"Keep note"}]}');
reset role;
update public.recipe_ingredients set id='98600000-0000-0000-0000-000000000041',pinned_product='98600000-0000-0000-0000-000000000022' where recipe='98600000-0000-0000-0000-000000000031';
select set_config('request.jwt.claims','{"role":"authenticated","sub":"98600000-0000-0000-0000-000000000001","session_id":"98600000-0000-0000-0000-000000000011"}',true);
set local role authenticated;
select public.owner_append_plan('98600000-0000-0000-0000-000000000051','{"plan_date":"2026-10-03","daypart":"dinner","dishes":[{"recipe":"98600000-0000-0000-0000-000000000031","scale_factor":2,"planned_servings":1.5},{"recipe":"98600000-0000-0000-0000-000000000031","scale_factor":0.5,"planned_servings":0.5}]}');
reset role;
-- Snapshot only these synthetic plan rows; POST must not alter portions or grouping.
create temporary table grouped_post_before as
select p.id,to_jsonb(p) plan,to_jsonb(c) consumption from public.meal_plans p join public.planned_consumptions c on c.meal_plan=p.id where p.recipe='98600000-0000-0000-0000-000000000031';
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select public.gpt_save_recipe('{"id":"98600000-0000-0000-0000-000000000031","name":"Grouped POST edited","servings":4,"ingredients":[{"foodId":"98600000-0000-0000-0000-000000000021","quantity":20,"unit":"g"}]}');
reset role;
do $$ begin
  if not exists(select 1 from public.recipes where id='98600000-0000-0000-0000-000000000031' and servings=4 and source_note='Keep provenance' and override_basis_qty=2 and override_kcal=400)
    or not exists(select 1 from public.recipe_ingredients where id='98600000-0000-0000-0000-000000000041' and qty=20 and note='Keep note' and pinned_product='98600000-0000-0000-0000-000000000022')
  then raise exception 'Grouped POST edit lost recipe metadata, nutrition basis or ingredient identity'; end if;
  if (select count(*) from grouped_post_before)<>2
    or (select count(distinct group_id) from public.meal_plans where recipe='98600000-0000-0000-0000-000000000031')<>1
    or exists(select 1 from grouped_post_before b left join public.meal_plans p on p.id=b.id left join public.planned_consumptions c on c.meal_plan=p.id where b.plan is distinct from to_jsonb(p) or b.consumption is distinct from to_jsonb(c))
  then raise exception 'POST changed grouped plan identity or portions'; end if;
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"98600000-0000-0000-0000-000000000001","session_id":"98600000-0000-0000-0000-000000000011"}',true);
set local role authenticated;
-- The same atomic planning request must still return its original two dishes.
select public.owner_append_plan('98600000-0000-0000-0000-000000000051','{"plan_date":"2026-10-03","daypart":"dinner","dishes":[{"recipe":"98600000-0000-0000-0000-000000000031","scale_factor":2,"planned_servings":1.5},{"recipe":"98600000-0000-0000-0000-000000000031","scale_factor":0.5,"planned_servings":0.5}]}');
reset role;
do $$ begin
  if (select count(*) from public.meal_plans where recipe='98600000-0000-0000-0000-000000000031')<>2 then raise exception 'Grouped request replay duplicated dishes'; end if;
end $$;
rollback;
select 'PASS: grouped recipe POST metadata, ingredient identity, independent portions and request replay';
