"""Validate the Blender handoff. Run with system Python (NumPy + Pillow).

python3 blender/codex/validate_assets.py --quick  # validate available final files
python3 blender/codex/validate_assets.py --final  # require all deliverables
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT/'assets'
BODIES = ('mercury venus earth mars jupiter saturn uranus neptune proxima-b proxima-d '
          'barnard-b barnard-c barnard-d barnard-e wolf-359-b sirius-b eps-eri-b '
          'tau-ceti-e tau-ceti-f trappist-1b trappist-1c trappist-1d trappist-1e '
          'trappist-1f trappist-1g trappist-1h').split()
CONTRACT = {f'textures/planet-{body}.png':((2048,1024),'RGB') for body in BODIES}
CONTRACT.update({
    'textures/sun-photosphere.png':((2048,1024),'RGB'),
    'textures/sun-corona.png':((2048,2048),'RGBA'),
    'textures/blackhole-still.png':((2048,2048),'RGBA'),
    'textures/galaxy-milkyway.png':((4096,4096),'RGBA'),
    'textures/galaxy-andromeda.png':((4096,4096),'RGBA'),
    'textures/galaxy-milkyway-edge.png':((4096,1024),'RGBA'),
    'sprites/warp-bubble-8x1.png':((4096,512),'RGBA'),
    'sprites/shatter-debris-4x4.png':((1024,1024),'RGBA'),
})


def inspect_png(filename, expected=None):
    with Image.open(filename) as im:
        if expected:
            assert im.size == expected[0], f'{filename.name}: size {im.size} != {expected[0]}'
            assert im.mode == expected[1], f'{filename.name}: mode {im.mode} != {expected[1]}'
        out={'width':im.width,'height':im.height,'mode':im.mode}
        if im.mode == 'RGBA':
            alpha=im.getchannel('A')
            lo,hi=alpha.getextrema()
            assert lo==0 and hi>100, f'{filename.name}: missing transparency or content'
            out['alpha_range']=[lo,hi]
            out['content_bounds']=alpha.getbbox()
            out['transparent_pixels']=alpha.histogram()[0]
        if filename.name.startswith('planet-') and filename.name.endswith('.png'):
            left=np.array(im.crop((0,0,1,im.height))).astype(float)
            right=np.array(im.crop((im.width-1,0,im.width,im.height))).astype(float)
            out['uv_seam_mean_byte_difference']=round(float(np.abs(left-right).mean()),4)
        if filename.name=='warp-bubble-8x1.png':
            a=np.array(im.crop((0,0,512,512))).astype(float)
            b=np.array(im.crop((3584,0,4096,512))).astype(float)
            out['first_last_tile_mean_byte_difference']=round(float(np.abs(a-b).mean()),4)
            out['tile_order']='left to right, 512 × 512'
        if filename.name=='shatter-debris-4x4.png':
            out['tile_order']='top-left origin, row-major, 256 × 256'
            boxes=[]
            for i in range(16):
                x,y=(i%4)*256,(i//4)*256
                bounds=im.crop((x,y,x+256,y+256)).getchannel('A').getbbox()
                assert bounds is not None, f'Empty shatter frame {i}'
                boxes.append(bounds)
            out['tile_content_bounds']=boxes
        return out


def main():
    p=argparse.ArgumentParser(description=__doc__)
    mode=p.add_mutually_exclusive_group(required=True)
    mode.add_argument('--quick',action='store_true')
    mode.add_argument('--final',action='store_true')
    argv=sys.argv[1:]
    if '--' in argv: argv=argv[argv.index('--')+1:]
    args=p.parse_args(argv)
    errors=[]
    records=[]
    for relative,contract in CONTRACT.items():
        path=ASSETS/relative
        if not path.exists():
            if args.final: errors.append(f'Missing: {relative}')
            continue
        try:
            item={'path':relative,'required':True,**inspect_png(path,contract)}
            item['bytes']=path.stat().st_size
            item['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
            records.append(item)
        except Exception as e:
            errors.append(str(e))
    for path in sorted(ASSETS.rglob('*.png')):
        relative=str(path.relative_to(ASSETS))
        if relative in CONTRACT: continue
        if path.parent.name not in ('textures','sprites'): continue
        try:
            records.append({'path':relative,'required':False,**inspect_png(path),
                            'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        except Exception as e:
            errors.append(str(e))
    movie=ASSETS/'video/blackhole-loop.mov'
    movie_data=None
    if movie.exists():
        try:
            result=subprocess.run(['/opt/homebrew/bin/ffprobe','-v','error','-select_streams','v:0',
                                   '-show_streams','-of','json',str(movie)],check=True,capture_output=True,text=True)
            info=json.loads(result.stdout)['streams'][0]
            assert info['codec_name']=='hevc', 'Movie is not HEVC'
            assert (info['width'],info['height'])==(1080,1080), 'Movie resolution mismatch'
            assert info['avg_frame_rate']=='30/1', 'Movie frame rate mismatch'
            assert int(info['nb_frames'])==360, 'Movie does not contain 360 frames'
            assert abs(float(info['duration'])-12)<.001, 'Movie duration mismatch'
            report_path=ROOT/'blender/codex/out/blackhole/movie-verification.json'
            assert report_path.exists(), 'Missing native Apple alpha decode report'
            native=json.loads(report_path.read_text())
            assert native['contains_alpha_characteristic'], 'Missing HEVC alpha layer'
            assert native['alpha_min']==0 and native['alpha_max']==255, 'Alpha extremes absent'
            assert native['decoded_frames']==360, 'Native decoder did not read all frames'
            movie_data={'path':'video/blackhole-loop.mov','bytes':movie.stat().st_size,
                        'sha256':hashlib.sha256(movie.read_bytes()).hexdigest(),
                        'codec':'HEVC with alpha','native_decode':native}
        except Exception as e:
            errors.append(str(e))
    elif args.final:
        errors.append('Missing: video/blackhole-loop.mov')
    if args.final and not (ASSETS/'NOTES.md').exists(): errors.append('Missing: NOTES.md')
    manifest={'status':'pass' if not errors else 'fail','required_planet_count':len(BODIES),
              'required_png_count':len(CONTRACT),'pngs':records,'video':movie_data,'errors':errors}
    output=(ASSETS/'manifest.json') if args.final else (ROOT/'blender/codex/out/validation-partial.json')
    output.write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'status':manifest['status'],'pngs_checked':len(records),'errors':errors,
                      'report':str(output)},indent=2))
    return 1 if errors else 0


if __name__=='__main__':
    sys.exit(main())
