class_name PoseLab
extends Node2D
## The pose lab: every pose of both figures, looked at where they will be
## played, and the duel's guard to try with a thumb.
##
## The owner could not tell the duel's LOW guard from its duck on the phone,
## and no screen in the game could show him either one on demand: a match
## reaches a pose when it reaches it, and the contact sheets are pictures on a
## desk, not the phone in the hand under the Well's night. So this is a dev
## mode on the title screen (ModeRegistry, `dev`) with two pages.
##
## BROWSE steps through PoseCatalogue -- every Fighter.State and stance, every
## Player.State, every idle bit, read from the enums so a pose added later is
## here without anyone listing it -- with the pose's name in Alcazar over it.
## The figure stands on a real strip's middle zone at the scale play draws it
## (the adventure's 180 units, or the duel's close or far framing), with the
## same figure three times larger in an inset beside it for the detail. Rows
## on the left change what is shown: the duel fighter or the adventure's
## prince, which figure (the prince, the heroine, or the player's own saved
## look), the seat's colours, playing or frozen, the strip and so its hour,
## the scale, the hitboxes.
##
## TRY is the duel's own simulation on the same ground (PoseLabSpar): the
## player's fighter on the duel's touch controls, against a dummy holding a
## stance he picks, with the posture the combat matrix sees and the last
## outcome read out as it happens.
##
## ## Driven like every other page
##
## Left and right step the pose, up and down choose a row, JUMP changes it,
## SWORD or PAUSE go back -- the actions every page reads, so the keyboard, a
## gamepad and the thumb stick all work. Every row, both pose arrows and the
## pose's name can be tapped, as the title screen's rows can. On TRY the stick
## and the buttons are the fighter's, so its own rows are tapped, and Back or
## PAUSE return to BROWSE. Android's Back is one page back, as everywhere
## (docs/ui.md, "Ways back").
##
## Nothing here is gameplay: browsing never steps a body, and TRY steps the
## duel's fighters at the fixed tick exactly as a match does, with nothing
## of the lab's in their state.

enum Page { BROWSE, TRY }
enum Kind { DUEL, ADVENTURE }
enum Figure { PRINCE, HEROINE, STICK, PRINCESS, SAVED }
enum Scale { PLAY, DUEL_CLOSE, DUEL_FAR }

const MENU_SCENE := "res://scenes/menu.tscn"
## The browse page's rows, top to bottom.
const ROWS: Array[String] = [
	"kind", "figure", "seat", "motion", "light", "scale", "hitboxes", "try",
]
## TRY's rows, tapped only: the stick and the buttons are the fighter's.
const TRY_ROWS: Array[String] = ["back", "dummy", "thrusts", "light", "scale", "reset"]
const KIND_NAMES: Array[String] = ["DUEL FIGHTER", "ADVENTURE PRINCE"]
const FIGURE_NAMES: Array[String] = ["PRINCE", "HEROINE", "STICK", "PRINCESS", "SAVED LOOK"]
## The CharacterLook figure id behind each entry but the saved look.
const FIGURE_IDS: Array[String] = ["prince", "heroine", "stick", "princess"]
const SCALE_NAMES: Array[String] = ["1:1 PLAY", "DUEL CLOSE", "DUEL FAR"]
## The enlarged inset's scale: a whole multiple, so edges stay hard.
const INSET_SCALE := 3.0
const REPEAT_FIRST := 0.42
const REPEAT_DELAY := 0.12
## How long the stick is ignored after a tap: the same thumb is on it now.
const TAP_HOLD := 0.42

## Test seams, set before _ready: where the saved look is read from, and what
## going back from BROWSE does (the title screen).
var wardrobe_path := UserData.at(Wardrobe.PATH)
var leave := Callable()

var page := Page.BROWSE
var kind := Kind.DUEL
var figure := Figure.PRINCE
var seat := 0
var playing := true
var scale_mode := Scale.PLAY
var hitboxes := false
var row := 0
var index := 0

var _poses: Array[Dictionary] = []
var _repeat := 0.0
var _step_repeat := 0.0
var _stepping := false
var _hold := 0.0
## The JUMP or SWORD that changed the page is still down: not a press there.
var _held_over := false
var _back_asked := false
var _framing := MatchFraming.new()

