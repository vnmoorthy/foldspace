"""
common.py — shared helpers for the FOLDSPACE Blender scripts.

Every make_*.py script does:

    import common
    args = common.parse_args("what this script does", extra=add_my_flags)
    scene = common.fresh_scene(args, name="sun", res=(1024, 1024), samples=64, engine="CYCLES")
    ...build...
    common.render(scene, args, name="sun")

Run headless:

    /Applications/Blender.app/Contents/MacOS/Blender --background --python make_sun.py -- --quick

`--quick` = 256x256, few samples, a single frame, into blender/out/, rendered on the CPU.
Everything after the bare `--` is ours; Blender swallows the rest. Final renders default to the
Metal GPU; Cycles' Metal backend hangs inside sandboxed shells, so pass `--device CPU` there.
"""

import argparse
import math
import os
import sys
import time

import bpy
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT_DEFAULT = os.path.join(ROOT, "out")

_T0 = time.time()


def log(msg):
    print(f"[foldspace +{time.time() - _T0:6.1f}s] {msg}", flush=True)


# ----------------------------------------------------------------------------- args

def parse_args(description, extra=None):
    """Parse everything after `--`. `extra(parser)` adds script-specific flags."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser(description=description)
    p.add_argument("--quick", action="store_true", help="256x256, few samples, 1 frame, CPU, < 60 s")
    p.add_argument("--final", action="store_true",
                   help="full-resolution defaults (this is also the default when --quick is absent; --quick wins if both)")
    p.add_argument("--out", default=OUT_DEFAULT, help="output directory (default blender/out)")
    p.add_argument("--res", type=int, nargs=2, metavar=("W", "H"), default=None)
    p.add_argument("--samples", type=int, default=None)
    p.add_argument("--frames", type=int, default=None, help="frames to render (1 = still)")
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--engine", choices=["CYCLES", "EEVEE"], default=None)
    p.add_argument("--device", choices=["CPU", "GPU", "AUTO"], default="AUTO",
                   help="AUTO = CPU for --quick, Metal GPU otherwise. NOTE: Cycles' Metal backend hangs inside "
                        "sandboxed shells (e.g. Claude Code's Bash tool); run from Terminal for GPU, or pass "
                        "--device CPU / set FOLDSPACE_DEVICE=CPU")
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--view", choices=["AgX", "Filmic", "Standard"], default="AgX")
    p.add_argument("--save-blend", action="store_true", help="also write out/<name>.blend for Astra")
    if extra:
        extra(p)
    args = p.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    return args


# ----------------------------------------------------------------------------- scene

def _enable_gpu():
    """Turn on Metal for Cycles. Returns True if a GPU device is active."""
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        found = False
        for d in prefs.devices:
            d.use = d.type != "CPU"
            found = found or d.use
        return found
    except Exception as e:  # pragma: no cover
        log(f"GPU enable failed ({e}); falling back to CPU")
        return False


def fresh_scene(args, name, res=(1024, 1024), samples=64, engine="CYCLES", frames=1,
                transparent=True, quick_samples=None, force_cpu=False):
    """Wipe the default scene and configure render settings from args + per-script defaults."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = name

    engine = args.engine or engine
    w, h = args.res or (res if not args.quick else (256, 256))
    if args.quick:
        samples = quick_samples if quick_samples is not None else (4 if engine == "CYCLES" else 8)
        frames = 1
    else:
        samples = args.samples or samples
        frames = args.frames or frames

    scene.render.engine = "CYCLES" if engine == "CYCLES" else "BLENDER_EEVEE"
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.resolution_percentage = 100
    scene.render.fps = args.fps
    scene.frame_start = 1
    scene.frame_end = max(1, frames)
    scene.render.film_transparent = transparent
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.compression = 50
    scene.render.use_persistent_data = True

    if scene.render.engine == "CYCLES":
        cyc = scene.cycles
        cyc.samples = samples
        cyc.use_denoising = not args.quick and samples >= 16
        cyc.use_adaptive_sampling = True
        cyc.max_bounces = 4
        cyc.transparent_max_bounces = 8
        cyc.volume_bounces = 0
        cyc.caustics_reflective = False
        cyc.caustics_refractive = False
        device = args.device
        if device == "AUTO":
            device = "CPU" if args.quick else "GPU"
        env_dev = os.environ.get("FOLDSPACE_DEVICE", "").upper()
        if env_dev in ("CPU", "GPU"):
            device = env_dev
        want_gpu = device == "GPU" and not force_cpu
        if want_gpu:
            log("enabling Metal (if this line is the last thing you see, Metal is hanging: rerun with --device CPU)")
        cyc.device = "GPU" if (want_gpu and _enable_gpu()) else "CPU"
        log(f"Cycles on {cyc.device}, {samples} samples, {w}x{h}, {scene.frame_end} frame(s)")
    else:
        ee = scene.eevee
        ee.taa_render_samples = samples
        log(f"EEVEE, {samples} samples, {w}x{h}, {scene.frame_end} frame(s)")

    set_view_transform(scene, args.view)
    scene.world = bpy.data.worlds.new(f"{name}_world")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0, 0, 0, 1)
        bg.inputs["Strength"].default_value = 0.0
    return scene


