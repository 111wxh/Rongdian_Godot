extends Node

# 临时探针：找出相机附近那些"大块平面"，看是谁在挡镜头。
# 用法：godot --path . res://tools/probe2.tscn

var _main: Node

func _ready() -> void:
	_main = load("res://Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	var world: Node = _main.get_node_or_null("World")
	if world == null:
		print("NO WORLD")
		get_tree().quit()
		return

	var cam_pos := Vector3(0.0, 2.0, 90.0)
	print("=== 相机附近 45m 内的 MeshInstance3D ===")
	var hits := 0
	for n in world.get_children():
		_collect(n, cam_pos, 0)

	# 同时报一下 structures 组里有没有异常大的物体
	print("=== structures 组 AABB 体积 Top ===")
	var arr: Array = []
	for n in get_tree().get_nodes_in_group("structures"):
		if n is Node3D:
			var aabb: AABB = _aabb_of(n)
			arr.append({"name": n.name, "kind": n.get_meta("kind", "?"), "pos": (n as Node3D).global_position, "size": aabb.size, "c": aabb.get_center() + (n as Node3D).global_position})
	arr.sort_custom(func(a, b): return a["size"].length() > b["size"].length())
	for i in range(mini(8, arr.size())):
		print("  ", arr[i])
	print("probe done")
	get_tree().quit()

func _collect(n: Node, cam_pos: Vector3, depth: int) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		var c: Vector3 = aabb.get_center()
		var d: float = c.distance_to(cam_pos)
		if d < 45.0 and aabb.size.y < 3.0 and (aabb.size.x > 6.0 or aabb.size.z > 6.0):
			print("  BIG-FLAT ", mi.name, " d=", snappedf(d, 0.1), " size=", aabb.size, " center=", c)
	for c2 in n.get_children():
		_collect(c2, cam_pos, depth + 1)

func _aabb_of(n: Node) -> AABB:
	var total := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null:
				var a: AABB = mi.get_aabb()
				if first:
					total = a
					first = false
				else:
					total = total.merge(a)
		for c in cur.get_children():
			stack.append(c)
	return total
