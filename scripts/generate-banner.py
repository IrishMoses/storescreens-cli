#!/usr/bin/env python3
"""Generate StoreScreens' capture-only banner and social image.

Requires fonttools and cairosvg. Bundled Barlow Condensed fonts are OFL licensed;
text becomes SVG outlines so GitHub does not depend on installed fonts.
"""
from html import escape
from pathlib import Path
import os
import sys

# macOS does not include package-manager library directories in dyld's defaults.
if sys.platform == "darwin" and "DYLD_FALLBACK_LIBRARY_PATH" not in os.environ:
    for prefix in ["/opt/homebrew/lib", "/usr/local/lib"]:
        if (Path(prefix) / "libcairo.2.dylib").exists():
            environment = dict(os.environ, DYLD_FALLBACK_LIBRARY_PATH=prefix)
            os.execve(sys.executable, [sys.executable, *sys.argv], environment)

import cairosvg
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
FONTS = {
    weight: TTFont(ASSETS / "fonts" / f"BarlowCondensed-{weight}.ttf")
    for weight in ["Regular", "SemiBold"]
}
INK, MUTED, ACCENT, LINE, PAPER = "#202823", "#56645a", "#b44c2d", "#b9c2b6", "#f0f0e6"


def text(value, x, y, size, weight="Regular", color=INK, tracking=0):
    font = FONTS[weight]
    glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    pen, advance = SVGPathPen(glyphs), 0
    for char in value:
        name = cmap.get(ord(char))
        if name is None:
            raise ValueError(f"Font does not contain {char!r}")
        glyphs[name].draw(TransformPen(pen, (1, 0, 0, 1, advance, 0)))
        advance += font["hmtx"].metrics[name][0] + tracking / scale
    return f'<path aria-label="{escape(value, quote=True)}" fill="{color}" transform="translate({x} {y}) scale({scale} {-scale})" d="{pen.getCommands()}"/>'


def screen(x, y, number, active=False):
    stroke = ACCENT if active else MUTED
    rows = [f'<rect x="{x+16}" y="{y+offset}" width="{width}" height="5" fill="{stroke}" opacity="{opacity}"/>'
            for offset, width, opacity in [(43, 43, .8), (63, 60, .3), (75, 47, .3), (124, 60, .3), (136, 39, .3)]]
    return ''.join([
        f'<rect x="{x}" y="{y}" width="96" height="180" rx="10" fill="{PAPER}" stroke="{stroke}" stroke-width="2"/>',
        f'<path d="M{x+36} {y+13}h24" stroke="{stroke}" stroke-width="3"/>',
        *rows,
        f'<rect x="{x+16}" y="{y+91}" width="60" height="20" fill="{stroke}" opacity=".12"/>',
        text(number, x+16, y+168, 16, color=stroke),
    ])


def render(height):
    social = height == 640
    shift = 72 if social else 0
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="{height}" viewBox="0 0 1280 {height}">',
             '<title>StoreScreens — XCUITest Screenshot Orchestration</title>',
             '<desc>Set up simulators. Run UI tests. Collect screenshots.</desc>',
             f'<rect width="1280" height="{height}" fill="{PAPER}"/>',
             f'<path d="M72 {58+shift}h42" stroke="{ACCENT}" stroke-width="3"/>',
             text("CAPTURE / XCUITEST", 126, 64+shift, 18, "SemiBold", ACCENT, 1.5),
             text("StoreScreens", 68, 202+shift, 125, "SemiBold", tracking=-1),
             text("XCUITest Screenshot Orchestration", 72, 267+shift, 42, "SemiBold"),
             text("Set up simulators. Run UI tests. Collect screenshots.", 72, 316+shift, 28, color=MUTED),
             screen(916, 128+shift, "01"), screen(978, 160+shift, "02"), screen(1040, 192+shift, "03", True),
             f'<path d="M72 {386+shift}H1208" stroke="{LINE}"/>',
             text("storescreens.app", 72, 424+shift, 22, "SemiBold"),
             text("SIMULATORS  /  UI TESTS  /  RAW PNGs", 918, 424+shift, 18, color=MUTED),
             '</svg>']
    return ''.join(parts).encode()


banner = render(480)
(ASSETS / "banner.svg").write_bytes(banner)
cairosvg.svg2png(bytestring=banner, write_to=str(ASSETS / "banner.png"), scale=2)
cairosvg.svg2png(bytestring=render(640), write_to=str(ASSETS / "social.png"))
print("Generated assets/banner.svg, assets/banner.png, and assets/social.png")
