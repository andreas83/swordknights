#!/usr/bin/env python3
"""Generate the game's typeface — atlas and metrics — from code.

There are no image assets in this project. The tile atlas comes from the
palette, the skyline from a seed, the character from polygons; the font follows
the same rule and is drawn here, pixel by pixel, at the sizes it is actually
used at.

    python3 tools/generate_font.py

Writes, for each optical size, a BMFont pair into assets/:

    font_alcazar_micro.png   + .fnt     cap 5 px
    font_alcazar_text.png    + .fnt     cap 7 px
    font_alcazar_display.png + .fnt     cap 14 px

Godot imports the .fnt as a FontFile with no further configuration; run
`godot --headless --path . --import` afterwards. scripts/ui/ui_font.gd is the
only thing in the game that names these files.

THE FACE — "Alcazar"
--------------------
A Latin unicase built on square-Kufic manners, invented rather than copied: no
real script is imitated, only the posture is borrowed.

  * Square counters. O, C, G, D are rectangles. At five pixels a curve is a
    lie, and the rectangle is also what the reference inscriptions do.
  * Terminal bars. C, E, S, Z, L, U close on a full-width horizontal. The
    long baseline bar is the loudest thing about the reference lettering.
  * Flat apexes. A, M, W, V have no points; the diagonals are steps. This is
    both a Kufic cue and the only way a diagonal survives at five pixels.
  * Barred I and footed 1. The alif-like stem with a bar top and bottom.
  * One-pixel strokes throughout the reading sizes; the display cut doubles
    them and stands each stem on a one-pixel spur, so the title reads as
    carved rather than as the small text enlarged.

Three optical cuts rather than one scaled face: at a 180-unit-tall viewport the
difference between cap 5 and cap 7 is the difference between a readable hint
and a smear, and neither is a scaled-down title.

WHAT IS IN IT
-------------
A-Z, 0-9, space, and the punctuation the game actually prints:
. , : ; - / ( ) ' " ! ? % + and the two typographic marks the UI leans on,
the middle dot and the em dash. Lowercase is mapped onto the capitals, so a
string that forgot its .to_upper() still renders. See docs/ui.md for how to add
a glyph.
"""
from __future__ import annotations

import pathlib

from PIL import Image

OUT_DIR = pathlib.Path(__file__).resolve().parent.parent / "assets"
FACE = "Alcazar"

# One pixel of sidebearing on the right of every glyph; tracking on top of that
# is the caller's business (scripts/ui/ui_font.gd).
SIDEBEARING = 1


