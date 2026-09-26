# FOLDSPACE asset integration

26 September 2026. The Blender deliverables are now connected to the iOS app.

## Implemented

- **Black hole:** an alpha-preserving `AVPlayerLayer` loops the movie between the
  background Canvas and the gameplay Canvas. The still remains visible until the
  player is ready and is used when Reduce Motion is enabled. Playback pauses while
  the scene is inactive, and teardown releases the player and loop. The 24-rs
  render width matches the game's existing coordinate system. Missing resources
  retain the procedural drawing.
- **Materials:** authored roughness and emission companions, Earth's night-side
  emission mask, stellar limb darkening, and a Sun corona billboard at 6.3 radii.
  Roughness is tagged as linear data; color maps retain sRGB.
- **Warp and debris:** exact atlas crops, clamped warp indexing, and a one-shot
  debris animation behind the existing 3D fragments. The debris node removes
  itself after fading.
- **Galaxies:** authored Milky Way and Andromeda images in travel/finale views,
  an edge-on map backdrop, and the Andromeda SceneKit plane. Sequence views apply
  the face-on Andromeda texture's 77-degree projection once.
- **Sun dive:** a photosphere patch near the surface, fading before the interior.
- **Resource loading:** large 2D images are downsampled to 2048 pixels and cached;
  atlas frames are cropped once. The regenerated project includes the loaders.

Gameplay physics and progression remain unchanged. The existing uniform planet
atmosphere shells, ring-shadow approximation, and tidally locked planet animation
remain as documented in `assets/review-materials.md`.

## Build

The local scheme/destination build fails during platform selection even though
the simulator SDK is installed. Direct target mode bypasses that lookup:

```sh
xcodebuild -project Foldspace.xcodeproj -target Foldspace \
  -configuration Debug -sdk iphonesimulator \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  SYMROOT=blender/codex/out/integration/TargetBuild build
```

Toolchain: Xcode 26.6, iOS Simulator SDK 26.5, Swift language mode 5,
Sentry 8.58.4. Compilation found three existing issues that were corrected:
material blend mode uses `SCNBlendMode.add`, particle blend mode uses
`SCNParticleBlendMode.additive`, and `demoSkip` calls require `to:`. The debris
action accesses its node's material directly, avoiding a non-Sendable material
capture in the action closure.

**Final result: BUILD SUCCEEDED**, including the corrected emission-only stellar
material. `git diff --check` also passed. The final incremental build emitted only
the non-blocking notice that App Intents metadata extraction had no dependency.

Build log: `out/integration/build-target.log`. The executable is an arm64 iOS
Simulator app, with deployment target iOS 26.0. Bundle validation found all
43 generated media files and no missing resource.

## Native material rendering

The Sun and Earth materials were rendered offscreen with SceneKit and Metal on
the Apple M3, using the production shader strings and authored PNGs. All scenes
prepared and rendered with no shader compilation errors.

- Sun limb shading changed 346,518 pixels relative to an unshaded control,
  darkening them as expected.
- Earth's night mask suppressed 347 city-light pixels in an emission-only
  comparison; it introduced no brighter pixels. The lit sphere showed the ocean
  roughness highlights.
- The corona was centered and its transparent center preserved the sphere.
- Rendering exposed a washed-out Sun center caused by adding the same texture
  through both diffuse and emission. Stars now use black diffuse and the emission
  texture at intensity 1.0. The corrected render retains central granulation.

Harness, control images, and logs: `out/integration/material-render/`.
Corrected Sun preview: `sun-corona-emission-only-candidate.png` in that folder.
Earth preview: `earth-lit.png`. These are native material tests, not app screenshots.

## Device preview status

End-to-end app visual checks remain blocked by the local preview environment:

- The new `Foldspace Asset Review` simulator could not start `launchd_sim`.
- A preexisting iPhone 17 Pro reports Booted, but neither its boot-completion
  check nor a 25-second screenshot attempt completed. The CoreSimulator dyld
  cache builder was stuck without producing a cache.
- Bitrig app access through the computer-use tool timed out. No Bitrig preview
  was obtained.

The existing simulator app/save was not changed. No review copy was installed
because the simulator did not respond. A responsive simulator or device is
still needed to check movie compositing through a full loop, atlas animation,
Reduce Motion transitions, label contrast, and controls in the app. Existing demo
launch modes are `blackhole`, `galaxy`, `warp`, `sun`, `weapon`, and `andromeda`.

## Review

An independent source review checked alpha/layer ordering, movie lifecycle,
atlas order and bounds, texture scale, galaxy projection, shader symbols, and
Earth light-direction coordinates. No additional actionable issue was found.

The original asset validation remains in `assets/manifest.json`: all 42 PNGs
meet their contracts, and AVFoundation decoded all 360 movie frames with alpha.
This validates the encoded movie independently of the app's player layer.

For detailed source changes and remaining device acceptance checks, see
`assets/review-materials.md` and `assets/review-sequences.md`.
