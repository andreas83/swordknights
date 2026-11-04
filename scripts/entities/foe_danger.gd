class_name FoeDanger
extends RefCounted
## One way a foe can hurt the prince on this frame: a rectangle, the side the
## blow comes from, and what happens when he turns it aside.
##
## Game resolves every danger the same way, whatever made it -- a guard's cut,
## a boss's sweep, an arrow in flight (Game._resolve_danger()):
##
## 1. **Parried** -- the prince's parry is up and he faces `from_x`
##    (Player.deflect), and `parry` says the blow could be turned. Steel meets
##    steel: Game's clang, and whatever `parry` did to the blow.
## 2. **Evaded** -- a backstep's window is open and he faces `from_x`
##    (Player.evades), and the danger is `evadable`. Nothing happens to anyone;
##    the blow that did not land is the read.
## 3. **Rolled under** -- a roll is tucked (Player.rolls_under), from either
##    side, and the danger is `rollable`. Nothing happens to anyone; he comes
##    up on the far side of it.
## 4. **Landed** -- `damage` hearts through Player.damage(), which refuses it
##    in his grace after a hit, and `landed` hears whether it was dealt.
##
## A danger that has no `parry` cannot be parried: a raised sword is simply
## hit. That is a design lever, not an omission -- a falling block, a fire, a
## boss's slam can each say so in one line.
##
## A danger with no `damage` and a `push` is a **shove**: landed, it throws
## the prince back at `push` (away from `from_x`) and staggers him for
## `stagger` seconds, and costs no heart and grants no grace -- a Bastion's
## shield, a wall that pushes back (Player.shove()). Without a push, a
## danger with no damage does nothing at all.

## Where the blow is, in world units.
var rect := Rect2()
## The x the blow comes from. The parry and the backstep both read the
## prince's facing against it, so a cut from behind goes round a raised guard.
var from_x := 0.0
## Hearts it takes when it lands.
var damage := 1
## Whether a backstep's window lets it by.
var evadable := true
## Whether a roll's tuck lets it by, from the front or from behind. True by
## default, as `evadable` is, because the default danger is a blade or a
## shield set against a standing man, and a body tucked at the floor goes
## under either -- a sentinel's cut, a Bastion's face and his shove. False
## for what is aimed at where he is rather than where a man stands: a body
## coming down on him (a pounce, the King's slam) and anything in flight,
## which a roll passes only by being lower than it (FoeProjectile.danger()).
var rollable := true
## For a shove (`damage` 0): the velocity it throws him at, x away from
## `from_x`, and how long he reels.
var push := Vector2.ZERO
var stagger := 0.32
## `() -> bool`: the blow met a parry; true when it was turned. Unbound, it
## cannot be parried.
var parry := Callable()
## `(dealt: bool) -> void`: it reached the prince. `dealt` is false when his
## grace refused the damage. A projectile is spent here.
var on_landed := Callable()


static func make(at: Rect2, from: float, hearts: int = 1) -> FoeDanger:
	var danger := FoeDanger.new()
	danger.rect = at
	danger.from_x = from
	danger.damage = hearts
	return danger


func can_be_parried() -> bool:
	return parry.is_valid()


## The prince's parry met it. True when the blow was turned.
func parried() -> bool:
	return parry.is_valid() and bool(parry.call())


func landed(dealt: bool) -> void:
	if on_landed.is_valid():
		on_landed.call(dealt)
