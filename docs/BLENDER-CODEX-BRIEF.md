# FOLDSPACE — Blender visuals brief (for OpenAI Codex / Astra)

**Goal:** produce physically faithful, stunning space visuals in Blender that drop straight into the FOLDSPACE iOS app (SwiftUI + SceneKit). Everything below is self-contained: you do not need the rest of this conversation.

**Ground rules**
- Blender 5.2.1 LTS is installed: `/Applications/Blender.app/Contents/MacOS/Blender --background --python <script.py> -- [args]`.
- Work **only** in `blender/codex/` (your scripts) and `assets/` (your outputs). **Do not edit any `.swift` file**, `project.yml`, or `blender/*.py` (those are written by a separate agent; read them if useful).
- Every script must run headless and accept `-- --quick` for a fast 256 px preview render (< 60 s), and `-- --final` for the full-res output. Put previews in `blender/codex/out/`.
- No copyrighted reference imagery in the repo. Procedural or from-equation only. NASA/ESA imagery is public domain but keep it out of the repo anyway; use it only as a visual reference.
- "Theoretical-astrophysics approved" means: the physics in the table below must hold in the render. Note every deliberate deviation in `assets/NOTES.md` with the reason (e.g. "disc tilt exaggerated to 30° for readability").

---

## Deliverables (exact paths; the app looks for these names)

| # | Asset | Path | Spec |
|---|---|---|---|
| 1 | Planet textures (one per body id) | `assets/textures/planet-<bodyid>.png` | Equirectangular **2048×1024**, sRGB PNG, no alpha. Optional `planet-<bodyid>-normal.png` and `planet-<bodyid>-emissive.png` (lava/cities). |
| 2 | Sun surface | `assets/textures/sun-photosphere.png` | Equirect 2048×1024, granulation + sunspots; plus `sun-corona.png` 2048×2048 RGBA radial corona/streamers (transparent background) for a billboard. |
| 3 | Black hole loop (Sagittarius A*) | `assets/video/blackhole-loop.mov` | **HEVC with alpha** (Blender: FFmpeg → QuickTime, codec H.265, RGBA), **1080×1080**, 30 fps, **12 s seamless loop**, transparent background (only the shadow, photon ring, and disc are opaque). Also `assets/textures/blackhole-still.png` 2048² RGBA. |
| 4 | Warp bubble sprite sheet | `assets/sprites/warp-bubble-8x1.png` | 8 frames in a row, each **512×512** RGBA, of the Alcubierre York-time surface animating from flat → contracted-ahead/expanded-behind → flat. |
| 5 | Galaxies | `assets/textures/galaxy-milkyway.png`, `assets/textures/galaxy-andromeda.png` | **4096×4096** RGBA, face-on spiral with transparent background; plus `galaxy-milkyway-edge.png` 4096×1024 RGBA (edge-on band for the galaxy-map backdrop). |
| 6 | Planet-shatter debris sheet | `assets/sprites/shatter-debris-4x4.png` | 16 frames 256², RGBA, generic rock fragments dispersing (used as a particle sprite behind the 3D shatter). |
| 7 | Notes | `assets/NOTES.md` | For each asset: what physics is encoded, parameters used, deviations, render time, and the command that produced it. |

