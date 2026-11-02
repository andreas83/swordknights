class_name TouchSurface
extends Control
## The drawing half of TouchControls. Kept separate so the parent CanvasLayer
## owns the input handling and this node owns nothing but pixels.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Shown on phones and tablets from the start; on anything else it stays
	# hidden until a real touch arrives (TouchControls reveals it), and a key
	# or pad press hides it again.
	visible = OS.has_feature("mobile")


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var controls := get_parent() as TouchControls
	if controls != null:
		controls.draw_surface()