def set_view_transform(scene, name="AgX"):
    vs = scene.view_settings
    for candidate in (name, "AgX", "Filmic", "Standard"):
        try:
            vs.view_transform = candidate
            break
        except TypeError:
            continue
    try:
        vs.look = "None"
    except TypeError:
        pass
    vs.exposure = 0.0
    vs.gamma = 1.0


# ----------------------------------------------------------------------------- objects

def add_camera(scene, location, target=(0, 0, 0), fov_deg=35.0, name="Camera"):
    cam_data = bpy.data.cameras.new(name)
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(fov_deg)
    cam_data.clip_start = 0.01
    cam_data.clip_end = 5000
    cam = bpy.data.objects.new(name, cam_data)
    scene.collection.objects.link(cam)
    cam.location = location
    look_at(cam, target)
    scene.camera = cam
    return cam


def look_at(obj, target, up=(0, 0, 1)):
    """Point -Z of obj at target (camera/light convention)."""
    from mathutils import Vector
    direction = Vector(target) - Vector(obj.location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_sun_light(scene, direction_from, energy=5.0, color=(1, 1, 1), angle_deg=0.53, name="Sun"):
    """A directional light shining *from* `direction_from` toward the origin."""
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = energy
    ld.color = color
    ld.angle = math.radians(angle_deg)
    lo = bpy.data.objects.new(name, ld)
    scene.collection.objects.link(lo)
    lo.location = direction_from
    look_at(lo, (0, 0, 0))
    return lo


def add_uv_sphere(scene, name, radius=1.0, segments=128, rings=64, location=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=location)
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.shade_smooth()
    return obj


def add_grid(scene, name, size_x, size_y, nx, ny):
    """A subdivided plane (nx x ny quads) centred at the origin, lying in XY."""
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=nx, y_subdivisions=ny, size=1.0)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size_x, size_y, 1)
    bpy.ops.object.transform_apply(scale=True)
    return obj


def add_billboard(scene, name, camera, distance, fill=1.05):
    """A plane parented to the camera that exactly fills the frame at `distance`."""
    cam_data = camera.data
    h = 2 * distance * math.tan(cam_data.angle_y / 2) * fill
    aspect = scene.render.resolution_x / scene.render.resolution_y
    w = h * aspect
    bpy.ops.mesh.primitive_plane_add(size=1.0)
    obj = bpy.context.active_object
    obj.name = name
    obj.parent = camera
    obj.matrix_parent_inverse.identity()
    obj.location = (0, 0, -distance)
    obj.rotation_euler = (0, 0, 0)
    obj.scale = (w, h, 1)
    return obj


# ----------------------------------------------------------------------------- materials

