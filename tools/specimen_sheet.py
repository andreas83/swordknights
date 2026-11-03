#!/usr/bin/env python3
"""Assemble docs/typography.png: the face, at size and magnified, and the
screens it changed.

    python3 tools/specimen_sheet.py docs/typography.png \\
        before=/tmp/ui/before after=/tmp/ui/after wide=/tmp/ui/wide

The frame directories come from tests/ui_screens.gd. Every screen is shown at
1:1 — a 1280x720 shot is a four-times magnification of a 320x180 canvas, and
judging type on the magnified version is judging a different typeface.

The face itself is drawn straight from tools/generate_font.py's glyph tables
rather than from the atlas, so the sheet cannot drift away from the font.
"""
from __future__ import annotations

import importlib.util
import pathlib
import sys

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
CANVAS_H = 180

INK = (0x2B, 0x0A, 0x14, 255)
SHADOW_DEEP = (0x7A, 0x12, 0x30, 255)
PAPER = (0xFF, 0xF4, 0xC2, 255)
LIGHT = (0xF7, 0xCE, 0x2E, 255)
LIGHT_SOFT = (0xFF, 0xE8, 0x73, 255)
DIM = (0xE8, 0x70, 0x2A, 255)

SHEET_W = 1180
PAD = 18


def load_generator():
    spec = importlib.util.spec_from_file_location(
        "generate_font", HERE / "generate_font.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Pen:
    """Draws the face from the generator's own glyph tables."""

    def __init__(self, cuts: dict):
        self.cuts = cuts

    def width(self, cut: str, text: str, tracking: float) -> int:
        table = self.cuts[cut]
        total = 0.0
        # The shipped face maps lowercase onto the capitals in the .fnt; the
        # glyph tables only hold the capitals, so do the same here.
        for char in text.upper():
            glyph = table["glyphs"].get(char)
            total += (table["space"] if glyph is None else glyph["advance"]) + tracking
        return int(max(0.0, total - tracking))

    def draw(self, image, cut: str, text: str, x: int, y: int,
             colour=PAPER, tracking: float = 1.0, scale: int = 1) -> int:
        """`y` is the cap line. Returns the pen position after the string."""
        table = self.cuts[cut]
        pixels = image.load()
        pen = float(x)
        for char in text.upper():
            glyph = table["glyphs"].get(char)
            if glyph is None:
                pen += table["space"] + tracking
                continue
            for row_index, row in enumerate(glyph["grid"]):
                for col_index, ink in enumerate(row):
                    if not ink:
                        continue
                    px = int(pen) + (col_index + glyph["xoffset"]) * scale
                    py = y + row_index * scale
                    for dy in range(scale):
                        for dx in range(scale):
                            tx, ty = px + dx, py + dy
                            if 0 <= tx < image.size[0] and 0 <= ty < image.size[1]:
                                pixels[tx, ty] = colour
            pen += glyph["advance"] * scale + tracking * scale
        return int(pen)


def heading(pen: Pen, image, text: str, y: int, note: str = "") -> int:
    pen.draw(image, "text", text, PAD, y, PAPER, 1.0, 2)
    if note:
        pen.draw(image, "micro", note,
                 PAD + pen.width("text", text, 1.0) * 2 + 16, y + 9, DIM, 1.0, 1)
    return y + 24


def rule(image, x: int, y: int, w: int, colour=(0x7A, 0x12, 0x30, 255)) -> None:
    pixels = image.load()
    for i in range(w):
        if 0 <= x + i < image.size[0] and 0 <= y < image.size[1]:
            pixels[x + i, y] = colour


def canvas_1to1(path: pathlib.Path) -> Image.Image:
    shot = Image.open(path).convert("RGBA")
    factor = max(1, shot.size[1] // CANVAS_H)
    return shot.resize(
        (shot.size[0] // factor, shot.size[1] // factor), Image.NEAREST
    )


def magnify(image: Image.Image, scale: int) -> Image.Image:
    return image.resize(
        (image.size[0] * scale, image.size[1] * scale), Image.NEAREST
    )


def specimen_block(pen: Pen, image, y: int) -> int:
    """The face: every cut at its real size, then one magnified."""
    x = PAD
    y = heading(pen, image, "ALCAZAR", y,
                "A LATIN UNICASE ON SQUARE-KUFIC MANNERS · BUILT BY TOOLS/GENERATE_FONT.PY")

    lines = [
        ("micro", "MICRO · CAP 5", [
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            "0123456789 .,:;-/()'\"!?%+ · —",
            "SEED 1294877 · 24 COLS 9 BEATS · DIFF 0.55",
        ]),
        ("text", "TEXT · CAP 7", [
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            "0123456789 .,:;-/()'\"!?%+ · —",
            "ADVENTURE · ENDLESS · DUEL · SOUND",
        ]),
        ("display", "DISPLAY · CAP 14", [
            "ABCDEFGHIJKLM",
            "NOPQRSTUVWXYZ",
            "SWORDKNIGHTS",
        ]),
    ]

    for cut, label, rows in lines:
        pen.draw(image, "micro", label, x, y, LIGHT, 1.0, 2)
        y += 16
        for row in rows:
            pen.draw(image, cut, row, x + 10, y, PAPER, 1.0, 1)
            y += pen.cuts[cut]["cap"] + 5
        y += 10

    # The same word at 1:1 and magnified, side by side. A bitmap face has to
    # be shown at the size it is set at or the sheet is about a different
    # typeface; the magnification is only there to show where the pixels went.
    pen.draw(image, "micro", "AT SIZE, AND MAGNIFIED", x, y, LIGHT, 1.0, 2)
    y += 18
    word = "SWORDKNIGHTS"
    for cut, scale in (("micro", 6), ("text", 5), ("display", 3)):
        cap = pen.cuts[cut]["cap"]
        pen.draw(image, cut, word, x + 10, y + (cap * scale - cap) // 2, PAPER, 1.0, 1)
        pen.draw(image, cut, word, x + 200, y, PAPER, 1.0, scale)
        y += cap * scale + 14
    return y + 6


def screens_block(pen: Pen, image, y: int, dirs: dict) -> int:
    shots = [
        ("menu", "TITLE SCREEN"),
        ("settings", "SETTINGS — NEW"),
        ("hud_hurt", "LEVEL HUD"),
        ("hud_pause", "PAUSE OVERLAY"),
        ("match_flash", "DUEL · INITIATIVE"),
        ("match_over", "DUEL · MATCH OVER"),
        ("menu_touch", "TOUCH CONTROLS"),
    ]
    columns = [name for name in ("before", "after", "wide") if name in dirs]

    x = PAD
    y = heading(pen, image, "SCREENS", y, "EVERY FRAME AT 1:1 · 320x180 CANVAS")

    header_x = x
    for column in columns:
        pen.draw(image, "micro", column.upper(), header_x, y, LIGHT, 1.0, 2)
        header_x += 330
    y += 16

    for name, label in shots:
        pen.draw(image, "micro", label, x, y, PAPER, 1.0, 2)
        y += 14
        cell_x = x
        tallest = 0
        for column in columns:
            path = dirs[column] / ("%s.png" % name)
            if not path.exists():
                pen.draw(image, "micro", "-", cell_x + 4, y + 10, DIM, 1.0, 1)
                cell_x += 330
                continue
            shot = canvas_1to1(path)
            image.paste(shot, (cell_x, y))
            tallest = max(tallest, shot.size[1])
            rule(image, cell_x, y + shot.size[1] + 1, shot.size[0])
            cell_x += 330
        y += tallest + 16
    return y


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(2)
    out = pathlib.Path(sys.argv[1])
    dirs: dict[str, pathlib.Path] = {}
    for argument in sys.argv[2:]:
        key, _, value = argument.partition("=")
        dirs[key] = pathlib.Path(value)

    generator = load_generator()
    cuts = {
        "micro": generator.build_cut("micro", generator.MICRO, body=5, scale=1,
                                     spurs=False),
        "text": generator.build_cut("text", generator.TEXT, body=7, scale=1,
                                    spurs=False),
        "display": generator.build_cut("display", generator.TEXT, body=7, scale=2,
                                       spurs=True),
    }
    pen = Pen(cuts)

    # Draw once onto a generous canvas, then crop to what was used.
    image = Image.new("RGBA", (SHEET_W, 4200), INK)
    y = PAD
    y = specimen_block(pen, image, y)
    rule(image, PAD, y, SHEET_W - PAD * 2, SHADOW_DEEP)
    y += 18
    y = screens_block(pen, image, y, dirs)

    image = image.crop((0, 0, SHEET_W, min(y + PAD, image.size[1])))
    out.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(out)
    print("wrote %s (%dx%d)" % (out, image.size[0], image.size[1]))


if __name__ == "__main__":
    main()
