# Galactic Registry · Supabase

Every beacon, destroyed world, warp, core sample, slingshot and Andromeda arrival in FOLDSPACE is posted
to one Postgres table on Supabase and read back for the HUD feed and the [`docs/registry.html`](../docs/registry.html)
dashboard. The game is fully playable offline: with no credentials the registry reports `OFFLINE` and
everything else works exactly the same.

```
Foldspace app ──POST /rest/v1/events──▶ Supabase PostgREST ──▶ public.events (RLS: anon insert + select)
docs/registry.html ◀──GET /rest/v1/events?order=created_at.desc──┘
```

## 1 · Create the project

1. Go to [supabase.com](https://supabase.com) → **New project** (any name, e.g. `foldspace`, any region).
2. Wait for the database to provision (about a minute).

## 2 · Run the migration

**SQL editor (fastest):** Dashboard → **SQL Editor** → **New query** → paste
[`migrations/20260926000000_events.sql`](migrations/20260926000000_events.sql) → **Run**.
Then paste [`seed.sql`](seed.sql) → **Run** so the feed has three rows.

**CLI:**

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref <your-project-ref>   # from the project URL: https://<ref>.supabase.co
supabase db push                                 # applies supabase/migrations/*
psql "$(supabase db url)" -f supabase/seed.sql   # optional demo rows
```

What the migration creates:

| Object | Purpose |
|---|---|
| `public.events` | `id uuid`, `callsign`, `event` (checked enum), `body`, `energy`, `created_at` |
| index on `created_at desc` | the feed query |
| RLS + two policies | **anon INSERT** and **anon SELECT** — no update, no delete |
| `public.galactic_stats` view | `commanders`, `claimed`, `destroyed`, `andromeda_arrivals`, `events`, `last_event_at` |

## 3 · Find the URL and anon key

Dashboard → **Project Settings** → **API**:

- **Project URL** → `https://<ref>.supabase.co`
- **Project API keys → `anon` `public`** → a long `eyJ…` JWT

The anon key is designed to ship inside clients; RLS is what protects the data.

## 4 · Put them in the app

```bash
cp Foldspace/Secrets.example.plist Foldspace/Secrets.plist   # gitignored
```

Edit `Foldspace/Secrets.plist`:

```xml
<key>SUPABASE_URL</key>       <string>https://abcdefgh.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>  <string>eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...</string>
```

Then `xcodegen generate` once (so the new resource is in the project) and run. The console's gear menu
and the outer display show `REGISTRY ONLINE · n CMDR` when the first refresh succeeds.

Simulator shortcut: instead of the plist, set `FOLDSPACE_SUPABASE_URL` and `FOLDSPACE_SUPABASE_ANON_KEY`
as environment variables in the Xcode scheme (Run → Arguments).

## 5 · curl

```bash
export SUPABASE_URL="https://abcdefgh.supabase.co"
export SUPABASE_ANON_KEY="eyJ..."

# Insert (exactly what the app sends; id + created_at are server defaults)
curl -sS -X POST "$SUPABASE_URL/rest/v1/events" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=minimal" \
  -d '{"callsign":"NOVA-4821","event":"claimed","body":"mars","energy":40}'
# → HTTP 201, empty body

# Latest 25 events
curl -sS "$SUPABASE_URL/rest/v1/events?select=*&order=created_at.desc&limit=25" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY"

# Aggregates
curl -sS "$SUPABASE_URL/rest/v1/galactic_stats" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY"

# RLS check — this must fail with 401/403 (no delete policy)
curl -sS -X DELETE "$SUPABASE_URL/rest/v1/events?callsign=eq.NOVA-4821" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY"
```

## Dashboard

Open [`docs/registry.html`](../docs/registry.html) with the same two values in the query string:

```
docs/registry.html?url=https://abcdefgh.supabase.co&key=eyJ...
```

or paste them into the two constants at the top of the file. With no URL the page shows a clearly
labelled demo feed so it is never blank.

## App-side code

[`Foldspace/Network/GalacticRegistry.swift`](../Foldspace/Network/GalacticRegistry.swift) —
`record(_:body:energy:)` is fire-and-forget with an in-memory retry queue; `refresh()` pulls the latest
500 rows and computes the stat tiles in-app. Credentials come from
[`Foldspace/Config/Secrets.swift`](../Foldspace/Config/Secrets.swift).
