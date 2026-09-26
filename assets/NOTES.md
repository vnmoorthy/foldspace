# FOLDSPACE — completed Blender asset handoff

Generated for `docs/BLENDER-CODEX-BRIEF.md`, 26 September 2026.

All required deliverables are present: **34 required PNGs and one HEVC-alpha movie**.
Extras include seven planet emission/roughness maps and a 77° inclined Andromeda
image, for **42 PNGs plus one movie** (about **111.14 MiB** of media). Every image
is procedural or computed from equations. No reference imagery was downloaded.

- [Visual overview](PREVIEW.png)
- [Machine-readable validation and SHA-256 hashes](manifest.json)
- [Black-hole movie](video/blackhole-loop.mov)
- Generators and replay instructions: `blender/codex/README.md`.

## Delivery and integration

The assets are handed over in this folder, as permitted by the brief. No asset
branch switch is required in the shared checkout. The original generation work
was confined to `assets/` and `blender/codex/`. Following the user's request to
continue, the iOS integration now connects these resources to the app views.

| Asset | Exact output | Contract |
|---|---|---|
| 26 bodies | `textures/planet-<bodyid>.png` | 2048 × 1024, RGB, sRGB, equirectangular |
| Sun | `textures/sun-photosphere.png` | 2048 × 1024, RGB, equirectangular |
| Corona | `textures/sun-corona.png` | 2048 × 2048, straight RGBA |
| Black-hole still | `textures/blackhole-still.png` | 2048 × 2048, straight RGBA |
| Black-hole loop | `video/blackhole-loop.mov` | 1080 × 1080, HEVC with alpha, 30 fps, 360 frames, 12 s |
| Warp atlas | `sprites/warp-bubble-8x1.png` | 4096 × 512; eight 512² tiles, left to right |
| Galaxy planes | `textures/galaxy-milkyway.png`, `textures/galaxy-andromeda.png` | 4096², straight RGBA, face-on |
| Milky Way band | `textures/galaxy-milkyway-edge.png` | 4096 × 1024, straight RGBA |
| Debris atlas | `sprites/shatter-debris-4x4.png` | 1024²; sixteen 256² tiles, top-left, row-major |

The explicit body list in the brief has **26 IDs**, including Sirius B. Sirius B
is a white dwarf and needs the stellar emission material despite its required
`planet-sirius-b` filename.

The regenerated Xcode project includes every media filename and the new loaders.
`BlackHoleView` places the transparent loop between its background and gameplay
layers, keeps a still until playback is ready, and uses the still for Reduce Motion.
Warp and debris views step through the atlases. Galaxy views use the authored
planes and edge band. Planet materials load roughness and emission companions,
mask Earth's lights to the night side, and apply stellar limb darkening. The Sun
has its corona billboard and a photosphere patch in the dive sequence.

See [material integration](review-materials.md) and
[sequence integration](review-sequences.md) for implementation details and visual
acceptance checks. Build and runtime verification are recorded in
`blender/codex/INTEGRATION.md`; integration does not imply a completed Bitrig check.

Treat diffuse/emission PNGs as sRGB and roughness companions as linear data.
Keep the planet UV seam at −X, with north at the top. There is no baked planet
illumination: atmosphere rims, stellar lighting, night masks, ring shadows, and
Sun limb darkening belong in runtime materials. Read the asset sections below
for the exact assumptions, map orientation, scales, and deliberate departures.

## Validation and reproducibility

`blender/codex/validate_assets.py --final` checks all required paths, dimensions,
PNG modes, alpha coverage, atlas content, and movie format/timing. Planet maps
also passed CRC, color-tag, UV-seam, and pole checks. Final rendered images were
visually reviewed. Apple AVFoundation decoded every movie frame and confirmed
the auxiliary alpha layer; FFmpeg's base-layer pixel-format report alone is
insufficient for Apple HEVC alpha. Native results are embedded in `manifest.json`.

The six generators accept headless `-- --quick` and `-- --final`. Quick runs
write previews below `blender/codex/out/`. Run large jobs sequentially using
`render_all.py` to avoid memory contention; final emission-plane renders have
denoising disabled because it removed detail and exhausted memory without
improving these deterministic images. Individual command lines and measured
runtimes follow. The optional ship-stretch and time-dilation HUD animations
were not part of the required set and are not included.

---

## Sagittarius A*: still and transparent movie

Outputs: `textures/blackhole-still.png` (2048 × 2048, straight RGBA) and
`video/blackhole-loop.mov` (1080 × 1080, 30 fps, 360 frames / 12 seconds, HEVC with alpha).

### Physics and parameters

`blender/codex/blackhole.py` traces Schwarzschild null geodesics numerically. In units
of the Schwarzschild radius, `u = r_s / r`, the ray equation is
`u'' + u = 1.5 u²`. Fourth-order Runge–Kutta integration starts at an observer at
infinity with `u = 0`, `u' = 1/b`. Spherical symmetry lets each ray travel in its own
plane. The script intersects that curved trajectory with the equatorial emitting
disc up to three times, retaining the first intersection within the disc. This
produces the upper and lower lensed images from the actual ray trajectories.

