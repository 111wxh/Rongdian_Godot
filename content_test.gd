extends Node
## 内容测试：交互系统（NPC/生物碰撞体）+ 世界内容（路面/房屋）+ 手部视图模型 + 拢雪
## 直接跳过开场（intro 流程由 intro_test 覆盖）

var fails: Array = []

func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Player = Game.player
	var hud: HUD = Game.hud
	var world: Node3D = Game.world
	if player == null or hud == null or world == null:
		print("FATAL: player/hud/world 缺失")
		get_tree().quit(1)
		return

	# ---- 0. 输入绑定回归（最关键）：use 必须是鼠标左键、interact 必须是 E。
	# 之前 use 被误放进 KEY_ACTIONS 注册成 InputEventKey(physical=1)，
	# 导致真实按住左键采集/捕猎/拆除全部失效；而 Input.action_press("use")
	# 会绕过 InputMap，所以旧测试发现不了。这里直接查真实绑定。
	var use_mouse := false
	for e in InputMap.action_get_events("use"):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			use_mouse = true
	var int_e := false
	for e in InputMap.action_get_events("interact"):
		if e is InputEventKey and e.physical_keycode == KEY_E:
			int_e = true
	print("[0] 绑定检查: use=鼠标左键?", use_mouse, " interact=E?", int_e)
	if not use_mouse:
		fails.append("use 未绑定鼠标左键（左键采集/捕猎/拆除将全部失效）")
	if not int_e:
		fails.append("interact 未绑定 E 键")

	if hud.intro:
		hud.intro.queue_free()
	Game.started = true
	player.control_enabled = true
	# 冻结全部生物 AI：除 [3]/[12] 外各段都不需要活AI，而狼会主动逼近、
	# 可能横在准星与目标之间（[12] 会自行解冻它的狼）
	for cr in get_tree().get_nodes_in_group("creatures"):
		if cr is Creature:
			cr.set_physics_process(false)
	await get_tree().create_timer(0.6).timeout

	# ---- 1. 世界内容：路面 / 房屋 / 水塔 ----
	var roads := get_tree().get_nodes_in_group("roads")
	print("[1] 路面网格数=", roads.size())
	if roads.size() < 4:
		fails.append("路面生成不足: %d" % roads.size())
	var kinds := {}
	for n in get_tree().get_nodes_in_group("structures"):
		var k := String(n.get_meta("kind", "?"))
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("[1] 结构统计=", kinds)
	for need in ["gable_house", "flat_house", "gas_station", "diner", "warehouse", "water_tower"]:
		if int(kinds.get(need, 0)) < 1:
			fails.append("缺少结构: " + need)

	# ---- 2. NPC：碰撞体 + 射线命中 + 搬起/交谈 ----
	var npc: SurvivorNPC = null
	for c in world.get_children():
		if c is SurvivorNPC:
			npc = c
			break
	if npc == null:
		fails.append("世界里没有幸存者")
	else:
		var has_col := false
		for ch in npc.get_children():
			if ch is CollisionShape3D:
				has_col = true
		print("[2] NPC 碰撞体=", has_col)
		if not has_col:
			fails.append("NPC 没有碰撞体（射线穿过人，永远无法交互）")
		# 贴身站位 + 计算式瞄准（对地形高差稳健）。
		# 注意：NPC 出生点旁可能是陨坑，先把人和玩家都放到出生点附近的平地
		var bx := 0.0
		var bz := 26.0
		var by: float = world.height_at(bx, bz)
		npc.global_position = Vector3(bx + 1.5, by, bz)
		player.global_position = Vector3(bx - 0.5, by + 0.5, bz)
		await _aim_at(player, npc.global_position + Vector3(0, 1.0, 0))
		player._update_interact_target()
		var tgt: Node3D = player.interact_target
		print("[2] 准星目标=", tgt, " 提示=", player._prompt_text)
		if tgt != npc:
			fails.append("准星照不到幸存者")
		elif not (player._prompt_text as String).contains("搬起") and not (player._prompt_text as String).contains("交谈"):
			fails.append("NPC 提示异常: %s" % player._prompt_text)
		if npc.state == "frozen":
			player._do_interact()
			await get_tree().process_frame
			print("[2] 搬起后 carrying=", player.carrying)
			if player.carrying != npc:
				fails.append("对幸存者按 E 未触发搬起")
			player.carrying = null
			npc.carried = false
		# 放下：让她回到地面（搬起时被移到手持点，悬空了），再实测"交谈"
		npc.global_position = Vector3(bx + 1.5, by, bz)
		await _aim_at(player, npc.global_position + Vector3(0, 1.0, 0))
		npc.state = "free"
		player._update_interact_target()
		print("[2] 放下后准星目标=", player.interact_target, " 提示=", player._prompt_text)
		player._do_interact()
		await get_tree().process_frame
		print("[2] 对话面板可见=", hud.dialogue_ui.visible)
		if not hud.dialogue_ui.visible:
			fails.append("对幸存者按 E 未打开对话")
		else:
			hud.dialogue_ui.visible = false
			hud._open_panels = 0

	# ---- 3. 生物：碰撞体 + 不下沉 + 准星捕猎 ----
	var creature: Creature = null
	for c in get_tree().get_nodes_in_group("creatures"):
		creature = c
		break
	if creature == null:
		fails.append("世界里没有生物")
	else:
		var has_col := false
		for ch in creature.get_children():
			if ch is CollisionShape3D:
				has_col = true
		print("[3] 生物碰撞体=", has_col)
		if not has_col:
			fails.append("生物没有碰撞体（会沉入地下且无法捕猎）")
		var gy0: float = world.height_at(creature.global_position.x, creature.global_position.z)
		await get_tree().create_timer(1.5).timeout  # 物理演化：修复前会一直下沉
		var dy: float = creature.global_position.y - gy0
		print("[3] 生物 1.5s 后相对地面 dy=", dy)
		if dy < -1.5:
			fails.append("生物正在沉入地下（dy=%.2f）" % dy)
		# 冻结其 AI 避免逃跑，贴脸瞄准
		creature.set_physics_process(false)
		var cp := creature.global_position
		player.global_position = cp + Vector3(0, 0.5, 1.6)
		await _aim_at(player, cp + Vector3(0, 0.55, 0))
		# 先持矛，再验提示（无矛时提示是"需要一柄长矛"）。
		# 物理进程每帧刷新准星，可能在持矛前就用旧提示刷过——显式刷新模拟换工具行为
		Game.active_tool = "spear"
		Game.add_item("spear", 1)
		player._refresh_prompt()
		player._update_interact_target()
		print("[3] 准星目标=", player.interact_target, " 提示=", player._prompt_text)
		if player.interact_target != creature:
			fails.append("准星照不到生物")
		elif not (player._prompt_text as String).contains("捕猎"):
			fails.append("生物提示异常: %s" % player._prompt_text)
		player._do_interact()
		await get_tree().process_frame
		print("[3] 捕猎后 dead=", creature.dead, " 冻肉=", Game.count_item("frozen_meat"))
		if not creature.dead:
			fails.append("对生物按 E 未触发捕猎")
		Game.active_tool = ""
		creature.set_physics_process(true)

	# ---- 4. 手部视图模型：空手 / 持刀 / 持矛双手 / 出拳 ----
	var vm: ViewModel = player.viewmodel
	if vm == null:
		fails.append("玩家没有视图模型")
	else:
		print("[4] 视图模型 rig=", vm.rig != null, " 右臂=", vm.arm_r != null, " 左臂=", vm.arm_l != null)
		if vm.rig == null or vm.arm_r == null or vm.arm_l == null:
			fails.append("视图模型结构不完整")
		else:
			Game.active_tool = ""
			await get_tree().process_frame
			await get_tree().process_frame
			print("[4] 空手 item=", vm.item_node, " 左臂可见=", vm.arm_l.visible)
			if vm.item_node != null:
				fails.append("空手状态仍显示持物")
			if vm.arm_l.visible:
				fails.append("空手时左臂应隐藏")
			Game.active_tool = "knife"
			await get_tree().process_frame
			await get_tree().process_frame
			print("[4] 持刀 item=", vm.item_node, " 子节点=", vm.item_node.get_child_count() if vm.item_node else -1)
			if vm.item_node == null or vm.item_node.get_child_count() < 2:
				fails.append("持有小刀但手持模型缺失")
			Game.active_tool = "spear"
			await get_tree().process_frame
			await get_tree().process_frame
			print("[4] 持矛 item 子节点=", vm.item_node.get_child_count() if vm.item_node else -1, " 左臂可见=", vm.arm_l.visible)
			if vm.item_node == null or vm.item_node.get_child_count() < 2:
				fails.append("长矛模型缺失")
			if not vm.arm_l.visible:
				fails.append("持矛时左臂应可见（双手持）")
			vm.punch()
			await get_tree().process_frame
			if vm._punch_t >= 1.0:
				fails.append("出拳动画未触发")
			Game.active_tool = ""

	# ---- 5. 拢雪（含冷却递减修复）+ 通知队列消费 ----
	player.set_facing(player.rotation.y, -1.3)  # 低头看地
	await get_tree().create_timer(0.4).timeout
	player._update_interact_target()
	print("[5] 地面准星目标=", player.interact_target, " 提示=", player._prompt_text)
	if player.interact_target == null or not (player._prompt_text as String).contains("雪"):
		fails.append("准星照不到地面（拢雪失灵）")
	else:
		var snow0 := Game.count_item("snow_brick")
		# 拢雪走 use 动作（森林之子式长按，_update_gather 驱动）
		Input.action_press("use")
		for i in range(14):   # 1.4s > T_PICK_SMALL(1.2s)
			player._update_gather(0.1)
		Input.action_release("use")
		await get_tree().process_frame
		if Game.count_item("snow_brick") <= snow0:
			fails.append("拢雪未获得冰雪砖")
		# 冷却应结束：T_PICK_SMALL(1.2s) 过后再可拢雪，多留 0.1s 余量
		await get_tree().create_timer(1.3).timeout
		var snow1 := Game.count_item("snow_brick")
		Input.action_press("use")
		for i in range(14):
			player._update_gather(0.1)
		Input.action_release("use")
		await get_tree().process_frame
		print("[5] 二次拢雪: ", snow1, " -> ", Game.count_item("snow_brick"))
		if Game.count_item("snow_brick") <= snow1:
			fails.append("拢雪冷却未递减（只能拢一次）")
	var notes0 := hud._notes.size()
	Game.notify("队列测试通知", "info")
	await get_tree().process_frame
	await get_tree().process_frame
	print("[5] 通知队列: 事件残留=", Game.ui_events.size(), " 通知条数=", hud._notes.size())
	if Game.ui_events.size() > 1:
		fails.append("ui_events 未被 HUD 及时消费")
	if hud._notes.size() <= notes0:
		fails.append("通知未显示到左下角")

	# ---- 5b. 通知上限 + tween 安全（复现 previously freed instance）----
	# 同步连发 12 条（HUD 每帧一次消费完队列，_notes 超出 6 条上限即提前释放旧通知），
	# 若被释放通知的淡出 tween 未 kill，6 秒后会向已释放 Label 赋值 → 红错
	var first_label: Control = hud._notes[0].get("label") if hud._notes.size() > 0 else null
	var had_label: bool = first_label != null  # 立即记录：Godot 4 中对象释放后引用会变 null
	var n_before := hud._notes.size()
	for i in range(12):
		Game.notify("轰炸通知 %d" % i, "info")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if hud._notes.size() > 6:
		fails.append("通知超过 6 条上限未裁剪")
	# 最早的通知应已被提前释放——正是触发 bug 的关键路径
	var early_freed: bool = had_label and not is_instance_valid(first_label)
	print("[5b] 上限裁剪: ", n_before, " -> ", hud._notes.size(),
		" 最早通知已提前释放=", early_freed)
	if had_label and not early_freed:
		fails.append("最早通知未被提前释放（未覆盖 bug 路径）")
	# 等 8 秒：覆盖 6s 间隔 + 1.5s 淡出 + 释放。若 tween 未 kill，此刻会向已释放实例赋值
	await get_tree().create_timer(8.0).timeout
	var alive := 0
	for item in hud._notes:
		if is_instance_valid(item.get("label")):
			alive += 1
	print("[5b] 8 秒后仍存活的淡出中通知=", alive, "（容忍期间游戏新通知）",
		" ui_events 残留=", Game.ui_events.size())
	if alive > 2:
		fails.append("8 秒后通知未淡出移除（tween 被提前 kill 或回调失效）: %d" % alive)

	# ---- 5c. 长按 E 采集（森林之子式：按住累积，松手取消，完成才产出） ----
	player.set_facing(player.rotation.y, -1.3)  # 低头看地
	await get_tree().create_timer(0.4).timeout
	player._update_interact_target()
	var hold0 := Game.count_item("snow_brick")
	# 短按（0.3s < T_PICK_SMALL=1.2s）松手取消：不应产出
	Input.action_press("use")
	await get_tree().create_timer(0.3).timeout
	Input.action_release("use")
	await get_tree().process_frame
	var hold_short := Game.count_item("snow_brick")
	# 按住 1.4s（> 冷却）应产出 1 块；进度条应已显示过
	Input.action_press("use")
	await get_tree().create_timer(1.4).timeout
	var mid_prog: float = player.gather_progress()
	Input.action_release("use")
	await get_tree().process_frame
	var hold_long := Game.count_item("snow_brick")
	print("[5c] 长按采集: 短按后=", hold_short, " 长按后=", hold_long, " 按住中进度=", mid_prog)
	if hold_short > hold0:
		fails.append("长按采集：短按 0.3s 不应产出（松手应取消）")
	if hold_long <= hold_short:
		fails.append("长按采集：按住 1.4s 应产出冰雪砖")
	if mid_prog <= 0.0:
		fails.append("采集进度读数不为正（HUD 进度条无数据）")

	# ---- 6. 建造模式：幽灵接线 / 落位 / AABB 重叠拒绝 ----
	Game.add_item("wood", 40)
	if is_instance_valid(Game.hud):
		Game.hud.open_build_with("wood_wall")
	await get_tree().process_frame
	await get_tree().process_frame
	var bld: Builder = player.builder
	print("[6] build_mode=", Game.build_mode, " key=", bld.current_key,
		" ghost_visible=", bld.ghost.visible if bld.ghost else false)
	if not Game.build_mode:
		fails.append("建造模式未开启")
	if bld.current_key != "wood_wall":
		fails.append("选中做法未交给 Builder（幽灵不会显示）")
	if bld.ghost and not bld.ghost.visible:
		fails.append("幽灵预览未显示")
	var n0 := Game.buildings.size()
	var gx: float = player.global_position.x + 40.0
	var gz: float = player.global_position.z + 40.0
	var gy: float = Game.world.height_at(gx, gz) if (is_instance_valid(Game.world) and Game.world.has_method("height_at")) else 0.0
	var wp := Vector3(gx, gy + 1.3, gz)
	bld.ghost.position = wp
	bld._try_place()
	await get_tree().process_frame
	print("[6] 首次落位: ", n0, " -> ", Game.buildings.size())
	if Game.buildings.size() <= n0:
		fails.append("建造落位失败（材料够、空地应放得下）")
	# 同一位置再放：AABB 重叠应拒绝（先清掉放置冷却，单独验校验本身）
	bld.ghost.position = wp
	bld._place_cd = 0.0
	var n1 := Game.buildings.size()
	bld._try_place()
	await get_tree().process_frame
	print("[6] 重叠位置: ", n1, " -> ", Game.buildings.size())
	if Game.buildings.size() != n1:
		fails.append("重叠位置未被拒绝（AABB 校验失效）")
	# 贴建允许：3m 墙平移 3m 属于严丝合缝，应放得下
	if Game.buildings.size() > n0:
		var first: Dictionary = Game.buildings[n0]
		var fp: Array = first.get("pos", [0, 0, 0])
		bld.ghost.position = Vector3(float(fp[0]) + 3.0, float(fp[1]), float(fp[2]))
		bld._place_cd = 0.0
		var n2 := Game.buildings.size()
		bld._try_place()
		await get_tree().process_frame
		print("[6] 贴建 3m: ", n2, " -> ", Game.buildings.size())
		if Game.buildings.size() <= n2:
			fails.append("严丝合缝的贴建被误拒（自由搭建受阻）")
	# 退出建造
	bld._back_to_menu()
	await get_tree().process_frame
	if Game.build_mode:
		fails.append("退出建造模式失败")

	# ---- 7. 可采物件：长按砍伐（ResourceNode gather_time） ----
	if is_instance_valid(Game.hud):
		Game.hud._close_all()   ## 建造返回时面板开着，先关掉才能采集
	var tree := ResourceNode.new()
	tree.setup({"id": "dead_tree", "name": "枯树", "uses": 2, "gather_time": 1.0,
		"gather_verb": "砍伐",
		"loot": [{"id": "wood", "min": 2, "max": 2, "chance": 1.0}]})
	Game.world.add_child(tree)
	var w0 := Game.count_item("wood")
	player.interact_target = tree
	player._gather_t = 0.0
	player._gather_total = 0.0
	Input.action_press("use")
	for i in range(12):
		player._update_gather(0.1)   # 模拟按住 1.2s（> gather_time 1.0）
	Input.action_release("use")
	await get_tree().process_frame
	var w1 := Game.count_item("wood")
	var before_press := Game.count_item("wood")
	player._do_interact()   # 瞬按长按采集物：不应产出
	await get_tree().process_frame
	print("[7] 砍伐枯树: wood ", w0, " -> ", w1, " 瞬按后=", Game.count_item("wood"),
		" 提示=", tree.get_prompt(player))
	if w1 <= w0:
		fails.append("长按砍伐未获得木头")
	if Game.count_item("wood") != before_press:
		fails.append("长按采集物被瞬按触产出（必须是按住）")
	player.interact_target = null

	# ---- 8. 徒手合成（背包两件一碰）+ 快捷轮盘 ----
	# 开局只有 6 槽（DV.INV_BASE_SLOTS）：前置流程的随机战利品会占满，
	# 清空后 determinism 测合成本身（容量压力由 [11] 与游戏内体验覆盖）
	Game.inventory.slots.clear()
	Game.add_item("cloth", 6)
	var r0 := Game.count_item("rope")
	var rid := Recipes.combo_id("cloth", "cloth")
	print("[8] combo(cloth,cloth)=", rid)
	if rid != "rope_from_cloth":
		fails.append("徒手合成配对失败（布+布应得捻绳）")
	var res := Game.craft_recipe(rid)
	await get_tree().process_frame
	print("[8] 合成: ok=", res.get("ok", false), " rope ", r0, " -> ", Game.count_item("rope"),
		" cloth 剩=", Game.count_item("cloth"))
	if not res.get("ok", false):
		fails.append("徒手合成执行失败")
	if Game.count_item("rope") <= r0:
		fails.append("合成未产出绳索")
	if Game.count_item("cloth") != 3:
		fails.append("合成未正确扣除材料（6 布应剩 3）")
	# 轮盘：有工具/消耗品时应有条目；执行工具条目应换手持
	Game.add_item("knife", 1)
	if is_instance_valid(Game.hud):
		var ents := Game.hud._wheel_entries()
		print("[8] 轮盘条目=", ents.size())
		if ents.is_empty():
			fails.append("快捷轮盘无条目（包里有刀/布条时应有）")
		Game.active_tool = ""
		Game.hud._wheel_execute({"kind": "tool", "id": "knife", "label": "小刀"})
		await get_tree().process_frame
		print("[8] 轮盘执行后 active_tool=", Game.active_tool)
		if Game.active_tool != "knife":
			fails.append("轮盘执行工具条目未换手持")

	# ---- 9. 任意长度墙（滚轮伸缩 + AABB 按实际长度） ----
	if is_instance_valid(Game.hud):
		Game.hud._close_all()
	Game.add_item("wood", 60)
	Game.hud.open_build_with("wood_wall")
	await get_tree().process_frame
	await get_tree().process_frame
	bld._place_cd = 0.0
	bld._len = 0.0
	bld._adjust_len(3.0)   # 默认 3m + 3m = 6m
	bld._adjust_len(0.5)   # 6.5m？不对——从默认起算：3+3+0.5=6.5
	print("[9] 伸缩后 piece_size=", bld._piece_size(), " len=", bld._len)
	if absf(bld._piece_size().x - 6.5) > 0.01:
		fails.append("滚轮伸缩长度不对（3m 默认 +3.5m 步进应为 6.5m）")
	var sx: float = player.global_position.x + 60.0
	var sz: float = player.global_position.z + 60.0
	var sy2: float = Game.world.height_at(sx, sz) if (is_instance_valid(Game.world) and Game.world.has_method("height_at")) else 0.0
	bld.ghost.position = Vector3(sx, sy2 + 1.3, sz)
	bld._place_cd = 0.0
	bld._try_place()
	await get_tree().process_frame
	var placed: Dictionary = Game.buildings[-1] if Game.buildings.size() > 0 else {}
	print("[9] 长墙落位: len=", placed.get("len", 0.0))
	if absf(float(placed.get("len", 0.0)) - 6.5) > 0.01:
		fails.append("长墙落位未记录 len")
	# 6.5m 墙中点放 3m 墙：dx=4 < (6.5+3)/2-0.06=4.69 → 应被拒
	bld._len = 0.0
	bld.ghost.position = Vector3(sx + 4.0, sy2 + 1.3, sz)
	bld._place_cd = 0.0
	var n9 := Game.buildings.size()
	bld._try_place()
	await get_tree().process_frame
	print("[9] 压着长墙放: ", n9, " -> ", Game.buildings.size())
	if Game.buildings.size() != n9:
		fails.append("压着 6.5m 长墙的位置未被拒（AABB 未按伸缩长度算）")
	# 贴到长墙边缘：dx = 6.5/2 + 3/2 = 4.75 > 4.69 → 应放得下
	bld.ghost.position = Vector3(sx + 4.75, sy2 + 1.3, sz)
	bld._place_cd = 0.0
	bld._try_place()
	await get_tree().process_frame
	print("[9] 贴长墙边缘放: ", n9, " -> ", Game.buildings.size())
	if Game.buildings.size() <= n9:
		fails.append("贴长墙边缘的墙被误拒")
	bld._back_to_menu()
	await get_tree().process_frame

	# ---- 10. 背包网格：大件占位 + 拖动整理 ----
	Game.add_item("knife", 1)
	Game.add_item("wood", 10)
	var inv := Game.hud.inv_ui
	inv.refresh()
	var lay := inv._layout()
	print("[10] 网格布局项数=", lay.size())
	var knife_fp := Vector2i(0, 0)
	for e in lay:
		if String(e["id"]) == "knife":
			knife_fp = Vector2i(int(e["w"]), int(e["h"]))
	if knife_fp != Vector2i(2, 2):
		fails.append("工具应占 2×2 格（实际 %s）" % str(knife_fp))
	if inv._pos.has("knife") == false:
		fails.append("网格布局未记录刀的位置")
	# 拖动整理：拿起刀 → 挪到空格 (5,3)
	inv._held = "knife"
	if not inv._cell_free_for("knife", Vector2i(5, 3)):
		fails.append("空格 (5,3) 对刀应空闲")
	inv._on_cell(Vector2i(5, 3))
	await get_tree().process_frame
	print("[10] 拖动后刀的位置=", inv._pos.get("knife"))
	if inv._pos.get("knife") != Vector2i(5, 3):
		fails.append("拖动整理未生效")
	# 占用的格不能再放（把木头指向刀的 2×2 区域应失败）
	inv._held = "wood"
	if inv._cell_free_for("wood", Vector2i(5, 3)):
		fails.append("已占用格应判定为不可放")
	inv._held = ""
	# 网格总容量：40 格，当前占用应 < 40
	var cells := 0
	for e in inv._layout():
		cells += int(e["w"]) * int(e["h"])
	print("[10] 占用格子=", cells, "/", DV.INV_GRID_COLS * DV.INV_GRID_ROWS)
	if cells <= 0:
		fails.append("网格占用计数异常")

	# ---- 11. 拆除回收：长按拆墙返料 ----
	if is_instance_valid(Game.hud):
		Game.hud._close_all()
	# 前置流程的随机战利品可能已占满基础 12 槽（包满时连背包都加不进来）——
	# 拆除返料是被测对象，清空后 determinism 测试
	Game.inventory.slots.clear()
	Game.add_item("wood", 20)
	var wd0 := Game.count_item("wood")
	var bn := Game.buildings.size()
	var first_node = Game.buildings[0].get("node") if Game.buildings.size() > 0 else null
	print("[11] 拆除前: buildings=", bn, " wood=", wd0, " 槽位=", Game.inventory.used(), "/", Game.inventory.capacity())
	if first_node == null:
		fails.append("没有可拆的建筑（前置 [6][9] 应已放置）")
	else:
		player.interact_target = first_node
		player._gather_t = 0.0
		player._gather_total = 0.0
		Input.action_press("use")   # 拆除走 use 动作（与采集同链 _update_gather）
		for i in range(18):
			player._update_gather(0.1)   # 1.8s > DV.T_DEMOLISH(1.5s)
		Input.action_release("use")
		await get_tree().process_frame
		print("[11] 拆除后: buildings=", Game.buildings.size(), " wood=", Game.count_item("wood"))
		if Game.buildings.size() != bn - 1:
			fails.append("拆除未移除建筑")
		if Game.count_item("wood") <= wd0:
			fails.append("拆除未返还材料")
		player.interact_target = null

	# ---- 12. 狼群攻击模型：感知 50m 逼近 → 1m 撕咬掉血 ----
	var wolf: Creature = null
	for c in get_tree().get_nodes_in_group("creatures"):
		if String(c.species) == "wolf":
			wolf = c
			break
	if wolf == null:
		fails.append("世界里没有狼（捕食者缺失）")
	else:
		var hp0: float = Game.health
		var wx := player.global_position.x + 40.0
		var wz := player.global_position.z
		var wy: float = world.height_at(wx, wz) if is_instance_valid(world) else 0.0
		wolf.global_position = Vector3(wx, wy + 0.3, wz)
		wolf.ai_state = "wander"
		wolf.set_physics_process(true)
		await get_tree().create_timer(3.5).timeout
		var wdist: float = wolf.global_position.distance_to(player.global_position)
		print("[12] 狼 3.5s 后: 距玩家=", wdist, " 状态=", wolf.ai_state)
		if wdist > 35.0:
			fails.append("狼未在 50m 感知内逼近（dist=%.1f state=%s）" % [wdist, wolf.ai_state])
		# 贴到 1m 内触发撕咬
		wolf.global_position = player.global_position + Vector3(0.8, 0, 0)
		wolf.ai_state = "charge"
		await get_tree().create_timer(0.3).timeout
		print("[12] 撕咬后: 血量 ", hp0, " -> ", Game.health, " 狼状态=", wolf.ai_state)
		if Game.health >= hp0:
			fails.append("狼贴近后未造成伤害（攻击模型失效）")
		# 收摊：停掉这只狼，避免继续掉血影响后续
		wolf.dead = true
		wolf.set_physics_process(false)
		wolf.queue_free()

	# ---- 13. 分块随机扩充：ChunkManager 流式加载 + 确定性 ----
	var cm: ChunkManager = null
	for ch in world.get_children():
		if ch is ChunkManager:
			cm = ch
			break
	print("[13] ChunkManager=", cm != null, " 已加载块=", cm.loaded.size() if cm else 0)
	if cm == null:
		fails.append("世界没有挂 ChunkManager（分块扩充失效）")
	else:
		if cm.loaded.size() < 9:
			fails.append("初始块加载不足 3×3（实际 %d）" % cm.loaded.size())
		var total := 0
		for k in cm.loaded.keys():
			total += cm.loaded[k].size()
		print("[13] 初始 POI 节点总数=", total)
		if total <= 0:
			fails.append("初始 9 块没有生成任何 POI（冰原是空的）")
		# 确定性：同坐标同值、异坐标异值
		var r1: float = cm._rnd(3, 7, 42)
		var r2: float = cm._rnd(3, 7, 42)
		var r3: float = cm._rnd(3, 8, 42)
		if r1 != r2:
			fails.append("块随机数不确定（同坐标两次取值不同）")
		if r1 == r3:
			fails.append("不同块坐标随机数相同（哈希失效）")
		# 走远应卸载旧块
		var had_key: bool = cm.loaded.has("0,0")
		player.global_position = Vector3(400.0, world.height_at(400.0, 400.0) + 0.5, 400.0)
		await get_tree().create_timer(0.5).timeout
		var still: bool = cm.loaded.has("0,0")
		print("[13] 走远后: 原(0,0)块曾加载=", had_key, " 现在还在=", still)
		if had_key and still:
			fails.append("走远后旧块未卸载")
		# 生态：设计区 6 只保底（2狼2鹿2兔），区块野生动物在此之上涌现
		var n_creatures: int = get_tree().get_nodes_in_group("creatures").size()
		print("[13] 当前生物总数=", n_creatures, "（设计区保底 6 + 区块涌现）")
		if n_creatures < 6:
			fails.append("生物少于设计区保底 6 只")

	print("")
	if fails.is_empty():
		print("===== 内容测试全部通过 =====")
	else:
		print("===== 失败项 =====")
		for f in fails:
			print(" - ", f)
	get_tree().quit(0 if fails.is_empty() else 1)

## 把玩家准星精确指向 target（先等落地，按实际眼位解算 yaw/pitch）
## 走 set_facing：同时写入平滑目标并即时落位，否则会被 _apply_view_smoothing 拉回
func _aim_at(player: Player, target: Vector3) -> void:
	await get_tree().create_timer(0.4).timeout  # 等落地
	var eye: Vector3 = player.global_position + Vector3(0, 1.62, 0)
	var delta: Vector3 = target - eye
	var horiz: float = Vector2(delta.x, delta.z).length()
	player.set_facing(atan2(-delta.x, -delta.z), clampf(atan2(delta.y, horiz), -1.4, 1.4))
	await get_tree().create_timer(0.1).timeout
