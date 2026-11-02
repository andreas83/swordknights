#!/usr/bin/env python3
"""Assemble the pose frames from tests/character_poses.gd into a contact sheet.

    python3 tests/character_contact_sheet.py docs/character-states.png \
        after=/tmp/poses/after before=/tmp/poses/before

Each named directory becomes a block of labelled cells. A cell shows the pose
at the 4x window scale next to a 1:1 inset, because the only honest test of
this art is whether it reads at the size it is actually drawn.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# The pose harness pins the character's feet here, in 320x180 virtual units.
FEET = (160.0, 124.0)
SCALE = 4  # window override / viewport
CROP = (-26.0, -36.0, 26.0, 8.0)  # left, top, right, bottom, around the feet

COLUMNS = 4
PAD = 10
LABEL_H = 16
BG = (43, 10, 20)
FG = (255, 244, 194)
DIM = (242, 168, 41)


def _font(size: int) -> ImageFont.ImageFont:
    for name in (
        "DejaVuSansMono-Bold.ttf",
        "DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def crop_pose(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGB")
    box = (
        int((FEET[0] + CROP[0]) * SCALE),
        int((FEET[1] + CROP[1]) * SCALE),
        int((FEET[0] + CROP[2]) * SCALE),
        int((FEET[1] + CROP[3]) * SCALE),
    )
    return image.crop(box)


def pose_name(path: Path) -> str:
    stem = path.stem
    return stem.split("_", 1)[1] if "_" in stem else stem


def build_block(directory: Path, title: str, font: ImageFont.ImageFont,
                small: ImageFont.ImageFont) -> Image.Image:
    frames = sorted(directory.glob("*.png"))
    if not frames:
        raise SystemExit(f"no frames in {directory}")

    cells = [(pose_name(p), crop_pose(p)) for p in frames]
    cw, ch = cells[0][1].size
    rows = (len(cells) + COLUMNS - 1) // COLUMNS

    width = COLUMNS * (cw + PAD) + PAD
    height = LABEL_H + 10 + rows * (ch + LABEL_H + PAD) + PAD
    block = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(block)
    draw.text((PAD, 4), title.upper(), font=font, fill=FG)

    for index, (name, cell) in enumerate(cells):
        col, row = index % COLUMNS, index // COLUMNS
        x = PAD + col * (cw + PAD)
        y = LABEL_H + 10 + row * (ch + LABEL_H + PAD)
        block.paste(cell, (x, y))
        # 1:1 inset — the size a phone actually shows.
        native = cell.resize((cw // SCALE, ch // SCALE), Image.NEAREST)
        block.paste(native, (x + cw - native.width - 2, y + 2))
        draw.rectangle(
            [x + cw - native.width - 3, y + 1, x + cw - 2, y + native.height + 2],
            outline=DIM,
        )
        draw.text((x + 1, y + ch + 2), name, font=small, fill=DIM)

    return block


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2

    out = Path(argv[1])
    font, small = _font(14), _font(11)

    blocks = []
    for spec in argv[2:]:
        title, _, path = spec.partition("=")
        if not path:
            title, path = Path(spec).name, spec
        blocks.append(build_block(Path(path), title, font, small))

    width = max(b.width for b in blocks)
    height = sum(b.height for b in blocks) + PAD * (len(blocks) - 1)
    sheet = Image.new("RGB", (width, height), BG)
    y = 0
    for block in blocks:
        sheet.paste(block, (0, y))
        y += block.height + PAD

    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"wrote {out} ({sheet.width}x{sheet.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
