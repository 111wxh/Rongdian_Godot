extends Node3D
## 《融点》主入口：世界 → 昼夜 → 玩家 → HUD → 开场

var _title_ui

## autoload「Game」在编译期不可见（game.gd 与 main.gd 互相依赖形成解析环），
## 运行时按 /root/Game 取节点。
func _g() -> Node:
	var ml := Engine.get_main_loop()
	return ml.root.get_node_or_null("Game") if ml else null

func _ready() -> void:
	var g_rd: Node = _g()
	var loading := bool(g_rd.get("pending_load"))
	g_rd.set("pending_load", false)
	# 主菜单期间挡掉玩家输入/移动：player.gd 已按 Game.started 整体空转，
	# 这里额外确保鼠标不被 _ensure_mouse_captured 抢回
	Player.title_open = not loading and DisplayServer.get_name() != "headless"
	if loading:
		g_rd.call("load_game")
	else:
		g_rd.call("new_game")
	# 世界（程序化生成）
	var world: WorldGen = WorldGen.new()
	world.name = "World"
	add_child(world)
	# 昼夜 / 极光 / 暴风雪
	var dn := Node3D.new()
	dn.name = "DayNight"
	dn.set_script(load("res://scripts/world/day_night.gd"))
	add_child(dn)
	# 热引擎（T0 层 10Hz：dT/dt 营地核心温度结算）
	var th := Node.new()
	th.name = "ThermalEngine"
	th.set_script(load("res://scripts/world/thermal.gd"))
	add_child(th)
	# 疾病动力学（个体状态机）
	var dz := Node.new()
	dz.name = "DiseaseSystem"
	dz.set_script(load("res://scripts/survival/disease.gd"))
	add_child(dz)
	# 玩家
	var p: Player = _make_player()
	add_child(p)
	var spawn := Vector3(0, 0, 26)
	p.position = Vector3(spawn.x, world.height_at(spawn.x, spawn.z) + 0.2, spawn.z)
	p.set_facing(0.0, 0.0)
	g_rd.set("player", p)
	# 程序化音频层（风/脚步/火/操作声，零素材）
	var sb := Node.new()
	sb.name = "SoundBox"
	sb.set_script(load("res://scripts/world/sound_box.gd"))
	add_child(sb)
	g_rd.set("sound", sb)
	# HUD 之前加一层全屏后处理：暗角 / 颗粒 / 色散 / 冷暖分离（纯表现层）
	var fx := CanvasLayer.new()
	fx.name = "PostFX"
	fx.set_script(load("res://scripts/ui/postfx.gd"))
	fx.layer = 1
	add_child(fx)
	# HUD
	var hud: Node = load("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)
	# 分块随机扩充（涌现式冰原）：挂在 world 下，玩家周围 3×3 块流式加载。
	# 不依赖主菜单/测试分流，任何路径下都挂上；content_test 从 world 子节点里找它。
	var cm: Node = load("res://scripts/world/chunk_manager.gd").new()
	cm.name = "ChunkManager"
	world.add_child(cm)
	cm.call("setup", world)
	# 开始页面主菜单：只有「有窗口的正式运行 + 新游戏」才出现。
	# 无头测试（DisplayServer.headless）与读档重载一律不显示，六套自检路径不变。
	_title_ui = load("res://scripts/ui/main_menu.gd").new()
	_title_ui.name = "MainMenu"
	add_child(_title_ui)
	if loading:
		_apply_save(p, world)
		g_rd.set("started", true)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif Player.title_open:
		# 主菜单期间玩家不动、时间不推进：Game.started 仍为 false，
		# survival.gd 的 _physics_process 已在 Game.started=false 时整体空转。
		_title_ui.call("show_menu")
	else:
		hud.get("intro").call("start_intro", p)

func _make_player() -> Player:
	var p := Player.new()
	p.name = "Player"
	p.collision_layer = 2
	p.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	p.add_child(cs)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.62, 0)
	p.add_child(head)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 75.0
	cam.far = 1400.0
	# 近裁剪面 0.02：贴墙/贴地时不会把近处的面切掉看穿到背后（穿模修复）
	cam.near = 0.02
	head.add_child(cam)
	var ray := RayCast3D.new()
	ray.name = "InteractRay"
	ray.enabled = true
	cam.add_child(ray)
	var fl := SpotLight3D.new()
	fl.name = "Flashlight"
	fl.visible = false
	fl.spot_range = 20.0
	fl.spot_angle = 28.0
	fl.light_energy = 2.2
	fl.position = Vector3(0.2, -0.15, 0)
	cam.add_child(fl)
	var hold := Node3D.new()
	hold.name = "HoldPoint"
	hold.position = Vector3(0.4, -0.35, -0.8)
	cam.add_child(hold)
	var sv := Node.new()
	sv.name = "Survival"
	sv.set_script(load("res://scripts/survival/survival.gd"))
	p.add_child(sv)
	var bd := Node.new()
	bd.name = "Builder"
	bd.set_script(load("res://scripts/survival/building.gd"))
	p.add_child(bd)
	return p

func _apply_save(p: Player, world: Node3D) -> void:
	var g_as: Node = _g()
	p.position = g_as.get("load_pos") + Vector3(0, 0.6, 0)
	p.set_facing(g_as.get("load_rot"), 0.0)
	# 重建已放置的建筑
	for b in g_as.get("buildings"):
		if p.builder and p.builder.has_method("spawn_building"):
			p.builder.spawn_building(b)
	g_as.set("shelter_level", ShelterJudge.compute(g_as.get("buildings"), g_as.get("home_center")))
	# 恢复幸存者状态
	for npc in world.get_children():
		if npc is SurvivorNPC:
			for d in g_as.get("loaded_companions"):
				if String(d.get("sid", "")) == npc.sid:
					npc.from_save(d)
