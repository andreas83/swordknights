#!/usr/bin/env bash
#
# Re-render every image on the site from the game itself.
#
# Usage, from the repository root:
#   site/render_images.sh
#
# Needs godot 4.5.1, xvfb-run and Python with Pillow. Run
# `godot --headless --path . --import` once first on a fresh clone.
#
# The screenshots are committed rather than rendered in the Pages workflow on
# purpose: each one is looked at before it goes on the page, and a frame that
# a gameplay change has quietly broken (a title card over the hero, a duellist
# already dead at the moment of capture) should be caught by a person, not
# published by a robot. So this is the reproducible recipe, and the output is
# reviewed in the diff like any other change.
#
# Every frame is rendered at 1920x1080 -- six screen pixels per world unit on
# a 180-unit viewport -- and halved with a box filter for the 960-wide variant.
# Halving a 6-pixel block gives an exact 3-pixel block, so the pixel art stays
# hard-edged while the HUD's smooth lettering gets ordinary antialiasing.

set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-godot}"
OUT=site/public/img
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

shoot() {
	local name="$1" scene="$2" at="$3"
	shift 3
	xvfb-run -a "$GODOT" --path . --rendering-driver opengl3 --resolution 1920x1080 \
		--script tools/screenshot.gd -- \
		--scene "$scene" --out "$work/$name" --shots "$at" "$@" >"$work/$name.log" 2>&1 ||
		{ cat "$work/$name.log"; exit 1; }
	test -s "$work/$name/00.png" || { echo "no frame for $name" >&2; exit 1; }
	mv "$work/$name/00.png" "$work/$name.png"
}

# The lit terrace of level one, after its title card has faded, before any
# input: the figure, the long shadows, the arches.
shoot terrace res://scenes/game.tscn 6.0
# The title screen and the mode list.
shoot menu res://scenes/menu.tscn 2.5
# The tug of war's attract mode, both duellists still standing in the middle
# zone. Later in the demo one of them is already dead.
shoot duel res://scenes/duel_match.tscn 2.0 --demo

mkdir -p "$OUT"
python3 - "$work" "$OUT" <<'PY'
import sys
from pathlib import Path

from PIL import Image

work, out = Path(sys.argv[1]), Path(sys.argv[2])

for name in ("terrace", "menu", "duel"):
    full = Image.open(work / f"{name}.png").convert("RGB")
    full.save(out / f"{name}-1920.webp", lossless=True, method=6)
    full.reduce(2).save(out / f"{name}-960.webp", lossless=True, method=6)

# The duel's pose sheet is already rendered for docs/character.md by
# tests/fighter_poses.gd; the site carries a copy rather than a link into docs/.
Image.open("docs/fighter-poses.png").convert("RGB").save(
    out / "fighter-poses.webp", lossless=True, method=6
)

# Link previews in chat apps want a PNG at roughly 1.91:1. Cropped from the
# terrace below the HUD, so the figure and the arches stay in frame.
terrace = Image.open(work / "terrace.png").convert("RGB")
card = terrace.crop((0, 100, 1872, 1080)).resize((1200, 628), Image.BOX)
card.quantize(colors=64, method=Image.Quantize.MEDIANCUT).save(out / "card.png", optimize=True)
PY

python3 site/wordmark.py SWORDKNIGHTS >"$OUT/wordmark.svg"

ls -l "$OUT"
