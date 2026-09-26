# Material and SceneKit asset integration

Updated 26 September 2026. The initial source audit found working planet/Sun diffuse loading and complete resource references, but several generated assets had no consumer. The app integration below was then implemented in `PlanetMaterials.swift` and `SpaceScene.swift`.

## Implemented

| Area | Behavior | Source |
|---|---|---|
| Bundle loading | Cached named PNG loader with procedural fallback for missing planet maps. Roughness companions are tagged with a linear RGB color space. | [PlanetMaterials.swift:135](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/PlanetMaterials.swift:135>) |
| Planet companions | Earth and TRAPPIST-1 e/f use their ocean roughness maps. Earth, Barnard d, TRAPPIST-1 b, and Sirius B use authored emission companions. Missing lava maps retain the procedural fallback. | [PlanetMaterials.swift:20](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/PlanetMaterials.swift:20>) |
| Earth lights | Faint emission is multiplied by a smooth night-side mask. The key-light direction and surface normal are both in view space. Camera and key light share the rig, preserving the relationship while the hinge moves. | [PlanetMaterials.swift:59](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/PlanetMaterials.swift:59>), [SpaceScene.swift:342](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/SpaceScene.swift:342>) |
| Stellar shading | Stars emit the texture once at intensity 1.0 with black diffuse, preserving its authored detail. The specified view-dependent limb factor `0.3 + 0.7 μ` darkens the edge. Sirius B remains a star despite its `planet-sirius-b` filename. | [PlanetMaterials.swift:24](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/PlanetMaterials.swift:24>) |
| Sun corona | The authored corona is a camera-facing plane 6.3 solar radii wide, at opacity 0.9, with depth reads enabled and depth writes disabled. Its transparent center preserves the photosphere. Missing corona files retain the generic halo. | [SpaceScene.swift:418](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/SpaceScene.swift:418>) |
| SceneKit Andromeda | The M31 plane uses the face-on `galaxy-andromeda.png` with alpha blending and clamped image edges. The scene still supplies the plane orientation. Missing maps retain the procedural spiral. | [PlanetMaterials.swift:42](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/PlanetMaterials.swift:42>), [SpaceScene.swift:508](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/SpaceScene.swift:508>) |
| Shatter debris | The 4×4 atlas is cropped into sixteen 256² frames in top-left row order. A depth-tested billboard plays once behind the 3D fragments, then fades and removes itself. Its 9.9515-radius width matches the generator framing. | [SpaceScene.swift:743](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/SpaceScene.swift:743>) |
| Async material application | The background task prepares diffuse and companions, then the main actor assigns the whole material. Cold-cache and cached paths both set the Earth light uniform. The body-ID and shattered-state guards remain. | [SpaceScene.swift:303](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/SpaceScene.swift:303>) |

## Bundle configuration audit

All **43 generated media files (42 PNGs and one movie)** have matching `PBXFileReference` → `PBXBuildFile` → target Resources entries. **Missing generated media: none.** Resource entries are in [project.pbxproj](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace.xcodeproj/project.pbxproj:506>); their XcodeGen source is [project.yml](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/project.yml:31>). This work did not edit project configuration.

The seven companions are three roughness maps (Earth and TRAPPIST-1 e/f) and four emission maps (Earth, Barnard d, TRAPPIST-1 b, and Sirius B). No normal maps were generated; those are optional under the original brief.

## Verification

- `swiftc -frontend -parse` passes for both edited source files.
- `git diff --check` passes for both edited source files.
- The shader surface fields, custom uniforms, and view-space convention were checked against the installed Xcode SDK's `SceneKit.framework/Headers/SCNShadable.h`. The public [SCNShadable documentation](https://developer.apple.com/documentation/scenekit/scnshadable) describes the same modifier mechanism.
- Sun and Earth shader modifiers compiled and rendered with **actual Metal on the Apple M3** in the native macOS SceneKit harness. All renders prepared successfully and completed without shader errors. Final iOS app build and simulator checks remain owned by the parent task; a macOS material render does not claim full iOS UI validation.

## Native Metal visual validation

Harness: [RenderMaterials.swift](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/blender/codex/out/integration/material-render/RenderMaterials.swift>), with Sun/Earth shader strings extracted from the app source into neighboring `.metal` files. It reads the actual PNGs, uses the app's material intensities and light setup, and renders offscreen 1024² snapshots through `SCNRenderer`. The camera frames the complete globe for inspection. The first sandboxed run reported no Metal device; the approved run outside the sandbox used Apple M3. No simulator, network service, or persistent app state was involved.

- [Earth with production materials](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/blender/codex/out/integration/material-render/earth-lit.png>): continent/cloud detail is visible; ocean roughness produces a specular highlight. The Earth mask A/B comparison reduced city emission on the lit side: **347 pixels darkened, none brightened**. With diffuse and lights disabled to isolate emission, 4 nonblack pixels remain versus 354 without the shader, consistent with this mainly day-facing globe orientation.
- [Sun before brightness correction](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/blender/codex/out/integration/material-render/sun-limb.png>): its old constant diffuse plus 0.55 emission added the same map twice, clipping the bright center and hiding granules. The limb shader itself compiled and darkened 346,518 pixels versus its shader-free control.
- [Corrected Sun material](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/blender/codex/out/integration/material-render/sun-emission-only-candidate.png>): black diffuse and emission intensity 1.0 restore center granulation while retaining warm-white appearance and limb darkening. This verified correction is now applied in `PlanetMaterials.swift`.
- [Corrected Sun plus corona](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/blender/codex/out/integration/material-render/sun-corona-emission-only-candidate.png>): the generated corona is centered, scaled correctly, and depth-tests behind the photosphere. Prominence loops and radial streamers remain visible.

Logs: [initial shader audit](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/blender/codex/out/integration/material-render/render.log>) and [emission-only validation](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/blender/codex/out/integration/material-render/candidate.log>). The harness's default path preserves the original audit settings for comparison; `--candidate` reproduces the final star material. These are inspection outputs, not application bundle assets.

## Existing limits retained

- **Atmosphere and ring shadows:** the atmosphere remains the existing uniform additive shell at [SpaceScene.swift:367](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/SpaceScene.swift:367>). It does not model Rayleigh scattering or a red terminator. The key light still disables shadows at [548](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/SpaceScene.swift:548>), so Saturn has rings without their directional shadow. These are broader scene-lighting changes; the texture maps deliberately do not bake them in.
- **Locked-world orientation:** the hologram keeps rotating all planetary surfaces relative to the camera-mounted light at [SpaceScene.swift:292](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/Scene/SpaceScene.swift:292>). The authored locked-world substellar direction is longitude 0°, at the center of the map; see [notes-planets.md:28](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/assets/notes-planets.md:28>). A fixed stellar orientation remains a separate scene choice.
- **Playback time:** debris has 16 frames at 0.15 s each (2.4 s), followed by a 0.3 s fade. The generator's physical timeline spans 4 model time units. Playback is intentionally accelerated to accompany the existing shatter animation.
- **Separate galaxy UI paths:** GalaxyMapView and AndromedaFinaleView have independent drawing code. Their integration belongs to the parent task and is not verified by the SceneKit changes above. The optional inclined M31 texture already includes 77° projection; do not add another such tilt.

## Visual checks for the app build

Open Earth from a cold cache, revisit it, and compare ocean highlights and city masking. Inspect Sun limb shading and corona centering at multiple hinge angles. Check Barnard d and TRAPPIST-1 b fissures. Visit Andromeda's cockpit independently of its finale. Fire the Nova Lance once and verify that the debris sheet progresses once without showing neighboring atlas tiles or returning to frame zero.
