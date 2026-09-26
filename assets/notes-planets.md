# Planet texture production notes

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

No normal maps are shipped: random directional bump shading would incorrectly bake a sun direction, and the brief makes normal companions optional. Fine albedo/crater structure remains visible under app lighting.

## Verification and timing

The initial full quick set generated all 26 bodies in **39.67 s of script time** under concurrent rendering load. Blender startup is additional. The sandboxed Blender process crashes in Metal device detection before Python starts; an approved unsandboxed Blender invocation is required on this host. No installation or preference changes were needed.

The quick contact sheet was visually inspected for complete sphere coverage, recognizable Earth geography, band direction, Great Red Spot position, subdued gas-giant color, and the white-dwarf exception. Final generation timings and final validation are recorded in `blender/codex/out/planets/final-report.json` and the completion addendum below.
