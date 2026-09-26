"""Deterministic volumetric Voronoi fracture in vacuum. Blender 5.2 only."""
import argparse, math, os, random, sys, time
import bpy, bmesh
import numpy as np
from mathutils import Vector, Quaternion

ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p=argparse.ArgumentParser(); p.add_argument('--quick',action='store_true'); p.add_argument('--final',action='store_true')
args=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
QUICK=args.quick and not args.final
START=time.perf_counter(); SEED=6947; rng=random.Random(SEED)
OUT=os.path.join(ROOT,'blender/codex/out/shatter'); os.makedirs(OUT,exist_ok=True)
os.makedirs(os.path.join(ROOT,'assets/sprites'),exist_ok=True)

# Clip a convex polyhedron by n.dot(x) <= offset, retaining the new planar cap.
# This is the actual Voronoi half-space construction, not random rock stand-ins.
def clip(faces,n,offset):
    result=[]; intersections=[]
    for poly,is_outer in faces:
        out=[]
        for i,a in enumerate(poly):
            b=poly[(i+1)%len(poly)]
            da=n.dot(a)-offset; db=n.dot(b)-offset
            ina=da<=1e-7; inb=db<=1e-7
            if ina: out.append(a)
            if ina != inb:
                point=a+(b-a)*(da/(da-db))
                out.append(point); intersections.append(point)
        if len(out)>=3: result.append((out,is_outer))
    unique={tuple(round(c,6) for c in v):v for v in intersections}
    if len(unique)>=3:
        cap=list(unique.values()); center=sum(cap,Vector())/len(cap)
        helper=Vector((0,0,1)) if abs(n.z)<.9 else Vector((1,0,0))
        u=n.cross(helper).normalized(); v=n.cross(u)
        cap.sort(key=lambda q:math.atan2((q-center).dot(v),(q-center).dot(u)))
        result.append((cap,False))
    return result

def rock_material(name,low,high,scale):
    mat=bpy.data.materials.new(name); mat.use_nodes=True
    nt=mat.node_tree; bsdf=nt.nodes.get('Principled BSDF')
    noise=nt.nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value=scale; noise.inputs['Detail'].default_value=4
    tex=nt.nodes.new('ShaderNodeTexCoord'); nt.links.new(tex.outputs['Generated'],noise.inputs['Vector'])
    ramp=nt.nodes.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].position=.24; ramp.color_ramp.elements[0].color=(*low,1)
    ramp.color_ramp.elements[1].position=.78; ramp.color_ramp.elements[1].color=(*high,1)
    nt.links.new(noise.outputs['Fac'],ramp.inputs[0]); nt.links.new(ramp.outputs['Color'],bsdf.inputs['Base Color'])
    bump=nt.nodes.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=.28; bump.inputs['Distance'].default_value=.025
    nt.links.new(noise.outputs['Fac'],bump.inputs['Height']); nt.links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
    bsdf.inputs['Roughness'].default_value=.82
    return mat

bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=16 if QUICK else 48
scene.cycles.use_denoising=True; scene.cycles.seed=SEED; scene.cycles.use_animated_seed=False
scene.render.threads_mode='FIXED'; scene.render.threads=3
scene.render.resolution_x=scene.render.resolution_y=256; scene.render.resolution_percentage=100
scene.render.film_transparent=True; scene.render.image_settings.file_format='PNG'; scene.render.image_settings.color_mode='RGBA'; scene.render.image_settings.color_depth='8'
scene.view_settings.view_transform='AgX'; scene.view_settings.look='AgX - Medium High Contrast'
scene.world.color=(.10,.10,.10)
bpy.ops.object.camera_add(location=(5,-8,6)); cam=bpy.context.object
cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.type='ORTHO'; cam.data.ortho_scale=6.5; scene.camera=cam
for loc,power,color,size in [((-3,-4,7),1050,(1,.75,.50),4),((4,2,3),1400,(.45,.67,1),3),((1,-7,1),260,(1,.91,.81),5)]:
    bpy.ops.object.light_add(type='AREA',location=loc); light=bpy.context.object; light.data.energy=power; light.data.color=color; light.data.size=size
    light.rotation_euler=(Vector((0,0,0))-light.location).to_track_quat('-Z','Y').to_euler()
outer=rock_material('Weathered silicate exterior',(.038,.031,.027),(.30,.20,.10),6)
inner=rock_material('Fresh fractured silicate',(.09,.075,.062),(.42,.34,.23),9)

