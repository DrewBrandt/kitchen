-- Synthetic fixtures only. Run after migration 001; always rollback.
begin;
do $$
declare test_request_id uuid := gen_random_uuid(); result jsonb; repeated jsonb; entry public.food_logs%rowtype;
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin
    perform public.claim_mutation_payload(test_request_id, 'QA', '{}'::jsonb);
    raise exception 'Unauthorized claim unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  if exists(select 1 from public.gpt_action_requests where gpt_action_requests.request_id = test_request_id) then
    raise exception 'Unauthorized request changed the ledger';
  end if;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  result := public.log_manual_consumption('QA rollback meal', 'half bowl', '2026-10-01T12:00:00Z', 'dateOnly', null, null, '[]', 'gift', null, 0, 'other', false, 'unknown value; paid zero', null, test_request_id, null);
  repeated := public.log_manual_consumption('QA rollback meal', 'half bowl', '2026-10-01T12:00:00Z', 'dateOnly', null, null, '[]', 'gift', null, 0, 'other', false, 'unknown value; paid zero', null, test_request_id, null);
  if result is distinct from repeated then raise exception 'Retry did not return original result'; end if;
  select * into entry from public.food_logs where id = (result ->> 'id')::uuid;
  if entry.kcal is not null or entry.cost is not null or entry.out_of_pocket_cost <> 0 or entry.nutrition_status <> 'unknown' then
    raise exception 'Unknown value/nutrition or explicit paid zero was lost';
  end if;
  begin
    perform public.log_manual_consumption('QA changed input', 'half bowl', '2026-10-01T12:00:00Z', 'dateOnly', null, null, '[]', 'gift', null, 0, 'other', false, 'unknown value; paid zero', null, test_request_id, null);
    raise exception 'Changed retry unexpectedly succeeded';
  exception when others then
    if sqlerrm not like 'This request ID belongs%' then raise; end if;
  end;
  perform public.void_food_log(entry.id);
  if not exists(select 1 from public.food_logs where id = entry.id and voided_at is not null) then raise exception 'Void did not preserve audit row'; end if;
  perform public.restore_food_log(entry.id);
  if not exists(select 1 from public.food_logs where id = entry.id and voided_at is null) then raise exception 'Restore failed'; end if;
  if has_function_privilege('authenticated', 'public.claim_mutation_payload(uuid,text,jsonb)', 'execute') or has_function_privilege('anon', 'public.claim_mutation_payload(uuid,text,jsonb)', 'execute') then
    raise exception 'Private retry helper was exposed';
  end if;
end;
$$;
rollback;