# --------------------------------------------------------------------------
# The TEXT cut: cap height 7, one-pixel strokes. The master drawing — the
# micro cut is its own, tighter design, and the display cut is derived from
# this one.
# --------------------------------------------------------------------------
TEXT: dict[str, list[str]] = {
    # The bar sits one row above centre on A B E F G H P R: the long leg under
    # a high bar is the whole stance of the reference lettering, and it is what
    # stops this reading as a generic pixel grotesque.
    "A": [".###.", "#...#", "#####", "#...#", "#...#", "#...#", "#...#"],
    "B": ["####.", "#...#", "####.", "#...#", "#...#", "#...#", "####."],
    "C": ["#####", "#....", "#....", "#....", "#....", "#....", "#####"],
    "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "####.", "#....", "#....", "#....", "#####"],
    "F": ["#####", "#....", "####.", "#....", "#....", "#....", "#...."],
    "G": ["#####", "#....", "#.###", "#...#", "#...#", "#...#", "#####"],
    "H": ["#...#", "#...#", "#####", "#...#", "#...#", "#...#", "#...#"],
    "I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
    "J": ["..###", "....#", "....#", "....#", "....#", "#...#", ".####"],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
    "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
    "O": ["#####", "#...#", "#...#", "#...#", "#...#", "#...#", "#####"],
    "P": ["####.", "#...#", "####.", "#....", "#....", "#....", "#...."],
    "Q": ["#####", "#...#", "#...#", "#...#", "#...#", "#...#", "#####", "...#."],
    "R": ["####.", "#...#", "####.", "#.#..", "#..#.", "#...#", "#...#"],
    "S": ["#####", "#....", "#....", "#####", "....#", "....#", "#####"],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", "#####"],
    "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
    "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    "0": ["#####", "#...#", "#...#", "#.#.#", "#...#", "#...#", "#####"],
    "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", "#####"],
    "2": ["#####", "....#", "....#", "#####", "#....", "#....", "#####"],
    "3": ["#####", "....#", "....#", ".####", "....#", "....#", "#####"],
    "4": ["#...#", "#...#", "#...#", "#####", "....#", "....#", "....#"],
    "5": ["#####", "#....", "#....", "#####", "....#", "....#", "#####"],
    "6": ["#####", "#....", "#....", "#####", "#...#", "#...#", "#####"],
    "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
    "8": ["#####", "#...#", "#...#", "#####", "#...#", "#...#", "#####"],
    "9": ["#####", "#...#", "#...#", "#####", "....#", "....#", "#####"],
    ".": [".", ".", ".", ".", ".", ".", "#"],
    ",": ["..", "..", "..", "..", "..", ".#", ".#", "#."],
    ":": [".", ".", "#", ".", ".", "#", "."],
    ";": ["..", "..", ".#", "..", "..", ".#", ".#", "#."],
    "-": ["...", "...", "...", "###", "...", "...", "..."],
    "·": [".", ".", ".", "#", ".", ".", "."],
    "—": [".......", ".......", ".......", "#######", ".......", ".......", "......."],
    "/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
    "(": [".#", "#.", "#.", "#.", "#.", "#.", ".#"],
    ")": ["#.", ".#", ".#", ".#", ".#", ".#", "#."],
    "'": ["#", "#", ".", ".", ".", ".", "."],
    '"': ["#.#", "#.#", "...", "...", "...", "...", "..."],
    "!": ["#", "#", "#", "#", "#", ".", "#"],
    "?": ["#####", "....#", "....#", "..###", "..#..", ".....", "..#.."],
    "%": ["##..#", "##.#.", "...#.", "..#..", ".#...", ".#.##", "#..##"],
    "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
}

