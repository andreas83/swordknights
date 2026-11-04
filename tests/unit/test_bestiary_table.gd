extends GutTest
## The bestiary's shared rules, one table over every foe the registry places
## (docs/campaign.md, "What every foe shares", and each foe's own table).
##
## Each foe has its own suite, and each pins its own row. What only a table
## can hold is that the rows agree: that a foe added next week answers every
## one of the prince's moves -- the sword, the plunge, the stomp, the thrown
## sword, the dive kick and the sweep; the parry, the backstep and the roll
## against its live window -- that it bleeds when it is cut down
## (scripts/world/bloodshed.gd hears the contract's `defeated`), and that
## every tell it has stretches under LONGER WARNINGS. A registered foe with
## no row here fails, so none can join the game without being placed in it.
##
## Read from the front, at rest, one fresh foe per cell: "wounds" means a
## WOUNDED or KILLED outcome; "no" means anything else (a clang, a stagger, a
## knock), which the foe's own suite says more about.

const FRONT := -20.0

## kind -> the row. `blows`: Foe.Blow -> wounds from the front at rest.
## `live`: the state whose danger is read, or -1 for one thrown (a bolt);
## `parry`, `backstep`, `roll`: what each does to that danger; `lesson`: the
## blow that kills it, `lesson_state` the state that blow is the lesson in;
## `tells`: the methods that read Foe.warn().
const TABLE := {
	"patrol": {
		"blows": {"SWORD": true, "PLUNGE": true, "STOMP": true, "THROWN": true,
			"KICK": false, "SWEEP": false},
		"live": "STRIKE", "parry": true, "backstep": true, "roll": true,
		"lesson": "SWORD", "tells": ["windup_time"],
	},
	"bastion": {
		"blows": {"SWORD": false, "PLUNGE": true, "STOMP": false, "THROWN": false,
			"KICK": false, "SWEEP": false},
		"live": "SHOVE", "parry": false, "backstep": true, "roll": true,
		"lesson": "PLUNGE", "tells": ["windup_time"],
	},
	"caracal": {
		"blows": {"SWORD": true, "PLUNGE": true, "STOMP": true, "THROWN": true,
			"KICK": false, "SWEEP": false},
		"live": "POUNCE", "parry": false, "backstep": true, "roll": false,
		"lesson": "SWORD", "tells": ["crouch_time"],
	},
	"glassbearer": {
		"blows": {"SWORD": true, "PLUNGE": true, "STOMP": true, "THROWN": true,
			"KICK": false, "SWEEP": false},
		"live": "", "parry": true, "backstep": false, "roll": false,
		"lesson": "SHOT", "tells": ["aim_time"],
	},
	"owl": {
		"blows": {"SWORD": true, "PLUNGE": true, "STOMP": true, "THROWN": true,
			"KICK": false, "SWEEP": false},
		"live": "STOOP", "parry": false, "backstep": false, "roll": false,
		"lesson": "SWORD", "tells": ["spread_time"],
	},
	"eclipse": {
		"blows": {"SWORD": false, "PLUNGE": false, "STOMP": false, "THROWN": false,
			"KICK": false, "SWEEP": false},
		"live": "SHOVE", "parry": false, "backstep": true, "roll": true,
		"lesson": "SHOT", "tells": ["draw_time", "charge_time", "crouch_time", "gather_time",
			"pause_time"],
	},
}


func after_each() -> void:
	Assist.reset()


## Every registered kind that is a foe.
func _foes() -> Array[String]:
	var out: Array[String] = []
	var kinds := EntityRegistry.kinds()
	for kind: String in kinds:
		var node := EntityRegistry.make(kind)
		if node is Foe:
			out.append(kind)
		node.free()
	out.sort()
	return out


## A fresh foe of `kind`, at rest in the tree, facing west toward a prince
## standing FRONT of it.
func _foe(kind: String) -> Foe:
	var foe := EntityRegistry.make(kind) as Foe
	foe.position = Vector2(200.0, 200.0)
	add_child_autofree(foe)
	foe.set("facing", -1)
	return foe


func _wounds(outcome: Foe.Outcome) -> bool:
	return outcome == Foe.Outcome.WOUNDED or outcome == Foe.Outcome.KILLED


