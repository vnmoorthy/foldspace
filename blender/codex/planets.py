"""FOLDSPACE planet albedos, from equations and hand-drawn geography only.

Run with Blender's bundled NumPy:
  Blender --background --python blender/codex/planets.py -- --quick
  Blender --background --python blender/codex/planets.py -- --final
--quick writes 256x128 previews; --final writes 2048x1024 RGB PNGs.
No directional illumination is baked into the texture maps. The sphere previews
are explicitly separate, analytically lit inspection images.
"""
import argparse
import json
import math
from pathlib import Path
import struct
import sys
import time
import zlib
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'blender/codex/out/planets'
ASSETS = ROOT / 'assets/textures'
PI = np.float32(np.pi)

# Exact UniverseData IDs, classes, Kelvin temperatures and base colors.
BODIES = [
 ('mercury','rocky',440,'8C8078'), ('venus','desert',737,'E0B570'),
 ('earth','earthlike',288,'3B82D6'), ('mars','desert',210,'C4613A'),
 ('jupiter','gasGiant',165,'D2A374'), ('saturn','gasGiant',134,'E4C98A'),
 ('uranus','iceGiant',76,'7CD4DE'), ('neptune','iceGiant',72,'3E6BD1'),
 ('proxima-b','rocky',234,'9C8A78'), ('proxima-d','rocky',360,'8A7B6E'),
 ('barnard-b','rocky',400,'A07C63'), ('barnard-c','rocky',370,'8E7A69'),
 ('barnard-d','lava',440,'D9502F'), ('barnard-e','rocky',310,'7F736A'),
 ('wolf-359-b','iceGiant',40,'5FB8C9'), ('sirius-b','whiteDwarf',25200,'E8F0FF'),
 ('eps-eri-b','gasGiant',115,'C9975F'), ('tau-ceti-e','superEarth',320,'B39A75'),
 ('tau-ceti-f','superEarth',204,'8FA3B8'), ('trappist-1b','lava',400,'D8502E'),
 ('trappist-1c','rocky',342,'B57A5A'), ('trappist-1d','desert',288,'C9A46A'),
 ('trappist-1e','ocean',251,'2E5FB8'), ('trappist-1f','ocean',219,'4A7FC2'),
 ('trappist-1g','ice',199,'9FCBE8'), ('trappist-1h','ice',173,'C8E4F2'),
]

def smooth(a,b,x):
    t=np.clip((x-a)/(b-a),0,1)
    return t*t*(3-2*t)

def mix(a,b,t):
    return np.asarray(a)*(1-t[...,None])+np.asarray(b)*t[...,None]

def color(h):
    return np.array([int(h[i:i+2],16)/255 for i in (0,2,4)],dtype=np.float32)

def thermal_rgb(temperature):
    """Approximate RGB from Planck radiance at representative RGB wavelengths.

    White-balanced against 5772 K; not a full CIE spectral integration. The
    output is sRGB display-referred and normalized, not a luminosity estimate.
    """
    wavelengths=np.array([610.,550.,460.],np.float32)*1e-9
    c2=.01438776877  # h*c/k_B, m K
    radiance=1/(wavelengths**5*np.expm1(c2/(wavelengths*temperature)))
    white=1/(wavelengths**5*np.expm1(c2/(wavelengths*5772.)))
    value=radiance/white;value=value/value.max()
    return np.where(value<=.0031308,12.92*value,1.055*value**(1/2.4)-.055)

def png(path, pixels):
    """Lossless explicit RGB sRGB PNG; data maps omit the color space tag."""
    path.parent.mkdir(parents=True,exist_ok=True)
    a=np.uint8(np.clip(pixels,0,1)*255+.5)
    def chunk(tag,data):
        return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    h,w,_=a.shape
    raw=b''.join(b'\0'+row.tobytes() for row in a)
    tags=chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))
    if 'roughness' not in path.name:
        tags+=chunk(b'sRGB',b'\0')+chunk(b'gAMA',struct.pack('>I',45455))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+tags+chunk(b'IDAT',zlib.compress(raw,6))+chunk(b'IEND',b''))