def new_material(name, obj=None):
    """Fresh node material with just an Output node. Returns (mat, nodes, links, output_node)."""
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (600, 0)
    if obj is not None:
        if obj.data.materials:
            obj.data.materials[0] = mat
        else:
            obj.data.materials.append(mat)
    return mat, nt.nodes, nt.links, out


def node(nodes, kind, **props):
    """nodes.new + attribute assignment. `inputs` kwarg sets socket defaults by name/index."""
    n = nodes.new(kind)
    inputs = props.pop("inputs", None)
    for k, v in props.items():
        setattr(n, k, v)
    if inputs:
        for k, v in inputs.items():
            n.inputs[k].default_value = v
    return n


def math_node(nodes, links, op, a=None, b=None, c=None, **kw):
    """A Math node wired from sockets or constants. Returns its output socket."""
    n = nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = kw.get("clamp", False)
    for i, v in enumerate((a, b, c)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            links.new(v, n.inputs[i])
    return n.outputs[0]


def vmath_node(nodes, links, op, a=None, b=None, scale=None):
    n = nodes.new("ShaderNodeVectorMath")
    n.operation = op
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (tuple, list)):
            n.inputs[i].default_value = v
        else:
            links.new(v, n.inputs[i])
    if scale is not None:
        if isinstance(scale, (int, float)):
            n.inputs["Scale"].default_value = scale
        else:
            links.new(scale, n.inputs["Scale"])
    return n.outputs["Value"] if op in ("DOT_PRODUCT", "LENGTH", "DISTANCE") else n.outputs["Vector"]


def ramp(nodes, links, fac, stops, interpolation="LINEAR"):
    """ColorRamp from [(pos, (r,g,b,a)), ...]. Returns (color_socket, alpha_socket)."""
    n = nodes.new("ShaderNodeValToRGB")
    cr = n.color_ramp
    cr.interpolation = interpolation
    while len(cr.elements) > 1:
        cr.elements.remove(cr.elements[-1])
    cr.elements[0].position = stops[0][0]
    cr.elements[0].color = stops[0][1]
    for pos, col in stops[1:]:
        e = cr.elements.new(pos)
        e.color = col
    if isinstance(fac, (int, float)):
        n.inputs["Fac"].default_value = fac
    else:
        links.new(fac, n.inputs["Fac"])
    return n.outputs["Color"], n.outputs["Alpha"]


def noise(nodes, links, vector, scale=5.0, detail=4.0, roughness=0.5, distortion=0.0, dims="3D", w=None):
    n = nodes.new("ShaderNodeTexNoise")
    n.noise_dimensions = dims
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = roughness
    n.inputs["Distortion"].default_value = distortion
    if vector is not None:
        links.new(vector, n.inputs["Vector"])
    if w is not None and dims == "4D":
        if isinstance(w, (int, float)):
            n.inputs["W"].default_value = w
        else:
            links.new(w, n.inputs["W"])
    return n.outputs["Fac"]


def voronoi(nodes, links, vector, scale=5.0, feature="F1", distance="EUCLIDEAN", randomness=1.0, dims="3D", w=None):
    n = nodes.new("ShaderNodeTexVoronoi")
    n.voronoi_dimensions = dims
    n.feature = feature
    n.distance = distance
    n.inputs["Scale"].default_value = scale
    n.inputs["Randomness"].default_value = randomness
    if vector is not None:
        links.new(vector, n.inputs["Vector"])
    if w is not None and dims == "4D":
        if isinstance(w, (int, float)):
            n.inputs["W"].default_value = w
        else:
            links.new(w, n.inputs["W"])
    return n


def mapping(nodes, links, vector, scale=(1, 1, 1), rotation=(0, 0, 0), location=(0, 0, 0)):
    n = nodes.new("ShaderNodeMapping")
    n.inputs["Scale"].default_value = scale
    n.inputs["Rotation"].default_value = rotation
    n.inputs["Location"].default_value = location
    links.new(vector, n.inputs["Vector"])
    return n.outputs["Vector"]


