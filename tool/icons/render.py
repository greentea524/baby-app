#!/usr/bin/env python3
"""Regenerates the app's icon set from the SVGs beside this file.

    pip install Pillow && python3 tool/icons/render.py

Writes straight into web/. Needs a Chromium on disk; set CHROME to point at
one. Chromium is the rasteriser because the shapes are SVG paths, and its
--screenshot lays out in a viewport shorter than the window it is asked for
and pads the rest, so everything is rendered oversized into a known square,
cropped back, then downsampled. The 16px favicon in particular comes out far
cleaner downsampled from 1024 than drawn at 16px directly.
"""

import os
import subprocess
import tempfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(HERE, "..", "..", "web")
CHROME = os.environ.get(
    "CHROME", "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
)

# The manifest's theme_color, so the icon and the splash agree.
BG = "#7E9BD0"
MASTER = 1024


def body(name):
    art = open(os.path.join(HERE, name)).read()
    return art[art.index(">", art.index("<svg")) + 1 : art.rindex("</svg>")]


ART = body("bottle.svg")
# A 16px favicon cannot hold the measurement marks — they blur into a smear
# down one side of the bottle — so it gets a plainer, chunkier drawing.
ART_SIMPLE = body("bottle-simple.svg")


def page(*, radius, scale, inner):
    off = (1 - scale) * 512 / 2
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
      html,body{{margin:0;padding:0;background:transparent}}
      svg{{display:block}}
    </style></head><body>
    <svg xmlns="http://www.w3.org/2000/svg" width="{MASTER}" height="{MASTER}"
         viewBox="0 0 512 512" shape-rendering="geometricPrecision">
      <rect width="512" height="512" rx="{radius}" fill="{BG}"/>
      <g transform="translate({off},{off}) scale({scale})">{inner}</g>
    </svg></body></html>"""


def master(html):
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(html)
        src = f.name
    shot = os.path.join(tempfile.gettempdir(), "_icon_master.png")
    subprocess.run(
        [
            CHROME, "--headless", "--disable-gpu", "--no-sandbox",
            "--hide-scrollbars", "--force-device-scale-factor=1",
            "--default-background-color=00000000",
            f"--window-size={MASTER},{MASTER + 400}",
            f"--screenshot={shot}", f"file://{src}",
        ],
        check=True,
        capture_output=True,
    )
    os.unlink(src)
    # RGBA so the rounded icons have transparent corners rather than white
    # ones, which would show as a card on a dark home screen.
    img = Image.open(shot).convert("RGBA").crop((0, 0, MASTER, MASTER))
    os.unlink(shot)
    return img


# (path under web/, size, corner radius, share of the square the art fills, art)
TARGETS = [
    ("favicon.png", 16, 0, 1.0, ART_SIMPLE),
    ("icons/Icon-192.png", 192, 96, 0.9, ART),
    ("icons/Icon-512.png", 512, 96, 0.9, ART),
    # Maskable: full bleed, and the bottle kept inside the safe circle Android
    # crops to — 80% of the square, so the bottle's half-diagonal has to clear
    # 205 of the 512 artboard. At 0.85 it clears with room to spare.
    ("icons/Icon-maskable-192.png", 192, 0, 0.85, ART),
    ("icons/Icon-maskable-512.png", 512, 0, 0.85, ART),
]

if __name__ == "__main__":
    for name, size, radius, scale, inner in TARGETS:
        out = os.path.normpath(os.path.join(WEB, name))
        img = master(page(radius=radius, scale=scale, inner=inner))
        img.resize((size, size), Image.LANCZOS).save(out, optimize=True)
        print(f"{name}  {size}x{size}")
