"""Create an asset review contact sheet from delivered files and rendered globes.

python3 blender/codex/make_preview.py --final
python3 blender/codex/make_preview.py --quick
"""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT=Path(__file__).resolve().parents[2]
BG=(7,10,17)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--quick',action='store_true')
    mode.add_argument('--final',action='store_true')
    args=parser.parse_args()
    page=Image.new('RGB',(1600,1200),BG)
    draw=ImageDraw.Draw(page)
    font='/System/Library/Fonts/Supplemental/Arial.ttf'
    title=ImageFont.truetype(font,44)
    sub=ImageFont.truetype(font,20)
    small=ImageFont.truetype(font,17)
    draw.text((42,32),'FOLDSPACE / ASSET REVIEW',font=title,fill=(226,234,247))
    draw.text((44,91),'Procedural space visuals · 26 worlds · transparent effects · Schwarzschild light bending',font=sub,fill=(129,154,183))
    def put(relative,box,crop=None,trim=False):
        path=ROOT/relative
        with Image.open(path) as source:
            im=source.convert('RGBA')
            if crop: im=im.crop(crop)
            if trim:
                bounds=im.getchannel('A').getbbox()
                if bounds: im=im.crop(bounds)
            fit=ImageOps.contain(im,(box[2]-box[0],box[3]-box[1]),Image.Resampling.LANCZOS)
            x=box[0]+(box[2]-box[0]-fit.width)//2
            y=box[1]+(box[3]-box[1]-fit.height)//2
            page.paste(fit,(x,y),fit)
    def label(x,y,text,caption=None):
        draw.text((x,y),text,font=sub,fill=(220,230,244))
        if caption: draw.text((x,y+27),caption,font=small,fill=(126,147,173))
    put('assets/textures/blackhole-still.png',(42,165,940,530),trim=True)
    label(44,555,'SAGITTARIUS A*','2K still + 1080p HEVC-alpha loop · 12 s / 30 fps')
    put('assets/textures/galaxy-milkyway.png',(984,157,1246,470))
    put('assets/textures/galaxy-andromeda.png',(1280,157,1542,470))
    label(988,484,'MILKY WAY')
    label(1284,484,'ANDROMEDA')
    draw.text((988,528),'4096 px · RGBA · logarithmic arms',font=small,fill=(126,147,173))
    draw.line((42,626,1558,626),fill=(35,45,61),width=1)
    for i,(body,name) in enumerate([('earth','Earth'),('jupiter','Jupiter'),('mars','Mars'),
                                  ('proxima-b','Proxima b'),('trappist-1e','TRAPPIST-1 e'),('neptune','Neptune')]):
        x=43+i*253
        put(f'blender/codex/out/planets/{body}-sphere.png',(x,655,x+206,861))
        draw.text((x+4,874),name,font=sub,fill=(220,230,244))
    draw.text((44,921),'All 26 UV maps: 2048 × 1024 RGB. Globes shown with inspection lighting.',font=small,fill=(126,147,173))
    put('blender/codex/out/sun/sun-preview.png',(44,970,220,1146))
    label(244,1002,'SUN','Granulation + transparent corona')
    put('assets/sprites/warp-bubble-8x1.png',(665,964,875,1158),crop=(1536,0,2048,512))
    label(890,1002,'WARP','8-frame York-time surface')
    put('assets/sprites/shatter-debris-4x4.png',(1240,970,1430,1160),crop=(768,768,1024,1024))
    draw.text((1408,1004),'DEBRIS',font=sub,fill=(220,230,244))
    draw.text((1408,1032),'16 frames',font=small,fill=(126,147,173))
    draw.text((44,1169),'Physics, assumptions, commands, timings and integration notes: assets/NOTES.md',font=small,fill=(102,123,149))
    if args.quick:
        page.thumbnail((800,600))
    target=ROOT/('blender/codex/out/asset-review-quick.png' if args.quick else 'assets/PREVIEW.png')
    page.save(target)
    print(target)


if __name__=='__main__':
    main()
