#!/usr/bin/env python3
"""Generate the app icon -- every size of it -- from the palette.

    python3 tools/generate_icon.py
    godot --headless --path . --import

Writes:

    icon.svg                                   project icon, web favicon, site
    assets/icon/icon_192.png                   Android legacy launcher icon
    assets/icon/adaptive_background_432.png    Android adaptive, back layer
    assets/icon/adaptive_foreground_432.png    Android adaptive, front layer
    assets/icon/adaptive_monochrome_432.png    Android 13 themed icon
    site/public/img/apple-touch-icon.png       iOS ignores an SVG favicon

WHAT IT IS.
The whole of docs/art-direction.md in one frame: a horseshoe arch, the low sun
sitting on the horizon inside it, and the prince standing against the sun with
his sword up, throwing a long shadow down the floor towards you. Backlit, he is
a silhouette, and a silhouette against gold is the strongest two-tone read the
palette has -- which is the only thing that survives at 48 px on a phone's home
screen. The steel is the one cold colour in the frame, so the blade is what the
eye lands on second.

HOW IT IS DRAWN.
Like the tile atlas: no image editor, no anti-aliasing, hard edges only. The
picture is a stack of shapes described in unit coordinates (0..1 across the
icon), and each output is RASTERISED AT ITS OWN PIXEL GRID by point-sampling
the pixel centres, then scaled up by an integer with nearest filtering. So the
48 px favicon is drawn at 48 pixels, not shrunk from 432 and smeared -- the
same reason the game's typeface has three cuts instead of one scaled face
(docs/ui.md). Thin parts (the blade, the arch's lit rim) carry a minimum width
in grid pixels so that no grid can lose them between two sample points.

THE ADAPTIVE ICON is two layers on purpose. The sky and the sun are the back
layer; the arch, the floor, the figure and his shadow are the front. A launcher
that parallaxes the layers slides the sun behind the arch, which is the one
piece of motion this icon is allowed. Everything that must be seen sits inside
the 66/108 safe circle the launcher mask is guaranteed to leave alone.
"""
from __future__ import annotations

import math
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent

# --- the palette ----------------------------------------------------------
# Mirrors scripts/core/palette.gd.

INK = (0x2B, 0x0A, 0x14, 255)
SHADOW_DEEP = (0x7A, 0x12, 0x30, 255)
SHADOW = (0xB3, 0x21, 0x42, 255)
SHADOW_WARM = (0xD8, 0x45, 0x2C, 255)
MID = (0xE8, 0x70, 0x2A, 255)
LIGHT_WARM = (0xF2, 0xA8, 0x29, 255)
LIGHT = (0xF7, 0xCE, 0x2E, 255)
LIGHT_SOFT = (0xFF, 0xE8, 0x73, 255)
PAPER = (0xFF, 0xF4, 0xC2, 255)
STEEL = (0x8C, 0x8F, 0xA3, 255)
CLEAR = (0, 0, 0, 0)
## The darkest a surface may go -- tools/generate_tiles_png.py's SHADOW_PIT.
SHADOW_PIT = (0x4A, 0x0D, 0x1E, 255)

# --- the composition, in unit coordinates ---------------------------------

HORIZON = 0.74          # where the floor meets the sky, and the figure's feet
ARCH_CX = 0.5
ARCH_CY = 0.40          # centre of the horseshoe's circle
ARCH_R = 0.30
ARCH_SPRING = 0.47      # below this the jambs run straight
ARCH_JAMB = math.sqrt(ARCH_R ** 2 - (ARCH_SPRING - ARCH_CY) ** 2)
ARCH_RING = 0.045       # the moulding round the opening

SUN_C = (0.53, 0.555)
SUN_R = 0.20

# The sky inside the arch, top to bottom: hard bands, the same stops as
# Palette.SKY_STOPS. A gradient would be the one soft thing in the picture.
SKY_BANDS = ((0.30, SHADOW), (0.44, SHADOW_WARM), (0.58, MID), (1.0, LIGHT_WARM))

