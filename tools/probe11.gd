extends Node

# 探针：在 04_street_north 机位，用真实相机基向量手算屏幕投影，
# 列出落在画面左下角（<440, >380）的大块物体。

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
	var cb := cam.global_transform.basis
	var cp := cam.global_position
	var fov := deg_to_rad(cam.fov)
	var aspect := 1280.0 / 720.0
	print("--- cam at ", cp, " fov ", cam.fov)

	var world: Node = main.get_node_or_null("World")
	var hits: Array = []
	_gather(world, cam, cb, cp, fov, aspect, hits)
	hits.sort_custom(func(a, b): return a[4] < b[4])
	print("--- objects landing in left-lower region: ", hits.size())
	for i in range(mini(hits.size(), 22)):
		var h: Array = hits[i]
		print("  %s  dist=%.1f  px=(%d,%d) size=%s" % [h[0], h[4], int(h[1]), int(h[2]), str(h[3])])

func _gather(n: Node, cam: Camera3D, cb: Basis, cp: Vector3, fov: float, aspect: float, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var ab: AABB = mi.get_aabb()
			var center: Vector3 = mi.global_transform * ab.get_center()
			var rel: Vector3 = center - cp
			var d := rel.length()
			if d > 45.0 or d < 0.4:
				continue
			var local := cb.inverse() * rel
			if local.z > -0.4:
				continue
			var half_v: float = tan(fov * 0.5)
			var sx: float = (local.x / (-local.z)) / (half_v * aspect)
			var sy: float = (local.y / (-local.z)) / half_v
			var px: float = (sx * 0.5 + 0.5) * 1280.0
			var py: float = (0.5 - sy * 0.5) * 720.0
			var world_size: float = ab.size.length() * mi.global_transform.basis.get_scale().length() / 1.732
			if px < 460.0 and py > 370.0 and py < 720.0:
				out.append([mi.name, px, py, snappedf(world_size, 0.1), d])
		_gather(c, cam, cb, cp, fov, aspect, out)
