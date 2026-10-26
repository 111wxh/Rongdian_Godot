extends Node3D
## 大气对照探针 v2：先停掉 DayNight 的 _process（否则每帧被 _update_atmosphere 覆盖），
## 再手动逐组设定参数并出图，用来确定目标观感。

var _out := "res://tools/probe"
var _player: Node3D
var _dn: Node
var _env: Environment
var _sky: ShaderMaterial


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud = main.get_child(5)
	if hud and hud.get("intro"):
		hud.intro.queue_free()
		hud.intro = null
	Game.started = true
	_player = Game.player
	_dn = main.get_node("DayNight")
	Game.hour = 8.5
	Game.weather = "clear"
	_player.global_position = Vector3(0, Game.world.height_at(0, 90) + 1.7, 90)
	_player.set_facing(0.0, -0.05)
	await get_tree().create_timer(0.4).timeout

	# 冻结大气驱动，后续所有赋值才不会被每帧覆盖
	_dn.set_process(false)
	_env = _dn.get("_env")
	_sky = _dn.get("_sky_mat")
	await _shot("A_frozen_baseline")

	# ---- B：把天空压暗压蓝（雪地亮 / 天空暗 = 层次） ----
	_sky.set_shader_parameter("zenith_color", Color(0.06, 0.14, 0.32))
	_sky.set_shader_parameter("horizon_color", Color(0.42, 0.55, 0.72))
	_sky.set_shader_parameter("ground_color", Color(0.16, 0.20, 0.27))
	_sky.set_shader_parameter("aurora", 0.0)
	_sky.set_shader_parameter("stars", 0.0)
	_sky.set_shader_parameter("haze", 0.5)
	await _shot("B_sky_dark")

	# ---- C：叠加降低环境光 + 降低曝光 ----
	_env.ambient_light_energy = 0.42
	_env.tonemap_exposure = 0.92
	await _shot("C_dark_amb_exp")

	# ---- D：雾改冷蓝、拉远、减浓度 ----
	_env.fog_light_color = Color(0.44, 0.56, 0.72)
	_env.fog_light_energy = 0.85
	_env.fog_depth_end = 520.0
	_env.fog_depth_begin = 18.0
	_env.fog_depth_curve = 2.4
	_env.fog_height_density = 0.18
	_env.fog_sky_affect = 0.25
	await _shot("D_fog_blue_far")

	# ---- E：再关体积雾 ----
	_env.volumetric_fog_enabled = false
	await _shot("E_no_vol")

	# ---- F：E 基础上加一点夕阳暖光方向（太阳压低） ----
	var sun: DirectionalLight3D = _dn.get("sun")
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 2.6
	await _shot("F_warm_sun")

	# ---- G：再压曝光到 0.8 ----
	_env.tonemap_exposure = 0.80
	await _shot("G_exp080")

	# ---- H：加强 SSAO 与对比 ----
	_env.ssao_intensity = 2.4
	_env.adjustment_contrast = 1.14
	_env.adjustment_saturation = 1.05
	await _shot("H_contrast_ao")

	print("PROBE DONE")
	get_tree().quit()


func _shot(tag: String) -> void:
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, tag])
	print("PROBE ", tag)
