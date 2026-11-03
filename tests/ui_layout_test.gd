extends SceneTree
## The interface's load-bearing arithmetic, asserted without a screen.
##
##     godot --headless --path . --script tests/ui_layout_test.gd
##
## Named *_test.gd on purpose: .github/scripts/run_tests.sh discovers that
## suffix and nothing else. A suite named any other way is a suite that never
## runs, and this repository has shipped two of those.
##
## What is worth asserting here is the stuff a screenshot cannot show: that
## nothing assumes a 320-unit-wide viewport, that the safe area is believed
## only when it is believable, that every glyph the game prints is in the
## font, and that the one piece of state behind the settings screen actually
## writes through.

const WIDE := Vector2(440.0, 180.0) ## 22:9, a tall phone turned sideways
const NARROW := Vector2(240.0, 180.0) ## 4:3, a tablet
const SQUARE := Vector2(320.0, 180.0) ## the nominal canvas

var _failures: Array[String] = []


## Stands in for the AudioDirector autoload, so the suite can drive the
## settings screen without touching the real mixer or writing user://audio.cfg.
## It is the same handful of methods the panel calls, which is the point of
## the panel talking to an injected node rather than to a global.
class FakeAudio:
	extends Node

	var settings := AudioSettings.new()
	var played: PackedStringArray = PackedStringArray()

	func set_volume(bus: StringName, value: float) -> void:
		match String(bus):
			"Music":
				settings.music = value
			"SFX":
				settings.sfx = value
			_:
				settings.master = value

	func toggle_mute() -> void:
		settings.muted = not settings.muted

	func play(event: String) -> void:
		played.append(event)


func _panel() -> SettingsPanel:
	var panel := SettingsPanel.new()
	panel.audio = FakeAudio.new()
	panel.add_child(panel.audio)
	root.add_child(panel)
	return panel


## Everything runs on the first processed frame rather than in _initialize:
## a node added to `root` before the tree starts is not in the tree yet, so its
## _ready has not run and a freshly built settings panel is still half-built.
func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_layout_scales_with_width()
	_test_safe_area_is_sane()
	_test_banner_is_inside_the_safe_area()
	_test_font_cuts_load()
	_test_font_covers_the_game_strings()
	_test_font_is_unicase()
	_test_fit_degrades()
	_test_settings_writes_through()
	_test_settings_navigation_wraps()

	if _failures.is_empty():
		print("ui_layout_test: all checks passed")
		quit(0)
		return
	for line: String in _failures:
		printerr("FAIL: ", line)
	printerr("ui_layout_test: %d failure(s)" % _failures.size())
	quit(1)


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


## Every rectangle the interface is built on has to move with the width.
func _test_layout_scales_with_width() -> void:
	for view: Vector2 in [NARROW, SQUARE, WIDE]:
		var safe := UiLayout.safe(view)
		var content := UiLayout.content(view)
		var banner := UiLayout.banner(view)
		_check(is_equal_approx(safe.size.x, view.x) or safe.size.x < view.x,
			"safe area wider than the viewport at %s" % view)
		_check(content.size.x < safe.size.x,
			"content rect is not inset from the safe area at %s" % view)
		_check(banner.size.x == safe.size.x,
			"banner does not span the safe width at %s" % view)
		_check(absf(banner.get_center().x - view.x * 0.5) <= 1.0,
			"banner is not centred at %s" % view)

	# The two extremes must not produce the same layout, or something is
	# hard-coded to 320.
	_check(UiLayout.content(WIDE).size.x > UiLayout.content(NARROW).size.x + 100.0,
		"content width does not track the viewport width")
	_check(UiLayout.column(WIDE, 104.0).size.x == UiLayout.column(SQUARE, 104.0).size.x,
		"a column that fits should be the same width on any screen")
	_check(UiLayout.column(NARROW, 400.0).size.x <= NARROW.x,
		"a column wider than the screen was not clamped")


## A safe area is a report from the platform, and on desktop it describes the
## whole desktop rather than the window. Believing it moved every button off
## the right-hand edge.
func _test_safe_area_is_sane() -> void:
	for view: Vector2 in [NARROW, SQUARE, WIDE]:
		var safe := UiLayout.safe(view)
		_check(safe.position.x >= 0.0 and safe.position.y >= 0.0,
			"safe area starts off-screen at %s: %s" % [view, safe])
		_check(safe.end.x <= view.x + 0.01 and safe.end.y <= view.y + 0.01,
			"safe area ends off-screen at %s: %s" % [view, safe])
		_check(safe.size.x >= view.x * (1.0 - 2.0 * UiLayout.MAX_INSET),
			"safe area ate more than the cap allows at %s" % view)


func _test_banner_is_inside_the_safe_area() -> void:
	for view: Vector2 in [NARROW, SQUARE, WIDE]:
		var safe := UiLayout.safe(view)
		var banner := UiLayout.banner(view)
		_check(banner.position.y >= safe.position.y,
			"banner starts above the safe area at %s" % view)
		_check(banner.end.y <= safe.end.y,
			"banner ends below the safe area at %s" % view)
		_check(UiLayout.rail(view) < safe.end.y,
			"the hint rail is outside the safe area at %s" % view)


