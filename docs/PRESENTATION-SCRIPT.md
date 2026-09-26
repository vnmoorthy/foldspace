# FOLDSPACE — 3-minute presentation script

Bitrig Hacks: iPhone Duo Edition · Y Combinator · Sept 26 2026
Deck: [`docs/FOLDSPACE-Deck.pptx`](FOLDSPACE-Deck.pptx) (10 slides). Total: **180 seconds**. Spoken text: about 440 words, which is a relaxed pace that leaves room for the hinge to do the talking.

One presenter, one phone. Slides advance on a clicker or a second person. The phone is held up, half-open, for the whole talk; every demo beat is a hinge motion, never a tap (except the two gear-menu jumps noted below).

Formatting: **Say** blocks are the exact spoken words. **Do** blocks are stage directions. *(Duo)* is the real device or the Duo simulator folded from Device Hub; *(sim)* is the on-screen hinge control on a flat-iPhone simulator, with its macro buttons **CLOSE · SLAM · HOP · SQUEEZE · SNAP · PUMP ×4**, or drag the lid yourself.

---

## Timing at a glance

| # | Slide | Start | Length | Live hinge beat |
|---|---|---|---|---|
| 1 | FOLDSPACE (title) | 0:00 | 20 s | Hold the phone up half-open |
| 2 | Hinge sensors have existed for years | 0:20 | 14 s | none, talk slide |
| 3 | The phone is the ship | 0:34 | 18 s | Cockpit → flat → closed |
| 4 | Six gestures. Six verbs. | 0:52 | 12 s | none, talk slide |
| 5 | The hologram in the fold | 1:04 | 20 s | Open 90° → 150°, drag the probe across the fold |
| 6 | Fold space. | 1:24 | 24 s | Flat, pick Alpha Centauri, close smoothly, sit, open |
| 7 | Dive into the Sun · Nova Lance | 1:48 | 24 s | Squeeze, hold, snap open |
| 8 | Act III: the Core | 2:12 | 20 s | Fold toward the horizon, then pump ×4 and slam, open |
| 9 | Built with | 2:32 | 14 s | none, talk slide |
| 10 | Why this couldn't exist before | 2:46 | 14 s | Close the phone on the last line |

---

## Pre-show checklist (5 minutes before)

1. Fresh launch. In the console tap the **gear → Demo → Act III · The Core** once. This unlocks the warp drive, the Nova Lance and the Stellar Core Sample and parks you at Sagittarius A*.
2. Lay the phone flat, pick **Sol** on the galaxy map, close it once to warp home. Hop to **Venus** (dip the lid and bring it back until the HUD says Venus). Venus is unclaimed in the demo save, so the probe drag on slide 5 plants a fresh beacon.
3. Hold the phone at cockpit angle (~100°). Check the hologram sits in the crease and the console shows the ship computer panel. Registry pill should read a count, or `OFFLINE` if the room has no Wi-Fi (fine, the game plays offline).
4. Haptics on, volume up, brightness max. Clicker paired. Slide 1 on the screen.
5. Fallback tabs open on the laptop: the deck, `docs/screenshots/`, `docs/index.html`.

---

## Slide 1 · FOLDSPACE — 0:00–0:20 (20 s)

**On screen:** Title slide. "BITRIG HACKS · IPHONE DUO EDITION" strap, FOLDSPACE, "Fold the phone. Fold space.", repo URL.

**Do:** Walk on with the phone already half-open in one hand, held up at chest height so the room sees the crease. Do not look at the slide. Deliver the first two sentences flat, almost bored, then change gear on "We".

**Say:**

> Foldables have had hinge sensors for years. Everyone used them for animations. We used the hinge as an input device — and then we used both screens as a 3D corner. This is FOLDSPACE. The phone is the ship. Close it, and you fold space.

**Do:** On "Close it", close the phone halfway and stop. Hold the beat. Advance.

---

## Slide 2 · Hinge sensors have existed for years — 0:20–0:34 (14 s)

**On screen:** Three columns: 01 WHAT EVERYONE DID · Animations / 02 WHAT WE DID · The hinge is an input device / 03 AND THEN · Two screens are a 3D corner. Footer: "FOLDSPACE is what you get when you take the hinge literally."

**Do:** Point at column two on "One", column three on "Two". Keep the phone up. No demo here; this is the thesis, and it is quick.

**Say:**

