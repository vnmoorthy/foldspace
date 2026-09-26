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