base=bmesh.new(); bmesh.ops.create_icosphere(base,subdivisions=3,radius=1)
base_faces=[([v.co.copy() for v in f.verts],True) for f in base.faces]; base.free()
# Six widely separated seeds occupy the core. A dense shell creates 78 smaller
# surface cells. The resulting fragments are volumetric and fit one parent body.
seeds=[Vector(v)*.32 for v in [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]]
golden=math.pi*(3-math.sqrt(5))
for i in range(78):
    z=1-2*(i+.5)/78; radius=math.sqrt(1-z*z); phi=i*golden+rng.uniform(-.1,.1)
    radial=rng.uniform(.75,.95)
    seeds.append(Vector((radius*math.cos(phi),radius*math.sin(phi),z))*radial)
impact=Vector((.04,-.06,.08)); chunks=[]
for index,seed in enumerate(seeds):
    faces=base_faces
    others=sorted((s for j,s in enumerate(seeds) if j!=index),key=lambda s:(s-seed).length_squared)
    for other in others:
        delta=other-seed; n=delta.normalized(); offset=(other.length_squared-seed.length_squared)/(2*delta.length)
        faces=clip(faces,n,offset)
        if not faces: break
    unique={tuple(round(c,6) for c in v):v for poly,_ in faces for v in poly}
    if len(unique)<4: continue
    center=sum(unique.values(),Vector())/len(unique)
    vertices=[]; polys=[]; face_types=[]; ids={}
    for poly,is_outer in faces:
        ids_for_face=[]
        for v in poly:
            key=tuple(round(c,6) for c in v)
            if key not in ids:
                ids[key]=len(vertices); vertices.append(tuple((v-center)*.94))
            ids_for_face.append(ids[key])
        if len(set(ids_for_face))>=3:
            polys.append(ids_for_face); face_types.append(is_outer)
    mesh=bpy.data.meshes.new(f'Voronoi cell {index:02d}'); mesh.from_pydata(vertices,[],polys); mesh.update()
    bm=bmesh.new(); bm.from_mesh(mesh); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(mesh); bm.free()
    ob=bpy.data.objects.new(f'Rock chunk {index:02d}',mesh); bpy.context.collection.objects.link(ob)
    mesh.materials.append(outer); mesh.materials.append(inner)
    for face,was_outer in zip(mesh.polygons,face_types): face.material_index=0 if was_outer else 1
    bevel=ob.modifiers.new('Broken edge highlights','BEVEL'); bevel.width=.005; bevel.segments=1
    direction=center-impact; distance=direction.length
    velocity=direction.normalized()*(.35/distance)
    spin_axis=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-1,1))).normalized()
    omega=rng.uniform(.35,1.6)
    ob.rotation_mode='QUATERNION'; chunks.append((ob,center,velocity,spin_axis,omega))
print(f'Voronoi cells generated: {len(chunks)} in {time.perf_counter()-START:.2f}s',flush=True)

def pose(t):
    for ob,start,velocity,axis,omega in chunks:
        ob.location=start+velocity*t
        ob.rotation_quaternion=Quaternion(axis,omega*t)

def assemble(paths,target):
    atlas_array=np.zeros((1024,1024,4),np.float32)
    for i,path in enumerate(paths):
        img=bpy.data.images.load(path,check_existing=False); arr=np.empty(len(img.pixels),np.float32); img.pixels.foreach_get(arr)
        row=3-i//4; col=i%4
        atlas_array[row*256:(row+1)*256,col*256:(col+1)*256]=arr.reshape(256,256,4)
        bpy.data.images.remove(img)
    img=bpy.data.images.new('Shatter atlas',width=1024,height=1024,alpha=True); img.colorspace_settings.name='sRGB'
    img.pixels.foreach_set(atlas_array.ravel()); img.filepath_raw=target; img.file_format='PNG'; img.save()

if QUICK:
    pose(1.15); scene.render.filepath=os.path.join(OUT,'shatter-preview.png'); bpy.ops.render.render(write_still=True)
else:
    paths=[]
    for frame in range(16):
        pose(1.8*frame/15)
        path=os.path.join(OUT,f'shatter-{frame:02d}.png'); paths.append(path)
        scene.render.filepath=path; bpy.ops.render.render(write_still=True)
    assemble(paths,os.path.join(ROOT,'assets/sprites/shatter-debris-4x4.png'))
print(f'SHATTER_COMPLETE mode={"quick" if QUICK else "final"} seconds={time.perf_counter()-START:.2f}',flush=True)
