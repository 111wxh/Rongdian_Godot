extends Node

# 诊断探针：与 shot.gd 完全一致的 05_houses 机位，打印几何与实例统计，
# 并输出几张对照图，用来判断"中景白带"到底是几何没有起伏、还是着色没有细节。
# 关键点：相机朝向必须与 shot.gd 的 05_houses 一致（yaw=-0.9, pitch=0.0），
# 否则量到的画面区域根本不是同一块地方。

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

	# ---- 统计：地面高度起伏（判断几何到底有没有雪丘）----
	var w: Node3D = Game.world
	var hs: Array[float] = []
	var i := -40
	while i <= 40:
		var j := -40
		while j <= 40:
			hs.append(w.height_at(float(i) * 4.0, float(j) * 4.0))
			j += 1
		i += 1
	hs.sort()
	var mn: float = hs[0]
	var mx: float = hs[hs.size() - 1]
	var sum := 0.0
	for v in hs:
		sum += v
	print("HEIGHT grid 320m: min %.2f max %.2f range %.2f mean %.2f" % [mn, mx, mx - mn, sum / float(hs.size())])

	# 局部起伏：相邻 8m 采样点的高度差标准差（真正的"地形有没有起伏"）
	var diffs: Array[float] = []
	var a := -30
	while a <= 30:
		var b := -30
		while b <= 30:
			var x: float = float(a) * 8.0
			var z: float = float(b) * 8.0
			diffs.append(absf(w.height_at(x + 8.0, z) - w.height_at(x, z)))
			b += 1
		a += 1
	var dsum := 0.0
	for v in diffs:
		dsum += v
	print("HEIGHT 8m-neighbour |dh| mean %.3f" % (dsum / float(diffs.size())))

	# ---- 统计：野地细节是否真的存在 ----
	var grass := w.get_node_or_null("FieldGrass")
	if grass and grass is MultiMeshInstance3D:
		print("FIELDGRASS instances ", (grass as MultiMeshInstance3D).multimesh.instance_count,
			" visible ", grass.visible, " aabb ", (grass as MultiMeshInstance3D).get_aabb())
	else:
		print("FIELDGRASS missing")
	var n_structures := get_tree().get_nodes_in_group("structures").size()
	print("STRUCTURES ", n_structures)

	# ---- 渲染对照 ----
	var env: Environment = (dn.get("env") as WorldEnvironment).environment
	player.global_position = Vector3(22.0, w.height_at(22.0, 24.0) + 1.62, 24.0)
	player.set_facing(-0.9, 0.0)
	await get_tree().create_timer(0.6).timeout
	await _snap("p8_base")

	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	await _snap("p8_nofog")
	env.fog_enabled = true
	env.volumetric_fog_enabled = true

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