> Two ideas. One: the hinge angle is continuous, like a joystick axis, so it carries velocity and rhythm. Two: two screens meeting at a known angle are a corner, like Seoul's wave billboard. Everything else today is those two ideas on a spaceship.

---

## Slide 3 · The phone is the ship — 0:34–0:52 (18 s)

**On screen:** Five postures with angle bands: CLOSED 0–12° · SQUEEZED 12–45° · COCKPIT 45–135° · OPEN 135–170° · FLAT 170–180°. Footer about `onHingeChange`.

**Do:** Three postures, in rhythm with the words. *(Duo)* Hold at ~100°: windshield above the fold, console below. Lay it flat on your palm: galaxy map fills the 7.6" display. Close it fully and turn the outer display to the room. *(sim)* drag the lid to 100°, then 180°, then tap **CLOSE**. Let each posture sit for a full second before you speak the next line; the room needs to see the UI change before you name it.

**Say:**

> Every posture is a flight state. Half-open: cockpit. Windshield above the fold, console below. Flat: galaxy map. Closed — the outer display takes over. No mode switch. No button. The posture is the state.

**Do:** Open back to cockpit angle on "The posture is the state." Advance.

---

## Slide 4 · Six gestures. Six verbs. — 0:52–1:04 (12 s)

**On screen:** Six cards: `.hop` HOP · `.warpClose` WARP · `.squeezeBegan` CHARGE · `.snapOpen` FIRE · `.pumpComplete` PUMP · continuous angle DIVE. Footer: HingeEngine.swift.

**Do:** Talk slide. Sweep a hand across the six cards on "hop, warp, charge, fire, pump, dive". On the last two sentences, mime the close at two speeds with the phone: a smooth close, then a fast one. Do not actually close it; you want the room hungry for slide 6.

**Say:**

> Six gestures, six verbs: hop, warp, charge, fire, pump, dive. The recogniser tracks angle and velocity with hysteresis, so a squeeze never reads as a warp. Same close, a hundred degrees a second: warp. Two-fifty: collapse.

---

## Slide 5 · The hologram in the fold — 1:04–1:24 (20 s)

**On screen:** Full-bleed render of the planet standing in the crease. Bullets: SpaceScene drives the camera from the hinge angle · the planet stands on the console half and rises into the windshield half · nothing crosses `.division` except the probe drag.

**Do:** You are in orbit at Venus. *(Duo)* Hold the phone at exactly 90° so the planet is split across the fold. On "I open the phone", open it slowly to about 150° over two full seconds, keeping the bottom half still so the room sees only the top half tilt away. Pause. Then drag the probe from the console up across the crease into the planet: this is the only tap-and-drag in the talk, and it is deliberate, the one control allowed to cross the fold. *(sim)* drag the lid slider from 90 to 150, then drag the probe. If the beacon lands you get a haptic and a HUD line; let it land before you advance.

**Say:**

> Now the corner. One SceneKit scene, one camera, its pitch is the hinge angle, every frame. Watch the planet. I open the phone... it stays put. The windshield tilts away from it. Only the probe may cross the fold: drag it into the planet to plant a beacon.

---

## Slide 6 · Fold space. — 1:24–1:48 (24 s)

**On screen:** Alcubierre diagram: BEHIND: STRETCHED · AHEAD: SQUEEZED · BUBBLE STABILITY = CLOSE SPEED with the three bands (< 60°/s CRAWL · 60–160°/s STABLE · > 160°/s SLAM). Side panel: OUTER DISPLAY IN TRANSIT, "FOLDING SPACE · 4.24 ly".

**Do:** This is the money shot; give it the silence it needs. Lay the phone flat, tap Alpha Centauri on the galaxy map (1 s). Lift to cockpit angle. Point at the stability meter on the HUD. Then **slowly close the phone here — a steady one-second close, not a slam — and let it sit closed for a beat.** Turn the outer 5.4" display to the room: FOLDING SPACE, 4.24 ly, counting. Two full seconds of silence. Then **snap it open — wait for the room** to register Proxima b before you say its name. *(sim)* tap **CLOSE** (it is tuned to the ideal 1.0 s close), wait, then drag the lid open. If you have spare seconds, tap **SLAM** once from the map to show COLLAPSING; otherwise the last sentence carries it.

**Say:**

> Alcubierre, taken literally: squeeze space ahead, stretch it behind, ride the bubble. Alpha Centauri, four point two four light-years. Watch the stability meter. I close the phone, smoothly... and let it sit. Outer display: FOLDING SPACE, light-years counting. Open it — Proxima b. Slam it instead and the bubble collapses; you drop out short.

