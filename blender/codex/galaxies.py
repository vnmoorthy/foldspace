"""Procedural Milky Way and M31 emission textures; no reference imagery.

Blender --background --threads 2 --python blender/codex/galaxies.py -- --quick
Blender --background --threads 2 --python blender/codex/galaxies.py -- --final
"""
from pathlib import Path
import sys
import time
import json
import gc
import numpy as np
import bpy

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
sys.path.insert(0,str(HERE))
from emission_utils import fbm, noise2, smoothstep, render_plane


def spiral_fields(x,y,m31=False,bulge_coords=None):
    """Linear radiance and alpha from log-spiral density waves and dust."""
    r=np.sqrt(x*x+y*y)
    theta=np.arctan2(y,x)
    count=2 if m31 else 4
    pitch=.27 if m31 else .28
    phase=theta-np.log(np.maximum(r,.055)/.24)/pitch-.43
    perturb=(fbm(x*17,y*17,7,4)-.5)*.40
    distance=np.arctan2(np.sin(count*(phase+perturb)),np.cos(count*(phase+perturb)))/count
    cloud=fbm(x*14,y*14,83,4)
    width=(.18+.024/np.maximum(r,.13))*(.65+cloud)
    arm=np.exp(-(distance/width)**2)
    diffuse_arm=np.exp(-(distance/(width*2.1))**2)
    arm=.62*arm+.38*diffuse_arm
    arm*=smoothstep(.17,.32,r)
    envelope=(1-smoothstep(.78,1.03,r))*np.exp(-r*1.3)
    broad=fbm(x*5,y*5,12,5)
    filigree=fbm(x*110,y*110,33,3)
    clumps=smoothstep(.42,.8,fbm(x*43,y*43,62,4))
    # Dust ridges are slightly displaced to the inner edge of each arm.
    dust_distance=np.arctan2(np.sin(count*(phase+perturb+.073)),np.cos(count*(phase+perturb+.073)))/count
    dust=np.exp(-(dust_distance/(width*(.18+.42*cloud)))**2)*smoothstep(.18,.35,r)
    dust*=.45+.55*fbm(x*62,y*62,22,4)
    if m31:
        # Disc radius 110 kly = 33.7 kpc: the 10 kpc ring is at r=.297.
        ring=np.exp(-((r-.297-(cloud-.5)*.032)/.052)**2)
        outerring=np.exp(-((r-.59-(cloud-.5)*.045)/.069)**2)
        arm=.70*arm+.70*ring*(.30+.95*broad)+.24*outerring
        dust=np.maximum(dust*.66, np.exp(-((r-.284)/.016)**2)*(.65+.35*filigree))
    else:
        # A short Orion spur between the principal arms; no complete fifth arm.
        sd=np.arctan2(np.sin(phase-.76),np.cos(phase-.76))
        spur=np.exp(-(sd/.13)**2)*np.exp(-((r-.54)/.17)**4)
        arm+=.52*spur
    # O/B stars, old disc, and unresolved H-alpha knots are separate components.
    blue=np.array([.57,.80,1.25],np.float32)
    old=np.array([.55,.55,.57],np.float32)
    red=np.array([1.15,.10,.24],np.float32)
    grain=.48+.9*noise2(x*180,y*180,71)
    patch=.14+2.5*smoothstep(.28,.73,cloud)
    radiance=(envelope*(.38+.27*broad)*grain)[...,None]*old
    radiance+=(envelope*arm*patch*(.48+3.0*clumps)*(.30+1.3*filigree))[...,None]*blue
    knots=arm*np.maximum(noise2(x*115,y*115,93)-.65,0)**2*22
    radiance+=(knots*envelope)[...,None]*red
    ragged_dust=smoothstep(.46,.79,fbm(x*25,y*25,91,4))*diffuse_arm
    extinction=np.exp(-dust*(1.5+1.1*filigree)-ragged_dust*1.8)
    radiance*=extinction[...,None]
    # Yellow-white central old stellar population; resolved bar only for MW.
    if m31:
        bx,by=bulge_coords if bulge_coords is not None else (x,y)
        br=np.sqrt(bx*bx+by*by)
        bulge=2.6*np.exp(-np.sqrt((bx/.12)**2+(by/.09)**2))
        core=3.8*np.exp(-(br/.029)**1.1)
        bar=np.zeros_like(r)
        corecol=np.array([1.6,1.17,.66],np.float32)
    else:
        ca,sa=np.cos(.43),np.sin(.43)
        bx,by=x*ca+y*sa,-x*sa+y*ca
        # Full bar extent ~.54 R = 27 kly for a 100 kly disc diameter.
        bar=1.9*np.exp(-(bx/.23)**4-(by/.045)**2)
        bulge=1.5*np.exp(-r/.064)
        core=2.4*np.exp(-(r/.024)**1.15)
        corecol=np.array([1.35,1.19,.88],np.float32)
    radiance+=(bulge+bar+core)[...,None]*corecol
    alpha=np.clip((envelope*(.52+arm*.68)*(.68+.62*cloud)+bulge+bar+core)*1.15,0,1)
    alpha*=1-smoothstep(1,1.05,r)
    # Keep dark dust inside the disc opaque enough to read as absorption.
    return radiance,alpha