- Mass: 4.3 million solar masses; `r_s ≈ 1.27 × 10¹⁰ m ≈ 0.085 AU`.
- Captured rays have impact parameter `b < sqrt(27)/2 ≈ 2.598 r_s`. They are black
  with opaque alpha, except where emitting foreground disc material intercepts them.
- The physical photon orbit is at **1.5 r_s**. Its apparent critical curve for a
  distant observer is at **2.598 r_s**. These are different radii; the photon ring
  is drawn at the apparent radius, not at 1.5 r_s in image coordinates.
- The inner disc edge is the Schwarzschild ISCO at **3 r_s**; the outer edge is
  **10.8 r_s**. Inclination is **78° from the disc normal**. Image half-width is
  **12 r_s**. The outermost 1.25 r_s fades smoothly for compositing.
- Local orbital speed: `beta = 1 / sqrt(2 (r/r_s − 1))`, giving `beta = 0.5` at ISCO.
  The emitted ray direction is evaluated in a local static orthonormal frame.
  `D = sqrt(1 − beta²) / (1 − beta cos(theta))` and
  `g = sqrt(1 − r_s/r) D`. Approaching material is brighter and bluer.
- Temperature: `T = 11500 K (r / 3 r_s)^(-3/4)`; the observed color uses `g T`.
  Brightness follows the bolometric `g⁴` factor and `r⁻³` radial profile.
  A Planck spectrum is integrated over 380–780 nm against the analytic CIE observer
  fits of [Wyman et al. (2013)](https://jcgt.org/published/0002/02/01/), then converted to linear Rec.709. Blender's AgX view transform with
  Medium High Contrast maps this radiance to the final sRGB PNGs.
- Seed-free analytic turbulence follows azimuth with radial shear. The desired
  orbital cycle count is `5 (3 r_s/r)^(3/2)`. Blending the neighboring integer
  temporal harmonics approximates this continuous shear while guaranteeing that
  phase 1 is exactly phase 0. Frames 0–359 are encoded; the duplicate endpoint is
  excluded. This is an accelerated display animation, not a real-time Sgr A* orbit.

### Deliberate approximations

This is a numerical, thin, optically thick Schwarzschild disc model inspired by
[Luminet (1979)](https://articles.adsabs.harvard.edu/pdf/1979A%26A....75..228L).
The brief permits Schwarzschild; spin and frame dragging are absent. See
[James et al. (2015)](https://arxiv.org/abs/1502.03808) for the more complete Kerr
ray-bundle treatment. This script does not implement DNGR or OSL.

Sgr A* actually has a hot, sparse accretion flow; this visible-light thin disc and
its 11500 K display temperature are a cinematic teaching model, not a prediction
of its observed optical appearance or the EHT radio image. There is no accretion
rate fit, radiative-transfer simulation, polarization, scattering, or finite disc
thickness. The simple temperature law omits the zero-torque inner-boundary term.

The unresolved higher-order photon subrings are supplemented by a narrow Gaussian
at the critical curve, with width `max(0.02 r_s, 0.7 pixel)`. A faint 0.16 r_s
halo mimics the display point-spread function. Both make the critical curve readable
at phone resolution; they are not emitting plasma inside the ISCO. Only three
disc-crossing orders are sampled. The direct disc image retains its physical
Doppler asymmetry; the supplemental subring glow uses a fixed warm chromaticity.

The numerical geodesic renderer replaces Cycles path integration for this asset.
Blender provides the image and AgX export pipeline. This is deliberate: ordinary
Cycles rays are straight and would not provide Schwarzschild lensing. There is
no denoising or Monte Carlo sample budget because the solution is deterministic.

### Reproduce

From the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --threads 4 --python blender/codex/blackhole.py -- --quick
/Applications/Blender.app/Contents/MacOS/Blender --background --threads 4 --python blender/codex/blackhole.py -- --final
```

`--still-only` skips the movie. `--resume` preserves the final still and completed
frames under `blender/codex/out/blackhole/frames/`; use it only with unchanged
render parameters. Quick mode produces a 256 px preview. Measured quick render
time was under one second after Blender startup. Full timing is recorded in
`blender/codex/out/blackhole/final-report.json`; the first run was interrupted to
reduce memory contention, then resumed from its completed frames.

The movie uses FFmpeg's **macOS VideoToolbox** HEVC encoder with BGRA input,
`-alpha_quality 1`, a 12 Mbit/s target, and `hvc1` in a QuickTime container.
Ordinary `libx265` output would lose alpha. The native encoder and Blender's Metal
initialization require normal macOS process access outside Codex's restricted
sandbox on this machine.

### Verification

The solver checks the null-ray first integral
`(u')² + u² − u³ = 1/b²` and exact equality between generated phases 0 and 1.
The quick calculation's maximum relative first-integral error near the hole was
`1.5 × 10⁻¹⁰`; the total redshift factor spanned about `0.478–1.371`.

The movie is decoded through AVFoundation with
`blender/codex/verify_movie.m` to confirm the auxiliary alpha layer, all 360 frames,
transparent and opaque pixels, and the last-to-first frame difference relative to
ordinary adjacent frame differences. FFprobe alone reports the base HEVC layer
as `yuv420p` and cannot establish whether Apple HEVC alpha is present. The native
decode report is included in `manifest.json`.

### Final measured results

The resumed production run finished in **59.403 s**, reusing the completed 2K
still and 39 valid frames, regenerating the interrupted frame, and creating the
remaining 321 frames before encoding. The earlier contended run reached its
first movie frame at 112.6 s. These are separate run measurements, not a claimed
59-second fresh render of every output. The resumed numeric checks sampled a
256 px grid using the final geodesic integration table; final image dimensions
were checked independently. Final maximum first-integral relative error was
**9.38 × 10⁻¹²**, and phase 0 versus phase 1 was exactly equal.

AVFoundation decoded **360 frames**, **1080 × 1080**, **30 fps**, **12.000 s**.
Its alpha characteristic was present. The first frame contained **886,976 fully
transparent pixels**, **221,586 opaque pixels**, and **57,838 intermediate-alpha
pixels**. The last-to-first mean byte change was **1.294**, compared with an
ordinary adjacent-frame average of **1.081** and maximum **1.256**; the closing
step is comparable to the animation's ordinary motion, with no blank endpoint.

---

## Sun — `sun-photosphere.png`, `sun-corona.png`

**Generator:** `blender/codex/sun.py`, with `emission_utils.py`. Both outputs are rendered in Cycles from emission planes; the sphere preview uses the same fields. AgX / Medium High Contrast, 8 samples for quick and 128 maximum samples for final; adaptive minimum 4/8, two CPU threads. Denoising is enabled on the sphere preview and disabled on the emission-only texture planes, which have no indirect-light noise. All maps are procedural and deterministic. No reference images or downloaded textures were used.

**Photosphere:** 2048 × 1024 RGB PNG in sRGB, equirectangular. The warm white radiance represents a white-balanced 5772 K photosphere, avoiding a yellow Sun. A jittered three-dimensional Voronoi field sampled on a sphere produces bright cell interiors and dark intergranular lanes. Sampling in 3D avoids a longitude seam and polar pinching. Eleven irregular spots form groups at approximately ±17–26° latitude. Their darker, warmer umbrae represent approximately 3800 K material; penumbrae have radial filaments and intermediate brightness. The texture contains no directional lighting.

**Corona:** 2048 × 2048 straight-alpha RGBA PNG. One solar radius occupies 2048 / 6.3 ≈ 325 pixels from the centre. The visible corona extends to about 3 solar radii. Equatorial helmet streamers are longer than the polar plumes, with small radial filaments. A thin pink-red chromosphere and four limb-rooted prominence arches represent Hα emission. The solar interior is transparent so the billboard sits behind the opaque Sun sphere. Place the corona on a plane 6.3 solar radii wide. Its alpha falls smoothly to zero outside the corona.

**Limb darkening:** the saved sphere preview uses a Layer Weight node to drive emission with `I(μ)/I(1) = 0.3 + 0.7 μ`. This is view-dependent and therefore deliberately absent from the equirectangular texture. The app's Sun material must apply it to reproduce the preview. A diffuse or emission map cannot encode the correct limb for every viewpoint.

**Deliberate approximations:** the brief's “~1000 km cells” and “40–60 cells across the disc” cannot both hold for a 1.39-million-km solar diameter. The texture follows its readability target: ~56 cells across the projected diameter, so granulation is enlarged by roughly 25×. Spots and prominence width are also enlarged for a small mobile view. Colours and brightness were calibrated for AgX appearance, not a spectrally integrated radiative-transfer simulation. The 1–2 MK corona represents a visible Thomson-scattered continuum; it is not rendered as a million-kelvin blackbody. Its display brightness is boosted substantially so streamers can be seen alongside the photosphere; their natural contrast is much larger. Streamers are a dipole-like density illustration, not an MHD field solution. Prominence arches and their emission are illustrative, and the Hα rim is wider than physical scale to survive downsampling. PNGs are 8-bit display textures rather than photometric HDR data.

**Commands** (run from the repository root):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --threads 2 --python blender/codex/sun.py -- --quick
/Applications/Blender.app/Contents/MacOS/Blender --background --threads 2 --python blender/codex/sun.py -- --final
```

The preview and machine-readable timings are under `blender/codex/out/sun/`. On this Mac, Blender must run with permission to initialise the Metal device; a sandboxed invocation crashes before Python starts. The procedural work and Cycles renders themselves use CPU. Denoising the first full-size map stalled in OpenImageDenoise under memory pressure; that attempt was stopped and rerun with denoising disabled for emission planes. This is a deliberate departure from the brief's general denoising default and preserves the fine granule structure.

**Measured final generation:** 60.58 seconds for both full-resolution maps and the 768² sphere preview, including procedural field construction and saving. Final photosphere validation: 2048 × 1024, RGB; average display colour approximately (239, 235, 232). The mean adjacent seam-edge difference is 2.44 / 255, consistent with continuous spherical sampling at neighbouring pixel centres. Visual review confirms warm white granulation, spots, a darker limb, radial streamers, and pink prominence arches. See `blender/codex/out/sun/sun-preview.png`.

Current quick mode completed in 0.92 seconds inside Blender (~1.7 seconds including startup), including the 256² sphere preview.

The final corona is 2048² RGBA with alpha range 0–230, 2,511,055 fully transparent pixels, a transparent centre, and four transparent corners. Both final PNGs carry explicit sRGB metadata. `blender/codex/out/sun/validation.json` records file dimensions, alpha checks, and SHA-256 hashes.

---

## Planet texture production notes

## Files and reproduction

Generator: `blender/codex/planets.py`.

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --threads 2 --python blender/codex/planets.py -- --quick
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --threads 2 --python blender/codex/planets.py -- --final
```

An optional `--only earth,jupiter` filter supports individual iterations. The default processes **all 26 IDs explicitly listed in the brief**, including Sirius B. Their class, temperature, and base color come from the current `Foldspace/Universe/UniverseData.swift`. No Swift files were changed.

Final diffuse maps: `assets/textures/planet-<id>.png`, 2048×1024, 8-bit RGB, no alpha, explicit PNG sRGB and gAMA chunks. Roughness maps are RGB scalar data without sRGB/gAMA chunks; load them as linear data. Other companions are sRGB RGB PNGs:

- `planet-earth-roughness.png`: ocean ≈0.10, land ≈0.87, increased roughness for clouds and ice.
- `planet-trappist-1e-roughness.png`, `planet-trappist-1f-roughness.png`: open ocean ≈0.10, ice/land/clouds rougher.
- `planet-earth-emissive.png`: sparse, dim amber metropolitan lights, using hand-entered approximate locations.
- `planet-barnard-d-emissive.png`, `planet-trappist-1b-emissive.png`: dayside lava fissures.
- `planet-sirius-b-emissive.png`: blue-white white-dwarf photosphere; this must be used as emission rather than treating Sirius B as a rocky planet.

Quick maps are 256×128 in `blender/codex/out/planets/quick/`. Individual 256×256 lit inspection globes and contact sheets are in `blender/codex/out/planets/`. These preview globes are inspection aids and must not replace the unlit equirectangular maps in the app.

## Method and coordinate convention

This is an equation-driven image synthesis job executed inside Blender with its bundled NumPy. It directly samples spherical fields instead of rasterizing an EEVEE scene, which produces exact unlit albedo with no shadows, ambient light, camera orientation, or tone mapping baked into the export. PNG bytes are written by a small standard-library encoder so image color tags and the absence of alpha are explicit. AgX is relevant for scene renders; these albedo/data maps deliberately preserve their authored sRGB/data values.

The map goes from longitude −180° to +180°, north at the top. Its seam lies on −X. Spherical coordinates are X=cos(latitude)cos(longitude), Y=cos(latitude)sin(longitude), Z=sin(latitude). The fixed substellar direction used for hypothetical locked worlds is +X, longitude 0°, at the center of the texture. Runtime stellar lighting and spin/orbital orientation must agree with that direction for those worlds.

Noise is deterministic smooth 3D lattice noise evaluated on the unit sphere. Large terrain variation uses scale 3.1 with four octaves, domain-distorted detail scale 21 with three octaves, and rocky microtexture scale 94 with two octaves. Octave frequency ratio is 2.07 and amplitude ratio 0.51. Each body has a fixed seed recorded in the JSON report. No external imagery, map files, or copyrighted texture sources are used.

The first and last columns are made byte-identical, and each pole row has one longitude-invariant color. This avoids visible UV splits and arbitrary pole spokes. Local spherical crater stamps wrap longitude and use great-circle angular distances. Their darker floors and brighter ejecta encode albedo, not a fixed lighting direction. Crater sizes span about 0.008–0.095 radians; rocky bodies have 260 placements. This uses randomized impact centers, not a literal Voronoi crater shader.

## Encoded physics and deliberate choices

| Body or group | Encoded appearance and limits |
|---|---|
| Mercury | Neutral warm-gray airless regolith, overlapping crater floors/ejecta. No visible global ice cap: Mercury's polar ice is confined to small permanently shadowed regions. |
| Venus | Pale cream/ochre opaque sulfuric-acid cloud deck with soft sheared structure. Although the catalog class is desert, the surface is hidden from orbit. No glowing surface at 737 K. |
| Earth | Recognizable hand-drawn continent outlines, Sahara/Arabian/Australian dry regions, cold high latitudes, polar ice, dark oceans, nearshore shallows, cloud decks. Coasts are approximate and intentionally not cartographically authoritative. Clouds and terrain are combined in one albedo for the existing loader. |
| Mars | Rust-colored mineral albedo, darker terrain, broad Syrtis Major-like region, narrow Valles Marineris-like stripe, small polar ice caps. Large-scale features are illustrative, not a survey map. |
| Jupiter | Alternating cream zones and brown belts, latitude-parallel fine filaments, longitudinal turbulence, several light ovals. Great Red Spot centered at 22° S; the oval also displaces nearby belts. Spot longitude is arbitrary. |
| Saturn | Pale cream/gold bands, restrained contrast, muted polar haze. Ring shadows are directional illumination and are deliberately left to runtime ring geometry/light. No permanent shadow stripe is painted into the diffuse map. |
| Uranus | Methane-tinted pale cyan, faint bands and haze. |
| Neptune | Restrained methane blue and faint bands, a subtle illustrative dark storm and a small white cloud feature. Color is desaturated from the catalog's strongly blue swatch toward a less saturated visible-light appearance. The storm is not claimed as a current observed feature. |
| Proxima b | Rocky terrain with a hypothetical frost-rich antistellar hemisphere. No evidence for an actual surface map, atmosphere, ocean, or ice distribution is implied. The habitable flag is not treated as evidence of life. |
| Proxima d, Barnard b/c/e, TRAPPIST-1 c | Distinct seeded rocky/cratered mineral surfaces using their catalog color families. No molten global surface is inferred solely from close orbital distance. |
| Barnard d, TRAPPIST-1 b | **Deliberate gameplay exaggeration:** their catalog class is lava, but 440 K / 400 K do not support globally molten silicate surfaces. Separate sparse fissure emission represents hypothetical localized 1200–1800 K volcanism on the fixed dayside. This is not a measured condition. The global diffuse surface remains dark rock. |
| Wolf 359 b | Hypothetical methane-colored cold ice giant with faint bands. Its candidate status and unmeasured appearance remain as in the app catalog. |
| Sirius B | Nearly featureless blue-white 25,200 K white-dwarf photosphere, very low contrast texture, emission companion. **It is a star, not a planet**, despite the required `planet-sirius-b` filename. A star material must handle emission and view-dependent limb darkening. |
| Epsilon Eridani b | Hypothetical cold ammonia-cloud giant: tan/cream zonal belts and fine filaments. |
| Tau Ceti e | Dry, warm tan super-Earth terrain with subtle dune-scale variation; speculative surface. |
| Tau Ceti f | Cold muted blue-gray terrain with extensive ice and dark fracture networks; speculative ice cover. |
| TRAPPIST-1 d | Dry golden mineral terrain; does not assume a detected ocean or thick atmosphere. |
| TRAPPIST-1 e/f | Hypothetical tidally locked ocean/ice worlds, darker open water around the substellar hemisphere, sparse land, and more extensive ice on f than e. These are illustrative climate scenarios, not detections of liquid water. |
| TRAPPIST-1 g/h | Frozen blue-gray worlds with subdued fractures and impact terrain. Ice coverage and fracture patterns are speculative. |

Lava emission color is approximated from Planck radiance at representative 610/550/460 nm wavelengths, normalized and white-balanced against 5772 K, then encoded as sRGB. This is a three-channel approximation rather than full CIE spectral integration. The texture carries normalized color/intensity; runtime emission strength controls apparent luminosity. Fissure masking uses the signed dayside coordinate X and fades to zero on the antistellar side.

## Required runtime material behavior

These assets cannot themselves produce a soft terminator, a Rayleigh rim, dynamic ring shadows, or view-dependent specular oceans. Those require the app material/light:

- Use a physically based diffuse material and directional stellar lighting with very low ambient illumination. Keep the night hemisphere approximately black. Use an extended light/appropriate atmospheric scattering for a soft terminator.
- For Earth, add a thin atmosphere shell with density scale height about 8.5 km (scaled to the planet) and Rayleigh-like blue limb scattering/redder terminator. A fallback rim weight `(1 − dot(N,V))^4` is suitable for the brief's realtime approximation. Do not paint this rim onto the UV texture.
- Load the ocean roughness maps in linear/data space. Tune water specular independently of albedo. The combined cloud albedo limits physically correct separate cloud height/shadows.
- Earth lights should be faint and multiplied by a smooth night-side mask in the material; otherwise ordinary emission would remain visible on the day hemisphere too.
- Lava fissures are already limited to the fixed day hemisphere. Use their emissive maps on that orientation, including while the viewer sees its lit face.
- Saturn needs actual rings and runtime ring shadows. Sirius B requires an emissive stellar material with limb darkening rather than a dark night hemisphere.

No normal maps are shipped; the brief makes them optional. Fine albedo/crater structure remains visible under app lighting. Additional geometric relief would require a separate normal or displacement map.

## Verification and timing

The initial full quick set generated all 26 bodies in **39.67 s of script time** under concurrent rendering load. Blender startup is additional. The sandboxed Blender process crashes in Metal device detection before Python starts; an approved unsandboxed Blender invocation is required on this host. No installation or preference changes were needed.

The quick contact sheet was visually inspected for complete sphere coverage, recognizable Earth geography, band direction, Great Red Spot position, subdued gas-giant color, and the white-dwarf exception. Final generation timings and final validation are recorded in `blender/codex/out/planets/final-report.json` and the completion addendum below.

## Completion addendum

Final generation completed through Blender 5.2.1. The full set took **62.713 s** of script time; the final three-body cloud refinement took **16.254 s**. The maximum time for any individual body was **5.955 s**. Blender startup is excluded. The final maps contain 33 PNGs totaling **43,439,020 bytes** (about 41.4 MiB).

All 33 files passed PNG signature, chunk CRC, decompression, 2048×1024 dimensions, RGB/no-alpha, sRGB tagging for color maps, exact first/last-column equality, and constant pole-row checks. The complete result with SHA-256 hashes is in `blender/codex/out/planets/validation.json`. The final contact sheet and Earth, Jupiter, and lava sphere closeups were visually inspected.

Cloud refinement removed strong latitude anisotropy and nearest-neighbor preview sampling. Clouds now use locally rotated spherical domains for two illustrative cyclones, a rotated lattice basis, and fine-scale density variation. The final sheet reflects these refined maps.

| Body ID | Final map generation, seconds |
|---|---:|
| mercury | 1.432 |
| venus | 1.517 |
| earth | 5.955 |
| mars | 1.500 |
| jupiter | 1.509 |
| saturn | 1.050 |
| uranus | 1.100 |
| neptune | 1.269 |
| proxima-b | 1.160 |
| proxima-d | 1.412 |
| barnard-b | 1.796 |
| barnard-c | 2.459 |
| barnard-d | 2.561 |
| barnard-e | 1.294 |
| wolf-359-b | 0.877 |
| sirius-b | 0.986 |
| eps-eri-b | 1.998 |
| tau-ceti-e | 3.706 |
| tau-ceti-f | 4.467 |
| trappist-1b | 5.202 |
| trappist-1c | 4.094 |
| trappist-1d | 2.849 |
| trappist-1e | 4.784 |
| trappist-1f | 5.319 |
| trappist-1g | 2.957 |
| trappist-1h | 3.787 |

Each per-body time includes its optional companion maps and inspection globe. The exact per-invocation timing records and seeds are in `final-report.json` and `final-refinement-report.json`. No Blender jobs remain running for this deliverable.

---

## Sprite assets: warp bubble and rock debris

Scripts: `blender/codex/warp.py` and `blender/codex/shatter.py`. Both are self-contained Blender 5.2 Python scripts using bundled NumPy. No external image files, fracture add-on, or Pillow are required. They render with Cycles, AgX, transparent film, three CPU render threads, and deterministic geometry. The PNGs contain sRGB color and straight alpha.

### Alcubierre York-time surface

Output: `assets/sprites/warp-bubble-8x1.png`, **4096 × 512**, RGBA, eight **512 × 512** frames. Read left to right. Frames 0 and 7 are flat; frames 3 and 4 are the peak deformation. The 256 × 256 quick preview shows the full-amplitude surface, so its deformation is slightly stronger than either sampled peak frame.

The surface uses the analytic derivative of Alcubierre's smooth top-hat, with the ship at the origin and forward motion along **+x**, toward the small arrow's point:

```text
R = 1.05; sigma = 5.5; v_s = 0.46
r = sqrt(x*x + y*y)
f(r) = [tanh(sigma*(r+R)) - tanh(sigma*(r-R))] / [2*tanh(sigma*R)]
f'(r) = sigma*[sech²(sigma*(r+R)) - sech²(sigma*(r-R))] / [2*tanh(sigma*R)]
a(k) = sin²(pi*k/7), k = 0..7
z = theta = a(k) * v_s * (x/r) * f'(r), with theta(0,0) = 0
```

Positive x therefore has **negative York time**, displayed as the blue depressed front/contraction. Negative x has **positive York time**, displayed as the red raised rear/expansion. The interior and exterior approach flatness naturally from the same analytic expression; the finite tanh wall has exponentially small tails rather than an artificial cut to zero. The on/off envelope has zero slope at both flat endpoints. The grid follows the analytic height, including between visible grid intersections.

Presentation choices and limits:

- Coordinates, velocity, and surface height are dimensionless visualization units. Height and color represent the sign and relative strength of York time, not a literal embedding of the full spacetime metric.
- A small arrow marks the ship and forward direction inside the near-flat region. The 4 × 4 coordinate patch is finite, and line width and color intensity are chosen for a 512 px display.
- The atlas contains the requested rubber sheet only. It includes no starfield or interior aberration. It does not implement a separate simulation of wall lensing for a background starfield.
- The surface has 12% alpha between its bright coordinate lines. It is intentionally designed to composite over the app's dark scene.
- Final rendering uses 64 samples; quick mode uses 32 samples. The quick output is `blender/codex/out/warp/warp-preview.png`.

### Planet-shatter debris

Output: `assets/sprites/shatter-debris-4x4.png`, **1024 × 1024**, RGBA, sixteen **256 × 256** frames. Read **left to right, then top to bottom**. Frame 0 is the top-left tile and frame 15 is the bottom-right tile. The final frame is dispersed; this is a one-shot sequence and should not loop back to frame 0.

The script constructs **84 true volumetric Voronoi cells** by intersecting a convex triangulated sphere with every relevant bisector half-space. Six sparse seeds occupy the core, while 78 seeds populate the outer shell; core cells are correspondingly larger. Random seed: **6947**. This replaces dependence on the Cell Fracture add-on while retaining its underlying Voronoi construction.

Each chunk starts at its own cell center and receives a velocity directed away from the small internal impulse point `p = (0.04, -0.06, 0.08)`:

```text
d = length(center - p)
v = normalize(center - p) * (0.35 / d)
x(t) = center + v*t
t(k) = 4.0*k/15, k = 0..15
rotation(t) = quaternion(fixed_seeded_axis, angular_speed*t)
angular_speed = seeded uniform(0.35, 1.6) radians per time unit
```

Motion is ballistic: velocity and angular speed stay constant. There is no gravity, atmosphere, drag, easing, or artificial slowdown. The camera stays fixed at orthographic scale 9.9515. Its framing is derived from the endpoints of every linear trajectory plus a sphere that encloses each rotating chunk, with a 4% margin, so the full free-flight interval fits inside the frame. Silicate-like surface and fresh fracture materials use procedural noise and bump; warm key lighting and cool rim lighting expose the facet shapes.

Presentation choices and limits:

- This is a kinematic free-flight model after fragmentation, with no rigid-body collision solver or self-gravity. Passing fragments can overlap; the sprite is meant to support the separate 3D shatter. The velocity change per unit mass is proportional to inverse distance; it does not separately model differing masses and total force impulse.
- Chunk geometry is shrunk to 94% around each cell center to expose seams in the first frame. Edge bevels are 0.005 scene units. These visual adjustments make the fracture visible at 256 px.
- Distances, times, energy, lighting, and material colors are generic visualization units, not a simulation of a named planet's impact energy or composition.
- Final rendering uses 48 samples; quick mode uses 16 samples at the final time, 4.0. The quick output is `blender/codex/out/shatter/shatter-preview.png`.

### Reproduce

From the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python blender/codex/warp.py -- --quick
/Applications/Blender.app/Contents/MacOS/Blender --background --python blender/codex/warp.py -- --final
/Applications/Blender.app/Contents/MacOS/Blender --background --python blender/codex/shatter.py -- --quick
/Applications/Blender.app/Contents/MacOS/Blender --background --python blender/codex/shatter.py -- --final
```

Intermediate final frames and render logs are retained in `blender/codex/out/warp/` and `blender/codex/out/shatter/`. Quick mode produces one 256 px preview, not a lower-resolution replacement for the final atlas. Blender's Metal initialization requires running outside this session's filesystem sandbox on this machine; this is an environment constraint, not a script dependency.

### Measured runtime and verification

Measured script runtimes on this machine while other project renders were active:

| Script / mode | Runtime | Output |
|---|---:|---|
| Warp quick | 1.08 s | 256 × 256 RGBA preview |
| Warp final | 422.94 s (7.05 min) | 4096 × 512 RGBA, 1,136,631 bytes |
| Shatter quick | 3.00 s | 256 × 256 RGBA preview of the revised dispersed end state |
| Shatter final | 17.88 s | 1024 × 1024 RGBA, 658,205 bytes |

These times exclude Blender startup; full process wall times are slightly longer. Both final runs remain below ten minutes. Voronoi geometry construction itself took 0.64 s in the quick run. The final debris render ran after the concurrent heavy render jobs were paused; the large runtime difference reflects available resources as well as the wider framing.

Verification completed for both delivered final atlases:

- Opened and visually inspected both 256 px previews, full-size representative frames, the final debris atlas, and a 4 × 2 contact sheet of the final warp sequence (`blender/codex/out/warp/warp-contact.png`).
- Confirmed exact output dimensions and RGBA mode. All 24 atlas tiles are pixel-identical to their corresponding render PNGs, including color and alpha; row order is correct.
- Confirmed every tile has a fully transparent outer border, so no geometry is cut at the frame boundary. Alpha includes both zero and 255 in every frame.
- Confirmed warp frames 0 and 7 are pixel-identical.
- Checked the implemented analytic York derivative against a centered finite difference of the original top-hat expression at six radii: error below 1e-8. Front/rear signs and exact zero-envelope flatness also passed.
- Confirmed script syntax and the completed Blender logs. No iOS/Swift source, project configuration, or other agents' files were changed by this sprite work.

---

## Galaxies — Milky Way and Andromeda

**Generator:** `blender/codex/galaxies.py`, with `emission_utils.py`. Pure procedural radiance fields are rendered on emission planes in Cycles with AgX / Medium High Contrast. Quick uses 8 samples; final uses 128 maximum samples with an adaptive minimum of 8. Denoising is deliberately disabled: there is no indirect-light noise on these planes, the filter removes fine stellar structure, and its feature buffers cause excessive memory pressure at 4096². Rendering is limited to two CPU threads. NumPy evaluates the fields in 128-row blocks to limit memory. No measured star catalogues or external imagery are included.

**Files:**

- `assets/textures/galaxy-milkyway.png`: 4096 × 4096 straight-alpha RGBA, face-on.
- `assets/textures/galaxy-andromeda.png`: 4096 × 4096 straight-alpha RGBA, face-on.
- `assets/textures/galaxy-andromeda-inclined.png`: optional 4096 × 4096 RGBA illustration at 77° from face-on, with a −31° position angle.
- `assets/textures/galaxy-milkyway-edge.png`: 4096 × 1024 straight-alpha RGBA, edge-on stellar band and absorbing midplane.

**Milky Way:** a 100 kly diameter barred spiral. Four logarithmic arms use `r = a exp(bφ)` with `b = 0.28` (pitch angle ≈15.6°), a roughly 27 kly bar, an old yellow-white central population, and a shorter Orion spur. The four major arms represent Perseus, Scutum–Centaurus, Norma, and Sagittarius as a schematic density-wave pattern. Broad blue-white young populations, pink Hα knots, correlated fine structure, varying cloud widths, and irregular offset dust ridges make the arms visible. A deterministic 150,000-sample star distribution increases the resolved texture; 35% of samples belong to an inter-arm population.

**Andromeda:** a 220 kly diameter disc with two main logarithmic arms (`b = 0.27`, pitch ≈15.1°), a stronger yellow bulge, and ring features. A 10 kpc ring is at radius 0.297 of a 33.7 kpc disc radius. A fainter outer ring is included. Two small elliptical populations represent M32 and M110. Their centres are placed to keep them readable in the texture.

**Edge view:** vertical exponential thin and thick stellar populations, an old central bulge, a narrow absorbing dust lane, and a weak outer warp. It is an analytic edge-on illustration rather than an integrated ray trace through the face-on density field.

**Contract ambiguity:** the deliverables table requires both main textures to be face-on, while the physics paragraph calls for M31's observed 77° inclination. The exact required `galaxy-andromeda.png` is face-on so the app can orient its plane. The optional `galaxy-andromeda-inclined.png` supplies the requested projected illustration. Do not apply another 77° tilt to the latter texture.

**Deliberate approximations:** the arm positions are schematic and do not claim to be a current measured map of the Milky Way. Hα knots, individual bright stellar pixels, and dust contrast are amplified for mobile readability. The sprites show unresolved stellar emission and dust attenuation, not multiwavelength radiative transfer. M31's companion positions are illustrative in both views; the main face-on texture is a deprojection concept rather than an observed view. The 77° version projects a thin disc and adds a broader spheroidal bulge; it is not a full volume integral. Both galaxies fill similarly sized texture canvases; their physical size ratio must be applied by the app. In either square map, one model disc radius occupies 4096 / 2.48 ≈1652 pixels. Transparency represents a display compositing weight, not optical depth. PNGs are 8-bit sRGB display images rather than photometrically calibrated HDR maps.

**Commands** (run from the repository root):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --threads 2 --python blender/codex/galaxies.py -- --quick
/Applications/Blender.app/Contents/MacOS/Blender --background --threads 2 --python blender/codex/galaxies.py -- --final
```

Quick previews, versions composited onto black, and timing JSON are in `blender/codex/out/galaxies/`. Run these sequentially with other large Blender jobs on memory-constrained machines.

**Measured generation:** the final generator took 219.60 seconds total, including field construction, Cycles rendering, and saving. Per asset: Milky Way 69.33 s; face-on Andromeda 65.14 s; inclined Andromeda 73.49 s; Milky Way edge 11.22 s. Current quick mode took 1.35 s inside Blender (~2.1 s including startup), comfortably below 60 seconds. Earlier denoised previews slowed to 112 s under severe concurrent memory pressure; the current emission-only renderer avoids that filter.

**Validation:** all four PNGs have the required pixel dimensions and RGBA channels, explicit sRGB metadata, nonempty alpha, and fully transparent corner pixels. The three square files are 4096²; the edge band is 4096 × 1024. Final exported PNGs were composited over black in linear light and reviewed at 1024 px. Broad broken arms, granular inter-arm stars, dust structure, the Milky Way bar, Andromeda's warmer bulge, and both satellites are visible. The `*-final-review.png` images show these exported-map composites; the quick `*-black.png` images are direct Cycles composites. Their brightness can differ slightly because tone mapping and alpha compositing occur in a different order. `validation.json` records dimensions, alpha extrema, transparent-pixel counts, and SHA-256 hashes for the final maps.
