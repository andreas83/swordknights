class_name CameraView
extends RefCounted
## What the camera shows, in world units: the one question every foe asks
## before it acts, and every trap before it makes a sound.
##
## docs/campaign.md, "What makes it stand out": a foe acts only while the
## camera shows it. A bestiary range is a maximum, never a licence to strike
## from off the frame -- an owl eight tiles away on a 320-unit phone held
## upright is out of the picture, and a stoop out of the picture is a death
## nobody could read. The same rule keeps the Well's machinery quiet when it
## is off screen: a blade is heard where it is seen.
##
## The frame is the viewport's size over the camera's zoom, around where the
## camera holds (GameCamera.frame_centre()). The Adventure's camera stands at
## a fixed GameCamera.ZOOM, so a 180-unit viewport shows 120 units of world;
## the zoom is read off the camera rather than assumed, so a foe can never act
## on a stretch of world the screen does not show. Not the shaken image: the
## shake is random, and a foe's decision is the simulation's, so it must come
## out the same on every run and at every frame rate -- which is also why the
## camera smooths on the physics step. With no camera at all (a
## unit test stepping a foe on its own), everything is in view: the rule is
## about the screen, and there is none.


## The rectangle of the world the current camera shows, or an infinite one
## when there is no camera to ask.
static func rect_for(node: Node) -> Rect2:
	if node == null or not node.is_inside_tree():
		return everything()
	var viewport := node.get_viewport()
	if viewport == null:
		return everything()
	var camera := viewport.get_camera_2d()
	if camera == null:
		return everything()
	var size := viewport.get_visible_rect().size / camera.zoom
	var centre := camera.get_screen_center_position()
	if camera is GameCamera:
		centre = (camera as GameCamera).frame_centre()
	return Rect2(centre - size * 0.5, size)


## Whether any part of `rect` is on screen.
static func shows(node: Node, rect: Rect2) -> bool:
	return rect_for(node).intersects(rect, true)


static func everything() -> Rect2:
	return Rect2(Vector2(-1.0e9, -1.0e9), Vector2(2.0e9, 2.0e9))
