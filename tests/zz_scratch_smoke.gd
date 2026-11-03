extends SceneTree
const Support := preload("res://tests/fighter_support.gd")
var _warm := 0

func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 2:
		return false
	var stage := Support.build(root)
	stage.place(14.0)
	stage.a.disarm(1)
	stage.run(stage.tuning.disarmed_frames + 1, 0, 0)
	stage.run(1, Support.ATTACK, 0)
	stage.run(stage.tuning.sweep_active_to, 0, 0)
	print("b state ", stage.b.state, " armed=", stage.b.is_armed(), " downed_frame=", stage.b.state_frame)
	stage.a.respawn_at(Vector2(stage.b.position.x, stage.ground_y()), 1)
	stage.a.disarm(-1)
	for i in 16:
		stage.run(1, 0, 0)
		print(i, " a=", stage.a.state, " b=", stage.b.state, " bframe=", stage.b.state_frame, " ev=", stage.events)
		stage.events.clear()
	stage.dispose()
	quit(0)
	return true
