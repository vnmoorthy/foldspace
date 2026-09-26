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
