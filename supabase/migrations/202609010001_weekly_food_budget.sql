-- One food budget, stored once. Today, This week, Grocery, Trends and the panel
-- context strips all derive from this single weekly number; the daily figure is
-- weekly / 7. There is deliberately no separate grocery budget to drift from it.
alter table public.personal_settings
  add column weekly_food_budget numeric(10, 2) not null default 150
    check (weekly_food_budget > 0);

comment on column public.personal_settings.weekly_food_budget is
  'The single food budget, in USD per week. Every daily, weekly, and per-meal budget figure in the app derives from this value; do not add a second budget column.';