# The sun -- from the left, two across for one down -- as tools/
# generate_tiles_png.py uses it to pick a moulding's tone from its normal.
SUN_TO_SURFACE = (2.0, 1.0)


def in_poly(x: float, y: float, pts: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y):
            if x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                inside = not inside
        j = i
    return inside


def in_disc(x: float, y: float, c: tuple[float, float], r: float) -> bool:
    return (x - c[0]) ** 2 + (y - c[1]) ** 2 <= r * r


def near_segment(x: float, y: float, a: tuple[float, float], b: tuple[float, float],
                 half: float) -> bool:
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    px, py = ax + dx * t, ay + dy * t
    return (x - px) ** 2 + (y - py) ** 2 <= half * half


def arch_void(x: float, y: float, grow: float = 0.0) -> bool:
    """The opening. `grow` widens it, which is how the ring is measured."""
    if y > HORIZON + 0.5:
        return False
    if y <= ARCH_SPRING:
        return in_disc(x, y, (ARCH_CX, ARCH_CY), ARCH_R + grow)
    return abs(x - ARCH_CX) <= ARCH_JAMB + grow


def ring_tone(x: float, y: float):
    """The moulding's tone from the way it faces, exactly as the in-game arch
    picks it: the left of the ring catches the sun, the right is lost."""
    if y <= ARCH_SPRING:
        nx, ny = x - ARCH_CX, y - ARCH_CY
    else:
        nx, ny = (1.0 if x > ARCH_CX else -1.0), 0.0
    length = math.hypot(nx, ny) or 1.0
    d = -(nx * SUN_TO_SURFACE[0] + ny * SUN_TO_SURFACE[1]) / (length * math.sqrt(5.0))
    if d > 0.55:
        return LIGHT
    if d > 0.15:
        return LIGHT_WARM
    if d > -0.25:
        return SHADOW
    return INK


# --- the figure ------------------------------------------------------------
# Facing right, feet on the horizon, his head inside the sun's disc -- a head
# against gold is the one place a hood reads as a hood at 48 px. The raised
# sword crosses the right half of the sun and the arch's ring, so the blade is
# cut out against three different tones along its length.

FIG_X = 0.47
FEET = HORIZON
HEM = FEET - 0.035
SHOULDER = (FIG_X + 0.02, 0.485)
HAND = (FIG_X + 0.105, 0.405)
TIP = (FIG_X + 0.265, 0.135)
HOOD_C = (FIG_X + 0.004, 0.432)


def robe(x: float, y: float) -> bool:
    return in_poly(x, y, [
        (FIG_X - 0.034, 0.468), (FIG_X + 0.040, 0.468),
        (FIG_X + 0.070, HEM), (FIG_X - 0.058, HEM),
    ])


def legs(x: float, y: float) -> bool:
    """Two feet planted under the hem, wide: the stance is what turns a cone
    of cloth into somebody standing."""
    return (near_segment(x, y, (FIG_X - 0.030, HEM - 0.01), (FIG_X - 0.050, FEET), 0.017)
            or near_segment(x, y, (FIG_X + 0.035, HEM - 0.01), (FIG_X + 0.062, FEET), 0.017))


def cloak(x: float, y: float) -> bool:
    """Down his back from the shoulders and flaring out behind at the hem, the
    way the in-game cloak trails a run: the widest thing on him, and what
    makes the shape a figure rather than a cone."""
    return in_poly(x, y, [
        (FIG_X - 0.025, 0.462), (FIG_X - 0.060, 0.55), (FIG_X - 0.120, 0.635),
        (FIG_X - 0.185, 0.690), (FIG_X - 0.120, 0.690), (FIG_X - 0.150, 0.712),
        (FIG_X - 0.060, HEM), (FIG_X - 0.010, 0.55),
    ])


def hood(x: float, y: float) -> bool:
    """A cowl, not a head: a disc with its crown pulled forward into a peak."""
    c = HOOD_C
    return in_disc(x, y, c, 0.036) or in_poly(x, y, [
        (c[0] - 0.034, c[1] - 0.008), (c[0] + 0.034, c[1] - 0.090),
        (c[0] + 0.036, c[1] - 0.004),
    ])


