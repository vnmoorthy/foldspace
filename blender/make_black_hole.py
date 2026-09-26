"""
make_black_hole.py — Sagittarius A* for FOLDSPACE's BlackHoleView / cockpit hologram.

LENSING: which trick, and why
  Default = OSL Schwarzschild geodesics ("--mode osl", Cycles CPU — Blender's OSL does not run on Metal).
  A camera-facing plane carries a Script node that, for every shading point, integrates the null
  geodesic back from the camera through the pixel using Binet's equation in u = 1/r:

        d²u/dφ² = −u + (3/2) r_s u²          (exact for Schwarzschild, G = c = 1)

  with the exact first integral (du/dφ)² = 1/b² − u²(1 − r_s u), b = impact parameter measured in the
  camera's local static frame. RK4, fixed Δφ. The ray ends in one of three ways:
    • r < r_s                → captured  → the shadow (black)
    • crosses the disc plane with r_ISCO ≤ r ≤ r_out → disc hit → returns (r, φ, cos θ_v)
    • r > r_far, moving out  → escaped   → the final direction samples the starfield (Environment node)
  Because the trace is the real thing, the photon ring, the Einstein-ring images of the starfield and the
  far side of the disc bent over and under the shadow (the Interstellar / DNGR look, James, von
  Tunzelmann, Franklin & Thorne 2015, CQG 32 065001) all fall out automatically. Kerr spin is NOT
  modelled (Sgr A* spin is poorly constrained; DNGR used a = 0.999 for Gargantua).

  "--mode fake" = node-only, GPU/EEVEE friendly look-dev proxy: weak-field thin-lens warp of the
  background (β = θ − θ_E²/θ, θ_E² = 2 r_s / D_L), an emissive annulus disc with the same Doppler node
  math, a photon-ring torus at the apparent shadow radius, and a black sphere. No far-side lensing.
  The refractive-sphere IOR trick was rejected: it inverts and converges the background but has no
  shadow, no photon ring and the wrong radial deflection profile (α ∝ 1/b is not a lens).

DOPPLER / REDSHIFT (node math in both modes, on the Script/geometry outputs)
  Keplerian orbital speed measured by a static observer at r:  β = sqrt(r_s / (2 (r − r_s)))  (β = ½ at ISCO)
  g = ν_obs/ν_em = sqrt(1 − r_s/r) · sqrt(1 − β²) / (1 − β cos θ_v)      (gravitational × Doppler)
  I_obs = g⁴ I_em (bolometric; I_ν/ν³ invariant),  T_obs = g · T_em,  colour = Blackbody(T_obs)
  T_em(r) ∝ r^-3/4 (Shakura & Sunyaev 1973 thin disc), peak colour temperature --tpeak (art: 9000 K)
  Approaching side brighter and bluer, receding side dimmer and redder: cos θ_v > 0 ⇒ g > 1.

NUMBERS (r_s = 1 scene unit)
  photon sphere 1.5 r_s, ISCO 3 r_s (6 GM/c²), apparent shadow radius √27/2 r_s = 2.598 r_s,
  Sgr A*: M = 4.3e6 M☉ → r_s = 1.27e10 m = 0.085 AU = 18 R☉; EHT ring 51.8 µas (2022).
  "--check" bisects the critical impact parameter with the same integrator: expect 2.598 r_s.

Run
  Blender --background --python make_black_hole.py -- --quick
  Blender --background --python make_black_hole.py -- --check
  Blender --background --python make_black_hole.py -- --frames 360 --res 1024 1024 --samples 8   # 12 s loop
  Blender --background --python make_black_hole.py -- --mode fake --engine EEVEE --quick
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import common  # noqa: E402
from common import log, math_node, vmath_node, noise, blackbody  # noqa: E402

R_S = 1.0
R_PHOTON = 1.5
R_ISCO = 3.0
SHADOW = math.sqrt(27) / 2


def add_flags(p):
    p.add_argument("--mode", choices=["osl", "fake"], default="osl")
    p.add_argument("--check", action="store_true", help="numerical physics check instead of rendering")
    p.add_argument("--distance", type=float, default=22.0, help="camera distance in r_s")
    p.add_argument("--incl", type=float, default=12.0, help="camera elevation above the disc plane, degrees")
    p.add_argument("--fov", type=float, default=46.0)
    p.add_argument("--rout", type=float, default=7.0, help="disc outer radius in r_s")
    p.add_argument("--tpeak", type=float, default=9000.0, help="disc colour temperature at ISCO (K)")
    p.add_argument("--stars", type=float, default=1.0, help="starfield strength (0 hides it)")
    p.add_argument("--alpha-disc-only", action="store_true", help="transparent where stars would be (HEVC-alpha overlay)")
    p.add_argument("--step", type=float, default=0.02, help="OSL integrator Δφ (radians)")


# ----------------------------------------------------------------------------- physics check (pure python)

def _trace(b, rs=R_S, r0=60.0, h=0.01, max_steps=20000):
    """Return 'captured' or 'escaped' for a ray with impact parameter b, fired from r0 toward the hole."""
    u = 1.0 / r0
    w = math.sqrt(max(0.0, 1.0 / (b * b) - u * u * (1 - rs * u)))    # moving inward: u increasing
    for _ in range(max_steps):
        def f(u_, w_):
            return w_, -u_ + 1.5 * rs * u_ * u_
        k1u, k1w = f(u, w)
        k2u, k2w = f(u + 0.5 * h * k1u, w + 0.5 * h * k1w)
        k3u, k3w = f(u + 0.5 * h * k2u, w + 0.5 * h * k2w)
        k4u, k4w = f(u + h * k3u, w + h * k3w)
        u += h / 6 * (k1u + 2 * k2u + 2 * k3u + k4u)
        w += h / 6 * (k1w + 2 * k2w + 2 * k3w + k4w)
        if u * rs >= 1.0:
            return "captured"
        if u <= 1.0 / (r0 * 1.5) and w < 0:
            return "escaped"
    return "captured"


def physics_check():
    lo, hi = 1.0, 6.0
    for _ in range(40):
        mid = 0.5 * (lo + hi)
        if _trace(mid) == "captured":
            lo = mid
        else:
            hi = mid
    b_crit = 0.5 * (lo + hi)
    beta_isco = math.sqrt(R_S / (2 * (R_ISCO - R_S)))
    g_face_on = math.sqrt(1 - R_S / R_ISCO) * math.sqrt(1 - beta_isco ** 2)
    g_expected = math.sqrt(1 - 1.5 * R_S / R_ISCO)
    print("BLACK HOLE PHYSICS CHECK (G = c = 1, r_s = 1)")
    print(f"  critical impact parameter  b_crit = {b_crit:.4f} r_s   expected √27/2 = {SHADOW:.4f}   "
          f"{'PASS' if abs(b_crit - SHADOW) < 0.01 else 'FAIL'}")
    print(f"  β at ISCO                        = {beta_isco:.4f}     expected 0.5000            "
          f"{'PASS' if abs(beta_isco - 0.5) < 1e-6 else 'FAIL'}")
    print(f"  g (face-on, ISCO)                = {g_face_on:.4f}     expected sqrt(1-3M/r) = {g_expected:.4f}  "
          f"{'PASS' if abs(g_face_on - g_expected) < 1e-6 else 'FAIL'}")
    for name, val in (("photon sphere", R_PHOTON), ("ISCO", R_ISCO), ("shadow radius", SHADOW)):
        print(f"  {name:14s} = {val:.3f} r_s")
    M = 4.3e6 * 1.98847e30
    rs_m = 2 * 6.674e-11 * M / 2.998e8 ** 2
    print(f"  Sgr A*: r_s = {rs_m:.3e} m = {rs_m / 1.496e11:.3f} AU = {rs_m / 6.957e8:.1f} R☉")
    L = 10.0
    print(f"  tidal Δa across {L:.0f} m at r_s: 2GM L / r³ = {2 * 6.674e-11 * M * L / rs_m ** 3:.2e} m/s² "
          f"(spaghettification happens far inside the horizon for a supermassive hole)")


# ----------------------------------------------------------------------------- OSL

OSL_SOURCE = r"""
// Schwarzschild null-geodesic tracer for one camera ray. G = c = 1, Rs in scene units.
shader schwarzschild(
    vector CamPos = vector(0, -22, 0),
    vector BH = vector(0, 0, 0),
    vector DiscNormal = vector(0, 0, 1),
    float Rs = 1.0,
    float RIsco = 3.0,
    float ROut = 7.0,
    float RFar = 140.0,
    float StepPhi = 0.02,
    int MaxSteps = 2000,
    float Spin = 1.0,
    output float Kind = 0.0,        // 0 escaped, 1 disc, 2 captured
    output vector EscapeDir = vector(0, 1, 0),
    output float R = 0.0,           // disc hit radius, units of Rs
    output float Phi = 0.0,         // disc azimuth, radians [0, 2pi)
    output float CosV = 0.0,        // cos(angle between orbital velocity and photon direction to camera)
    output float Swept = 0.0)       // total phi swept (diagnostic)
{
    vector n = normalize(DiscNormal);
    vector O = CamPos - BH;
    vector D = normalize(P - CamPos);
    float r0 = length(O);
    vector e1 = O / r0;
    float dr = dot(D, e1);
    vector perp = D - dr * e1;
    float sp = length(perp);
    if (sp < 1e-7) {
        if (dr < 0.0) { Kind = 2.0; } else { Kind = 0.0; EscapeDir = D; }
        return;
    }
    vector e2 = perp / sp;
    // fixed basis in the disc plane for Phi
    vector a1 = (fabs(n[0]) < 0.9) ? normalize(cross(n, vector(1, 0, 0))) : normalize(cross(n, vector(0, 1, 0)));
    vector a2 = cross(n, a1);

    float u = 1.0 / r0;
    float b = r0 * sp / sqrt(max(1.0 - Rs * u, 1e-6));
    float w2 = 1.0 / (b * b) - u * u * (1.0 - Rs * u);
    float w = sqrt(max(w2, 0.0));
    if (dr > 0.0) w = -w;                    // moving outward => u decreasing
    float phi = 0.0;
    vector pos_prev = O;
    float side_prev = dot(O, n);
    float h = StepPhi;

    for (int i = 0; i < MaxSteps; i++) {
        float k1u = w,                     k1w = -u + 1.5 * Rs * u * u;
        float u2 = u + 0.5 * h * k1u,      w2_ = w + 0.5 * h * k1w;
        float k2u = w2_,                   k2w = -u2 + 1.5 * Rs * u2 * u2;
        float u3 = u + 0.5 * h * k2u,      w3 = w + 0.5 * h * k2w;
        float k3u = w3,                    k3w = -u3 + 1.5 * Rs * u3 * u3;
        float u4 = u + h * k3u,            w4 = w + h * k3w;
        float k4u = w4,                    k4w = -u4 + 1.5 * Rs * u4 * u4;
        u += h / 6.0 * (k1u + 2.0 * k2u + 2.0 * k3u + k4u);
        w += h / 6.0 * (k1w + 2.0 * k2w + 2.0 * k3w + k4w);
        phi += h;
        Swept = phi;
        if (u * Rs >= 1.0) { Kind = 2.0; return; }             // through the horizon
        if (u <= 0.0) { Kind = 0.0; EscapeDir = normalize(pos_prev - O + 1e-3 * D); return; }
        float r = 1.0 / u;
        vector pos = r * (cos(phi) * e1 + sin(phi) * e2);
        float side = dot(pos, n);
        if (side * side_prev < 0.0) {
            float t = side_prev / (side_prev - side);
            vector hit = pos_prev + t * (pos - pos_prev);
            float rh = length(hit);
            if (rh >= RIsco * Rs && rh <= ROut * Rs) {
                vector d = normalize(pos - pos_prev);          // our marching direction (away from camera)
                vector rhat = hit / rh;
                vector that = normalize(cross(n, rhat)) * Spin; // orbital velocity direction
                CosV = dot(that, -d);                           // photon travels toward the camera: -d
                R = rh / Rs;
                Phi = atan2(dot(hit, a2), dot(hit, a1));
                if (Phi < 0.0) Phi += 2.0 * M_PI;
                Kind = 1.0;
                return;
            }
        }
        if (r > RFar && w < 0.0) { Kind = 0.0; EscapeDir = normalize(pos - pos_prev); return; }
        side_prev = side;
        pos_prev = pos;
    }
    Kind = 2.0;
}
"""


def disc_shading(nodes, links, scene, R, CosV, Phi, tpeak, rout):
    """Doppler-beamed, gravitationally redshifted thin-disc emission from (R, cos θ_v, φ). Returns (color, strength)."""
    # β = sqrt(1 / (2 (R − 1)))   (R in r_s units)
    beta = math_node(nodes, links, "SQRT", math_node(nodes, links, "DIVIDE", 1.0,
                     math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT", R, 1.0), 2.0)))
    inv_gamma = math_node(nodes, links, "SQRT", math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "MULTIPLY", beta, beta)))
    grav = math_node(nodes, links, "SQRT", math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "DIVIDE", 1.0, R)))
    denom = math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "MULTIPLY", beta, CosV))
    g = math_node(nodes, links, "DIVIDE", math_node(nodes, links, "MULTIPLY", grav, inv_gamma), denom)
    # T_em ∝ r^-3/4, normalised to tpeak at ISCO
    t_em = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "POWER", math_node(nodes, links, "DIVIDE", R_ISCO, R), 0.75), tpeak)
    t_obs = math_node(nodes, links, "MULTIPLY", t_em, g)
    color = blackbody(nodes, links, t_obs)
    # Flux ∝ T⁴ ∝ r^-3 times the g⁴ beaming factor
    g4 = math_node(nodes, links, "POWER", g, 4.0)
    flux = math_node(nodes, links, "POWER", math_node(nodes, links, "DIVIDE", R_ISCO, R), 3.0)
    # Loop-safe differential rotation: n(R) whole turns per loop, Ω ∝ R^-3/2 quantised.
    t = common.time_value(nodes, scene)
    T = common.loop_seconds(scene)
    n_turns = math_node(nodes, links, "ROUND", math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "POWER", R, -1.5), 26.0))
    n_turns = math_node(nodes, links, "MAXIMUM", n_turns, 1.0)
    phase = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "DIVIDE", t, T), math_node(nodes, links, "MULTIPLY", n_turns, 2 * math.pi))
    phi_r = math_node(nodes, links, "SUBTRACT", Phi, phase)
    comb = nodes.new("ShaderNodeCombineXYZ")
    links.new(math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "COSINE", phi_r), 1.6), comb.inputs["X"])
    links.new(math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SINE", phi_r), 1.6), comb.inputs["Y"])
    links.new(math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "LOGARITHM", R, math.e), 9.0), comb.inputs["Z"])
    streaks = noise(nodes, links, comb.outputs["Vector"], scale=1.0, detail=5.0, roughness=0.6)
    streaks = math_node(nodes, links, "MULTIPLY_ADD", streaks, 1.3, 0.25)
    rings = noise(nodes, links, comb.outputs["Vector"], scale=3.0, detail=1.0)
    tex = math_node(nodes, links, "MULTIPLY", streaks, math_node(nodes, links, "MULTIPLY_ADD", rings, 0.5, 0.75))
    # Soft outer edge
    edge = math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "DIVIDE",
                     math_node(nodes, links, "SUBTRACT", R, rout * 0.8), rout * 0.2, clamp=True))
    edge = math_node(nodes, links, "MAXIMUM", edge, 0.0)
    strength = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "MULTIPLY", g4, flux), math_node(nodes, links, "MULTIPLY", tex, edge))
    strength = math_node(nodes, links, "MULTIPLY", strength, 6.0)
    return color, strength, g


def build_osl(scene, args, cam, env_img):
    plane = common.add_billboard(scene, "lens_plane", cam, distance=1.0, fill=1.1)
    mat, nodes, links, out = common.new_material("schwarzschild", plane)
    txt = bpy.data.texts.new("schwarzschild.osl")
    txt.write(OSL_SOURCE)
    scr = nodes.new("ShaderNodeScript")
    scr.mode = "INTERNAL"
    scr.script = txt
    scr.update()
    scr.inputs["CamPos"].default_value = tuple(cam.matrix_world.translation)
    scr.inputs["BH"].default_value = (0, 0, 0)
    scr.inputs["DiscNormal"].default_value = (0, 0, 1)
    scr.inputs["Rs"].default_value = R_S
    scr.inputs["RIsco"].default_value = R_ISCO
    scr.inputs["ROut"].default_value = args.rout
    scr.inputs["RFar"].default_value = max(140.0, args.distance * 6)
    scr.inputs["StepPhi"].default_value = args.step
    scr.inputs["MaxSteps"].default_value = int(30.0 / args.step)
    scr.inputs["Spin"].default_value = 1.0

    kind = scr.outputs["Kind"]
    is_disc = math_node(nodes, links, "COMPARE", kind, 1.0, 0.5)
    is_black = math_node(nodes, links, "GREATER_THAN", kind, 1.5)
    env = nodes.new("ShaderNodeTexEnvironment")
    env.image = env_img
    links.new(scr.outputs["EscapeDir"], env.inputs["Vector"])
    stars = vmath_node(nodes, links, "SCALE", env.outputs["Color"], scale=args.stars)
    dcol, dstr, _ = disc_shading(nodes, links, scene, scr.outputs["R"], scr.outputs["CosV"], scr.outputs["Phi"], args.tpeak, args.rout)
    disc = vmath_node(nodes, links, "SCALE", dcol, scale=dstr)
    mixn = nodes.new("ShaderNodeMix")
    mixn.data_type = "VECTOR"
    links.new(is_disc, mixn.inputs["Factor"])
    links.new(stars, mixn.inputs[4])
    links.new(disc, mixn.inputs[5])
    color = vmath_node(nodes, links, "SCALE", mixn.outputs[1], scale=math_node(nodes, links, "SUBTRACT", 1.0, is_black))
    if args.alpha_disc_only:
        alpha = math_node(nodes, links, "MAXIMUM", is_disc, is_black)
    else:
        alpha = 1.0
    common.emission_over_transparent(nodes, links, out, color, 1.0, alpha)
    return plane


def build_fake(scene, args, cam, env_img):
    """Node-only proxy: thin-lens background + Doppler annulus + photon ring + shadow sphere."""
    D_L = args.distance
    theta_e2 = 2 * R_S / D_L
    cam_pos = tuple(cam.matrix_world.translation)
    c_dir = [-v / D_L for v in cam_pos]                      # unit vector camera → hole
    # Background plane far behind the hole
    bg = common.add_billboard(scene, "lensed_background", cam, distance=D_L * 3, fill=1.2)
    mat, nodes, links, out = common.new_material("thin_lens", bg)
    geo = nodes.new("ShaderNodeNewGeometry")
    v = vmath_node(nodes, links, "NORMALIZE", vmath_node(nodes, links, "SUBTRACT", geo.outputs["Position"], cam_pos))
    vc = vmath_node(nodes, links, "DOT_PRODUCT", v, tuple(c_dir))
    trans = vmath_node(nodes, links, "SUBTRACT", v, vmath_node(nodes, links, "SCALE", tuple(c_dir), scale=vc))
    theta2 = vmath_node(nodes, links, "DOT_PRODUCT", trans, trans)
    factor = math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "DIVIDE", theta_e2, math_node(nodes, links, "MAXIMUM", theta2, 1e-5)))
    src = vmath_node(nodes, links, "ADD", tuple(c_dir), vmath_node(nodes, links, "SCALE", trans, scale=factor))
    env = nodes.new("ShaderNodeTexEnvironment")
    env.image = env_img
    links.new(vmath_node(nodes, links, "NORMALIZE", src), env.inputs["Vector"])
    common.emission_over_transparent(nodes, links, out, vmath_node(nodes, links, "SCALE", env.outputs["Color"], scale=args.stars), 1.0,
                                     0.0 if args.alpha_disc_only else 1.0)
    # Shadow sphere at the apparent radius
    shadow = common.add_uv_sphere(scene, "shadow", radius=SHADOW * R_S, segments=64, rings=32)
    smat, sn, sl, so = common.new_material("shadow", shadow)
    em = sn.nodes.new("ShaderNodeEmission") if False else sn.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0, 0, 0, 1)
    sl.new(em.outputs[0], so.inputs["Surface"])
    # Photon ring: thin bright torus facing the camera at the shadow edge
    bpy.ops.mesh.primitive_torus_add(major_radius=SHADOW * R_S * 1.02, minor_radius=0.05 * R_S, major_segments=96, minor_segments=8)
    ring = bpy.context.active_object
    ring.name = "photon_ring"
    con = ring.constraints.new("TRACK_TO")
    con.target = cam
    con.track_axis = "TRACK_Z"
    con.up_axis = "UP_Y"
    rmat, rn, rl, ro = common.new_material("photon_ring", ring)
    em = rn.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1.0, 0.85, 0.6, 1)
    em.inputs["Strength"].default_value = 25.0
    rl.new(em.outputs[0], ro.inputs["Surface"])
    # Disc annulus with Doppler node math on Incoming
    bpy.ops.mesh.primitive_circle_add(vertices=128, radius=args.rout * R_S, fill_type="NGON")
    disc = bpy.context.active_object
    disc.name = "disc"
    dmat, dn, dl, do = common.new_material("disc_doppler", disc)
    tc = dn.new("ShaderNodeTexCoord")
    geo = dn.new("ShaderNodeNewGeometry")
    pos = geo.outputs["Position"]
    r = vmath_node(dn, dl, "LENGTH", pos)
    R = math_node(dn, dl, "DIVIDE", r, R_S)
    rhat = vmath_node(dn, dl, "NORMALIZE", pos)
    that = vmath_node(dn, dl, "NORMALIZE", vmath_node(dn, dl, "CROSS_PRODUCT", (0, 0, 1), rhat))
    cosv = vmath_node(dn, dl, "DOT_PRODUCT", that, geo.outputs["Incoming"])
    sep = dn.new("ShaderNodeSeparateXYZ")
    dl.new(pos, sep.inputs["Vector"])
    phi = math_node(dn, dl, "ARCTAN2", sep.outputs["Y"], sep.outputs["X"])
    inner = math_node(dn, dl, "GREATER_THAN", R, R_ISCO)
    dcol, dstr, _ = disc_shading(dn, dl, scene, R, cosv, phi, args.tpeak, args.rout)
    dstr = math_node(dn, dl, "MULTIPLY", dstr, inner)
    common.emission_over_transparent(dn, dl, do, dcol, dstr, inner)
    for m in (dmat,):
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
    return disc


def main():
    args = common.parse_args("FOLDSPACE Sagittarius A*", add_flags)
    if args.check:
        physics_check()
        return
    osl = args.mode == "osl"
    scene = common.fresh_scene(args, "black_hole", res=(1024, 1024), samples=(8 if osl else 64),
                               engine="CYCLES" if osl else (args.engine or "CYCLES"), frames=1,
                               transparent=args.alpha_disc_only, quick_samples=4, force_cpu=osl)
    if osl:
        if scene.render.engine != "CYCLES":
            scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.shading_system = True
        scene.cycles.use_denoising = False
        scene.cycles.use_adaptive_sampling = False
        log("OSL Schwarzschild tracer on CPU (Blender's OSL has no Metal backend)")
    inc = math.radians(args.incl)
    cam = common.add_camera(scene, (0.0, -args.distance * math.cos(inc), args.distance * math.sin(inc)), (0, 0, 0), fov_deg=args.fov)
    env_img = common.starfield_image(os.path.join(args.out, "starfield.exr"), width=2048 if not args.quick else 1024,
                                     height=1024 if not args.quick else 512, seed=args.seed)
    if osl:
        build_osl(scene, args, cam, env_img)
    else:
        build_fake(scene, args, cam, env_img)
    common.add_bloom(scene, threshold=1.5, strength=0.3, size=8)
    path = common.render(scene, args, "black_hole")
    if scene.frame_end <= 1:
        log(f"black_hole: {common.png_stats(path)}")
    log("OUTPUTS: " + path)


if __name__ == "__main__":
    main()
