#!/usr/bin/env python3
"""Generate the tile atlas from the palette.

There are no hand-drawn assets in this project: the terrain and architecture
atlas is produced from the same duotone ramp the rest of the game uses, so
re-lighting the world (night, interior, storm) is a palette edit plus a re-run
of this script rather than an art pass.

    python3 tools/generate_tiles_png.py

Writes assets/tiles.png. Run tools/build_tileset.gd afterwards to rebuild the
TileSet resource that references it.

THE ATLAS HAS TWO HALVES.
The top half is every tile as it looks in full sun. The bottom half is the
SAME tile re-coloured one step down the ramp, as it looks inside a cast
shadow. The halves are in register: the shade twin of a tile is exactly
`SHADE_ROW_OFFSET` rows below it, which is what lets the world shader pick
between them with a constant V offset and a single extra texture fetch (see
assets/world_shadow.gdshader and docs/world.md).

The shade half is never painted by hand. It is the lit half pushed through
SHADE_MAP, so the two can never drift and so "re-light the world" stays one
table edit. Every colour a painter uses must therefore have an entry in
SHADE_MAP; main() fails loudly if one does not.
"""
from __future__ import annotations

import pathlib
from PIL import Image

TILE = 16
COLUMNS = 16
LIT_ROWS = 4
SHADE_ROW_OFFSET = LIT_ROWS
ROWS = LIT_ROWS * 2

# --- the palette ----------------------------------------------------------
# Mirrors scripts/core/palette.gd. Names say how a surface faces the light.

INK = (0x2B, 0x0A, 0x14, 255)
SHADOW_DEEP = (0x7A, 0x12, 0x30, 255)
SHADOW = (0xB3, 0x21, 0x42, 255)
SHADOW_WARM = (0xD8, 0x45, 0x2C, 255)
MID = (0xE8, 0x70, 0x2A, 255)
LIGHT_WARM = (0xF2, 0xA8, 0x29, 255)
LIGHT = (0xF7, 0xCE, 0x2E, 255)
LIGHT_SOFT = (0xFF, 0xE8, 0x73, 255)
PAPER = (0xFF, 0xF4, 0xC2, 255)

WATER = (0x46, 0xC7, 0xB0, 255)
WATER_DEEP = (0x1F, 0x8F, 0x86, 255)
WATER_INK = (0x14, 0x5A, 0x58, 255)
FOLIAGE = (0x5F, 0xBF, 0x7A, 255)
FOLIAGE_DARK = (0x2F, 0x7A, 0x4C, 255)
CLOTH = (0xC6, 0x35, 0x4F, 255)
CLOTH_DARK = (0x8E, 0x1F, 0x38, 255)
STEEL = (0x8C, 0x8F, 0xA3, 255)
STEEL_DARK = (0x5A, 0x5D, 0x70, 255)
STEEL_INK = (0x39, 0x3B, 0x4A, 255)
## One tone below SHADOW_DEEP, and the darkest a SURFACE is allowed to go.
## Black is reserved for joints, voids and the foreground silhouette: a
## shadowed wall that goes to INK stops being crimson and the duotone breaks.
SHADOW_PIT = (0x4A, 0x0D, 0x1E, 255)
CLEAR = (0, 0, 0, 0)

# One step down the ramp. A surface in cast shadow is not "the same colour,
# darker" -- it is the next tone down, which is what keeps the world duotone
# instead of muddy. Nothing here brightens.
SHADE_MAP = {
    CLEAR: CLEAR,
    PAPER: MID,
    LIGHT_SOFT: SHADOW_WARM,
    LIGHT: SHADOW,
    LIGHT_WARM: SHADOW_DEEP,
    MID: SHADOW_DEEP,
    SHADOW_WARM: SHADOW_DEEP,
    SHADOW: SHADOW_DEEP,
    SHADOW_DEEP: SHADOW_PIT,
    SHADOW_PIT: SHADOW_PIT,
    INK: INK,
    WATER: WATER_DEEP,
    WATER_DEEP: WATER_INK,
    WATER_INK: WATER_INK,
    FOLIAGE: FOLIAGE_DARK,
    FOLIAGE_DARK: FOLIAGE_DARK,
    CLOTH: CLOTH_DARK,
    CLOTH_DARK: INK,
    STEEL: STEEL_DARK,
    STEEL_DARK: STEEL_INK,
    STEEL_INK: STEEL_INK,
}

# The sun. Low from the left: two pixels across for every one down, which is
# the same vector scripts/render/sun_shadow.gd casts with. Surfaces whose
# normal points into it are lit; surfaces facing away are not.
SUN_TO_SURFACE = (2.0, 1.0)


# --- a 16x16 scratch tile -------------------------------------------------

