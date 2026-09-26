# FOLDSPACE backend — the Galactic Registry

A tiny public event log on [Butterbase](https://butterbase.ai). The iOS game posts one row every
time a commander claims a planet, shatters one with the Nova Lance, folds space to a new star,
assembles the warp drive, samples a stellar core, slingshots around Sagittarius A* or reaches
Andromeda. The dashboard (`dashboard/index.html`) renders the same rows as a live feed.

| What | Value |
|---|---|
| Butterbase app | `dragnet` → `app_a7c3jfpp8stm` (see **Provisioning status** below) |
| API base | `https://api.butterbase.ai/v1/app_a7c3jfpp8stm` |
| Table | `events` |
| Dashboard | `https://dragnet.butterbase.dev` (frontend URL of the app) |
| Access mode | `public` — anonymous inserts/selects, no API key or auth header |
| iOS client | `Foldspace/Network/GalacticRegistry.swift` (`RegistryConfig` at the top) |

## Provisioning status (read this first)

The Butterbase account is on the free plan, which allows **one project**, and that slot is taken by
the pre-existing app `dragnet` (`app_a7c3jfpp8stm`, table `cases`). `init_app("foldspace")` fails
with `project_limit_reached`, and the agent that wrote this file was **not permitted** to modify
`dragnet` (schema, CORS, frontend) or to delete it. So, as of this commit:

- `Foldspace/Network/GalacticRegistry.swift` — done, typechecks, works offline (`isOnline == false`).
- `backend/dashboard/index.html` + `backend/dashboard.zip` — done, ready to upload.
- **Not yet live:** the `events` table, the CORS origins, the seed rows and the dashboard deployment.

Pick one of these and run the steps in **Provisioning**:

- **A. Reuse `dragnet`** (fastest): keep `cases`, add the `events` table, deploy the dashboard to
  `https://dragnet.butterbase.dev`. Nothing in the code needs to change.
- **B. Fresh `foldspace` app**: delete `dragnet` (irreversible) or upgrade the plan, then
  `init_app("foldspace")`. Copy the new `app_id` into `RegistryConfig.appID` (Swift) and
  `DEFAULT_API_BASE` (dashboard), and `dashboardURL` → `https://foldspace.butterbase.dev`.

## Schema

Butterbase schema DSL (`manage_schema` → `apply`). When adding to `dragnet`, include the existing
`cases` table verbatim — a table missing from the document is treated as a drop request and rejected.

```json
{
  "tables": {
    "events": {
      "columns": {
        "id":         { "type": "uuid",        "primaryKey": true, "default": "gen_random_uuid()" },
        "callsign":   { "type": "text",        "nullable": false },
        "event":      { "type": "text",        "nullable": false },
        "body":       { "type": "text",        "nullable": false },
        "energy":     { "type": "integer",     "nullable": false, "default": "0" },
        "created_at": { "type": "timestamptz", "nullable": false, "default": "now()" }
      },
      "indexes": { "events_created_at_idx": { "columns": ["created_at"] } }
    }
  }
}
```

Equivalent SQL:

```sql
create table events (
  id         uuid primary key default gen_random_uuid(),
  callsign   text not null,
  event      text not null,   -- claimed | destroyed | warped | driveAssembled | coreSample | passedBlackHole | reachedAndromeda
  body       text not null,   -- kebab-case body id: earth, mars, trappist-1b, sgr-a-star, m31 …
  energy     integer not null default 0,
  created_at timestamptz not null default now()
);
create index events_created_at_idx on events (created_at);
```

`event` values are the `RegistryEvent` raw values; `body` values are the `CelestialBody.id`s from
`Foldspace/Universe/UniverseData.swift`.

## Endpoints

Base: `https://api.butterbase.ai/v1/app_a7c3jfpp8stm` (set `API` below once).

```bash
API="https://api.butterbase.ai/v1/app_a7c3jfpp8stm"

# Insert an event (anonymous — the app is in public access mode)
curl -s -X POST "$API/events" \
  -H "Content-Type: application/json" \
  -d '{"callsign":"NOVA-7","event":"claimed","body":"earth","energy":10}'

# Latest 25 events, newest first (what the game and the dashboard read)
curl -s "$API/events?select=id,callsign,event,body,energy,created_at&order=created_at.desc&limit=25"

# Filter examples
curl -s "$API/events?callsign=eq.NOVA-7&order=created_at.desc"
curl -s "$API/events?event=eq.destroyed&select=callsign,body,created_at"
curl -s "$API/events?event=in.(reachedAndromeda,passedBlackHole)"

# One row / update / delete (service key required once you tighten access)
curl -s "$API/events/<uuid>"
curl -s -X PATCH "$API/events/<uuid>" -H "Content-Type: application/json" -d '{"energy":99}'
curl -s -X DELETE "$API/events/<uuid>"
```

Filter grammar: `column=op.value` with `eq neq gt gte lt lte like ilike is in fts`;
sort with `order=col.desc`; page with `limit`/`offset`; project with `select=a,b`.

Seed rows (the three the dashboard is demoed with):

```bash
for row in \
  '{"callsign":"NOVA-7","event":"claimed","body":"earth","energy":10}' \
  '{"callsign":"NOVA-7","event":"driveAssembled","body":"neptune","energy":70}' \
  '{"callsign":"KESTREL","event":"destroyed","body":"trappist-1b","energy":140}'; do
  curl -s -X POST "$API/events" -H "Content-Type: application/json" -d "$row"; echo
done
```

## iOS client

`GalacticRegistry` (`@MainActor @Observable`) is created once in the app and handed to
`GameStore.registry`. `record(_:body:energy:)` POSTs in a detached `Task` and returns
immediately; failures set `isOnline = false` and queue the row (max 50) for the next `refresh()`.
`refresh()` pulls the latest 25 rows and computes `GalacticStats` (distinct commanders,
claimed/destroyed/Andromeda counts, `recent`). `startPolling(every:)` is a convenience for the
docked / outer-display screen. Change the target app in `RegistryConfig` only.

## Dashboard

`dashboard/index.html` is a single file, no build step: dark space theme, cyan monospaced HUD,
five stat tiles, live feed with relative times, auto-refresh every 5 s (paused while the tab is
hidden), hero header "FOLDSPACE — fold the phone, fold space", link to
<https://github.com/vnmoorthy/foldspace>. It reads `DEFAULT_API_BASE` (same app as
`RegistryConfig`) and accepts a runtime override: `index.html?api=https://api.butterbase.ai/v1/app_xxx`.

