extends Node

# 探针：把世界相机摆到 08_wide 机位，然后把每个 MeshInstance3D 的 AABB
# 投影到屏幕，看谁盖住了那块诡异灰带所在的像素。

var _main: Node
var _cam: Camera3D

func _ready() -> void:
	_main = load("res://Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node3D = _main.get_node_or_null("Player")
	var world: Node = _main.get_node_or_null("World")
	if player == null or world == null:
		print("NO PLAYER/WORLD")
		get_tree().quit()
		return
	player.global_position = Vector3(0.0, world.height_at(0.0, 90.0) + 1.62, 90.0)
	player.call("set_facing", 0.0, 0.06)
	await get_tree().process_frame
	await get_tree().process_frame
	_cam = player.get_node("Head/Camera3D")
	if _cam == null:
		print("NO CAM")
		get_tree().quit()
		return
	print("cam=", _cam.global_position, " dir=", -_cam.global_transform.basis.z)

	var targets := [Vector2(200, 400), Vector2(60, 415), Vector2(330, 405), Vector2(120, 380)]
	var all: Array = []
	_gather(world, all)
	print("mesh count=", all.size())
	for tp in targets:
		print("--- pixel ", tp, " ---")
		var found := 0
		for mi in all:
			var m := mi as MeshInstance3D
			var aabb: AABB = m.global_transform * m.get_aabb()
			var r := _screen_rect(aabb)
			if r.has_point(tp):
				var d: float = aabb.get_center().distance_to(_cam.global_position)
				print("   ", m.name, " d=", snappedf(d, 0.1), " rect=", r, " size=", aabb.size, " vis=", m.is_visible_in_tree())
				found += 1
				if found > 12:
					print("   ...")
					break
		if found == 0:
			print("   (nothing)")
	get_tree().quit()

func _gather(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_gather(c, out)

func _screen_rect(aabb: AABB) -> Rect2:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for i in range(8):
		var p: Vector3 = aabb.position + Vector3(
			aabb.size.x * float(i & 1),
			aabb.size.y * float((i >> 1) & 1),
			aabb.size.z * float((i >> 2) & 1))
		if _cam.is_position_behind(p):
			continue
		var s: Vector2 = _cam.unproject_position(p)
		mn = Vector2(minf(mn.x, s.x), minf(mn.y, s.y))
		mx = Vector2(maxf(mx.x, s.x), maxf(mx.y, s.y))
	if mn.x > mx.x:
		return Rect2(-1, -1, 0, 0)
	return Rect2(mn, mx - mn)
