class_name Foe
extends CharacterBody2D
## The contract between an enemy and the game that referees it.
##
## `Game` resolves every foe through this class and nothing else: a guard, an
## archer and a boss are told apart by what they answer here, never by a
## branch on their type. A new foe is a file that extends this and one line
## in the entity registry (docs/architecture.md, "Adding a foe").
##
## ## What the game asks, every playing frame
##
## - `target_rect` is written first: the prince's body, or an empty rect when
##   he is dead. A foe never reaches for the Player; that is what lets a test
##   hand one a rectangle and step it with no scene at all.
## - Nothing more of a foe that is not `is_alive()`. A dying body is scenery.
## - **The blade.** The sword's live rect against `hurt_rect()`, once per
##   swing per foe: the rect stays live for about eight frames and the pass
##   runs on each, so without that memory one swing would spend every heart
##   (tests/unit/test_one_swing.gd). A swing is `Blow.SWORD`, a plunge
##   `Blow.PLUNGE`, and the plunge springs the prince back off whatever it hit.
## - **The stomp.** Falling onto `bounds()` from above is `Blow.STOMP`, and
##   bounces him -- unless the foe answers `Outcome.NONE`, in which case it
##   was never a stomp and the foe's dangers are checked instead.
## - **The danger.** While `is_dangerous()`, each of `dangers()` against his
##   body, first one that touches him wins: parried, evaded or landed
##   (scripts/entities/foe_danger.gd). Touching a foe that is not dangerous
##   is free -- danger has one look, and the guard argues why at length
##   (scripts/entities/patrol.gd).
##
## ## What a blow did
##
## `take_blow()` answers with an `Outcome`, and Game presents it: a wound or a
## kill gets the wound sound and the impact (held frames, shake, sparks), a
## block gets steel on steel and no wound, `NONE` gets nothing. The default
## takes every blow as a wound through `hit()`, which is all the guard needs;
## a shield-bearer overrides it to turn a sword from the front.
##
## ## Down stays down
##
## `post` is set from the mark the foe was placed from, and stays the same
## across a restart and a checkpoint respawn. When `defeated` fires, Game
## remembers the post, and a respawn puts back every foe whose post is not
## remembered -- so a guard cut down stays down and one still standing goes
## back to where he was posted. A foe made at runtime (a boss's summons,
## `summon()`) has no post: never remembered, never put back.
##
## ## Presentation goes through Game
##
## A foe makes no sound and moves no camera of its own. It asks: `cue` for a
## sound, which Game plays through GameAudio.cue -- audio's one front door --
## and `impact` for a beat of weight, which Game spends from the same hitstop
## budget as every other impact (docs/feel.md). Hitstop is for things that
## resist the prince; a foe asking for one on its own initiative should think
## twice.
##
## ## Warnings are read through warn()
##
## Every tell a foe gives -- a raise, a draw, a crouch before a pounce -- and
## every timed window that stands between the prince and a death is read as
## `warn(seconds)`, never as the bare constant. That is the LONGER WARNINGS
## assist (scripts/core/assist.gd): off, warn() is the number it was given;
## on, it is longer by the one factor the player chose. A foe that compares a
## tell against its own constant has forgotten the assist, so the contract
## test for a new foe should drive its tell with the assist on, as
## tests/unit/test_longer_warnings.gd does the sentinel's raise. The cut, the
## opening after it and everything else a foe does keep their own timing.
##
## ## Projectiles
##
## `launch()` looses a FoeProjectile: Game adopts it into the level's
## entities, where it is frozen in a hitstop with everything else, cleared by
## a restart or a respawn, and met by the prince like any other danger -- with
## a parry that sends it back (scripts/entities/foe_projectile.gd).

## The killing blow landed.
signal defeated()
## A sound this foe wants heard.
signal cue(voice: StringName, options: Dictionary)
## A beat of weight this foe causes: Game._impact(), from the same budget.
signal impact(at: Vector2, frames: int, shake: float, weight: float)
## A projectile loosed: Game adopts it.
signal launched(projectile: FoeProjectile)
## A foe made at runtime -- a boss's summons: Game adopts it, without a post.
signal summoned(foe: Foe)