---

## Slide 7 · Dive into the Sun · Nova Lance — 1:48–2:12 (24 s)

**On screen:** Left: the Sun, three layers with real temperatures, CORONA ~1,000,000 K (angle 120°, depth 0) · PHOTOSPHERE 5,800 K · CORE 15,000,000 K (angle 12°, depth 1). Right: Nova Lance, three steps: squeeze and hold, snap open, the planet shatters in the corner.

**Do:** You are at Proxima b, so the Sun dive is told over the slide graphic (the numbers do the work) and the Nova Lance is done live on Proxima b. Point at the Sun graphic for the first four sentences; mime a slow close with the phone on "close slowly" without going below 60°, so nothing fires. Then the Lance: *(Duo)* **squeeze the phone to about 25° and hold it there for two seconds**; the crease glows orange and the room can see the glow leak out of the gap. On "Snap": **snap it open as hard as you can — wait for the room.** The planet shatters in the corner. If people are close they will hear the haptic. *(sim)* tap **SQUEEZE**, wait for the glow, tap **SNAP**. Deliver the last line dry, straight to the judges.

*If you are running ahead by ten seconds and are still in Sol (skipped slide 6), do the dive live instead: hop to the Sun, close slowly to 45°, let it sit while the HUD temperature climbs, open to climb out.*

**Say:**

> The Sun. Real numbers: corona, a million kelvin. Photosphere, fifty-eight hundred. Core, fifteen million. Depth is fold amount: close slowly and the temperature climbs. Open to climb out. That core sample unlocks the Nova Lance. Squeeze and hold — the crease glows. Snap. The planet shatters, in 3D, in the corner. No Star Wars was harmed.

---

## Slide 8 · Act III: the Core — 2:12–2:32 (20 s)

**On screen:** Left: black-hole render, SAGITTARIUS A* · 26,670 LY · 4M SOLAR MASSES, fold = gravity, time dilation on the HUD, the beam vanishes. Right: ANDROMEDA · 2,537,000 LY, pump four times, slam, open.

**Do:** One tap during the slide change: **gear → Demo → Act III**. You are in orbit at Sagittarius A*, everything unlocked. *(Duo)* Close the phone to about 60° and hold: the EARTH CLOCK on the HUD races while ship time crawls. Open it back to cockpit. Then the finale: **pump it four times — open, shut, open, shut, open, shut, open — counting out loud with each pump, then slam it.** Let it sit closed for a beat; the outer display reads INTERGALACTIC FOLD. Then open it slowly and turn the screen to the room before you say "Andromeda". *(sim)* tap **PUMP ×4**, count with it, then **SLAM**, wait, open.

**Say:**

> Act three. Sagittarius A-star, four million solar masses. Fold is gravity: close to fall in, and Earth's clock races while yours crawls. Now the jump. Pump — one, two, three, four — charging the Fold Core. Slam. Two and a half million light-years. Open it: Milky Way behind you. Andromeda, rising out of the corner.

---

## Slide 9 · Built with — 2:32–2:46 (14 s)

**On screen:** Four columns: IPHONE DUO APIS (`onHingeChange`, reserved regions `.division` and `.occlusion`, outer/inner continuity, size classes, multiple scenes) · RENDERING + SCIENCE (SceneKit, @Observable, NASA Exoplanet Archive, EHT) · SPONSOR STACK (Supabase, OpenAI, Sentry) · ARCHITECTURE flow.

**Do:** Talk slide. Lower the phone for the first time; the finale is still on its screen, which is fine. Point at the left column on "All Duo API" and at each sponsor logo as you name it. Do not explain the diagram; it is there for the judges to read while you talk.

**Say:**

> All Duo API: the hinge callback, the reserved fold region, the outer display. Supabase holds the Galactic Registry: every pilot's warps, one table. OpenAI is the ship computer, grounded in the real catalog. Sentry watches the hinge loop.

---

## Slide 10 · Why this couldn't exist before — 2:46–3:00 (14 s)

**On screen:** Three negatives (no angle · one plane · one face), the positive ("iPhone Duo has all three, and tells the app about them continuously"), WHAT'S NEXT (four items), repo URL, "Built in one day at Bitrig Hacks · MIT license".

**Do:** Slow down. Three negatives, one per breath. Speed back up for "Next". Then bring the phone up one last time, half-open, for the closing line. On "Fold space", **close the phone, and stop talking.** Do not say thank you; the closed phone is the full stop.