def add_stars(rgba,m31=False,inclined=False):
    """Deterministic subpixel stellar clustering, not a measured catalogue."""
    n=rgba.shape[0]
    rng=np.random.default_rng(17031 if m31 else 17340)
    number=150000 if n>256 else 2800
    r=rng.uniform(.23,.96,number)
    arms=rng.integers(0,2 if m31 else 4,number)
    theta=np.log(r/.24)/(.27 if m31 else .28)+.43+arms*(2*np.pi/(2 if m31 else 4))
    theta+=rng.normal(0,.15,number)
    # An older inter-arm population avoids an empty, smooth disc between arms.
    interarm=rng.random(number)<.35
    theta[interarm]=rng.uniform(-np.pi,np.pi,interarm.sum())
    x=r*np.cos(theta)
    y=r*np.sin(theta)
    if inclined:
        y*=np.cos(np.deg2rad(77))
        ca,sa=np.cos(np.deg2rad(-31)),np.sin(np.deg2rad(-31))
        x,y=x*ca-y*sa,x*sa+y*ca
    px=np.rint((x/1.24+1)*.5*n-.5).astype(int)
    py=np.rint((y/1.24+1)*.5*n-.5).astype(int)
    valid=(px>2)&(py>2)&(px<n-3)&(py<n-3)
    px,py=px[valid],py[valid]
    light=np.minimum(rng.lognormal(-1.85,.9,number),1.8)[valid]
    if n<=256:
        light*=.17
    colours=np.tile(np.array([.7,.9,1.3]),(len(light),1))
    colours[rng.random(len(light))<.08]=[1.5,.18,.36]
    for dy,dx,weight in [(0,0,1),(-1,0,.25),(1,0,.25),(0,-1,.25),(0,1,.25)]:
        for ch in range(3):
            np.add.at(rgba[:,:,ch],(py+dy,px+dx),light*colours[:,ch]*weight)
        np.maximum.at(rgba[:,:,3],(py+dy,px+dx),np.minimum(light*.7*weight,.92))


def faceon(n,m31=False,inclined=False):
    rgba=np.zeros((n,n,4),np.float32)
    axis=((np.arange(n,dtype=np.float32)+.5)/n*2-1)*1.24
    for start in range(0,n,128):
        stop=min(n,start+128)
        x=axis[None,:]
        y=axis[start:stop,None]
        if inclined:
            # Optional projected view: deproject the coordinates of a thin disc.
            ca,sa=np.cos(np.deg2rad(-31)),np.sin(np.deg2rad(-31))
            xx,yy=x*ca+y*sa,-x*sa+y*ca
            bulge_coords=(xx,yy)
            yy=yy/np.cos(np.deg2rad(77))
        else:
            xx,yy=x,y
            bulge_coords=None
        rgb,alpha=spiral_fields(xx,yy,m31,bulge_coords)
        if m31:
            # Satellite positions are illustrative in the deprojected view.
            for cx,cy,rx,ry,strength in [( .40,-.31,.031,.026,1.45),(-.68,.54,.071,.042,.73)]:
                rr=np.sqrt(((x-cx)/rx)**2+((y-cy)/ry)**2)
                satellite=strength*np.exp(-rr*1.45)*(1-smoothstep(3.7,5,rr))
                rgb+=satellite[...,None]*np.array([1.55,1.3,.85])
                alpha=1-(1-alpha)*(1-np.clip(satellite*1.8,0,1))
        rgba[start:stop,:,:3]=rgb
        rgba[start:stop,:,3]=alpha
    add_stars(rgba,m31,inclined)
    return rgba


