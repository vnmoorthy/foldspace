# Sequence and galaxy integration review

Updated 2026-09-26. The initial source audit found procedural drawings in all four
sequence/map views. After app integration was authorized, the hooks below were
implemented. Build and simulator verification are handled by the coordinating
agent; this fragment records source changes and the checks they need.

## Implemented

| View | Change | Source |
|---|---|---|
| Warp | Eight cached 512² atlas crops, clamped frame selection, seam alignment, normal alpha blend | [WarpSequenceView.swift:202](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/UI/Sequences/WarpSequenceView.swift:202>) |
| Warp galaxies | Face-on Milky Way and Andromeda maps with existing travel transforms; Andromeda projected once at cos 77° | [WarpSequenceView.swift:275](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/UI/Sequences/WarpSequenceView.swift:275>) |
| Finale | Cached galaxy maps replace dotted spirals; dark dust survives normal compositing | [AndromedaFinaleView.swift:198](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/UI/Sequences/AndromedaFinaleView.swift:198>) |
| Galaxy map | 4:1 edge-on Milky Way band on the original diagonal, below routes and labels | [GalaxyMapView.swift:191](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/UI/GalaxyMap/GalaxyMapView.swift:191>) |
| Sun dive | Warm-white photosphere patch fades in near the surface and gives way to the procedural interior with depth | [SunDiveView.swift:256](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/Foldspace/UI/Sequences/SunDiveView.swift:256>) |

Images and atlas frames are loaded into static fields through the shared
`VisualAssets` helper. No file decode or atlas crop occurs inside animation frame
loops. Existing procedural drawing remains available when the corresponding
resource is absent. Low-quality warp effects, arrival flash, dive controls and
plasma remain active.

## Warp indexing and orientation

The atlas is 4096×512, containing eight 512×512 frames in left-to-right order.
Frames 0 and 7 are flat; frames 3 and 4 have peak deformation.

```text
p          = clamp(transitProgress, 0, 1)
frame      = min(7, floor(p * 8))
sourceRect = (frame * 512, 0, 512, 512)
```

`VisualAssets.frames` provides cropped images. Drawing a clipped full atlas inside
a square would otherwise select or scale the wrong pixels. The sprite gets a
copied graphics context with normal blend mode, so it does not inherit the
streak/ring pass's additive blending.

The source camera projects +x approximately 13° down from screen-right. Rotating
the tile −103° points the ship arrow upward through the seam, with the blue
contraction region ahead and red expansion behind. This orientation was checked
in `blender/codex/out/warp/warp-03.png`. The atlas has no collapsing variant;
existing collapse effects remain, with additional tile jitter and reduced opacity.

## Galaxy projection and alpha

The required `galaxy-andromeda.png` is face-on. Both sequence views now apply y
compression of 0.225, approximately cos 77°, instead of their previous 0.42/0.45
values. Rotation occurs in the galaxy plane before projection. The optional
`galaxy-andromeda-inclined.png` is not used here because it already includes its
inclination and position angle.

All galaxy images use normal alpha compositing. The galaxy-map edge band already
has an edge-on projection, retains its 4:1 aspect ratio, and receives no further
inclination compression. Its opacity is 0.34; confirm label contrast on both
portrait and wide layouts.

## Black-hole findings handed to the coordinating agent

The original `BlackHoleView.drawScene` filled its whole Canvas with opaque
`020309`, so simply putting a movie behind it would hide the movie. The required
layer order is background color/grid/stars, then movie or still, then transparent
foreground for lane/path/ship, with controls above. The movie must use ordinary
source-over compositing so its black shadow hides the starfield. The old procedural
disc/horizon/ring should run only as the missing-resource fallback.

The original star/grid cutoff was 1.35 rs, inside the asset's apparent shadow of
2.598 rs. Drawing those layers behind the movie handles their occlusion correctly.
All scene layers need the same stress shake to avoid the hole slipping relative
to the ship.

The exact image-to-gameplay mapping is determined by `HALF_VIEW = 12.0` in
[blackhole.py:22](</Users/moorthy/Downloads/Projects/Bitrig Hackathon/blender/codex/blackhole.py:22>):

```text
rsPx                   = 0.06 * min(viewWidth, viewHeight)
movie/still square     = 24 * rsPx on each side
                       = 1.44 * min(viewWidth, viewHeight)
movie/still center     = (viewWidth / 2, viewHeight / 2)
apparent shadow radius = (sqrt(27) / 2) * rsPx
```

For a 400-point shorter dimension, this is a 576-point square with a 62.35-point
shadow radius. The 1080-pixel movie has a shadow radius of approximately 116.9
pixels; the 2048-pixel still has approximately 221.7. They use the same destination
square. A square that merely fits the shorter viewport undersizes the shadow by
about 31%. Gameplay capture remains at r = rs; the apparent shadow is an optical
size, not a new event-horizon collision radius.

## Verification

Completed for these edits: source inspection and `git diff --check`. No build,
simulator launch or device rendering was run by this worker.

Focused runtime checks:

- Black hole: transparent corners, opaque shadow, identical movie/still size,
  visible ship and controls, aligned shake, and one complete 12-second loop.
- Warp: flat/peak/flat at progress 0/0.5/1, no tile bleed, forward arrow toward the
  seam, and readable low-quality and arrival effects.
- Finale/map: dark dust, one Andromeda projection, and readable labels on narrow
  and wide layouts.
- Sun dive: visible granulation at surface depth, complete fade before the core,
  no image edge during drift, and visible controls/plasma throughout.

Source contract: `docs/BLENDER-VISUALS-PLAN.md` sections “iOS hook”. Export
conventions: `assets/NOTES.md` sections “Sagittarius A*”, “Sprite assets” and
“Galaxies”.