@onready var stage: PoseLabStage = $Stage
@onready var lab_figure: PoseLabFigure = $Figure
@onready var spar: PoseLabSpar = $Spar
@onready var camera: Camera2D = $Camera
@onready var ui: PoseLabUi = $Ui/Page
@onready var inset: PoseLabFigure = $Ui/Inset/Holder/Figure
@onready var _sky: ParallaxSky = $Sky/ParallaxSky


func _ready() -> void:
	stage.sky = _sky
	_sky.camera = camera
	camera.make_current()
	ui.lab = self
	inset.lifted = false
	($Ui/Inset/Holder as Node2D).scale = Vector2.ONE * INSET_SCALE
	stage.use_strip(PoseLabStage.ORDER[0])
	spar.visible = false
	_rebuild()
	_arguments()


## For a screenshot (tools/screenshot.gd): `--lab-body=adventure`,
## `--lab-pose=GUARD_LOW` (a label, underscores for spaces), `--lab-light=well`,
## `--lab-figure=heroine`, `--lab-frozen`, `--lab-try`.
func _arguments() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--lab-body=adventure":
			change("kind")
		elif arg == "--lab-figure=heroine":
			change("figure")
		elif arg.begins_with("--lab-light="):
			stage.use_strip(arg.trim_prefix("--lab-light="))
		elif arg == "--lab-frozen":
			change("motion")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--lab-pose="):
			var label := arg.trim_prefix("--lab-pose=").replace("_", " ")
			for i: int in _poses.size():
				if String(_poses[i]["label"]) == label:
					index = i
			_show()
		elif arg == "--lab-try":
			open_try()


func _exit_tree() -> void:
	# A static on the art: leave it as the rest of the game expects it.
	FighterArt.show_hitboxes = OS.get_cmdline_user_args().has("--hitboxes")


## --- the model the page shows -------------------------------------------------

func poses() -> Array[Dictionary]:
	return _poses


func pose() -> Dictionary:
	return _poses[index] if index < _poses.size() else {}


## What row `id` says it is set to, for the page.
func value_of(id: String) -> String:
	match id:
		"kind":
			return KIND_NAMES[kind]
		"figure":
			return FIGURE_NAMES[figure]
		"seat":
			return "ONE · CRIMSON" if seat == 0 else "TWO · SEA-GREEN"
		"motion":
			return "PLAYING" if playing else "FROZEN"
		"light":
			return stage.label()
		"scale":
			return SCALE_NAMES[scale_mode]
		"hitboxes":
			return "SHOWN" if hitboxes else "HIDDEN"
		"try":
			return "THE GUARD, BY THUMB"
		"dummy":
			return PoseLabSpar.DUMMY_NAMES[spar.dummy_stance]
		"thrusts":
			return "EVERY %.1f S" % (PoseLabSpar.THRUST_EVERY / 60.0) \
				if spar.dummy_thrusts else "NEVER"
	return ""


static func row_label(id: String) -> String:
	match id:
		"kind":
			return "BODY"
		"try":
			return "TRY"
		"back":
			return "POSES"
		"hitboxes":
			return "HITBOX"
	return id.to_upper()


## Whether row `id` means anything for what is shown: the seat and the
## hitboxes are the duel's.
func is_live(id: String) -> bool:
	if id == "seat" or id == "hitboxes":
		return kind == Kind.DUEL
	return true


## The figure's state in words, under its name.
func pose_detail() -> String:
	var body := lab_figure.body()
	if body is Fighter:
		var fighter := body as Fighter
		return "%s · STANCE %s · POSTURE %s · FRAME %d" % [
			PoseLabSpar.state_name(fighter), PoseCatalogue.stance_name(fighter.stance),
			PoseLabSpar.posture_name(fighter), fighter.state_frame]
	var player := body as Player
	if player == null:
		return ""
	return "%s · %.2f S" % [String(Player.State.keys()[player.state]).replace("_", " "),
		player.state_time]


## --- what the player does -----------------------------------------------------

func step_pose(by: int) -> void:
	if _poses.is_empty():
		return
	index = posmod(index + by, _poses.size())
	GameAudio.cue("ui_move")
	_show()


