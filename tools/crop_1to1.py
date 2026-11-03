#!/usr/bin/env python3
"""Cut a 1:1 crop out of a 4x screenshot, so type can be judged at real size.

A 1280x720 shot of this game is a four-times magnification of a 320x180
canvas. Looking at it is not looking at the game; this downsamples back to
canvas units with nearest-neighbour and, optionally, re-magnifies by a whole
number so the pixel grid is visible without being interpolated.

    python3 tools/crop_1to1.py shot.png out.png [--rect x,y,w,h] [--zoom 4]

The rect is in canvas units.
"""
from __future__ import annotations

import argparse

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("out")
    parser.add_argument("--rect", default="")
    parser.add_argument("--zoom", type=int, default=1)
    parser.add_argument("--height", type=int, default=180,
                        help="canvas height the shot was rendered at")
    args = parser.parse_args()

    image = Image.open(args.source).convert("RGBA")
    factor = image.size[1] // args.height
    canvas = image.resize(
        (image.size[0] // factor, image.size[1] // factor), Image.NEAREST
    )
    if args.rect:
        x, y, w, h = (int(part) for part in args.rect.split(","))
        canvas = canvas.crop((x, y, x + w, y + h))
    if args.zoom > 1:
        canvas = canvas.resize(
            (canvas.size[0] * args.zoom, canvas.size[1] * args.zoom), Image.NEAREST
        )
    canvas.save(args.out)
    print("%s -> %s %dx%d" % (args.source, args.out, canvas.size[0], canvas.size[1]))


if __name__ == "__main__":
    main()
