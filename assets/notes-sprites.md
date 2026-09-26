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
