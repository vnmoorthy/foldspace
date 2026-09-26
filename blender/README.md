# FOLDSPACE — Blender scripts

Headless Blender 5.2.1 builders for the game's space visuals. Every script runs from the repo root with

```bash
B="/Applications/Blender.app/Contents/MacOS/Blender"
"$B" --background --python blender/<script>.py -- [flags]
```

Everything after the bare `--` belongs to the script (`argparse`); Blender swallows the rest. Previews land in
`blender/out/` (gitignored); finals are copied into `assets/` under the names in
[`../docs/BLENDER-CODEX-BRIEF.md`](../docs/BLENDER-CODEX-BRIEF.md). The plan (physics, look-dev, who does
what) is [`../docs/BLENDER-VISUALS-PLAN.md`](../docs/BLENDER-VISUALS-PLAN.md). `blender/codex/` belongs to a
separate Codex agent — leave it alone.

Requirements: Blender 5.2.1 at the path above (numpy is bundled; Pillow optional). For the HEVC-with-alpha
movie: `ffmpeg` (`brew install ffmpeg`, present at `/opt/homebrew/bin/ffmpeg`) and Apple's `/usr/bin/avconvert`
(present on this Mac).

## Common flags (`common.py`)

| Flag | Meaning |
|---|---|
| `--quick` | 256×256, a handful of samples, one frame, **CPU**. Every script finishes in seconds. |
| `--final` | Full-resolution defaults (also the default when `--quick` is absent). |
| `--res W H`, `--samples N`, `--frames N`, `--fps N` | Override the script's defaults. `--frames 1` = still. |
| `--engine CYCLES\|EEVEE` | Override the script's engine. |
| `--device CPU\|GPU\|AUTO` | `AUTO` = CPU for `--quick`, Metal GPU for finals. **Cycles' Metal backend hangs inside sandboxed shells** (Claude Code's Bash tool: the probe never returned); run finals from Terminal, or pass `--device CPU` / `export FOLDSPACE_DEVICE=CPU`. EEVEE renders fine headless everywhere. |
| `--out DIR` | Output directory (default `blender/out`). Use a per-asset subdirectory for finals. |
| `--seed N`, `--view AgX\|Filmic\|Standard`, `--save-blend` | Variation seed; view transform (AgX default); also write `out/<name>.blend` for look-dev in the UI. |

Output naming: a still is `<out>/<name>.png` (RGBA when the film is transparent); an animation is
`<out>/<name>/frame_0001.png …`. Every run logs `png_stats` (size, mean/max RGB, alpha coverage) so a black
frame is caught without opening the image.

Blender 5.x notes baked into `common.py`: the compositor lives in `scene.compositing_node_group` (bloom via
`add_bloom`, glare `Size` is a 0–1 fraction of the frame), slotted actions hide `action.fcurves`
(`common.action_fcurves`), and OSL reserves the globals `u`/`v` (the geodesic tracer uses `iu`).

## Scripts

### `make_planet.py` — planet materials and equirect bakes
Nine `PlanetClass` materials (rocky, lava, desert, ice, ocean, superEarth, gasGiant, iceGiant, earthlike):
per-channel Rayleigh rim (τ ∝ λ⁻⁴, weights 0.175/0.41/1.0), sunset reddening at the terminator, latitude-based
zonal bands and a 22° S anticyclone for gas giants, Blackbody 1200–1700 K crack emission for lava, ice caps
beyond |lat| ≈ 60°, clouds for earthlike/ocean, optional rings. Cycles.

```bash
"$B" --background --python blender/make_planet.py -- --quick                                   # earthlike beauty → out/planet_earthlike.png
"$B" --background --python blender/make_planet.py -- --quick --planet gasGiant --no-clouds     # any class; --no-atmosphere too
"$B" --background --python blender/make_planet.py -- --final --all                              # all nine beauties, 1024², 64 spp
"$B" --background --python blender/make_planet.py -- --final --planet earthlike --bake --base-hex 3B82D6 --seed 1 --out blender/out/planets/earth
```
`--bake` writes `<out>/planet_<class>_albedo.png` (2048×1024, sRGB, no alpha; 256×128 with `--quick`) and, for
lava, `planet_lava_emission.png`. Bake one body per `--out` directory (the file is named by class), then copy to
`assets/textures/planet-<bodyid>.png` (+ `planet-<bodyid>-emissive.png`). Class and `--base-hex` per body come
from `Foldspace/Universe/UniverseData.swift` (`planetClass`, `colorHex`); the priority six:

