#!/usr/bin/env python3
"""Set a line of text in the game's own typeface, as an SVG, for the site.

    python3 site/wordmark.py SWORDKNIGHTS > site/public/img/wordmark.svg

The page's title should be the title the game shows, not a web font standing in
for it. Alcazar exists only as a bitmap atlas (tools/generate_font.py draws it),
so this reads the DISPLAY cut's BMFont pair straight out of assets/ and emits
one path segment per horizontal run of lit pixels. An SVG rather than a PNG
because the header scales fluidly with the viewport: rectangles stay
hard-edged at any size, where a bitmap is only crisp at integer multiples.

The drop shadow is the one the title screen draws: the same glyphs, one pixel
down and to the right, in deep shadow.

Reads the font, writes nothing but standard output. Needs Pillow.
"""

import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FNT = ROOT / "assets" / "font_alcazar_display.fnt"
ATLAS = ROOT / "assets" / "font_alcazar_display.png"

# scripts/core/palette.gd: PAPER for the face, SHADOW_DEEP for its shadow.
FACE = "#fff4c2"
SHADOW = "#7a1230"


def load_glyphs() -> tuple[dict[int, dict[str, int]], int]:
    glyphs: dict[int, dict[str, int]] = {}
    line_height = 0
    for line in FNT.read_text().splitlines():
        fields = dict(re.findall(r"(\w+)=(-?\d+)", line))
        if line.startswith("common "):
            line_height = int(fields["lineHeight"])
        elif line.startswith("char "):
            glyphs[int(fields["id"])] = {k: int(v) for k, v in fields.items()}
    return glyphs, line_height


def lit_pixels(text: str) -> tuple[set[tuple[int, int]], int, int]:
    glyphs, line_height = load_glyphs()
    atlas = Image.open(ATLAS).convert("RGBA")
    pixels: set[tuple[int, int]] = set()
    pen = 0
    for ch in text.upper():
        g = glyphs.get(ord(ch))
        if g is None:
            sys.exit(f"wordmark: no glyph for {ch!r} in {FNT.name}")
        for y in range(g["height"]):
            for x in range(g["width"]):
                r, _g, _b, a = atlas.getpixel((g["x"] + x, g["y"] + y))
                if a > 127 and r > 127:
                    pixels.add((pen + g["xoffset"] + x, g["yoffset"] + y))
        pen += g["xadvance"]
    xs = [p[0] for p in pixels]
    ys = [p[1] for p in pixels]
    # Normalise to the ink box, so the SVG has no dead margin to fight in CSS.
    left, top = min(xs), min(ys)
    pixels = {(x - left, y - top) for x, y in pixels}
    return pixels, max(xs) - left + 1, max(ys) - top + 1


def runs(pixels: set[tuple[int, int]], dx: int, dy: int) -> list[str]:
    out: list[str] = []
    for y in sorted({p[1] for p in pixels}):
        row = sorted(x for x, yy in pixels if yy == y)
        start = prev = row[0]
        for x in row[1:] + [None]:
            if x is not None and x == prev + 1:
                prev = x
                continue
            out.append(f"M{start + dx} {y + dy}h{prev - start + 1}v1h-{prev - start + 1}z")
            if x is not None:
                start = prev = x
    return out


def main() -> None:
    text = " ".join(sys.argv[1:]) or "SWORDKNIGHTS"
    pixels, width, height = lit_pixels(text)
    w, h = width + 1, height + 1  # room for the shadow
    print(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
        f'width="{w}" height="{h}" shape-rendering="crispEdges">'
    )
    print(f"<title>{text.title()}</title>")
    print(f'<path fill="{SHADOW}" d="' + "".join(runs(pixels, 1, 1)) + '"/>')
    print(f'<path fill="{FACE}" d="' + "".join(runs(pixels, 0, 0)) + '"/>')
    print("</svg>")


if __name__ == "__main__":
    main()
