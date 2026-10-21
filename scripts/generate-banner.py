#!/usr/bin/env python3
"""Generate StoreScreens' capture-only banner and social image.

Requires fonttools with WOFF support and cairosvg. The original app icon is
embedded unchanged; bundled IBM Plex Sans text becomes SVG outlines so GitHub
does not depend on installed fonts.
"""
from html import escape
from pathlib import Path
import base64
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
    weight: TTFont(ASSETS / "fonts" / f"IBMPlexSans-{weight}.woff2")
    for weight in ["Regular", "SemiBold"]
}
INK, MUTED, PAPER = "#162335", "#4f5f74", "#f8fafc"
TAGLINE = "XCUITest screenshot orchestration."
SUPPORTING_LINE = "Automate simulators and screenshot collection via MCP/CLI/Skill."
LOGO = base64.b64encode((ASSETS / "logo.png").read_bytes()).decode("ascii")


def text(value, x, y, size, weight="Regular", color=INK, max_width=None):
    font = FONTS[weight]
    glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    pen, advance = SVGPathPen(glyphs), 0
    for char in value:
        name = cmap.get(ord(char))
        if name is None:
            raise ValueError(f"Font does not contain {char!r}")
        glyphs[name].draw(TransformPen(pen, (1, 0, 0, 1, advance, 0)))
        advance += font["hmtx"].metrics[name][0]
    if max_width is not None and advance * scale > max_width:
        raise ValueError(f"Banner text exceeds its column: {value!r}")
    return f'<path aria-label="{escape(value, quote=True)}" fill="{color}" transform="translate({x} {y}) scale({scale} {-scale})" d="{pen.getCommands()}"/>'


def render(height):
    social = height == 640
    logo_size = 336 if social else 280
    logo_x = 52
    logo_y = (height - logo_size) / 2
    text_x = logo_x + logo_size + 56
    width = 1280 - text_x - 52
    middle = height / 2
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1280" height="{height}" viewBox="0 0 1280 {height}">',
        '<title>StoreScreens — XCUITest Screenshot Orchestration</title>',
        f'<desc>The StoreScreens app icon beside its name. {escape(SUPPORTING_LINE)}</desc>',
        f'<rect width="1280" height="{height}" fill="{PAPER}"/>',
        f'<image x="{logo_x}" y="{logo_y}" width="{logo_size}" height="{logo_size}" preserveAspectRatio="xMidYMid meet" xlink:href="data:image/png;base64,{LOGO}"/>',
        text("StoreScreens", text_x, middle - 40, 84, "SemiBold", max_width=width),
        text(TAGLINE, text_x + 2, middle + 27, 35, max_width=width - 2),
        text(SUPPORTING_LINE, text_x + 2, middle + 77, 23, color=MUTED, max_width=width - 2),
        '</svg>',
    ]
    return ''.join(parts).encode()


banner = render(420)
(ASSETS / "banner.svg").write_bytes(banner)
cairosvg.svg2png(bytestring=banner, write_to=str(ASSETS / "banner.png"), scale=2)
cairosvg.svg2png(bytestring=render(640), write_to=str(ASSETS / "social.png"))
print("Generated assets/banner.svg, assets/banner.png, and assets/social.png")
