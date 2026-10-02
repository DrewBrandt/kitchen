-- Disposable database only. Actual API roles, synthetic owner and sessions.
begin;
do $$ declare email text; begin
  if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict email;
  insert into auth.users(id,email,email_confirmed_at) values
    ('99500000-0000-0000-0000-000000000001',email,now()),
    ('99500000-0000-0000-0000-000000000002','not-owner@example.test',now());
  insert into auth.sessions(id,user_id) values
    ('99500000-0000-0000-0000-000000000011','99500000-0000-0000-0000-000000000001'),
    ('99500000-0000-0000-0000-000000000012','99500000-0000-0000-0000-000000000002');
end $$;
-- Force failure after all plan rows were inserted, while writing portions.
create function isolated_test.reject_test_portion() returns trigger language plpgsql as $$
begin if new.servings=97 then raise exception 'Test portion failure'; end if; return new; end $$;
create trigger reject_test_portion before update on public.planned_consumptions for each row execute function isolated_test.reject_test_portion();
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99500000-0000-0000-0000-000000000001","session_id":"99500000-0000-0000-0000-000000000011"}',true);
set local role authenticated;
do $$ declare a uuid; b uuid; sources jsonb; payload jsonb; result jsonb; request uuid:=gen_random_uuid(); n integer; begin
 a:=(public.owner_create_recipe(gen_random_uuid(),'{"name":"Chicken","servings":6,"ingredients":[]}')->>'id')::uuid;
 b:=(public.owner_create_recipe(gen_random_uuid(),'{"name":"Rice","servings":4,"ingredients":[]}')->>'id')::uuid;
 sources:=public.owner_append_plan(gen_random_uuid(),jsonb_build_object('plan_date','2026-10-02','daypart','dinner','dishes',jsonb_build_array(jsonb_build_object('recipe',a,'scale_factor',0.5,'planned_servings',0.5),jsonb_build_object('recipe',b,'scale_factor',0.5,'planned_servings',1))));
 a:=(sources#>>'{planIds,0}')::uuid; b:=(sources#>>'{planIds,1}')::uuid;
 payload:=jsonb_build_object('intent','leftover','source_group_id',(select group_id from public.meal_plans where id=a),'plan_date','2026-10-03','daypart','lunch','leftover_dishes',jsonb_build_array(jsonb_build_object('source_meal_plan',a,'planned_servings',0.5),jsonb_build_object('source_meal_plan',b,'planned_servings',1)));
 result:=public.owner_append_plan(request,payload);
 if public.owner_append_plan(request,payload)<>result then raise exception 'Retry changed result'; end if;
 if not exists(select 1 from public.meal_plans p join public.planned_consumptions c on c.meal_plan=p.id where p.id=(result#>>'{planIds,0}')::uuid and p.source_meal_plan=a and c.servings=0.5) or not exists(select 1 from public.meal_plans p join public.planned_consumptions c on c.meal_plan=p.id where p.id=(result#>>'{planIds,1}')::uuid and p.source_meal_plan=b and c.servings=1) then raise exception 'Unequal source portions lost'; end if;
 payload:=jsonb_set(payload,'{leftover_dishes}',jsonb_build_array(jsonb_build_object('source_meal_plan',b,'planned_servings',0.75)));
 result:=public.owner_append_plan(gen_random_uuid(),payload);
 if jsonb_array_length(result->'planIds')<>1 or not exists(select 1 from public.meal_plans where id=(result#>>'{planIds,0}')::uuid and source_meal_plan=b) then raise exception 'Subset lost'; end if;
 select count(*) into n from public.meal_plans;
 payload:=jsonb_set(payload,'{leftover_dishes}',jsonb_build_array(jsonb_build_object('source_meal_plan',a,'planned_servings',0.5),jsonb_build_object('source_meal_plan',b,'planned_servings',97)));
 begin perform public.owner_append_plan(gen_random_uuid(),payload); raise exception 'Failure not raised'; exception when raise_exception then if sqlerrm<>'Test portion failure' then raise; end if; end;
 if (select count(*) from public.meal_plans)<>n then raise exception 'Partial leftover insert survived'; end if;
 set constraints all immediate;
end $$;
rollback;
select 'PASS: unequal leftovers, subset, replay, rollback and exact source links';