## The danger a foe of `kind` sets against the prince in its live window.
func _danger(kind: String) -> FoeDanger:
	var row: Dictionary = TABLE[kind]
	if String(row["live"]) == "":
		var bolt := Sunbolt.make(Vector2(180.0, 185.0), Vector2.LEFT)
		autofree(bolt)
		return bolt.danger()
	var foe := _foe(kind)
	foe.call(&"_enter", _state(foe, String(row["live"])))
	var dangers: Array[FoeDanger] = foe.dangers()
	return dangers[0] if not dangers.is_empty() else null


func _state(foe: Foe, name: String) -> int:
	var states: Dictionary = (foe.get_script() as GDScript).get_script_constant_map()["State"]
	return int(states[name])


func test_every_foe_in_the_registry_has_a_row() -> void:
	var foes := _foes()
	assert_gt(foes.size(), 5, "the registry's foes were found")
	for kind: String in foes:
		assert_true(TABLE.has(kind), "%s has a row in the bestiary's table" % kind)
	for kind: String in TABLE:
		assert_true(foes.has(kind), "and the table's %s is placed by the registry" % kind)


func test_each_blade_and_each_foot_as_the_table_says() -> void:
	var cells := 0
	for kind: String in TABLE:
		var blows: Dictionary = TABLE[kind]["blows"]
		assert_eq(blows.size(), 6, "%s answers all six blows" % kind)
		for blow: String in blows:
			var foe := _foe(kind)
			var outcome := foe.take_blow(Foe.Blow[blow], foe.position.x + FRONT)
			assert_eq(_wounds(outcome), bool(blows[blow]),
				"%s, %s from the front: %s" % [kind, blow, Foe.Outcome.find_key(outcome)])
			cells += 1
	assert_eq(cells, 36, "six foes, six blows")


## Harmless to touch: at rest nothing a foe sets against the prince takes a
## heart. A Bastion's face is a wall that pushes back even at rest -- a
## danger with no damage -- and that is all it is.
func test_harmless_to_touch_at_rest() -> void:
	for kind: String in TABLE:
		var foe := _foe(kind)
		if not foe.is_dangerous():
			continue
		for danger: FoeDanger in foe.dangers():
			assert_eq(danger.damage, 0, "%s at rest takes no heart by touch" % kind)


func test_the_parry_the_backstep_and_the_roll_against_each_live_window() -> void:
	for kind: String in TABLE:
		var row: Dictionary = TABLE[kind]
		var danger := _danger(kind)
		assert_not_null(danger, "%s has a live window" % kind)
		if danger == null:
			continue
		assert_eq(danger.can_be_parried(), bool(row["parry"]), "%s: the parry" % kind)
		assert_eq(danger.evadable, bool(row["backstep"]), "%s: the backstep" % kind)
		assert_eq(danger.rollable, bool(row["roll"]), "%s: the roll" % kind)


func test_every_foe_bleeds_when_cut_down() -> void:
	for kind: String in TABLE:
		var foe := _foe(kind)
		var row: Dictionary = TABLE[kind]
		if kind == "eclipse":
			# Only the finale's parried beam ends him.
			var king := foe as Eclipse
			king.phase = Eclipse.Phase.FINALE
			king.call(&"_enter", Eclipse.State.POUR)
		var fell := [false]
		foe.defeated.connect(func() -> void: fell[0] = true)
		for _blow: int in 4:
			if fell[0]:
				break
			foe.take_blow(Foe.Blow[String(row["lesson"])], foe.position.x + FRONT)
		assert_true(fell[0], "%s, cut down by its lesson, says so: Bloodshed hears it" % kind)
	var stains := Bloodshed.new()
	autofree(stains)
	assert_true(stains.has_method(&"install"), "and the blood hangs off the contract")


func test_every_tell_stretches_under_longer_warnings() -> void:
	for kind: String in TABLE:
		var foe := _foe(kind)
		for tell: String in TABLE[kind]["tells"]:
			Assist.reset()
			var plain := float(foe.call(StringName(tell)))
			Assist.load_saved(UserData.at("user://test_bestiary_table_assist.cfg"))
			Assist.set_longer_warnings(true)
			var longer := float(foe.call(StringName(tell)))
			assert_almost_eq(longer, plain * Assist.LONGER, 0.0001,
				"%s.%s() is told %.2f times as long" % [kind, tell, Assist.LONGER])
	Assist.reset()
	var file := UserData.at("user://test_bestiary_table_assist.cfg")
	if FileAccess.file_exists(file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
