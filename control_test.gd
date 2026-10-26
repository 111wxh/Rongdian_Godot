extends Node
## 控制项专项测试：鼠标视角输入链路 / Ctrl 下蹲 / 提示板动态对比色
## 直接跳过开场（intro 流程由 intro_test 覆盖），聚焦本次新增与修复

var fails: Array = []

func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Player = Game.player
	var hud: HUD = Game.hud
	if player == null or hud == null:
		print("FATAL: player/hud 缺失")
		get_tree().quit(1)
		return

	# ---- 0. 跳过开场：中断 intro（连带其 tween），直接进入自由状态 ----
	if hud.intro:
		hud.intro.queue_free()
	Game.started = true
	player.control_enabled = true
	# 冻结全部生物 AI：本测试聚焦控制链路，而新版狼会主动逼近玩家、
	# 可能横在准星与目标之间（曾偶发挡掉床的射线）
	for cr in get_tree().get_nodes_in_group("creatures"):
		if cr is Creature:
			cr.set_physics_process(false)
	await get_tree().create_timer(0.4).timeout

	# ---- 1. 鼠标视角：_input 链路（GUI 之前的通道）----
	# 视角为 0.12s 平滑插值（设计文档《操作手感》：禁止 1:1 刚性跟随），
	# 这里给足收敛时间（≈4 倍时间常数）再测量"最终落点"，而非单帧瞬时值。
	var head: Node3D = player.head
	var yaw0: float = player.rotation.y
	var pitch0: float = head.rotation.x
	player.set_facing(yaw0, pitch0)   # 清掉任何遗留目标，本步从当前姿态起步
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(80, -40)
	player._input(mm)
	await get_tree().create_timer(0.5).timeout
	var d_yaw: float = absf(player.rotation.y - yaw0)
	var d_pitch: float = absf(head.rotation.x - pitch0)
	print("[1] _input 视角: dyaw=", d_yaw, " dpitch=", d_pitch)
	if d_yaw < 0.05 or d_pitch < 0.02:
		fails.append("鼠标视角输入无响应（_input 链路断裂）")
	# 旧通道 _unhandled_input 不再处理视角（避免双重旋转）
	# 先让上一视线收敛并锁死目标，避免遗留插值被误判为 _unhandled_input 造成
	await get_tree().create_timer(0.5).timeout
	player.set_facing(player.rotation.y, head.rotation.x)
	var yaw1: float = player.rotation.y
	player._unhandled_input(mm)
	await get_tree().create_timer(0.1).timeout
	if absf(player.rotation.y - yaw1) > 0.001:
		fails.append("_unhandled_input 仍处理视角（会双重旋转）")
	# 复位
	player.set_facing(yaw0, pitch0)

	# ---- 2. 面板打开时视角应被拦截 ----
	# 先让上一阶段视线完全收敛并锁死目标，避免遗留插值被误读为"面板未拦截"
	await get_tree().create_timer(0.5).timeout
	player.set_facing(player.rotation.y, head.rotation.x)
	_push_key(KEY_TAB, true)
	await get_tree().process_frame
	_push_key(KEY_TAB, false)
	await get_tree().create_timer(0.2).timeout
	print("[2] 背包打开 _open_panels=", hud._open_panels)
	if hud._open_panels <= 0:
		fails.append("背包面板未能打开")
	player.set_facing(player.rotation.y, head.rotation.x)  # 锁定当前视角目标
	var yaw2: float = player.rotation.y
	var pitch2: float = head.rotation.x
	player._input(mm)
	await get_tree().create_timer(0.2).timeout
	if absf(player.rotation.y - yaw2) > 0.001 or absf(head.rotation.x - pitch2) > 0.001:
		fails.append("面板打开时视角仍被旋转（拦截失效）")
	_push_key(KEY_TAB, true)
	await get_tree().process_frame
	_push_key(KEY_TAB, false)
	await get_tree().create_timer(0.2).timeout
	if hud._open_panels != 0:
		fails.append("背包面板未能关闭")

	# ---- 3. Ctrl 下蹲：状态 / 相机高度 / 松开恢复 ----
	await get_tree().create_timer(0.5).timeout  # 等落地
	Input.action_press("crouch")
	await get_tree().create_timer(0.6).timeout
	print("[3] 蹲下: crouching=", player.crouching, " amt=", player.crouch_amt,
		" cam_y=", player.cam.position.y)
	if not player.crouching:
		fails.append("按住 Ctrl 未进入下蹲状态")
	if player.crouch_amt < 0.8:
		fails.append("下蹲过渡未完成: %f" % player.crouch_amt)
	if player.cam.position.y > -0.4:
		fails.append("下蹲相机高度未下降: %f" % player.cam.position.y)
	Input.action_release("crouch")
	await get_tree().create_timer(0.6).timeout
	print("[3] 恢复: crouching=", player.crouching, " amt=", player.crouch_amt,
		" cam_y=", player.cam.position.y)
	if player.crouching or player.crouch_amt > 0.05:
		fails.append("松开 Ctrl 未恢复站立")
	if absf(player.cam.position.y) > 0.15:
		fails.append("恢复站立后相机高度异常: %f" % player.cam.position.y)

	# ---- 4. 蹲着移动更慢（对比站立位移）----
	var p0: Vector3 = player.global_position
	_push_key(KEY_W, true)
	await get_tree().create_timer(1.0).timeout
	_push_key(KEY_W, false)
	await get_tree().create_timer(0.3).timeout
	var stand_moved: float = p0.distance_to(player.global_position)
	Input.action_press("crouch")
	await get_tree().create_timer(0.6).timeout
	var p1: Vector3 = player.global_position
	_push_key(KEY_W, true)
	await get_tree().create_timer(1.0).timeout
	_push_key(KEY_W, false)
	await get_tree().create_timer(0.3).timeout
	var crouch_moved: float = p1.distance_to(player.global_position)
	Input.action_release("crouch")
	print("[4] 位移: 站立=", stand_moved, " 下蹲=", crouch_moved)
	if crouch_moved >= stand_moved * 0.75:
		fails.append("下蹲未显著减速（站=%f 蹲=%f）" % [stand_moved, crouch_moved])

	# ---- 5. 提示板动态对比色：亮底黑字 / 暗底白字 ----
	hud.lbl_prompt.text = "测试提示"
	hud.lbl_prompt.visible = true
	hud._apply_prompt_contrast(0.9)
	var c_bright: Color = hud.lbl_prompt.get_theme_color("font_color")
	var o_bright: Color = hud.lbl_prompt.get_theme_color("font_outline_color")
	hud._apply_prompt_contrast(0.05)
	var c_dark: Color = hud.lbl_prompt.get_theme_color("font_color")
	var o_dark: Color = hud.lbl_prompt.get_theme_color("font_outline_color")
	print("[5] 亮底字=", c_bright, " 描边=", o_bright, " / 暗底字=", c_dark, " 描边=", o_dark)
	if c_bright.r + c_bright.g + c_bright.b > 0.45:
		fails.append("亮背景下提示字不是深色")
	if c_dark.r + c_dark.g + c_dark.b < 2.0:
		fails.append("暗背景下提示字不是浅色")
	if o_bright.r + o_bright.g + o_bright.b < c_bright.r + c_bright.g + c_bright.b:
		fails.append("亮底描边未与文字反色")
	hud.lbl_prompt.visible = false

	# ---- 6. 进屋：从屋外走向保安亭门（地板改纯视觉后应无台阶阻挡）----
	var world: Node3D = Game.world
	if world == null or not world.has_method("height_at"):
		fails.append("世界缺失，无法测试进屋")
	else:
		var gy: float = world.height_at(-10.6, 9.0)
		player.global_position = Vector3(-10.6, gy + 0.6, 9.0)
		player.set_facing(PI / 2.0, 0.0)  # 面向 -x（门开在东侧墙）
		await get_tree().create_timer(0.5).timeout  # 落地
		var x_before: float = player.global_position.x
		_push_key(KEY_W, true)
		await get_tree().create_timer(2.0).timeout
		_push_key(KEY_W, false)
		await get_tree().create_timer(0.3).timeout
		var x_after: float = player.global_position.x
		print("[6] 走向房门: x=", x_before, " -> ", x_after, "（门线≈-11.7）")
		if x_after > -11.7:
			fails.append("玩家被挡在门外进不去（x=%.2f，疑似地板台阶/碰撞）" % x_after)

		# ---- 7. 床交互：准星捕获 + E 触发睡眠 ----
		var bed_node: Node3D = null
		for c in world.get_children():
			if c is BedInteract:
				bed_node = c
				break
		if bed_node == null:
			fails.append("世界里找不到床")
		else:
			# 贴身 + 接近垂直向下看：对地形起伏不敏感，稳定命中床体
			player.global_position = bed_node.global_position + Vector3(0, 0.5, 0.7)
			player.set_facing(0.0, -1.2)
			await get_tree().create_timer(0.8).timeout  # 确保落地
			player._update_interact_target()
			var tgt: Node3D = player.interact_target
			print("[7] 准星目标=", tgt, " 提示=", player._prompt_text)
			if tgt == null or not (tgt is BedInteract):
				fails.append("准星照不到床（床碰撞体埋地或位置不对）")
			elif not (player._prompt_text as String).contains("睡"):
				fails.append("床提示文案异常: %s" % player._prompt_text)
			else:
				# try_sleep 是同步的（瞬间睡到次日早晨），断言其效果而非中间态
				Game.hour = 6.9  # 贴近清晨，缩短睡眠模拟
				var f_before: float = Game.fatigue
				player._do_interact()
				await get_tree().process_frame
				var slept_to_morning: bool = Game.hour >= 7.0
				var rested: bool = Game.fatigue < f_before
				print("[7] 睡眠效果: hour=", Game.hour, " fatigue=", f_before, " -> ", Game.fatigue)
				if not slept_to_morning:
					fails.append("睡未到早晨（hour=%.1f）" % Game.hour)
				elif not rested:
					fails.append("睡眠未恢复精力")
				else:
					print("[7] 床睡眠链路完整 ok")

	print("")
	if fails.is_empty():
		print("===== 控制项测试全部通过 =====")
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
