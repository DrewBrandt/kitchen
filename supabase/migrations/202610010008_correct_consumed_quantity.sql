-- Candidate action: deliberately no role receives EXECUTE here.
-- Quantities are canonical g / fl oz / count for raw lots, servings for prepared lots.
create function public.correct_consumed_quantity(
  p_request_id uuid, p_food_log uuid, p_expected_quantity numeric, p_quantity numeric
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  original public.food_logs%rowtype;
  replacement public.food_logs%rowtype;
  source_event public.inventory_events%rowtype;
  source_lot public.inventory_lots%rowtype;
  prior jsonb; result jsonb; before_plans jsonb;
  ratio numeric; unit_label text; new_event uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if p_request_id is null or p_food_log is null then raise exception 'Request and consumption IDs are required'; end if;
  if p_expected_quantity is null or p_expected_quantity::text in ('NaN','Infinity','-Infinity') or p_expected_quantity <= 0
     or p_quantity is null or p_quantity::text in ('NaN','Infinity','-Infinity') or p_quantity <= 0 then
    raise exception 'Quantities must be finite and positive; remove the event to record none';
  end if;
  prior := public.claim_mutation_payload(p_request_id, 'correct_consumed_quantity',
    jsonb_build_object('foodLogId',p_food_log,'expectedQuantity',p_expected_quantity,'quantity',p_quantity));
  if prior is not null then return prior; end if;

  select * into original from public.food_logs where id=p_food_log for update;
  if not found then raise exception 'Consumption event does not exist'; end if;
  if original.voided_at is not null or exists(select 1 from public.food_log_replacements where original_log=p_food_log) then
    raise exception 'This consumption was removed or replaced; refresh before correcting it';
  end if;
  if original.kind not in ('inventory','prepared') or exists(select 1 from public.inventory_lots where acquisition_food_log=p_food_log) then
    raise exception 'Only an existing single-lot consumption can be corrected; purchase-linked entries are unsupported';
  end if;
  perform 1 from public.inventory_events where food_log=p_food_log order by id for update;
  if (select count(*) from public.inventory_events where food_log=p_food_log) <> 1 then
    raise exception 'Correction requires exactly one inventory event; multi-lot or ambiguous entries are unsupported';
  end if;
  select * into source_event from public.inventory_events where food_log=p_food_log;
  if source_event.voided_at is not null or source_event.reason <> 'eaten' or source_event.quantity_delta >= 0
     or source_event.prep is not null then raise exception 'Correction requires one active eaten event'; end if;
  if -source_event.quantity_delta <> p_expected_quantity then raise exception 'Consumed quantity changed; refresh before correcting it'; end if;
  select * into source_lot from public.inventory_lots where id=source_event.lot for update;
  if not found then raise exception 'Source lot does not exist'; end if;
  if (original.kind='prepared' and source_lot.prep is null)
     or (original.kind='inventory' and (source_lot.prep is not null or source_lot.product is null or source_lot.product is distinct from original.product))
     or (original.kind='prepared' and not exists(select 1 from public.preps where id=source_lot.prep and recipe is not distinct from original.recipe))
     or (source_lot.prep is not null and not exists(select 1 from public.preps where id=source_lot.prep and voided_at is null)) then
    raise exception 'Source provenance is inconsistent or preparation was undone';
  end if;
  if p_quantity > source_lot.remaining_qty + p_expected_quantity then raise exception 'Insufficient stock in the original lot'; end if;
  if p_quantity = p_expected_quantity then
    result := jsonb_build_object('status','unchanged','id',p_food_log,'originalId',p_food_log,'lotId',source_lot.id,'quantity',p_quantity);
    perform public.gpt_complete_request(p_request_id,result);
    return result;
  end if;
  perform 1 from public.planned_consumptions where food_log=p_food_log order by id for update;
  select coalesce(jsonb_agg(to_jsonb(pc)),'[]'::jsonb) into before_plans from public.planned_consumptions pc where food_log=p_food_log;
  ratio := p_quantity / p_expected_quantity;
  if source_lot.prep is not null then unit_label := 'servings';
  else
    select case food.measure_style when 'weight' then 'g' when 'volume' then 'fl oz' else 'count' end into unit_label
    from public.products product join public.base_foods food on food.id=product.food where product.id=source_lot.product;
  end if;

  -- Preserve original rows, and let the ledger trigger return stock before the new deduction.
  update public.food_logs set voided_at=now() where id=p_food_log;
  update public.inventory_events set voided_at=now() where id=source_event.id;
  insert into public.food_logs(
    label,kind,product,recipe,servings,portion_label,occurred_at,time_precision,note,
    kcal,protein_g,carbs_g,fat_g,fiber_g,sugar_g,sodium_mg,
    nutrition_is_estimated,nutrition_source,nutrition_estimate,components,
    cost,cost_is_estimated,cost_source,acquisition_type,total_price,out_of_pocket_cost,paid_by,price_as_of
  ) values (
    original.label,original.kind,original.product,original.recipe,original.servings*ratio,p_quantity::text||' '||unit_label,original.occurred_at,original.time_precision,original.note,
    original.kcal*ratio,original.protein_g*ratio,original.carbs_g*ratio,original.fat_g*ratio,original.fiber_g*ratio,original.sugar_g*ratio,original.sodium_mg*ratio,
    original.nutrition_is_estimated,original.nutrition_source,original.nutrition_estimate,original.components,
    original.cost*ratio,original.cost_is_estimated,original.cost_source,original.acquisition_type,original.total_price*ratio,original.out_of_pocket_cost*ratio,original.paid_by,original.price_as_of
  ) returning * into replacement;
  insert into public.inventory_events(lot,quantity_delta,reason,food_log,occurred_at,note,cook_session)
  values(source_lot.id,-p_quantity,'eaten',replacement.id,source_event.occurred_at,source_event.note,source_event.cook_session)
  returning id into new_event;
  update public.planned_consumptions set food_log=replacement.id where food_log=p_food_log;
  insert into public.food_log_replacements(original_log,replacement_log) values(p_food_log,replacement.id);
  insert into public.record_edits(resource,record_id,before_state,after_state)
  values('consumption',p_food_log,
    jsonb_build_object('consumption',to_jsonb(original),'event',to_jsonb(source_event),'plannedConsumptions',before_plans),
    jsonb_build_object('consumption',to_jsonb(replacement),'eventId',new_event,'quantity',p_quantity,'requestId',p_request_id,'reason','Correct consumed quantity'));
  result := jsonb_build_object('status','corrected','id',replacement.id,'originalId',p_food_log,'lotId',source_lot.id,'quantity',p_quantity,'unit',unit_label);
  perform public.gpt_complete_request(p_request_id,result);
  return result;
end;
$$;
revoke all on function public.correct_consumed_quantity(uuid,uuid,numeric,numeric) from public, anon, authenticated, service_role;
