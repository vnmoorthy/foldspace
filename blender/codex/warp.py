"""Analytic Alcubierre York-time sprite atlas; Blender 5.2, no external deps."""
import argparse, math, os, sys, time
import bpy
import numpy as np
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = argparse.ArgumentParser()
p.add_argument('--quick', action='store_true')
p.add_argument('--final', action='store_true')
args = p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
QUICK = args.quick and not args.final
START = time.perf_counter()
OUT = os.path.join(ROOT, 'blender/codex/out/warp')
os.makedirs(OUT, exist_ok=True)
os.makedirs(os.path.join(ROOT, 'assets/sprites'), exist_ok=True)
R, SIGMA, VELOCITY = 1.05, 5.5, 0.46

def york(x, y, envelope):
    r = math.hypot(x, y)
    if r < 1e-12:
        return 0.0
    derivative = SIGMA * ((1 / math.cosh(SIGMA * (r + R)))**2 - (1 / math.cosh(SIGMA * (r - R)))**2) / (2 * math.tanh(SIGMA * R))
    return envelope * VELOCITY * (x / r) * derivative

def rgba(z):
    # Exactly zero is neutral ice-white; signed York time selects its hue.
    t = min(1.0, abs(z) / 0.27)
    neutral = np.array([0.025, 0.19, 0.28])
    col = np.array([1.0, .095, .033]) if z > 0 else np.array([.025, .24, 1.0])
    rgb = neutral * (1 - t) + col * t
    return (*rgb, 1)

def material(name, emission, alpha=1):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    attr = nodes.new('ShaderNodeVertexColor'); attr.layer_name = 'YorkColor'
    shader = nodes.new('ShaderNodeEmission')
    shader.inputs['Strength'].default_value = emission
    mat.node_tree.links.new(attr.outputs['Color'], shader.inputs['Color'])
    output = nodes.new('ShaderNodeOutputMaterial')
    if alpha < 1:
        transparent = nodes.new('ShaderNodeBsdfTransparent')
        mix = nodes.new('ShaderNodeMixShader'); mix.inputs[0].default_value = alpha
        mat.node_tree.links.new(transparent.outputs[0], mix.inputs[1])
        mat.node_tree.links.new(shader.outputs[0], mix.inputs[2])
        mat.node_tree.links.new(mix.outputs[0], output.inputs['Surface'])
    else:
        mat.node_tree.links.new(shader.outputs[0], output.inputs['Surface'])
    return mat

def colored_mesh(name, verts, faces, colors, mat):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces); mesh.update()
    att = mesh.color_attributes.new(name='YorkColor', type='FLOAT_COLOR', domain='POINT')
    att.data.foreach_set('color', np.array(colors, np.float32).ravel())
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob

bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32 if QUICK else 64
scene.cycles.use_denoising = True
scene.cycles.seed = 0
scene.cycles.use_animated_seed = False
scene.render.threads_mode = 'FIXED'; scene.render.threads = 3
scene.render.resolution_x = scene.render.resolution_y = 256 if QUICK else 512
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'; scene.render.image_settings.color_mode = 'RGBA'
scene.render.image_settings.color_depth = '8'
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.world.color = (.045, .045, .045)
bpy.ops.object.camera_add(location=(3.0, -6.7, 4.3))
cam = bpy.context.object; cam.name = 'York camera'
cam.rotation_euler = (Vector((0,0,0)) - cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.type='ORTHO'; cam.data.ortho_scale=5.5
scene.camera=cam
bpy.ops.object.light_add(type='AREA', location=(1,-3,6))
bpy.context.object.data.energy = 500; bpy.context.object.data.shape='DISK'; bpy.context.object.data.size=5
surf_mat = material('Soft signed spacetime surface', .4, .12)
line_mat = material('Signed coordinate grid', 1.8)

# Sample the finite coordinate patch and color it by signed York time.
def make_frame(envelope):
    for ob in list(bpy.data.objects):
        if ob.type == 'MESH':
            bpy.data.objects.remove(ob, do_unlink=True)
    extent=2.0; n=101
    verts=[]; cols=[]; faces=[]
    for iy in range(n):
        y=-extent+2*extent*iy/(n-1)
        for ix in range(n):
            x=-extent+2*extent*ix/(n-1); z=york(x,y,envelope)
            verts.append((x,y,z)); cols.append(rgba(z))
    for iy in range(n-1):
        for ix in range(n-1):
            k=iy*n+ix; faces.append((k,k+1,k+1+n,k+n))
    surface=colored_mesh('York time rubber sheet',verts,faces,cols,surf_mat)
    for poly in surface.data.polygons: poly.use_smooth=True
    # Each visible grid line is a continuous ribbon on the analytic surface.
    verts=[]; faces=[]; cols=[]
    samples=145
    for axis in range(2):
        for j in range(27):
            fixed=-extent+2*extent*j/26
            width=.0042 if j%2 else .006
            base=len(verts)
            for k in range(samples):
                varying=-extent+2*extent*k/(samples-1)
                for side in (-1,1):
                    x,y=(fixed+side*width,varying) if axis==0 else (varying,fixed+side*width)
                    z=york(x,y,envelope)
                    verts.append((x,y,z+.012)); cols.append(rgba(z))
                if k:
                    a=base+2*(k-1); faces.append((a,a+1,a+3,a+2))
    colored_mesh('Coordinates following exact York surface',verts,faces,cols,line_mat)
    # A tiny direction arrow occupies the flat interior and points along +x.
    verts=[(-.12,-.036,.045),(.05,-.036,.045),(.05,-.082,.045),(.17,0,.045),(.05,.082,.045),(.05,.036,.045),(-.12,.036,.045)]
    colored_mesh('Ship direction +x',verts,[tuple(range(7))],[(.75,.94,1,1)]*7,line_mat)

def assemble(paths, target, cols, rows):
    arrays=[]
    for path in paths:
        img=bpy.data.images.load(path,check_existing=False)
        arr=np.empty(len(img.pixels),np.float32); img.pixels.foreach_get(arr)
        arrays.append(arr.reshape(img.size[1],img.size[0],4))
        bpy.data.images.remove(img)
    h,w=arrays[0].shape[:2]
    pixels=np.zeros((h*rows,w*cols,4),np.float32)
    for i,arr in enumerate(arrays):
        row=rows-1-i//cols; col=i%cols
        pixels[row*h:(row+1)*h,col*w:(col+1)*w]=arr
    atlas=bpy.data.images.new('Warp atlas',width=w*cols,height=h*rows,alpha=True)
    atlas.colorspace_settings.name='sRGB'
    atlas.pixels.foreach_set(pixels.ravel()); atlas.filepath_raw=target; atlas.file_format='PNG'; atlas.save()

if QUICK:
    make_frame(1.0)
    scene.render.filepath=os.path.join(OUT,'warp-preview.png')
    bpy.ops.render.render(write_still=True)
else:
    paths=[]
    for frame in range(8):
        # C1-smooth activation with exact flat endpoints, symmetric through loop.
        envelope=math.sin(math.pi*frame/7)**2
        make_frame(envelope)
        path=os.path.join(OUT,f'warp-{frame:02d}.png'); paths.append(path)
        scene.render.filepath=path; bpy.ops.render.render(write_still=True)
    assemble(paths,os.path.join(ROOT,'assets/sprites/warp-bubble-8x1.png'),8,1)
print(f'WARP_COMPLETE mode={"quick" if QUICK else "final"} seconds={time.perf_counter()-START:.2f}',flush=True)
