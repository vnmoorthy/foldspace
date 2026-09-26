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
