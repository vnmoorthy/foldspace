"""Schwarzschild thin-disc ray tracing, AgX export, and native HEVC-alpha movie.

Blender --background --threads 4 --python blender/codex/blackhole.py -- --quick
Blender --background --threads 4 --python blender/codex/blackhole.py -- --final
Optional --still-only skips the 360-frame animation. No downloaded imagery.
"""
import argparse
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import time

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'blender/codex/out/blackhole'
BC = math.sqrt(27) / 2
HALF_VIEW = 12.0
INC = math.radians(78)
INNER, OUTER = 3.0, 10.8


def geodesics(quick=False):
    """u=rs/r. RK4 integrates u'' = 1.5u²-u from an observer at infinity.

    Conserved first integral: (u')²+u²-u³ = 1/b². Every photon trajectory
    lies in one plane through the origin by Schwarzschild spherical symmetry.
    """
    db = .004 if quick else .001
    dp = .009 if quick else .0045
    bs = np.arange(.02, HALF_VIEW * 1.42 + db, db, dtype=np.float64)
    steps = int(3 * math.pi / dp) + 2
    us = np.zeros((steps, len(bs)), dtype=np.float32)
    vs = np.zeros_like(us)
    u = np.zeros_like(bs)
    v = 1 / bs
    active = np.ones(len(bs), dtype=bool)
    max_error = 0.0
    def force(a):
        return 1.5 * a * a - a
    for k in range(steps):
        us[k] = np.where(active, u, np.nan)
        vs[k] = np.where(active, v, np.nan)
        a = force(u)
        ub, vb = u + dp*v/2, v + dp*a/2
        ab = force(ub)
        uc, vc = u + dp*vb/2, v + dp*ab/2
        ac = force(uc)
        ud, vd = u + dp*vc, v + dp*ac
        u += dp*(v + 2*vb + 2*vc + vd)/6
        v += dp*(a + 2*ab + 2*ac + force(ud))/6
        active &= (u >= 0) & (u < 1)
        if np.any(active):
            # Relative error near the critical photon orbit, where it matters.
            keep = active & (bs > 2)
            err = np.abs((v[keep]**2 + u[keep]**2 - u[keep]**3)*bs[keep]**2 - 1)
            if len(err):
                max_error = max(max_error, float(np.max(err)))
        u[~active] = 0
        v[~active] = 0
    return bs, dp, us, vs, max_error


def ray_map(size, table):
    bs, dp, ut, vt, _ = table
    xy = (np.arange(size, dtype=np.float32) + .5) / size * (2*HALF_VIEW) - HALF_VIEW
    x, y = np.meshgrid(xy, xy)  # Blender image pixels start at the bottom.
    b = np.hypot(x, y)
    safe_b = np.maximum(b, 1e-6)
    bx, by, bz = x/safe_b, y/safe_b*math.cos(INC), y/safe_b*math.sin(INC)
    n = np.array([0, -math.sin(INC), math.cos(INC)], dtype=np.float32)
    first = np.mod(np.arctan2(-n[2], bz), np.pi)
    bi = np.clip((b-bs[0])/(bs[1]-bs[0]), 0, len(bs)-2.001)
    ib = bi.astype(np.int32)
    fb = bi-ib
    radius = np.full_like(x, OUTER)
    theta = np.zeros_like(x)
    shift = np.ones_like(x)
    hit = np.zeros_like(x, dtype=bool)
    hit_order = np.full_like(x, -1, dtype=np.int8)
    for order in range(3):
        phi = first + order*np.pi
        pi = phi/dp
        ip = pi.astype(np.int32)
        fp = pi-ip
        def sample(a):
            lo = a[ip, ib]*(1-fb)+a[ip, ib+1]*fb
            hi = a[ip+1, ib]*(1-fb)+a[ip+1, ib+1]*fb
            return lo*(1-fp)+hi*fp
        u, du = sample(ut), sample(vt)
        valid = (~hit) & np.isfinite(u) & (u >= 1/OUTER) & (u <= 1/INNER)
        cs, sn = np.cos(phi), np.sin(phi)
        ex, ey = sn*bx, cs*n[1]+sn*by
        # e_phi is the increasing-geodesic-angle direction in the ray plane.
        px, py = cs*bx, -sn*n[1]+cs*by
        denom = np.sqrt(np.maximum(du*du+u*u*(1-u), 1e-10))
        kr, kp = du/denom, -u*np.sqrt(np.maximum(1-u, 0))/denom
        kx, ky = kr*ex+kp*px, kr*ey+kp*py
        az = np.arctan2(ey, ex)
        beta = np.sqrt(np.maximum(u/(2*(1-u)), 0))
        cos_vel = -np.sin(az)*kx+np.cos(az)*ky
        doppler = np.sqrt(np.maximum(1-beta*beta, 0))/(1-beta*cos_vel)
        g = np.sqrt(np.maximum(1-u, 0))*doppler
        radius[valid] = 1/u[valid]
        theta[valid] = az[valid]
        shift[valid] = g[valid]
        hit_order[valid] = order
        hit |= valid
    return dict(b=b, radius=radius, theta=theta, g=shift, hit=hit, order=hit_order)


