#!/usr/bin/env python3
"""Convert assets/logo.png into a fastfetch ASCII logo (assets/fastfetch/logo.txt).
Two colours: $1 = the shaded purple disc and the cat's eyes, nose and mouth, $2 = the solid white cat.
usage: make-logo.py [COLS]   (default 56 columns; rows = COLS/2 because terminal cells are ~1:2)"""
import subprocess, sys, os
here = os.path.dirname(os.path.abspath(__file__))
cols = int(sys.argv[1]) if len(sys.argv) > 1 else 56
rows = cols // 2
raw = subprocess.run(['convert', os.path.join(here, '..', 'logo.png'), '-background', 'none', '-alpha', 'on',
                      '-filter', 'Box', '-resize', f'{cols}x{rows}!', '-depth', '8', 'txt:-'],
                     capture_output=True, text=True, check=True).stdout
grid = {}
for line in raw.splitlines():
    if line.startswith('#'): continue
    coord, rest = line.split(':', 1)
    x, y = map(int, coord.split(','))
    r, g, b, a = [int(v) for v in rest.split('(')[1].split(')')[0].split(',')[:4]]
    grid[(x, y)] = (r, g, b, a)
out = []
for y in range(rows):
    cur, s = None, ''
    for x in range(cols):
        r, g, b, a = grid[(x, y)]
        if a < 128:
            ch, col = ' ', None
        elif (r + g + b) / 3 > 170:
            ch, col = '█', '$2'      # white cat
        else:
            ch, col = '▒', '$1'      # purple disc / features (shaded so the cat reads without colour)
        if col and col != cur:
            s += col; cur = col
        s += ch
    out.append(s.rstrip())
while out and not out[0].strip(): out.pop(0)
while out and not out[-1].strip(): out.pop()
open(os.path.join(here, 'logo.txt'), 'w').write('\n'.join(out) + '\n')
print(len(out), 'lines')
