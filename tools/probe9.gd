extends Node

# 诊断探针：03_booth 机位，逐类隐藏物体，判断前景那片"光滑白块"到底是什么。
# 输出 a=全开 b=隐藏雪丘(SphereMesh 扁平体) c=隐藏雪丘+野草 d=隐藏所有 MeshInstance3D 只留地形

var _out := "res://tools/shots"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
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
	dn.call("_update_sun", 0.016)
	dn.call("_update_atmosphere", 0.016)
	await get_tree().process_frame

	var w: Node3D = Game.world
	player.global_position = Vector3(-8.0, w.height_at(-8.0, 12.0) + 1.62, 12.0)
	player.set_facing(1.9, -0.02)
	await get_tree().create_timer(0.5).timeout

	await _snap("p9_a_all")

	# 隐藏所有压扁球体（雪丘 _drift）
	var hidden := 0
	for c in w.get_children():
		if c is MeshInstance3D and c.mesh is SphereMesh:
			c.visible = false
			hidden += 1
	print("HIDDEN_SPHERES ", hidden)
	await _snap("p9_b_no_drift")

	var grass := w.get_node_or_null("FieldGrass")
	if grass:
		grass.visible = false
	await _snap("p9_c_no_drift_no_grass")

	# 再隐藏除地形外的所有网格
	var hid2 := 0
	for c in w.get_children():
		if c is MeshInstance3D and c.visible and c != w.get_node_or_null("Terrain"):
			c.visible = false
			hid2 += 1
		elif c is StaticBody3D:
			for k in c.get_children():
				if k is MeshInstance3D:
					k.visible = false
					hid2 += 1
	print("HIDDEN_REST ", hid2)
	await _snap("p9_d_terrain_only")

	print("PROBE DONE")
	get_tree().quit()

func _snap(tag: String) -> void:
	for k in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, tag]
	img.save_png(path)
	print("PROBE saved: ", path)
