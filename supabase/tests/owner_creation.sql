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
do $$ declare
  u uuid; f uuid:=gen_random_uuid(); r uuid; r2 uuid; product uuid:=gen_random_uuid(); lot uuid:=gen_random_uuid();
  recipe_payload jsonb; result jsonb; again jsonb; plan_payload jsonb; group_key text:=gen_random_uuid()::text;
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); other uuid:=gen_random_uuid(); baseline jsonb; n bigint; request uuid;
begin
  select id into strict u from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit) values(f,'Owner creation food','weight',u);
  recipe_payload:=jsonb_build_object('name','Owner atomic recipe','servings',4,'instructions','["Cook","Serve"]'::jsonb,
    'ingredients',jsonb_build_array(jsonb_build_object('ingredient',f,'qty',180,'unit',u,'sort_order',0)));
  result:=public.owner_create_recipe('99500000-0000-0000-0000-000000000020',recipe_payload); r:=(result->>'id')::uuid;
  again:=public.owner_create_recipe('99500000-0000-0000-0000-000000000020',recipe_payload);
  if again<>result or (select count(*) from public.recipe_ingredients where recipe=r)<>1 then raise exception 'Recipe retry duplicated'; end if;
  if not exists(select 1 from public.recipes where id=r and servings=4 and prompt_for_feedback=false and instructions='["Cook","Serve"]') then raise exception 'Recipe defaults changed'; end if;
  begin
    perform public.owner_create_recipe('99500000-0000-0000-0000-000000000020',recipe_payload||'{"name":"Changed"}');
    raise exception 'Changed recipe payload accepted';
  exception when raise_exception then if sqlerrm not like 'This request ID belongs%' then raise; end if; end;
  r2:=(public.owner_create_recipe(gen_random_uuid(),'{"name":"Empty ingredients allowed","ingredients":[]}')->>'id')::uuid;
  if not exists(select 1 from public.recipes where id=r2 and servings=1 and instructions='[]') then raise exception 'Empty recipe defaults changed'; end if;
  n:=(select count(*) from public.recipes);
  begin
    perform public.owner_create_recipe('99500000-0000-0000-0000-000000000021',jsonb_build_object('name','Must roll back','ingredients',
      jsonb_build_array(jsonb_build_object('ingredient',f,'qty',1,'unit',u),jsonb_build_object('ingredient',gen_random_uuid(),'qty',1,'unit',u))));
    raise exception 'Bad ingredient accepted';
  exception when foreign_key_violation then null;
    when raise_exception then if sqlerrm<>'Ingredient unit cannot be converted to the food stock measure' then raise; end if; end;
  if (select count(*) from public.recipes)<>n then raise exception 'Recipe partially committed'; end if;
  begin perform public.owner_create_recipe(gen_random_uuid(),recipe_payload||jsonb_build_object('id',r)); raise exception 'Upsert accepted';
  exception when raise_exception then if sqlerrm<>'Invalid recipe fields' then raise; end if; end;

  insert into public.products(id,food,name,package_qty_base,package_unit) values(product,f,'Owner test product',180,u);
  insert into public.inventory_lots(id,product,initial_qty,remaining_qty,location) values(lot,product,180,180,'pantry');
  insert into public.meal_plans(id,recipe,plan_date,daypart,group_id,intent,scale_factor,name,emoji) values
    (a,r,current_date,'dinner',group_key,'prepare',0.5,'Rice A','A'),
    (b,r2,current_date,'dinner',group_key,'prepare',2,'Dish B','B'),
    (other,r,current_date+14,'dinner','unrelated','prepare',10,'Unrelated','C');
  insert into public.shopping_items(free_text,source,note) values('Keep manual','manual','Unchanged');
  perform public.rebuild_shopping_from_plan(current_date+14,current_date+20);
  if not exists(select 1 from public.shopping_items where source='generated' and generated_active) then raise exception 'Missing unrelated-week grocery fixture'; end if;
  select jsonb_agg(to_jsonb(s) order by id) into baseline from public.shopping_items s;
  plan_payload:=jsonb_build_object('intent','leftover','plan_date',current_date+1,'daypart','lunch','planned_servings',0.75,'source_group_id',group_key);
  result:=public.owner_append_plan('99500000-0000-0000-0000-000000000030',plan_payload);
  if jsonb_array_length(result->'planIds')<>2 then raise exception 'Group components missing'; end if;
  if (select count(distinct group_id) from public.meal_plans where id in(select value::uuid from jsonb_array_elements_text(result->'planIds')))<>1 then raise exception 'Split leftover group'; end if;
  if (select count(*) from public.meal_plans p join public.meal_plans s on s.id=p.source_meal_plan
      join public.planned_consumptions c on c.meal_plan=p.id
      where p.id in(select value::uuid from jsonb_array_elements_text(result->'planIds'))
        and s.id in(a,b) and p.recipe=s.recipe and p.scale_factor=s.scale_factor and p.name=s.name and p.emoji=s.emoji
        and p.leftover_of_group_id=group_key and p.intent='leftover' and p.status='planned' and c.servings=0.75)<>2 then raise exception 'Source/portion metadata changed'; end if;
  -- Replay returns the original snapshot even after another source component is added.
  insert into public.meal_plans(recipe,plan_date,daypart,group_id,intent) values(r,current_date,'dinner',group_key,'prepare');
  if public.owner_append_plan('99500000-0000-0000-0000-000000000030',plan_payload)<>result then raise exception 'Plan replay changed source expansion'; end if;
  begin perform public.owner_append_plan('99500000-0000-0000-0000-000000000030',plan_payload||'{"planned_servings":2}'); raise exception 'Changed plan accepted';
  exception when raise_exception then if sqlerrm not like 'This request ID belongs%' then raise; end if; end;
  begin perform public.owner_append_plan('99500000-0000-0000-0000-000000000020',plan_payload); raise exception 'Cross-operation replay accepted';
  exception when raise_exception then if sqlerrm<>'requestId was already used for a different operation' then raise; end if; end;
  n:=(select count(*) from public.meal_plans);
  begin perform public.owner_append_plan('99500000-0000-0000-0000-000000000031',plan_payload||'{"planned_servings":97}'); raise exception 'Portion failure not triggered';
  exception when raise_exception then if sqlerrm<>'Test portion failure' then raise; end if; end;
  if (select count(*) from public.meal_plans)<>n then raise exception 'Plan partially committed'; end if;
  result:=public.owner_append_plan(gen_random_uuid(),jsonb_build_object('recipe',r,'plan_date',current_date,'daypart','dinner','scale_factor',0.5,'planned_servings',1));
  if not exists(select 1 from public.meal_plans p join public.planned_consumptions c on c.meal_plan=p.id
    where p.id=(result#>>'{planIds,0}')::uuid and p.recipe=r and p.scale_factor=0.5 and c.servings=1) then raise exception 'Preparation defaults changed'; end if;
  foreach request in array array[product,lot] loop
    result:=public.owner_append_plan(gen_random_uuid(),jsonb_build_object('intent','consume','plan_date',current_date,'daypart','snack',
      case when request=product then 'product' else 'inventory_lot' end,request,'planned_servings',0.5));
    if not exists(select 1 from public.meal_plans where id=(result#>>'{planIds,0}')::uuid and consume_from_inventory=true
      and scale_factor=1 and coalesce(inventory_lot,public.meal_plans.product)=request) then raise exception 'Pantry source changed'; end if;
  end loop;
  -- Legacy ungrouped source selection remains exact.
  update public.meal_plans set group_id=null where id=other;
  result:=public.owner_append_plan(gen_random_uuid(),plan_payload||jsonb_build_object('source_group_id',other));
  if not exists(select 1 from public.meal_plans where id=(result#>>'{planIds,0}')::uuid and source_meal_plan=other) then raise exception 'Exact source fallback lost'; end if;
  begin perform public.owner_append_plan(gen_random_uuid(),plan_payload||'{"mode":"replaceWeek"}'); raise exception 'Replacement accepted';
  exception when raise_exception then if sqlerrm<>'Invalid plan fields' then raise; end if; end;
  begin perform public.owner_append_plan(gen_random_uuid(),plan_payload||'{"rebuild":true}'); raise exception 'Rebuild accepted';
  exception when raise_exception then if sqlerrm<>'Invalid plan fields' then raise; end if; end;
  if (select jsonb_agg(to_jsonb(s) order by id) from public.shopping_items s) is distinct from baseline then raise exception 'Browser append touched groceries'; end if;
end $$;
reset role;
do $$ begin
  if exists(select 1 from public.gpt_action_requests where request_id in('99500000-0000-0000-0000-000000000021','99500000-0000-0000-0000-000000000031')) then raise exception 'Failed transaction retained request'; end if;
  if has_function_privilege('anon','public.owner_create_recipe(uuid,jsonb)','execute')
    or has_function_privilege('service_role','public.owner_append_plan(uuid,jsonb)','execute')
    or has_function_privilege('authenticated','public.claim_mutation_payload(uuid,text,jsonb)','execute')
    or has_table_privilege('authenticated','public.gpt_action_requests','select') then raise exception 'Capability boundary widened'; end if;
end $$;
-- Denial must occur BEFORE replay, even for a known completed ID.
delete from auth.sessions where id='99500000-0000-0000-0000-000000000011';
set local role authenticated;
do $$ declare claims jsonb; begin
  for claims in select value from jsonb_array_elements('[
    {"role":"authenticated","sub":"99500000-0000-0000-0000-000000000001","session_id":"99500000-0000-0000-0000-000000000011"},
    {"role":"authenticated","sub":"99500000-0000-0000-0000-000000000002","session_id":"99500000-0000-0000-0000-000000000012"},
    {"role":"authenticated","sub":"99500000-0000-0000-0000-000000000001"},
    {"role":"authenticated","sub":"99500000-0000-0000-0000-000000000001","session_id":"99500000-0000-0000-0000-000000000099"},
    {"role":"service_role"}]') loop
    perform set_config('request.jwt.claims',claims::text,true);
    begin perform public.owner_create_recipe('99500000-0000-0000-0000-000000000020','{}'); raise exception 'Unauthorized recipe replay'; exception when insufficient_privilege then null; end;
    begin perform public.owner_append_plan('99500000-0000-0000-0000-000000000030','{}'); raise exception 'Unauthorized plan replay'; exception when insufficient_privilege then null; end;
  end loop;
end $$;
reset role;
set local role anon;
do $$ begin
  begin perform public.owner_create_recipe(gen_random_uuid(),'{}'); raise exception 'Anonymous create'; exception when insufficient_privilege then null; end;
  begin perform public.owner_append_plan(gen_random_uuid(),'{}'); raise exception 'Anonymous append'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('test.owner.food',(select id::text from public.base_foods where name='Owner creation food'),true);
set local role service_role;
do $$ declare recipe_id uuid; payload jsonb; result jsonb; food uuid; begin
  -- Existing service routes retain their upsert/replace and auto-rebuild contract.
  food:=current_setting('test.owner.food')::uuid;
  payload:=jsonb_build_object('name','GPT compatibility recipe','servings',2,'ingredients',
    jsonb_build_array(jsonb_build_object('foodId',food,'quantity',180,'unit','g')));
  recipe_id:=(public.gpt_save_recipe(payload)->>'id')::uuid;
  result:=public.gpt_save_recipe(payload||jsonb_build_object('id',recipe_id,'name','GPT updated recipe'));
  if (result->>'id')::uuid<>recipe_id then raise exception 'GPT upsert changed'; end if;
  result:=public.gpt_save_plan('append',null,jsonb_build_array(jsonb_build_object('source','recipe','sourceId',recipe_id,
    'date',current_date+28,'slot','dinner','plannedServings',1,'scaleFactor',10)));
  if result->>'status'<>'added' or (result->>'entries')::integer<>1 or (result->>'generatedGroceries')::integer<1 then raise exception 'GPT auto rebuild changed'; end if;
  result:=public.gpt_save_plan('replaceWeek',current_date+28,'[]');
  if result->>'status'<>'replaced' or (result->>'entries')::integer<>0 then raise exception 'GPT replace changed'; end if;
  begin perform public.owner_create_recipe(gen_random_uuid(),'{}'); raise exception 'Service create access added'; exception when insufficient_privilege then null; end;
  begin perform public.owner_append_plan(gen_random_uuid(),'{}'); raise exception 'Service append access added'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.recipes where name='GPT updated recipe') or exists(
    select 1 from public.meal_plans p join public.recipes r on r.id=p.recipe where r.name='GPT updated recipe'
  ) then raise exception 'GPT upsert/replace persisted unexpected state'; end if;
end $$;
select 'PASS: atomic owner create/append, rollback, replay, scope, source groups, groceries';
rollback;
