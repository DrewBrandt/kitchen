-- The September 1 crispy-roasted-potato batch yielded two servings, but the
-- historical repair recorded one. One serving was eaten, so one remains.
do $$
declare
  potato_lot constant uuid := '147c26f7-c381-4825-bcf1-63fe26118c92';
  potato_prep constant uuid := 'cdea109f-0368-482e-81d7-bc5efe26191e';
  eaten_event public.inventory_events%rowtype;
begin
  if exists (select 1 from public.inventory_lots where id = potato_lot) then
    if exists (
      select 1
      from public.inventory_lots lot
      join public.preps prep on prep.id = lot.prep
      where lot.id = potato_lot
        and lot.prep = potato_prep
        and lot.initial_qty = 2
        and lot.remaining_qty = 1
        and prep.actual_yield_qty = 2
        and prep.voided_at is null
    ) then
      null;
    elsif not exists (
      select 1
      from public.inventory_lots lot
      join public.preps prep on prep.id = lot.prep
      where lot.id = potato_lot
        and lot.prep = potato_prep
        and lot.initial_qty = 1
        and lot.remaining_qty = 0
        and prep.actual_yield_qty = 1
        and prep.voided_at is null
    ) then
      raise exception 'Crispy roasted potato batch is not in the expected pre-correction state';
    else
      select * into strict eaten_event
      from public.inventory_events
      where lot = potato_lot
        and reason = 'eaten'
        and quantity_delta = -1
        and voided_at is null;

      -- Remove and restore the immutable consumption event around the baseline
      -- correction. Its triggers derive remaining_qty as initial + event deltas.
      delete from public.inventory_events where id = eaten_event.id;

      update public.inventory_lots
      set initial_qty = 2,
          note = concat_ws(' ', note, 'Corrected initial yield from one serving to two; one serving remains after the existing consumption.')
      where id = potato_lot;

      insert into public.inventory_events(
        id, lot, quantity_delta, reason, occurred_at, cook_session, prep,
        food_log, note, voided_at, created_at
      ) values (
        eaten_event.id, eaten_event.lot, eaten_event.quantity_delta,
        eaten_event.reason, eaten_event.occurred_at, eaten_event.cook_session,
        eaten_event.prep, eaten_event.food_log, eaten_event.note,
        eaten_event.voided_at, eaten_event.created_at
      );

      update public.preps
      set actual_yield_qty = 2,
          note = concat_ws(' ', note, 'Corrected actual yield from one serving to two; one serving was eaten and one remains.')
      where id = potato_prep;
    end if;

    if not exists (
      select 1
      from public.inventory_lots lot
      left join public.inventory_events event
        on event.lot = lot.id
       and event.voided_at is null
      where lot.id = potato_lot
      group by lot.id, lot.initial_qty, lot.remaining_qty
      having lot.remaining_qty = lot.initial_qty + coalesce(sum(event.quantity_delta), 0)
    ) then
      raise exception 'Crispy roasted potato inventory history is inconsistent after yield correction';
    end if;
  end if;
end;
$$;