| body id | `--planet` | `--base-hex` | body id | `--planet` | `--base-hex` |
|---|---|---|---|---|---|
| `earth` | earthlike | 3B82D6 | `proxima-b` | rocky | 9C8A78 |
| `jupiter` | gasGiant | D2A374 | `trappist-1e` | ocean | 2E5FB8 |
| `mars` | desert | C4613A | `neptune` | iceGiant | 3E6BD1 |

(then `venus` desert E0B570, `saturn` gasGiant E4C98A `--rings`, `uranus` iceGiant 7CD4DE, `mercury` rocky 8C8078,
`barnard-d` / `trappist-1b` lava D9502F / D8502E, and the rest from `UniverseData.swift`). The baked albedo must
not contain the rim or clouds — they are separate shells in `SpaceScene`.

### `make_sun.py` — the Sun
Emission-only Cycles scene: Blackbody(5772 K) photosphere with looping 4-D Voronoi granulation, sunspot belts
(umbra 3800 K / penumbra 5000 K, |lat| < 30°), limb darkening I(μ)/I(1) = 0.3 + 0.7 μ, Hα chromosphere shell,
Baumbach-law corona billboard with a helmet-streamer belt, Bezier prominences, compositor bloom.

```bash
"$B" --background --python blender/make_sun.py -- --quick                                       # → out/sun.png
"$B" --background --python blender/make_sun.py -- --final --res 2048 2048 --samples 64 --out blender/out/sun_final
"$B" --background --python blender/make_sun.py -- --final --frames 240 --res 1024 1024 --out blender/out/sun_loop   # 8 s seamless loop
"$B" --background --python blender/make_sun.py -- --quick --dive 0.8                            # camera inside the photosphere (SunDiveView)
```
Flags: `--gain` (photosphere exposure, default 3.0), `--granule-scale`, `--spots` (threshold; higher = fewer),
`--prominences N`, `--no-corona`, `--dive 0..1`. Not yet scripted (plan task C3): the equirect
`sun-photosphere.png` bake and a corona-only `sun-corona.png` render; until then the beauty still is the
hologram billboard.

### `make_black_hole.py` — Sagittarius A*
OSL Schwarzschild null-geodesic tracer (Binet equation, RK4) on a camera-filling plane, **Cycles CPU** (OSL has
no Metal backend): shadow, photon ring, the far side of the disc lensed over and under the shadow, Einstein-ring
starfield; disc with Doppler beaming (g⁴, β = 0.5 at ISCO), gravitational redshift, T ∝ r⁻³ᐟ⁴, loop-safe
differential rotation; `--mode fake` = node-only GPU/EEVEE proxy for look-dev.

```bash
"$B" --background --python blender/make_black_hole.py -- --check                                # physics test, no render (b_crit 2.598 r_s PASS)
"$B" --background --python blender/make_black_hole.py -- --quick                                # → out/black_hole.png (+ out/starfield.exr)
"$B" --background --python blender/make_black_hole.py -- --final --res 2048 2048 --samples 16 --alpha-disc-only --device CPU --out blender/out/bh_still
"$B" --background --python blender/make_black_hole.py -- --final --frames 360 --res 1080 1080 --samples 8 --alpha-disc-only --device CPU --out blender/out/bh_loop
"$B" --background --python blender/make_black_hole.py -- --quick --mode fake --engine EEVEE --save-blend
```
Flags: `--distance` (22 r_s), `--incl` (12°), `--fov` (46), `--rout` (7 r_s), `--tpeak` (9000 K), `--gain`
(disc exposure, 2.0), `--stars` (0 hides them), `--alpha-disc-only` (transparent where stars would be, for the
overlay), `--step` (Δφ). Budget: ~10–15 s/frame at 1080² × 8 spp on the CPU → the 360-frame loop is ~1–1.5 h.

### `make_warp_bubble.py` — Alcubierre warp bubble
York time θ = v_s (x/r) df/dr on a displaced grid (numpy), vertex colours blue = contraction (ahead, +x) /
red = expansion (behind), scrolling grid lines, bubble-wall shell, ship marker. EEVEE, transparent film.

```bash
"$B" --background --python blender/make_warp_bubble.py -- --quick                               # → out/warp_bubble.png
"$B" --background --python blender/make_warp_bubble.py -- --final --form --frames 8 --res 512 512 --out blender/out/warp8   # flat→peak→flat, 8 frames
"$B" --background --python blender/make_warp_bubble.py -- --final --frames 60 --res 512 512 --out blender/out/warp_loop     # 2 s scrolling loop
"$B" --background --python blender/make_warp_bubble.py -- --quick --quality 0.3                 # collapsing-bubble variant
"$B" --background --python blender/make_warp_bubble.py -- --quick --stars --beta 0.85           # opaque, aberrated + Doppler-shifted sky
```
Flags: `--R` (4), `--sigma` (2), `--vs` (1 c), `--amp` (1.6), `--cells`, `--quality 0..1`, `--form`, `--stars`, `--beta`.

