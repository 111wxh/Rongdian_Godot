extends Node
## 视觉取样器（开发工具，不参与游戏逻辑）
## 用法：godot --path <proj> res://tools/shot.tscn -- --out=res://tools/shots --tag=v1
## 载入 Main.tscn → 跳过开场 → 依次把摄像机摆到若干机位 → 存 PNG。
## 只读取世界，不修改任何游戏状态语义。

const SHOTS := [
	# 机位名, 世界坐标, 朝向 yaw(弧度), pitch(弧度), 说明
	["01_street_dawn", Vector3(0.0, 0.0, 26.0), 0.0, -0.02, "出生点看街道（默认开局构图）"],
	["02_store", Vector3(9.0, 0.0, -6.0), 1.15, -0.05, "便利店门口"],
	["03_booth", Vector3(-8.0, 0.0, 12.0), 1.9, -0.02, "保安亭"],
	["04_street_north", Vector3(-3.0, 0.0, 55.0), 3.14, -0.03, "街道向北回望"],
	["05_houses", Vector3(16.0, 0.0, 41.0), -0.40, -0.01, "民居群"],
	["06_gas", Vector3(34.0, 0.0, -26.0), 0.75, 0.02, "加油站"],
	["07_diner", Vector3(-27.0, 0.0, 2.0), 1.5, 0.0, "餐馆"],
	["08_wide", Vector3(0.0, 0.0, 90.0), 0.0, 0.06, "远景天际线"],
	["09_night", Vector3(0.0, 0.0, 26.0), 0.0, 0.05, "同一机位的夜景"],
	["10_warehouse", Vector3(-40.0, 0.0, 20.0), 1.57, 0.03, "仓库正面（体量检查）"],
	["11_flat_house", Vector3(-24.0, 0.0, 52.0), 1.57, 0.02, "平顶民居（体量检查）"],
	["12_gable", Vector3(18.0, 0.0, 34.0), -1.57, 0.02, "双坡顶民居（体量检查）"],
	["13_ruins", Vector3(24.0, 0.0, -40.0), 3.14, 0.0, "废墟群（断面检查）"],
]

var out_dir := "res://tools/shots"
var tag := "shot"
var _forced_hour := -1.0
# 白天机位的时间：可被 --hour= 覆盖，便于对同一机位做不同光照的对比
var _day_hour := 9.5
# 只拍某几个机位：--only=01,08 或 --only=01_street（子串匹配）。
# 单机位迭代时不必等 13 个机位 + 每个 0.7s 的稳定时间，一轮从 ~25s 降到 ~6s。
# 留空则拍全部。
var _only := ""
# --nohands：取景时藏掉第一人称手部模型。手部是独立 CanvasLayer 贴图，
# 会一起被 get_viewport().get_texture() 抓到，挡住画面左下角一大块。
# 评估"世界"的时候必须能关掉它，否则永远看不清前景。
var _no_hands := false
# --nohud：连 HUD 一起藏掉。HUD 里那些半透明面板（提示框、任务条）会盖在
# 画面上，既挡住雪地又让人误以为世界里有灰色板块。评估"世界"时必须关。
var _no_hud := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a.begins_with("--hour="):
			_day_hour = float(a.substr(7))
		elif a.begins_with("--only="):
			_only = a.substr(7)
		elif a == "--nohands":
			_no_hands = true
		elif a == "--nohud":
			_no_hud = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Player = Game.player
	var hud: HUD = Game.hud
	if player == null:
		print("SHOT-FATAL: no player")
		get_tree().quit(1)
		return
	if hud and hud.intro:
		hud.intro.queue_free()
	# HUD 在取景时必须能整体关掉：任务条、提示框都是半透明板，
	# 会在画面正中盖一块灰，量化时会被当成"雪面很灰"。
	if _no_hud and hud:
		hud.visible = false
	Game.started = true
	player.control_enabled = true
	# 手部是 ViewModel 里的 CanvasLayer("HandsLayer") 贴图，ViewModel 本身是
	# 普通 Node（没有 visible），必须按节点名找到那一层来关。
	if _no_hands and player.viewmodel:
		var hl := player.viewmodel.get_node_or_null("HandsLayer") as CanvasLayer
		if hl:
			hl.visible = false
	await get_tree().create_timer(0.5).timeout
	var cam: Camera3D = player.get_node("Head/Camera3D")
	# 让 viewmodel 之类的东西别挡住取景
	for i in range(SHOTS.size()):
		var s: Array = SHOTS[i]
		if _only != "" and not _match_only(String(s[0])):
			continue
		var p: Vector3 = s[1]
		p.y = Game.world.height_at(p.x, p.z) + 1.62
		player.global_position = p + Vector3(0, 0.05, 0)
		player.set_facing(float(s[2]), float(s[3]))
		var want_pos: Vector3 = player.global_position
		# 冻结物理：机位必须逐帧一致，否则重力/碰撞会把玩家从摆好的位置
		# 推走几米，同一机位每次渲出完全不同的构图——以前所有
		# "改前/改后" 的对比图其实都不可比。
		player.set_physics_process(false)
		player.velocity = Vector3.ZERO
		if String(s[0]).ends_with("night"):
			_forced_hour = 22.5
		else:
			# 白天的机位必须显式写回白天：否则会沿用上一个夜景机位的 22:30，
			# 排在 09_night 之后的所有机位都会拍成夜景（曾经的坑）。
			_forced_hour = _day_hour
		await get_tree().create_timer(0.7).timeout
		# 物理被冻结了，但玩家仍可能被别的东西挪动（如出生点修正、碰撞解算
		# 在冻结前已生效）；取图前强制回到目标位姿，保证构图逐帧一致。
		player.global_position = want_pos
		player.set_facing(float(s[2]), float(s[3]))
		await get_tree().create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var name := "%s_%s.png" % [tag, String(s[0])]
		var path := out_dir.path_join(name)
		img.save_png(path)
		print("SHOT saved: ", ProjectSettings.globalize_path(path), " ", img.get_width(), "x", img.get_height())
	if _forced_hour > 0.0:
		_forced_hour = -1.0
	get_tree().quit(0)

func _process(_d: float) -> void:
	if _forced_hour > 0.0:
		Game.hour = _forced_hour


func _match_only(shot_name: String) -> bool:
	for want in _only.split(",", false):
		want = want.strip_edges()
		if want == "":
			continue
		if shot_name == want or shot_name.begins_with(want) or shot_name.contains(want):
			return true
	return false