class Patch:
    """A pixel buffer with the handful of primitives these tiles need.

    Deliberately not PIL's ImageDraw: at 16 px every tile is placed pixel by
    pixel, and ImageDraw's anti-aliasing-free-but-off-by-one rectangles cost
    more time than they save.
    """

    def __init__(self, width: int, height: int, fill=CLEAR) -> None:
        self.w = width
        self.h = height
        self.px = [[fill for _ in range(width)] for _ in range(height)]

    def set(self, x: int, y: int, c) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def get(self, x: int, y: int):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return CLEAR

    def rect(self, x0: int, y0: int, x1: int, y1: int, c) -> None:
        """Inclusive on both corners."""
        for y in range(min(y0, y1), max(y0, y1) + 1):
            for x in range(min(x0, x1), max(x0, x1) + 1):
                self.set(x, y, c)

    def hline(self, y: int, x0: int, x1: int, c) -> None:
        self.rect(x0, y, x1, y, c)

    def vline(self, x: int, y0: int, y1: int, c) -> None:
        self.rect(x, y0, x, y1, c)

    def fill(self, c) -> None:
        self.rect(0, 0, self.w - 1, self.h - 1, c)

    def mirror(self) -> "Patch":
        out = Patch(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                out.px[y][x] = self.px[y][self.w - 1 - x]
        return out

    def sub(self, x0: int, y0: int, w: int, h: int) -> "Patch":
        out = Patch(w, h)
        for y in range(h):
            for x in range(w):
                out.px[y][x] = self.get(x0 + x, y0 + y)
        return out


FACE_RAMP = (LIGHT, LIGHT_WARM, SHADOW, SHADOW_DEEP)
## The arch ring sits on a SHADOW spandrel, so its unlit steps have to go
## below that or the curve disappears into the wall behind it.
RING_RAMP = (LIGHT, LIGHT_WARM, SHADOW_DEEP, INK)


def lit_by_normal(nx: float, ny: float, ramp=FACE_RAMP):
    """Pick a tone for a surface from the direction it faces."""
    length = (nx * nx + ny * ny) ** 0.5 or 1.0
    # Positive when the normal points back along the incoming ray.
    d = -(nx * SUN_TO_SURFACE[0] + ny * SUN_TO_SURFACE[1]) / (length * 5.0 ** 0.5)
    if d > 0.55:
        return ramp[0]
    if d > 0.15:
        return ramp[1]
    if d > -0.25:
        return ramp[2]
    return ramp[3]


# --- masonry --------------------------------------------------------------

COURSE = 8  # two courses to a tile


def ashlar(p: Patch, body, top_course: int = 0) -> None:
    """Coursed stone: a lit lip on the top of every course, a dark bed joint
    under it, and staggered perpends. Three tones is enough to read as stone
    at 16 px; a noise texture at this size reads as dirt."""
    lip = MID if body is SHADOW else SHADOW
    bed = INK if body is SHADOW_DEEP else SHADOW_DEEP
    course = top_course
    index = 0
    while course < TILE:
        if course >= 0:
            p.hline(course, 0, TILE - 1, lip)
        bottom = min(course + COURSE - 1, TILE - 1)
        if bottom > course:
            p.hline(bottom, 0, TILE - 1, bed)
        # Perpends alternate so the courses interlock rather than grid up.
        jx = 4 if index % 2 == 0 else 12
        if course + 1 <= bottom - 1:
            p.vline(jx, course + 1, bottom - 1, bed)
        course += COURSE
        index += 1


CAP_LIGHT = 3   # gold top surface
CAP_BEVEL = 1   # warm bevel under it
CAP_LINE = 1    # the hard line where the top surface ends


def solid(capped: bool, lit_left: bool) -> Patch:
    p = Patch(TILE, TILE)
    body = SHADOW if capped else SHADOW_DEEP
    p.fill(body)
    if capped:
        top = CAP_LIGHT + CAP_BEVEL + CAP_LINE
        ashlar(p, body, top_course=top)
        p.rect(0, 0, TILE - 1, CAP_LIGHT - 1, LIGHT)
        p.hline(CAP_LIGHT, 0, TILE - 1, LIGHT_WARM)
        p.hline(CAP_LIGHT + CAP_BEVEL, 0, TILE - 1, SHADOW_WARM)
    else:
        ashlar(p, body)
    if lit_left:
        # A left-facing vertical face is square to a sun this low, so it is
        # the brightest thing on a wall after the top surface itself.
        start = (CAP_LIGHT + CAP_BEVEL + CAP_LINE) if capped else 0
        p.vline(0, start, TILE - 1, LIGHT_WARM)
        p.vline(1, start, TILE - 1, MID)
    return p


def platform(_unused=None) -> Patch:
    """A one-way stone shelf. Corbels under it say 'you can stand here' from
    a distance, which a plain slab does not."""
    p = Patch(TILE, TILE)
    p.rect(0, 0, TILE - 1, 2, LIGHT)
    p.hline(3, 0, TILE - 1, LIGHT_WARM)
    p.hline(4, 0, TILE - 1, SHADOW_WARM)
    p.rect(0, 5, TILE - 1, 6, SHADOW_DEEP)
    for cx in (2, 8):
        p.rect(cx, 7, cx + 4, 8, SHADOW_DEEP)
        p.set(cx, 7, SHADOW)
    return p


def spikes(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    base = TILE - 1
    p.rect(0, base - 2, TILE - 1, base, SHADOW_DEEP)
    p.hline(base - 2, 0, TILE - 1, SHADOW)
    for i in range(4):
        cx = i * 4 + 2
        for k in range(11):
            y = base - 3 - k
            half = max(0, (10 - k) * 2 // 7)
            p.rect(cx - half, y, cx + half, y, STEEL)
            p.rect(cx - half, y, cx - 1, y, STEEL_DARK)
    return p


def water(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    p.rect(0, 2, TILE - 1, TILE - 1, WATER_DEEP)
    p.hline(2, 0, TILE - 1, WATER)
    p.hline(3, 0, TILE - 1, WATER)
    for x in (1, 2, 9, 10):
        p.set(x, 5, WATER)
    p.rect(0, TILE - 3, TILE - 1, TILE - 1, WATER_INK)
    return p


def ladder(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    p.rect(3, 0, 4, TILE - 1, SHADOW_DEEP)
    p.vline(3, 0, TILE - 1, SHADOW)
    p.rect(TILE - 5, 0, TILE - 4, TILE - 1, SHADOW_DEEP)
    p.vline(TILE - 5, 0, TILE - 1, SHADOW)
    for i in range(3):
        y = 2 + i * 5
        p.rect(3, y, TILE - 4, y, LIGHT_WARM)
        p.rect(3, y + 1, TILE - 4, y + 1, SHADOW_DEEP)
    return p


# --- the horseshoe arch ---------------------------------------------------
#
# Drawn once at 32x48 and then cut into six tiles, because the curve has to
# run continuously across the seam. Two cells wide and three tall is the
# smallest opening a 22 px character walks through without ducking.

ARCH_W, ARCH_H = TILE * 2, TILE * 3
ARCH_CX, ARCH_CY, ARCH_R = 16.0, 13.0, 12.0
ARCH_SPRING = 20.0                      # below here the jambs run straight
ARCH_JAMB = (ARCH_R ** 2 - (ARCH_SPRING - ARCH_CY) ** 2) ** 0.5
RING = 3.0


def _arch_void(x: float, y: float) -> bool:
    if y <= ARCH_SPRING:
        return (x - ARCH_CX) ** 2 + (y - ARCH_CY) ** 2 <= ARCH_R ** 2
    return abs(x - ARCH_CX) <= ARCH_JAMB


def _arch_ring(x: float, y: float) -> bool:
    if _arch_void(x, y):
        return False
    if y <= ARCH_SPRING:
        d = ((x - ARCH_CX) ** 2 + (y - ARCH_CY) ** 2) ** 0.5
        return d <= ARCH_R + RING
    return abs(x - ARCH_CX) <= ARCH_JAMB + RING


def _arch_normal(x: float, y: float) -> tuple[float, float]:
    if y <= ARCH_SPRING:
        return (x - ARCH_CX, y - ARCH_CY)
    return (1.0 if x > ARCH_CX else -1.0, 0.0)


def arch_sheet() -> Patch:
    p = Patch(ARCH_W, ARCH_H)
    for y in range(ARCH_H):
        for x in range(ARCH_W):
            fx, fy = x + 0.5, y + 0.5
            if _arch_void(fx, fy):
                # The light that gets through the opening lands on the wall
                # behind it, offset down-right along the sun vector. That
                # patch is the arch's own shape, shifted.
                through = _arch_void(fx - 7.0, fy - 3.5)
                p.set(x, y, SHADOW_DEEP if through else INK)
            elif _arch_ring(fx, fy):
                nx, ny = _arch_normal(fx, fy)
                p.set(x, y, lit_by_normal(nx, ny, RING_RAMP))
            else:
                p.set(x, y, SHADOW)
                ashlar_pixel(p, x, y)
    # A hard keystone so the crown is not just a smooth band.
    p.rect(14, 0, 17, 2, LIGHT)
    p.hline(3, 14, 17, LIGHT_WARM)
    return p


def ashlar_pixel(p: Patch, x: int, y: int) -> None:
    """Coursing for the spandrels of the arch sheet, in sheet coordinates."""
    if y % COURSE == 0:
        p.set(x, y, MID)
    elif y % COURSE == COURSE - 1:
        p.set(x, y, SHADOW_DEEP)
    elif x % 8 == (4 if (y // COURSE) % 2 == 0 else 0):
        p.set(x, y, SHADOW_DEEP)


# --- architecture and decoration -----------------------------------------

def backdrop(_unused=None) -> Patch:
    """Background masonry with a blind recess. Never collides; this is the
    filler behind a colonnade."""
    p = Patch(TILE, TILE)
    p.fill(SHADOW_DEEP)
    ashlar(p, SHADOW_DEEP)
    for y in range(TILE):
        for x in range(TILE):
            fx, fy = x + 0.5, y + 0.5
            if _recess(fx, fy, 8.0, 7.0, 5.2, 4.4):
                # Light rakes in over the left lip and dies on the back wall.
                p.set(x, y, SHADOW_DEEP if _recess(fx - 4.0, fy - 2.0, 8.0, 7.0, 5.2, 4.4) else INK)
    _recess_lip(p, 8.0, 7.0, 5.2, 4.4)
    return p


def _recess(fx: float, fy: float, cx: float, cy: float, r: float, half: float) -> bool:
    """A horseshoe-topped hole: a disc above the springline, straight below."""
    if fy < cy:
        return (fx - cx) ** 2 + (fy - cy) ** 2 <= r * r
    return abs(fx - cx) <= half and fy < TILE


def _recess_lip(p: Patch, cx: float, cy: float, r: float, half: float) -> None:
    """One lit pixel along the sun-facing edge of a recess. Without it a
    carved hole reads as a sticker rather than as depth."""
    for y in range(TILE):
        for x in range(TILE):
            fx, fy = x + 0.5, y + 0.5
            if _recess(fx, fy, cx, cy, r, half):
                continue
            if (_recess(fx + 1.0, fy, cx, cy, r, half)
                    or _recess(fx, fy + 1.0, cx, cy, r, half)):
                p.set(x, y, LIGHT_WARM)


# --- what a lit cap promises ------------------------------------------------
#
# In this art a band of gold across the top of a thing says one thing: you can
# stand here. Terrain caps and platforms carry it, and nothing else may. A
# player on a phone jumped at a balustrade's lit rail hanging over the Sun
# Terrace because it was drawn exactly like a ledge, and called the carved
# friezes "horizontal ladders" -- two gold rails with slots between. So no
# decoration has light (LIGHT_WARM or brighter) across 12 or more of its 16
# columns in any row: it may be lit on an edge, a post, a jamb, never across
# its top. tests/unit/test_false_platforms.gd reads the atlas and holds it.
# docs/world.md, "Lit caps are a promise", argues the rule.

def cornice(_unused=None) -> Patch:
    """A low moulding along a terrace lip, in the empty cell above it: a kerb
    on the floor, not a second floor over it. Its top catches only the warm
    shade; the floor's own cap below it is the gold."""
    p = Patch(TILE, TILE)
    p.hline(11, 0, TILE - 1, SHADOW_WARM)
    p.rect(0, 12, TILE - 1, 13, SHADOW)
    p.rect(0, 14, TILE - 1, TILE - 1, SHADOW_DEEP)
    for x in range(1, TILE, 4):          # dentils
        p.rect(x, 14, x + 1, TILE - 1, INK)
    return p


def balustrade(_unused=None) -> Patch:
    """A railing standing on the terrace, waist high to the prince, behind
    him: the plinth sits on the floor at the bottom of the cell, the rail
    twelve pixels up. It used to hang a cell higher with a gold rail, which
    read as a ledge over the floor; now it is dark, unlit across its top, and
    shorter than the man passing in front of it, so it cannot be mistaken
    for anything to stand on. Posts are two pixels wide on purpose -- see
    docs/world.md: a one-pixel caster lands on only half the shadow lanes and
    casts a dotted shadow."""
    p = Patch(TILE, TILE)
    p.hline(3, 0, TILE - 1, SHADOW)
    p.hline(4, 0, TILE - 1, SHADOW_DEEP)
    p.hline(5, 0, TILE - 1, INK)
    for px0 in (1, 6, 11):
        p.rect(px0, 6, px0 + 2, 12, SHADOW_DEEP)
        p.vline(px0, 6, 12, SHADOW)
        p.vline(px0 + 2, 6, 12, INK)
    p.hline(13, 0, TILE - 1, SHADOW)
    p.rect(0, 14, TILE - 1, TILE - 1, SHADOW_DEEP)
    return p


def _shaft(p: Patch, y0: int, y1: int) -> None:
    p.rect(4, y0, 11, y1, SHADOW)
    p.vline(4, y0, y1, LIGHT_WARM)
    p.vline(5, y0, y1, MID)
    p.vline(8, y0, y1, SHADOW_DEEP)
    p.vline(11, y0, y1, INK)


def column_shaft(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    _shaft(p, 0, TILE - 1)
    return p


def column_cap(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    _shaft(p, 7, TILE - 1)
    # The abacus is lit on its west end, the face square to the sun, and not
    # across its top: a column ends four tiles up, exactly at grab height,
    # and a gold slab there reads as a ledge to grab.
    p.rect(1, 0, TILE - 2, 1, SHADOW_WARM)
    p.vline(1, 0, 1, LIGHT_WARM)
    p.hline(2, 1, TILE - 2, SHADOW)
    for i in range(4):                            # flaring echinus
        inset = 2 + i
        p.rect(inset, 3 + i, TILE - 1 - inset, 3 + i, SHADOW)
        p.set(inset, 3 + i, LIGHT_WARM)
        p.set(TILE - 1 - inset, 3 + i, INK)
    return p


def column_base(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    _shaft(p, 0, 8)
    for i in range(3):                            # flaring torus
        inset = 3 - i
        p.rect(inset, 9 + i, TILE - 1 - inset, 9 + i, SHADOW)
        p.set(inset, 9 + i, LIGHT_WARM)
        p.set(TILE - 1 - inset, 9 + i, INK)
    p.hline(12, 0, TILE - 1, MID)                 # plinth, warm, not a cap
    p.rect(0, 13, TILE - 1, TILE - 1, SHADOW_DEEP)
    p.vline(0, 13, TILE - 1, MID)
    return p


def planter(_unused=None) -> Patch:
    """Green is rationed to living things, so this is the only tile in the
    terrain set that carries it."""
    p = Patch(TILE, TILE)
    for fx, h, lean in ((4, 8, -1), (8, 9, 0), (11, 7, 1)):
        for k in range(h):
            x = fx + round(lean * (k * k) / 24.0)
            p.set(x, 8 - k, FOLIAGE)
            p.set(x + 1, 8 - k, FOLIAGE_DARK)
    p.hline(9, 2, TILE - 3, MID)                  # the rim: warm, not a cap
    p.set(2, 9, LIGHT_WARM)
    p.hline(10, 2, TILE - 3, SHADOW_WARM)
    p.rect(2, 11, TILE - 3, TILE - 1, SHADOW)
    p.vline(2, 11, TILE - 1, LIGHT_WARM)
    p.vline(TILE - 3, 11, TILE - 1, INK)
    p.rect(5, 12, 10, 13, SHADOW_DEEP)
    return p


def niche(_unused=None) -> Patch:
    """A blind recess carved into a wall face. Auto-dressed onto tall walls,
    which is how a flat rectangle of masonry stops being a placeholder."""
    p = Patch(TILE, TILE)
    p.fill(SHADOW)
    ashlar(p, SHADOW)
    for y in range(TILE):
        for x in range(TILE):
            fx, fy = x + 0.5, y + 0.5
            if _recess(fx, fy, 8.0, 8.0, 4.6, 3.8):
                p.set(x, y, INK)
    _recess_lip(p, 8.0, 8.0, 4.6, 3.8)
    p.rect(6, 11, 9, 14, SHADOW_DEEP)             # an urn standing in it
    p.vline(6, 11, 14, SHADOW)
    p.hline(10, 5, 10, SHADOW_DEEP)
    p.hline(11, 5, 10, SHADOW)
    return p


def frieze(_unused=None) -> Patch:
    """A carved band: blind arches cut into the course under a lip, the
    cheapest way to make a long wall face read as built rather than poured.
    Two to a cell, round-headed, in the wall's own shade and with no rails:
    three slots a cell between two gold lines was a ladder lying on its side,
    and was called one by a player who tried to climb it. Lit along the lower
    and right inner edges, as every carved recess is (docs/ui.md, "The
    light")."""
    p = Patch(TILE, TILE)
    p.fill(SHADOW)
    p.hline(0, 0, TILE - 1, SHADOW_WARM)
    p.hline(1, 0, TILE - 1, SHADOW_DEEP)
    for sx in (2, 10):
        cx = sx + 2.0
        for y in range(4, 12):
            for x in range(sx, sx + 4):
                fx, fy = x + 0.5, y + 0.5
                inside = abs(fx - cx) <= 1.8 if fy > 6.5 else (fx - cx) ** 2 + (fy - 6.5) ** 2 <= 3.6
                if inside:
                    p.set(x, y, INK)
        p.vline(sx + 4, 6, 11, MID)              # the right jamb, in the sun
        p.hline(12, sx, sx + 3, MID)             # the sill
    p.rect(0, 14, TILE - 1, TILE - 1, SHADOW_DEEP)
    return p


def banner(_unused=None) -> Patch:
    """Hanging cloth on the mid-ground. Crimson accent, rationed."""
    p = Patch(TILE, TILE)
    p.rect(3, 0, TILE - 4, TILE - 1, CLOTH)
    p.vline(3, 0, TILE - 1, CLOTH_DARK)
    p.vline(8, 0, TILE - 1, CLOTH_DARK)
    p.vline(TILE - 4, 0, TILE - 1, CLOTH_DARK)
    p.rect(3, 0, TILE - 4, 1, INK)
    p.rect(4, 2, 7, 2, SHADOW_WARM)
    return p


def fountain_sheet() -> Patch:
    """Two cells wide. Teal is water and player two and nothing else."""
    p = Patch(TILE * 2, TILE)
    # The rim is waist high and nobody stands on it, so it is warm, not
    # gold; the water and its one specular are what the eye goes to.
    p.hline(5, 0, TILE * 2 - 1, MID)
    p.hline(6, 0, TILE * 2 - 1, SHADOW_WARM)
    p.hline(7, 0, TILE * 2 - 1, SHADOW)
    p.rect(0, 8, TILE * 2 - 1, TILE - 1, SHADOW)
    p.rect(2, 8, TILE * 2 - 3, 10, WATER)
    p.rect(2, 11, TILE * 2 - 3, TILE - 1, WATER_DEEP)
    p.rect(4, 8, 6, 8, PAPER)                     # the one specular
    p.rect(14, 0, 17, 4, WATER)                   # the jet
    p.vline(14, 0, 4, PAPER)
    p.rect(0, TILE - 2, TILE * 2 - 1, TILE - 1, SHADOW_DEEP)
    p.vline(0, 5, TILE - 1, LIGHT_WARM)
    p.vline(TILE * 2 - 1, 8, TILE - 1, INK)
    return p


# --- the foreground plane -------------------------------------------------
#
# Everything below is drawn in front of the player and never above SHADOW_DEEP
# in tone. The art direction calls this near-silhouette: it is there to be
# passed behind, not to be looked at.

def fore_rail(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    p.rect(0, 1, TILE - 1, 3, INK)
    p.hline(1, 0, TILE - 1, SHADOW_DEEP)
    for px0 in (1, 6, 11):
        p.rect(px0, 4, px0 + 3, TILE - 1, INK)
        p.vline(px0, 4, TILE - 1, SHADOW_DEEP)
    p.rect(0, 12, TILE - 1, 13, INK)
    p.hline(12, 0, TILE - 1, SHADOW_DEEP)
    return p


def fore_column(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    p.rect(2, 0, TILE - 3, TILE - 1, INK)
    p.vline(2, 0, TILE - 1, SHADOW_DEEP)
    p.vline(3, 0, TILE - 1, SHADOW_DEEP)
    p.vline(8, 0, TILE - 1, SHADOW_DEEP)
    return p


def fore_soffit() -> Patch:
    """The inside corner of an arch passing in front of the camera. Drawn as
    a pair; this is the left one."""
    p = Patch(TILE, TILE)
    for y in range(TILE):
        for x in range(TILE):
            d = ((x + 0.5 - TILE) ** 2 + (y + 0.5 - TILE) ** 2) ** 0.5
            if d > TILE - 0.5:
                p.set(x, y, INK)
            elif d > TILE - 2.0:
                p.set(x, y, SHADOW_DEEP)
    return p


def fore_cloth(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    p.rect(1, 0, TILE - 2, TILE - 1, CLOTH_DARK)
    p.rect(1, 0, TILE - 2, 1, INK)
    for x in (4, 8, 12):
        p.vline(x, 2, TILE - 1, INK)
    return p


def fore_cloth_tail(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    p.rect(1, 0, TILE - 2, 9, CLOTH_DARK)
    for x in (4, 8, 12):
        p.vline(x, 0, 9, INK)
    for i in range(5):                            # scalloped fringe
        for x in range(1, TILE - 1):
            if (x + i) % 5 < 5 - i:
                p.set(x, 10 + i, CLOTH_DARK)
    return p


# --- wear, growth and the things people leave about ------------------------
#
# Row two of the atlas. A city that has stood for three hundred years is not
# clean: stone cracks and spalls, ivy comes over the parapets, moss grows where
# water stands, and the people who live there leave jars against the wall and
# a rug over the railing. scripts/world/dresser.gd gives each room ONE of those
# moods, so that rooms differ from each other rather than all carrying a little
# of everything.
#
# The first seven are OVERLAYS: drawn over a wall face on the props plane with
# a transparent ground, so the coursing of the stone underneath shows through.
# The rest stand on a floor or hang from an overhang.

def crack(_unused=None) -> Patch:
    """A crack running down through two courses, its lower-right lip catching
    the sun, plus a chipped arris where it leaves a block."""
    p = Patch(TILE, TILE)
    path = [(9, 0), (9, 1), (8, 2), (8, 3), (7, 4), (7, 5), (8, 6), (8, 7),
            (7, 8), (6, 9), (6, 10), (5, 11), (5, 12), (6, 13), (5, 14)]
    for x, y in path:
        p.set(x, y, INK)
    for x, y in path:
        if p.get(x + 1, y) == CLEAR:
            p.set(x + 1, y, SHADOW)
    p.set(10, 2, INK)                             # a hairline branch
    p.set(11, 3, INK)
    p.rect(0, 8, 1, 9, INK)                       # chipped corner of a block
    p.set(2, 9, SHADOW)
    return p


def worn(_unused=None) -> Patch:
    """One block spalled away: a shallow recess whose lower and right inner
    walls are lit, with the broken edge still showing."""
    p = Patch(TILE, TILE)
    p.rect(5, 9, 11, 14, SHADOW_PIT)
    p.hline(9, 5, 11, INK)
    p.vline(5, 9, 14, INK)
    p.hline(14, 6, 11, SHADOW)
    p.vline(11, 10, 14, SHADOW)
    p.set(7, 11, SHADOW_DEEP)
    p.set(9, 12, SHADOW_DEEP)
    p.rect(1, 2, 3, 3, SHADOW_PIT)                # a pitted patch higher up
    p.hline(2, 1, 3, INK)
    p.set(3, 3, SHADOW)
    return p


IVY_STRANDS = (2, 6, 10, 13)


def _leaf(p: Patch, x: int, y: int) -> None:
    """A 2x2 leaf, lit on its upper left, the way everything is."""
    p.set(x, y, FOLIAGE)
    p.set(x + 1, y, FOLIAGE)
    p.set(x, y + 1, FOLIAGE)
    p.set(x + 1, y + 1, FOLIAGE_DARK)


def _ivy(p: Patch, lengths, leaf_every: int, top_mat: bool) -> None:
    for i, x in enumerate(IVY_STRANDS):
        length = lengths[i]
        for y in range(length):
            p.set(x, y, FOLIAGE_DARK)
        for y in range((i * 3) % leaf_every, length - 1, leaf_every):
            _leaf(p, x - 1 + (y // leaf_every) % 2, y)
    if top_mat:
        # The mat spilling over the parapet: dense along the top edge.
        for x in range(0, TILE, 3):
            _leaf(p, x, 0)
            _leaf(p, x + 1, 2 if x % 2 else 1)


def ivy_top(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    _ivy(p, (TILE, TILE, TILE, TILE), 4, True)
    return p


def ivy(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    _ivy(p, (TILE, TILE, TILE, TILE), 5, False)
    return p


def ivy_end(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    _ivy(p, (9, 13, 6, 11), 5, False)
    return p


def moss(_unused=None) -> Patch:
    """Clumps of green in the joints of stone that stands in water: the
    cistern moss the art direction names as one of the few places green
    belongs. Clumps, not a pattern -- an even dash along every joint read as
    netting."""
    p = Patch(TILE, TILE)
    for x0, y0, w in ((1, 7, 4), (10, 15, 5), (6, 15, 2), (12, 7, 2)):
        p.hline(y0, x0, x0 + w - 1, FOLIAGE_DARK)
        p.hline(y0 - 1, x0 + 1, x0 + w - 2, FOLIAGE)
    p.set(3, 8, FOLIAGE_DARK)                     # a trail down the stone
    p.set(3, 9, FOLIAGE_DARK)
    p.set(11, 14, FOLIAGE_DARK)
    return p


def window(_unused=None) -> Patch:
    """A latticed window in a wall face: a horseshoe-headed opening filled
    with turned wood, a lit sill, and two panes of lamplight from the room
    behind. A wall with a window in it is a house, not a rampart."""
    p = Patch(TILE, TILE)
    for y in range(2, 14):
        for x in range(4, 12):
            fx, fy = x + 0.5, y + 0.5
            if fy < 5.5 and (fx - 8.0) ** 2 + (fy - 5.5) ** 2 > 12.5:
                continue
            on_grid = (x + y) % 3 == 0 or (x - y) % 3 == 0
            p.set(x, y, SHADOW_WARM if on_grid else INK)
    for x, y in ((6, 8), (9, 10)):
        p.set(x, y, LIGHT_WARM)
    p.hline(14, 3, 12, LIGHT)                     # the sill's lit top
    p.hline(15, 3, 12, SHADOW_DEEP)
    p.vline(12, 4, 13, SHADOW)                    # the reveal the sun reaches
    return p


def urn(_unused=None) -> Patch:
    """A tall amphora against the wall: terracotta, lit down its left side,
    with two handles that make it a vessel rather than an egg."""
    p = Patch(TILE, TILE)
    profile = {4: 2, 5: 2, 6: 3, 7: 4, 8: 4, 9: 4, 10: 4, 11: 3, 12: 3, 13: 2, 14: 2}
    for y, half in profile.items():
        for x in range(8 - half, 8 + half):
            p.set(x, y, MID if x < 7 else SHADOW_WARM)
        p.set(8 - half, y, LIGHT_WARM)
        p.set(7 + half, y, SHADOW)
    p.rect(6, 2, 9, 3, MID)                       # neck and lip
    p.hline(2, 6, 9, LIGHT_WARM)
    p.set(9, 3, SHADOW)
    p.vline(3, 5, 7, SHADOW_WARM)                 # handles
    p.vline(12, 5, 7, SHADOW)
    p.hline(9, 5, 10, SHADOW_DEEP)                # a painted band
    p.rect(6, 15, 9, 15, SHADOW_DEEP)             # foot
    return p


def jars(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    for x0, top, w in ((1, 9, 6), (8, 11, 5)):
        for y in range(top, TILE):
            for x in range(x0, x0 + w):
                p.set(x, y, MID if x < x0 + w // 2 else SHADOW_WARM)
            p.set(x0, y, LIGHT_WARM)
            p.set(x0 + w - 1, y, SHADOW)
        p.rect(x0 + 1, top - 1, x0 + w - 2, top - 1, LIGHT_WARM)
        p.hline(TILE - 1, x0, x0 + w - 1, SHADOW_DEEP)
    p.hline(12, 1, 6, SHADOW_DEEP)
    return p


def rubble(_unused=None) -> Patch:
    """Fallen stones at the foot of a wall: each block a lit top and a shaded
    face, the same two planes the terrain is made of."""
    p = Patch(TILE, TILE)
    for x0, y0, w, h in ((1, 11, 5, 4), (6, 13, 4, 2), (10, 10, 5, 5), (7, 9, 3, 3)):
        p.rect(x0, y0, x0 + w - 1, y0 + h - 1, SHADOW)
        p.hline(y0, x0, x0 + w - 1, LIGHT)
        p.vline(x0 + w - 1, y0 + 1, y0 + h - 1, SHADOW_DEEP)
    p.hline(TILE - 1, 0, TILE - 1, SHADOW_DEEP)
    return p


def grass(_unused=None) -> Patch:
    """Tufts along a lip: a living edge on a stone one. Kept off the
    standing-caster list -- blades this thin would cast a dotted shadow."""
    p = Patch(TILE, TILE)
    for x, h in ((1, 2), (2, 4), (3, 3), (6, 2), (9, 3), (10, 5), (11, 3), (14, 2)):
        for k in range(h):
            p.set(x, TILE - 1 - k, FOLIAGE if k == h - 1 or x % 2 else FOLIAGE_DARK)
    return p


def planter_bloom(_unused=None) -> Patch:
    """The planter, in flower. The blossoms take CLOTH's crimson so the
    flowers sit inside the palette rather than beside it."""
    p = planter()
    for x, y in ((3, 2), (8, 0), (12, 3), (6, 4), (10, 1)):
        p.set(x, y, CLOTH)
        p.set(x + 1, y, CLOTH)
        p.set(x, y + 1, CLOTH_DARK)
    return p


def palm_sheet() -> Patch:
    """A potted palm, two cells tall. Its fronds stand on the terrace, so a
    palm throws the one ragged shadow in a world of straight ones."""
    p = Patch(TILE, TILE * 2)
    base = TILE * 2 - 1
    p.rect(4, base - 4, 11, base, SHADOW)         # the pot
    p.vline(4, base - 4, base, LIGHT_WARM)
    p.vline(11, base - 4, base, INK)
    p.hline(base - 5, 3, 12, LIGHT)
    for y in range(6, base - 5):                  # the trunk, ringed
        p.set(7, y, SHADOW_WARM)
        p.set(8, y, SHADOW_DEEP)
        if y % 3 == 0:
            p.set(7, y, MID)
    crown = (7.5, 6.0)
    for dx, lift, length in ((-1, 2.0, 7), (1, 2.0, 7), (-1, 0.6, 6), (1, 0.6, 6),
                             (-1, 3.2, 4), (1, 3.4, 4)):
        for k in range(length):
            x = int(crown[0] + dx * (k + 0.5))
            y = int(crown[1] - lift + (k * k) / 7.0)
            p.set(x, y, FOLIAGE)
            p.set(x, y + 1, FOLIAGE_DARK)
    p.rect(7, 4, 8, 6, FOLIAGE_DARK)
    return p


def lantern(_unused=None) -> Patch:
    """A pierced brass lantern hung from an overhang. The chain is two pixels
    wide for the same reason a balustrade post is."""
    p = Patch(TILE, TILE)
    for y in range(0, 5):
        p.set(7, y, INK if y % 2 else SHADOW_DEEP)
        p.set(8, y, SHADOW_DEEP if y % 2 else INK)
    p.rect(6, 5, 9, 5, LIGHT_WARM)                # cap
    p.rect(5, 6, 10, 6, LIGHT_WARM)
    p.rect(5, 7, 10, 11, INK)                     # body
    for x, y in ((6, 8), (8, 8), (7, 10), (9, 10), (6, 10)):
        p.set(x, y, LIGHT_SOFT)                   # the flame, through the piercing
    p.vline(5, 7, 11, LIGHT_WARM)
    p.rect(5, 12, 10, 12, LIGHT_WARM)
    p.rect(7, 13, 8, 14, SHADOW_WARM)             # finial
    return p


def balustrade_rug(_unused=None) -> Patch:
    """A rug hung over the railing to air. Somebody lives here."""
    p = balustrade()
    p.rect(3, 3, 12, 13, CLOTH)
    p.hline(3, 3, 12, CLOTH_DARK)                 # the fold over the rail
    p.hline(6, 3, 12, LIGHT_WARM)
    p.hline(10, 3, 12, LIGHT_WARM)
    for x in range(4, 12, 3):
        p.set(x, 7, SHADOW_DEEP)
        p.set(x + 1, 8, SHADOW_DEEP)
    p.vline(12, 3, 13, CLOTH_DARK)
    for x in range(3, 13, 2):                     # fringe
        p.set(x, 14, LIGHT_WARM)
    return p


# --- secrets: the masonry that is hiding something --------------------------
#
# Row three of the atlas, and every tile on it is an OVERLAY drawn over a
# buried or capped solid tile (scripts/world/secret_view.gd), so the coursing
# of the real wall shows through everywhere the tell does not.
#
# The tell is a mason's, because architecture is the subject: a doorway that
# was bricked up. Coursed ashlar never lets a vertical joint run through two
# courses; an opening filled in afterwards always does, down both jambs, and
# the fill is laid in smaller stones whose beds do not line up with the wall's.
# Nobody needs to be told that. They need to have seen it once, and the first
# secret in the Sun Terrace sits where the player is already looking.
#
# Cracked fill (the kind a sword opens) adds a stepped crack along the fill's
# own joints, which is how a real infill fails. The tones are the wall's own:
# a straight joint is INK like every bed joint, the fill's lips are the wall's
# lip colour, and nothing here is brighter than the stone around it.

SEAL_JAMB_L = 1
SEAL_JAMB_R = 14
SEAL_CROWN_CX = 7.5
SEAL_CROWN_CY = 8.0
SEAL_CROWN_R = 7.2


def _seal_inside(x: int, y: int, top: bool) -> bool:
    """True for a pixel of the filled opening, jambs excluded."""
    if not (SEAL_JAMB_L < x < SEAL_JAMB_R):
        return False
    if not top or y + 0.5 >= SEAL_CROWN_CY:
        return True
    dx = x + 0.5 - SEAL_CROWN_CX
    dy = y + 0.5 - SEAL_CROWN_CY
    return dx * dx + dy * dy <= (SEAL_CROWN_R - 0.6) ** 2


def _seal_fill(p: Patch, top: bool) -> None:
    """The fill: courses half the wall's height, offset so no bed lines up,
    framed by straight joints down both jambs and, on the upper cell, a
    round crown where the old arch was."""
    for y in range(TILE):
        for x in range(TILE):
            if not _seal_inside(x, y, top):
                continue
            # Courses of five against the wall's eight, so a bed of the fill
            # only meets a bed of the wall once in forty rows.
            row = (y + 3) % 5
            course = (y + 3) // 5
            if row == 4:
                p.set(x, y, SHADOW_PIT)
            elif row == 0:
                p.set(x, y, SHADOW)
            elif x in ((4, 9) if course % 2 == 0 else (6, 11)):
                p.set(x, y, SHADOW_PIT)
            else:
                p.set(x, y, SHADOW_DEEP)
    for y in range(TILE):
        for x in range(TILE):
            if _seal_inside(x, y, top):
                continue
            # The joint that frames the fill: any pixel touching it.
            if any(_seal_inside(x + dx, y + dy, top)
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                p.set(x, y, INK)


# The crack in the frame of the whole doorway: the upper cell is rows 0-15,
# the lower one 16-31. It starts under the crown and steps down the fill's
# own joints, which is how a real infill fails.
SEAL_CRACK = [(6, 6), (6, 7), (7, 8), (7, 9), (7, 10), (8, 11), (8, 12),
              (8, 13), (9, 14), (9, 15), (8, 16), (8, 17), (8, 18), (9, 19),
              (9, 20), (9, 21), (8, 22), (8, 23), (7, 24), (7, 25), (8, 26),
              (8, 27), (9, 28), (9, 29), (10, 30), (10, 31)]


def _seal_crack(p: Patch, first_row: int) -> None:
    """The part of SEAL_CRACK that falls in this cell, its lower-right lip
    catching the sun."""
    points = [(x, y - first_row) for x, y in SEAL_CRACK
              if first_row <= y < first_row + TILE]
    for x, y in points:
        p.set(x, y, INK)
    for x, y in points:
        if (x + 1, y) not in points:
            p.set(x + 1, y, SHADOW)


def seal_top(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    _seal_fill(p, True)
    return p


def seal_foot(_unused=None) -> Patch:
    p = Patch(TILE, TILE)
    _seal_fill(p, False)
    return p


def crack_top(_unused=None) -> Patch:
    p = seal_top()
    _seal_crack(p, 0)
    return p


def crack_foot(_unused=None) -> Patch:
    p = seal_foot()
    _seal_crack(p, TILE)
    return p


def crack_cap(_unused=None) -> Patch:
    """A floor that will not take a fall: a hairline across the gold cap, one
    tone down rather than black. It enters and leaves at the same height on
    both edges, so a cracked floor two cells wide reads as one seam rather than
    a stamp repeated, and it drops through the bevel in one place, where the
    slab has settled a pixel. From above it is a seam in the light."""
    p = Patch(TILE, TILE)
    path = [(0, 1), (1, 1), (2, 1), (3, 2), (4, 2), (5, 1), (6, 1), (7, 2),
            (8, 2), (9, 3), (10, 2), (11, 2), (12, 1), (13, 1), (14, 1), (15, 1)]
    for x, y in path:
        p.set(x, y, MID)
    p.set(9, CAP_LIGHT + 1, SHADOW_DEEP)
    p.set(9, CAP_LIGHT + 2, INK)
    return p


# --- atlas layout ---------------------------------------------------------
# Keep in sync with scripts/world/tiles.gd.

NAMES = [
    # row 0 -- terrain the player touches, then the mid-ground architecture
    "solid_capped", "solid_capped_lit", "solid_buried", "solid_buried_lit",
    "platform", "spikes", "water", "ladder",
    "backdrop", "cornice", "balustrade", "column_shaft",
    "column_cap", "column_base", "planter", "niche",
    # row 1 -- the arch, the set pieces, then the foreground plane
    "arch_top_l", "arch_top_r", "arch_mid_l", "arch_mid_r",
    "arch_leg_l", "arch_leg_r", "fountain_l", "fountain_r",
    "frieze", "banner", "fore_rail", "fore_column",
    "fore_soffit_l", "fore_soffit_r", "fore_cloth", "fore_cloth_tail",
    # row 2 -- wear, growth and the things people leave about
    "crack", "worn", "ivy_top", "ivy",
    "ivy_end", "moss", "window", "urn",
    "jars", "rubble", "grass", "planter_bloom",
    "palm_top", "palm_pot", "lantern", "balustrade_rug",
    # row 3 -- the tells of a secret: a bricked-up doorway, whole and cracked
    "seal_top", "seal_foot", "crack_top", "crack_foot",
    "crack_cap",
]


def build_patches() -> dict:
    sheet = arch_sheet()
    basin = fountain_sheet()
    soffit = fore_soffit()
    palm = palm_sheet()
    out = {
        "solid_capped": solid(True, False),
        "solid_capped_lit": solid(True, True),
        "solid_buried": solid(False, False),
        "solid_buried_lit": solid(False, True),
        "platform": platform(),
        "spikes": spikes(),
        "water": water(),
        "ladder": ladder(),
        "backdrop": backdrop(),
        "cornice": cornice(),
        "balustrade": balustrade(),
        "column_shaft": column_shaft(),
        "column_cap": column_cap(),
        "column_base": column_base(),
        "planter": planter(),
        "niche": niche(),
        "fountain_l": basin.sub(0, 0, TILE, TILE),
        "fountain_r": basin.sub(TILE, 0, TILE, TILE),
        "frieze": frieze(),
        "banner": banner(),
        "fore_rail": fore_rail(),
        "fore_column": fore_column(),
        "fore_soffit_l": soffit,
        "fore_soffit_r": soffit.mirror(),
        "fore_cloth": fore_cloth(),
        "fore_cloth_tail": fore_cloth_tail(),
        "crack": crack(),
        "worn": worn(),
        "ivy_top": ivy_top(),
        "ivy": ivy(),
        "ivy_end": ivy_end(),
        "moss": moss(),
        "window": window(),
        "urn": urn(),
        "jars": jars(),
        "rubble": rubble(),
        "grass": grass(),
        "planter_bloom": planter_bloom(),
        "palm_top": palm.sub(0, 0, TILE, TILE),
        "palm_pot": palm.sub(0, TILE, TILE, TILE),
        "lantern": lantern(),
        "balustrade_rug": balustrade_rug(),
        "seal_top": seal_top(),
        "seal_foot": seal_foot(),
        "crack_top": crack_top(),
        "crack_foot": crack_foot(),
        "crack_cap": crack_cap(),
    }
    for i, part in enumerate(("arch_top_l", "arch_top_r", "arch_mid_l",
                              "arch_mid_r", "arch_leg_l", "arch_leg_r")):
        out[part] = sheet.sub((i % 2) * TILE, (i // 2) * TILE, TILE, TILE)
    return out


def main() -> None:
    patches = build_patches()
    missing = [n for n in NAMES if n not in patches]
    if missing:
        raise SystemExit("no painter for %s" % ", ".join(missing))

    image = Image.new("RGBA", (COLUMNS * TILE, ROWS * TILE), CLEAR)
    unknown = set()

    for index, name in enumerate(NAMES):
        ox, oy = (index % COLUMNS) * TILE, (index // COLUMNS) * TILE
        patch = patches[name]
        for y in range(TILE):
            for x in range(TILE):
                c = patch.get(x, y)
                image.putpixel((ox + x, oy + y), c)
                shade = SHADE_MAP.get(c)
                if shade is None:
                    unknown.add(c)
                    shade = c
                image.putpixel((ox + x, oy + y + SHADE_ROW_OFFSET * TILE), shade)

    if unknown:
        raise SystemExit(
            "colours with no SHADE_MAP entry (the shade half would be wrong): %s"
            % ", ".join("#%02x%02x%02x" % c[:3] for c in sorted(unknown))
        )

    out = pathlib.Path(__file__).resolve().parent.parent / "assets" / "tiles.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    print("wrote %s (%dx%d, %d tiles + %d shade twins)"
          % (out, image.width, image.height, len(NAMES), len(NAMES)))


if __name__ == "__main__":
    main()