Preview locally:

```bash
cd backend/dashboard && python3 -m http.server 8080   # http://localhost:8080
```

## Provisioning (one-time)

Via the Butterbase MCP tools (Claude Code / Cursor with the `butterbase` server):

1. `manage_app list` — confirm the target `app_id`.
2. `manage_schema apply` — the schema above (plus the existing `cases` table if reusing `dragnet`).
3. `manage_app update_access_mode` → `public` (already the case for `dragnet`).
4. `manage_app update_cors` → `["https://dragnet.butterbase.dev", "http://localhost:8080"]`
   (the API rejects a bare `*`; list the dashboard origin and any local dev origins).
5. `seed_database` / `insert_row` — the three seed rows above; `select_rows` to verify.
6. `create_frontend_deployment { app_id, framework: "static" }` → returns `uploadUrl` + `deployment_id`.
7. `curl -X PUT "<uploadUrl>" -H "Content-Type: application/zip" --data-binary @backend/dashboard.zip`
8. `manage_frontend { action: "start_deployment", deployment_id }` — wait for `READY`, then
   `curl -I https://<subdomain>.butterbase.dev` until it returns 200 (the CDN can lag a minute).
9. Insert a row with the curl above and watch it appear in the feed within 5 s.

`backend/dashboard.zip` is rebuilt with `cd backend/dashboard && zip -X -r ../dashboard.zip index.html`
(forward-slash paths; `index.html` at the archive root).