## How the prince reached it. SHOT is one of a foe's own projectiles, sent back
## by a parry.
enum Blow { SWORD, PLUNGE, STOMP, SHOT }
## What a blow did. NONE: it passed through, or there was nothing to hit.
enum Outcome { NONE, BLOCKED, WOUNDED, KILLED }

## Every foe joins this group, so whatever needs to know whether one is about
## -- the prince's idle, for one -- asks the tree instead of being handed a
## list by the scene that spawned them.
const GROUP := &"foes"

var level: Level
## Stable across restarts and respawns; empty for a foe made at runtime.
var post := ""
## The prince's body this frame, or an empty rect when there is nobody to
## fight. Game writes it every physics frame.
var target_rect := Rect2()


## On no collision layer, so the prince's body passes through and every
## meeting is the referee's, by rectangles; standing on the terrain's two
## layers, like him. Lit: a level's hour never dims a foe, because a tell that
## dims is a death that cannot be read (WorldGrade).
func _ready() -> void:
	collision_layer = 0
	collision_mask = Tiles.MASK_SOLID | Tiles.MASK_ONE_WAY
	add_to_group(GROUP)
	add_to_group(MatchDusk.LIT)


## --- the contract -----------------------------------------------------------

## The body, in world units: what a stomp lands on. Override it.
func bounds() -> Rect2:
	return Rect2()


## Where a blade wounds it. The body, unless a foe says otherwise.
func hurt_rect() -> Rect2:
	return bounds()


## False from the killing blow on.
func is_alive() -> bool:
	return true


## True while any of `dangers()` can hurt.
func is_dangerous() -> bool:
	return false


## In a fight: raising, striking or recovering. Holds the prince's idle from
## anywhere in the level. Dangerous, unless a foe says more.
func is_engaged() -> bool:
	return is_dangerous()


## What can hurt the prince this frame. Asked only while `is_dangerous()`.
func dangers() -> Array[FoeDanger]:
	return []


## One wound from `from_x`. True when it killed. Override it.
func hit(_from_x: float) -> bool:
	return false


## A blow from the prince landed on it. Every blow is a wound by default.
func take_blow(_blow: Blow, from_x: float) -> Outcome:
	if not is_alive():
		return Outcome.NONE
	return Outcome.KILLED if hit(from_x) else Outcome.WOUNDED


## The sound of a wound. Played through Game, pitched per blow.
func wound_voice() -> StringName:
	return &"guard_hit"


## Where the sparks go when it is plunged into: the top of its body.
func impact_point() -> Vector2:
	return Vector2(global_position.x, bounds().position.y)


## Heavy enough that its feet hold a plate down and a lift counts it as a
## rider: a guard, a Bastion, a Glassbearer. A cat or an owl is too light and
## answers false (docs/campaign.md, "Counterweights").
func has_weight() -> bool:
	return true


## --- the entity protocol (scripts/entities/entity_registry.gd) ---------------

## How long a warning of `seconds` lasts: a tell, or a window that guards a
## death. The one way a foe reads one (above).
func warn(seconds: float) -> float:
	return seconds * Assist.warning_scale()


func place(site: EntitySite) -> void:
	position = site.at
	level = site.level
	post = site.post


## Straight back to Game, which referees the meeting against this contract.
func meet(contact: Contact) -> void:
	contact.meet_foe(self)


## Looses `projectile`: it is the game's from here on.
func launch(projectile: FoeProjectile) -> void:
	projectile.source = self
	projectile.level = level
	launched.emit(projectile)


## Brings `foe` into the level, positioned by the caller. It is refereed like
## any other, but it has no post: a respawn clears it and does not bring it
## back, and nothing remembers it was cut down.
func summon(foe: Foe) -> void:
	foe.level = level
	foe.post = ""
	summoned.emit(foe)
