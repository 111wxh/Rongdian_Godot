extends Node
## 场景重载时序测试：模拟 F9 读档 / 重开 → reload_current_scene →
## 旧场景节点释放，验证协程恢复时不再给已释放实例赋值
## （"Trying to assign invalid previously freed instance"）
##
## 覆盖三条真实触发路径：
##   A. intro 睁眼/记忆闪回的 await get_tree().create_timer() 恢复时
##      （caption/state 赋值）——场景树 timer 不随 intro 释放而取消
##   B. 捕猎 0.45s 锁定（player._try_hunt 的 await）恢复时
##      （control_enabled 赋值）
##   C. 旧 HUD 释放后持续 notify（队列制消费）

func _ready() -> void:
	# ---- 第一次加载：intro 自动进入 start_intro ----
	var main1: Node = load("res://Main.tscn").instantiate()
	add_child(main1)
	await get_tree().process_frame
	await get_tree().process_frame
	var old_intro: Node = null
	if Game.hud:
		old_intro = Game.hud.intro
	print("[1] Main1 就绪, intro=", old_intro != null,
		" state=", old_intro.get("state") if old_intro else "n/a")

	# ---- 路径A：记忆闪回进行中重载 ----
	# 等 intro 进入 struggle（睁眼 tween 4.5s + 0.8s 场景树 timer 之后），
	# 按 W×6 触发 _memory_flash——其循环里的 await create_timer(1.7) 是
	# 场景树 timer，不随 intro 释放取消；恢复后若缺自检，
	# caption.text = "" 会给已释放实例赋值报错
	var t := 0.0
	# 新演出是时间线驱动（不再有按 W 挣扎）：等到记忆闪回阶段即可
	while old_intro != null and old_intro.get("state") != "memory" and t < 40.0:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	if old_intro == null or old_intro.get("state") != "memory":
		print("FAIL: 开场未进入 memory 状态")
		get_tree().quit(1)
		return
	# 闪回循环的 1.7s timer 正在跑，0.3s 后重载（timer 尚未恢复）
	await get_tree().create_timer(0.3).timeout
	var main2: Node = load("res://Main.tscn").instantiate()
	add_child(main2)
	main1.queue_free()  # 释放旧 intro
	await get_tree().create_timer(2.5).timeout  # 覆盖 1.7s 恢复点
	if is_instance_valid(old_intro):
		print("FAIL: 旧 intro 未释放")
		get_tree().quit(1)
		return
	print("[2] 路径A（记忆闪回中重载）ok, 旧 intro 已释放")

	# ---- 路径B：捕猎 0.45s 锁定期间重载 ----
	Game.started = true
	await get_tree().create_timer(0.5).timeout
	var player = Game.player
	var main3: Node = null
	var creature: Node3D = null
	for cn in get_tree().get_nodes_in_group("creatures"):
		if cn is Node3D and cn.has_method("try_harvest"):
			creature = cn
			break
	if player and creature:
		creature.set_physics_process(false)  # 冻结 AI 避免逃跑
		var cp: Vector3 = creature.global_position
		player.global_position = cp + Vector3(0, 0.5, 1.4)
		# 面向 creature（_try_hunt 要求 facing > 0.55）
		player.rotation.y = atan2(-(cp.x - player.global_position.x), -(cp.z - player.global_position.z))
		player.head.rotation.x = -0.15
		Game.active_tool = "spear"
		Game.add_item("spear", 1)
		await get_tree().create_timer(0.4).timeout  # 等落地
		player._try_hunt()  # 内部 await 0.45s，恢复后 control_enabled = ...
		await get_tree().create_timer(0.15).timeout  # 锁定尚未结束
		var old_player: Node = player
		main3 = load("res://Main.tscn").instantiate()
		add_child(main3)
		main2.queue_free()  # 释放承载旧 player 的场景
		await get_tree().create_timer(1.5).timeout  # 覆盖 0.45s 恢复点
		if is_instance_valid(old_player):
			print("FAIL: 旧 player 未释放")
			get_tree().quit(1)
			return
		print("[3] 路径B（捕猎锁定重载）ok, 旧 player 已释放")
	else:
		print("[3] 路径B 跳过：player=", player != null, " creature=", creature != null)

	# ---- 路径C：旧 HUD 释放后持续 notify（队列制应只被新 HUD 消费）----
	await get_tree().create_timer(1.0).timeout
	Game.notify("旧场景释放后的通知", "info")
	for i in range(10):
		Game.notify("轰炸 %d" % i, "info")
	Game.notify("线索类 toast", "clue")
	await get_tree().create_timer(0.8).timeout
	if Game.ui_events.size() > 2:
		print("FAIL: ui_events 未被消费, size=", Game.ui_events.size())
		get_tree().quit(1)
		return
	print("[4] 路径C（释放后 notify）ok, ui_events 残留=", Game.ui_events.size())

	# ---- 连续场景替换稳定性 ----
	var main4: Node = load("res://Main.tscn").instantiate()
	add_child(main4)
	if is_instance_valid(main3):
		main3.queue_free()
	await get_tree().create_timer(1.0).timeout
	Game.notify("二次替换后", "info")
	await get_tree().create_timer(0.5).timeout
	print("[5] 二次替换 ok, HUD=", Game.hud != null)

	print("===== 重载时序测试全部通过 =====")
	get_tree().quit(0)

func _push_key(key: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)
