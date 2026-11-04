"""Stitches the frames tools/level_tour.gd wrote into one image of the level.

    python3 tools/level_tour.py <frames dir> <out.png> [--scale N]

Each frame is the camera's view round a centre on a grid. The camera keeps to
the level's bounds and has its own drag and offset, so the tool writes where
its view really was beside each frame, and this pastes each frame there.
The result is the level at N pixels per world unit (2 by default): every
pixel the game drew, hard-edged, so nothing is resampled but by whole steps.
"""

import os
import sys

from PIL import Image


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, out = sys.argv[1], sys.argv[2]
    scale = 2
    if "--scale" in sys.argv:
        scale = int(sys.argv[sys.argv.index("--scale") + 1])
    with open(os.path.join(src, "grid.txt"), encoding="utf-8") as handle:
        cols, rows, view_w, view_h, world_w, world_h = map(int, handle.read().split())
    sheet = Image.new("RGB", (world_w * scale, world_h * scale))
    for row in range(rows):
        for col in range(cols):
            frame = Image.open(os.path.join(src, "%02d_%02d.png" % (row, col))).convert("RGB")
            frame = frame.resize((view_w * scale, view_h * scale), Image.NEAREST)
            with open(os.path.join(src, "%02d_%02d.txt" % (row, col)), encoding="utf-8") as at:
                centre_x, centre_y = map(float, at.read().split())
            left = round((centre_x - view_w / 2) * scale)
            top = round((centre_y - view_h / 2) * scale)
            sheet.paste(frame, (left, top))
    sheet.save(out)
    print("level_tour: %s (%dx%d)" % (out, sheet.width, sheet.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
