"""FOLDSPACE Sun: spherical Voronoi granules, spots, corona and preview.

Blender --background --threads 2 --python blender/codex/sun.py -- --quick
Blender --background --threads 2 --python blender/codex/sun.py -- --final
"""
import sys
from pathlib import Path
import time
import json
import numpy as np
import bpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from emission_utils import noise2, fbm, smoothstep, render_plane, reset, float_image, emission_material


def hash3(x, y, z, k):
    v = np.sin(x*127.1+y*311.7+z*74.7+k*59.31)*43758.5453
    return v-np.floor(v)


def photosphere(w, h):
    result = np.ones((h, w, 4), np.float32)
    lon = (np.arange(w, dtype=np.float32)+.5)/w*2*np.pi-np.pi
    # Rows in Blender's pixel buffer run south to north.
    spots = [(-2.3, .35, .039), (-2.24, .38, .024), (-.56, .41, .047),
             (-.45, .39, .031), (.76, -.34, .044), (.84, -.37, .025),
             (2.1, -.44, .052), (2.23, -.4, .031), (2.18, -.46, .022),
             (1.2, .28, .026), (-1.27, -.30, .029)]
    for start in range(0, h, 128):
        stop = min(h, start+128)
        lat = ((np.arange(start, stop, dtype=np.float32)+.5)/h*np.pi-np.pi/2)[:, None]
        px = np.cos(lat)*np.cos(lon)[None, :]*28
        py = np.cos(lat)*np.sin(lon)[None, :]*28
        pz = np.broadcast_to(np.sin(lat)*28, px.shape)
        gx, gy, gz = np.floor(px), np.floor(py), np.floor(pz)
        d1, d2 = np.full(px.shape, 1e6, np.float32), np.full(px.shape, 1e6, np.float32)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    x, y, z = gx+dx, gy+dy, gz+dz
                    d = (x+.12+.76*hash3(x,y,z,1)-px)**2
                    d += (y+.12+.76*hash3(x,y,z,2)-py)**2
                    d += (z+.12+.76*hash3(x,y,z,3)-pz)**2
                    d2 = np.minimum(d2, np.maximum(d1, d))
                    d1 = np.minimum(d1, d)
        lane = smoothstep(.0, .19, np.sqrt(d2)-np.sqrt(d1))
        intensity = .61 + .46*lane - .075*np.sqrt(d1)
        # A very weak broad photospheric pattern, periodic across the UV seam.
        intensity *= .98+.04*fbm(px*.20, py*.20+pz*.13, 9, 3)
        col = np.array([3.55, 3.10, 2.60], np.float32)[None, None, :]*intensity[..., None]
        for slon, slat, radius in spots:
            dl = np.arctan2(np.sin(lon-slon), np.cos(lon-slon))[None, :]*np.cos(slat)
            dy = lat-slat
            angle = np.arctan2(dy, dl)
            rr = np.sqrt(dl*dl+(dy*1.22)**2)/radius
            rr *= 1+.09*np.sin(angle*5+slon)+.045*np.cos(angle*9)
            pen = 1-smoothstep(.62, 1.7, rr)
            umb = 1-smoothstep(.35, .72, rr)
            filaments = .85+.15*np.sin(angle*37+rr*12)
            # 3800 K umbra with a warmer and brighter penumbra.
            pen_col = np.array([.83, .59, .40], np.float32)*filaments[..., None]
            umb_col = np.array([.17, .075, .031], np.float32)
            col = col*(1-pen[..., None])+pen_col*pen[..., None]
            col = col*(1-umb[..., None])+umb_col*umb[..., None]
        result[start:stop, :, :3] = col
    return result


