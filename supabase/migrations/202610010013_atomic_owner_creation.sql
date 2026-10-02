-- Atomic equivalents of the browser's existing owner CRUD. No table or GPT ACL changes.
-- Intentionally do not reuse GPT upsert/replace/rebuild paths: browser creation
-- permits empty ingredients and plan append never rebuilds shopping.
create function public.owner_create_recipe(p_request_id uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare prior jsonb; result jsonb; recipe_id uuid; item jsonb; servings numeric;
begin
  if auth.role() is distinct from 'authenticated' or not public.is_app_owner() then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' or exists (
    select 1 from jsonb_object_keys(p_payload) k where k <> all(array[
      'name','emoji','servings','instructions','source_url','prompt_for_feedback','ingredients'])
  ) then raise exception 'Invalid recipe fields'; end if;
  prior := public.claim_mutation_payload(p_request_id, 'owner_create_recipe', p_payload);
  if prior is not null then return prior; end if;
  servings := coalesce((p_payload->>'servings')::numeric, 1);
  if nullif(btrim(p_payload->>'name'),'') is null or servings <= 0
    or servings::text in ('NaN','Infinity','-Infinity') then raise exception 'Name and positive servings required'; end if;
  if jsonb_typeof(p_payload->'ingredients') is distinct from 'array' then raise exception 'Ingredients must be an array'; end if;
  insert into public.recipes(name,emoji,servings,instructions,source_url,prompt_for_feedback)
  values(p_payload->>'name',p_payload->>'emoji',servings,coalesce(p_payload->'instructions','[]'::jsonb),
    p_payload->>'source_url',coalesce((p_payload->>'prompt_for_feedback')::boolean,false)) returning id into recipe_id;
  for item in select value from jsonb_array_elements(p_payload->'ingredients') loop
    if jsonb_typeof(item) is distinct from 'object' or exists (
      select 1 from jsonb_object_keys(item) k where k <> all(array['ingredient','qty','unit','sort_order'])
    ) then raise exception 'Invalid ingredient fields'; end if;
    if (item->>'qty')::numeric::text in ('NaN','Infinity','-Infinity') then raise exception 'Invalid ingredient quantity'; end if;
    insert into public.recipe_ingredients(recipe,ingredient,qty,unit,sort_order)
    values(recipe_id,(item->>'ingredient')::uuid,(item->>'qty')::numeric,(item->>'unit')::uuid,
      coalesce((item->>'sort_order')::integer,0));
  end loop;
  result := jsonb_build_object('id',recipe_id);
  perform public.gpt_complete_request(p_request_id,result);
  return result;
