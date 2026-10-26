extends Node

# 对照：同一机位渲染 a=正常 b=关掉太阳阴影 c=关掉地形自身遮罩，判断路面横条是不是 shadow acne。

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
	Game.hour = 8.5
	Game.weather = "clear"
	await get_tree().process_frame

	var player: Player = Game.player
	var dn: Node = main.get_node_or_null("DayNight")
	dn.set_process(false)
	var x := -3.0
	var z := 55.0
	var gy: float = Game.world.height_at(x, z)
	player.global_position = Vector3(x, gy + 0.2, z)
	player.set_facing(3.14, -0.03)
	await get_tree().process_frame
	await get_tree().process_frame

	var sun: DirectionalLight3D = dn.get("sun")
	var env: WorldEnvironment = dn.get("env")
	print("sun shadow_enabled=", sun.shadow_enabled, " bias=", sun.shadow_bias,
		" normal_bias=", sun.shadow_normal_bias, " mode=", sun.directional_shadow_mode,
		" max_dist=", sun.directional_shadow_max_distance)

	await _shot("a_normal")

	# b: 关掉太阳阴影
	sun.shadow_enabled = false
	await _shot("b_noshadow")
	sun.shadow_enabled = true

	# c: 关掉 SSAO
	env.environment.ssao_enabled = false
	await _shot("c_nossao")
	env.environment.ssao_enabled = true

	# d: 关掉雾
	env.environment.fog_enabled = false
	await _shot("d_nofog")
	env.environment.fog_enabled = true

	get_tree().quit()

func _shot(tag: String) -> void:
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/cmp_%s.png" % tag)
	print("CMP saved ", tag)
