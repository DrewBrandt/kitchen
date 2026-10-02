-- Synthetic, rollback-only integration scenario using actual authenticated RPCs.
begin;
do $$ declare email text; begin
  if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict email;
  insert into auth.users(id,email,email_confirmed_at) values('98750000-0000-0000-0000-000000000001',email,now());
  insert into auth.sessions(id,user_id) values('98750000-0000-0000-0000-000000000011','98750000-0000-0000-0000-000000000001');
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"98750000-0000-0000-0000-000000000001","session_id":"98750000-0000-0000-0000-000000000011"}',true);
set local role authenticated;
do $$ declare
 r uuid:=gen_random_uuid(); r2 uuid:=gen_random_uuid(); request uuid:=gen_random_uuid(); bad_request uuid:=gen_random_uuid();
 result jsonb; payload jsonb; snapshot jsonb; n bigint; ids uuid[]; p1 jsonb; p2 jsonb; logs uuid[]; invalid jsonb;
begin
 insert into public.recipes(id,name,servings) values(r,'Multi-dish recipe',4),(r2,'Multi-dish side',2);
 payload:=jsonb_build_object('plan_date','2026-10-03','daypart','dinner','dishes',jsonb_build_array(
   jsonb_build_object('recipe',r,'scale_factor',1,'planned_servings',1.5),
   jsonb_build_object('recipe',r2,'scale_factor',0.5,'planned_servings',0.5),
   jsonb_build_object('recipe',r,'scale_factor',2,'planned_servings',2)));
 select jsonb_agg(to_jsonb(s) order by id) into snapshot from public.shopping_items s;
 result:=public.owner_append_plan(request,payload);
 if public.owner_append_plan(request,payload)<>result then raise exception 'Replay returned different plans'; end if;
 select array_agg(value::uuid order by ordinality) into ids from jsonb_array_elements_text(result->'planIds') with ordinality;
 if cardinality(ids)<>3 or (select count(distinct group_id) from public.meal_plans where id=any(ids))<>1
   or not exists(select 1 from public.meal_plans where id=ids[1] and recipe=r and scale_factor=1)
   or not exists(select 1 from public.meal_plans where id=ids[2] and recipe=r2 and scale_factor=0.5)
   or not exists(select 1 from public.meal_plans where id=ids[3] and recipe=r and scale_factor=2)
   or not exists(select 1 from public.planned_consumptions where meal_plan=ids[1] and servings=1.5)
   or not exists(select 1 from public.planned_consumptions where meal_plan=ids[2] and servings=0.5)
   or not exists(select 1 from public.planned_consumptions where meal_plan=ids[3] and servings=2) then raise exception 'Grouped row identity, make/eat quantities, or duplicate recipe lost'; end if;
 if (select jsonb_agg(to_jsonb(s) order by id) from public.shopping_items s) is distinct from snapshot then raise exception 'Grouped append changed groceries'; end if;
 begin perform public.owner_append_plan(request,payload||'{"daypart":"lunch"}'); raise exception 'Changed replay accepted';
 exception when raise_exception then if sqlerrm not like 'This request ID belongs%' then raise; end if; end;
 n:=(select count(*) from public.meal_plans);
 begin perform public.owner_append_plan(bad_request,jsonb_set(payload,'{dishes,1,recipe}',to_jsonb(gen_random_uuid()))); raise exception 'Missing second recipe accepted'; exception when foreign_key_violation then null; end;
 if (select count(*) from public.meal_plans)<>n then raise exception 'Failed group left first dish'; end if;
 -- The failed transaction must not retain the request claim.
 perform public.owner_append_plan(bad_request,payload);
 for invalid in select value from jsonb_array_elements('[[],null,{},[null],[{}],[{"recipe":""}]]') loop
   begin perform public.owner_append_plan(gen_random_uuid(),jsonb_set(payload,'{dishes}',invalid)); raise exception 'Invalid dishes accepted';
   exception when raise_exception then if sqlerrm='Invalid dishes accepted' then raise; end if; end;
 end loop;
 begin perform public.owner_append_plan(gen_random_uuid(),payload||jsonb_build_object('recipe',r)); raise exception 'Mixed single/group accepted';
 exception when raise_exception then if sqlerrm<>'Use per-dish quantities and sources' then raise; end if; end;
 -- Partial preparation and consumption retain exact dish sources, even for repeated recipes.
 p1:=public.prepare_recipe(gen_random_uuid(),r,1,4,'fridge',ids[1],0,now());
 if (select status from public.meal_plans where id=ids[1])<>'made'
   or exists(select 1 from public.meal_plans where id in(ids[2],ids[3]) and status<>'planned') then raise exception 'Partial preparation touched another dish'; end if;
 p2:=public.prepare_recipe(gen_random_uuid(),r2,0.5,1,'fridge',ids[2],0,now());
 logs:=public.consume_planned_meals(gen_random_uuid(),array[ids[1],ids[2]],array[1.5::numeric,0.5],now());
 if cardinality(logs)<>2 or (select remaining_qty from public.inventory_lots where id=(p1->>'lotId')::uuid)<>2.5
   or (select remaining_qty from public.inventory_lots where id=(p2->>'lotId')::uuid)<>0.5
   or (select status from public.planned_consumptions where meal_plan=ids[3])<>'planned' then raise exception 'Independent consumption lost exact source or portions'; end if;
 raise notice 'PASS grouped append: independent make/eat, repeated recipes, replay, atomic rollback, partial preparation, exact consumption, no grocery rebuild';
end $$;
reset role;
-- Force an error after a dish was inserted, during its portion update.
create function isolated_test.reject_group_portion() returns trigger language plpgsql as $$ begin if new.servings=97 then raise exception 'Injected portion failure'; end if; return new; end $$;
create trigger reject_group_portion before update on public.planned_consumptions for each row execute function isolated_test.reject_group_portion();
set local role authenticated;
do $$ declare r uuid; n bigint; before_portions bigint; request uuid:=gen_random_uuid(); payload jsonb; begin
 select id into strict r from public.recipes where name='Multi-dish recipe';
 n:=(select count(*) from public.meal_plans); before_portions:=(select count(*) from public.planned_consumptions);
 payload:=jsonb_build_object('plan_date','2026-10-03','daypart','dinner','dishes',jsonb_build_array(
   jsonb_build_object('recipe',r,'scale_factor',1,'planned_servings',1),jsonb_build_object('recipe',r,'scale_factor',1,'planned_servings',97)));
 begin perform public.owner_append_plan(request,payload); raise exception 'Injected failure not raised';
 exception when raise_exception then if sqlerrm<>'Injected portion failure' then raise; end if; end;
 if (select count(*) from public.meal_plans)<>n or (select count(*) from public.planned_consumptions)<>before_portions then raise exception 'Portion failure left partial group'; end if;
 perform public.owner_append_plan(request,jsonb_set(payload,'{dishes,1,planned_servings}','2'));
 raise notice 'PASS second portion failure rolls back all dishes, portions and request claim';
end $$;
reset role;
rollback;