def blackbody(temp):
    """Planck spectrum integrated against analytic CIE 1931 observer fits.

    Wyman, Sloan & Shirley (2013), Gaussian CIE matching-function fits.
    Returns normalized linear Rec.709 chromaticity; g^4 supplies bolometric
    intensity separately, so temperature is not double counted.
    """
    ts = np.linspace(1000, 24000, 2048)
    w = np.arange(380, 781, 5, dtype=np.float64)
    def gauss(mu, a, b):
        return np.exp(-.5*((w-mu)*np.where(w < mu, a, b))**2)
    cx = 1.056*gauss(599.8,.0264,.0323)+.362*gauss(442,.0624,.0374)-.065*gauss(501.1,.049,.0382)
    cy = .821*gauss(568.8,.0213,.0247)+.286*gauss(530.9,.0613,.0322)
    cz = 1.217*gauss(437,.0845,.0278)+.681*gauss(459,.0385,.0725)
    rad = (w[None,:]*1e-9)**-5 / np.expm1(.01438777/(ts[:,None]*w[None,:]*1e-9))
    xyz = rad @ np.stack([cx,cy,cz], axis=1)
    mat = np.array([[3.2406,-1.5372,-.4986],[-.9689,1.8758,.0415],[.0557,-.204,1.057]])
    rgb = np.maximum(xyz @ mat.T, 0)
    rgb /= np.maximum(rgb.max(axis=1,keepdims=True), 1e-12)
    indices = np.clip((temp-1000)/(23000)*(len(ts)-1), 0, len(ts)-1.001)
    lo = indices.astype(np.int32)
    f = indices-lo
    return (rgb[lo]*(1-f[...,None])+rgb[lo+1]*f[...,None]).astype(np.float32)


def shading_setup(m):
    r, g = m['radius'], m['g']
    m['color'] = blackbody(11500*(r/INNER)**(-.75)*g)
    # Thin disc luminosity falls as T^4, without a zero-torque ISCO correction.
    m['brightness'] = 5.5*(r/INNER)**(-3)*g**4
    m['edge'] = np.clip((r-INNER)/.09, 0, 1)*np.clip((OUTER-r)/1.25, 0, 1)
    # Blend adjacent integer temporal harmonics. This retains smooth Keplerian
    # shear while making the entire 12s animation exactly periodic.
    cycles = 5*(INNER/r)**1.5
    m['k'] = np.floor(cycles).astype(np.float32)
    m['frac'] = cycles-m['k']
    return m


def shade(m, phase):
    r, az = m['radius'], m['theta']
    t = 2*np.pi*(phase % 1)
    k, f = m['k'], m['frac']
    def turbulence(angle):
        warp = 2.9*np.sin(11*angle+2.2*r)+1.2*np.sin(23*angle-4.1*r)
        return (.30*np.sin(7*angle+11*r+warp)
                +.17*np.sin(17*angle+26*r+warp*1.8)
                +.09*np.sin(37*angle+61*r+warp*3.1)
                +.16*np.sin(3*angle+2.1*r+4.2))
    filaments = (1-f)*turbulence(az-k*t)+f*turbulence(az-(k+1)*t)
    # Fine orbit-following filaments, never a radial spoke/starburst pattern.
    modulation = np.clip(1+filaments, .25, 1.8)
    flux = m['brightness']*modulation
    rgb = m['color']*flux[...,None]
    alpha = np.where(m['hit'], m['edge'], 0).astype(np.float32)
    rgb *= (alpha > 0)[...,None]
    # Captured background rays form a truly black opaque silhouette. A foreground
    # disc intersection is allowed to pass in front of this capture cross-section.
    captured = m['b'] < BC
    alpha = np.maximum(alpha, captured.astype(np.float32))
    # Unresolved higher-order photon subrings convolved with a finite display PSF.
    width = max(.020, 2*HALF_VIEW/len(r)*.7)
    ring = np.exp(-.5*((m['b']-BC-.008)/width)**2)
    ring *= (~m['hit'])
    rgb += ring[...,None]*np.array([1.8,1.02,.49], np.float32)
    alpha = np.maximum(alpha, np.clip(ring,0,1))
    # Modest optical PSF halo, not emitting matter inside the ISCO.
    halo = np.exp(-.5*((m['b']-BC)/.16)**2)*.035*(~m['hit'])*(~captured)
    rgb += halo[...,None]*np.array([1.0,.54,.22])
    alpha = np.maximum(alpha, halo)
    return np.dstack([rgb, alpha]).astype(np.float32)


