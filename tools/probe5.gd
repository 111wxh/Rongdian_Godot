extends Node

# 探针：手动按 1280x720 构造射线，判断那条水平灰带是什么。

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
	var basis: Basis = _cam.global_transform.basis
	var half_v: float = tan(deg_to_rad(_cam.fov * 0.5))
	var aspect: float = 1280.0 / 720.0
	print("cam=", _cam.global_position, " fov=", _cam.fov, " half_v=", snappedf(half_v, 0.001))

	for py in [300, 340, 360, 380, 395, 405, 415, 430, 450, 500]:
		var line: String = "y=%3d " % py
		for px in [100, 300, 640, 1000]:
			var ndc := Vector2(float(px) / 1280.0 * 2.0 - 1.0, 1.0 - float(py) / 720.0 * 2.0)
			var dir: Vector3 = (basis * Vector3(ndc.x * half_v * aspect, ndc.y * half_v, -1.0)).normalized()
			var o: Vector3 = _cam.global_position
			var q := PhysicsRayQueryParameters3D.create(o, o + dir * 1400.0)
			var r: Dictionary = space.intersect_ray(q)
			if r.is_empty():
				line += "| x%4d MISS           " % px
			else:
				var col: Node = r["collider"]
				line += "| x%4d %s %.0fm     " % [px, String(col.name).substr(0, 10), o.distance_to(r["position"])]
		print(line)
	get_tree().quit()