def arm(x: float, y: float) -> bool:
    return near_segment(x, y, SHOULDER, HAND, 0.019)


def figure(x: float, y: float) -> bool:
    return robe(x, y) or legs(x, y) or cloak(x, y) or hood(x, y) or arm(x, y)


def blade(x: float, y: float, px: float) -> bool:
    return near_segment(x, y, HAND, TIP, max(0.012, 0.75 * px))


def blade_edge(x: float, y: float, px: float) -> bool:
    """The lit edge: the upper-left side of the blade, the side the sun is on."""
    dx, dy = TIP[0] - HAND[0], TIP[1] - HAND[1]
    n = math.hypot(dx, dy)
    ox, oy = -dy / n, dx / n          # points up-left of the blade
    off = max(0.006, 0.5 * px)
    a = (HAND[0] - ox * off, HAND[1] - oy * off)
    b = (TIP[0] - ox * off, TIP[1] - oy * off)
    return near_segment(x, y, a, b, max(0.006, 0.5 * px)) and blade(x, y, px)


def guard(x: float, y: float, px: float) -> bool:
    dx, dy = TIP[0] - HAND[0], TIP[1] - HAND[1]
    n = math.hypot(dx, dy)
    ox, oy = -dy / n, dx / n
    g = (HAND[0] + dx / n * 0.028, HAND[1] + dy / n * 0.028)
    a = (g[0] + ox * 0.040, g[1] + oy * 0.040)
    b = (g[0] - ox * 0.040, g[1] - oy * 0.040)
    return near_segment(x, y, a, b, max(0.011, 0.6 * px))


def cast_shadow(x: float, y: float) -> bool:
    """Backlit, so the shadow comes straight at the viewer and keeps going off
    the bottom of the frame: longer than the figure, which is the point."""
    return in_poly(x, y, [
        (FIG_X - 0.06, FEET), (FIG_X + 0.07, FEET),
        (FIG_X + 0.16, 1.30), (FIG_X - 0.12, 1.30),
    ])


# --- layers -----------------------------------------------------------------

def back_layer(x: float, y: float, px: float):
    """Sky and sun. Fills the whole square: the adaptive mask may show any of
    it, so there is nothing transparent here."""
    if in_disc(x, y, SUN_C, SUN_R) and y < HORIZON:
        # One hard ring inside the disc: a gold face with a paler heart, the
        # way the parallax sky's sun is built.
        return LIGHT_SOFT if in_disc(x, y, SUN_C, SUN_R * 0.62) else LIGHT
    for limit, tone in SKY_BANDS:
        if y < limit:
            return tone
    return LIGHT_WARM


def front_layer(x: float, y: float, px: float):
    """Arch, floor, figure, shadow. Transparent wherever the sky shows."""
    if blade_edge(x, y, px):
        return PAPER
    if blade(x, y, px):
        return STEEL
    if guard(x, y, px):
        return LIGHT_WARM
    if figure(x, y):
        return INK

    if y >= HORIZON:
        if cast_shadow(x, y):
            return SHADOW_DEEP
        # The floor: a lit lip, then bands stepping down into the frame.
        if y < HORIZON + max(0.035, 1.6 * px):
            return LIGHT
        if y < HORIZON + max(0.06, 2.6 * px):
            return LIGHT_WARM
        if y < 0.86:
            return SHADOW_WARM
        # Coursed paving below, at the same pitch as the wall's courses.
        if (y % 0.125) < max(0.012, 0.6 * px):
            return SHADOW_DEEP
        return SHADOW

    if arch_void(x, y):
        return CLEAR
    if arch_void(x, y, max(ARCH_RING, 1.6 * px)):
        return ring_tone(x, y)
    # The keystone: the one block of full sun on the wall.
    if abs(x - ARCH_CX) < 0.045 and y < ARCH_CY - ARCH_R + 0.0 and y > ARCH_CY - ARCH_R - 0.07:
        return LIGHT
    # Coursed stone, as the tiles are: a joint every course.
    course = 0.125
    if (y % course) < max(0.012, 0.6 * px):
        return SHADOW_PIT
    return SHADOW_DEEP