**Body ids (for #1):** `mercury venus earth mars jupiter saturn uranus neptune proxima-b proxima-d barnard-b barnard-c barnard-d barnard-e wolf-359-b sirius-b eps-eri-b tau-ceti-e tau-ceti-f trappist-1b trappist-1c trappist-1d trappist-1e trappist-1f trappist-1g trappist-1h`. Classes and colours are in `Foldspace/Universe/UniverseData.swift` (read it: `planetClass`, `colorHex`, `temperatureK`, `habitable`). Priority order if time is short: **earth, jupiter, mars, proxima-b, trappist-1e, neptune**, then the rest.

**How the app consumes them (so you know the contract):** SceneKit maps `planet-<id>.png` as the sphere's diffuse on a UV sphere (equirect, seam at −X). `sun-photosphere.png` goes on an emissive sphere; `sun-corona.png` on a camera-facing billboard behind it. The black hole `.mov` plays behind a SwiftUI Canvas in `BlackHoleView`. The warp sheet is stepped through by `WarpSequenceView`. Galaxy PNGs are textured planes in `SpaceScene` (Andromeda finale) and the galaxy-map backdrop.

---

## Physics that must hold (per visual)

### 1. Planets
- **Blackbody/colour sanity:** albedo colour from class; no neon. Terminator has a soft falloff; night side ~black (add faint emissive city lights only for Earth).
- **Earthlike atmosphere:** thin **Rayleigh-scattering rim** (blue limb brightening, reddening at the terminator). In Cycles: a slightly larger sphere with a Volume Scatter (density ∝ e^(−h/H), H ≈ 8.5 km scaled) or a Principled Volume; in EEVEE: a Fresnel-driven emissive rim shader, blue, weight ∝ (1 − dot(N,V))^4.
- **Gas giants:** **zonal bands** (latitude-parallel, alternating light zones/dark belts), band-edge turbulence via noise distorted along longitude; Jupiter: Great Red Spot ~22° S; Saturn: paler, ring shadow band; Uranus/Neptune: methane absorption → teal/azure, near-featureless with faint bands.
- **Lava worlds** (e.g. tidally-locked close-in rocky planets): dayside emissive cracks at 1200–1800 K (orange-white), nightside dark.
- **Ice / ocean / desert / rocky:** polar caps on ice/rocky; specular ocean (roughness ~0.1) with continents; craters via Voronoi on airless rocky bodies.
- **Tidal locking:** for Proxima b / TRAPPIST-1 planets, one fixed substellar hot spot in the texture is acceptable.

### 2. The Sun
- Photosphere **T = 5772 K** → blackbody colour ~ (255, 240, 220) *after* white balance; do not render it pure yellow.
- **Granulation:** ~1000 km cells (Voronoi, ~40–60 cells across the disc), bright cell centres, dark lanes; **sunspots** (dark umbra ~3800 K, lighter penumbra) in two bands ±15–30° latitude.
- **Limb darkening:** I(μ)/I(1) ≈ 0.3 + 0.7·μ (μ = cos of emission angle) — implement with a Layer Weight/Fresnel node driving emission strength.
- **Chromosphere** thin pink-red (Hα 656 nm) rim; **corona** 1–2 MK: faint, streamers along a dipole-like field, extends to ~2–3 solar radii; **prominences** as loops from the limb.

### 3. Alcubierre warp bubble
- The metric: ds² = −dt² + (dx − v_s f(r_s) dt)² + dy² + dz². Visualise the **York time θ = v_s (x_s / r_s) df/dr_s**: **contraction of space in front** of the ship (θ < 0) and **expansion behind** (θ > 0), **flat interior**. Render the "rubber sheet" surface z = θ(x, y) as an animated displaced grid, colour-coded (blue = contraction, red = expansion), with f(r) a smooth top-hat (Alcubierre's tanh form: f = [tanh(σ(r+R)) − tanh(σ(r−R))] / [2 tanh(σR)]).
- Starfield seen from inside the bubble: no relativistic aberration of the *interior* (it's flat), but the **wall** distorts the outside view — show lensing/streaking of stars only at the bubble wall.
- Source: Alcubierre, M. (1994) *Class. Quantum Grav.* 11, L73.

### 4. Sagittarius A* (the showpiece)
- Non-rotating (Schwarzschild) is acceptable; Kerr is a bonus. Units: r_s = 2GM/c². Mass 4.3×10⁶ M☉ → r_s ≈ 1.27×10¹⁰ m ≈ 0.085 AU.
- **Shadow** apparent radius ≈ 2.6 r_s (photon capture radius √27 GM/c²); **photon ring** at r = 1.5 r_s (thin, bright); **ISCO** at 3 r_s → the accretion disc's inner edge sits at 3 r_s, not at the horizon.
- **Gravitational lensing:** the far side of the disc appears **above and below** the shadow (the "Interstellar" look). This is *physics*, not style. Approaches, in order of fidelity:
  1. **OSL ray-bending shader in Cycles** (best): trace null geodesics in the equatorial approximation, or use the Luminet/Interstellar-style thin-disc mapping.
  2. **Refractive-sphere trick** (fast, EEVEE-compatible): a transparent sphere with a radially varying IOR (Fresnel-driven refraction ramp) around the black disc to bend the disc image over/under the shadow. Document that it is an approximation.
- **Relativistic Doppler beaming:** the approaching side of the disc is **brighter and bluer** by factor D³–D⁴ (D = 1/[γ(1 − β cosθ)]) with orbital β ≈ 0.5 at 3 r_s; the receding side dimmer and redder. Implement as an emission multiplier from the dot product of the disc's tangential velocity and the view vector.
- **Gravitational redshift:** emission colour shifts redder toward the inner edge, ∝ √(1 − r_s/r).
- Disc temperature profile (Shakura–Sunyaev thin disc): T ∝ r^(−3/4); colour from blackbody node; turbulent brightness noise advected with the orbital shear (inner rings orbit faster: Ω ∝ r^(−3/2)).
- **Loop seamlessly**: build the disc rotation and noise advection as functions of frame/360 so frame 360 == frame 0.
- Source: James, von Tunzelmann, Franklin & Thorne (2015), *Class. Quantum Grav.* 32, 065001 (the DNGR paper); EHT Collaboration (2022) Sgr A* results.

### 5. Spaghettification
- Tidal acceleration across a ship of length L: **Δa ≈ 2GM·L / r³**. For a stellar-mass hole this is lethal well outside the horizon; for Sgr A* (supermassive) tidal forces at the horizon are mild — the game exaggerates for drama. Provide a 16-frame ship-stretch sprite (optional) and note the exaggeration in `NOTES.md`.

### 6. Planet shatter
- Cell Fracture add-on (Voronoi, 60–120 chunks, larger chunks at the core), rigid-body sim with an outward impulse ∝ 1/distance-from-impact, slight rotation, **no atmosphere drag** (vacuum), debris keeps moving in straight lines (no slowdown). Silence (no sound cue in the asset). Render 16 frames as a sprite sheet on transparent background.

### 7. Galaxies
- **Milky Way:** barred spiral (SBbc), ~100 kly disc, bar ~27 kly, 4 major arms (Perseus, Scutum–Centaurus, Norma, Sagittarius) + Orion spur; yellow-white bulge, blue-white arms with pink Hα knots, dark dust lanes; central bar visible face-on.
- **Andromeda (M31):** larger (~220 kly), two prominent arms/rings, tilt **77°** from face-on, dust ring at ~10 kpc; bulge more yellow than the Milky Way's. Two satellites (M32, M110) as small ellipticals.
- Build with density-wave spiral: arm pattern r(φ) = a·e^(bφ) (b ≈ 0.2–0.3), stars as point cloud with arm density boost, dust as dark noise along arms, in a Cycles emission-only scene; or a 2-D procedural shader on a plane.

### 8. Time-dilation clock
- Gravitational: dτ/dt = √(1 − r_s/r). Provide a small looping HUD ring animation (optional) where Earth-clock speed = 1/√(1 − r_s/r) × ship-clock.

---

## Render defaults
- Cycles for the black hole + Sun + galaxies (path tracing, denoise on, 128–512 samples final / 8 for `--quick`); EEVEE Next for planets (fast).
- Colour management: **AgX** (Blender default) or Filmic; **do not** use Standard for bright emissive scenes.
- Transparent film for everything meant to be composited (RGBA PNG / HEVC-alpha).
- Keep every render under ~10 min at final settings on an Apple Silicon Mac; cap samples accordingly.

## Order of work (if time is short)
1. **Black hole loop** (the demo showpiece) — still first (`blackhole-still.png`), then the 12 s loop.
2. **Sun** photosphere + corona.
3. **Earth, Jupiter, Mars, Proxima b, TRAPPIST-1e, Neptune** textures.
4. Warp bubble sheet.
5. Andromeda + Milky Way.
6. Shatter sheet, remaining planets.

When an asset is done, commit it on branch `assets` (or hand over the `assets/` folder). The iOS side will add the loaders: `PlanetMaterials` will prefer `planet-<id>.png` over its procedural texture when the file exists in the bundle.
