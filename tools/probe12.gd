extends Node

# 探针：在 04_street_north 机位向屏幕点 (170,470) 打射线，
# 报告命中的碰撞体与它对应的网格/材质。

func _ready() -> void:
	_run()

func _run() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud := main.get_node_or_null("HUD")
	if hud and hud.get("intro"):
		hud.get("intro").queue_free()
	Game.started = true
	await get_tree().process_frame

	var player: Player = Game.player
	var dn: Node = main.get_node_or_null("DayNight")
	dn.set_process(false)
	Game.hour = 8.5
	Game.weather = "clear"
	await get_tree().process_frame

	var x := -3.0
	var z := 55.0
	var gy: float = Game.world.height_at(x, z)
	player.global_position = Vector3(x, gy + 0.2, z)
	player.set_facing(3.14, -0.03)
	await get_tree().process_frame
	await get_tree().process_frame

	var cam: Camera3D = Game.player.get_node("Head/Camera3D")
	var space := cam.get_world_3d().direct_space_state
	var cb := cam.global_transform.basis
	var cp := cam.global_position
	var half_v: float = tan(deg_to_rad(cam.fov) * 0.5)
	var aspect := 1280.0 / 720.0
	for pt in [Vector2(170, 470), Vector2(150, 440), Vector2(220, 500), Vector2(600, 430)]:
		var ndc := Vector2(pt.x / 1280.0 * 2.0 - 1.0, 1.0 - pt.y / 720.0 * 2.0)
		var dir: Vector3 = (cb * Vector3(ndc.x * half_v * aspect, ndc.y * half_v, -1.0)).normalized()
		var q := PhysicsRayQueryParameters3D.create(cp, cp + dir * 60.0)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			print("pt ", pt, " -> no hit")
			continue
		var col: Object = hit["collider"]
		var node := col as Node
		print("pt ", pt, " -> ", node.name, " path=", str(node.get_path()).substr(0, 90),
			" dist=", snappedf(cp.distance_to(hit["position"]), 0.1))
		# 找出该碰撞体下挂的 MeshInstance3D
		for c in node.get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				var m: Material = mi.material_override
				if m == null and mi.mesh:
					m = mi.mesh.surface_get_material(0)
				print("     mesh=", mi.mesh.get_class() if mi.mesh else "null",
					" mat=", m.get_class() if m else "null")
				if m is ShaderMaterial:
					print("       params: ", (m as ShaderMaterial).shader.resource_path)