def mono_layer(x: float, y: float, px: float):
    """Android's themed icon wants one shape in alpha: the arch and the
    figure with his sword, cut out of nothing."""
    if blade(x, y, px) or guard(x, y, px) or figure(x, y):
        return (255, 255, 255, 255)
    if y < HORIZON and not arch_void(x, y) and arch_void(x, y, max(ARCH_RING, 1.6 * px)):
        return (255, 255, 255, 255)
    return CLEAR


def flat(x: float, y: float, px: float):
    front = front_layer(x, y, px)
    return front if front[3] else back_layer(x, y, px)


# --- rasterising -------------------------------------------------------------

def raster(paint, grid: int, scale: int, inset: float = 0.0, span: float = 1.0) -> Image.Image:
    """Point-sample `paint` at the centre of every pixel of a `grid`-square
    canvas, then scale by an integer. `inset`/`span` map the canvas onto a
    window of the unit square, which is how the adaptive layers -- drawn on a
    108-unit canvas of which 72 are visible -- reuse the same picture."""
    image = Image.new("RGBA", (grid, grid), CLEAR)
    px = span / grid
    for j in range(grid):
        for i in range(grid):
            x = inset + (i + 0.5) * px
            y = inset + (j + 0.5) * px
            image.putpixel((i, j), paint(x, y, px))
    if scale != 1:
        image = image.resize((grid * scale, grid * scale), Image.NEAREST)
    return image


def svg(image: Image.Image) -> str:
    """One <path> per colour, one subpath per horizontal run: crisp at any
    size, and a few kilobytes rather than a rect per pixel."""
    runs: dict[tuple, list[str]] = {}
    w, h = image.size
    for y in range(h):
        x = 0
        while x < w:
            c = image.getpixel((x, y))
            end = x
            while end + 1 < w and image.getpixel((end + 1, y)) == c:
                end += 1
            if c[3]:
                runs.setdefault(c[:3], []).append("M%d %dh%dv1h-%dz" % (x, y, end - x + 1,
                                                                         end - x + 1))
            x = end + 1
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
           'viewBox="0 0 %d %d" shape-rendering="crispEdges">' % (w * 4, h * 4, w, h)]
    out.append("  <!-- Generated by tools/generate_icon.py. Do not edit by hand. -->")
    for c, parts in runs.items():
        out.append('  <path fill="#%02x%02x%02x" d="%s"/>' % (c[0], c[1], c[2], "".join(parts)))
    out.append("</svg>")
    return "\n".join(out) + "\n"


# The adaptive canvas is 108 units of which the middle 72 are ever shown, and
# the picture above is composed for the visible square. So the canvas maps to
# a unit window 1.5x the picture, centred.
ADAPTIVE_GRID = 108
ADAPTIVE_SPAN = 108.0 / 72.0
ADAPTIVE_INSET = (1.0 - ADAPTIVE_SPAN) / 2.0


def main() -> None:
    # The favicon and the project icon: drawn at 48, the size it is judged at.
    small = raster(flat, 48, 1)
    (ROOT / "icon.svg").write_text(svg(small))

    out = ROOT / "assets" / "icon"
    out.mkdir(parents=True, exist_ok=True)
    raster(flat, 48, 4).save(out / "icon_192.png")
    raster(back_layer, ADAPTIVE_GRID, 4, ADAPTIVE_INSET, ADAPTIVE_SPAN).save(
        out / "adaptive_background_432.png")
    raster(front_layer, ADAPTIVE_GRID, 4, ADAPTIVE_INSET, ADAPTIVE_SPAN).save(
        out / "adaptive_foreground_432.png")
    raster(mono_layer, ADAPTIVE_GRID, 4, ADAPTIVE_INSET, ADAPTIVE_SPAN).save(
        out / "adaptive_monochrome_432.png")
    raster(flat, 60, 3).save(ROOT / "site" / "public" / "img" / "apple-touch-icon.png")
    print("wrote icon.svg, assets/icon/*.png, site/public/img/apple-touch-icon.png")


if __name__ == "__main__":
    main()