### `render_sprites.py` — sprite sheets and HEVC-alpha movies
```bash
"$B" --background --python blender/render_sprites.py -- --quick                                  # self-test: 16 ring frames → out/sprites_quick_sheet.png/.json
"$B" --background --python blender/render_sprites.py -- --frames-dir blender/out/warp8/warp_bubble --cols 8 --name warp-bubble-8x1 --out assets/sprites
"$B" --background --python blender/render_sprites.py -- --frames-dir blender/out/bh_loop/black_hole --hevc --no-sheet --name blackhole-loop --fps 30 --out assets/video
```
`--frames-dir DIR` (the input; `--frames` is the render-frame count in every script), `--pattern`, `--cols`
(default ⌈√n⌉), `--name`, `--max-frames`, `--packer auto|pil|bpy`, `--hevc`, `--no-sheet`. The sheet gets a JSON
manifest (`frame_width/height, columns, rows, count, fps, duration`) and a round-trip pixel check. `--hevc`
runs ffmpeg → ProRes 4444 → `avconvert --preset PresetHEVC1920x1080WithAlpha` → `<out>/<name>.mov` (`hvc1`
with alpha; play with `AVPlayerLayer` + `AVPlayerLooper`).

## Outputs → asset contract

| Brief asset (`assets/…`) | Produce with | Raw output |
|---|---|---|
| `textures/planet-<bodyid>.png` (2048×1024) | `make_planet.py --final --planet <class> --bake --base-hex <hex> --out blender/out/planets/<bodyid>` | `blender/out/planets/<bodyid>/planet_<class>_albedo.png` → rename |
| `textures/planet-<bodyid>-emissive.png` | same run, lava classes only | `…/planet_lava_emission.png` |
| `textures/sun-photosphere.png`, `sun-corona.png` | `make_sun.py` beauty/loop today; equirect bake + corona-only render are plan task C3 | `blender/out/sun_final/sun.png` |
| `video/blackhole-loop.mov` (1080², 30 fps, 12 s) | `make_black_hole.py --final --frames 360 …` then `render_sprites.py --hevc` | `blender/out/bh_loop/black_hole/frame_####.png` → `assets/video/blackhole-loop.mov` |
| `textures/blackhole-still.png` (2048²) | `make_black_hole.py --final --res 2048 2048 --samples 16 --alpha-disc-only` | `blender/out/bh_still/black_hole.png` → copy |
| `sprites/warp-bubble-8x1.png` (8 × 512²) | `make_warp_bubble.py --final --form --frames 8 --res 512 512` then `render_sprites.py --cols 8` | `assets/sprites/warp-bubble-8x1.png` + `.json` |
| `textures/galaxy-*.png` | not in these scripts (plan task C6; Codex `galaxies.py` has candidates) | — |
| `sprites/shatter-debris-4x4.png` | not in these scripts (plan task C7; Codex `shatter.py` has candidates); pack with `render_sprites.py --cols 4` | — |
| `NOTES.md` | by hand from each run's log line (`png_stats`, York-time range, `--check` output) | — |

Then copy the files under `Foldspace/Resources/` and run `xcodegen generate`; the Swift hooks are named per asset in the plan.

## Verified (`--quick`, CPU, this Mac)

| Script | Time | Result |
|---|---|---|
| `make_planet.py` | ~3 s | `out/planet_earthlike.png` — blue oceans, green/brown continents, clouds, polar cap, blue Rayleigh rim |
| `make_sun.py` | ~4 s | `out/sun.png` — warm-white limb-darkened disc, sunspot, orange prominence arches, streamer corona fading by ~2 R☉ |
| `make_black_hole.py` | ~2–15 s | `out/black_hole.png` — shadow with the disc lensed over and under it, photon ring, Einstein-ringed stars; approaching half 2.8× brighter |
| `make_warp_bubble.py` | ~2–5 s | `out/warp_bubble.png` — grid with the York surface: blue contraction ahead (+x), red expansion behind, wall shell, ship marker |
| `render_sprites.py` | ~4 s | `out/sprites_quick_sheet.png` — 4×4 sheet of a rotating, pulsing ring; round-trip diff 0/255 |

`make_black_hole.py -- --check`: b_crit = 2.5981 r_s (√27/2 PASS), β_ISCO = 0.5, g(face-on, ISCO) = 0.7071,
Sgr A* r_s = 1.27 × 10¹⁰ m = 0.085 AU.
