extends Node

# 探针：确认新增的防雪栅栏 / 电线杆是否真的生成，以及它们在相机前多大。

func _ready() -> void:
	_run()

func _run() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var world: Node = main.get_node_or_null("World")
	print("--- world children count: ", world.get_child_count())
	var fence: Node = null
	var wires := 0
	var poles := 0
	for c in world.get_children():
		if c.name == "SnowFence":
			fence = c
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh:
			wires += 1
	print("SnowFence found: ", fence != null)
	if fence and fence is MultiMeshInstance3D:
		print("  instances: ", (fence as MultiMeshInstance3D).multimesh.instance_count)
		print("  aabb: ", (fence as MultiMeshInstance3D).get_aabb())
	print("cyl MeshInstance3D (wires+poles+posts): ", wires)

	# 统计所有 y>2.5 的细长物体（电线杆应该是最高的那批）
	var tall: Array = []
	for c in world.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var h := mi.get_aabb().size.y * mi.scale.y
			if h > 4.0:
				tall.append([snappedf(mi.global_position.x, 0.1), snappedf(mi.global_position.y, 0.1),
					snappedf(mi.global_position.z, 0.1), snappedf(h, 0.1)])
	print("tall(>4m) meshes: ", tall.size())
	for i in range(mini(tall.size(), 12)):
		print("   ", tall[i])