func _test_font_cuts_load() -> void:
	for cut: int in [UiFont.Cut.MICRO, UiFont.Cut.TEXT, UiFont.Cut.DISPLAY]:
		var face := UiFont.face(cut)
		_check(face != null, "cut %d did not load" % cut)
		if face == null:
			continue
		_check(face.fixed_size == UiFont.CAP[cut],
			"cut %d is cap %d but the file says %d"
				% [cut, UiFont.CAP[cut], face.fixed_size])
	_check(UiFont.cap(UiFont.Cut.DISPLAY) > UiFont.cap(UiFont.Cut.TEXT),
		"the display cut is not larger than the text cut")


## Every character the game is known to print, in one string. A glyph missing
## from the atlas renders as nothing at all, which is invisible in a diff and
## obvious only to a player.
func _test_font_covers_the_game_strings() -> void:
	var used := (
		"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
		+ ".,:;-/()'\"!?%+"
		+ "·—"
	)
	for cut: int in [UiFont.Cut.MICRO, UiFont.Cut.TEXT, UiFont.Cut.DISPLAY]:
		var face := UiFont.face(cut)
		if face == null:
			continue
		for i: int in used.length():
			var code := used.unicode_at(i)
			_check(face.has_char(code),
				"cut %d has no glyph for U+%04X (%s)" % [cut, code, used[i]])


func _test_font_is_unicase() -> void:
	var face := UiFont.face(UiFont.Cut.TEXT)
	if face == null:
		return
	# A string that forgot its .to_upper() must still render, at the same width.
	_check(is_equal_approx(
		UiFont.width("swordknights", UiFont.Cut.TEXT),
		UiFont.width("SWORDKNIGHTS", UiFont.Cut.TEXT)
	), "lowercase is not mapped onto the capitals")
	_check(UiFont.width("III", UiFont.Cut.TEXT) < UiFont.width("MMM", UiFont.Cut.TEXT),
		"the face is not proportional — I is as wide as M")


func _test_fit_degrades() -> void:
	var options := PackedStringArray(["A LONG SENTENCE INDEED", "SHORT", "S"])
	_check(UiFont.fit(options, 400.0, UiFont.Cut.MICRO) == options[0],
		"fit did not take the first option when it had room")
	_check(UiFont.fit(options, 40.0, UiFont.Cut.MICRO) == options[1],
		"fit did not fall back to the second option")
	_check(UiFont.fit(options, 1.0, UiFont.Cut.MICRO) == options[2],
		"fit did not fall back to the last option")


## The settings screen exists so that a volume can be changed without a
## keyboard. If it stops writing through to AudioSettings, every pixel of it is
## decoration.
func _test_settings_writes_through() -> void:
	var panel := _panel()
	var rows := panel.rows()
	_check(rows.size() >= 4, "the settings screen lost a row")

	var music := -1
	var mute := -1
	for i: int in rows.size():
		match String(rows[i]["id"]):
			"music":
				music = i
			"mute":
				mute = i
			_:
				pass
	_check(music >= 0 and mute >= 0, "settings is missing the music or mute row")
	if music < 0 or mute < 0:
		panel.queue_free()
		return

	while panel.index() != music:
		panel.move(1)
	var before := panel.value_of(rows[music])
	panel.adjust(-1)
	var lowered := panel.value_of(rows[music])
	_check(lowered < before, "left on the music row did not lower the volume")
	# The gauge has ten cells, so a step lands on the grid rather than wherever
	# the saved value happened to be.
	_check(is_equal_approx(
		lowered, snappedf(lowered, SettingsPanel.STEP)
	), "a step left did not land on the gauge's grid: %f" % lowered)
	panel.adjust(1)
	_check(is_equal_approx(panel.value_of(rows[music]), lowered + SettingsPanel.STEP),
		"right did not raise the music volume by one step")

	for _i: int in 20:
		panel.adjust(-1)
	_check(panel.value_of(rows[music]) >= 0.0, "volume went below zero")
	for _i: int in 20:
		panel.adjust(1)
	_check(panel.value_of(rows[music]) <= 1.0, "volume went above one")

	while panel.index() != mute:
		panel.move(1)
	var muted := panel.value_of(rows[mute])
	panel.confirm()
	_check(not is_equal_approx(panel.value_of(rows[mute]), muted),
		"confirming the mute row did not toggle it")
	panel.confirm()
	_check(is_equal_approx(panel.value_of(rows[mute]), muted),
		"confirming twice did not put mute back")

	panel.queue_free()


func _test_settings_navigation_wraps() -> void:
	var panel := _panel()
	var count := panel.rows().size()
	var start := panel.index()
	for _i: int in count:
		panel.move(1)
	_check(panel.index() == start, "moving down a full lap did not return")
	panel.move(-1)
	_check(panel.index() == wrapi(start - 1, 0, count), "moving up did not wrap")
	panel.queue_free()
