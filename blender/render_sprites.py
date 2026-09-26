"""
render_sprites.py — pack a directory of rendered frames into a sprite sheet (+ JSON manifest), or
turn them into an HEVC-with-alpha .mov for AVPlayer.

Pack (Pillow if importable, else numpy through bpy — Blender's Python ships numpy but not Pillow):
  Blender --background --python render_sprites.py -- --frames-dir out/warp_bubble --cols 8
  → out/warp_bubble_sheet.png  +  out/warp_bubble_sheet.json
     {"frame_width": 512, "frame_height": 512, "columns": 8, "rows": 8, "count": 60, "fps": 30, ...}
  SpriteKit/SwiftUI reads frame i at (i % columns, i / columns). Keep sheets ≤ 4096×4096 (Metal
  texture limit on iPhone is 16384, but 4096 keeps memory at 64 MB RGBA and loads instantly).

HEVC with alpha (needs ffmpeg + Apple's avconvert; both present on this Mac):
  Blender --background --python render_sprites.py -- --frames-dir out/black_hole --hevc --fps 30
  → ffmpeg PNG → ProRes 4444 (yuva444p10le) → avconvert PresetHEVC1920x1080WithAlpha → out/black_hole.mov
  AVPlayerLayer plays it with transparency (hvc1, alpha channel), 12 s loop via AVPlayerLooper.

Self-test:
  Blender --background --python render_sprites.py -- --quick
  renders 16 tiny frames of a pulsing ring (EEVEE), packs a 4x4 sheet, verifies pixels round-trip.
"""

import glob
import json
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
import common  # noqa: E402
from common import log  # noqa: E402


def add_flags(p):
    # NB: common.parse_args already owns --frames (frame COUNT); the input directory is --frames-dir.
    p.add_argument("--frames-dir", "--dir", dest="frames_dir", default=None, help="directory of frame PNGs")
    p.add_argument("--pattern", default="*.png")
    p.add_argument("--cols", type=int, default=0, help="columns (default: ceil(sqrt(n)))")
    p.add_argument("--name", default=None, help="output basename (default <dir>_sheet)")
    p.add_argument("--max-frames", type=int, default=0)
    p.add_argument("--packer", choices=["auto", "pil", "bpy"], default="auto")
    p.add_argument("--hevc", action="store_true", help="also/only produce an HEVC-with-alpha .mov")
    p.add_argument("--no-sheet", action="store_true")


# ----------------------------------------------------------------------------- packers

def load_rgba_bpy(path):
    img = bpy.data.images.load(path, check_existing=False)
    img.colorspace_settings.name = "Non-Color"      # keep the stored bytes as they are
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1]                # top-down rows


def save_rgba_bpy(arr, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new("sheet", w, h, alpha=True, float_buffer=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).reshape(-1).astype(np.float32))
    img.file_format = "PNG"
    img.filepath_raw = path
    img.save()
    bpy.data.images.remove(img)


