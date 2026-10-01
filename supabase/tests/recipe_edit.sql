-- Disposable database only: verifies real owner role, transaction rollback and omitted fields.
begin;
do $$ declare owner_email text; begin
  if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict owner_email;
  insert into auth.users(id,email,email_confirmed_at) values('99600000-0000-0000-0000-000000000001',owner_email,now());
  insert into auth.sessions(id,user_id) values('99600000-0000-0000-0000-000000000011','99600000-0000-0000-0000-000000000001');
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99600000-0000-0000-0000-000000000001","session_id":"99600000-0000-0000-0000-000000000011"}',true);
set local role authenticated;
do $$ declare f uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); u uuid; before_state jsonb; after_state jsonb; edits bigint; begin
  select id into strict u from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit) values(f,'Atomic recipe food','weight',u);
  insert into public.recipes(id,name,servings,instructions,source_note,portions,preparation_rules,override_basis_qty,override_kcal)
  values(r,'Original',2,'["Original step"]','Keep source','[{"name":"portion"}]','[]',2,100);
  insert into public.recipe_ingredients(recipe,ingredient,qty,unit) values(r,f,10,u);
  select jsonb_build_object('recipe',to_jsonb(rec),'ingredients',(select jsonb_agg(to_jsonb(i)) from public.recipe_ingredients i where recipe=r)) into before_state from public.recipes rec where id=r;
  select count(*) into edits from public.record_edits where record_id=r;
  begin
    perform public.gpt_update_recipe(r,jsonb_build_object('name','Must rollback','ingredients',jsonb_build_array(
      jsonb_build_object('foodId',f,'quantity',20,'unit','g'),jsonb_build_object('food','Nonexistent ingredient','quantity',1,'unit','g'))));
    raise exception 'Expected ingredient rejection';
  exception when raise_exception then
    if sqlerrm not like 'Unknown ingredient:%' then raise; end if;
  end;
  select jsonb_build_object('recipe',to_jsonb(rec),'ingredients',(select jsonb_agg(to_jsonb(i)) from public.recipe_ingredients i where recipe=r)) into after_state from public.recipes rec where id=r;
  if before_state is distinct from after_state or (select count(*) from public.record_edits where record_id=r)<>edits then raise exception 'Invalid ingredient partially saved recipe'; end if;
  perform public.gpt_update_recipe(r,jsonb_build_object('name','Updated','ingredients',jsonb_build_array(jsonb_build_object('foodId',f,'quantity',20,'unit',u))));
  if not exists(select 1 from public.recipes where id=r and name='Updated' and source_note='Keep source' and portions='[{"name":"portion"}]'::jsonb and override_kcal=100 and override_basis_qty=2) then raise exception 'Omitted fields lost'; end if;
  if (select qty from public.recipe_ingredients where recipe=r)<>20 or (select count(*) from public.record_edits where record_id=r)<>edits+1 then raise exception 'Successful edit missing ingredients or audit'; end if;
  perform set_config('request.jwt.claims','{"role":"authenticated","sub":"99600000-0000-0000-0000-000000000001"}',true);
  begin
    perform public.gpt_update_recipe(r,'{"name":"Unauthorized"}');
    raise exception 'Missing session was accepted';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99600000-0000-0000-0000-000000000001","session_id":"99600000-0000-0000-0000-000000000011"}',true);
do $$ declare
  f uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); u uuid; prod uuid:=gen_random_uuid();
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); payload jsonb;
  before_ingredients jsonb;
begin
  select id into strict u from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit) values(f,'Duplicate recipe food','weight',u);
  insert into public.products(id,food,name,package_qty_base,package_unit) values(prod,f,'Pinned ingredient product',100,u);
  insert into public.recipes(id,name,servings,override_basis_qty,override_kcal) values(r,'Four servings',4,1,200);
  insert into public.recipe_ingredients(id,recipe,ingredient,qty,unit,sort_order,note,pinned_product) values
    (a,r,f,10,u,0,'First duplicate',prod),(b,r,f,20,u,1,'Different amount',null),(c,r,f,10,u,2,'Second duplicate',prod);
  select jsonb_agg(to_jsonb(i) order by sort_order,id) into before_ingredients from public.recipe_ingredients i where recipe=r;
  payload:=jsonb_build_array(jsonb_build_object('foodId',f,'quantity',10,'unit',u,'sortOrder',0),
    jsonb_build_object('foodId',f,'quantity',20,'unit',u,'sortOrder',1),jsonb_build_object('foodId',f,'quantity',10,'unit',u,'sortOrder',2));
  perform public.gpt_update_recipe(r,jsonb_build_object('name','Rename only','servings',4,'ingredients',payload));
  if (select jsonb_agg(to_jsonb(i) order by sort_order,id) from public.recipe_ingredients i where recipe=r) is distinct from before_ingredients then raise exception 'Rename lost ingredient identity or metadata'; end if;
  if not exists(select 1 from public.recipes where id=r and servings=4 and override_basis_qty=1 and override_kcal=200) then raise exception 'Rename rescaled unequal nutrition basis'; end if;
  -- Yield-only edits preserve recorded per-serving overrides (200 / 1 = 200).
  perform public.gpt_update_recipe(r,'{"servings":8}');
  if not exists(select 1 from public.recipes where id=r and servings=8 and override_basis_qty=1 and override_kcal=200) then raise exception 'Yield edit rescaled omitted nutrition'; end if;
  -- First row changes quantity; unchanged duplicates must be reserved before fallback.
  payload:=jsonb_build_array(jsonb_build_object('foodId',f,'quantity',30,'unit',u,'sortOrder',0),
    jsonb_build_object('foodId',f,'quantity',20,'unit',u,'sortOrder',1),jsonb_build_object('foodId',f,'quantity',10,'unit',u,'sortOrder',2));
  perform public.gpt_update_recipe(r,jsonb_build_object('ingredients',payload));
  if (select count(*) from public.recipe_ingredients where recipe=r)<>3 or
     (select count(*) from public.recipe_ingredients where id in(a,b,c))<>3 or
     not exists(select 1 from public.recipe_ingredients where id=a and qty=30 and note='First duplicate' and pinned_product=prod) or
     not exists(select 1 from public.recipe_ingredients where id=b and qty=20 and note='Different amount') or
     not exists(select 1 from public.recipe_ingredients where id=c and qty=10 and note='Second duplicate' and pinned_product=prod) then raise exception 'Quantity edit lost duplicate metadata'; end if;
  perform public.gpt_update_recipe(r,'{"nutrition":{"calories":800}}');
  if not exists(select 1 from public.recipes where id=r and override_basis_qty=8 and override_kcal=800) then raise exception 'Explicit nutrition no longer uses batch yield'; end if;
  perform public.gpt_update_recipe(r,'{"nutrition":null}');
  if not exists(select 1 from public.recipes where id=r and override_basis_qty is null and override_kcal is null) then raise exception 'Explicit nutrition clear failed'; end if;
  if not has_function_privilege('authenticated','public.gpt_update_recipe(uuid,jsonb)','EXECUTE') or has_function_privilege('anon','public.gpt_update_recipe(uuid,jsonb)','EXECUTE') or not has_function_privilege('service_role','public.gpt_update_recipe(uuid,jsonb)','EXECUTE') then raise exception 'Recipe edit ACL changed'; end if;
end $$;
rollback;
select 'PASS: atomic recipe edit, invalid ingredient rollback, preserved omitted fields, missing-session denial' as result;
