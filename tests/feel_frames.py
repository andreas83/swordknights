#!/usr/bin/env python3
"""Assemble docs/feel-frames.png from the frames tests/feel_frames.gd renders.

A hitstop and a wipe are timing, not composition: a single screenshot of
either says nothing. So this lays the frames out in a strip with the frame
number and the elapsed milliseconds under each one, and marks the frames that
are *identical to the one before them* — which is what a held frame is, and
the only honest way to show one on paper.

    xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 60 \
      --script tests/feel_frames.gd -- --out /tmp/feel
    python3 tests/feel_frames.py /tmp/feel docs/feel-frames.png

Colours come from scripts/core/palette.gd. Nothing here is generated at build
time; the PNG is committed, as docs/character-states.png is.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

# scripts/core/palette.gd
INK = (0x2B, 0x0A, 0x14)
SHADOW_DEEP = (0x7A, 0x12, 0x30)
LIGHT = (0xF7, 0xCE, 0x2E)
LIGHT_SOFT = (0xFF, 0xE8, 0x73)
PAPER = (0xFF, 0xF4, 0xC2)

CELL = (320, 180)
GAP = 10
MARGIN = 26
CAPTION_H = 34
HEADER_H = 46
ROW_GAP = 16
FRAME_MS = 1000.0 / 60.0
# Below this share of changed pixels a frame is the same frame again.
HELD_THRESHOLD = 0.05

FONT_DIR = Path("/usr/share/fonts/truetype/dejavu")

# label, heading, note, frames to show, crop box in 320x180 space (or None for
# the whole frame). The impact row is cropped because the beat is four frames
# of two figures not moving, and at 320x180 the two figures are forty pixels
# wide between them.
ROWS = [
    (
        "reveal",
        "MENU → LEVEL",
        "The shadow lifts off the scene. One hard raked edge, a lit rim, no fade.",
        [4, 6, 8, 10, 12, 14, 16],
        None,
    ),
    (
        "impact",
        "SWORD CONNECTS",
        "Four frames of frozen simulation. Nothing moves, then everything does.",
        [17, 19, 20, 21, 22, 23, 26],
        (30, 44, 150, 112),
    ),
    (
        "retry",
        "DEATH → RESPAWN",
        "A beat you can read, then the respawn behind the cover. Half a second.",
        [2, 8, 16, 23, 28, 33, 38],
        None,
    ),
]


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(str(FONT_DIR / name), size)
    except OSError:
        return ImageFont.load_default()


def changed_share(image: Image.Image, previous: Image.Image | None) -> float:
    """Percentage of pixels that differ from the frame before."""
    if previous is None:
        return 100.0
    diff = ImageChops.difference(image, previous).convert("L")
    changed = sum(count for value, count in enumerate(diff.histogram()) if value > 6)
    return changed / float(image.width * image.height) * 100.0


def load_beat(
    source: Path, label: str, crop: tuple[int, int, int, int] | None
) -> dict[int, tuple[Image.Image, float]]:
    """Every captured frame of one beat, each with how much it changed.

    The change is measured on the whole frame even when the cell is cropped:
    "nothing in this frame moved" is a claim about the frame, not about the
    part of it that happens to be in shot.
    """
    frames: dict[int, tuple[Image.Image, float]] = {}
    previous: Image.Image | None = None
    for path in sorted(source.glob(f"{label}-*.png")):
        index = int(path.stem.split("-")[-1])
        image = Image.open(path).convert("RGB")
        # The capture is an integer multiple of the 320x180 design viewport, so
        # NEAREST hands the original pixels back rather than resampling them.
        cell = image.resize(CELL, Image.NEAREST)
        if crop is not None:
            cell = cell.crop(crop).resize(CELL, Image.NEAREST)
        frames[index] = (cell, changed_share(image, previous))
        previous = image
    return frames


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    source = Path(sys.argv[1])
    target = Path(sys.argv[2])

    beats = [
        (title, note, picks, load_beat(source, label, crop))
        for label, title, note, picks, crop in ROWS
    ]
    missing = [title for title, _, _, frames in beats if not frames]
    if missing:
        print(f"no frames for: {', '.join(missing)} (looked in {source})", file=sys.stderr)
        return 1

    columns = max(len(picks) for _, _, picks, _ in beats)
    width = MARGIN * 2 + columns * CELL[0] + (columns - 1) * GAP
    row_h = HEADER_H + CELL[1] + CAPTION_H
    height = MARGIN * 2 + len(beats) * row_h + (len(beats) - 1) * ROW_GAP + 30

    sheet = Image.new("RGB", (width, height), INK)
    draw = ImageDraw.Draw(sheet)

    title_font = font("DejaVuSans-Bold.ttf", 23)
    note_font = font("DejaVuSans.ttf", 16)
    caption_font = font("DejaVuSansMono.ttf", 14)
    held_font = font("DejaVuSansMono-Bold.ttf", 13)

    y = MARGIN
    for title, note, picks, frames in beats:
        draw.text((MARGIN, y), title, font=title_font, fill=PAPER)
        draw.text((MARGIN + 290, y + 4), note, font=note_font, fill=LIGHT_SOFT)
        top = y + HEADER_H

        first = picks[0]
        for column, index in enumerate(picks):
            if index not in frames:
                continue
            image, change = frames[index]
            x = MARGIN + column * (CELL[0] + GAP)
            sheet.paste(image, (x, top))

            held = change < HELD_THRESHOLD
            # A one-pixel rule under every frame; gold and three pixels under a
            # frame that is the frame before it over again.
            rule_h = 3 if held else 1
            draw.rectangle(
                [x, top + CELL[1], x + CELL[0] - 1, top + CELL[1] + rule_h - 1],
                fill=LIGHT if held else SHADOW_DEEP,
            )

            stamp = f"f{index - first:+03d}   {(index - first) * FRAME_MS:5.0f} ms"
            draw.text((x, top + CELL[1] + 9), stamp, font=caption_font, fill=LIGHT_SOFT)
            if held:
                draw.text(
                    (x + CELL[0] - 46, top + CELL[1] + 9), "HELD", font=held_font, fill=LIGHT
                )
        y = top + CELL[1] + CAPTION_H + ROW_GAP

    # The legend earns its line: the gold rule is the only thing in the sheet
    # that is measured rather than chosen.
    legend_y = height - MARGIN - 16
    draw.rectangle([MARGIN, legend_y + 7, MARGIN + 28, legend_y + 9], fill=LIGHT)
    draw.text(
        (MARGIN + 38, legend_y - 2),
        "identical to the frame before it  ·  60 Hz, every frame captured  ·  "
        "tests/feel_frames.gd + tests/feel_frames.py  ·  docs/feel.md",
        font=note_font,
        fill=LIGHT_SOFT,
    )

    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    print(f"wrote {target} ({sheet.width}x{sheet.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