def corona(n):
    result = np.zeros((n, n, 4), np.float32)
    axis = ((np.arange(n, dtype=np.float32)+.5)/n*2-1)*3.15
    for start in range(0, n, 128):
        stop = min(n, start+128)
        x = axis[None, :]
        y = axis[start:stop, None]
        r = np.sqrt(x*x+y*y)
        theta = np.arctan2(y, x)
        exterior = smoothstep(.985, 1.008, r)
        fade = 1-smoothstep(2.35, 3.05, r)
        base = np.exp(-np.maximum(r-1, 0)/.25)*.23
        # Extended equatorial helmet streamers and shorter polar plumes.
        stream = np.zeros_like(r)
        for t, amp, width, length in [(.02,.48,.22,.64), (.37,.23,.11,.57),
                                     (-.41,.32,.14,.62), (2.83,.39,.18,.67),
                                     (-2.99,.48,.20,.71), (2.47,.19,.11,.49),
                                     (1.39,.13,.09,.34), (-1.48,.14,.08,.38)]:
            bend = .07*np.sin(theta*2)*(r-1)
            delta = np.arctan2(np.sin(theta-t-bend), np.cos(theta-t-bend))
            stream += amp*np.exp(-.5*(delta/(width/(np.maximum(r,1)**.9)))**2)*np.exp(-np.maximum(r-1,0)/length)
        threads = .68+.32*noise2(theta*105, r*6, 31)
        density = (base+stream*threads)*exterior*fade
        halo = np.exp(-((r-1.015)/.019)**2)*.28
        # H-alpha chromosphere and several limb-rooted arch-shaped prominences.
        pink = np.array([2.5, .15, .35], np.float32)
        white = np.array([1.45, 1.62, 1.88], np.float32)
        strength = density+halo
        weighted = density[..., None]*white+halo[..., None]*pink
        for t, height, halfwidth in [(.64,.24,.13), (2.15,.19,.12), (-.76,.32,.19), (-2.55,.16,.11)]:
            radial = x*np.cos(t)+y*np.sin(t)
            tangent = -x*np.sin(t)+y*np.cos(t)
            arch = 1+height*np.sqrt(np.maximum(0,1-(tangent/halfwidth)**2))
            line = np.exp(-((radial-arch)/.014)**2)*(np.abs(tangent)<halfwidth)*exterior
            foot = .30*np.exp(-((radial-arch)/.037)**2)*(np.abs(tangent)<halfwidth)*exterior
            v = (line+foot)*.65
            strength += v
            weighted += v[..., None]*pink
        result[start:stop,:, :3] = weighted/np.maximum(strength[..., None], 1e-6)
        result[start:stop,:, 3] = np.clip(strength, 0, .90)
    return result


def sphere_preview(surface, halo, path, quick):
    scene = reset(quick)
    scene.render.film_transparent = False
    scene.render.resolution_x = scene.render.resolution_y = 256 if quick else 768
    si = float_image('Photosphere radiance', surface)
    ci = float_image('Corona radiance', halo)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=128, ring_count=64, radius=1)
    sphere = bpy.context.object
    sphere.rotation_euler = (np.pi/2, 0, -.5)
    bpy.ops.object.shade_smooth()
    sphere.data.materials.append(emission_material(si, limb=True))
    bpy.ops.mesh.primitive_plane_add(size=6.3, location=(0,0,-1.02))
    bpy.context.object.data.materials.append(emission_material(ci))
    bpy.ops.object.camera_add(location=(0,0,10))
    cam=bpy.context.object; cam.data.type='ORTHO'; cam.data.ortho_scale=6.3
    scene.camera=cam
    scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)


def main():
    began=time.monotonic()
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    if ('--quick' in args)==('--final' in args):
        raise SystemExit('Supply exactly one of --quick or --final')
    quick='--quick' in args
    out=HERE/'out'/'sun' if quick else ROOT/'assets'/'textures'
    out.mkdir(parents=True,exist_ok=True)
    surface=photosphere(256 if quick else 2048,128 if quick else 1024)
    halo=corona(256 if quick else 2048)
    render_plane(surface,out/'sun-photosphere.png',quick,rgb=True)
    render_plane(halo,out/'sun-corona.png',quick)
    preview=HERE/'out'/'sun'/('sun-preview-quick.png' if quick else 'sun-preview.png')
    sphere_preview(surface,halo,preview,quick)
    elapsed=time.monotonic()-began
    record={'mode':'quick' if quick else 'final','seconds':round(elapsed,2),'cycles_samples':8 if quick else 128,
            'adaptive_min_samples':4 if quick else 8,'colour_management':'AgX, Medium High Contrast','threads':2}
    (HERE/'out'/'sun'/('timing-quick.json' if quick else 'timing-final.json')).write_text(json.dumps(record,indent=2)+'\n')
    print('SUN COMPLETE',json.dumps(record))


if __name__=='__main__':
    main()
