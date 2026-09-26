# FOLDSPACE asset generators

Deliverables are in `../../assets/`. These scripts follow
`docs/BLENDER-CODEX-BRIEF.md`; all scene imagery is procedural or computed from
equations. App source and Xcode configuration are owned by the iOS agent.

## Regenerate

Requires Blender 5.2, bundled NumPy, and macOS FFmpeg with the VideoToolbox encoder
for the HEVC-alpha movie. No Blender add-ons or downloaded image maps are needed.

```sh
python3 blender/codex/render_all.py --quick
python3 blender/codex/render_all.py --final
```

Run from the repository root. The driver renders sequentially to keep memory use
predictable. Quick mode writes 256 px previews below `blender/codex/out/` and does
not replace delivered files. Individual commands and physics choices appear in
`assets/NOTES.md`. Each executable generator accepts `-- --quick` or `-- --final`
when called through Blender. `blackhole.py` also accepts `--still-only` or
`--resume` to continue unchanged interrupted final renders.

## Validate

The native decoder checks the actual Apple HEVC alpha layer; software FFmpeg
decoding alone cannot validate that layer.

```sh
clang -fobjc-arc -Wno-deprecated-declarations -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo blender/codex/verify_movie.m -o blender/codex/out/verify_movie
blender/codex/out/verify_movie assets/video/blackhole-loop.mov > blender/codex/out/blackhole/movie-verification.json
python3 blender/codex/validate_assets.py --final
```

Validation uses system Python with Pillow and NumPy. It checks every required
filename, image mode and size, transparency, nonempty atlas frames, movie timing,
codec, and native decoded alpha. `assets/manifest.json` contains hashes, byte sizes,
image metadata, and the movie verification result. The validator's `--quick`
mode checks whichever final files already exist without requiring the complete set.

`out/` contains disposable previews, movie frames, logs, and compiled verification
utilities. It is ignored by Git; the source scripts and the `assets/` handoff are
the durable deliverables. Avoid parallel high-resolution Blender jobs on a machine
already running the simulator or other renders.
