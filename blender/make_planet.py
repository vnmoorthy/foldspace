"""
make_planet.py — procedural planets for FOLDSPACE's nine `PlanetClass` values
(rocky, lava, desert, ice, ocean, superEarth, gasGiant, iceGiant, earthlike).

What it makes
  * a lit "beauty" render of one class (or all nine with --all): out/planet_<class>.png, RGBA
  * with --bake: an equirectangular albedo map baked from the same node material,
    out/planet_<class>_albedo.png (2048x1024; 256x128 in --quick) — the drop-in for
    PlanetMaterials.texture(for:) — plus out/planet_lava_emission.png for lava worlds.

Physics that must hold
  * Atmosphere rim = single-scattering Rayleigh: per-channel optical depth τ_c ∝ λ_c^-4 with
    λ = 680/550/440 nm → weights (0.175, 0.41, 1.0). Scattered light 1 - exp(-τ·chord) is blue for
    thin paths, whitens at the limb where the chord is long; the transmitted sunlight
    exp(-τ·secant(sun)) reddens near the terminator (sunset ring). Day side only (n·L > 0).
  * Gas-giant bands are a function of latitude (object-space z) with turbulence added to z,
    i.e. zonal flow, not longitude; the Great-Red-Spot-style storm is an anticyclonic oval
    sitting in a band, elongated along longitude.
  * Lava emission is thermal: Blackbody node at 1200–1700 K (basalt liquidus ≈ 1450 K), masked
    to the crack network (Voronoi distance-to-edge) and to lava lakes.
  * Ice caps beyond |lat| ≈ 60° (|z| > 0.85), deserts within |lat| < 20°.

Run
  Blender --background --python make_planet.py -- --quick                 # earthlike beauty + tiny bake
  Blender --background --python make_planet.py -- --planet gasGiant --bake
  Blender --background --python make_planet.py -- --all
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import common  # noqa: E402
from common import log, math_node, vmath_node, ramp, noise, voronoi, mapping, blackbody  # noqa: E402

CLASSES = ["rocky", "lava", "desert", "ice", "ocean", "superEarth", "gasGiant", "iceGiant", "earthlike"]

# Rayleigh weights ∝ λ^-4, normalised to blue (R 680 nm, G 550 nm, B 440 nm).
RAYLEIGH = (0.175, 0.41, 1.0)

ATMOSPHERE = {
    # class: (tint rgb, density k, rim power, sunset strength)
    "earthlike": ((0.55, 0.75, 1.0), 2.2, 3.0, 1.0),
    "ocean": ((0.5, 0.75, 1.0), 2.6, 3.0, 1.0),
    "superEarth": ((0.85, 0.8, 0.75), 3.5, 2.2, 0.6),   # thick haze, less blue
    "gasGiant": ((1.0, 0.92, 0.78), 1.4, 3.5, 0.5),
    "iceGiant": ((0.55, 0.9, 1.0), 2.0, 3.0, 0.3),
}


def add_flags(p):
    p.add_argument("--planet", default="earthlike", choices=CLASSES)
    p.add_argument("--all", action="store_true", help="render all nine classes (beauty only)")
    p.add_argument("--bake", action="store_true", help="bake equirect albedo (+emission for lava)")
    p.add_argument("--bake-size", type=int, nargs=2, metavar=("W", "H"), default=None)
    p.add_argument("--base-hex", default=None, help="override the class base colour, e.g. C4613A (Mars)")
    p.add_argument("--rings", action="store_true", help="add a Saturn-style ring plane")


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


# ----------------------------------------------------------------------------- shared node bits

def sphere_coords(nodes, links, seed):
    """Object-space coordinates of the unit sphere, offset per seed so every world differs."""
    tc = nodes.new("ShaderNodeTexCoord")
    return mapping(nodes, links, tc.outputs["Object"], location=(seed * 1.37 % 7, seed * 0.61 % 5, seed * 2.1 % 11))


def z_of(nodes, links, vec):
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(vec, sep.inputs["Vector"])
    return sep.outputs["X"], sep.outputs["Y"], sep.outputs["Z"]


def smoothstep(nodes, links, x, e0, e1):
    """smoothstep(e0, e1, x) with Math nodes."""
    t = math_node(nodes, links, "DIVIDE", math_node(nodes, links, "SUBTRACT", x, e0), e1 - e0)
    t = math_node(nodes, links, "MINIMUM", math_node(nodes, links, "MAXIMUM", t, 0.0), 1.0)
    return math_node(nodes, links, "SMOOTH_MIN", t, t, 0.0) if False else \
        math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "MULTIPLY", t, t),
                  math_node(nodes, links, "SUBTRACT", 3.0, math_node(nodes, links, "MULTIPLY", t, 2.0)))


def mix_rgb(nodes, links, fac, a, b, blend="MIX"):
    n = nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    n.blend_type = blend
    if isinstance(fac, (int, float)):
        n.inputs["Factor"].default_value = fac
    else:
        links.new(fac, n.inputs["Factor"])
    for sock, val in ((n.inputs[6], a), (n.inputs[7], b)):   # A / B colour sockets
        if isinstance(val, (tuple, list)):
            sock.default_value = (*val, 1.0) if len(val) == 3 else val
        else:
            links.new(val, sock)
    return n.outputs[2]


def rgb(nodes, color):
    n = nodes.new("ShaderNodeRGB")
    n.outputs[0].default_value = (*color, 1.0)
    return n.outputs[0]


def scale_rgb(nodes, links, color, k):
    return vmath_node(nodes, links, "SCALE", color, scale=k)


# ----------------------------------------------------------------------------- surface materials

def surface_material(cls, seed, base_override=None, obj=None):
    mat, nodes, links, out = common.new_material(f"planet_{cls}", obj)
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs[0], out.inputs["Surface"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Specular IOR Level"].default_value = 0.35
    vec = sphere_coords(nodes, links, seed)
    x, y, z = z_of(nodes, links, vec)
    absz = math_node(nodes, links, "ABSOLUTE", z)
    color = None
    roughness = 0.9
    emission = None

    if cls == "rocky":
        base = base_override or (0.46, 0.41, 0.36)
        n1 = noise(nodes, links, vec, scale=4.0, detail=8.0, roughness=0.55)
        crat = voronoi(nodes, links, vec, scale=9.0, feature="F1")
        d = crat.outputs["Distance"]
        rnd = crat.outputs["Color"]
        rx, _, _ = z_of(nodes, links, rnd)
        has = math_node(nodes, links, "GREATER_THAN", rx, 0.55)
        floor = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "LESS_THAN", d, 0.30), has)
        rim = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "MULTIPLY",
                        math_node(nodes, links, "GREATER_THAN", d, 0.30), math_node(nodes, links, "LESS_THAN", d, 0.40)), has)
        shade = math_node(nodes, links, "ADD", math_node(nodes, links, "MULTIPLY_ADD", n1, 0.5, 0.75),
                          math_node(nodes, links, "SUBTRACT", math_node(nodes, links, "MULTIPLY", rim, 0.25),
                                    math_node(nodes, links, "MULTIPLY", floor, 0.3)))
        color = scale_rgb(nodes, links, rgb(nodes, base), shade)
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.6
        links.new(math_node(nodes, links, "ADD", math_node(nodes, links, "MULTIPLY", n1, 0.3),
                            math_node(nodes, links, "SUBTRACT", rim, floor)), bump.inputs["Height"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        roughness = 0.95

    elif cls == "lava":
        base = base_override or (0.12, 0.09, 0.08)
        n1 = noise(nodes, links, vec, scale=5.0, detail=7.0)
        color = scale_rgb(nodes, links, rgb(nodes, base), math_node(nodes, links, "MULTIPLY_ADD", n1, 0.8, 0.5))
        edge = voronoi(nodes, links, vec, scale=7.0, feature="DISTANCE_TO_EDGE").outputs["Distance"]
        crack = math_node(nodes, links, "SUBTRACT", 1.0, smoothstep(nodes, links, edge, 0.0, 0.05))
        density = smoothstep(nodes, links, noise(nodes, links, vec, scale=2.0, detail=3.0), 0.42, 0.55)
        lakes = smoothstep(nodes, links, noise(nodes, links, vec, scale=3.0, detail=6.0, roughness=0.6), 0.66, 0.74)
        glow = math_node(nodes, links, "MAXIMUM", math_node(nodes, links, "MULTIPLY", crack, density), lakes, clamp=True)
        temp = math_node(nodes, links, "MULTIPLY_ADD", noise(nodes, links, vec, scale=6.0, detail=2.0), 500.0, 1200.0)
        emission = (blackbody(nodes, links, temp), math_node(nodes, links, "MULTIPLY", glow, 8.0))
        roughness = 0.9

    elif cls == "desert":
        base = base_override or (0.76, 0.52, 0.32)
        dunes = nodes.new("ShaderNodeTexWave")
        dunes.wave_type = "BANDS"
        dunes.bands_direction = "DIAGONAL"
        dunes.inputs["Scale"].default_value = 9.0
        dunes.inputs["Distortion"].default_value = 3.0
        dunes.inputs["Detail"].default_value = 3.0
        links.new(vec, dunes.inputs["Vector"])
        n1 = noise(nodes, links, vec, scale=3.0, detail=7.0)
        dark = smoothstep(nodes, links, noise(nodes, links, vec, scale=2.2, detail=5.0), 0.58, 0.68)
        shade = math_node(nodes, links, "MULTIPLY_ADD", dunes.outputs["Fac"], 0.25, 0.8)
        shade = math_node(nodes, links, "MULTIPLY", shade, math_node(nodes, links, "MULTIPLY_ADD", n1, 0.4, 0.8))
        sand = scale_rgb(nodes, links, rgb(nodes, base), shade)
        color = mix_rgb(nodes, links, dark, sand, scale_rgb(nodes, links, rgb(nodes, base), 0.45))
        cap = math_node(nodes, links, "MULTIPLY", smoothstep(nodes, links, absz, 0.86, 0.93), 0.9)
        color = mix_rgb(nodes, links, cap, color, (0.9, 0.9, 0.92))
        roughness = 0.95

    elif cls == "ice":
        base = base_override or (0.86, 0.92, 0.97)
        edge = voronoi(nodes, links, vec, scale=5.0, feature="DISTANCE_TO_EDGE").outputs["Distance"]
        crack = math_node(nodes, links, "SUBTRACT", 1.0, smoothstep(nodes, links, edge, 0.0, 0.03))
        n1 = noise(nodes, links, vec, scale=4.0, detail=6.0)
        shade = math_node(nodes, links, "MULTIPLY_ADD", n1, 0.3, 0.8)
        color = mix_rgb(nodes, links, math_node(nodes, links, "MULTIPLY", crack, 0.8),
                        scale_rgb(nodes, links, rgb(nodes, base), shade), (0.25, 0.45, 0.7))
        roughness = 0.5

    elif cls == "ocean":
        base = base_override or (0.03, 0.15, 0.4)
        h = noise(nodes, links, vec, scale=2.5, detail=7.0, roughness=0.55)
        land = smoothstep(nodes, links, h, 0.60, 0.63)
        depth, _ = ramp(nodes, links, h, [(0.30, (0.01, 0.05, 0.22, 1)), (0.55, (*base, 1)), (0.60, (0.1, 0.5, 0.6, 1))])
        landcol, _ = ramp(nodes, links, h, [(0.60, (0.55, 0.5, 0.3, 1)), (0.68, (0.2, 0.35, 0.12, 1)), (0.8, (0.4, 0.38, 0.3, 1))])
        color = mix_rgb(nodes, links, land, depth, landcol)
        roughness = mix_rgb(nodes, links, land, (0.28, 0.28, 0.28), (0.85, 0.85, 0.85))

    elif cls == "superEarth":
        base = base_override or (0.52, 0.47, 0.4)
        n1 = noise(nodes, links, vec, scale=3.0, detail=8.0, roughness=0.6)
        rift = voronoi(nodes, links, vec, scale=3.0, feature="DISTANCE_TO_EDGE").outputs["Distance"]
        rmask = math_node(nodes, links, "SUBTRACT", 1.0, smoothstep(nodes, links, rift, 0.0, 0.05))
        shade = math_node(nodes, links, "MULTIPLY_ADD", n1, 0.6, 0.6)
        color = mix_rgb(nodes, links, math_node(nodes, links, "MULTIPLY", rmask, 0.7),
                        scale_rgb(nodes, links, rgb(nodes, base), shade), (0.18, 0.12, 0.1))
        basins = smoothstep(nodes, links, noise(nodes, links, vec, scale=1.8, detail=4.0), 0.56, 0.62)
        color = mix_rgb(nodes, links, basins, color, (0.28, 0.3, 0.22))
        roughness = 0.85

    elif cls in ("gasGiant", "iceGiant"):
        turb = noise(nodes, links, vec, scale=2.5, detail=5.0, roughness=0.5)
        fine = noise(nodes, links, vec, scale=12.0, detail=3.0)
        zp = math_node(nodes, links, "ADD", z, math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT", turb, 0.5), 0.12))
        zp = math_node(nodes, links, "ADD", zp, math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT", fine, 0.5), 0.03))
        comb = nodes.new("ShaderNodeCombineXYZ")
        links.new(zp, comb.inputs["Z"])
        band = noise(nodes, links, comb.outputs["Vector"], scale=(6.0 if cls == "gasGiant" else 4.0), detail=2.0, roughness=0.4)
        if cls == "gasGiant":
            stops = [(0.30, (0.62, 0.36, 0.25, 1)), (0.42, (0.85, 0.78, 0.65, 1)), (0.5, (0.72, 0.55, 0.38, 1)),
                     (0.58, (0.92, 0.9, 0.85, 1)), (0.68, (0.66, 0.45, 0.3, 1))]
            if base_override:
                b = base_override
                stops = [(p, (b[0] * c[0] / 0.75, b[1] * c[1] / 0.6, b[2] * c[2] / 0.45, 1)) for p, c in stops]
            color, _ = ramp(nodes, links, band, stops)
            # Anticyclonic storm: an oval elongated along longitude, sitting at −22° latitude.
            lat0, lon0 = math.radians(-22), math.radians(35 + seed * 40 % 300)
            centre = (math.cos(lat0) * math.cos(lon0), math.cos(lat0) * math.sin(lon0), math.sin(lat0))
            dvec = vmath_node(nodes, links, "SUBTRACT", vec, centre)
            dvec = vmath_node(nodes, links, "MULTIPLY", dvec, (1.0, 1.0, 2.2))
            dist = vmath_node(nodes, links, "LENGTH", dvec)
            swirl = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT",
                              noise(nodes, links, vec, scale=25.0, detail=2.0), 0.5), 0.05)
            dist = math_node(nodes, links, "ADD", dist, swirl)
            spot = math_node(nodes, links, "SUBTRACT", 1.0, smoothstep(nodes, links, dist, 0.16, 0.24))
            color = mix_rgb(nodes, links, spot, color, (0.78, 0.33, 0.22))
            roughness = 0.8
        else:
            base = base_override or (0.35, 0.62, 0.85)
            stops = [(0.35, (base[0] * 0.8, base[1] * 0.85, base[2] * 0.95, 1)), (0.5, (*base, 1)),
                     (0.65, (min(1, base[0] * 1.5), min(1, base[1] * 1.25), min(1, base[2] * 1.1), 1))]
            color, _ = ramp(nodes, links, band, stops)
            storms = smoothstep(nodes, links, noise(nodes, links, vec, scale=6.0, detail=3.0), 0.72, 0.78)
            color = mix_rgb(nodes, links, storms, color, (0.95, 0.97, 1.0))
            roughness = 0.7

    elif cls == "earthlike":
        h = noise(nodes, links, vec, scale=2.2, detail=8.0, roughness=0.55)
        h = math_node(nodes, links, "ADD", h, math_node(nodes, links, "MULTIPLY",
                      math_node(nodes, links, "SUBTRACT", noise(nodes, links, vec, scale=7.0, detail=4.0), 0.5), 0.12))
        sea = 0.52
        land = smoothstep(nodes, links, h, sea - 0.004, sea + 0.004)
        ocean, _ = ramp(nodes, links, h, [(0.30, (0.01, 0.04, 0.16, 1)), (sea - 0.06, (0.03, 0.12, 0.35, 1)),
                                          (sea, (0.08, 0.42, 0.55, 1))])
        landcol, _ = ramp(nodes, links, h, [(sea, (0.16, 0.36, 0.12, 1)), (sea + 0.08, (0.12, 0.28, 0.09, 1)),
                                            (sea + 0.16, (0.45, 0.36, 0.22, 1)), (sea + 0.24, (0.55, 0.5, 0.45, 1)),
                                            (sea + 0.3, (0.9, 0.9, 0.9, 1))])
        # Deserts inside |lat| < 20° where it is dry (noise), ice caps beyond ~60°.
        dry = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT", 1.0, smoothstep(nodes, links, absz, 0.25, 0.4)),
                        smoothstep(nodes, links, noise(nodes, links, vec, scale=3.0, detail=3.0), 0.5, 0.6))
        landcol = mix_rgb(nodes, links, dry, landcol, (0.76, 0.62, 0.4))
        capline = math_node(nodes, links, "SUBTRACT", 0.86, math_node(nodes, links, "MULTIPLY",
                            noise(nodes, links, vec, scale=4.0, detail=3.0), 0.08))
        cap = smoothstep(nodes, links, math_node(nodes, links, "SUBTRACT", absz, capline), 0.0, 0.03)
        color = mix_rgb(nodes, links, land, ocean, landcol)
        color = mix_rgb(nodes, links, cap, color, (0.93, 0.95, 0.98))
        roughness = mix_rgb(nodes, links, land, (0.22, 0.22, 0.22), (0.85, 0.85, 0.85))
        roughness = mix_rgb(nodes, links, cap, roughness, (0.55, 0.55, 0.55))

    links.new(color, bsdf.inputs["Base Color"])
    if isinstance(roughness, (int, float)):
        bsdf.inputs["Roughness"].default_value = roughness
    else:
        links.new(roughness, bsdf.inputs["Roughness"])
    if emission is not None:
        col, strength = emission
        links.new(col, bsdf.inputs["Emission Color"])
        links.new(strength, bsdf.inputs["Emission Strength"])
    return mat


# ----------------------------------------------------------------------------- shells

def per_channel_scatter(nodes, links, path, k, weights):
    """colour_c = 1 - exp(-k * weights_c * path) — single-scattering Rayleigh brightness."""
    comps = []
    for w in weights:
        tau = math_node(nodes, links, "MULTIPLY", path, k * w)
        comps.append(math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "EXPONENT",
                               math_node(nodes, links, "MULTIPLY", tau, -1.0))))
    comb = nodes.new("ShaderNodeCombineXYZ")
    for sock, c in zip(("X", "Y", "Z"), comps):
        links.new(c, comb.inputs[sock])
    return comb.outputs["Vector"]


def per_channel_transmit(nodes, links, path, k, weights):
    """colour_c = exp(-k * weights_c * path) — sunlight surviving a long slant path (reddening)."""
    comps = []
    for w in weights:
        comps.append(math_node(nodes, links, "EXPONENT", math_node(nodes, links, "MULTIPLY", path, -k * w)))
    comb = nodes.new("ShaderNodeCombineXYZ")
    for sock, c in zip(("X", "Y", "Z"), comps):
        links.new(c, comb.inputs[sock])
    return comb.outputs["Vector"]


def atmosphere_material(cls, sun_dir, obj):
    tint, k, rim_pow, sunset = ATMOSPHERE[cls]
    mat, nodes, links, out = common.new_material(f"atmo_{cls}", obj)
    geo = nodes.new("ShaderNodeNewGeometry")
    # μ = n·v (0 at the limb). Chord through a thin shell ∝ 1/sqrt(μ² + ε) — capped.
    mu = vmath_node(nodes, links, "DOT_PRODUCT", geo.outputs["Normal"], geo.outputs["Incoming"])
    mu = math_node(nodes, links, "ABSOLUTE", mu)
    chord = math_node(nodes, links, "DIVIDE", 1.0, math_node(nodes, links, "SQRT",
                      math_node(nodes, links, "MULTIPLY_ADD", mu, mu, 0.02)))
    chord = math_node(nodes, links, "MULTIPLY", chord, 0.14)                  # ≈1 at the limb
    scatter = per_channel_scatter(nodes, links, chord, k, RAYLEIGH)
    # Sun geometry: day side and slant path toward the Sun (secant law, soft-capped).
    ndl = vmath_node(nodes, links, "DOT_PRODUCT", geo.outputs["Normal"], tuple(sun_dir))
    day = math_node(nodes, links, "MULTIPLY_ADD", ndl, 1.6, 0.35, clamp=True)
    secant = math_node(nodes, links, "DIVIDE", 1.0, math_node(nodes, links, "MAXIMUM", ndl, 0.06))
    secant = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "MINIMUM", secant, 16.0), 0.09 * sunset)
    transmitted = per_channel_transmit(nodes, links, secant, k, RAYLEIGH)
    col = vmath_node(nodes, links, "MULTIPLY", scatter, transmitted)
    col = vmath_node(nodes, links, "MULTIPLY", col, tuple(tint))
    rim = math_node(nodes, links, "POWER", math_node(nodes, links, "SUBTRACT", 1.0, mu), rim_pow)
    strength = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "MULTIPLY_ADD", rim, 1.0, 0.06), day)
    alpha = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "MULTIPLY_ADD", rim, 0.9, 0.05), day, clamp=True)
    common.emission_over_transparent(nodes, links, out, col, math_node(nodes, links, "MULTIPLY", strength, 2.4), alpha)
    _blend(mat)
    mat.use_backface_culling = True
    return mat


def cloud_material(seed, obj, coverage=0.55):
    mat, nodes, links, out = common.new_material("clouds", obj)
    vec = sphere_coords(nodes, links, seed + 11)
    n = noise(nodes, links, vec, scale=3.0, detail=9.0, roughness=0.6, distortion=0.8)
    alpha = smoothstep(nodes, links, n, coverage, coverage + 0.18)
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.95, 0.96, 0.98, 1)
    bsdf.inputs["Roughness"].default_value = 0.9
    tr = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(alpha, mix.inputs["Fac"])
    links.new(tr.outputs[0], mix.inputs[1])
    links.new(bsdf.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], out.inputs["Surface"])
    _blend(mat)
    return mat


def ring_material(obj):
    mat, nodes, links, out = common.new_material("rings", obj)
    tc = nodes.new("ShaderNodeTexCoord")
    r = vmath_node(nodes, links, "LENGTH", tc.outputs["Object"])          # plane is scaled so r ∈ [0, 1]
    bands = noise(nodes, links, common.node(nodes, "ShaderNodeCombineXYZ").outputs["Vector"], scale=1.0)
    comb = nodes.new("ShaderNodeCombineXYZ")
    links.new(math_node(nodes, links, "MULTIPLY", r, 40.0), comb.inputs["X"])
    bands = noise(nodes, links, comb.outputs["Vector"], scale=1.0, detail=3.0)
    inner = smoothstep(nodes, links, r, 0.48, 0.52)
    outer = math_node(nodes, links, "SUBTRACT", 1.0, smoothstep(nodes, links, r, 0.92, 0.98))
    gap = math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "MULTIPLY",
                    smoothstep(nodes, links, r, 0.74, 0.755), math_node(nodes, links, "SUBTRACT", 1.0, smoothstep(nodes, links, r, 0.78, 0.795))))
    alpha = math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "MULTIPLY", inner, outer), gap)
    alpha = math_node(nodes, links, "MULTIPLY", alpha, math_node(nodes, links, "MULTIPLY_ADD", bands, 0.6, 0.4))
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.85, 0.78, 0.62, 1)
    bsdf.inputs["Roughness"].default_value = 0.8
    tr = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(alpha, mix.inputs["Fac"])
    links.new(tr.outputs[0], mix.inputs[1])
    links.new(bsdf.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], out.inputs["Surface"])
    _blend(mat)
    return mat


def _blend(mat):
    for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass


# ----------------------------------------------------------------------------- build / bake

def build_planet(scene, cls, args, sun_dir):
    for o in [o for o in scene.objects if o.type == "MESH"]:
        bpy.data.objects.remove(o, do_unlink=True)
    seed = args.seed + CLASSES.index(cls) * 13
    body = common.add_uv_sphere(scene, "planet", radius=1.0, segments=128, rings=64)
    surface_material(cls, seed, hex_rgb(args.base_hex) if args.base_hex else None, body)
    if cls in ATMOSPHERE:
        shell = common.add_uv_sphere(scene, "atmosphere", radius=1.035, segments=96, rings=48)
        atmosphere_material(cls, sun_dir, shell)
    if cls in ("earthlike", "ocean"):
        clouds = common.add_uv_sphere(scene, "clouds", radius=1.012, segments=96, rings=48)
        cloud_material(seed, clouds, coverage=0.5 if cls == "earthlike" else 0.58)
    if args.rings or cls == "gasGiant" and args.planet == "gasGiant" and args.rings:
        bpy.ops.mesh.primitive_plane_add(size=4.6)
        rings = bpy.context.active_object
        rings.name = "rings"
        rings.rotation_euler = (math.radians(12), math.radians(4), 0)
        ring_material(rings)
    body.rotation_euler = (0, math.radians(-8), math.radians(20))
    return body


def bake_equirect(scene, body, size, path, bake_type):
    """Bake the surface material's base colour (or emission) to an equirect PNG via Cycles."""
    prev_engine = scene.render.engine
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.use_denoising = False
    w, h = size
    img = bpy.data.images.new(f"bake_{bake_type}", w, h, alpha=False)
    mat = body.data.materials[0]
    nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.nodes.active = tex
    for o in scene.objects:
        o.select_set(False)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bake = scene.render.bake
    bake.use_pass_direct = False
    bake.use_pass_indirect = False
    bake.use_pass_color = True
    bake.margin = 8
    bake.use_clear = True
    bpy.ops.object.bake(type=bake_type)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    nt.nodes.remove(tex)
    scene.render.engine = prev_engine
    log(f"baked {bake_type} → {path}")
    return path