func move_row(by: int) -> void:
	row = posmod(row + by, ROWS.size())
	GameAudio.cue("ui_move")


## Changes row `id` one step on (or back, with `by` -1).
func change(id: String, by: int = 1) -> void:
	if not is_live(id):
		GameAudio.cue("ui_back")
		return
	GameAudio.cue("ui_confirm")
	match id:
		"kind":
			kind = posmod(kind + by, Kind.size()) as Kind
			index = 0
			_rebuild()
		"figure":
			figure = posmod(figure + by, Figure.size()) as Figure
			_rebuild()
		"seat":
			seat = 1 - seat
			_rebuild()
		"motion":
			playing = not playing
			lab_figure.set_playing(playing)
			inset.set_playing(playing)
		"light":
			stage.use_strip(PoseLabStage.step(stage.strip_id, by))
			if page == Page.TRY:
				_build_spar()
		"scale":
			scale_mode = posmod(scale_mode + by, Scale.size()) as Scale
		"hitboxes":
			hitboxes = not hitboxes
			FighterArt.show_hitboxes = hitboxes
		"try":
			open_try()
		"back":
			close_try()
		"dummy":
			spar.set_dummy(posmod(spar.dummy_stance + by, PoseLabSpar.Dummy.size())
				as PoseLabSpar.Dummy)
		"thrusts":
			spar.dummy_thrusts = not spar.dummy_thrusts
		"reset":
			spar.place()


func confirm() -> void:
	change(ROWS[row])


func open_try() -> void:
	page = Page.TRY
	_held_over = true
	_build_spar()
	spar.visible = true
	lab_figure.visible = false
	$Ui/Inset.visible = false


func close_try() -> void:
	page = Page.BROWSE
	_held_over = true
	spar.visible = false
	lab_figure.visible = true
	$Ui/Inset.visible = true
	GameAudio.cue("ui_back")


func back() -> void:
	if page == Page.TRY:
		close_try()
		return
	GameAudio.cue("ui_back")
	if leave.is_valid():
		leave.call()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


## A tap at `at`, in screen units: a row, an arrow, the name. True if it
## landed on one. Public so a test can tap without a touch.
func tap(at: Vector2) -> bool:
	if TouchControls.claims(self, at):
		return false
	var hit := ui.hit(at)
	if hit.is_empty():
		return false
	_hold = TAP_HOLD
	match String(hit["kind"]):
		"prev":
			step_pose(-1)
		"next":
			step_pose(1)
		"row":
			var id := String(hit["id"])
			if page == Page.BROWSE:
				row = ROWS.find(id)
			change(id, int(hit.get("by", 1)))
	return true


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed:
		return
	var local := ui.make_input_local(touch) as InputEventScreenTouch
	if tap(local.position):
		get_viewport().set_input_as_handled()


## Android's Back: one page back, held for the next frame like a button.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back_asked = true


func _process(delta: float) -> void:
	_repeat = maxf(0.0, _repeat - delta)
	_step_repeat = maxf(0.0, _step_repeat - delta)
	_hold = maxf(0.0, _hold - delta)
	if _held_over and not _press_held():
		_held_over = false
	if _back_asked:
		_back_asked = false
		back()
		return
	if page == Page.BROWSE:
		_browse_input()
	elif Input.is_action_just_pressed("pause"):
		close_try()
	_label_thumbs()
	_frame_camera()
	ui.queue_redraw()


func _browse_input() -> void:
	if _hold > 0.0 or _held_over:
		return
	var across := Input.get_axis("move_left", "move_right")
	if absf(across) > 0.5:
		if is_zero_approx(_step_repeat):
			step_pose(signi(int(signf(across))))
			_step_repeat = REPEAT_DELAY if _stepping else REPEAT_FIRST
			_stepping = true
	else:
		_step_repeat = 0.0
		_stepping = false
	var down := Input.get_axis("move_up", "move_down")
	if absf(down) > 0.5:
		if is_zero_approx(_repeat):
			move_row(signi(int(signf(down))))
			_repeat = REPEAT_FIRST
	else:
		_repeat = 0.0
	if Input.is_action_just_pressed("jump"):
		confirm()
	elif Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("pause"):
		back()


