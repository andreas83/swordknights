extends GutTest
## Smoke tests: the boot scene — the first thing the engine loads — must
## instantiate cleanly and keep its contract with the engine.
##
## This is the test that proves the harness can touch real project scenes, not
## just project settings.

const BOOT_SCENE_PATH := "res://scenes/boot.tscn"


func test_boot_scene_resource_exists() -> void:
	assert_true(
		ResourceLoader.exists(BOOT_SCENE_PATH),
		"%s is the configured main scene and must be loadable" % BOOT_SCENE_PATH
	)


func test_boot_scene_loads_as_a_packed_scene() -> void:
	var packed: Resource = load(BOOT_SCENE_PATH)
	assert_not_null(packed, "boot scene failed to load")
	assert_is(packed, PackedScene, "boot scene must be a PackedScene")


func test_boot_scene_instantiates_and_runs_ready() -> void:
	var packed: PackedScene = load(BOOT_SCENE_PATH)
	var boot: Node = packed.instantiate()
	assert_not_null(boot, "boot scene did not instantiate")

	# add_child_autofree puts the node in the live tree, so _ready() actually
	# runs, and frees it when the test ends.
	add_child_autofree(boot)
	await wait_physics_frames(2)

	assert_true(
		is_instance_valid(boot), "boot node did not survive _ready() — something in boot.gd errored"
	)
	assert_eq(boot.name, &"Boot", "boot scene root is expected to be named Boot")


func test_boot_script_declares_the_menu_scene_it_hands_off_to() -> void:
	# boot.gd deliberately degrades to a warning when the menu scene is absent,
	# so the constant is the only thing we can assert until the menu lands.
	var boot_script: GDScript = load("res://scripts/core/boot.gd")
	assert_not_null(boot_script, "scripts/core/boot.gd must parse and load")

	var constants: Dictionary = boot_script.get_script_constant_map()
	assert_has(constants, "MENU_SCENE", "boot.gd must keep naming the scene it transitions to")
	assert_eq(
		constants["MENU_SCENE"],
		"res://scenes/menu.tscn",
		"the hand-off target moved; update boot.gd and this test together"
	)
