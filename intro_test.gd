extends Node
## 开场链路测试：电影化苏醒演出（眨眼→低头→拔腿→后倒→看天→撑起）→
## 记忆 → 起名 → 职业 → 自由移动。验证时间线推进、镜头/手部姿态、输入交接。

var fails: Array = []
var _mouse_chain_broken := true

func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var intro: IntroUI = Game.hud.intro
	var player: Player = Game.player
	if intro == null or player == null:
		print("FATAL: intro/player 缺失")
		get_tree().quit(1)
		return

	# ---- 1. 眨眼苏醒 → 低头 → 拔腿（约 6 秒）----
	var t := 0.0
	while intro.state != "pull_legs" and t < 25.0:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	print("[1] 进入 pull_legs, state=", intro.state, " 用时=", t)
	if intro.state != "pull_legs":
		fails.append("开场未推进到拔腿阶段")
	# 低头验证：俯仰应为负（朝下看腿）
	if intro.state == "pull_legs" and intro._pitch > -0.5:
		fails.append("拔腿阶段未低头（pitch=%.2f）" % intro._pitch)
	# 手部姿态验证
	if player.viewmodel == null or player.viewmodel.cinematic != "reach_down":
		fails.append("拔腿阶段手部未进入 reach_down 演出姿态")

	# ---- 2. 向后倒在地上：眼高应降到 0.5 左右，且改为仰望 ----
	t = 0.0
	while intro.state != "lie" and t < 20.0:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	print("[2] 进入 lie, state=", intro.state, " head_y=", intro._head_y, " pitch=", intro._pitch)
	if intro.state != "lie":
		fails.append("开场未推进到躺倒阶段")
	else:
		if intro._head_y > 1.0:
			fails.append("躺倒时眼高未降低（head_y=%.2f，应≈0.5）" % intro._head_y)
		if intro._pitch < 0.5:
			fails.append("躺倒时未仰望天空（pitch=%.2f）" % intro._pitch)

	# ---- 3. 跳过：演出中按 ESC，应直接进起名且姿态复位 ----
	_push_key(KEY_ESCAPE, true)
	_push_key(KEY_ESCAPE, false)
	t = 0.0
	while intro.state != "name" and t < 5.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	print("[3] 按 ESC 跳过: state=", intro.state, " head_y=", intro._head_y, " pitch=", intro._pitch,
		" 手部姿态=", player.viewmodel.cinematic if player.viewmodel else "none")
	if intro.state != "name":
		fails.append("按 ESC 未能跳过演出进入起名")
	else:
		if intro._head_y < 1.5:
			fails.append("跳过后眼高未复位（head_y=%.2f）" % intro._head_y)
		if absf(intro._pitch) > 0.01:
			fails.append("跳过后俯仰未复位（pitch=%.2f）" % intro._pitch)
		if player.viewmodel and player.viewmodel.cinematic != "":
			fails.append("跳过后手部演出姿态未复位")

	# ---- 4. 填名字并确认 ----
	if intro.state == "name":
		var confirmed := false
		for c in intro.panel.find_children("*", "Button", true, false):
			var btn: Button = c
			if btn.text == "就是这个名字":
				btn.pressed.emit()
				confirmed = true
				break
		if not confirmed:
			fails.append("找不到名字确认按钮")
		await get_tree().process_frame
		await get_tree().process_frame
	print("[4] 名字确认后 state=", intro.state)

	# ---- 5. 选职业 ----
	if intro.state == "profession":
		var btns := intro.panel.find_children("*", "Button", true, false)
		if btns.is_empty():
			fails.append("职业按钮缺失")
		else:
			var first: Button = btns[0]
			print("[5] 选择职业: ", first.text)
			first.pressed.emit()
			await get_tree().process_frame
			await get_tree().process_frame
	print("[5] 选职业后 state=", intro.state)

	# ---- 6. 交接验证 ----
	await get_tree().create_timer(0.5).timeout
	print("[6] started=", Game.started, " control_enabled=", player.control_enabled,
		" mouse_mode=", Input.mouse_mode, " intro_visible=", intro.visible)
	if not Game.started:
		fails.append("Game.started 未置 true")
	if not player.control_enabled:
		fails.append("player.control_enabled 未置 true")
	print("[6] started/control ok, intro_visible=", intro.visible)
	if intro.visible:
		fails.append("intro 节点结束后未隐藏（全屏 fade 会吞鼠标事件）")

	# ---- 7. 真实移动验证：按住 W 1 秒，位置应变化 ----
	var p0: Vector3 = player.global_position
	_push_key(KEY_W, true)
	await get_tree().create_timer(1.0).timeout
	_push_key(KEY_W, false)
	await get_tree().create_timer(0.3).timeout
	var moved: float = p0.distance_to(player.global_position)
	print("[7] 按住 W 1秒 位移=", moved, " (", p0, " -> ", player.global_position, ")")
	if moved < 1.0:
		fails.append("按住 W 玩家未移动（移动链路断裂）, moved=%f" % moved)

	# ---- 8. 鼠标视角验证：模拟鼠标移动，视角应变化 ----
	var head: Node3D = player.head
	var yaw_before: float = player.rotation.y
	print("[8-diag] _open_panels=", Game.hud._open_panels if Game.hud else "no-hud",
		" mouse_mode=", Input.mouse_mode)
	# 8a. 直接调用 player 的输入处理（绕过事件分发，验证代码逻辑）
	var mm0 := InputEventMouseMotion.new()
	mm0.relative = Vector2(60, -30)
	player._input(mm0)
	await get_tree().process_frame
	print("[8a] 直接调用后 pitch=", head.rotation.x, " yaw=", player.rotation.y)
	if absf(head.rotation.x) > 0.01 or absf(player.rotation.y - yaw_before) > 0.01:
		_mouse_chain_broken = false
	# 复位
	head.rotation.x = 0.0
	player.rotation.y = yaw_before
	# 8b. 走真实事件系统（headless 环境不一定分发鼠标事件，仅作信息输出）
	for i in range(5):
		var mm := InputEventMouseMotion.new()
		mm.relative = Vector2(60, -30)
		Input.parse_input_event(mm)
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	print("[8b] 事件系统后 pitch=", head.rotation.x, " yaw=", player.rotation.y,
		"（headless 下鼠标事件可能不分发，仅参考；以 8a 为准）")
	# 8a 有效即视角链路 OK；8b 在真实窗口环境由玩家鼠标验证
	if absf(head.rotation.x) < 0.01 and absf(player.rotation.y - yaw_before) < 0.01 and _mouse_chain_broken:
		fails.append("鼠标移动未改变视角")

	print("")
	if fails.is_empty():
		print("===== 开场链路测试全部通过 =====")
	else:
		print("===== 失败项 =====")
		for f in fails:
			print(" - ", f)
	get_tree().quit(0 if fails.is_empty() else 1)

func _push_key(key: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)