def hashed(ix,iy,iz,seed):
    with np.errstate(over='ignore'):
        h=(ix.astype(np.uint32)*np.uint32(374761393) ^ iy.astype(np.uint32)*np.uint32(668265263)
           ^ iz.astype(np.uint32)*np.uint32(2246822519) ^ np.uint32(seed*1013))
        h=(h^(h>>13))*np.uint32(1274126177)
        h=h^(h>>16)
    return (h.astype(np.float32)/np.float32(4294967295))*2-1

def noise(x,y,z,seed=1):
    ix=np.floor(x).astype(np.int32); iy=np.floor(y).astype(np.int32); iz=np.floor(z).astype(np.int32)
    fx=(x-ix).astype(np.float32); fy=(y-iy).astype(np.float32); fz=(z-iz).astype(np.float32)
    fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy);fz=fz*fz*(3-2*fz)
    r=np.zeros(x.shape,np.float32)
    for a in (0,1):
        for b in (0,1):
            for c in (0,1):
                r+=hashed(ix+a,iy+b,iz+c,seed)*(fx if a else 1-fx)*(fy if b else 1-fy)*(fz if c else 1-fz)
    return r

def field(x,y,z,scale,seed,octaves=4):
    r=np.zeros(x.shape,np.float32); amp=1.;norm=0.
    for o in range(octaves):
        r+=amp*noise(x*scale+9.2,y*scale-4.5,z*scale+1.7,seed+o*17)
        norm+=amp;amp*=.51;scale*=2.07
    return r/norm

def coords(w,h):
    lon=np.broadcast_to(np.linspace(-PI,PI,w,dtype=np.float32),(h,w))
    lat=np.broadcast_to(np.linspace(PI/2,-PI/2,h,dtype=np.float32)[:,None],(h,w))
    return lon,lat,np.cos(lat)*np.cos(lon),np.cos(lat)*np.sin(lon),np.sin(lat)

def crater_field(w,h,seed,count=220):
    """Spherical crater distance, locally evaluated; rings encode ejecta albedo.

    These are not lit bowls: normal maps/geometry are separate runtime concerns.
    """
    rng=np.random.default_rng(seed)
    out=np.zeros((h,w),np.float32)
    for i in range(count):
        lo=rng.uniform(-np.pi,np.pi);la=np.arcsin(rng.uniform(-.985,.985))
        r=rng.uniform(.008,.021) if i>35 else rng.uniform(.026,.095)
        dy=int(np.ceil(r*1.65/np.pi*(h-1)))+1
        dx=int(np.ceil(r*1.7/max(.09,np.cos(la))/(2*np.pi)*(w-1)))+1
        cy=(np.pi/2-la)/np.pi*(h-1);cx=(lo+np.pi)/(2*np.pi)*(w-1)
        ys=np.arange(max(0,int(cy)-dy),min(h,int(cy)+dy+1))
        xs0=np.arange(int(cx)-dx,int(cx)+dx+1);xs=xs0%(w-1)
        lats=np.pi/2-ys[:,None]/(h-1)*np.pi
        lons=xs0[None,:]/(w-1)*2*np.pi-np.pi
        angular=np.arccos(np.clip(np.sin(lats)*np.sin(la)+np.cos(lats)*np.cos(la)*np.cos(lons-lo),-1,1))/r
        stamp=(-.085*np.exp(-angular**4/.5)+.15*np.exp(-((angular-.92)/.13)**2)
               +.025*np.exp(-((angular-1.2)/.2)**2))
        out[np.ix_(ys,xs)]+=stamp
    return out

