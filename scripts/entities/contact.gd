class_name Contact
extends RefCounted
## The prince as the level's entities see him for one physics frame, and the
## short list of things an entity may ask the game to do about him.
##
## ## Why a contact and not the Player
##
## An entity holding the Player could do anything to him, and the question of
## what touching a thing *means* -- a heal, a checkpoint, a wound, the end of
## the level -- would be answered once per entity file. So `Game` hands every
## entity this instead, once a frame through `meet()`: the prince's
## rectangles and the few facts a trigger reads, plus a fixed vocabulary of
## consequences, each bound by Game to the one place its rule lives. A torch
## offers itself as a checkpoint and Game decides whether it is further on; a
## door says it was reached and Game ends the level.
##
## The consequences are Callables, so a test drives any entity with a contact
## it built itself: no scene, no prince, nothing else running.
##
## ## The vocabulary
##
## `harm(hearts, from_x)` is a mechanism's way to hurt him without being a
## foe. `reach_exit()` and `offer_checkpoint(at)` are the level's two goals.
## `reveal_secret(cell, at)` finds a secret for him, for a seal his body and
## blade cannot open -- the sun seal, which light opens. A
## relic's tally and heal ride on its own `collected` signal, which its
## `place()` wires to the site (scripts/entities/entity_site.gd) because a
## relic can be taken by more than the prince's body.
##
## `meet_foe(foe)` and `meet_shot(shot)` are double dispatch: a foe's `meet()`
## hands itself straight back, so the arbitration of a fight stays in Game,
## written once against the foe contract (scripts/entities/foe.gd), and Game's
## loop over the level's entities has no branch for any kind of thing in it.
##
## A new kind of entity that needs a consequence none of these give is the
## moment to add one here and in Game -- once, for every kind after it -- and
## never a branch for one kind.

## The prince's body, feet at the bottom edge.
var body := Rect2()
## The sword's live rectangle this frame, or an empty one.
var blade := Rect2()
## Where his feet are: `Player.position`.
var feet := Vector2.ZERO
var velocity := Vector2.ZERO
var facing := 1
var grounded := false
var alive := true
var plunging := false

## Bound by Game. Each is optional: an unbound consequence does nothing.
var exit_reached := Callable()
## `(at: Vector2) -> bool`: true when the checkpoint moved there.
var checkpoint_offered := Callable()
## `(foe: Foe) -> void`
var foe_met := Callable()
## `(shot: FoeProjectile) -> void`
var shot_met := Callable()
## `(hearts: int, from_x: float) -> bool`: true when the hurt was dealt.
var harmed := Callable()
## `(cell: Vector2i, at: Vector2) -> bool`: true when a secret was found.
var secret_revealed := Callable()


## The blade is out and live this frame.
func has_blade() -> bool:
	return blade.size.x > 0.0


## The prince reached a way out. Game ends the level after this frame's pass,
## so everything else he touched on the same frame is counted first.
func reach_exit() -> void:
	if exit_reached.is_valid():
		exit_reached.call()


## Offers `at` as the place a death comes back to. True when Game took it:
## further on than the checkpoint already held.
func offer_checkpoint(at: Vector2) -> bool:
	return checkpoint_offered.is_valid() and bool(checkpoint_offered.call(at))


## Hurts the prince by `hearts`, from the side `from_x` is on -- a crushing
## block, a trap's blade -- through the same Player.damage() a cut uses, with
## its grace and its held frames. True when it was dealt. Something that
## should kill outright is a hazard instead: Mechanism.set_kind(SPIKES).
func harm(hearts: int, from_x: float) -> bool:
	return harmed.is_valid() and bool(harmed.call(hearts, from_x))


## Finds the secret whose seal or room holds `cell`, as if the prince had
## found it at `at`: the count, the banner, the chime and the reveal, through
## the secret keeper. For a seal that something other than his body or his
## blade opens -- light, for a sun seal (scripts/mechanisms/sun_seal.gd). True
## when a secret was found now.
func reveal_secret(cell: Vector2i, at: Vector2) -> bool:
	return secret_revealed.is_valid() and bool(secret_revealed.call(cell, at))


func meet_foe(foe: Foe) -> void:
	if foe_met.is_valid():
		foe_met.call(foe)


func meet_shot(shot: FoeProjectile) -> void:
	if shot_met.is_valid():
		shot_met.call(shot)
