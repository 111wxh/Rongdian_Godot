extends Node

# 探针：从相机向指定像素射线，报告命中的物理体与位置。

var _main: Node
var _cam: Camera3D

func _ready() -> void:
	_main = load("res://Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node3D = _main.get_node_or_null("Player")
	var world: Node = _main.get_node_or_null("World")
	player.global_position = Vector3(0.0, world.height_at(0.0, 90.0) + 1.62, 90.0)
	player.call("set_facing", 0.0, 0.06)
	await get_tree().process_frame
	await get_tree().process_frame
	_cam = player.get_node("Head/Camera3D")
	var space: PhysicsDirectSpaceState3D = _cam.get_world_3d().direct_space_state
	var vp: Vector2 = _cam.get_viewport().get_visible_rect().size
	print("viewport=", vp, " cam=", _cam.global_position)
	for tp in [Vector2(200, 400), Vector2(60, 415), Vector2(330, 405), Vector2(120, 385), Vector2(20, 430), Vector2(400, 395)]:
		var o: Vector3 = _cam.project_ray_origin(tp)
		var d: Vector3 = _cam.project_ray_normal(tp)
		var q := PhysicsRayQueryParameters3D.create(o, o + d * 400.0)
		var r: Dictionary = space.intersect_ray(q)
		if r.is_empty():
			print("pixel ", tp, " -> MISS")
		else:
			var col: Node = r["collider"]
			print("pixel ", tp, " -> ", col.name, " owner=", col.owner.name if col.owner else "-",
				" parent=", col.get_parent().name if col.get_parent() else "-",
				" pos=", r["position"], " n=", r["normal"], " dist=", snappedf(o.distance_to(r["position"]), 0.1))
	get_tree().quit()