## TRY's frame: the player's byte off the shared actions, which the keyboard,
## a gamepad and the touch controls all drive, as the duel against the
## computer reads it.
func _physics_process(_delta: float) -> void:
	if page != Page.TRY:
		return
	var bits := 0 if _held_over else PlayerInput.bits_from_actions("")
	spar.step(bits)
	ui.your_bits = bits


func _press_held() -> bool:
	for action: String in ["jump", "attack", "pause"]:
		if Input.is_action_pressed(action):
			return true
	return false


func _label_thumbs() -> void:
	var controls := TouchControls.of(self)
	if controls == null:
		return
	if page == Page.TRY:
		controls.play_labels()
	else:
		controls.set_labels("CHANGE|SET", "BACK")


## --- what is shown --------------------------------------------------------------

## The look the figures wear: one of the default figures, or the
## player's own from the wardrobe -- player two's for the sea-green seat.
func look() -> CharacterLook:
	if figure == Figure.SAVED:
		return Wardrobe.open(wardrobe_path).look(seat if kind == Kind.DUEL else 0)
	var out := CharacterLook.new()
	out.take_ids({"figure": FIGURE_IDS[figure]})
	return out


## Re-reads the catalogue for the body shown, and dresses both figures.
func _rebuild() -> void:
	_poses = PoseCatalogue.fighter() if kind == Kind.DUEL else PoseCatalogue.prince()
	index = clampi(index, 0, maxi(0, _poses.size() - 1))
	var body := PoseLabFigure.Body.FIGHTER if kind == Kind.DUEL \
		else PoseLabFigure.Body.PRINCE
	var dressed := look()
	for each: PoseLabFigure in [lab_figure, inset]:
		each.dress(body, dressed, seat)
		var art := each.art()
		if art != null and each == lab_figure and kind == Kind.DUEL:
			art.add_to_group(MatchDusk.LIT)
	if page == Page.TRY:
		_build_spar()
	_show()


func _show() -> void:
	var entry := pose()
	lab_figure.position = stage.mark(0)
	lab_figure.playing = playing
	inset.playing = playing
	lab_figure.show_pose(entry)
	inset.show_pose(entry)


func _build_spar() -> void:
	var looks: Array[CharacterLook] = [_seat_look(0), _seat_look(1)]
	spar.build(stage, looks)


func _seat_look(which: int) -> CharacterLook:
	if figure == Figure.SAVED:
		return Wardrobe.open(wardrobe_path).look(which)
	return look()


## The zoom the SCALE row asks for: the adventure's 180 units, or what the
## duel's camera stands at close and far on this screen (MatchFraming).
func zoom_for(which: Scale) -> float:
	if which == Scale.PLAY:
		return 1.0
	var view := get_viewport_rect().size
	var per_unit := _per_unit()
	_framing.per_unit = per_unit
	_framing.screen = view * per_unit
	var level := _framing.close_level() if which == Scale.DUEL_CLOSE \
		else _framing.far_level()
	return float(level) / per_unit


## Puts the feet where the page wants them: the browse figure in the gap
## between the rows and the inset, the sparring pair centred.
func _frame_camera() -> void:
	var zoom := zoom_for(scale_mode)
	camera.zoom = Vector2.ONE * zoom
	var view := get_viewport_rect().size
	var feet := stage.mark(0)
	var on_screen := ui.stage_point(view)
	if page == Page.TRY and spar.you != null:
		feet = Vector2((spar.you.position.x + spar.dummy.position.x) * 0.5, stage.mark(0).y)
		on_screen = Vector2(view.x * 0.5, view.y * 0.62)
	var centre := feet - (on_screen - view * 0.5) / zoom
	var per_world := zoom * _per_unit()
	camera.position = (centre * per_world).round() / per_world


## Screen pixels per canvas unit: the canvas_items stretch. Six, a 1080 px
## phone's, when there is no window to measure.
func _per_unit() -> float:
	var view := get_viewport_rect().size
	var window := get_window()
	if window != null and view.y > 0.0 and window.size.y > 0:
		return float(window.size.y) / view.y
	return 6.0