# Hand-authored approximate outlines, lon/lat degrees. They are intentionally
# independent of downloaded geographical datasets, imagery, or map libraries.
LAND = [
 [(-168,66),(-160,71),(-144,70),(-130,69),(-122,72),(-112,73),(-100,77),(-83,82),(-65,80),(-63,69),(-72,62),(-62,58),(-55,53),(-57,48),(-67,45),(-70,41),(-75,35),(-80,32),(-81,25),(-83,25),(-84,30),(-89,29),(-96,26),(-97,22),(-92,18),(-87,21),(-86,16),(-84,12),(-78,8),(-83,8),(-88,14),(-94,16),(-104,20),(-110,24),(-115,32),(-122,37),(-126,49),(-135,58),(-146,61),(-155,59),(-165,61)],
 [(-80,9),(-71,12),(-62,10),(-60,7),(-52,4),(-50,0),(-44,-2),(-35,-6),(-35,-12),(-39,-17),(-40,-22),(-48,-28),(-53,-34),(-57,-38),(-63,-42),(-65,-48),(-68,-55),(-73,-53),(-75,-44),(-74,-35),(-72,-29),(-70,-18),(-77,-12),(-81,-5),(-79,1)],
 [(-73,59),(-49,60),(-42,64),(-39,69),(-25,72),(-19,78),(-27,83),(-47,83),(-63,79),(-65,73)],
 [(-17,15),(-17,21),(-13,27),(-10,30),(-6,36),(3,36),(10,37),(12,33),(20,32),(25,31),(32,31),(35,23),(39,16),(44,12),(51,12),(48,4),(42,-1),(40,-11),(35,-20),(33,-27),(28,-33),(19,-35),(15,-28),(12,-17),(9,-4),(9,4),(3,6),(-2,5),(-8,5),(-15,10)],
 [(-10,36),(-9,43),(-2,44),(-4,49),(2,51),(6,54),(8,57),(6,59),(5,62),(13,68),(25,71),(30,69),(35,64),(43,67),(53,69),(65,68),(75,72),(90,74),(105,78),(121,73),(140,72),(160,70),(180,68),(180,60),(170,59),(162,55),(156,50),(151,46),(145,48),(141,53),(137,53),(139,45),(134,43),(129,35),(126,39),(122,39),(122,31),(120,25),(113,22),(108,20),(110,11),(105,8),(102,3),(103,0),(99,6),(98,14),(94,17),(90,22),(87,21),(82,16),(78,8),(75,10),(72,20),(67,25),(59,25),(55,20),(51,15),(45,13),(42,16),(40,22),(36,29),(33,31),(35,35),(28,36),(26,40),(22,39),(24,35),(20,37),(19,41),(16,40),(16,37),(13,38),(12,43),(7,44),(3,42),(0,40)],
 [(113,-22),(114,-29),(116,-34),(128,-32),(134,-34),(139,-37),(147,-39),(153,-28),(153,-24),(147,-18),(143,-11),(140,-17),(136,-12),(130,-12),(123,-16),(119,-20)],
 [(-8,50),(-5,51),(-6,55),(-3,58),(0,59),(1,53)],
 [(-10,51),(-10,55),(-6,55),(-6,52)],
 [(-24,63),(-22,67),(-14,66),(-13,64)],
 [(43,-12),(49,-13),(50,-17),(46,-25),(43,-25)],
 [(130,31),(132,35),(136,36),(141,41),(145,44),(145,42),(139,37),(136,34)],
 [(95,5),(99,4),(104,-3),(106,-6),(102,-5)],
 [(106,-6),(111,-7),(115,-8),(114,-9),(108,-8)],
 [(109,7),(117,7),(119,1),(115,-4),(109,-1)],
 [(130,-2),(140,-2),(150,-6),(149,-10),(142,-9),(138,-5)],
 [(166,-34),(175,-38),(178,-42),(172,-41),(167,-46),(166,-44),(171,-40)],
 [(-180,-73),(-160,-75),(-140,-73),(-120,-75),(-100,-73),(-80,-73),(-66,-63),(-60,-65),(-65,-73),(-40,-78),(-15,-74),(10,-70),(40,-68),(70,-70),(95,-66),(115,-66),(140,-66),(165,-72),(180,-73),(180,-90),(-180,-90)],
]