def main():
    args = common.parse_args("FOLDSPACE procedural planets", add_flags)
    scene = common.fresh_scene(args, "planet", res=(1024, 1024), samples=64, engine="CYCLES", transparent=True,
                               quick_samples=6)
    if scene.render.engine == "CYCLES":
        scene.cycles.samples = max(scene.cycles.samples, 6)
    sun_pos = (-5.0, -6.0, 4.0)
    L = [c / math.sqrt(sum(v * v for v in sun_pos)) for c in sun_pos]
    common.add_sun_light(scene, sun_pos, energy=5.5, color=(1.0, 0.97, 0.92))
    common.add_sun_light(scene, (6.0, 2.0, -3.0), energy=0.35, color=(0.5, 0.7, 1.0), name="Fill")
    common.add_camera(scene, (0, -3.6, 0.5), (0, 0, 0), fov_deg=36)

    classes = CLASSES if args.all else [args.planet]
    outputs = []
    for cls in classes:
        body = build_planet(scene, cls, args, L)
        path = common.render(scene, args, f"planet_{cls}")
        outputs.append(path)
        log(f"{cls}: {common.png_stats(path)}")
        if args.bake and not args.all:
            size = tuple(args.bake_size) if args.bake_size else ((256, 128) if args.quick else (2048, 1024))
            p = bake_equirect(scene, body, size, os.path.join(args.out, f"planet_{cls}_albedo.png"), "DIFFUSE")
            outputs.append(p)
            if cls == "lava":
                p = bake_equirect(scene, body, size, os.path.join(args.out, f"planet_{cls}_emission.png"), "EMIT")
                outputs.append(p)
    log("OUTPUTS: " + ", ".join(outputs))


if __name__ == "__main__":
    main()
