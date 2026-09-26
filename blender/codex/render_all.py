"""Run the FOLDSPACE asset generators sequentially to control memory use.

python3 blender/codex/render_all.py --quick
python3 blender/codex/render_all.py --final
"""
import argparse
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--quick',action='store_true')
    mode.add_argument('--final',action='store_true')
    parser.add_argument('--blender',default='/Applications/Blender.app/Contents/MacOS/Blender')
    argv=sys.argv[1:]
    if '--' in argv: argv=argv[argv.index('--')+1:]
    args=parser.parse_args(argv)
    root=Path(__file__).resolve().parents[2]
    started=time.monotonic()
    for name in ('blackhole','sun','planets','warp','galaxies','shatter'):
        command=[args.blender,'--background','--factory-startup','--threads','3',
                 '--python',str(root/'blender/codex'/f'{name}.py'),'--',
                 '--quick' if args.quick else '--final']
        print(f'Generating {name}',flush=True)
        subprocess.run(command,cwd=root,check=True)
    print(f'All generators completed in {time.monotonic()-started:.1f} seconds.')


if __name__=='__main__':
    main()
