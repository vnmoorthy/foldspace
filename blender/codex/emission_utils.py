"""Small deterministic field helpers and a Cycles/AgX texture-plane renderer."""
from pathlib import Path
import math
import numpy as np
import bpy


def noise2(x, y, seed=0):
    """Continuous, deterministic value noise; does not require SciPy."""
    ix, iy = np.floor(x), np.floor(y)
    fx, fy = x-ix, y-iy
    fx, fy = fx*fx*(3-2*fx), fy*fy*(3-2*fy)
    def h(a, b):
        z = np.sin(a*127.1 + b*311.7 + seed*74.7) * 43758.5453
        return z-np.floor(z)
    return ((1-fx)*h(ix, iy)+fx*h(ix+1, iy))*(1-fy) + ((1-fx)*h(ix, iy+1)+fx*h(ix+1, iy+1))*fy


def fbm(x, y, seed=0, octaves=4):
    result = np.zeros(np.broadcast_shapes(np.shape(x), np.shape(y)), np.float32)
    weight, norm = 1.0, 0.0
    for i in range(octaves):
        result += weight*noise2(x, y, seed+i*3)
        norm += weight
        weight *= .5
        x, y = x*2.03+1.73, y*2.03-2.37
    return result/norm


def smoothstep(a, b, x):
    t = np.clip((x-a)/(b-a), 0, 1)
    return t*t*(3-2*t)


def reset(quick):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 8 if quick else 128
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = .03
    scene.cycles.adaptive_min_samples = 4 if quick else 8
    scene.cycles.use_denoising = True
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 2
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = 0
    scene.world = bpy.data.worlds.new('Black space')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes.get('Background').inputs[1].default_value = 0
    return scene


def float_image(name, rgba):
    h, w = rgba.shape[:2]
    image = bpy.data.images.new(name, width=w, height=h, alpha=True, float_buffer=True)
    image.alpha_mode = 'STRAIGHT'
    image.colorspace_settings.name = 'Linear Rec.709'
    image.pixels.foreach_set(np.ascontiguousarray(rgba, dtype=np.float32).ravel())
    image.update()
    return image


def emission_material(image, limb=False):
    mat = bpy.data.materials.new('Radiance with straight alpha')
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = image
    tex.interpolation = 'Linear'
    emission = nt.nodes.new('ShaderNodeEmission')
    nt.links.new(tex.outputs['Color'], emission.inputs['Color'])
    if limb:
        layer = nt.nodes.new('ShaderNodeLayerWeight')
        layer.inputs['Blend'].default_value = .5
        # Facing = 0 at normal incidence, 1 at grazing: 1 - .7*Facing.
        mul = nt.nodes.new('ShaderNodeMath'); mul.operation = 'MULTIPLY_ADD'
        mul.inputs[1].default_value = -.7; mul.inputs[2].default_value = 1
        nt.links.new(layer.outputs['Facing'], mul.inputs[0])
        nt.links.new(mul.outputs[0], emission.inputs['Strength'])
    transparent = nt.nodes.new('ShaderNodeBsdfTransparent')
    mix = nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(tex.outputs['Alpha'], mix.inputs[0])
    nt.links.new(transparent.outputs[0], mix.inputs[1])
    nt.links.new(emission.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs['Surface'])
    return mat


def render_plane(rgba, path, quick=False, rgb=False):
    """Bake an emission plane through Cycles and AgX, preserving transparency."""
    scene = reset(quick)
    h, w = rgba.shape[:2]
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.resolution_percentage = 100
    scene.render.image_settings.color_mode = 'RGB' if rgb else 'RGBA'
    image = float_image('Procedural linear radiance', rgba)
    bpy.ops.mesh.primitive_plane_add(size=2)
    plane = bpy.context.object
    plane.scale.x = w/h
    plane.data.materials.append(emission_material(image))
    bpy.ops.object.camera_add(location=(0, 0, 10))
    cam = bpy.context.object
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 2*w/h
    cam.rotation_euler = (0, 0, 0)
    scene.camera = cam
    # Blender cameras look down their local -Z, which is correct here.
    scene.render.filepath = str(path)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    return image


def save_scene(path):
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
