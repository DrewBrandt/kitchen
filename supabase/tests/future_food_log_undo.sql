-- Synthetic owner, real RPCs and stock triggers; rolls back all fixtures.
begin;
do $$ declare email text; begin
  if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict email;
  insert into auth.users(id,email,email_confirmed_at) values('98600000-0000-0000-0000-000000000001',email,now());
  insert into auth.sessions(id,user_id) values('98600000-0000-0000-0000-000000000011','98600000-0000-0000-0000-000000000001');
end $$;

select set_config('request.jwt.claims','{"role":"authenticated","sub":"98600000-0000-0000-0000-000000000001","session_id":"98600000-0000-0000-0000-000000000011"}',true);
set local role authenticated;
do $$ declare
  u uuid; f uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); raw uuid:=gen_random_uuid();
  log_id uuid; other_log uuid; event_time timestamptz; case_name text;
  -- Choose a synthetic fixed owner-zone offset where transaction time is about 06:30.
  -- This makes the same-day noon case deterministic at every test-run time.
  owner_offset interval := interval '6 hours 30 minutes' - ((now() at time zone 'UTC') - date_trunc('day',now() at time zone 'UTC'));
  local_morning timestamp; date_only_noon timestamptz;
  error_message text; rejected boolean;
begin
  local_morning:=now() at time zone owner_offset;
  date_only_noon:=(date_trunc('day',local_morning)+interval '12 hours') at time zone owner_offset;
  if extract(hour from local_morning)<>6 or date_only_noon<=now()
    or (date_only_noon at time zone owner_offset)::date<>local_morning::date then
    raise exception 'Invalid same-day before-noon fixture'; end if;
  select id into strict u from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit) values(f,'Undo audit food','weight',u);
  insert into public.products(id,food,name,package_qty_base,package_unit) values(p,f,'Undo audit product',100,u);
  insert into public.inventory_lots(id,product,initial_qty,remaining_qty,location) values(raw,p,100,100,'pantry');
  for case_name,event_time in select * from (values
    ('future',now()+interval '1 day'),('dateOnly',date_only_noon),('past',now()-interval '1 day')
  ) as cases(label,occurred_at) loop
    log_id:=public.consume_inventory_lot(gen_random_uuid(),raw,10,event_time);
    if case_name='dateOnly' then update public.food_logs set time_precision='dateOnly' where id=log_id; end if;
    if (select remaining_qty from public.inventory_lots where id=raw)<>90 then raise exception '%: initial stock',case_name; end if;
    perform public.void_food_log(log_id);
    if (select remaining_qty from public.inventory_lots where id=raw)<>100
      or not exists(select 1 from public.food_logs where id=log_id and occurred_at=event_time and voided_at=now()) then
      raise exception '%: void must restore stock with unchanged event time and actual void time',case_name; end if;
    other_log:=public.consume_inventory_lot(gen_random_uuid(),raw,95,now());
    rejected:=false;
    begin perform public.restore_food_log(log_id);
    exception when raise_exception then
      get stacked diagnostics error_message=message_text;
      if error_message not like 'Inventory event would make lot % negative' then raise; end if;
      rejected:=true;
    end;
    if not rejected or (select remaining_qty from public.inventory_lots where id=raw)<>5
      or not exists(select 1 from public.food_logs where id=log_id and voided_at=now()) then
      raise exception '%: insufficient-stock restore must fail atomically',case_name; end if;
    perform public.void_food_log(other_log);
    perform public.restore_food_log(log_id);
    if (select remaining_qty from public.inventory_lots where id=raw)<>90
      or not exists(select 1 from public.food_logs where id=log_id and voided_at is null) then
      raise exception '%: valid restore failed',case_name; end if;
    perform public.correct_consumed_quantity(gen_random_uuid(),log_id,10,5);
    if (select remaining_qty from public.inventory_lots where id=raw)<>95
      or not exists(select 1 from public.food_logs where id=log_id and occurred_at=event_time and voided_at=now()) then
      raise exception '%: quantity correction failed',case_name; end if;
    -- Reset with another independent synthetic lot for the next case.
    raw:=gen_random_uuid();
    insert into public.inventory_lots(id,product,initial_qty,remaining_qty,location) values(raw,p,100,100,'pantry');
    raise notice 'PASS: % immediate void, actual timestamps, quantity correction, valid restore and insufficient-stock rollback',case_name;
  end loop;
end $$;
reset role;
rollback;
