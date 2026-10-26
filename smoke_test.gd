extends Node
## 无头冒烟测试：实例化主场景 → 物品/配方/建造/天灾/存读档/结局 全流程

var fails: Array = []

func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# ---- 1. 跳过开场，进入游戏 ----
	Game.player_name = "测试者"
	Game.profession = "medic"
	Game.started = true
	# 开局只有 6 槽（DV.INV_BASE_SLOTS）：全流程会累积十几种物品，
	# 先发两个包扩容（顺便覆盖背包扩容路径），避免容量预检把后续添加全拒
	Game.add_item("backpack", 2)
	if Game.hud and Game.hud.intro:
		Game.hud.intro.visible = false
	print("[1] 开场跳过 ok, started=", Game.started, " player=", Game.player != null, " 容量=", Game.inventory_capacity())

	# ---- 2. 物品 ----
	for id in ["wood", "stone", "rope", "matches", "cloth", "scrap"]:
		Game.add_item(id, 5)
	if Game.count_item("wood") < 5:
		fails.append("物品增减异常")
	print("[2] 背包 ok: wood=", Game.count_item("wood"), " 容量=", Game.inventory_capacity())

	# ---- 3. 配方 ----
	for rid in ["campfire", "spear"]:
		Game.learn_recipe(rid)
	var can: bool = Recipes.can_make("campfire")
	print("[3] 配方 ok, campfire 可做=", can)

	# ---- 4. 建造 ----
	var bd: Builder = Game.player.builder
	var pos := Vector3(round(Game.player.global_position.x), 0.0, round(Game.player.global_position.z + 3.0))
	var before := Game.buildings.size()
	var entry := {"type": "campfire", "pos": [pos.x, pos.y, pos.z], "rot": 0.0}
	Game.buildings.append(entry)
	bd.spawn_building(entry)
	if Game.buildings.size() <= before:
		fails.append("建造登记失败")
	print("[4] 建造 ok, buildings=", Game.buildings.size())

	# ---- 5. 家与庇护所 ----
	Game.has_home = true
	Game.home_center = Vector3(pos.x, 0.0, pos.z)
	Game.home_type = "campfire"
	Game.shelter_level = ShelterJudge.compute(Game.buildings, Game.home_center)
	print("[5] 庇护所等级=", Game.shelter_level)

	# ---- 6. 天灾逐类触发 ----
	for kind in ["cold_wave", "blizzard", "ice_collapse", "ruin_collapse", "meteor"]:
		Game.health = 100.0
		Game.world.trigger_disaster(kind)
		await get_tree().create_timer(0.3).timeout
		if Game.game_over:
			fails.append("天灾致死: " + kind)
			Game.game_over = false
			Game.health = 100.0
	print("[6] 天灾五种全部触发 ok, state=", Game.disaster_state, " health=", Game.health)

	# ---- 7. 存档 / 读档 ----
	Game.set_flag("smoke_test", true)
	Game.add_clue("clue_01")
	if not Game.save_game():
		fails.append("存档失败")
	Game.buildings.clear()
	Game.set_flag("smoke_test", false)
	if not Game.load_game():
		fails.append("读档失败")
	if not Game.get_flag("smoke_test"):
		fails.append("读档后 flag 丢失")
	print("[7] 存读档 ok, flag=", Game.get_flag("smoke_test"), " clues=", Game.clues.size())

	# ---- 8. 结局 ----
	for sid in ["true", "rongdian", "home", "alone", "extinguished"]:
		if not Endings.ENDINGS.has(sid):
			fails.append("结局缺定义: " + sid)
	var eid := Endings.evaluate()
	print("[8] 结局 ok, 当前判定=", eid)

	# ---- 9. 时间快进（周制天灾调度）----
	Game.day = 7
	Game.hour = 23.5
	Game.next_disaster_day = 7.0
	Game.tick_disasters(120.0)
	print("[9] 天灾调度 ok, state=", Game.disaster_state, " count=", Game.disaster_count)

	# ---- 10. 生物与NPC ----
	var creatures := get_tree().get_nodes_in_group("creatures")
	var npcs: Array = get_tree().get_nodes_in_group("npcs") if get_tree().has_group("npcs") else []
	print("[10] 生物=", creatures.size(), " NPC=", npcs.size())
	if creatures.is_empty():
		fails.append("世界没有生成生物")
	if npcs.is_empty():
		fails.append("世界没有生成幸存者")

	# ---- 11. 完整循环：占地基 → 建造 → 制作 → 睡眠 → 解冻 → 加入 → 捕猎 → 终端 → 结局 ----
	Game.player.control_enabled = true
	# 11.1 找一处地基占为家（保安亭）
	Game.has_home = false
	Game.home_type = ""
	Game.home_center = Vector3.ZERO
	var foundation: FoundationMarker = null
	for ch in Game.world.get_children():
		if ch is FoundationMarker:
			foundation = ch
			break
	if foundation == null:
		fails.append("找不到可占地基")
	else:
		foundation.interact(Game.player)
		if not Game.has_home:
			fails.append("占地基失败")
	print("[11.1] 占地基 ok, home=", Game.home_type, " center=", Game.home_center)

	# 11.2 在家附近搭一套：墙×4 + 顶 + 床 + 箱 + 篝火
	# 先清空：[4] 的篝火可能被 [6] 的天灾随机摧毁/残留，带着它画图纸会因
	# "离家太远"随机失败——家的布置从这套开始算
	Game.buildings.clear()
	Game.add_item("wood", 40)
	Game.add_item("cloth", 10)
	Game.add_item("rope", 6)
	Game.add_item("stone", 10)
	var hc: Vector3 = Game.home_center
	var layout := [
		{"type": "wood_wall", "pos": [hc.x + 2.5, hc.y, hc.z]},
		{"type": "wood_wall", "pos": [hc.x - 2.5, hc.y, hc.z]},
		{"type": "wood_wall", "pos": [hc.x, hc.y, hc.z + 2.5]},
		{"type": "wood_wall", "pos": [hc.x, hc.y, hc.z - 2.5]},
		{"type": "wood_roof", "pos": [hc.x, hc.y + 2.6, hc.z]},
		{"type": "bed", "pos": [hc.x + 1.0, hc.y, hc.z + 1.0]},
		{"type": "storage", "pos": [hc.x - 1.2, hc.y, hc.z + 1.0]},
		{"type": "campfire", "pos": [hc.x, hc.y, hc.z - 3.5]},
	]
	for b in layout:
		Game.buildings.append(b)
		Game.player.builder.spawn_building(b)
	Game.shelter_level = ShelterJudge.compute(Game.buildings, Game.home_center)
	if Game.shelter_level < 2:
		fails.append("庇护所等级异常: %d" % Game.shelter_level)
	print("[11.2] 建造 ok, 庇护所=", Game.shelter_level, " ", BuildingDefs.level_name(Game.shelter_level))

	# 11.3 制作：长矛 + 火边烤肉（把玩家放到篝火边）
	Game.learn_recipe("spear")
	Game.learn_recipe("cook_meat")
	if not Recipes.can_make("spear"):
		fails.append("长矛材料校验失败")
	for mid in Recipes.def("spear").get("inputs", {}):
		Game.remove_item(String(mid), int(Recipes.def("spear").inputs[mid]))
	Game.add_item("spear", 1)
	Game.active_tool = "spear"
	Game.player.global_position = hc + Vector3(0, 0.2, -2.5)
	Game.player.survival._update_fire_and_shelter()
	if Game.fire_strength <= 0.0:
		fails.append("篝火热区未生效")
	Game.add_item("frozen_meat", 1)
	if not (Recipes.can_make("cook_meat") and Recipes.station_ok("cook_meat")):
		fails.append("火边烤肉条件异常")
	print("[11.3] 制作 ok, 火源强度=", Game.fire_strength)

	# 11.4 睡一觉（床就在家旁边）
	var slept: bool = Game.player.survival.try_sleep(hc + Vector3(1.0, 0, 1.0))
	if not slept or Game.fatigue > 60.0:
		fails.append("睡眠异常")
	print("[11.4] 睡眠 ok, 第", Game.day, "天 ", "%.1f" % Game.hour, "时 疲劳=", int(Game.fatigue))

	# 11.5 解冻一名幸存者并让她加入（林晚：需要旧照片）
	var npc: SurvivorNPC = null
	for ch in Game.world.get_children():
		if ch is SurvivorNPC and ch.sid == "linwan":
			npc = ch
			break
	if npc == null:
		fails.append("找不到林晚")
	else:
		npc.global_position = hc + Vector3(1.5, 0, -3.0)
		npc.thaw = 21.9
		npc._finish_thaw()
		if npc.state != "free":
			fails.append("解冻失败")
		Game.add_item("old_photo", 1)
		var chk: Dictionary = npc.join_check()
		if not chk.get("ok", false):
			fails.append("加入条件异常: " + String(chk.get("reason", "")))
		else:
			npc.join()
			if Game.companions.size() != 1:
				fails.append("加入后同伴数异常")
	print("[11.5] 同伴 ok, companions=", Game.companions.size())

	# 11.6 捕猎：把一只雪兔放到面前，用长矛一次了结
	var prey: Creature = null
	for ch in Game.world.get_children():
		if ch is Creature and ch.species == "rabbit" and not ch.dead:
			prey = ch
			break
	if prey == null:
		fails.append("找不到可捕猎生物")
	else:
		var meat_before := Game.count_item("frozen_meat")
		prey.global_position = Game.player.global_position + Vector3(1.2, 0, 0)
		prey.try_harvest(Game.player)
		if not prey.dead or Game.count_item("frozen_meat") <= meat_before:
			fails.append("捕猎掉落异常")
	print("[11.6] 捕猎 ok")

	# 11.7 点亮融点终端 → 结局判定
	for cid in ["clue_01", "clue_02", "clue_03", "clue_04", "clue_05", "clue_06", "clue_07", "clue_08"]:
		Game.add_clue(cid)
	var term: TerminalInteract = null
	for ch in Game.world.get_children():
		if ch is TerminalInteract:
			term = ch
			break
	if term == null:
		fails.append("找不到融点终端")
	else:
		term.interact(Game.player)
		if not Game.get_flag("terminal_done"):
			fails.append("终端点亮失败")
	print("[11.7] 终端 ok, 结局判定=", Endings.evaluate())

	# ---- 12. 图纸：自绘保存 → 一键复刻 → 防烂尾 ----
	if Game.player and Game.player.builder:
		Game.add_item("backpack", 1)   # 先扩容，保证测试料装得下
		Game.add_item("wood", 100)
		Game.add_item("stone", 100)
		Game.add_item("cloth", 50)
		Game.add_item("rope", 50)
		Game.add_item("matches", 20)
		Game.add_item("snow_brick", 50)
		var captured: Dictionary = Game.player.builder.capture_blueprint("测试图纸")
		if (captured.get("layout", []) as Array).is_empty():
			fails.append("图纸保存为空")
		Game.buildings.clear()
		var rb: Dictionary = Game.player.builder.apply_blueprint(captured)
		if not rb.get("ok", false):
			fails.append("一键放置失败: " + String(rb.get("why", "")))
		elif Game.buildings.size() != 8:
			fails.append("图纸复刻数量异常: %d" % Game.buildings.size())
		# 重叠拒绝：原样再放一张，应被挡下
		var rb2: Dictionary = Game.player.builder.apply_blueprint(captured)
		if rb2.get("ok", false):
			fails.append("重叠图纸未被拒绝")
		# 材料不足拒绝：清空石块，风雪堡垒应放不成
		Game.buildings.clear()
		Game.remove_item("stone", Game.count_item("stone"))
		var rb3: Dictionary = Game.player.builder.apply_blueprint(BlueprintPresets.all()[1])
		if rb3.get("ok", false):
			fails.append("材料不足时图纸仍然放置成功")
		if not Game.buildings.is_empty():
			fails.append("失败的图纸放置留下了半拉子建筑")
		# 料补足，他人图纸「火塘小屋」一键落成
		Game.add_item("stone", 100)
		var rb4: Dictionary = Game.player.builder.apply_blueprint(BlueprintPresets.all()[0])
		if not rb4.get("ok", false):
			fails.append("他人图纸放置失败: " + String(rb4.get("why", "")))
		Game.shelter_level = ShelterJudge.compute(Game.buildings, Game.home_center)
		print("[12] 图纸 ok, 当前建筑=", Game.buildings.size(), " 庇护所=", Game.shelter_level)
		if Game.shelter_level < 2:
			fails.append("图纸放置后庇护所等级异常")
	else:
		fails.append("找不到建造器")

	print("")
	if fails.is_empty():
		print("===== 冒烟测试全部通过 =====")
	else:
		print("===== 失败项 =====")
		for f in fails:
			print(" - ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
