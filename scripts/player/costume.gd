class_name Costume
extends RefCounted
## What a figure wears over the shared skeleton. This base class is the prince,
## and it draws nothing: his hood, robe, sash and cloak are PlayerArt's own
## drawing helpers, exactly as they were before there was a second figure.
##
## ## Why a costume layer and not a second PlayerArt
##
## PlayerArt does three jobs: it turns a state into a **pose** (`_posture()`),
## turns the pose into a **rig** of points (`_rig()`), and draws **planes** on
## that rig. Only the third job differs between the prince and the heroine.
## Everything that makes a pose read -- the lean, the stride, the arm angles,
## the sword's arc, the squash on a landing -- lives in the first two, and a
## pose added to player_art.gd has to reach every figure without anyone
## remembering to copy it. A forked HeroineArt would have drifted from the
## first new pose on; a FighterArt for each figure would have doubled again.
##
## So a costume replaces whole layers of the drawing and nothing else:
##
##     back   behind the legs        the prince's cloak
##     body   over the legs and arm  the prince's robe and sash
##     head   over everything        the prince's hood
##
## and two more for the limbs, one call per leg and per arm:
##
##     leg    behind the robe        the prince's tapered legs and boots
##     arm    back one behind, front one over the body
##
## The robed figures leave the limbs to PlayerArt, because the limbs are where
## the pose is legible and they do not change with the clothes. A figure whose
## *build* differs -- the stick avatar's lines, the 3D model's volumes -- has
## to replace them too, and it still bends them at PlayerArt's own joints. The
## sword, the ledge grip and the contact shadow stay shared by every figure:
## the duel's sword is drawn along the rect the simulation fights with, and no
## costume may move that. Each `draw_*` returns true when it has drawn that
## layer and false to leave it to PlayerArt -- which is how this base class is
## the prince without a line of drawing.
##
## A costume reads the rig PlayerArt has just built, through PlayerArt's own
## underscore fields and helpers. They are underscore-named because nothing
## *outside the drawing* should read them; a costume is the drawing, split into
## a file per figure. A pose field a new layer needs is added to `_pose()` and
## read here, the same rule as for PlayerArt's own helpers: never special-case
## a state inside a layer.
##
## A costume may keep cosmetic state for its own secondary motion (the
## heroine's braid does). `tick()` runs from PlayerArt._process, never from
## physics, so like the cloth lag it is presentation that a replay or a network
## peer is free to draw differently.

## How many frames this costume has drawn, and the box around what it drew on
## the last one, in the art node's space. A test reads them to prove a layer
## was drawn rather than assuming it; nothing in the game does.
var frames_drawn := 0
var drawn := Rect2()


## Called once per rendered frame, before the frame is drawn.
func tick(_art: PlayerArt, _delta: float) -> void:
	pass


## The first layer of every frame, so the base class counts frames here too:
## the prince's are drawn by PlayerArt, but they are still frames drawn.
func draw_back(_art: PlayerArt, _pose: Dictionary) -> bool:
	frames_drawn += 1
	return false


func draw_body(_art: PlayerArt, _pose: Dictionary) -> bool:
	return false


func draw_head(_art: PlayerArt, _pose: Dictionary) -> bool:
	return false


## One leg, hip to `knee` to `foot`; `back` is the far one.
func draw_leg(_art: PlayerArt, _knee: Vector2, _foot: Vector2, _back: bool) -> bool:
	return false


## One arm, shoulder to `hand`; `back` is the far one.
func draw_arm(_art: PlayerArt, _hand: Vector2, _back: bool) -> bool:
	return false


## Called when the figure changes into another costume, so one that hung
## nodes on the art takes them away with it.
func take_off(_art: PlayerArt) -> void:
	pass


## What the sword is drawn in, for a figure whose blade is its own: any of
## "steel", "edge", "edge_hot", "guard" and "glow". Missing keys are the
## shared sword's colours; "glow", when given, is a halo drawn round the blade.
## Only colours: the blade's shape and reach are the pose's and, in the duel,
## the simulation's.
func blade_colours() -> Dictionary:
	return {}


## The colours a player chose for this costume beyond the accent, so the duel
## can hold every one of them clear of both teams' colours
## (tests/unit/test_duel_seats_distinct.gd).
func worn_colours() -> Array[Color]:
	return []
