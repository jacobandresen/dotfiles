#!/usr/bin/env python3
"""Render demo/taskbay.cast as an animated GIF: python3 demo/gif.py [in.cast] [out.gif]

The recorder saves every frame as a full screen redraw, so each frame is drawn on a
character grid from its SGR colours. Needs Pillow and a monospace font with Nerd Font
icons (TASKBAY_FONT, else fontconfig's "Hack Nerd Font Mono", else "monospace")."""
import json, os, re, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

here = Path(__file__).resolve().parent
source = Path(sys.argv[1] if len(sys.argv) > 1 else here / "taskbay.cast")
target = Path(sys.argv[2] if len(sys.argv) > 2 else here / "taskbay.gif")
FG, BG, SIZE, IDLE = (235, 219, 178), (28, 28, 28), 14, 2.0

def font_file(style):
    for name in filter(None, [os.environ.get("TASKBAY_FONT"), "Hack Nerd Font Mono", "monospace"]):
        found = subprocess.run(["fc-match", "-f", "%{file}", f"{name}:style={style}"], capture_output=True, text=True).stdout
        if found: return found
fonts = {False: ImageFont.truetype(font_file("Regular"), SIZE), True: ImageFont.truetype(font_file("Bold"), SIZE)}
left, top, right, bottom = fonts[False].getbbox("M")
cw, ch = round(fonts[False].getlength("M")), SIZE + 4

def palette(n):  # xterm 256 colours
    base = [(0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0), (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
            (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0), (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)]
    if n < 16: return base[n]
    if n < 232:
        n -= 16
        return tuple(0 if v == 0 else 55 + v * 40 for v in (n // 36, n // 6 % 6, n % 6))
    return (8 + (n - 232) * 10,) * 3

def render(text, width, height):
    image = Image.new("RGB", (width * cw, height * ch), BG)
    draw = ImageDraw.Draw(image)
    body = text.split("\x1b[2J", 1)[-1]
    body, cursor = re.subn(r"\x1b\[(\d+);(\d+)H$", "", body)
    fg, bg, bold, reverse = FG, None, False, False
    for row, line in enumerate(body.split("\r\n")[:height]):
        col = 0
        for token in re.split(r"(\x1b\[[0-9;]*m)", line):
            if token.startswith("\x1b["):
                codes = [int(c) if c else 0 for c in token[2:-1].split(";")]
                i = 0
                while i < len(codes):
                    c = codes[i]
                    if c == 0: fg, bg, bold, reverse = FG, None, False, False
                    elif c == 1: bold = True
                    elif c == 22: bold = False
                    elif c == 7: reverse = True
                    elif c == 27: reverse = False
                    elif c == 39: fg = FG
                    elif c == 49: bg = None
                    elif c in (38, 48):
                        colour = tuple(codes[i + 2:i + 5]) if codes[i + 1] == 2 else palette(codes[i + 2])
                        i += 4 if codes[i + 1] == 2 else 2
                        if c == 38: fg = colour
                        else: bg = colour
                    elif 30 <= c <= 37 or 90 <= c <= 97: fg = palette(c - 30 if c < 90 else c - 82)
                    elif 40 <= c <= 47 or 100 <= c <= 107: bg = palette(c - 40 if c < 100 else c - 92)
                    i += 1
                continue
            front, back = (bg or BG, fg) if reverse else (fg, bg)
            for char in token:
                x, y = col * cw, row * ch
                if back: draw.rectangle([x, y, x + cw - 1, y + ch - 1], fill=back)
                if char != " ": draw.text((x, y + 2), char, font=fonts[bold], fill=front)
                col += 1
    return image

lines = source.read_text().splitlines()
header, events = json.loads(lines[0]), [json.loads(line) for line in lines[1:] if line]
frames, durations = [], []
for index, (time, _, text) in enumerate(events):
    following = events[index + 1][0] if index + 1 < len(events) else time + 3
    frames.append(render(text, header["width"], header["height"]).quantize(colors=128, dither=Image.Dither.NONE))
    durations.append(max(20, round(min(following - time, IDLE) * 1000)))
frames[0].save(target, save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True, disposal=1)
print(f"{target}: {len(frames)} frames, {sum(durations) / 1000:.0f}s, {target.stat().st_size // 1024} KiB")