def blackbody(nodes, links, temperature):
    n = nodes.new("ShaderNodeBlackbody")
    if isinstance(temperature, (int, float)):
        n.inputs["Temperature"].default_value = temperature
    else:
        links.new(temperature, n.inputs["Temperature"])
    return n.outputs["Color"]


def emission_over_transparent(nodes, links, out, color, strength, alpha):
    """Emission shown with `alpha` on a transparent film (Mix Shader Transparent→Emission)."""
    em = nodes.new("ShaderNodeEmission")
    links.new(color, em.inputs["Color"])
    if isinstance(strength, (int, float)):
        em.inputs["Strength"].default_value = strength
    else:
        links.new(strength, em.inputs["Strength"])
    tr = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    if isinstance(alpha, (int, float)):
        mix.inputs["Fac"].default_value = alpha
    else:
        links.new(alpha, mix.inputs["Fac"])
    links.new(tr.outputs[0], mix.inputs[1])
    links.new(em.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], out.inputs["Surface"])
    return mix


def time_value(nodes, scene, name="Time"):
    """A Value node driven by the scene frame: seconds = frame / fps. Loop length = frame_end / fps."""
    v = nodes.new("ShaderNodeValue")
    v.name = v.label = name
    fc = v.outputs[0].driver_add("default_value")
    fc.driver.type = "SCRIPTED"
    fc.driver.expression = f"(frame - 1) / {scene.render.fps}"
    return v.outputs[0]


def loop_seconds(scene):
    return scene.frame_end / scene.render.fps


def action_fcurves(action):
    """Every F-curve of an Action, on any Blender version. 4.4+ 'slotted' actions keep them in
    layers → strips → channelbags and no longer expose `action.fcurves` (5.x removes it)."""
    if action is None:
        return []
    fcs = getattr(action, "fcurves", None)
    if fcs is not None:
        try:
            return list(fcs)
        except Exception:
            pass
    out = []
    for layer in getattr(action, "layers", []):
        for strip in getattr(layer, "strips", []):
            for cb in getattr(strip, "channelbags", []):
                out.extend(cb.fcurves)
    return out


# ----------------------------------------------------------------------------- compositor glare

def add_bloom(scene, threshold=1.0, strength=0.35, size=7):
    """Post-process glare so emissive things bloom. Blender 5.x keeps the compositor in
    `scene.compositing_node_group` (a CompositorNodeTree ending in a Group Output); 4.x used
    `scene.node_tree` + a Composite node. Both are handled; failure only disables bloom."""
    try:
        scene.render.use_compositing = True
        if hasattr(scene, "compositing_node_group"):
            nt = scene.compositing_node_group
            if nt is None:
                nt = bpy.data.node_groups.new(f"{scene.name}_compositor", "CompositorNodeTree")
                scene.compositing_node_group = nt
            nt.nodes.clear()
            has_out = any(getattr(item, "in_out", "") == "OUTPUT" for item in nt.interface.items_tree)
            if not has_out:
                nt.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
            comp = nt.nodes.new("NodeGroupOutput")
            comp_in = comp.inputs[0]
        else:
            scene.use_nodes = True
            nt = scene.node_tree
            nt.nodes.clear()
            comp = nt.nodes.new("CompositorNodeComposite")
            comp_in = comp.inputs["Image"]
        rl = nt.nodes.new("CompositorNodeRLayers")
        rl.scene = scene
        glare = nt.nodes.new("CompositorNodeGlare")
        # 5.x: the glare type is a menu socket; 4.x: an enum property.
        if "Type" in glare.inputs:
            for t in ("BLOOM", "FOG_GLOW"):
                try:
                    glare.inputs["Type"].default_value = t
                    break
                except (TypeError, ValueError):
                    continue
        else:
            for t in ("BLOOM", "FOG_GLOW"):
                try:
                    glare.glare_type = t
                    break
                except TypeError:
                    continue
        # Blender ≤ 4.3 took an integer `size` 6–9 (blur = 2^size px); 4.4+/5.x take a 0–1 fraction of the
        # image. Accept the legacy integer and convert, so `size=7` never means "flood the whole frame".
        if size > 1.0:
            max_res = max(scene.render.resolution_x, scene.render.resolution_y, 1)
            rel_size = max(0.02, min(0.35, (2.0 ** size) / max_res))
        else:
            rel_size = size
        for key, val in (("Threshold", threshold), ("Strength", strength), ("Size", rel_size), ("Mix", 0.0),
                         ("Quality", "MEDIUM")):
            if key in glare.inputs:
                try:
                    glare.inputs[key].default_value = val
                except Exception:
                    pass
            elif hasattr(glare, key.lower()):
                try:
                    setattr(glare, key.lower(), val)
                except Exception:
                    pass
        nt.links.new(rl.outputs["Image"], glare.inputs["Image"])
        nt.links.new(glare.outputs["Image"], comp_in)
        log(f"bloom: glare threshold {threshold}, strength {strength}, size {rel_size:.3f} of frame")
        return True
    except Exception as e:
        log(f"bloom skipped: {e}")
        scene.render.use_compositing = False
        return False