def land_mask(w,h,n):
    mask=np.zeros((h,w),np.float32)
    for poly in LAND:
        pts=np.array(poly,dtype=float)
        miny=max(0,int((90-pts[:,1].max())/180*(h-1)))
        maxy=min(h-1,int((90-pts[:,1].min())/180*(h-1))+1)
        for row in range(miny,maxy+1):
            yy=90-row/(h-1)*180;cross=[]
            for j in range(len(pts)):
                a,b=pts[j-1],pts[j]
                if (a[1]>yy)!=(b[1]>yy):
                    cross.append(a[0]+(yy-a[1])*(b[0]-a[0])/(b[1]-a[1]))
            cross.sort()
            for a,b in zip(cross[::2],cross[1::2]):
                ia=max(0,int((a+180)/360*(w-1)));ib=min(w,int((b+180)/360*(w-1))+1)
                mask[row,ia:ib]=1
    # Small deterministic domain warp roughens the hand-drawn coasts.
    rows=np.clip(np.arange(h)[:,None]+(n*h*.006).astype(int),0,h-1)
    cols=(np.arange(w)[None,:]+(np.roll(n,13,axis=1)*w*.004).astype(int))%w
    return mask[rows,cols]

def clouds(x,y,z,lat,seed):
    swirl=field(x,y,z,3,seed,3)
    # Longitude-dependent shearing remains continuous on the sphere.
    angle=swirl*.65+np.sin(lat*5)*.9
    xx=x*np.cos(angle)-y*np.sin(angle);yy=x*np.sin(angle)+y*np.cos(angle)
    c=field(xx*1.0,yy*1.0,z*2,12,seed+70,4)
    c+=.09*np.cos(lat*8)
    return smooth(.05,.36,c)*.82

def gas(body,lon,lat,x,y,z,n,detail,seed):
    name,kind,temp,hexcol=body
    if kind=='iceGiant':
        base=color(hexcol)
        if name=='neptune':base=color('588CBD')  # less saturated true-color methane blue
        bands=np.sin(lat*31+n*1.2)*.018+detail*.035
        image=base[None,None,:]*(1+bands[...,None])
        if name=='neptune':
            lo=(lon-.4+PI)%(2*PI)-PI
            storm=np.exp(-((lo/.19)**2+((lat+.37)/.074)**2)*2)
            image*=1-storm[...,None]*.15
            cloud=np.exp(-((lat+.27+np.sin(lon*3)*.01)/.016)**2)*smooth(.1,.45,n)*.13
            image=mix(image,[.8,.86,.87],cloud)
        return image
    v=lat + .014*np.sin(lon*9+lat*17) + .008*np.sin(lon*31+n*5)+n*.043
    # The anticyclone also diverts surrounding belts, not just a painted oval.
    lo=(lon-.44+PI)%(2*PI)-PI
    rr=(lo/.24)**2+((lat+np.deg2rad(22))/.105)**2
    if name=='jupiter':v+=.065*np.exp(-rr*.45)*np.sin(np.arctan2((lat+.384)/.105,lo/.24)*2)
    belt=.52+.25*np.sin(v*29+.4*np.sin(v*9))+.13*np.sin(v*53+.4)+.07*np.sin(v*109+n*7)
    filament=np.sin(v*235+n*9+detail*4)*.027+detail*.09
    if name=='saturn':
        image=mix(color('D1B67F'),color('EEE0B3'),np.clip(.35+belt*.48+filament,0,1))
        image=mix(image,color('A5AC91'),smooth(1.07,1.52,np.abs(lat))*.45)
    else:
        image=mix(color('916852' if name=='jupiter' else '886744'),color('EFE1C1'),np.clip(belt+filament,0,1))
        image=mix(image,color('B98763'),smooth(.8,1.5,np.abs(lat))*.45)
    if name=='jupiter':
        theta=np.arctan2((lat+.384)/.105,lo/.24)
        spiral=np.sin(np.sqrt(rr)*26-theta*3+n*6)*.06
        spot=mix(color('A96248'),color('DCAC7D'),np.clip(.4+np.sqrt(rr)*.22+spiral,0,1))
        image=mix(image,spot,(1-smooth(.65,1.08,rr))*.93)
        for a,b in [(-1.2,-.55),(1.3,-.5),(-2.3,.35),(.9,.6)]:
            d=((lon-a)/.053)**2+((lat-b)/.026)**2
            image=mix(image,color('EADFC6'),np.exp(-d*2)*.66)
    return image

