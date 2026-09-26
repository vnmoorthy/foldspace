#!/usr/bin/env python3
"""Build the README hero (docs/hero.png, 1600x800) and the GitHub social
card (docs/social-preview.png, 1280x640) from the project's own Blender
renders. Pure Pillow + numpy; no stock, no AI imagery.

    python3 docs/tools/make_hero.py

Everything is rendered at 2x (3200x1600) and downsampled for clean edges.
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont, ImageOps

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
A = lambda *p: os.path.join(ROOT, *p)

S = 2                      # supersample
W, H = 1600 * S, 800 * S
rng = np.random.default_rng(7)

FUTURA = "/System/Library/Fonts/Supplemental/Futura.ttc"     # idx 2 = Bold
AVENIR = "/System/Library/Fonts/Avenir Next.ttc"             # idx 5 Medium, 7 Regular, 8 Heavy
MENLO = "/System/Library/Fonts/Menlo.ttc"


def font(path, size, index=0):
    return ImageFont.truetype(path, int(size * S), index=index)


def screen(base, layer):
    """base, layer: RGB images same size."""
    return ImageChops.screen(base, layer)


def add_rgba(base_rgb, layer_rgba):
    """Additive (screen-like) blend of a premultiplied-by-alpha RGBA glow onto RGB."""
    l = np.asarray(layer_rgba).astype(np.float32) / 255.0
    b = np.asarray(base_rgb).astype(np.float32) / 255.0
    rgb = l[..., :3] * l[..., 3:4]
    out = 1 - (1 - b) * (1 - rgb)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def radial(w, h, cx, cy, rx, ry, power=1.0):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
    return np.clip(1 - d, 0, 1) ** power


# ---------------------------------------------------------------- background
def background():
    img = np.zeros((H, W, 3), np.float32)      # pure black, SpaceX-style

    # soft nebula clouds: low-res fractal-ish noise, coloured and masked
    def cloud(seed, scale):
        r = np.random.default_rng(seed)
        acc = np.zeros((H // 8, W // 8), np.float32)
        for octv, amp in ((16, 1.0), (32, 0.5), (64, 0.25)):
            n = r.random((octv // 2, octv)).astype(np.float32)
            n = np.asarray(Image.fromarray(n * 255).resize((W // 8, H // 8), Image.BICUBIC)) / 255
            acc += n * amp
        acc = (acc - acc.min()) / (acc.max() - acc.min())
        acc = acc ** 2.2 * scale
        return np.asarray(Image.fromarray((acc * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)) / 255

    # very faint neutral haze so the black isn't dead flat
    haze = cloud(11, 1.0) * radial(W, H, W * 0.45, H * 0.5, W * 0.7, H * 0.9, 1.2)
    img += haze[..., None] * np.array([10, 12, 16], np.float32)
    img += rng.normal(0, 1.6, (H, W, 1)).astype(np.float32)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def stars(base):
    layer = Image.new("RGB", (W, H), 0)
    d = ImageDraw.Draw(layer)
    n = 620
    xs = rng.random(n) * W
    ys = rng.random(n) * H
    for x, y in zip(xs, ys):
        mag = rng.random() ** 3.2            # mostly tiny
        r = 0.6 * S + mag * 2.4 * S
        t = rng.random()
        if t < 0.55:   col = (200, 215, 240)
        elif t < 0.85: col = (255, 245, 225)
        else:          col = (150, 205, 255)
        k = 0.22 + 0.60 * (mag ** 0.6)
        col = tuple(int(c * k) for c in col)
        d.ellipse((x - r, y - r, x + r, y + r), fill=col)
    soft = layer.filter(ImageFilter.GaussianBlur(0.9 * S))
    base = screen(base, soft)
    # bright stars get a bloom
    bright = Image.new("RGB", (W, H), 0)
    d = ImageDraw.Draw(bright)
    for _ in range(16):
        x, y = rng.random() * W, rng.random() * H
        r = (1.6 + rng.random() * 1.6) * S
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 250, 240))
    bloom = bright.filter(ImageFilter.GaussianBlur(6 * S))
    bloom = ImageChops.multiply(bloom, Image.new("RGB", (W, H), (120, 150, 180)))
    base = screen(base, bloom)
    base = screen(base, bright.filter(ImageFilter.GaussianBlur(0.8 * S)))
    return base


def galaxies(base):
    g = Image.open(A("assets/textures/galaxy-andromeda-inclined.png")).convert("RGBA")
    g = g.resize((int(1500 * S), int(1500 * S)), Image.LANCZOS).rotate(18, resample=Image.BICUBIC)
    # tint bluish, fade
    arr = np.asarray(g).astype(np.float32)
    arr[..., 0] *= 0.85; arr[..., 1] *= 0.9; arr[..., 2] *= 1.0
    arr[..., 3] *= 0.22
    g = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    g = g.filter(ImageFilter.GaussianBlur(1.2 * S))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    layer.alpha_composite(g, (int(-300 * S), int(-560 * S)))
    return add_rgba(base, layer)


# ----------------------------------------------------------------- black hole
def black_hole(base, cx, cy, width):
    src = Image.open(A("assets/textures/blackhole-still.png")).convert("RGBA")
    src = src.crop((40, 460, 2008, 1440))                     # tight bbox
    scale = width / src.width
    src = src.resize((int(src.width * scale), int(src.height * scale)), Image.LANCZOS)
    arr = np.asarray(src).astype(np.float32) / 255
    lum = arr[..., :3] @ np.array([0.30, 0.55, 0.15], np.float32)
    lum = np.clip((lum - 0.06) / 0.94, 0, 1)
    hh, ww = lum.shape
    yy, xx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    rr = np.sqrt(((xx - ww / 2) / (ww / 2)) ** 2 + ((yy - hh * 0.50) / (hh * 0.5)) ** 2)
    boost = np.clip(1.35 - 1.05 * rr, 0.22, 1.35)
    lum = np.clip(lum * boost, 0, 1) ** 1.6
    # Gargantua-style ramp: ember -> orange -> gold -> hot white
    stops = np.array([[0.00, 0.06, 0.01, 0.00],
                      [0.18, 0.45, 0.10, 0.01],
                      [0.40, 0.95, 0.38, 0.06],
                      [0.65, 1.00, 0.72, 0.30],
                      [0.85, 1.00, 0.93, 0.72],
                      [1.00, 1.00, 1.00, 0.98]], np.float32)
    rgb = np.stack([np.interp(lum, stops[:, 0], stops[:, i + 1]) for i in range(3)], -1)
    alpha = arr[..., 3]
    # deepen the shadow: where the render is truly black keep it opaque black
    dark = (lum < 0.02) & (alpha > 0.5)
    rgb[dark] = 0
    out = np.concatenate([rgb, alpha[..., None]], -1)
    bh = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))

    x0, y0 = int(cx - bh.width / 2), int(cy - bh.height / 2)

    # halo glow behind
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gl = bh.copy()
    ga = np.asarray(gl).astype(np.float32)
    ga[..., 3] *= 0.9
    gl = Image.fromarray(ga.astype(np.uint8))
    glow.alpha_composite(gl, (x0, y0))
    halo = glow.filter(ImageFilter.GaussianBlur(70 * S))
    ha = np.asarray(halo).astype(np.float32)
    ha[..., 3] *= 0.30
    ha[..., :3] *= np.array([1.0, 0.55, 0.25], np.float32)
    halo = Image.fromarray(np.clip(ha, 0, 255).astype(np.uint8))
    base = add_rgba(base, halo)
    # bloom
    bloom = glow.filter(ImageFilter.GaussianBlur(12 * S))
    ba = np.asarray(bloom).astype(np.float32); ba[..., 3] *= 0.35
    base = add_rgba(base, Image.fromarray(ba.astype(np.uint8)))
    # the body itself (normal over)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    layer.alpha_composite(bh, (x0, y0))
    base = Image.alpha_composite(base.convert("RGBA"), layer).convert("RGB")
    return base


# ------------------------------------------------------------------- planets
def planet(path, diameter, rim_dir=(1, 0), rim_col=(120, 220, 255), rim=0.55, dim=0.0):
    p = Image.open(path).convert("RGB")
    arr = np.asarray(p).astype(np.float32)
    # locate the sphere from brightness
    m = arr.max(-1) > 18
    ys, xs = np.where(m)
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    r = (xs.max() - xs.min()) / 2
    D = int(diameter * S)
    big = p.resize((int(p.width * D / (2 * r)), int(p.height * D / (2 * r))), Image.LANCZOS)
    big = big.filter(ImageFilter.UnsharpMask(2, 60, 3))
    k = big.width / p.width
    box = (int(cx * k - D / 2), int(cy * k - D / 2), int(cx * k + D / 2), int(cy * k + D / 2))
    big = big.crop(box)
    # anti-aliased circular mask
    mask = Image.new("L", (D * 4, D * 4), 0)
    ImageDraw.Draw(mask).ellipse((2, 2, D * 4 - 3, D * 4 - 3), fill=255)
    mask = mask.resize((D, D), Image.LANCZOS)
    # shading: darken the side away from the light, add rim light on the light side
    y, x = np.mgrid[0:D, 0:D].astype(np.float32)
    nx, ny = (x - D / 2) / (D / 2), (y - D / 2) / (D / 2)
    rr = np.clip(1 - nx * nx - ny * ny, 0, 1)
    nz = np.sqrt(rr)
    lx, ly = rim_dir
    n = math.hypot(lx, ly); lx, ly = lx / n, ly / n
    lamb = np.clip(nx * lx + ny * ly + 0.35 * nz, 0, 1)
    shade = 0.10 + 0.90 * lamb ** 0.9
    a = np.asarray(big).astype(np.float32) * shade[..., None] * (1 - dim)
    edge = (1 - nz) ** 6 * np.clip(nx * lx + ny * ly + 0.4, 0, 1)
    a += edge[..., None] * np.array(rim_col, np.float32) * rim
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGBA")
    img.putalpha(mask)
    return img


def place_planet(base, img, cx, cy, glow_col=(60, 170, 220), glow_k=0.35):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x0, y0 = int(cx * S - img.width / 2), int(cy * S - img.height / 2)
    # atmosphere glow
    g = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(g)
    pad = img.width * 0.06
    gd.ellipse((x0 - pad, y0 - pad, x0 + img.width + pad, y0 + img.height + pad), fill=glow_col + (int(255 * glow_k),))
    g = g.filter(ImageFilter.GaussianBlur(img.width * 0.09))
    base = add_rgba(base, g)
    layer.alpha_composite(img, (x0, y0))
    return Image.alpha_composite(base.convert("RGBA"), layer).convert("RGB")


# ------------------------------------------------------------------ fold line
def fold_line(base, y_line, x0, x1, bh_cx, bh_cy):
    """Thin cyan light streak; bends toward the black hole as it approaches."""
    pts = []
    for i in range(0, 1201):
        t = i / 1200
        x = x0 + (x1 - x0) * t
        d = max(bh_cx - x, 60)
        bend = (bh_cy - y_line) * (1 / (1 + (d / 300) ** 2.4))
        pts.append((x * S, (y_line + bend) * S))
    core = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dc, dg = ImageDraw.Draw(core), ImageDraw.Draw(glow)
    # fade in from the left, brighten towards the hole
    for i in range(len(pts) - 1):
        t = i / (len(pts) - 1)
        a = min(1, t / 0.10) * (0.55 + 0.45 * t ** 0.6) * min(1, (1 - t) / 0.10)
        dc.line([pts[i], pts[i + 1]], fill=(245, 255, 255, int(255 * a)), width=int(1.4 * S))
        dg.line([pts[i], pts[i + 1]], fill=(61, 242, 255, int(255 * a)), width=int(7 * S))
    wide = glow.filter(ImageFilter.GaussianBlur(24 * S))
    wa = np.asarray(wide).astype(np.float32); wa[..., 3] *= 1.1
    base = add_rgba(base, Image.fromarray(np.clip(wa, 0, 255).astype(np.uint8)))
    base = add_rgba(base, glow.filter(ImageFilter.GaussianBlur(6 * S)))
    base = add_rgba(base, glow.filter(ImageFilter.GaussianBlur(1.5 * S)))
    base = add_rgba(base, core.filter(ImageFilter.GaussianBlur(0.7 * S)))
    return base


# ------------------------------------------------------------------ typography
def draw_tracked(draw, xy, text, fnt, fill, tracking=0.0):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + tracking * S
    return x


def text_width(draw, text, fnt, tracking=0.0):
    return sum(draw.textlength(ch, font=fnt) for ch in text) + tracking * S * (len(text) - 1)


def typography(base, left, top):
    txt = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(txt)
    HN = "/System/Library/Fonts/HelveticaNeue.ttc"     # 7 Light, 12 Thin, 0 Regular, 10 Medium
    f_title = font(HN, 128, 7)
    f_tag = font(HN, 34, 12)
    f_label = font(HN, 13, 10)

    x, y = left * S, top * S
    draw_tracked(d, (x + 1 * S, y), "SWIFTUI   ·   SCENEKIT   ·   IPHONE DUO HINGE", f_label, (255, 255, 255, 150), 4.0)
    y += 42 * S
    draw_tracked(d, (x - 5 * S, y), "FOLDSPACE", f_title, (255, 255, 255, 255), 7.0)
    y += 172 * S
    d.text((x, y), "Fold the phone. Fold space.", font=f_tag, fill=(255, 255, 255, 235))
    y += 72 * S
    draw_tracked(d, (x + 1 * S, y), "IPHONE DUO   ·   BITRIG HACKS   ·   YC   ·   SEPT 2026", f_label, (255, 255, 255, 120), 4.0)

    # soft dark halo so stars don't sit inside the strokes
    alpha = txt.split()[3]
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.putalpha(alpha.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(14 * S)))
    sa = np.asarray(shadow).astype(np.float32); sa[..., 3] *= 0.7
    shadow = Image.fromarray(sa.astype(np.uint8))
    out = Image.alpha_composite(base.convert("RGBA"), shadow)
    out = Image.alpha_composite(out, txt)
    return out.convert("RGB")


def vignette(base, strength=0.35):
    v = radial(W, H, W / 2, H / 2, W * 0.78, H * 0.95, 1.0)
    v = 1 - strength * (1 - v) ** 1.6
    a = np.asarray(base).astype(np.float32) * v[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def grain(base, amt=2.0):
    a = np.asarray(base).astype(np.float32)
    a += rng.normal(0, amt, (H, W, 1)).astype(np.float32)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def build():
    BH_CX, BH_CY = 1335, 415          # 1x coords
    img = background()
    img = galaxies(img)
    img = stars(img)
    img = black_hole(img, BH_CX * S, BH_CY * S, 1040 * S)
    earth = planet(A("blender/codex/out/planets/earth-sphere.png"), 150, rim_dir=(1, -0.35), rim_col=(200, 225, 255), rim=0.7)
    img = place_planet(img, earth, 610, 672, glow_col=(90, 140, 200), glow_k=0.18)
    prox = planet(A("blender/codex/out/planets/proxima-b-sphere.png"), 44, rim_dir=(1, -0.3),
                  rim_col=(255, 210, 170), rim=0.6, dim=0.15)
    img = place_planet(img, prox, 930, 600, glow_col=(255, 200, 150), glow_k=0.10)
    img = vignette(img)
    img = typography(img, 96, 262)
    img = fold_line(img, 452, -40, BH_CX - 260, BH_CX, BH_CY)
    img = grain(img)
    return img


if __name__ == "__main__":
    out = build()
    hero = out.resize((1600, 800), Image.LANCZOS)
    hero.save(A("docs/hero.png"), optimize=True)
    out.resize((1280, 640), Image.LANCZOS).save(A("docs/social-preview.png"), optimize=True)
    print("wrote docs/hero.png and docs/social-preview.png")