**Say:**

> A flat iPhone has no angle. One plane. One face. Duo has all three, and reports them continuously. Next: real hardware on Xcode 27.1, and a shared sky — other pilots' beacons in your map. Fold the phone. Fold space.

---

## Judges' questions we expect

**Why wasn't this possible before?**
A flat iPhone gives an app zero bits about its own shape. iPhone Duo gives it a continuous angle through `onHingeChange`, a known fold line (`.division`), and a second display that faces the world when the phone is shut. Without the angle there is nothing to close, squeeze, snap or pump; without two planes there is no corner for the hologram; without the outer display nothing shows FOLDING SPACE in transit. FOLDSPACE uses all three, and none of them exist on a slab.

**Why is the hinge simulated?**
It isn't, on the right toolchain. The Duo APIs ship in the Xcode 27.1 beta, which needs macOS 26.6; the hackathon build machine was on 26.5. So the native hinge path is behind a `DUO_SDK` compilation flag, and the same `HingeEngine` runs from three sources: the Duo hinge callback, an on-screen hinge control in the simulator, or CoreMotion tilt on a flat iPhone. Flip the flag on 27.1 and Device Hub folds drive the game directly. Everything you saw, thresholds, hysteresis, velocity bands, was tuned against real degrees per second.

**What's real physics and what's exaggerated?**
Real: every distance (Proxima b at 4.24 ly, Sgr A* at 26,670 ly, Andromeda at 2.537 Mly), every planet fact from the NASA Exoplanet Archive, the Sun's layer temperatures from NASA's fact sheets, and the direction of time dilation near a 4-million-solar-mass black hole. Exaggerated: the rates. You cross 4 light-years in seconds, the Earth clock races visibly, and "fold = gravity" is a control mapping, not a metric. The Alcubierre framing is a metaphor we took literally for the hinge: squeeze ahead, stretch behind, ride the bubble in the crease.

**What's next?**
Real hardware first: flip `DUO_SDK` on Xcode 27.1 and fold a physical Duo. Then a shared sky: the Galactic Registry already stores every pilot's beacons and warps, so other players' beacons appear in your galaxy map. Then the ship computer talks back with voice, and the catalog grows from ten systems to the 5,000+ confirmed exoplanets. The engine is done; the universe is data.

**How do the sponsor tools fit?**
Each covers something outside the phone. Supabase (Postgres + PostgREST) is the Galactic Registry: every beacon, warp, shattered world and Andromeda arrival is POSTed to one `events` table with anon-insert RLS, read back by the HUD and a live dashboard. OpenAI (gpt-5-mini) is the ship computer: NARRATE and ASK in the console, plus the Commander's Log at Andromeda, with a strict prompt that only sees the body's real facts and never invents numbers. Sentry captures crashes and traces the 60 Hz hinge loop, with every game log line as a breadcrumb. All three are optional; with no keys the game runs fully offline and the ship computer uses a deterministic voice built from the same facts.

---

## If the demo breaks

Do not debug on stage. If the phone or simulator hangs, say "the ship is folded; let me show you where it went" and switch the slide screen to the stills: the seven screenshots in `docs/screenshots/` (`01-cockpit`, `02-galaxy-map`, `03-outer-display-warp`, `04-sun-dive`, `05-nova-lance`, `06-sagittarius-a`, `07-andromeda`) follow the talk in order, so you walk them with the same spoken lines and mime the hinge motion on the dead phone. The deck already carries the key visuals if the screenshots folder is not on the laptop: slide 3 (the five postures), slide 5 (the planet in the crease), slide 6 (the outer display reading FOLDING SPACE · 4.24 ly), slide 7 (the Sun's layers and the shatter), slide 8 (Sagittarius A* and Andromeda), and `docs/hero.png` is the wide fold-the-phone hero if you need one image on screen while you talk. The landing page at `docs/index.html` and the live registry dashboard at `docs/registry.html` both open offline in a browser tab. If only one beat fails (a warp that won't fire because the map lost its target, a probe that won't cross the fold), skip it, keep the words, and spend the saved seconds on the finale: **gear → Demo → Act III**, pump four times, slam, open. Andromeda rising out of the corner is the image they should leave with.

*Before the talk: `docs/screenshots/` must actually contain the seven PNGs named above; as of writing the folder is empty. Capture them from the simulator with the gear-menu demo jumps.*
