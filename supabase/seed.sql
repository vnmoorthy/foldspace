-- FOLDSPACE · Galactic Registry seed — three commanders so the feed is never empty.
-- Run after the migration (Supabase SQL editor, or `supabase db reset` picks it up automatically).

insert into public.events (callsign, event, body, energy) values
  ('NOVA-4821', 'claimed',          'earth',   25),
  ('VEGA-0117', 'destroyed',        'mercury', 65),
  ('LYRA-9034', 'reachedAndromeda', 'm31',     812);
