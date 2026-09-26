"""
make_warp_bubble.py — the Alcubierre warp bubble for FOLDSPACE's WarpSequenceView.

Physics
  Alcubierre (1994, CQG 11 L73): metric ds² = −dt² + (dx − v_s f(r_s) dt)² + dy² + dz², with
      f(r_s) = [tanh(σ(r_s + R)) − tanh(σ(r_s − R))] / (2 tanh(σR)),   r_s = sqrt((x − x_s)² + y² + z²)
  The volume expansion of the space-like hypersurfaces (the York time) is
      θ = v_s (x_s / r_s) · df/dr_s,
      df/dr = σ [sech²(σ(r + R)) − sech²(σ(r − R))] / (2 tanh(σR))
  θ < 0 ahead of the ship (space contracts), θ > 0 behind (space expands), θ = 0 inside and far away:
  the passengers sit in flat space. This script draws exactly that surface (the famous Alcubierre
  figure) as a displaced grid: z = A·θ(x, y) on the z = 0 slice, colour = sign(θ): blue contraction,
  red expansion. Space "flows" through the wall at v_s, so the grid lines scroll toward −x; over the
  loop they advance an integer number of cells so the sprite sheet loops seamlessly.

  Starfield (--stars): the view from the bridge is drawn with special-relativistic aberration
      d_rest = (d' + [(γ − 1)(d'·v̂) − γβ] v̂) / (γ (1 − β d'·v̂))   (inverse map, sampled per pixel)
  and the Doppler factor D = 1 / (γ (1 − β cos θ')) with I' = D⁴ I and T' = D·T (blackbody tint).
  Caveat: inside a true Alcubierre bubble the ship is locally at rest; Clark, Hiscock & Larson (1999,
  CQG 16 3965) show the forward sky is blueshifted and aft redshifted by the bubble wall, with star
  positions displaced toward the direction of travel — qualitatively the same look, so we use the SR
  formulae as the tractable stand-in and say so.

Run
  Blender --background --python make_warp_bubble.py -- --quick
  Blender --background --python make_warp_bubble.py -- --frames 60 --res 512 512     # 2 s sprite loop
  Blender --background --python make_warp_bubble.py -- --quality 0.3 --quick         # collapsing variant
  Blender --background --python make_warp_bubble.py -- --stars --quick               # aberrated sky behind
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
import common  # noqa: E402
from common import log, math_node, vmath_node, noise, blackbody  # noqa: E402


def add_flags(p):
    p.add_argument("--R", type=float, default=4.0, help="bubble radius")
    p.add_argument("--sigma", type=float, default=2.0, help="wall steepness (thickness ~ 1/σ)")
    p.add_argument("--vs", type=float, default=1.0, help="bubble speed in c (York time scales linearly)")
    p.add_argument("--amp", type=float, default=1.6, help="vertical exaggeration of θ")
    p.add_argument("--quality", type=float, default=1.0, help="bubble stability 0..1 (<1 adds wall jitter)")
    p.add_argument("--form", action="store_true", help="animate the bubble forming and relaxing (shape key 0→1→0) instead of scrolling")
    p.add_argument("--stars", action="store_true", help="opaque render with an aberrated, Doppler-shifted starfield")
    p.add_argument("--beta", type=float, default=0.85, help="apparent β for the star aberration (visual)")
    p.add_argument("--cells", type=float, default=1.0, help="grid cells per scene unit")


def york_time(x, y, R, sigma, vs):
    r = np.sqrt(x * x + y * y)
    r_safe = np.maximum(r, 1e-6)
    sech2 = lambda a: 1.0 / np.cosh(a) ** 2
    dfdr = sigma * (sech2(sigma * (r_safe + R)) - sech2(sigma * (r_safe - R))) / (2.0 * math.tanh(sigma * R))
    return vs * (x / r_safe) * dfdr


def build_grid(scene, args):
    size_x, size_y = 40.0, 26.0
    nx, ny = (320, 208) if not args.quick else (200, 130)
    grid = common.add_grid(scene, "york_grid", size_x, size_y, nx, ny)
    me = grid.data
    n = len(me.vertices)
    co = np.empty(n * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    theta = york_time(co[:, 0], co[:, 1], args.R, args.sigma, args.vs)
    tmax = float(np.abs(theta).max())
    log(f"York time θ: min {theta.min():.3f}, max {theta.max():.3f} (v_s={args.vs}c, R={args.R}, σ={args.sigma}); "
        f"interior |θ| at origin = {abs(york_time(np.array([0.0]), np.array([0.0]), args.R, args.sigma, args.vs)[0]):.1e}")
    z = args.amp * theta / max(tmax, 1e-9)
    if args.quality < 1.0:
        rng = np.random.default_rng(args.seed)
        jitter = (1.0 - args.quality) * 0.35 * rng.normal(size=n) * (np.abs(theta) / tmax)
        z = z + jitter
    # Vertex colour attribute: contraction blue, expansion red, magnitude in alpha.
    att = me.color_attributes.new(name="york", type="FLOAT_COLOR", domain="POINT")
    mag = np.abs(theta) / max(tmax, 1e-9)
    cols = np.zeros((n, 4), dtype=np.float32)
    cols[:, 0] = np.clip(theta, 0, None) / max(tmax, 1e-9)         # R: expansion
    cols[:, 2] = np.clip(-theta, 0, None) / max(tmax, 1e-9)        # B: contraction
    cols[:, 1] = 0.15 * mag
    cols[:, 3] = mag
    att.data.foreach_set("color", cols.reshape(-1))
    if args.form:
        grid.shape_key_add(name="Basis")
        key = grid.shape_key_add(name="york")
        flat = co.copy()
        flat[:, 2] = z
        key.data.foreach_set("co", flat.reshape(-1))
        # flat → peak → flat (sine-eased), so an 8-frame sheet reads 0, ., ., peak, peak, ., ., 0 and loops.
        if scene.frame_end < 3:
            key.value = 1.0                                   # a single still: show the full surface
        else:
            mid = (1 + scene.frame_end) // 2
            for frame, value in ((1, 0.0), (mid, 1.0), (scene.frame_end, 0.0)):
                key.value = value
                key.keyframe_insert("value", frame=frame)
        for fc in common.action_fcurves(grid.data.shape_keys.animation_data.action):
            for kp in fc.keyframe_points:
                kp.interpolation = "SINE"
                kp.easing = "EASE_IN_OUT"
    else:
        co[:, 2] = z
        me.vertices.foreach_set("co", co.reshape(-1))
    me.update()
    bpy.ops.object.shade_smooth()
    return grid, tmax


def grid_material(scene, args, obj):
    mat, nodes, links, out = common.new_material("york_grid", obj)
    tc = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(tc.outputs["Object"], sep.inputs["Vector"])
    # Scroll toward −x at v_s; over the loop shift an integer number of cells.
    T = common.loop_seconds(scene)
    t = common.time_value(nodes, scene)
    cells_per_loop = max(1, round(args.vs * 3.0 * T)) if scene.frame_end > 1 else 0
    offset = math_node(nodes, links, "MULTIPLY", t, cells_per_loop / max(T, 1e-6))
    gx = math_node(nodes, links, "ADD", math_node(nodes, links, "MULTIPLY", sep.outputs["X"], args.cells), offset)
    gy = math_node(nodes, links, "MULTIPLY", sep.outputs["Y"], args.cells)

    def line(coord, width=0.06):
        """1 on a grid line (fract ≈ 0 or 1, i.e. d = |fract − ½| > ½ − width), 0 inside the cell."""
        f = math_node(nodes, links, "FRACT", coord)
        d = math_node(nodes, links, "ABSOLUTE", math_node(nodes, links, "SUBTRACT", f, 0.5))
        return math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT", d, 0.5 - width, clamp=True),
                         1.0 / width, clamp=True)

    lines = math_node(nodes, links, "MAXIMUM", line(gx), line(gy))
    lines = math_node(nodes, links, "POWER", lines, 0.6)
    attr = nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "york"
    york = attr.outputs["Color"]
    mag = attr.outputs["Alpha"]
    if args.form and obj.data.shape_keys is not None:
        # Colour and alpha follow the forming surface: scale the York attribute by the shape-key value.
        fv = nodes.new("ShaderNodeValue")
        fv.name = fv.label = "form"
        fc = fv.outputs[0].driver_add("default_value")
        fc.driver.type = "SCRIPTED"
        var = fc.driver.variables.new()
        var.name = "k"
        var.type = "SINGLE_PROP"
        var.targets[0].id_type = "KEY"
        var.targets[0].id = obj.data.shape_keys
        var.targets[0].data_path = 'key_blocks["york"].value'
        fc.driver.expression = "k"
        york = vmath_node(nodes, links, "SCALE", york, scale=fv.outputs[0])
        mag = math_node(nodes, links, "MULTIPLY", mag, fv.outputs[0])
    # Fill: York colour, lines: white-cyan, brighter over the wall.
    line_col = nodes.new("ShaderNodeRGB")
    line_col.outputs[0].default_value = (0.62, 0.95, 1.0, 1.0)
    fill = vmath_node(nodes, links, "SCALE", york, scale=1.4)
    mixn = nodes.new("ShaderNodeMix")
    mixn.data_type = "VECTOR"
    links.new(lines, mixn.inputs["Factor"])
    links.new(fill, mixn.inputs[4])
    links.new(vmath_node(nodes, links, "SCALE", line_col.outputs[0], scale=math_node(nodes, links, "MULTIPLY_ADD", mag, 2.5, 1.2)), mixn.inputs[5])
    alpha = math_node(nodes, links, "MAXIMUM", math_node(nodes, links, "MULTIPLY", lines, 0.9),
                      math_node(nodes, links, "MULTIPLY_ADD", mag, 0.55, 0.06), clamp=True)
    if args.quality < 1.0:
        flicker = noise(nodes, links, vmath_node(nodes, links, "ADD", tc.outputs["Object"],
                                                  vmath_node(nodes, links, "SCALE", (0, 0, 1), scale=math_node(nodes, links, "MULTIPLY", t, 40.0))),
                        scale=6.0, detail=2.0)
        alpha = math_node(nodes, links, "MULTIPLY", alpha, math_node(nodes, links, "MULTIPLY_ADD", flicker, 1.0 - args.quality, args.quality))
    common.emission_over_transparent(nodes, links, out, mixn.outputs[1], 1.0, alpha)
    _blend(mat)
    return mat


def bubble_shell(scene, args):
    shell = common.add_uv_sphere(scene, "bubble_wall", radius=args.R, segments=64, rings=32)
    mat, nodes, links, out = common.new_material("bubble_wall", shell)
    geo = nodes.new("ShaderNodeNewGeometry")
    mu = math_node(nodes, links, "ABSOLUTE", vmath_node(nodes, links, "DOT_PRODUCT", geo.outputs["Normal"], geo.outputs["Incoming"]))
    rim = math_node(nodes, links, "POWER", math_node(nodes, links, "SUBTRACT", 1.0, mu), 4.0)
    col = nodes.new("ShaderNodeRGB")
    col.outputs[0].default_value = (0.45, 0.9, 1.0, 1.0)
    common.emission_over_transparent(nodes, links, out, col.outputs[0], math_node(nodes, links, "MULTIPLY", rim, 3.0),
                                     math_node(nodes, links, "MULTIPLY", rim, 0.6 * args.quality + 0.2, clamp=True))
    _blend(mat)
    mat.use_backface_culling = True
    return shell


def ship_marker(scene):
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.35, depth=1.4, location=(0, 0, 0.25))
    ship = bpy.context.active_object
    ship.name = "ship"
    ship.rotation_euler = (0, math.radians(90), 0)
    mat, nodes, links, out = common.new_material("ship", ship)
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.6, 0.98, 1.0, 1)
    em.inputs["Strength"].default_value = 6.0
    links.new(em.outputs[0], out.inputs["Surface"])
    return ship


def aberrated_world(scene, args, env_img):
    """World shader: sample the starfield with SR aberration + Doppler for motion along +x at β."""
    beta = args.beta
    gamma = 1.0 / math.sqrt(1 - beta * beta)
    world = scene.world
    nt = world.node_tree
    nodes, links = nt.nodes, nt.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputWorld")
    tc = nodes.new("ShaderNodeTexCoord")
    d = vmath_node(nodes, links, "NORMALIZE", tc.outputs["Generated"])
    vhat = (1.0, 0.0, 0.0)
    cos_obs = vmath_node(nodes, links, "DOT_PRODUCT", d, vhat)
    # d_rest = (d' + [(γ−1) cos' − γβ] v̂) / (γ (1 − β cos'))
    coef = math_node(nodes, links, "SUBTRACT", math_node(nodes, links, "MULTIPLY", cos_obs, gamma - 1.0), gamma * beta)
    num = vmath_node(nodes, links, "ADD", d, vmath_node(nodes, links, "SCALE", vhat, scale=coef))
    den = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "MULTIPLY", cos_obs, beta)), gamma)
    d_rest = vmath_node(nodes, links, "NORMALIZE", vmath_node(nodes, links, "SCALE", num, scale=math_node(nodes, links, "DIVIDE", 1.0, den)))
    env = nodes.new("ShaderNodeTexEnvironment")
    env.image = env_img
    links.new(d_rest, env.inputs["Vector"])
    # Doppler: D = 1 / (γ (1 − β cos')) ; I' = D⁴ I ; T' = D·T → tint = BB(6000 D) / BB(6000)
    D = math_node(nodes, links, "DIVIDE", 1.0, den)
    d4 = math_node(nodes, links, "MINIMUM", math_node(nodes, links, "POWER", D, 4.0), 40.0)
    tint = vmath_node(nodes, links, "DIVIDE", blackbody(nodes, links, math_node(nodes, links, "MULTIPLY", D, 6000.0)), blackbody(nodes, links, 6000.0))
    col = vmath_node(nodes, links, "MULTIPLY", vmath_node(nodes, links, "SCALE", env.outputs["Color"], scale=d4), tint)
    bg = nodes.new("ShaderNodeBackground")
    links.new(col, bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    links.new(bg.outputs[0], out.inputs["Surface"])


def _blend(mat):
    for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass


def main():
    args = common.parse_args("FOLDSPACE Alcubierre warp bubble", add_flags)
    scene = common.fresh_scene(args, "warp_bubble", res=(512, 512), samples=32, engine="EEVEE", frames=60,
                               transparent=not args.stars, quick_samples=8)
    grid, tmax = build_grid(scene, args)
    grid_material(scene, args, grid)
    bubble_shell(scene, args)
    ship_marker(scene)
    common.add_camera(scene, (-14.0, -20.0, 13.0), (1.5, 0, 0), fov_deg=34)
    if args.stars:
        env_img = common.starfield_image(os.path.join(args.out, "starfield.exr"), width=2048 if not args.quick else 1024,
                                         height=1024 if not args.quick else 512, seed=args.seed)
        aberrated_world(scene, args, env_img)
    common.add_bloom(scene, threshold=1.2, strength=0.3, size=6)
    path = common.render(scene, args, "warp_bubble")
    if scene.frame_end <= 1:
        log(f"warp_bubble: {common.png_stats(path)}")
    log("OUTPUTS: " + path)


if __name__ == "__main__":
    main()