def edgeon(w,h):
    rgba=np.zeros((h,w,4),np.float32)
    xx=((np.arange(w,dtype=np.float32)+.5)/w*2-1)*1.15
    yy=((np.arange(h,dtype=np.float32)+.5)/h*2-1)*.2875
    for start in range(0,h,128):
        stop=min(h,start+128)
        x=xx[None,:]
        y=yy[start:stop,None]
        # Vertical exponential populations and a thin absorbing midplane.
        radial=np.exp(-np.abs(x)*1.6)*(1-smoothstep(.77,1.05,np.abs(x)))
        warp=.016*np.sin(x*2.7)*smoothstep(.35,.9,np.abs(x))
        z=y-warp
        texture=fbm(x*41,z*175,31,5)
        thick=radial*np.exp(-np.abs(z)/.040)*.55
        thin=radial*np.exp(-np.abs(z)/.011)*(.65+texture)
        bulge=2.1*np.exp(-np.sqrt((x/.135)**2+(z/.058)**2)*1.8)
        extinction=np.exp(-4.6*np.exp(-(z/(.0055+.002*texture))**2)*(.7+texture))
        light=(thick+thin)*extinction
        rgba[start:stop,:,:3]=light[...,None]*np.array([.85,.89,1.1])+ (bulge*extinction)[...,None]*np.array([1.4,1.16,.77])
        rgba[start:stop,:,3]=np.clip((thick+thin+bulge)*1.4,0,1)
    return rgba


def main():
    began=time.monotonic()
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    if ('--quick' in args)==('--final' in args):
        raise SystemExit('Supply exactly one of --quick or --final')
    quick='--quick' in args
    out=HERE/'out'/'galaxies' if quick else ROOT/'assets'/'textures'
    out.mkdir(parents=True,exist_ok=True)
    n=256 if quick else 4096
    products=[('galaxy-milkyway.png',lambda:faceon(n)),
              ('galaxy-andromeda.png',lambda:faceon(n,m31=True)),
              ('galaxy-andromeda-inclined.png',lambda:faceon(n,m31=True,inclined=True)),
              ('galaxy-milkyway-edge.png',lambda:edgeon(n,n//4))]
    times={}
    for name,build in products:
        start=time.monotonic()
        print('Generating',name,flush=True)
        rgba=build()
        print('Rendering',name,'after',round(time.monotonic()-start,2),'seconds of field generation',flush=True)
        render_plane(rgba,out/name,quick)
        # An opaque black background makes faint transparency visible in review.
        if quick:
            scene=bpy.context.scene
            scene.render.film_transparent=False
            scene.render.filepath=str(out/(Path(name).stem+'-black.png'))
            bpy.ops.render.render(write_still=True)
        times[name]=round(time.monotonic()-start,2)
        del rgba
        gc.collect()
    record={'mode':'quick' if quick else 'final','seconds':round(time.monotonic()-began,2),'per_asset_seconds':times,
            'cycles_samples':8 if quick else 128,'adaptive_min_samples':4 if quick else 8,'threads':2,'colour_management':'AgX, Medium High Contrast'}
    (HERE/'out'/'galaxies'/('timing-quick.json' if quick else 'timing-final.json')).write_text(json.dumps(record,indent=2)+'\n')
    print('GALAXIES COMPLETE',json.dumps(record))


if __name__=='__main__':
    main()
