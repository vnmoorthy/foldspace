"""
make_sun.py — the Sun for FOLDSPACE's SunDiveView / cockpit hologram.

Layers (all emission, Cycles or EEVEE, no lamps — the Sun is the lamp)
  * photosphere: Blackbody(5772 K) [G2V effective temperature, IAU 2015 nominal], granulation as a
    looping 4-D Voronoi cell field (bright cell centres, dark intergranular lanes; real granules are
    ~1000 km ≈ 1/700 R☉, drawn ~10x too large so they read at phone size), sunspots restricted to the
    ±30° activity belts with umbra ≈ 3800 K and penumbra ≈ 5000 K,
    and limb darkening I(μ)/I(1) = 1 − u(1 − μ), u = 0.6 (linear law, V band; Cox 2000, Allen's
    Astrophysical Quantities). μ = n·v from the Geometry node.
  * chromosphere: a 1.012 R☉ shell glowing Hα (656.3 nm) only at the limb.
  * corona: a camera-facing plane with the Baumbach (1937) white-light brightness law
    B(r)/B☉ = 0.0532 r^-2.5 + 1.425 r^-7 + 2.565 r^-17   (r in solar radii; real corona ≈ 10^-6 of the
    disc, scaled up ×10^5 here so it is visible next to the disc), modulated by radial streamers and a
    solar-minimum helmet-streamer belt (brighter at the equator ∝ cos² latitude).
  * prominences: Hα-red Bezier arches on the limb, 0.05–0.25 R☉ tall (real: 10^4–10^5 km ≈ 0.015–0.15 R☉).

Run
  Blender --background --python make_sun.py -- --quick
  Blender --background --python make_sun.py -- --frames 240        # 8 s seamless granulation loop
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import common  # noqa: E402
from common import log, math_node, vmath_node, noise, voronoi, mapping, blackbody  # noqa: E402

T_EFF = 5772.0
T_UMBRA = 3800.0
T_PENUMBRA = 5000.0
LIMB_U = 0.6


def add_flags(p):
    p.add_argument("--no-corona", action="store_true")
    p.add_argument("--prominences", type=int, default=4)
    p.add_argument("--granule-scale", type=float, default=70.0, help="Voronoi cells per unit (visual, not to scale)")
    p.add_argument("--spots", type=float, default=0.86, help="sunspot threshold 0..1 (higher = fewer spots)")
    p.add_argument("--dive", type=float, default=0.0,
                   help="0 = seen from space; 1 = camera inside the photosphere (SunDiveView backdrop)")


def loop_noise_w(nodes, links, scene, speed):
    """Two W values + blend factor that make any 4-D noise/Voronoi loop seamlessly over the animation."""
    t = common.time_value(nodes, scene)
    T = common.loop_seconds(scene)
    w0 = math_node(nodes, links, "MULTIPLY", t, speed)
    w1 = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT", t, T), speed)
    fac = math_node(nodes, links, "DIVIDE", t, max(T, 1e-6))
    return w0, w1, fac


def photosphere_material(scene, args, obj):
    mat, nodes, links, out = common.new_material("photosphere", obj)
    tc = nodes.new("ShaderNodeTexCoord")
    vec = tc.outputs["Object"]
    geo = nodes.new("ShaderNodeNewGeometry")

    # Granulation: F1 distance of a 4-D Voronoi, looped in W. Cell centres bright, lanes dark.
    w0, w1, fac = loop_noise_w(nodes, links, scene, speed=0.35)
    g0 = voronoi(nodes, links, vec, scale=args.granule_scale, feature="F1", dims="4D", w=w0).outputs["Distance"]
    g1 = voronoi(nodes, links, vec, scale=args.granule_scale, feature="F1", dims="4D", w=w1).outputs["Distance"]
    gran = math_node(nodes, links, "ADD", math_node(nodes, links, "MULTIPLY", g0, math_node(nodes, links, "SUBTRACT", 1.0, fac)),
                     math_node(nodes, links, "MULTIPLY", g1, fac))
    lanes = math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "MULTIPLY", gran, 1.15, clamp=True))
    lanes = math_node(nodes, links, "POWER", lanes, 0.7)
    fine = noise(nodes, links, vec, scale=180.0, detail=2.0)
    bright = math_node(nodes, links, "ADD", math_node(nodes, links, "MULTIPLY_ADD", lanes, 0.32, 0.80),
                       math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT", fine, 0.5), 0.08))

    # Sunspots: sparse Voronoi cells in the activity belts (|lat| < 30° → |z| < 0.5).
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(vec, sep.inputs["Vector"])
    absz = math_node(nodes, links, "ABSOLUTE", sep.outputs["Z"])
    belt = math_node(nodes, links, "LESS_THAN", absz, 0.5)
    sv = voronoi(nodes, links, mapping(nodes, links, vec, scale=(1, 1, 0.6)), scale=3.2, feature="F1")
    srand = nodes.new("ShaderNodeSeparateXYZ")
    links.new(sv.outputs["Color"], srand.inputs["Vector"])
    has_spot = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "GREATER_THAN", srand.outputs["X"], args.spots), belt)
    filaments = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT", noise(nodes, links, vec, scale=60.0, detail=2.0), 0.5), 0.05)
    sd = math_node(nodes, links, "ADD", sv.outputs["Distance"], filaments)
    umbra = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "LESS_THAN", sd, 0.10), has_spot)
    penumbra = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "LESS_THAN", sd, 0.19), has_spot)

    # Temperature field → Blackbody colour. Granules ±3 % around T_eff, spots much cooler.
    temp = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "MULTIPLY_ADD", lanes, 0.06, 0.97), T_EFF)
    temp = math_node(nodes, links, "ADD", math_node(nodes, links, "MULTIPLY", temp, math_node(nodes, links, "SUBTRACT", 1.0, penumbra)),
                     math_node(nodes, links, "MULTIPLY", penumbra, T_PENUMBRA))
    temp = math_node(nodes, links, "ADD", math_node(nodes, links, "MULTIPLY", temp, math_node(nodes, links, "SUBTRACT", 1.0, umbra)),
                     math_node(nodes, links, "MULTIPLY", umbra, T_UMBRA))
    col = blackbody(nodes, links, temp)

    # Limb darkening: μ = n·v ; I = 1 − u(1 − μ).
    mu = vmath_node(nodes, links, "DOT_PRODUCT", geo.outputs["Normal"], geo.outputs["Incoming"])
    mu = math_node(nodes, links, "MAXIMUM", mu, 0.0)
    limb = math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT", 1.0, mu), LIMB_U))
    # Spots darken the intensity too (umbra ≈ 20 % of the photosphere in white light).
    spotdim = math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "ADD",
                        math_node(nodes, links, "MULTIPLY", umbra, 0.8), math_node(nodes, links, "MULTIPLY", penumbra, 0.3)))
    strength = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "MULTIPLY", bright, limb), spotdim)
    strength = math_node(nodes, links, "MULTIPLY", strength, 14.0)

    em = nodes.new("ShaderNodeEmission")
    links.new(col, em.inputs["Color"])
    links.new(strength, em.inputs["Strength"])
    links.new(em.outputs[0], out.inputs["Surface"])
    return mat


def chromosphere_material(obj):
    mat, nodes, links, out = common.new_material("chromosphere", obj)
    geo = nodes.new("ShaderNodeNewGeometry")
    mu = math_node(nodes, links, "ABSOLUTE", vmath_node(nodes, links, "DOT_PRODUCT", geo.outputs["Normal"], geo.outputs["Incoming"]))
    rim = math_node(nodes, links, "POWER", math_node(nodes, links, "SUBTRACT", 1.0, mu), 10.0)
    tc = nodes.new("ShaderNodeTexCoord")
    spic = noise(nodes, links, tc.outputs["Object"], scale=90.0, detail=2.0)
    strength = math_node(nodes, links, "MULTIPLY", rim, math_node(nodes, links, "MULTIPLY_ADD", spic, 12.0, 8.0))
    col = nodes.new("ShaderNodeRGB")
    col.outputs[0].default_value = (1.0, 0.18, 0.08, 1.0)       # Hα
    common.emission_over_transparent(nodes, links, out, col.outputs[0], strength, math_node(nodes, links, "MULTIPLY", rim, 1.0, clamp=True))
    _blend(mat)
    mat.use_backface_culling = True
    return mat


def corona_material(scene, obj, size):
    """Baumbach K+F corona on a billboard. Local plane coords are ±size/2 solar radii."""
    mat, nodes, links, out = common.new_material("corona", obj)
    tc = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(tc.outputs["Object"], sep.inputs["Vector"])
    x = math_node(nodes, links, "MULTIPLY", sep.outputs["X"], size / 2.0)   # plane is unit-square scaled by `size`
    y = math_node(nodes, links, "MULTIPLY", sep.outputs["Y"], size / 2.0)
    r = math_node(nodes, links, "SQRT", math_node(nodes, links, "ADD", math_node(nodes, links, "MULTIPLY", x, x), math_node(nodes, links, "MULTIPLY", y, y)))
    r = math_node(nodes, links, "MAXIMUM", r, 1.0)
    baum = math_node(nodes, links, "ADD",
                     math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "POWER", r, -2.5), 0.0532),
                     math_node(nodes, links, "ADD",
                               math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "POWER", r, -7.0), 1.425),
                               math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "POWER", r, -17.0), 2.565)))
    # Streamers: noise stretched along r (low frequency in log r, higher in angle). Seamless in angle.
    ang = math_node(nodes, links, "ARCTAN2", y, x)
    cosA = math_node(nodes, links, "COSINE", ang)
    sinA = math_node(nodes, links, "SINE", ang)
    logr = math_node(nodes, links, "LOGARITHM", r, math.e)
    comb = nodes.new("ShaderNodeCombineXYZ")
    links.new(math_node(nodes, links, "MULTIPLY", cosA, 5.0), comb.inputs["X"])
    links.new(math_node(nodes, links, "MULTIPLY", sinA, 5.0), comb.inputs["Y"])
    links.new(math_node(nodes, links, "MULTIPLY", logr, 0.9), comb.inputs["Z"])
    w0, w1, fac = loop_noise_w(nodes, links, scene, speed=0.08)
    s0 = noise(nodes, links, comb.outputs["Vector"], scale=1.0, detail=4.0, roughness=0.55, dims="4D", w=w0)
    s1 = noise(nodes, links, comb.outputs["Vector"], scale=1.0, detail=4.0, roughness=0.55, dims="4D", w=w1)
    streak = math_node(nodes, links, "ADD", math_node(nodes, links, "MULTIPLY", s0, math_node(nodes, links, "SUBTRACT", 1.0, fac)),
                       math_node(nodes, links, "MULTIPLY", s1, fac))
    streak = math_node(nodes, links, "POWER", math_node(nodes, links, "MULTIPLY_ADD", streak, 1.6, -0.3, clamp=True), 1.8)
    # Helmet-streamer belt: brighter near the equator (plane x axis), ∝ cos² latitude.
    belt = math_node(nodes, links, "MULTIPLY_ADD", math_node(nodes, links, "MULTIPLY", cosA, cosA), 0.6, 0.4)
    brightness = math_node(nodes, links, "MULTIPLY", baum, math_node(nodes, links, "MULTIPLY", belt, math_node(nodes, links, "MULTIPLY_ADD", streak, 1.2, 0.35)))
    strength = math_node(nodes, links, "MULTIPLY", brightness, 2.2)
    col = nodes.new("ShaderNodeRGB")
    col.outputs[0].default_value = (1.0, 0.93, 0.8, 1.0)
    alpha = math_node(nodes, links, "MULTIPLY", brightness, 1.6, clamp=True)
    common.emission_over_transparent(nodes, links, out, col.outputs[0], strength, alpha)
    _blend(mat)
    return mat


def prominence_material():
    mat = bpy.data.materials.new("prominence")
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    tc = nodes.new("ShaderNodeTexCoord")
    n = noise(nodes, links, tc.outputs["Object"], scale=8.0, detail=3.0)
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1.0, 0.28, 0.10, 1.0)
    links.new(math_node(nodes, links, "MULTIPLY_ADD", n, 30.0, 12.0), em.inputs["Strength"])
    links.new(em.outputs[0], out.inputs["Surface"])
    return mat


def add_prominence(scene, mat, angle_deg, height, width, seed):
    """An arch of plasma on the limb in the plane facing the camera (x–z plane; camera looks along +y)."""
    a = math.radians(angle_deg)
    da = width / 2.0
    p0 = (math.cos(a - da), 0.0, math.sin(a - da))
    p3 = (math.cos(a + da), 0.0, math.sin(a + da))
    up = (math.cos(a) * (1 + height), 0.0, math.sin(a) * (1 + height))
    cu = bpy.data.curves.new(f"prom_{seed}", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 0.012 + 0.01 * (seed % 3)
    cu.bevel_resolution = 3
    cu.resolution_u = 24
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(2)
    pts = [p0, up, p3]
    for bp, p in zip(sp.bezier_points, pts):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(cu.name, cu)
    scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def _blend(mat):
    for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass


def main():
    args = common.parse_args("FOLDSPACE Sun", add_flags)
    scene = common.fresh_scene(args, "sun", res=(1024, 1024), samples=32, engine="CYCLES", transparent=True, quick_samples=6)
    if scene.render.engine == "CYCLES":
        scene.cycles.samples = max(scene.cycles.samples, 6)

    sun = common.add_uv_sphere(scene, "photosphere", radius=1.0, segments=128, rings=64)
    photosphere_material(scene, args, sun)
    chromo = common.add_uv_sphere(scene, "chromosphere", radius=1.012, segments=96, rings=48)
    chromosphere_material(chromo)

    corona_size = 7.0
    if not args.no_corona:
        bpy.ops.mesh.primitive_plane_add(size=1.0)
        corona = bpy.context.active_object
        corona.name = "corona"
        corona.scale = (corona_size, corona_size, 1)
        corona_material(scene, corona, corona_size)
    prom_mat = prominence_material()
    for i in range(args.prominences):
        ang = 25 + i * (300 / max(1, args.prominences)) + (args.seed * 17 + i * 53) % 25
        add_prominence(scene, prom_mat, ang, height=0.08 + 0.06 * ((i + args.seed) % 3), width=0.18 + 0.05 * (i % 2), seed=i)

    # Camera: from space (dive 0) to inside the photosphere (dive 1). SunDiveView maps hinge → depth.
    dist = 6.2 * (1 - args.dive) + 0.6 * args.dive
    cam = common.add_camera(scene, (0.0, -dist, 0.6 * (1 - args.dive)), (0, 0, 0), fov_deg=40)
    if not args.no_corona:
        con = corona.constraints.new("TRACK_TO")
        con.target = cam
        con.track_axis = "TRACK_Z"
        con.up_axis = "UP_Y"
    common.add_bloom(scene, threshold=2.0, strength=0.25, size=7)

    path = common.render(scene, args, "sun")
    if scene.frame_end <= 1:
        log(f"sun: {common.png_stats(path)}")
    log("OUTPUTS: " + path)


if __name__ == "__main__":
    main()