end $$;
revoke all on function public.owner_create_recipe(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.owner_create_recipe(uuid,jsonb) to authenticated;

create function public.owner_append_plan(p_request_id uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  prior jsonb; result jsonb; intent text; portions numeric; scale numeric;
  source_group text; group_id text := gen_random_uuid()::text;
  source_row public.meal_plans%rowtype; plan_id uuid; plan_ids uuid[] := '{}'; dish jsonb;
begin
  if auth.role() is distinct from 'authenticated' or not public.is_app_owner() then
    raise exception 'Unauthorized' using errcode = '42501';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' or exists (
    select 1 from jsonb_object_keys(p_payload) k where k <> all(array[
      'intent','plan_date','daypart','planned_servings','scale_factor','recipe','product','inventory_lot','source_group_id','note','dishes'])
  ) then raise exception 'Invalid plan fields'; end if;
  prior := public.claim_mutation_payload(p_request_id,'owner_append_plan',p_payload);
  if prior is not null then return prior; end if;
  intent := coalesce(nullif(p_payload->>'intent',''),'prepare');
  if p_payload ? 'dishes' then
    if intent <> 'prepare' or jsonb_typeof(p_payload->'dishes') is distinct from 'array' then raise exception 'Choose recipe dishes'; end if;
    if jsonb_array_length(p_payload->'dishes')=0 then raise exception 'Choose at least one dish'; end if;
    if exists(select 1 from jsonb_object_keys(p_payload) k where k not in('intent','plan_date','daypart','note','dishes')) then raise exception 'Use per-dish quantities and sources'; end if;
    for dish in select value from jsonb_array_elements(p_payload->'dishes') loop
      if jsonb_typeof(dish) is distinct from 'object' then raise exception 'Invalid dish'; end if;
      if exists(select 1 from jsonb_object_keys(dish) k where k not in('recipe','scale_factor','planned_servings'))
        or nullif(dish->>'recipe','') is null then raise exception 'Choose one recipe per dish'; end if;
      scale:=(dish->>'scale_factor')::numeric; portions:=(dish->>'planned_servings')::numeric;
      if scale is null or portions is null or scale<=0 or portions<=0
        or scale::text in('NaN','Infinity','-Infinity') or portions::text in('NaN','Infinity','-Infinity') then raise exception 'Servings and scale must be positive'; end if;
      insert into public.meal_plans(recipe,plan_date,daypart,scale_factor,status,group_id,intent,note)
      values((dish->>'recipe')::uuid,(p_payload->>'plan_date')::date,(p_payload->>'daypart')::public.daypart,
        scale,'planned',group_id,'prepare',p_payload->>'note') returning id into plan_id;
      update public.planned_consumptions set servings=portions where meal_plan=plan_id;
      if not found then raise exception 'Missing planned portions'; end if;
      plan_ids:=array_append(plan_ids,plan_id);
    end loop;
    result:=jsonb_build_object('planIds',to_jsonb(plan_ids));
    perform public.gpt_complete_request(p_request_id,result); return result;
  end if;

  portions := coalesce((p_payload->>'planned_servings')::numeric,1);
  scale := coalesce((p_payload->>'scale_factor')::numeric,1);
  if portions <= 0 or scale <= 0 or portions::text in ('NaN','Infinity','-Infinity')
    or scale::text in ('NaN','Infinity','-Infinity') then raise exception 'Servings and scale must be positive'; end if;
  if intent = 'leftover' then
    if num_nonnulls(nullif(p_payload->>'recipe',''),nullif(p_payload->>'product',''),nullif(p_payload->>'inventory_lot','')) <> 0 then
      raise exception 'Choose only a source preparation group'; end if;
    source_group := nullif(p_payload->>'source_group_id','');
    if source_group is null then raise exception 'Choose a source preparation group'; end if;
    -- Same group-first, exact-ID fallback as the browser. Lock the copied rows
    -- against deletion/change until every linked component and portion commits.
    for source_row in select p.* from public.meal_plans p
      where (p.group_id=source_group or (not exists(select 1 from public.meal_plans g where g.group_id=source_group) and p.id::text=source_group))
        and p.intent='prepare' and p.recipe is not null order by p.id for share
    loop
      insert into public.meal_plans(plan_date,daypart,meal,recipe,scale_factor,status,name,emoji,group_id,
        leftover_of_group_id,source_meal_plan,intent,preparation_tasks,note)
      values((p_payload->>'plan_date')::date,(p_payload->>'daypart')::public.daypart,source_row.meal,source_row.recipe,
        source_row.scale_factor,'planned',source_row.name,source_row.emoji,group_id,source_group,source_row.id,'leftover','[]',p_payload->>'note')
      returning id into plan_id;
      plan_ids := array_append(plan_ids,plan_id);
    end loop;
    if cardinality(plan_ids)=0 then raise exception 'Choose a recipe preparation that will provide leftovers'; end if;
  elsif intent='consume' then
    if nullif(p_payload->>'recipe','') is not null or nullif(p_payload->>'source_group_id','') is not null
      or num_nonnulls(nullif(p_payload->>'product',''),nullif(p_payload->>'inventory_lot',''))<>1 then
      raise exception 'Choose a pantry product or one exact lot'; end if;
    insert into public.meal_plans(product,inventory_lot,consume_from_inventory,plan_date,daypart,scale_factor,status,group_id,intent,note)
    values(nullif(p_payload->>'product','')::uuid,nullif(p_payload->>'inventory_lot','')::uuid,true,
      (p_payload->>'plan_date')::date,(p_payload->>'daypart')::public.daypart,1,'planned',group_id,'consume',p_payload->>'note')
    returning id into plan_id;
    plan_ids := array_append(plan_ids,plan_id);
  elsif intent='prepare' then
    if nullif(p_payload->>'recipe','') is null
      or num_nonnulls(nullif(p_payload->>'product',''),nullif(p_payload->>'inventory_lot',''),nullif(p_payload->>'source_group_id',''))<>0 then
      raise exception 'Choose one recipe'; end if;
    insert into public.meal_plans(recipe,plan_date,daypart,scale_factor,status,group_id,intent,note)
    values((p_payload->>'recipe')::uuid,(p_payload->>'plan_date')::date,(p_payload->>'daypart')::public.daypart,
      scale,'planned',group_id,'prepare',p_payload->>'note') returning id into plan_id;
    plan_ids := array_append(plan_ids,plan_id);
  else raise exception 'Invalid plan intent'; end if;
  update public.planned_consumptions set servings=portions where meal_plan=any(plan_ids);
  if (select count(*) from public.planned_consumptions where meal_plan=any(plan_ids))<>cardinality(plan_ids) then
    raise exception 'Missing planned portions'; end if;
  result := jsonb_build_object('planIds',to_jsonb(plan_ids));
  perform public.gpt_complete_request(p_request_id,result);
  return result;
end $$;
revoke all on function public.owner_append_plan(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.owner_append_plan(uuid,jsonb) to authenticated;