# ----------------------------------------------------------------------------- starfield (numpy)

def _kelvin_to_rgb(t):
    """Tanner Helland's approximation of the Planckian locus, 1000-40000 K -> linear-ish RGB 0..1."""
    t = np.clip(t, 1000, 40000) / 100.0
    r = np.where(t <= 66, 255.0, 329.698727446 * np.power(np.maximum(t - 60, 1e-3), -0.1332047592))
    g = np.where(t <= 66, 99.4708025861 * np.log(np.maximum(t, 1e-3)) - 161.1195681661,
                 288.1221695283 * np.power(np.maximum(t - 60, 1e-3), -0.0755148492))
    b = np.where(t >= 66, 255.0, np.where(t <= 19, 0.0, 138.5177312231 * np.log(np.maximum(t - 10, 1e-3)) - 305.0447927307))
    rgb = np.stack([r, g, b], axis=-1) / 255.0
    return np.clip(rgb, 0, 1) ** 2.2


def starfield_image(path, width=2048, height=1024, count=9000, seed=7, milky_way=True, max_intensity=40.0):
    """Equirectangular HDR starfield (EXR): Gaussian-PSF stars with blackbody colours + a Milky Way band.
    Returns a bpy Image loaded from `path`."""
    rng = np.random.default_rng(seed)
    img = np.zeros((height, width, 3), dtype=np.float32)

    # Stars: uniform on the sphere -> equirect via (lon, lat); magnitudes log-uniform.
    lon = rng.uniform(0, 2 * np.pi, count)
    lat = np.arcsin(rng.uniform(-1, 1, count))
    x = (lon / (2 * np.pi) * width).astype(int) % width
    y = ((0.5 - lat / np.pi) * height).astype(int) % height
    mag = rng.exponential(1.1, count)                  # most stars faint, a few bright
    inten = np.minimum(max_intensity, 0.15 * np.exp(mag * 1.35))
    temp = np.exp(rng.normal(np.log(5500), 0.45, count))
    col = _kelvin_to_rgb(temp) * inten[:, None]
    for dx, dy, wgt in ((0, 0, 1.0), (1, 0, 0.35), (-1, 0, 0.35), (0, 1, 0.35), (0, -1, 0.35),
                        (1, 1, 0.12), (-1, 1, 0.12), (1, -1, 0.12), (-1, -1, 0.12)):
        np.add.at(img, ((y + dy) % height, (x + dx) % width), col * wgt)

    if milky_way:
        # A tilted great circle of diffuse light with fBm-ish clumps and dark dust.
        yy, xx = np.mgrid[0:height, 0:width]
        lon_g = xx / width * 2 * np.pi
        lat_g = (0.5 - yy / height) * np.pi
        tilt = math.radians(60)
        # Galactic latitude of each pixel for a plane tilted by `tilt` about the x axis.
        b = np.arcsin(np.clip(np.sin(lat_g) * math.cos(tilt) - np.cos(lat_g) * np.sin(lon_g) * math.sin(tilt), -1, 1))
        band = np.exp(-(b / math.radians(9)) ** 2)
        clumps = np.zeros_like(band)
        for octave in range(4):
            f = 2 ** octave
            small = rng.uniform(0, 1, (8 * f + 1, 16 * f + 1)).astype(np.float32)
            ys = np.linspace(0, 8 * f, height)
            xs = np.linspace(0, 16 * f, width)
            yi = np.clip(ys.astype(int), 0, 8 * f - 1)
            xi = np.clip(xs.astype(int), 0, 16 * f - 1)
            fy = (ys - yi)[:, None]
            fx = (xs - xi)[None, :]
            v = (small[yi][:, xi] * (1 - fx) * (1 - fy) + small[yi][:, xi + 1] * fx * (1 - fy)
                 + small[yi + 1][:, xi] * (1 - fx) * fy + small[yi + 1][:, xi + 1] * fx * fy)
            clumps += v / (2 ** octave)
        clumps /= clumps.max()
        dust = np.clip(1.4 * (clumps - 0.45), 0, 1) * np.exp(-(b / math.radians(4)) ** 2)
        mw = band * (0.35 + 0.65 * clumps) * (1 - 0.85 * dust)
        img += (mw[..., None] * np.array([0.9, 0.85, 1.0], dtype=np.float32) * 0.6)

    flat = np.concatenate([img, np.ones((height, width, 1), dtype=np.float32)], axis=-1)[::-1].reshape(-1)
    bimg = bpy.data.images.new("starfield", width, height, alpha=True, float_buffer=True)
    bimg.colorspace_settings.name = "Linear Rec.709" if "Linear Rec.709" in _colorspaces() else "Non-Color"
    bimg.pixels.foreach_set(flat)
    bimg.file_format = "OPEN_EXR"
    bimg.filepath_raw = path
    bimg.save()
    loaded = bpy.data.images.load(path, check_existing=False)
    return loaded


