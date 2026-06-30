#!/usr/bin/env python3
"""Generate the classic Mac icon (assets/happy-mac.svg) from a 32x32 pixel grid.

A compact Macintosh in beige with a black CRT showing a green-phosphor shell
prompt (">_") -- the classic Mac silhouette, dressed as a terminal to match
WezTerm. Drawn one rect per pixel with crisp edges so it scales cleanly, and on a
transparent background so it reads on any panel. Edit the drawing primitives /
palette below and re-run.

Exit codes:
  0: Success
  1: Error (permission denied, cannot write file, etc.)
"""
import os
import sys

W = H = 32
# grid states -> colours (None = transparent)
PALETTE = {
    '#': '#1a1a1a',   # case outline, groove, floppy slot, screen bezel
    'B': '#dccfa8',   # beige case
    'K': '#0a140a',   # black CRT glass (faint green tint)
    'G': '#33ff66',   # green phosphor prompt
}
g = [[' '] * W for _ in range(H)]


def rect(x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = ch


def px(x, y, ch):
    g[y][x] = ch


def chamfer(x0, y0, x1, y1):
    # knock out the 4 extreme corners for a rounded feel
    for (x, y) in [(x0, y0), (x1, y0), (x0, y1), (x1, y1)]:
        g[y][x] = ' '


# --- body (compact Mac case) ---
rect(6, 2, 25, 29, '#')        # dark shell
rect(7, 3, 24, 28, 'B')        # beige interior -> 1px border
chamfer(6, 2, 25, 29)
chamfer(7, 3, 24, 28)

# --- screen (black CRT) ---
rect(9, 5, 22, 16, '#')        # bezel
rect(10, 6, 21, 15, 'K')       # glass

# --- green-phosphor shell prompt on the screen ---
px(12, 8, 'G')                 # ">" chevron
px(13, 9, 'G')
px(14, 10, 'G')
px(13, 11, 'G')
px(12, 12, 'G')
rect(16, 12, 19, 12, 'G')      # "_" cursor

# --- groove under the screen ---
rect(8, 19, 23, 19, '#')

# --- floppy disk slot ---
rect(11, 23, 20, 23, '#')

# --- emit SVG (one rect per pixel) ---
S = 10  # logical px size
rects = []
for y in range(H):
    for x in range(W):
        col = PALETTE.get(g[y][x])
        if col is None:
            continue
        rects.append(f'<rect x="{x*S}" y="{y*S}" width="{S}" height="{S}" fill="{col}"/>')

svg = (
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{W*S}" height="{H*S}" '
    f'viewBox="0 0 {W*S} {H*S}" shape-rendering="crispEdges">\n'
    + '\n'.join(rects)
    + '\n</svg>\n'
)

out = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', 'assets', 'happy-mac.svg'))

# Ensure output directory exists
out_dir = os.path.dirname(out)
if not os.path.exists(out_dir):
    try:
        os.makedirs(out_dir, exist_ok=True)
        print(f"  Created directory: {out_dir}")
    except OSError as e:
        print(f"  ✗ Failed to create directory {out_dir}: {e}" >&2)
        sys.exit(1)

# Check write permission
if not os.access(out_dir, os.W_OK):
    print(f"  ✗ No write permission for directory: {out_dir}" >&2)
    sys.exit(1)

try:
    with open(out, 'w') as f:
        f.write(svg)
    print(f"  ✓ Wrote {out} ({W*S}x{H*S})")
except IOError as e:
    print(f"  ✗ Failed to write {out}: {e}" >&2)
    sys.exit(1)
