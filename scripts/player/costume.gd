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
## Legs, arms, hands, the sword, the ledge grip and the contact shadow stay
## shared, because they are where the pose is legible and they do not change
## with the clothes. Each `draw_*` returns true when it has drawn that layer
## and false to leave it to PlayerArt -- which is how this base class is the
## prince without a line of drawing.
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
