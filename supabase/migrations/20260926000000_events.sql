-- FOLDSPACE · Galactic Registry
-- One append-only table of gameplay events, written and read by Supabase's anon role and nothing else.
-- Apply in the Supabase SQL editor (paste + Run) or with `supabase db push`. Idempotent.

create table if not exists public.events (
  id          uuid primary key default gen_random_uuid(),
  callsign    text not null,
  event       text not null
              check (event in ('claimed','destroyed','warped','driveAssembled','coreSample','passedBlackHole','reachedAndromeda')),
  body        text not null,
  energy      integer not null default 0,
  created_at  timestamptz not null default now(),
  -- Anonymous writes are allowed, so keep them sane.
  constraint events_callsign_len  check (char_length(callsign) between 1 and 24),
  constraint events_body_len      check (char_length(body) between 1 and 64),
  constraint events_energy_range  check (energy between 0 and 1000000)
);

comment on table public.events is 'FOLDSPACE gameplay events: beacons, destroyed worlds, warps, Andromeda arrivals.';

create index if not exists events_created_at_desc_idx on public.events (created_at desc);

-- Row-level security: anon may INSERT and SELECT. No UPDATE / DELETE policy exists, so RLS refuses them.
alter table public.events enable row level security;

drop policy if exists "anon can insert events" on public.events;
create policy "anon can insert events"
  on public.events
  for insert
  to anon
  with check (true);

drop policy if exists "anon can read events" on public.events;
create policy "anon can read events"
  on public.events
  for select
  to anon
  using (true);

-- Supabase grants ALL on new public tables to anon/authenticated by default; narrow that too.
revoke all on table public.events from anon, authenticated;
grant select, insert on table public.events to anon;

-- Aggregate view for dashboards and curl. security_invoker => evaluated under the caller's RLS.
create or replace view public.galactic_stats
  with (security_invoker = true) as
select
  count(distinct callsign)                              as commanders,
  count(*) filter (where event = 'claimed')             as claimed,
  count(*) filter (where event = 'destroyed')           as destroyed,
  count(*) filter (where event = 'reachedAndromeda')    as andromeda_arrivals,
  count(*)                                              as events,
  max(created_at)                                       as last_event_at
from public.events;

grant select on public.galactic_stats to anon;

-- Optional: stream inserts to future dashboards over Supabase Realtime.
-- alter publication supabase_realtime add table public.events;