def earth(lon,lat,x,y,z,n,detail,seed):
    h,w=n.shape;land=land_mask(w,h,n)
    shelf=land.copy()
    for k in (1,2,4):
        shelf=(shelf+np.roll(shelf,k,axis=1)+np.roll(shelf,-k,axis=1)+np.roll(shelf,k,axis=0)+np.roll(shelf,-k,axis=0))/5
    ocean=mix(color('0E2B47'),color('245870'),np.clip(shelf*1.4+detail*.05,0,1))
    deg=lat*180/PI;lng=lon*180/PI
    dry=smooth(.05,.35, np.cos(lat*5)*-.2+n*.7)
    sahara=np.exp(-((lng-18)/37)**4-((deg-23)/13)**4)
    australia=np.exp(-((lng-134)/22)**4-((deg+25)/14)**4)
    arabia=np.exp(-((lng-47)/15)**4-((deg-25)/15)**4)
    dry=np.clip(dry*.4+sahara*.98+australia*.85+arabia*.9,0,1)
    terrain=mix(color('354C31'),color('C4B07A'),dry)
    terrain*=1+detail[...,None]*.2+n[...,None]*.15
    cold=smooth(56,78,np.abs(deg)+n*14)
    terrain=mix(terrain,color('D1D4CB'),cold)
    image=mix(ocean,terrain,land)
    seaice=smooth(73,85,np.abs(deg)+n*11)
    image=mix(image,color('D5E1DE'),seaice)
    cloud=clouds(x,y,z,lat,seed+120)
    # Ice remains exposed while terrestrial cloud decks keep a soft white albedo.
    image=mix(image,color('E5E9E3'),cloud)
    rough=np.clip(.10+land*.77+cloud*.7+seaice*.6,0,1)
    emission=np.zeros_like(image)
    # Stylized sparse metropolitan locations, not a satellite night map.
    cities=[(-74,41),(-71,42),(-87,42),(-118,34),(-122,38),(-95,30),(-99,19),(-46,-24),(-58,-35),(-77,-12),(-.1,51),(2,49),(5,51),(13,52),(12,42),(30,31),(31,30),(29,41),(37,56),(77,29),(73,19),(90,24),(116,40),(121,31),(114,23),(127,38),(140,36),(135,35),(107,-6),(101,14),(151,-34),(145,-38),(28,-26),(3,7)]
    for clon,clat in cities:
        dx=((lng-clon+180)%360-180)*np.cos(np.deg2rad(clat));dy=deg-clat
        dots=np.exp(-(dx*dx+dy*dy)/.10)*.30
        emission+=dots[...,None]*color('DCAF6C')
    emission*=land[...,None]*(1-cloud[...,None]*.9)
    return image,rough,emission