def _colorspaces():
    try:
        return [i.identifier for i in bpy.types.ColorManagedInputColorspaceSettings.bl_rna.properties["name"].enum_items]
    except Exception:
        return []


# ----------------------------------------------------------------------------- render

def render(scene, args, name, subdir=None):
    """Still -> out/<name>.png. Animation -> out/<name>/frame_0001.png ... Returns the path/dir."""
    t = time.time()
    if scene.frame_end <= 1:
        path = os.path.join(args.out, f"{name}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        log(f"rendered {path} in {time.time() - t:.1f}s")
        result = path
    else:
        d = os.path.join(args.out, subdir or name)
        os.makedirs(d, exist_ok=True)
        scene.render.filepath = os.path.join(d, "frame_")
        bpy.ops.render.render(animation=True)
        log(f"rendered {scene.frame_end} frames into {d} in {time.time() - t:.1f}s "
            f"({(time.time() - t) / scene.frame_end:.1f}s/frame)")
        result = d
    if args.save_blend:
        bp = os.path.join(args.out, f"{name}.blend")
        bpy.ops.wm.save_as_mainfile(filepath=bp)
        log(f"saved {bp}")
    return result


def png_stats(path):
    """Quick sanity numbers for a rendered PNG: size, mean RGB, alpha coverage."""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    stats = {
        "size": (w, h),
        "mean_rgb": tuple(round(float(v), 3) for v in px[..., :3].mean(axis=(0, 1))),
        "max_rgb": tuple(round(float(v), 3) for v in px[..., :3].max(axis=(0, 1))),
        "alpha_coverage": round(float((px[..., 3] > 0.02).mean()), 3),
    }
    bpy.data.images.remove(img)
    return stats
