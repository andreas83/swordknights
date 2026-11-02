#!/usr/bin/env python3
"""Generate the tile atlas from the palette.

There are no hand-drawn assets in this project: the terrain atlas is produced
from the same duotone ramp the rest of the game uses, so re-lighting the world
(night, interior, storm) is a palette edit plus a re-run of this script rather
than an art pass.

    python3 tools/generate_tiles_png.py

Writes assets/tiles.png. Run tools/build_tileset.gd afterwards to rebuild the
TileSet resource that references it.
"""
from __future__ import annotations

import pathlib
from PIL import Image, ImageDraw

TILE = 16
COLUMNS = 8
ROWS = 2

INK = (0x2B, 0x0A, 0x14, 255)
SHADOW_DEEP = (0x7A, 0x12, 0x30, 255)
SHADOW = (0xB3, 0x21, 0x42, 255)
LIGHT_WARM = (0xF2, 0xA8, 0x29, 255)
LIGHT = (0xF7, 0xCE, 0x2E, 255)
WATER = (0x46, 0xC7, 0xB0, 255)
WATER_DEEP = (0x1F, 0x8F, 0x86, 255)
STEEL = (0x8C, 0x8F, 0xA3, 255)
STEEL_DARK = (0x5A, 0x5D, 0x70, 255)
CLEAR = (0, 0, 0, 0)

# Overlay tints, applied with `over()`. PIL's `fill` REPLACES a pixel including
# its alpha rather than compositing, so painting a translucent colour straight
# onto the atlas would punch a hole in the tile and let the sky show through.
JOINT_TINT = (0x2B, 0x0A, 0x14, 56)
LEFT_LIGHT_TINT = (0xF2, 0xA8, 0x29, 82)


def over(tint: tuple[int, int, int, int], base: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    """Composite a translucent tint onto an opaque base, returning opaque RGBA."""
    a = tint[3] / 255.0
    return (
        round(tint[0] * a + base[0] * (1 - a)),
        round(tint[1] * a + base[1] * (1 - a)),
        round(tint[2] * a + base[2] * (1 - a)),
        255,
    )

CAP_HEIGHT = 4
BEVEL_HEIGHT = 2

# Atlas layout. Keep in sync with scripts/world/tiles.gd.
NAMES = [
    "solid_capped", "solid_capped_lit", "solid_buried", "solid_buried_lit",
    "platform", "spikes", "water", "ladder",
    "backdrop",
]


def cell(draw: ImageDraw.ImageDraw, index: int) -> tuple[int, int]:
    return (index % COLUMNS) * TILE, (index // COLUMNS) * TILE


def masonry(draw: ImageDraw.ImageDraw, ox: int, oy: int, offset: int, body) -> None:
    """One horizontal joint and one vertical joint reads as stone without noise."""
    joint = over(JOINT_TINT, body)
    joint_y = oy + TILE - 5
    draw.rectangle([ox, joint_y, ox + TILE - 1, joint_y], fill=joint)
    jx = ox + offset
    draw.rectangle([jx, joint_y, jx, oy + TILE - 1], fill=joint)


def solid(draw: ImageDraw.ImageDraw, ox: int, oy: int, capped: bool, lit_left: bool) -> None:
    body = SHADOW if capped else SHADOW_DEEP
    draw.rectangle([ox, oy, ox + TILE - 1, oy + TILE - 1], fill=body)
    if capped:
        draw.rectangle([ox, oy, ox + TILE - 1, oy + CAP_HEIGHT - 1], fill=LIGHT)
        draw.rectangle(
            [ox, oy + CAP_HEIGHT, ox + TILE - 1, oy + CAP_HEIGHT + BEVEL_HEIGHT - 2],
            fill=LIGHT_WARM,
        )
    masonry(draw, ox, oy, TILE // 2 if capped else TILE // 4, body)
    if lit_left:
        top = oy + (CAP_HEIGHT if capped else 0)
        draw.rectangle([ox, top, ox, oy + TILE - 1], fill=over(LEFT_LIGHT_TINT, body))


def platform(draw: ImageDraw.ImageDraw, ox: int, oy: int) -> None:
    draw.rectangle([ox, oy, ox + TILE - 1, oy + CAP_HEIGHT - 1], fill=LIGHT)
    draw.rectangle(
        [ox, oy + CAP_HEIGHT, ox + TILE - 1, oy + CAP_HEIGHT], fill=LIGHT_WARM
    )


def spikes(draw: ImageDraw.ImageDraw, ox: int, oy: int) -> None:
    base = oy + TILE - 1
    draw.rectangle([ox, base - 2, ox + TILE - 1, base], fill=SHADOW_DEEP)
    count = 4
    step = TILE // count
    for i in range(count):
        sx = ox + i * step
        tip_y = base - int(TILE * 0.72)
        draw.polygon(
            [(sx + step / 2, tip_y), (sx + step - 1, base - 2), (sx, base - 2)],
            fill=STEEL,
        )
        draw.polygon(
            [(sx + step / 2, tip_y), (sx + step / 2, base - 2), (sx, base - 2)],
            fill=STEEL_DARK,
        )


def water(draw: ImageDraw.ImageDraw, ox: int, oy: int) -> None:
    draw.rectangle([ox, oy + 2, ox + TILE - 1, oy + TILE - 1], fill=WATER_DEEP)
    draw.rectangle([ox, oy + 2, ox + TILE - 1, oy + 3], fill=WATER)


def ladder(draw: ImageDraw.ImageDraw, ox: int, oy: int) -> None:
    draw.rectangle([ox + 3, oy, ox + 4, oy + TILE - 1], fill=SHADOW_DEEP)
    draw.rectangle([ox + TILE - 5, oy, ox + TILE - 4, oy + TILE - 1], fill=SHADOW_DEEP)
    for i in range(3):
        y = oy + 2 + i * 5
        draw.rectangle([ox + 3, y, ox + TILE - 4, y + 1], fill=LIGHT_WARM)


def backdrop(draw: ImageDraw.ImageDraw, ox: int, oy: int) -> None:
    """A recessed arch niche: the Moorish motif that reads even at 16 px."""
    draw.rectangle([ox, oy, ox + TILE - 1, oy + TILE - 1], fill=SHADOW_DEEP)
    left, right = ox + 3, ox + TILE - 4
    radius = (right - left) / 2
    draw.rectangle([left, oy + 4 + radius, right, oy + TILE - 1], fill=INK)
    draw.pieslice([left, oy + 4, right, oy + 4 + 2 * radius], 180, 360, fill=INK)


def main() -> None:
    image = Image.new("RGBA", (COLUMNS * TILE, ROWS * TILE), CLEAR)
    draw = ImageDraw.Draw(image)

    painters = {
        "solid_capped": lambda d, x, y: solid(d, x, y, True, False),
        "solid_capped_lit": lambda d, x, y: solid(d, x, y, True, True),
        "solid_buried": lambda d, x, y: solid(d, x, y, False, False),
        "solid_buried_lit": lambda d, x, y: solid(d, x, y, False, True),
        "platform": platform,
        "spikes": spikes,
        "water": water,
        "ladder": ladder,
        "backdrop": backdrop,
    }

    for index, name in enumerate(NAMES):
        ox, oy = cell(draw, index)
        painters[name](draw, ox, oy)

    out = pathlib.Path(__file__).resolve().parent.parent / "assets" / "tiles.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    print(f"wrote {out} ({image.width}x{image.height}, {len(NAMES)} tiles)")


if __name__ == "__main__":
    main()