def rocky(body,lon,lat,x,y,z,n,detail,seed):
    name,kind,temp,hexcol=body;h,w=n.shape
    fine=field(x,y,z,94,seed+90,2)
    relief=crater_field(w,h,seed,260 if kind=='rocky' else 80)
    base=color(hexcol)
    if kind=='lava':base=color('635149')
    image=base[None,None,:]*(.88+n[...,None]*.44+detail[...,None]*.22+fine[...,None]*.08+relief[...,None])
    emission=None;rough=np.full((h,w),.88,np.float32)
    if name=='mars':
        image=mix(image,color('594A3D'),smooth(.13,.39,n)*.69)
        # Broad albedo around Syrtis Major and a narrow canyon system.
        syrtis=np.exp(-((lon-.95)/.35)**2-((lat-.1)/.35)**2)
        image=mix(image,color('665246'),syrtis*.5)
        canyon=np.exp(-((lat+.17+.03*np.sin(lon*5))/ .014)**2)*np.exp(-((lon+1.03)/.4)**6)
        image*=1-canyon[...,None]*.25
        cap=smooth(1.37,1.48,np.abs(lat)+n*.1)
        image=mix(image,color('DDDDCC'),cap)
    elif name=='proxima-b':
        # The cold anti-stellar terrain is frozen. The warmer face stays rocky.
        frost=smooth(.08,.58,-x+n*.35)
        image=mix(image,color('CDD0C7')*(1+detail[...,None]*.11),frost*.8)
    elif kind=='ice' or name=='tau-ceti-f':
        icebase=color('BCD0D9' if kind=='ice' else '9BAEB8')
        cracks=1-smooth(.005,.034,np.abs(field(x+n*.09,y+n*.09,z,11,seed+170,3)))
        ice=icebase[None,None,:]*(.94+detail[...,None]*.15+n[...,None]*.11)
        image=mix(image,ice,np.full((h,w),.87))
        image=mix(image,color('617C8A'),cracks*.32)
    elif kind=='lava':
        flow=field(x+n*.16,y+n*.16,z+n*.16,9,seed+240,3)
        cracks=1-smooth(.007,.025,np.abs(flow))
        dayside=smooth(.0,.65,x)
        cracks*=dayside
        image=mix(image,color('9F6544'),cracks*.4)
        hot=smooth(.008,.0,np.abs(flow))
        emission=mix(thermal_rgb(1200),thermal_rgb(1800),hot)*cracks[...,None]
    elif kind=='desert' or name=='tau-ceti-e':
        dune=(.5+.5*np.sin(lat*310+n*20+detail*9))*smooth(.0,.35,n)
        image*=1+dune[...,None]*.045
    return image,rough,emission

def make(body,w,h,seed):
    lon,lat,x,y,z=coords(w,h)
    n=field(x,y,z,3.1,seed,4);detail=field(x+n*.17,y+n*.17,z+n*.17,21,seed+8,3)
    name,kind,temp,hexcol=body
    em=None;rough=None
    if kind in ('gasGiant','iceGiant'):
        image=gas(body,lon,lat,x,y,z,n,detail,seed)
    elif name=='earth':
        image,rough,em=earth(lon,lat,x,y,z,n,detail,seed)
    elif name=='venus':
        # Opaque sulfuric-acid cloud deck: the surface is never visible from orbit.
        swirl=field(x,y,z*2.5,7,seed+50,4)
        wave=np.sin(lat*13+n*4+np.sin(lon*3)*.15)
        image=mix(color('BCAB84'),color('E6D9AE'),np.clip(.66+swirl*.4+wave*.07,0,1))
    elif kind=='whiteDwarf':
        # Almost featureless hot photosphere; never draw a rocky planet here.
        image=color('D7E4FA')[None,None,:]*(.99+detail[...,None]*.008)
        em=image.copy()
    elif kind=='ocean':
        land=smooth(.22,.36,n)
        landcolor=color('847C61')[None,None,:]*(1+detail[...,None]*.15)
        ocean=color('244963' if name.endswith('e') else '376580')[None,None,:]*(1+detail[...,None]*.13)
        image=mix(ocean,landcolor,land)
        # Tidally locked hypothetical open ocean on the substellar hemisphere.
        threshold=-.15 if name.endswith('e') else .45
        ice=smooth(.02,.32,threshold-x+n*.32)
        icecol=color('B6C9D0')[None,None,:]*(1+detail[...,None]*.1)
        image=mix(image,icecol,ice)
        cl=clouds(x,y,z,lat,seed+120)*smooth(-.5,.8,x)*.68
        image=mix(image,color('DAE0DC'),cl)
        rough=np.clip(.10+land*.76+ice*.7+cl*.6,0,1)
    else:
        image,rough,em=rocky(body,lon,lat,x,y,z,n,detail,seed)
    # Identical seam columns and longitude-invariant pole rows are part of the
    # export contract. UV bilinear filtering therefore cannot reveal a split.
    for a in (image,rough,em):
        if a is None:continue
        a[:,-1]=a[:,0]
        a[0]=np.mean(a[0],axis=0);a[-1]=np.mean(a[-1],axis=0)
    return np.clip(image,0,1),rough,em

