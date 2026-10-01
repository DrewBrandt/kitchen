-- Narrow idempotent overloads. All new entry points stay uncallable until separately approved grants.

create function public.consume_inventory_lot(p_request_id uuid, p_lot uuid, p_quantity numeric, p_occurred_at timestamptz default now())
returns uuid language plpgsql security definer set search_path = '' as $$
declare prior jsonb; result uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior := public.claim_mutation_payload(p_request_id, 'consume_inventory_lot', jsonb_build_object('p_lot', p_lot, 'p_quantity', p_quantity, 'p_occurred_at', p_occurred_at));
  if prior is not null then return (prior #>> '{}')::uuid; end if;
  result := public.consume_inventory_lot(p_lot, p_quantity, p_occurred_at);
  perform public.gpt_complete_request(p_request_id, coalesce(to_jsonb(result), 'null'::jsonb));
  return result;
end;
$$;
revoke all on function public.consume_inventory_lot(uuid, uuid, numeric, timestamptz) from public, anon, authenticated, service_role;

create function public.consume_prepared_lot(p_request_id uuid, p_lot uuid, p_quantity numeric, p_occurred_at timestamptz default now())
returns uuid language plpgsql security definer set search_path = '' as $$
declare prior jsonb; result uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior := public.claim_mutation_payload(p_request_id, 'consume_prepared_lot', jsonb_build_object('p_lot', p_lot, 'p_quantity', p_quantity, 'p_occurred_at', p_occurred_at));
  if prior is not null then return (prior #>> '{}')::uuid; end if;
  result := public.consume_prepared_lot(p_lot, p_quantity, p_occurred_at);
  perform public.gpt_complete_request(p_request_id, coalesce(to_jsonb(result), 'null'::jsonb));
  return result;
end;
$$;
revoke all on function public.consume_prepared_lot(uuid, uuid, numeric, timestamptz) from public, anon, authenticated, service_role;

create function public.consume_planned_meals(p_request_id uuid, p_meal_plans uuid[], p_servings numeric[], p_occurred_at timestamptz default now())
returns uuid[] language plpgsql security definer set search_path = '' as $$
declare prior jsonb; result uuid[];
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior := public.claim_mutation_payload(p_request_id, 'consume_planned_meals', jsonb_build_object('p_meal_plans', p_meal_plans, 'p_servings', p_servings, 'p_occurred_at', p_occurred_at));
  if prior is not null then return array(select value::uuid from jsonb_array_elements_text(prior)); end if;
  result := public.consume_planned_meals(p_meal_plans, p_servings, p_occurred_at);
  perform public.gpt_complete_request(p_request_id, coalesce(to_jsonb(result), 'null'::jsonb));
  return result;
end;
$$;
revoke all on function public.consume_planned_meals(uuid, uuid[], numeric[], timestamptz) from public, anon, authenticated, service_role;

create function public.prepare_recipe(p_request_id uuid, p_recipe uuid, p_scale numeric default 1, p_servings numeric default null, p_location text default 'fridge', p_meal_plan uuid default null, p_eaten_servings numeric default 0, p_occurred_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare prior jsonb; result jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior := public.claim_mutation_payload(p_request_id, 'prepare_recipe', jsonb_build_object('p_recipe', p_recipe, 'p_scale', p_scale, 'p_servings', p_servings, 'p_location', p_location, 'p_meal_plan', p_meal_plan, 'p_eaten_servings', p_eaten_servings, 'p_occurred_at', p_occurred_at));
  if prior is not null then return prior; end if;
  result := public.prepare_recipe(p_recipe, p_scale, p_servings, p_location, p_meal_plan, p_eaten_servings, p_occurred_at);
  perform public.gpt_complete_request(p_request_id, coalesce(to_jsonb(result), 'null'::jsonb));
  return result;
end;
$$;
revoke all on function public.prepare_recipe(uuid, uuid, numeric, numeric, text, uuid, numeric, timestamptz) from public, anon, authenticated, service_role;

create function public.cook_recipes(p_request_id uuid, p_recipes uuid[])
returns uuid[] language plpgsql security definer set search_path = '' as $$
declare prior jsonb; result uuid[];
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior := public.claim_mutation_payload(p_request_id, 'cook_recipes', jsonb_build_object('p_recipes', p_recipes));
  if prior is not null then return array(select value::uuid from jsonb_array_elements_text(prior)); end if;
  result := public.cook_recipes(p_recipes);
  perform public.gpt_complete_request(p_request_id, coalesce(to_jsonb(result), 'null'::jsonb));
  return result;
end;
$$;
revoke all on function public.cook_recipes(uuid, uuid[]) from public, anon, authenticated, service_role;

create function public.set_inventory_lot_quantity(p_request_id uuid, p_lot uuid, p_remaining numeric, p_discard boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare prior jsonb; result uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior := public.claim_mutation_payload(p_request_id, 'set_inventory_lot_quantity', jsonb_build_object('p_lot', p_lot, 'p_remaining', p_remaining, 'p_discard', p_discard));
  if prior is not null then return (prior #>> '{}')::uuid; end if;
  result := public.set_inventory_lot_quantity(p_lot, p_remaining, p_discard);
  perform public.gpt_complete_request(p_request_id, coalesce(to_jsonb(result), 'null'::jsonb));
  return result;
end;
$$;
revoke all on function public.set_inventory_lot_quantity(uuid, uuid, numeric, boolean) from public, anon, authenticated, service_role;