# --------------------------------------------------------------------------
# The MICRO cut: cap height 5. Not a reduction of the text cut — at five
# pixels every letter has to be square, so the whole alphabet is redrawn on a
# 5x5 body. Which, conveniently, is the most Kufic the face ever looks.
# --------------------------------------------------------------------------
MICRO: dict[str, list[str]] = {
    "A": [".###.", "#...#", "#####", "#...#", "#...#"],
    "B": ["####.", "#...#", "####.", "#...#", "####."],
    "C": ["#####", "#....", "#....", "#....", "#####"],
    "D": ["####.", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "####.", "#....", "#####"],
    "F": ["#####", "#....", "####.", "#....", "#...."],
    "G": ["#####", "#....", "#.###", "#...#", "#####"],
    "H": ["#...#", "#...#", "#####", "#...#", "#...#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"],
    "J": ["..###", "....#", "....#", "#...#", "####."],
    "K": ["#...#", "#..#.", "###..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
    "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#"],
    "O": ["#####", "#...#", "#...#", "#...#", "#####"],
    "P": ["####.", "#...#", "####.", "#....", "#...."],
    "Q": ["#####", "#...#", "#...#", "#...#", "#####", "...#."],
    "R": ["####.", "#...#", "####.", "#..#.", "#...#"],
    "S": ["#####", "#....", "#####", "....#", "#####"],
    "T": ["#####", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", "#####"],
    "V": ["#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
    "X": ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
    "Y": ["#...#", ".#.#.", "..#..", "..#..", "..#.."],
    "Z": ["#####", "...#.", "..#..", ".#...", "#####"],
    "0": ["#####", "#...#", "#.#.#", "#...#", "#####"],
    "1": ["..#..", ".##..", "..#..", "..#..", "#####"],
    "2": ["#####", "....#", "#####", "#....", "#####"],
    "3": ["#####", "....#", ".####", "....#", "#####"],
    "4": ["#...#", "#...#", "#####", "....#", "....#"],
    "5": ["#####", "#....", "#####", "....#", "#####"],
    "6": ["#####", "#....", "#####", "#...#", "#####"],
    "7": ["#####", "....#", "...#.", "..#..", "..#.."],
    "8": ["#####", "#...#", "#####", "#...#", "#####"],
    "9": ["#####", "#...#", "#####", "....#", "#####"],
    ".": [".", ".", ".", ".", "#"],
    ",": ["..", "..", "..", ".#", ".#", "#."],
    ":": [".", "#", ".", "#", "."],
    ";": ["..", ".#", "..", ".#", ".#", "#."],
    "-": ["...", "...", "###", "...", "..."],
    "·": [".", ".", "#", ".", "."],
    "—": [".....", ".....", "#####", ".....", "....."],
    "/": ["....#", "...#.", "..#..", ".#...", "#...."],
    "(": [".#", "#.", "#.", "#.", ".#"],
    ")": ["#.", ".#", ".#", ".#", "#."],
    "'": ["#", "#", ".", ".", "."],
    '"': ["#.#", "#.#", "...", "...", "..."],
    "!": ["#", "#", "#", ".", "#"],
    "?": ["#####", "....#", "..###", ".....", "..#.."],
    "%": ["##..#", "##.#.", "..#..", ".#.##", "#..##"],
    "+": [".....", "..#..", "#####", "..#..", "....."],
}
# Space is a width, not a drawing. (glyph, advance) in pixels.
SPACE_ADVANCE = {"micro": 4, "text": 4, "display": 7}


def parse(rows: list[str]) -> tuple[int, int, list[list[bool]]]:
    """A list of '#'/'.' rows into (width, height, grid)."""
    width = max(len(row) for row in rows)
    grid = [[c == "#" for c in row.ljust(width, ".")] for row in rows]
    return width, len(rows), grid


def upscale(grid: list[list[bool]], factor: int) -> list[list[bool]]:
    out: list[list[bool]] = []
    for row in grid:
        doubled = [cell for cell in row for _ in range(factor)]
        for _ in range(factor):
            out.append(list(doubled))
    return out


def spur(grid: list[list[bool]], baseline_row: int, max_run: int) -> list[list[bool]]:
    """Stand every stem that reaches the baseline on a one-pixel foot.

    The display cut is the text cut at double scale, which on its own is only
    the small face enlarged. The spurs are what make it a display cut: each
    vertical stroke gets a carved base, while anything wider than a stem — the
    terminal bars of C, E, L, S, Z, the bowl of D — stays flat, so the square
    skyline of the face survives at size.
    """
    width = len(grid[0])
    padded = [[False] + row + [False] for row in grid]
    bottom = grid[baseline_row]

    run_start: int | None = None
    for x in range(width + 1):
        filled = x < width and bottom[x]
        if filled and run_start is None:
            run_start = x
        elif not filled and run_start is not None:
            a, b = run_start, x - 1
            run_start = None
            if b - a + 1 > max_run:
                continue  # a bar, not a stem
            padded[baseline_row][a] = True
            padded[baseline_row][b + 2] = True
    return padded


def build_cut(name: str, maps: dict[str, list[str]], body: int, scale: int,
              spurs: bool) -> dict:
    """One optical size: rasterised glyphs plus the metrics the .fnt needs.

    `body` is the cap height of the source drawing; a glyph taller than that
    descends below the baseline by the difference.
    """
    out: dict[str, dict] = {}
    for char, rows in maps.items():
        width, height, grid = parse(rows)
        if height < body:
            raise ValueError("glyph %r is %d rows, shorter than the %d-row body"
                             % (char, height, body))
        descent = height - body
        if scale > 1:
            grid = upscale(grid, scale)
        baseline_row = (body - 1) * scale
        offset_x = 0
        if spurs:
            # Letters and digits only: a comma standing on two little feet is
            # a blob, not an inscription. Punctuation still gets the padding,
            # so every glyph in the cut sits on the same sidebearing.
            if char.isalnum():
                grid = spur(grid, baseline_row, max_run=2 * scale)
            else:
                grid = [[False] + row + [False] for row in grid]
            offset_x = -1
        out[char] = {
            "grid": grid,
            "w": len(grid[0]),
            "h": len(grid),
            "xoffset": offset_x,
            # The pen step is measured on the drawing, not on the padding the
            # spurs live in, or every display glyph would gain two pixels.
            "advance": width * scale + SIDEBEARING + (1 if spurs else 0),
            "descent": descent * scale,
        }

    return {
        "name": name,
        "cap": body * scale,
        "glyphs": out,
        "space": SPACE_ADVANCE[name],
    }


def pack(cut: dict) -> tuple[Image.Image, dict[str, tuple[int, int]]]:
    """Shelf-pack the glyphs into the smallest square power-of-two atlas."""
    items = sorted(cut["glyphs"].items(), key=lambda kv: -kv[1]["h"])
    for side in (32, 64, 128, 256, 512):
        placed: dict[str, tuple[int, int]] = {}
        x = y = shelf = 0
        ok = True
        for char, glyph in items:
            if x + glyph["w"] + 1 > side:
                x = 0
                y += shelf + 1
                shelf = 0
            if y + glyph["h"] + 1 > side:
                ok = False
                break
            placed[char] = (x, y)
            x += glyph["w"] + 1
            shelf = max(shelf, glyph["h"])
        if ok:
            image = Image.new("RGBA", (side, side), (255, 255, 255, 0))
            pixels = image.load()
            for char, (gx, gy) in placed.items():
                grid = cut["glyphs"][char]["grid"]
                for row_index, row in enumerate(grid):
                    for col_index, ink in enumerate(row):
                        if ink:
                            pixels[gx + col_index, gy + row_index] = (255, 255, 255, 255)
            return image, placed
    raise RuntimeError("glyphs do not fit in a 512x512 atlas")


def write_fnt(cut: dict, placed: dict[str, tuple[int, int]], side: int,
              page: str, path: pathlib.Path) -> None:
    """BMFont, text flavour. Godot's importer turns this into a FontFile."""
    cap = cut["cap"]
    # One pixel of internal leading above the caps, the deepest descender
    # below, and one pixel of leading under that.
    deepest = max(glyph["descent"] for glyph in cut["glyphs"].values())
    base = cap + 1
    line_height = base + deepest + 1

    lines = [
        'info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 '
        "stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0"
        % (FACE, cap),
        # alphaChnl=0 says the glyph lives in the alpha channel; the colour
        # channels are declared as "one" (4) and are white everywhere. Get
        # this wrong and Godot builds every glyph out of the colour channels,
        # which renders the whole cell solid — every letter a filled block.
        "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 "
        "alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4" % (line_height, base, side, side),
        'page id=0 file="%s"' % page,
    ]

    entries: list[str] = []

    def emit(code: int, char: str) -> None:
        glyph = cut["glyphs"][char]
        gx, gy = placed[char]
        entries.append(
            "char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d "
            "xadvance=%d page=0 chnl=15"
            % (
                code, gx, gy, glyph["w"], glyph["h"], glyph["xoffset"],
                base - cap, glyph["advance"],
            )
        )

    for char in sorted(cut["glyphs"], key=ord):
        emit(ord(char), char)
        # Unicase: a string that forgot its .to_upper() still reads.
        if "A" <= char <= "Z":
            emit(ord(char.lower()), char)

    entries.append(
        "char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 "
        "xadvance=%d page=0 chnl=15" % cut["space"]
    )

    lines.append("chars count=%d" % len(entries))
    lines.extend(entries)
    lines.append("kernings count=0")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def build() -> list[dict]:
    cuts = [
        build_cut("micro", MICRO, body=5, scale=1, spurs=False),
        build_cut("text", TEXT, body=7, scale=1, spurs=False),
        build_cut("display", TEXT, body=7, scale=2, spurs=True),
    ]
    report = []
    for cut in cuts:
        image, placed = pack(cut)
        stem = "font_alcazar_%s" % cut["name"]
        png = OUT_DIR / (stem + ".png")
        image.save(png)
        write_fnt(cut, placed, image.size[0], stem + ".png", OUT_DIR / (stem + ".fnt"))
        report.append({
            "name": cut["name"], "cap": cut["cap"],
            "glyphs": len(cut["glyphs"]), "atlas": image.size[0],
        })
    return report


if __name__ == "__main__":
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for line in build():
        print("%-8s cap %2d px, %d glyphs, %dx%d atlas"
              % (line["name"], line["cap"], line["glyphs"], line["atlas"], line["atlas"]))