def preview(image,em,name,size=256):
    v=np.linspace(-1.13,1.13,size,dtype=np.float32)
    xx,yy=np.meshgrid(v,-v);rad=xx*xx+yy*yy;inside=rad<=1
    zz=np.sqrt(np.maximum(0,1-rad))
    center=.15 if name=='earth' else .35
    lon=np.arctan2(xx,zz)+center;lat=np.arcsin(np.clip(yy,-1,1))
    h,w,_=image.shape
    col=((lon+PI)/(2*PI)*(w-1)).astype(int)%w
    row=np.clip(((PI/2-lat)/PI*(h-1)).astype(int),0,h-1)
    tex=image[row,col]
    sunlight=np.maximum(0,xx*-.40+yy*.25+zz*.88)
    lighting=np.maximum(0,sunlight)*.99+.002
    rgb=np.clip(tex**2.2*lighting[...,None],0,1)**(1/2.2)
    if em is not None:
        mask=(1-smooth(0,.15,sunlight)) if name=='earth' else np.ones_like(sunlight)
        rgb=np.clip(rgb+em[row,col]*mask[...,None],0,1)
    if name=='sirius-b':rgb=tex
    if name in ('earth','trappist-1e','trappist-1f'):
        rim=(1-zz)**4*sunlight*.35
        rgb=np.clip(rgb+rim[...,None]*np.array([.15,.38,.60]),0,1)
    background=np.zeros_like(rgb)+np.array([.014,.022,.035])
    return np.where(inside[...,None],rgb,background)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--quick',action='store_true');parser.add_argument('--final',action='store_true')
    parser.add_argument('--only',default='',help='Comma-separated IDs for iteration')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    w,h=(2048,1024) if args.final else (256,128)
    target=ASSETS if args.final else OUT/'quick'
    selected=[b for b in BODIES if not args.only or b[0] in args.only.split(',')]
    start=time.perf_counter();reports=[];previews=[]
    for body in selected:
        t=time.perf_counter();name=body[0]
        seed=100+BODIES.index(body)*19
        albedo,rough,em=make(body,w,h,seed)
        path=target/f'planet-{name}.png';png(path,albedo)
        extras=[]
        if rough is not None and (name=='earth' or body[1]=='ocean'):
            p=target/f'planet-{name}-roughness.png';png(p,np.repeat(rough[...,None],3,axis=2));extras.append(p.name)
        if em is not None:
            p=target/f'planet-{name}-emissive.png';png(p,em);extras.append(p.name)
        globe=preview(albedo,em,name)
        png(OUT/f'{name}-sphere.png',globe);previews.append(globe)
        info={'id':name,'class':body[1],'temperatureK':body[2],'seed':seed,'albedo':str(path.relative_to(ROOT)),
              'size':[w,h],'extra_maps':extras,'seconds':round(time.perf_counter()-t,3),
              'seam_max_difference':float(np.max(np.abs(albedo[:,0]-albedo[:,-1]))),
              'pole_longitude_range':float(max(np.ptp(albedo[0],axis=0).max(),np.ptp(albedo[-1],axis=0).max()))}
        reports.append(info);print(json.dumps(info),flush=True)
    cols=7;rows=math.ceil(len(previews)/cols)
    sheet=np.zeros((rows*272,cols*256,3),np.float32)+np.array([.014,.022,.035])
    for i,globe in enumerate(previews):
        yy,xx=divmod(i,cols);sheet[yy*272:yy*272+256,xx*256:xx*256+256]=globe
    png(OUT/('final-contact-sheet.png' if args.final else 'quick-contact-sheet.png'),sheet)
    summary={'mode':'final' if args.final else 'quick','total_seconds':round(time.perf_counter()-start,3),'bodies':reports}
    (OUT/('final-report.json' if args.final else 'quick-report.json')).write_text(json.dumps(summary,indent=2))
    print(f'Done: {len(reports)} bodies in {summary["total_seconds"]:.2f}s',flush=True)

if __name__=='__main__':main()