def pack(frames, cols, out_png, packer="auto"):
    n = len(frames)
    cols = cols or int(math.ceil(math.sqrt(n)))
    rows = int(math.ceil(n / cols))
    use_pil = packer in ("auto", "pil")
    if use_pil:
        try:
            from PIL import Image
        except ImportError:
            if packer == "pil":
                raise
            use_pil = False
    if use_pil:
        first = Image.open(frames[0]).convert("RGBA")
        fw, fh = first.size
        sheet = Image.new("RGBA", (cols * fw, rows * fh), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            im = Image.open(f).convert("RGBA")
            sheet.paste(im, ((i % cols) * fw, (i // cols) * fh))
        sheet.save(out_png, optimize=True)
        how = "Pillow"
    else:
        first = load_rgba_bpy(frames[0])
        fh, fw = first.shape[:2]
        sheet = np.zeros((rows * fh, cols * fw, 4), dtype=np.float32)
        for i, f in enumerate(frames):
            arr = first if i == 0 else load_rgba_bpy(f)
            y, x = (i // cols) * fh, (i % cols) * fw
            sheet[y:y + fh, x:x + fw] = arr[:fh, :fw]
        save_rgba_bpy(sheet, out_png)
        how = "bpy/numpy"
    return {"frame_width": fw, "frame_height": fh, "columns": cols, "rows": rows, "count": n, "packer": how}


def verify(frames, meta, out_png, index):
    """Check that frame `index` in the sheet equals the source frame (max abs diff in 8-bit units)."""
    sheet = load_rgba_bpy(out_png)
    src = load_rgba_bpy(frames[index])
    fh, fw, cols = meta["frame_height"], meta["frame_width"], meta["columns"]
    y, x = (index // cols) * fh, (index % cols) * fw
    crop = sheet[y:y + fh, x:x + fw]
    return float(np.abs(crop - src).max() * 255)


# ----------------------------------------------------------------------------- HEVC alpha

def hevc_alpha(frames_dir, pattern, fps, out_mov, width=None):
    ffmpeg = shutil.which("ffmpeg")
    avconvert = shutil.which("avconvert") or "/usr/bin/avconvert"
    if not ffmpeg or not os.path.exists(avconvert):
        log("ffmpeg/avconvert not found; skipping HEVC")
        return None
    frames = sorted(glob.glob(os.path.join(frames_dir, pattern)))
    # ffmpeg needs a printf pattern: derive from the first file name (frame_0001.png → frame_%04d.png)
    base = os.path.basename(frames[0])
    stem = base.rstrip("0123456789.png") if False else base[:len(base) - len(base.split("_")[-1])]
    digits = len(base.split("_")[-1].split(".")[0])
    start = int(base.split("_")[-1].split(".")[0])
    seq = os.path.join(frames_dir, f"{stem}%0{digits}d.png")
    prores = out_mov.replace(".mov", "_prores4444.mov")
    cmd1 = [ffmpeg, "-y", "-framerate", str(fps), "-start_number", str(start), "-i", seq,
            "-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le", prores]
    log(" ".join(cmd1))
    subprocess.run(cmd1, check=True)
    preset = "PresetHEVC3840x2160WithAlpha" if (width or 0) > 1920 else "PresetHEVC1920x1080WithAlpha"
    cmd2 = [avconvert, "--preset", preset, "--source", prores, "--output", out_mov, "--replace"]
    log(" ".join(cmd2))
    subprocess.run(cmd2, check=True)
    log(f"HEVC-alpha → {out_mov}  (import into Xcode, play with AVPlayerLayer + AVPlayerLooper)")
    return out_mov


# ----------------------------------------------------------------------------- self-test

def render_demo_frames(args, count=16, size=64):
    scene = common.fresh_scene(args, "sprites_demo", res=(size, size), samples=8, engine="EEVEE", frames=count,
                               transparent=True, quick_samples=8)
    scene.frame_end = count
    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.18, major_segments=48, minor_segments=12)
    ring = bpy.context.active_object
    mat, nodes, links, out = common.new_material("ring", ring)
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.3, 0.9, 1.0, 1)
    t = common.time_value(nodes, scene)
    T = common.loop_seconds(scene)
    pulse = common.math_node(nodes, links, "MULTIPLY_ADD",
                             common.math_node(nodes, links, "SINE", common.math_node(nodes, links, "MULTIPLY", t, 2 * math.pi / T)), 2.0, 3.0)
    links.new(pulse, em.inputs["Strength"])
    links.new(em.outputs[0], out.inputs["Surface"])
    ring.rotation_euler = (math.radians(60), 0, 0)
    ring.keyframe_insert("rotation_euler", frame=1)
    ring.rotation_euler = (math.radians(60), 0, 2 * math.pi)
    ring.keyframe_insert("rotation_euler", frame=count + 1)
    for fc in common.action_fcurves(ring.animation_data.action):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    common.add_camera(scene, (0, -4.5, 2.0), (0, 0, 0), fov_deg=40)
    d = common.render(scene, args, "sprites_quick")
    return d


def main():
    args = common.parse_args("FOLDSPACE sprite packer / HEVC-alpha exporter", add_flags)
    if args.quick and not args.frames_dir:
        args.frames_dir = render_demo_frames(args)
        args.cols = args.cols or 4
    if not args.frames_dir:
        log("nothing to do: pass --frames-dir DIR (or --quick for the self-test)")
        return
    frames = sorted(glob.glob(os.path.join(args.frames_dir, args.pattern)))
    if args.max_frames:
        frames = frames[:args.max_frames]
    if not frames:
        log(f"no frames matching {args.pattern} in {args.frames_dir}")
        return
    name = args.name or (os.path.basename(os.path.normpath(args.frames_dir)) + "_sheet")
    outputs = []
    if not args.no_sheet:
        out_png = os.path.join(args.out, f"{name}.png")
        meta = pack(frames, args.cols, out_png, args.packer)
        meta.update({"fps": args.fps, "duration": len(frames) / args.fps, "loop": True,
                     "frames": [os.path.basename(f) for f in frames]})
        with open(os.path.join(args.out, f"{name}.json"), "w") as fh:
            json.dump(meta, fh, indent=2)
        diff = verify(frames, meta, out_png, min(5, len(frames) - 1))
        log(f"sheet {meta['columns']}x{meta['rows']} of {meta['frame_width']}x{meta['frame_height']} "
            f"({meta['count']} frames, {meta['packer']}) → {out_png}; round-trip max diff {diff:.1f}/255 "
            f"{'OK' if diff <= 1.0 else 'MISMATCH'}")
        outputs += [out_png, out_png.replace(".png", ".json")]
    if args.hevc:
        mov = hevc_alpha(args.frames_dir, args.pattern, args.fps, os.path.join(args.out, f"{name.replace('_sheet', '')}.mov"))
        if mov:
            outputs.append(mov)
    log("OUTPUTS: " + ", ".join(outputs))


if __name__ == "__main__":
    main()
