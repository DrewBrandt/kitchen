-- Disposable fixtures; call POST's real service-only RPC without new grants.
begin;
do $$ begin if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if; end $$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
create function pg_temp.post_recipe(payload jsonb) returns jsonb language plpgsql as $$
declare result jsonb; begin
  execute 'set local role service_role';
  result:=public.gpt_save_recipe(payload);
  execute 'reset role'; return result;
exception when others then execute 'reset role'; raise;
end $$;
do $$ declare
  u uuid; f uuid:=gen_random_uuid(); other_food uuid:=gen_random_uuid(); product uuid:=gen_random_uuid();
  r uuid:=gen_random_uuid(); generated uuid; a uuid; b uuid; response jsonb; payload jsonb; before_state jsonb;
  rejected boolean; bad jsonb; audits bigint;
begin
 select id into strict u from public.measure_conversions where short_name='g';
 insert into public.base_foods(id,name,measure_style,display_unit) values(f,'POST rice','weight',u),(other_food,'POST other food','weight',u);
 insert into public.products(id,food,name,package_qty_base,package_unit) values(product,f,'POST pinned rice',100,u);
 payload:=jsonb_build_object('id',r,'name','POST preservation','servings',2,'emoji','Rice','sourceNote','Provenance',
  'promptForFeedback',false,'instructions',jsonb_build_array('Original method'),'nutrition',jsonb_build_object('calories',400),
  'ingredients',jsonb_build_array(jsonb_build_object('foodId',f,'quantity',10,'unit',u,'note','Sauce')));
 response:=pg_temp.post_recipe(payload);
 if response<>jsonb_build_object('status','saved','id',r) then raise exception 'Supplied new ID creation response'; end if;
 select id into strict a from public.recipe_ingredients where recipe=r;
 update public.recipe_ingredients set pinned_product=product where id=a;
 payload:=jsonb_build_object('id',r,'name','POST preservation edited','servings',4,'ignoredLegacyField','ignored',
  'ingredients',jsonb_build_array(jsonb_build_object('foodId',f,'quantity',20,'unit',u)));
 response:=pg_temp.post_recipe(payload);
 if response<>jsonb_build_object('status','saved','id',r)
  or not exists(select 1 from public.recipe_ingredients where id=a and recipe=r and qty=20 and note='Sauce' and pinned_product=product and sort_order=0)
  or not exists(select 1 from public.recipes where id=r and source_note='Provenance' and emoji='Rice' and not prompt_for_feedback
    and override_basis_qty=2 and override_kcal=400 and instructions='["Original method"]' and servings=4)
 then raise exception 'Existing-ID update lost metadata, identity, defaults or response'; end if;
 -- Supplying note/null metadata is intentional; omitted fields above were retained.
 response:=pg_temp.post_recipe(payload||jsonb_build_object('sourceNote',null,'nutrition',null,'ingredients',
  jsonb_build_array(jsonb_build_object('foodId',f,'quantity',21,'unit',u,'note',null))));
 if not exists(select 1 from public.recipe_ingredients where id=a and note is null and pinned_product=product and qty=21)
  or not exists(select 1 from public.recipes where id=r and source_note is null and override_basis_qty is null and override_kcal is null)
 then raise exception 'Explicit null clearing failed'; end if;
 response:=pg_temp.post_recipe(payload||jsonb_build_object('nutrition',jsonb_build_object('basisQuantity',99,'calories',800)));
 if not exists(select 1 from public.recipes where id=r and override_basis_qty=4 and override_kcal=800) then raise exception 'Batch nutrition basis changed'; end if;
 -- Adding a different food retains old row identity and POST's all-zero default order.
 payload:=payload||jsonb_build_object('ingredients',jsonb_build_array(
   jsonb_build_object('foodId',f,'quantity',20,'unit',u),jsonb_build_object('foodId',other_food,'quantity',5,'unit',u)));
 perform pg_temp.post_recipe(payload);
 select id into strict b from public.recipe_ingredients where recipe=r and ingredient=other_food;
 if not exists(select 1 from public.recipe_ingredients where id=a) or exists(select 1 from public.recipe_ingredients where recipe=r and sort_order<>0)
 then raise exception 'Addition replaced old row or changed POST default order'; end if;
 select jsonb_build_object('recipe',(select to_jsonb(x) from public.recipes x where id=r),'rows',
  (select jsonb_agg(to_jsonb(x) order by id) from public.recipe_ingredients x where recipe=r)) into before_state;
 audits:=(select count(*) from public.record_edits);
 for bad in select value from jsonb_array_elements(jsonb_build_array(
  jsonb_build_array(jsonb_build_object('foodId',f,'quantity',25,'unit',u)),
  jsonb_build_array(jsonb_build_object('foodId',f,'quantity',25,'unit','kg'),jsonb_build_object('foodId',other_food,'quantity',5,'unit',u)),
  jsonb_build_array(jsonb_build_object('id',null,'foodId',f,'quantity',25,'unit',u),jsonb_build_object('foodId',other_food,'quantity',5,'unit',u))
 )) loop
  rejected:=false;
  begin perform pg_temp.post_recipe(payload||jsonb_build_object('name','Must rollback','ingredients',bad));
  exception when raise_exception then
   if sqlerrm<>'Removing or replacing ingredients requires PATCH with ingredient IDs' then raise; end if;
   rejected:=true;
  end;
  if not rejected or (select jsonb_build_object('recipe',(select to_jsonb(x) from public.recipes x where id=r),'rows',
    (select jsonb_agg(to_jsonb(x) order by id) from public.recipe_ingredients x where recipe=r))) is distinct from before_state
    or (select count(*) from public.record_edits)<>audits then raise exception 'Destructive update did not roll back fully'; end if;
 end loop;
 -- Ambiguous duplicate legacy rows must reject before losing either pin/note.
 insert into public.recipe_ingredients(recipe,ingredient,qty,unit,sort_order,note) values(r,f,20,u,0,'Duplicate');
 rejected:=false;
 begin perform pg_temp.post_recipe(payload);
 exception when raise_exception then
  if sqlerrm<>'Ingredient identity is unclear; use PATCH with ingredient IDs' then raise; end if;
  rejected:=true;
 end;
 if not rejected or (select count(*) from public.recipe_ingredients where recipe=r)<>3 or
   not exists(select 1 from public.recipe_ingredients where id=a and pinned_product=product) then raise exception 'Ambiguous identity not protected'; end if;
 -- New generated IDs and supplied IDs still use the original creation behavior.
 response:=pg_temp.post_recipe(jsonb_build_object('name','Generated POST recipe','servings',2,'ingredients',
  jsonb_build_array(jsonb_build_object('foodId',f,'quantity',1,'unit',u),jsonb_build_object('foodId',other_food,'quantity',2,'unit',u))));
 generated:=(response->>'id')::uuid;
 if response<>jsonb_build_object('status','saved','id',generated) or generated=r
  or (select count(*) from public.recipe_ingredients where recipe=generated and sort_order=0)<>2
  or not exists(select 1 from public.recipes where id=generated and prompt_for_feedback and instructions='[]' and source_note is null and override_basis_qty is null)
 then raise exception 'Generated creation/defaults changed'; end if;
 -- Bad creation is still all-or-nothing, including a caller-supplied new ID.
 rejected:=false;
 begin perform pg_temp.post_recipe(jsonb_build_object('id',gen_random_uuid(),'name','Must not survive POST','servings',2,'ingredients',
  jsonb_build_array(jsonb_build_object('foodId',f,'quantity',1,'unit',u),jsonb_build_object('foodId',other_food,'quantity',1,'unit','no-such-unit'))));
 exception when raise_exception then
  if sqlerrm not like 'Unknown unit:%' then raise; end if;
  rejected:=true;
 end;
 if not rejected or exists(select 1 from public.recipes where name='Must not survive POST') then raise exception 'Creation rollback failed'; end if;
 -- Existing unauthorized roles stay unable to execute POST.
 if has_function_privilege('authenticated','public.gpt_save_recipe(jsonb)','EXECUTE')
  or has_function_privilege('anon','public.gpt_save_recipe(jsonb)','EXECUTE')
  or not has_function_privilege('service_role','public.gpt_save_recipe(jsonb)','EXECUTE') then raise exception 'POST ACL changed'; end if;
end $$;
rollback;
select 'PASS: recipe POST creation, metadata/identity preservation, safe narrowing, rollback, response and ACL';
