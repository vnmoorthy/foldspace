# FOLDSPACE — Blender visuals plan

Physics that must hold, the Blender approach, render specs, and the exact iOS hook for every visual in
the game; then the split of work between **Claude** (everything scriptable) and **Astra** (art direction,
look-dev, review) for one evening. Companion to [`BLENDER-CODEX-BRIEF.md`](BLENDER-CODEX-BRIEF.md)
(asset contract and paths) and [`../blender/README.md`](../blender/README.md) (how to run the scripts).

**Starter scripts** (all in `blender/`, all run headless with `-- --quick` for a 256 px CPU preview):

| Script | What it already does |
|---|---|
| `common.py` | CLI (`--quick/--res/--samples/--frames/--fps/--engine/--device/--seed/--view/--save-blend`), fresh scene with AgX + transparent film, camera/light/sphere/grid/billboard helpers, node helpers (`math_node`, `vmath_node`, `ramp`, `noise`, `voronoi`, `blackbody`, `emission_over_transparent`), frame-driven `time_value` for seamless loops, compositor bloom (Blender 5.x `compositing_node_group` aware), a numpy HDR **starfield** (blackbody-coloured Gaussian stars + Milky Way band → `starfield.exr`), `render()` (still or frame sequence), `png_stats()` sanity numbers. |
| `make_planet.py` | Nine `PlanetClass` materials (rocky, lava, desert, ice, ocean, superEarth, gasGiant, iceGiant, earthlike) with per-channel **Rayleigh** rim shell, cloud shell, optional rings; `--bake` writes the **equirect albedo** (and lava **emission**) map for `PlanetMaterials`; `--no-clouds` / `--no-atmosphere` for look-dev and bake checks. Latitude masks read the unit-sphere z, noise reads a per-seed offset copy. |
| `make_sun.py` | Photosphere (Blackbody 5772 K, looping 4-D Voronoi granulation, sunspot belts, **limb darkening** u = 0.7), Hα chromosphere shell, **Baumbach** corona billboard with helmet-streamer belt, Bezier prominences, `--gain` exposure, `--dive` camera for `SunDiveView`. |
| `make_black_hole.py` | **OSL Schwarzschild geodesic tracer** (Binet equation, RK4) on a camera plane: shadow, photon ring, far-side disc lensing, Einstein-ring starfield; Doppler + gravitational redshift node math (g⁴ beaming, Blackbody(g·T)); loop-safe differential rotation; `--gain` disc exposure; `--check` numerical physics test; `--mode fake` node-only proxy. Quick preview measured: approaching half 2.8× brighter than the receding half. |
| `make_warp_bubble.py` | Alcubierre **York-time** surface z = A·θ(x, y) as a displaced grid with vertex colours (blue = contraction, red = expansion), scrolling grid, bubble-wall shell, ship marker, `--form` flat → peak → flat shape key (the 8×1 sheet), `--quality` jitter for collapsing bubbles, `--stars` aberrated/Doppler world. |
| `render_sprites.py` | Packs a frame directory (`--frames-dir`) into a **sprite sheet + JSON manifest** (Pillow or numpy/bpy), round-trip verifies a tile, and produces **HEVC-with-alpha `.mov`** via ffmpeg (ProRes 4444) → `avconvert`. `--quick` self-test renders 16 frames of a pulsing ring and packs a 4×4 sheet. |

A separate Codex agent works in `blender/codex/` (`blackhole.py`, `sun.py`, `warp.py`, `shatter.py`,
`galaxies.py`, `planets.py`) and writes finals into `assets/`. Where the two overlap, the `assets/` file
that best passes the checks below wins; do not edit `blender/codex/`.

---

## 0. Environment facts (measured on this Mac, Blender 5.2.1 LTS)