def save_agx(rgba, filename):
    filename.parent.mkdir(parents=True, exist_ok=True)
    h, w = rgba.shape[:2]
    img = bpy.data.images.new('Geodesic radiance', width=w, height=h, alpha=True, float_buffer=True)
    img.alpha_mode = 'STRAIGHT'
    img.pixels.foreach_set(rgba.ravel())
    img.save_render(str(filename), scene=bpy.context.scene)
    bpy.data.images.remove(img)


def configure():
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = 0
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'
    scene.render.image_settings.compression = 35


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--quick',action='store_true')
    mode.add_argument('--final',action='store_true')
    parser.add_argument('--still-only',action='store_true')
    parser.add_argument('--resume',action='store_true',help='Keep existing final still and completed movie frames')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    start = time.monotonic()
    OUT.mkdir(parents=True,exist_ok=True)
    configure()
    table = geodesics(args.quick)
    size = 256 if args.quick else 2048
    print('Preparing geodesic map', size, flush=True)
    filename = OUT/'blackhole-quick.png' if args.quick else ROOT/'assets/textures/blackhole-still.png'
    map_size = 256 if args.resume and filename.exists() else size
    m = shading_setup(ray_map(map_size,table))
    if not (args.resume and filename.exists()):
        save_agx(shade(m,0),filename)
    timing = {'still_seconds':round(time.monotonic()-start,3)}
    checks = {'null_first_integral_max_relative_error':table[-1], 'shadow_radius_rs':BC,
              'ray_check_resolution':map_size,
              'photon_orbit_radius_rs':1.5,'disc_inner_radius_rs':INNER,
              'higher_order_pixels':int(np.sum(m['order']>0)),
              'loop_phase_0_vs_1_max_delta':float(np.max(np.abs(shade(m,0)-shade(m,1)))),
              'doppler_total_shift_range':[float(m['g'][m['hit']].min()),float(m['g'][m['hit']].max())]}
    del m
    if args.final and not args.still_only:
        frames = OUT/'frames'
        frames.mkdir(exist_ok=True)
        m = shading_setup(ray_map(1080,table))
        del table
        for frame in range(360):
            frame_path = frames/f'{frame:04d}.png'
            if args.resume and frame_path.exists():
                # An interrupted PNG may exist before its last chunk is written.
                with frame_path.open('rb') as saved:
                    saved.seek(-12, 2) if frame_path.stat().st_size >= 12 else saved.seek(0)
                    complete = saved.read() == b'\x00\x00\x00\x00IEND\xaeB`\x82'
                if complete:
                    continue
            save_agx(shade(m,frame/360),frame_path)
            if frame % 30 == 0:
                print(f'Frame {frame}/360; elapsed {time.monotonic()-start:.1f}s',flush=True)
        video = ROOT/'assets/video/blackhole-loop.mov'
        video.parent.mkdir(parents=True,exist_ok=True)
        ffmpeg = shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg'
        subprocess.run([ffmpeg,'-hide_banner','-y','-framerate','30','-i',str(frames/'%04d.png'),
                        '-vf','format=bgra','-c:v','hevc_videotoolbox','-allow_sw','1',
                        '-alpha_quality','1','-b:v','12M','-tag:v','hvc1',
                        '-color_primaries','bt709','-color_trc','iec61966-2-1','-colorspace','bt709',
                        '-movflags','+faststart','-an',str(video)],check=True)
    timing['total_seconds'] = round(time.monotonic()-start,3)
    result = {'mode':'quick' if args.quick else 'final','resumed':args.resume,
              'checks':checks,'timing':timing}
    (OUT/('quick-report.json' if args.quick else 'final-report.json')).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2),flush=True)


if __name__ == '__main__':
    main()