- **Cycles on CPU works everywhere** (64 px probe: 1.5 s). **Cycles' Metal backend hangs inside sandboxed
  shells** (Claude Code's Bash tool; the probe never returned in 100 s). `--quick` therefore renders on the
  CPU by default (`--device AUTO`); final renders default to Metal and must be launched from Terminal, or
  with `--device CPU` / `FOLDSPACE_DEVICE=CPU` when scripted from Claude.
- **OSL runs on the CPU only** (`make_black_hole.py` forces it). Budget ~1024² × 8 samples × 360 frames.
- Blender 5.x API changes handled in `common.py`: `scene.compositing_node_group` (not `scene.node_tree`),
  glare type is the `Type` menu socket and its **Size is a 0–1 fraction of the frame** (the old 6–9 integer
  floods the whole image with bloom), slotted actions hide `action.fcurves` (`common.action_fcurves`),
  EEVEE engine id is `BLENDER_EEVEE`, `Scene.use_nodes` deprecated. EEVEE renders headless in the sandbox.
- OSL globals `P, I, N, u, v, …` are reserved; the tracer's inverse radius is `iu`.
- HEVC-with-alpha cannot be written by Blender's FFmpeg output; use `render_sprites.py --hevc`
  (ffmpeg → ProRes 4444 → `avconvert --preset PresetHEVC1920x1080WithAlpha`).
- Colour management: AgX view, look None. Never `Standard` for emissive scenes.

---

## 1. Planets

### Physics that must hold
- **Rayleigh rim**: single-scattering optical depth τ_c ∝ λ_c⁻⁴. With λ = 680 / 550 / 440 nm the weights are
  (440/680)⁴ : (440/550)⁴ : 1 = **0.175 : 0.41 : 1.0**. Scattered light 1 − e^(−τ·chord) is blue on short
  paths and whitens at the limb where the chord is long; transmitted sunlight e^(−τ·sec z) reddens toward the
  terminator (the sunset ring). Scale height H = 8.5 km = 1.3 × 10⁻³ R⊕ — far too thin to see, so the shell is
  drawn at 1.035 R and the brightness law, not the thickness, carries the physics. Day side only (n·L > 0).
- **Terminator**: Lambertian falloff, night side ~black; Earth only gets faint emissive city lights.
- **Gas giants**: zonal bands are a function of **latitude** (object-space z) with turbulence added to z —
  zonal flow, not longitude. Jupiter's Great Red Spot: anticyclone at **22° S**, ~1.3 Earth diameters wide,
  elongated along longitude. Saturn: paler, a dark ring-shadow band on the winter hemisphere. Uranus/Neptune:
  methane absorption bands at 619, 727, 890 nm remove red → teal (Uranus, `7CD4DE`) / azure (Neptune,
  `3F63D6`-ish), near-featureless with faint bands and rare white methane-ice storms.
- **Lava worlds** (Barnard d, TRAPPIST-1 b): thermal emission, Blackbody **1200–1800 K** (basalt liquidus
  ≈ 1450 K), masked to a crack network (Voronoi distance-to-edge) and lakes; dayside only if tidally locked.
- **Ice / ocean / desert / rocky**: polar caps beyond |lat| ≈ 60° (|z| > 0.85); deserts inside |lat| < 20°;
  ocean specular roughness ≈ 0.1–0.3 with continents; Voronoi craters on airless bodies; albedo colours from
  `UniverseData.colorHex`, no neon.
- **Tidal locking** (Proxima b/d, TRAPPIST-1 b–h): one fixed substellar hot spot in the texture is fine.

### Blender approach (`make_planet.py`)
- **Cycles** for the beauty renders (the Rayleigh shell is an emission-over-transparent shader using
  Geometry Incoming/Normal, so it also works in EEVEE with `surface_render_method = BLENDED`). Materials are
  pure nodes on `TexCoord.Object` so they **bake** cleanly: `bake_equirect()` runs a Cycles `DIFFUSE`
  (colour only) bake into a 2048×1024 image on the UV sphere, `EMIT` for lava.
- Node recipe: `sphere_coords` → Noise/Voronoi → `ramp` per class; `atmosphere_material` builds
  `per_channel_scatter` / `per_channel_transmit` with the weights above; `cloud_material` is a smoothstepped
  distorted noise on a 1.012 R shell; `ring_material` is a radial noise with the Cassini gap at 0.74–0.79.
- Optional upgrades: Principled Volume in a 1.02 R shell for true multiple scattering (Cycles, slow); a
  normal map from `Bump` height via a `NORMAL` bake for `planet-<id>-normal.png`.

### Render specs
`assets/textures/planet-<bodyid>.png` equirect **2048×1024 sRGB, no alpha**; optional `-normal.png`,
`-emissive.png`. Body ids and classes: `mercury` rocky, `venus` desert, `earth` earthlike, `mars` desert,
`jupiter`/`saturn`/`eps-eri-b` gasGiant, `uranus`/`neptune`/`wolf-359-b` iceGiant, `proxima-b`/`proxima-d`/
`barnard-b`/`barnard-c`/`barnard-e`/`trappist-1c` rocky, `barnard-d`/`trappist-1b` lava, `trappist-1d` desert,
`trappist-1e`/`trappist-1f` ocean, `trappist-1g`/`trappist-1h` ice, `tau-ceti-e`/`tau-ceti-f` superEarth.
Bake command: `make_planet.py -- --planet earthlike --bake --base-hex 3B82D6 --seed 5`, ~1 min per body on CPU.

### iOS hook
- `Foldspace/Scene/PlanetMaterials.swift`: `PlanetMaterials.texture(for: body, size:)` returns the
  `UIImage` that `material(for:)` puts on `diffuse.contents` (lava also `lavaEmissionTexture(for:)` →
  `emission.contents`). The dispatch is `private static func render(_ body:, size:)`; the one-line hook is
  "return `UIImage(named: "planet-\(body.id)")` if it exists, else the procedural path". Textures are square
  512² today but `SCNSphere` UVs are standard equirect (u around the equator, v pole to pole), so a 2:1 image
  drops in unchanged; the cache key is `"\(body.id)#\(size)"`.
- `Foldspace/Scene/SpaceScene.swift`: `addSphere` shows `placeholderMaterial` then `loadTextureAsync` →
  `applyTexture(forBodyID:)`, so a bundled PNG simply arrives faster. Rings: `PlanetMaterials.hasRings`
  (saturn, uranus) → `ringTexture(for:)` on an `SCNPlane` of width 4.8 R. Atmosphere shell:
  `addAtmosphere(color:radius:)` at 1.04 R — keep it; the baked albedo must **not** include the rim.
- Bundle: drop PNGs under `Foldspace/Resources/` (XcodeGen bundles every non-source file under `Foldspace/`)
  and run `xcodegen generate`. Only PNG/HEIC; no asset-catalog needed.

---

## 2. The Sun

### Physics that must hold
- **T_eff = 5772 K** (IAU 2015 nominal). Blackbody(5772) after AgX white balance ≈ (255, 240, 220): warm
  white, **not yellow**. The game's `SunLayer` table (`Foldspace/Game/GameStore.swift`) uses corona 1,000,000 K,
  chromosphere 20,000 K, photosphere 5,800 K, convective 2,000,000 K, radiative 7,000,000 K, core 15,000,000 K.
- **Granulation**: cells ~1000 km (1/700 R☉, lifetime 8–20 min, ~4 million on the disc). Drawn 10–20× too
  large so they read on a phone; bright centres (upflow, +3 % T), dark intergranular lanes.
- **Sunspots**: umbra ≈ **3800 K**, penumbra ≈ 5000–5500 K, confined to the activity belts |lat| 15–30°
  (Spörer's law); umbra ≈ 20 % of photospheric intensity in white light.
- **Limb darkening**: I(μ)/I(1) = **0.3 + 0.7 μ**, μ = cos(emission angle) (linear law, V band, u = 0.7;
  Cox 2000, *Allen's Astrophysical Quantities*; Neckel & Labs 1994). `make_sun.py` uses `LIMB_U = 0.7`.
- **Chromosphere**: 2000–3000 km (0.003–0.004 R☉) thick, Hα 656.3 nm pink-red, only visible at the limb.
- **Corona**: 1–2 MK, white-light brightness B(r)/B☉ = 0.0532 r⁻²·⁵ + 1.425 r⁻⁷ + 2.565 r⁻¹⁷ (Baumbach 1937,
  r in R☉) — ≈ 10⁻⁶ of the disc, so it is scaled ×10⁵ to be visible; streamers along a dipole-like field,
  brighter at the equator (helmet-streamer belt ∝ cos² latitude), extending to 2–3 R☉.
- **Prominences**: Hα loops 10⁴–10⁵ km (0.015–0.15 R☉) tall anchored on the limb.

### Blender approach (`make_sun.py`)
- **Cycles**, emission only (the Sun is the lamp). Photosphere: 4-D Voronoi F1 with two `W` values blended
  by `t/T` so the granulation **loops seamlessly** (`loop_noise_w`); temperature field → Blackbody; limb
  darkening from `Geometry.Normal · Incoming` (μ) driving emission strength; sunspot mask from a sparse
  Voronoi restricted to |z| < 0.5 with filament noise. Chromosphere: 1.012 R shell, (1 − μ)¹⁰ rim, Hα RGB.
  Corona: camera-tracked plane, Baumbach law in `r = |Object xy|·size/2`, streamers from 4-D noise in
  (cos φ, sin φ, ln r) space (seamless in angle), ×belt. Prominences: bevelled Bezier arches.
- Compositor bloom (glare BLOOM, threshold 2.0) sells the brightness; `--frames 240` gives an 8 s loop.
- `--dive 0..1` moves the camera from 6.2 R to inside the photosphere for `SunDiveView` backdrops.

### Render specs
`assets/textures/sun-photosphere.png` equirect 2048×1024 (bake the photosphere material with the same
`bake_equirect` pattern as the planets, `EMIT` pass), `assets/textures/sun-corona.png` 2048² RGBA (render the
corona plane alone with `--no-corona` inverted, i.e. hide the sphere, transparent film). Optional: a 240-frame
1024² loop for the hologram (`render_sprites.py --hevc`).

### iOS hook
- `PlanetMaterials.material(for:)` `.star` case: `diffuse = emission = texture(for: body)`,
  `emission.intensity = 0.55`, `lightingModel = .constant` → `sun-photosphere.png` replaces `renderStar` for
  `BodyID.sun` (`"sun"`). Sirius B (`sirius-b`, also `.star`) keeps the procedural white dwarf.
- `SpaceScene.rebuildBody` `.star`: `addSphere(segments: 56)` + `addHalo(color: baseColor, size: r*3.6,
  opacity: 0.95, falloff: 2.2)` — the halo is a billboard `SCNPlane` with `haloTexture`; swap its
  `diffuse.contents` for `sun-corona.png` (additive, `writesToDepthBuffer = false`) and raise `size` to ~r*6.
- `Foldspace/UI/Sequences/SunDiveView.swift`: `drawStar(context:size:depth:t:)` is pure `Canvas`
  (ramp gold → white → violet, granulation squares, rising plasma). A Blender `--dive` frame per layer
  (`SunLayer.depthStart` 0, 0.12, 0.22, 0.35, 0.62, 0.88) can be drawn first with
  `context.draw(Image(...), in: rect)` and cross-faded by `depth`, keeping the plasma pass on top.

---

## 3. Alcubierre warp bubble

### Physics that must hold
- Metric: ds² = −dt² + (dx − v_s f(r_s) dt)² + dy² + dz², r_s = √((x − x_s)² + y² + z²), with the smooth
  top-hat f(r) = [tanh(σ(r + R)) − tanh(σ(r − R))] / (2 tanh(σR)) (Alcubierre 1994, *CQG* 11, L73).
- **York time** (volume expansion of the spatial slices): θ = v_s (x_s / r_s) · df/dr_s, with
  df/dr = σ [sech²(σ(r + R)) − sech²(σ(r − R))] / (2 tanh(σR)). **θ < 0 ahead** (space contracts),
  **θ > 0 behind** (expands), **θ = 0 inside and far away** — passengers sit in flat space; the surface
  z = θ(x, y) on the equatorial slice is Alcubierre's famous figure.
- Energy density T⁰⁰ = −(1/8π) · v_s² ρ² / (4 r_s²) · (df/dr_s)² < 0 (ρ² = y² + z²): the "Exotic Matter"
  drive part in Act I is literally this requirement.
- View from inside: the interior is flat (no aberration); the **wall** blueshifts the forward sky and
  redshifts the aft sky and displaces stars toward the direction of travel (Clark, Hiscock & Larson 1999,
  *CQG* 16, 3965). The special-relativistic aberration d_rest = (d′ + [(γ − 1)(d′·v̂) − γβ] v̂) / (γ(1 − β d′·v̂))
  with D = 1/(γ(1 − β cos θ′)), I′ = D⁴ I, T′ = D·T is the tractable stand-in and is labelled as such.

### Blender approach (`make_warp_bubble.py`)
- **EEVEE** (fast, transparent film) — or `--engine CYCLES` where EEVEE has no GPU context. A 320×208 grid is
  displaced in numpy by z = A·θ/max|θ| (`york_time()`), vertex colours store sign and magnitude (`york`
  attribute), the shader draws scrolling grid lines (`FRACT`) tinted by the York colour with alpha ∝ |θ|;
  the grid advances an integer number of cells per loop so the sheet loops. `--form` animates a shape key
  0 → 1 (bubble forming) with sine easing; `--quality < 1` adds wall jitter + alpha flicker (collapsing).
  `--stars` renders opaque over the aberrated, Doppler-tinted starfield in the world shader.
- Geometry-nodes alternative for Astra: Grid → Set Position (z from a Math tree of the same formula) →
  Store Named Attribute; lets her tune R, σ, A live in the viewport.

### Render specs
`assets/sprites/warp-bubble-8x1.png` = 8 frames of 512² RGBA in a row, flat → contracted-ahead/expanded-behind
→ flat: render `--form --frames 8 --res 512 512` then `render_sprites.py --frames-dir out/warp_bubble --cols 8
--name warp-bubble-8x1`. Optional 60-frame 512² scrolling loop for the outer display.

### iOS hook
- `Foldspace/UI/Sequences/WarpSequenceView.swift`: `drawTransit(context:size:t:progress:mode:quality:)` is a
  `Canvas` — seam glow band at `seamY = size.height/2`, streaks converging on the seam, chromatic rings,
  arrival flash at progress > 0.92; `quality < 0.45` = `collapsing` (red, jittered). The sheet is stepped by
  `let frame = Int(min(7, progress * 8))` (or by `t` for a loop) and drawn with `context.draw(Image(...),
  in: rect)` after clipping to the tile `CGRect(x: frame*512, y: 0, width: 512, height: 512)`, centred on
  the seam and rotated so the bubble's +x (travel) points into the fold. Collapsing → the `--quality 0.3`
  variant sheet.
- `Foldspace/UI/Outer/OuterDisplayView.swift` `OuterFoldTunnel` (concentric ellipses rushing outward) can
  show the 60-frame loop while the phone is closed; `SpaceScene.setWarp(progress:active:)` drives the
  `warpSystem` particle streaks (`particleImage = haloTexture`) — a streak sprite from Blender is optional.

---

## 4. Sagittarius A* (the showpiece)

### Physics that must hold
- Units r_s = 2GM/c². M = 4.3 × 10⁶ M☉ → **r_s = 1.27 × 10¹⁰ m = 0.085 AU = 18 R☉**; distance 8.15 kpc; EHT
  (2022) ring diameter 51.8 ± 2.3 µas. Schwarzschild is acceptable (Sgr A* spin is poorly constrained);
  Kerr is a bonus (DNGR used a = 0.999 for Gargantua).
- **Photon sphere** r = 1.5 r_s; **apparent shadow radius** b_crit = √27/2 r_s = **2.598 r_s** (the photon
  capture impact parameter); **ISCO** 6GM/c² = **3 r_s** → the disc's inner edge is at 3 r_s, not the horizon.
- **Lensing**: photons from the far side of the disc are bent **over the top and under the bottom** of the
  shadow (primary image above, secondary below) — Luminet (1979) and James, von Tunzelmann, Franklin &
  Thorne (2015), *CQG* 32, 065001 (DNGR). A thin bright photon ring hugs the shadow edge; the background
  starfield forms an Einstein ring. This is physics, not style.
- **Doppler beaming**: Keplerian speed measured by a static observer β = √(r_s / 2(r − r_s)) → **β = 0.5 at
  ISCO**. g = ν_obs/ν_em = √(1 − r_s/r) · √(1 − β²) / (1 − β cos θ_v) (gravitational × kinematic); bolometric
  I_obs = **g⁴** I_em (I_ν/ν³ invariant; per band it is g³ — the brief's D³–D⁴), T_obs = g·T_em → the
  approaching side is brighter and bluer, the receding side dimmer and redder.
- **Gravitational redshift** alone: √(1 − r_s/r) = 0.816 at ISCO → colour reddens inward.
- **Disc**: Shakura–Sunyaev (1973) T ∝ r⁻³ᐟ⁴ (with the (1 − √(r_in/r))¹ᐟ⁴ factor the peak sits at
  49/36 r_in ≈ 4.1 r_s; art peak colour temperature `--tpeak 9000 K`), Ω ∝ r⁻³ᐟ² so turbulence shears —
  inner rings orbit faster.
- **Seamless loop**: rotation and noise advection are functions of frame/360 with **integer turns per
  ring**, so frame 360 == frame 0.

### Blender approach (`make_black_hole.py`)
- `--mode osl` (default, **Cycles CPU**): a camera-filling plane carries a Script node; for each shading
  point it integrates d²u/dφ² = −u + (3/2) r_s u² (u = 1/r, exact Schwarzschild) with RK4 from the camera,
  ends *captured* (shadow), *disc hit* (returns R, φ, cos θ_v) or *escaped* (direction samples the
  Environment starfield). `disc_shading()` applies β, g, g⁴, T ∝ r⁻³ᐟ⁴, Blackbody, loop-safe rotation and
  streak/ring noise in (cos φ_r, sin φ_r, ln R) space. `--check` bisects b_crit with the same integrator:
  **2.5981 r_s (PASS)**, β_ISCO = 0.5, g_face-on(ISCO) = 0.7071.
- `--mode fake` (GPU/EEVEE look-dev proxy): thin-lens warp β = θ − θ_E²/θ of the background, Doppler
  annulus with the same node math, photon-ring torus at 2.598 r_s, black sphere. No far-side lensing —
  for framing/colour only. The refractive-IOR-sphere trick from the brief was rejected (no shadow, no
  photon ring, wrong deflection profile) and is documented in the script header.
- Bloom via compositor glare; `--alpha-disc-only` makes the film transparent where stars would be, for the
  HEVC-alpha overlay; `--incl 12 --distance 22 --fov 46` frames the DNGR look.

### Render specs
`assets/video/blackhole-loop.mov` HEVC + alpha, **1080×1080, 30 fps, 12 s (360 frames)**:
`make_black_hole.py -- --frames 360 --res 1080 1080 --samples 8 --alpha-disc-only --out blender/out/bh`
then `render_sprites.py -- --frames-dir blender/out/bh/black_hole --hevc --no-sheet --name blackhole-loop`.
`assets/textures/blackhole-still.png` 2048² RGBA: `--res 2048 2048 --samples 16 --alpha-disc-only`.
CPU budget: ~10–15 s/frame at 1080² × 8 spp → ~1–1.5 h for the loop; start it early, render the still first.

### iOS hook
- `Foldspace/UI/Sequences/BlackHoleView.swift`: `drawScene(_:size:t:model:fold:)` is a `Canvas` in world
  units where `SlingshotModel.rs = 0.06` (6 % of min(w, h)) and `rsPx = rs * u`. Today it draws the horizon
  at `rsPx`, a black gradient to `1.5 rsPx`, a stroked "photon ring" at `1.5 rsPx`, and `drawAccretionDisc`
  (inner 1.75 rsPx, outer 4.4 rsPx, `scaleBy(y: 0.34)`, `rotate(−14°)`, Doppler half brighter). The movie
  goes **behind** the Canvas as an `AVPlayerLayer`/`VideoPlayer` (`AVPlayerLooper`, `hvc1` with alpha), centred
  on `toScreen(.zero)` and scaled so the movie's **shadow radius (2.598 r_s in Blender units) = 2.6 × rsPx**;
  then the Canvas keeps stars, lane, ship, ghost path and readouts and skips its own disc/horizon/ring.
  Note the current Canvas ring at 1.5 rsPx is the photon-*sphere* radius, not the apparent ring — the movie
  corrects this for free. Demo: `SIMCTL_CHILD_FOLDSPACE_DEMO=blackhole`.
- `Foldspace/Scene/SpaceScene.swift` `addBlackHole(_:radius:)` (cockpit hologram, `visualRadius` 0.72):
  shadow `SCNSphere`, photon-ring `SCNTorus` at 1.03 r on an `SCNBillboardConstraint`, inner emissive torus
  1.55 r, and an `SCNPlane` 5.4 r with `PlanetMaterials.accretionDiskTexture()` (additive) rotating every
  11 s. `blackhole-still.png` replaces the plane texture (billboarded); physically the torus should sit at
  2.6 r and the disc inner edge at 3 r if the shadow sphere is the horizon.

---

## 5. Spaghettification

### Physics
Tidal acceleration across a body of length L along the radial direction: **Δa ≈ 2GM·L / r³**. Sgr A* at the
horizon, L = 10 m: 2GM L / r_s³ = **5.6 × 10⁻³ m/s²** (harmless — a supermassive hole's tides are mild at the
horizon; lethal tides are far inside). A 10 M☉ hole (r_s = 29.5 km), L = 2 m at the horizon: ≈ 2 × 10⁸ m/s²
(2 × 10⁷ g). The game exaggerates for drama: `SlingshotModel.tidalStretch = 1 + 2 (rs/r)²` (r⁻², not r⁻³),
`underTidalStress` inside 3 r_s, `tidalSeverity` 0 → 1 between 3 r_s and the horizon; the ship path is
`scaleBy(x: stretch, y: 1/√stretch)` (area-preserving). Note the exaggeration in `assets/NOTES.md`.

### Blender approach / hook (optional)
16-frame ship-stretch sprite: a simple ship mesh with a Simple Deform (Stretch) keyed 1 → 3.5 along the
radial axis plus a Displace noise for hull shear, EEVEE, transparent, 256² frames → `render_sprites.py`.
Hook: replace the vector `hullPath` in `BlackHoleView.drawScene` with the sprite frame indexed by
`min(15, Int(model.tidalSeverity * 15))`.

---

## 6. Planet shatter

### Physics
Vacuum: **no drag, no slowdown**, debris flies in straight lines with constant angular velocity; impulse
∝ 1/(distance from impact) with a slight spin; larger chunks at the core. Silence in the asset.

### Blender approach
Cell Fracture add-on (enable `object_fracture_cell`): source = own vertices + 60–120 particle points,
recursion 1 for the core, `bpy.ops.object.add_fracture_cell_objects`; Rigid Body World with gravity 0 and
damping 0; initial velocities by keyframing frame 1 → 2 per chunk (or a Force Field: Force, negative, at the
impact point, then bake). 16 frames over ~1.8 s, EEVEE/Cycles, transparent film, 256² →
`render_sprites.py --cols 4 --name shatter-debris-4x4`. Codex's `shatter.py` already builds analytic
Voronoi cells without the add-on; reuse its frames if they pass review.

### iOS hook
`SpaceScene.shatter(bodyID:)` → `spawnBeam`, `spawnFlash`, `spawnFragments` (~40 textured tetrahedra with
ballistic `SCNAction`s). The sheet becomes an `SCNParticleSystem` behind them with
`particleImage = UIImage(named: "shatter-debris-4x4")`, `imageSequenceColumnCount = 4`,
`imageSequenceRowCount = 4`, `imageSequenceFrameRate = 9`, `imageSequenceAnimationMode = .clamp`,
`birthRate` one burst, `emitterShape` the sphere. `WeaponView.drawFiring` (SwiftUI) keeps its flash/rings.

---

## 7. Galaxies: Milky Way and Andromeda

### Physics that must hold
- **Density-wave spirals** (Lin & Shu 1964): arms are a pattern, not material; log-spiral
  r(φ) = a·e^(bφ) with **b ≈ 0.2–0.3** (pitch angle ψ = arctan b ≈ 11–17°; the Milky Way's is ~12–13°).
  Star density boosted along arms; young blue stars and pink Hα (H II) knots on the arms; dust lanes dark on
  the arms' inner (concave) edges; the bulge is old and yellow.
- **Milky Way**: barred spiral SBbc, stellar disc ~100 kly (≈ 30 kpc) across, central bar ~27 kly long,
  4 major arms (Perseus, Scutum–Centaurus, Norma, Sagittarius) + the Orion Spur; Sun at 8.2 kpc = 26,700 ly
  (the game's Sgr A* distance 26,670 ly). Edge-on band for the galaxy map: thin disc + dust lane + bulge.
- **Andromeda (M31)**: SA(s)b, ~220 kly across, **inclination 77°** from face-on (position angle ~38°), the
  10 kpc dust/star-formation ring plus an inner ring, a yellower bulge, satellites M32 (cE2) and M110 (dE5).
  Merger with the Milky Way begins in ~4.5 Gyr.

### Blender approach
Cycles emission-only scene: **Geometry Nodes** point cloud (Distribute Points in Volume on a thin disc, density
∝ exp(−r/h) × [1 + A·cos(m(φ − ln(r/a)/b))] via a Math tree, m = 2 or 4), instanced as tiny emissive
spheres with colour from radius (blue arms, yellow bulge) plus a second sparse set of pink H II points; dust as
a dark Principled Volume (or an emission × (1 − noise) plane) along the same spiral phase shifted inward.
Camera orthographic from +z for face-on 4096²; for M31 either rotate the camera to 77° or leave face-on and let
the app squash it (both provided). Edge-on: camera in the plane, 4096×1024. Alternative: a 2-D procedural
shader on a plane (`ARCTAN2`, `LOGARITHM` → spiral phase) — faster, fine for the backdrop.

### Render specs
`assets/textures/galaxy-milkyway.png`, `galaxy-andromeda.png` 4096² RGBA face-on, transparent background;
`galaxy-milkyway-edge.png` 4096×1024 RGBA. 128 samples, denoise on. (Codex's `galaxies.py` already produced
candidates in `blender/codex/out/galaxies/`.)

### iOS hook
- `SpaceScene.addGalaxy(_:radius:)`: an `SCNPlane` 3.6 r (r = 1.1 for `.galaxy`) with
  `PlanetMaterials.material(for:)` `.galaxy` → `galaxyTexture()` (additive, double-sided, no depth write),
  tilted `−(π/2 − 0.6)` and rotating every 140 s, plus a warm halo. `galaxy-andromeda.png` replaces
  `galaxyTexture()` for `BodyID.andromedaGalaxy` (`"m31"`).
- `Foldspace/UI/Sequences/AndromedaFinaleView.swift` `drawScene` / `drawGalaxy(...)`: Canvas spirals —
  Milky Way at the bottom (`arms: 4`, `tilt: 0.34`, receding), Andromeda at the top (`arms: 2`, `tilt: 0.42`,
  growing over `approach = 9 s`). Draw the PNGs with `context.draw(Image, in:)` after `scaleBy(y: tilt)`;
  physically M31's tilt is cos 77° = **0.22** — keep 0.42 for readability and note the deviation.
- `WarpSequenceView.drawGalaxySilhouette` (intergalactic fold) and `GalaxyMapView` step 2 ("Milky Way band",
  a blurred quad curve) take `galaxy-milkyway.png` / `galaxy-milkyway-edge.png` the same way.
- `SpaceScene.buildStarfield` (sphere r = 70, `starfieldTexture()` 1024×512) can take the tone-mapped
  `starfield.exr` → PNG from `common.starfield_image` for a consistent sky across scenes.

---

## 8. Time-dilation clock

dτ/dt = **√(1 − r_s/r)**; the Earth clock runs 1/√(1 − r_s/r) × the ship clock: 1.22× at 3 r_s, 3.3× at
1.1 r_s, 10× at 1.01 r_s. In the game: `SlingshotModel.timeDilation = 1 / max(0.02, 1 − rs/r).squareRoot()`,
accrued as `store.addEarthYears(dt · timeDilation · 0.5)` per frame, shown in the `BlackHoleView` readouts.
Optional asset: a looping HUD ring (two hands, Earth hand ×γ) rendered in EEVEE at 256², 60 frames, with
γ read from the file name; or leave it in SwiftUI (already correct).

---

## 9. Who does what (one evening, 18:00–23:00)

### WHAT CLAUDE DOES (scriptable: bpy builders, batch renders, packing, export, physics checks)

| # | Task | Est. | Output / check |
|---|---|---|---|
| C1 | **Black hole still** `make_black_hole.py -- --res 2048 2048 --samples 16 --alpha-disc-only --device CPU`; verify shadow radius ≈ 2.6 r_s in pixels from `png_stats` + a row scan, ring above/below present | 30 min render (background) | `assets/textures/blackhole-still.png` |
| C2 | **Black hole loop** 360 × 1080² × 8 spp CPU in the background; frame 1 vs 360 diff < 1/255; `render_sprites.py --hevc` → `.mov`; probe with `avconvert`/`ffprobe` for `hvc1` + alpha | 60–90 min render, 10 min pack | `assets/video/blackhole-loop.mov` |
| C3 | **Sun** photosphere bake (EMIT, 2048×1024) + corona 2048² RGBA + 240-frame loop; check mean colour ≈ warm white, limb ratio I(edge)/I(centre) ≈ 0.3 | 25 min | `sun-photosphere.png`, `sun-corona.png` |
| C4 | **Warp sheet** `--form --frames 8 --res 512 512` → 8×1 pack; log θ(0,0) ≈ 0 and sign map (blue ahead, red behind) | 15 min | `warp-bubble-8x1.png` + `.json` |
| C5 | **Planet bakes** for earth, jupiter, mars, proxima-b, trappist-1e, neptune (then the rest, `--base-hex` from `UniverseData.colorHex`); check no rim/alpha in the albedo, lava emission map present | 6 × 1 min + 20 × 1 min | `planet-<id>.png` (+ `-emissive`) |
| C6 | **Galaxies**: either adopt Codex's `galaxies.py` outputs or build the GN spiral; check pitch angle by fitting ln r vs φ on the arm ridge (b within 0.2–0.3), M31 tilt file provided both ways | 30 min | `galaxy-*.png` |
| C7 | **Shatter sheet** (Cell Fracture or Codex frames) packed 4×4; verify straight-line motion (centroid vs frame linear, R² > 0.99) | 20 min | `shatter-debris-4x4.png` |
| C8 | **Export to Xcode**: copy `assets/**` → `Foldspace/Resources/`, `xcodegen generate`, `xcodebuild … build`, write the loader hooks named above (`PlanetMaterials.render`, `addHalo` corona, `addGalaxy`, `BlackHoleView` player, `WarpSequenceView` tiles) | 45 min | app builds, assets visible |
| C9 | `assets/NOTES.md`: per asset physics encoded, parameters, deviations (disc tilt, granule size ×15, corona ×10⁵, M31 tilt 0.42 vs 0.22, tidal r⁻²), render time, command | 20 min | `assets/NOTES.md` |
| C10 | Re-run every `--quick` after each script change; keep `blender/out/` gitignored, commit only `assets/` | ongoing | green quick runs |

### WHAT ASTRA DOES (art direction, look-dev, camera + lighting, sim tuning, review vs reference, finals)

| # | Task | Est. | Notes |
|---|---|---|---|
| A1 | **Black hole look-dev** on the `--mode fake --engine EEVEE` proxy in the viewport (open `--save-blend` output): `--tpeak`, `--incl` (DNGR used ~10–15°), `--rout`, streak scale, bloom; then confirm on 3–4 OSL frames | 45 min | Reference: Luminet 1979 fig., DNGR fig. 15, EHT Sgr A* 2022 |
| A2 | **Sun** art pass: granule scale (readability vs 1000 km truth), spot count, corona streamer contrast, prominence placement; approve the warm-white (not yellow) disc | 30 min | Reference: SDO/HMI continuum, eclipse corona photos (Druckmüller) |
| A3 | **Warp bubble** camera and colour: angle so the fold line reads as the bubble's travel axis; blue/red intensity; grid density (`--cells`); collapsing variant jitter amount | 20 min | Alcubierre 1994 fig. 1 |
| A4 | **Planets** review vs reference per class (Jupiter belts/zones and GRS latitude, Neptune blue depth, Earth cloud coverage ~50–60 %, ice-cap latitude); pick seeds; approve `--base-hex` overrides | 40 min | NASA fact sheets, JunoCam colour |
| A5 | **Galaxies** review: arm count, pitch, bar visibility, dust lane placement, M31 ring at 10 kpc, bulge colour; decide readability tilt for the finale | 30 min | GALEX/Spitzer M31, Gaia-based MW face-on maps (reference only) |
| A6 | **Shatter sim tuning** (chunk count, core chunk size, impulse falloff, spin) and light rig for readable facets | 30 min | Cell Fracture recursion + rigid body |
| A7 | **Final renders** launched from Terminal (Metal): planets EEVEE/Cycles 2048×1024, galaxies 4096² 128 spp, sun loop; hand `.png/.mov` back into `assets/` | 60 min wall, mostly waiting | keep every final under ~10 min except the OSL loop |
| A8 | **Integration review** on device/simulator: seam alignment of the bubble, movie scale vs `rsPx`, corona size in the hologram, texture seams at −X on the spheres | 30 min | `SIMCTL_CHILD_FOLDSPACE_DEMO=blackhole|sun|warp|andromeda` |

### Minimum viable stunning (if only ~2 hours)
1. **Black hole**: C1 still now (frames the demo), C2 loop in the background all evening, A1 look-dev on the
   fake proxy while it renders. Without the loop, the still behind `BlackHoleView` already replaces the Canvas
   disc.
2. **Sun**: C3 + A2 — photosphere + corona textures into the hologram (`addHalo` swap) and the `SunDiveView`
   backdrop.
3. **Warp bubble**: C4 + A3 — the 8-frame sheet on the fold seam in `WarpSequenceView`.
Then C8 to get all three on the phone, C9 notes; planets and galaxies are the stretch.

### Physics acceptance checks (Claude runs, Astra signs off)
- `make_black_hole.py -- --check` → b_crit 2.598 r_s PASS, β_ISCO 0.5, g 0.7071.
- Still: measured shadow radius / (camera pixels per r_s) = 2.6 ± 0.1; ring visible above and below.
- Doppler: mean luminance of the approaching half ≥ 2.5× the receding half across the disc band (g⁴ with
  β = 0.5, cos θ_v ≈ ±1 → (1.5/0.5)⁴ ≈ 81× at the extreme; the 256 px quick preview measures 2.8× after AgX).
- Sun: I(μ = 0.05)/I(1) between 0.30 and 0.36 on a horizontal row through the centre.
- Warp: `York time θ` log line: interior |θ| at origin < 10⁻⁶ × max|θ|; z < 0 for x > 0 (ahead), z > 0 for x < 0.
- Planets: albedo PNG has no alpha, mean luminance within ±30 % of `colorHex`, seam-free at u = 0/1.
- Galaxies: arm ridge fit gives b ∈ [0.2, 0.3]; M31 face-on/inclined pair provided.
- Shatter: fragment centroid tracks are straight lines (no deceleration).
