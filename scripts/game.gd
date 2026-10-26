extends Node
## 《融点》全局状态中枢（autoload）
## 时间 / 身体 / 物品 / 家 / 同伴 / 故事 / 天灾 的唯一真相来源。

signal notified(text: String, kind: String)
## 以下信号由各系统跨类发射/连接（Game 本类内不直接使用），
## 加注解消除"declared but never explicitly used"静态警告
@warning_ignore("unused_signal")
signal prompt_changed(text: String)
@warning_ignore("unused_signal")
signal stats_changed()
@warning_ignore("unused_signal")
signal inventory_changed()
@warning_ignore("unused_signal")
signal clue_added(id: String)
@warning_ignore("unused_signal")
signal companion_joined(npc_name: String)
@warning_ignore("unused_signal")
signal disaster_started(kind: String)
@warning_ignore("unused_signal")
signal disaster_warning(kind: String)

const SAVE_PATH := "user://rongdian_save.json"

const DEFAULT_RECIPES := [
	"rope_from_cloth", "snow_brick_press", "campfire", "wood_wall", "wood_door",
	"wood_roof", "stone_wall", "snow_wall", "bed", "storage",
	"bandage", "cloth_coat", "melt_water", "cook_meat",
]

var player: Player = null
var world: WorldGen = null
var hud: HUD = null
var sound: Node = null   ## 程序化音频层（SoundBox，main.gd 挂载）：风/脚步/火/操作声

## UI 事件队列：Game/场景系统只入队，HUD 每帧在自身存活时消费。
## 信号直连 HUD 曾在场景重载时广播到已释放实例（assign to freed instance），
## 队列制从架构上杜绝整类问题。notified 信号保留发射，供外部监听。
var ui_events: Array[Dictionary] = []

# ---------- 时间 / 天气 ----------
var day: int = 1
var hour: float = 8.5
const MINUTES_PER_SECOND: float = 1440.0 / DV.SEC_PER_DAY   ## 1 游戏日 = DV.SEC_PER_DAY 现实秒（当前 3600s=60min/日 → 0.4 游戏分钟/现实秒）
var weather: String = "clear"                  # clear / snow / blizzard
var weather_left: float = 0.0
var wind: float = 0.0
var world_seed: int = 20261015

# ---------- 身体（单数人称：只写"我"） ----------
var body_temp: float = 36.8
var core_temp: float = DV.CORE_TEMP_NORMAL   # 核心体温（Cold Lag 四档判据）
var perceived_temp: float = 36.8
var hunger: float = 8.0
var thirst: float = 8.0
var fatigue: float = 8.0
var health: float = 100.0
var wet: float = 0.0
var sleeping: bool = false
var hypothermia_tier: int = 0                  # 0 无 / 1 轻 / 2 中 / 3 重
# ---------- 疾病（个体状态机，零传染性） ----------
var diseases: Array[Dictionary] = []           # [{"id", "stage" 0-3, "t" 游戏分钟}]
var drug_resist: Dictionary = {}               # {"disease_id": 0-0.9}
var drug_resist_day: Dictionary = {}           # {"disease_id": 上次用药游戏日}
# ---------- 热引擎（T0 层 10Hz） ----------
var heat_surplus: String = "tight"             # rich 富足 / tight 紧平衡 / deficit 赤字
var q_in: float = 0.0                          # 当前 ΣQ_in (W)
var q_out: float = 0.0                         # 当前 ΣQ_out (W)
var c_total: float = 50000.0                   # 营地总热容 J/K
var camp_temp: float = -20.0                   # 营地核心温度 °C
var season: String = "winter"                  # winter/early_spring/mid_spring/late_spring
var disaster_lambda: float = 0.15              # 当前 λ（泊松速率/游戏日）

# ---------- 物品 ----------
var inventory: Inventory = null
var active_tool: String = ""
var known_recipes: Dictionary = {}
# ---------- 玩家成长（5 属性 + 75 技能） ----------
var attributes := {"physique": 5.0, "perception": 5.0, "intelligence": 5.0,
	"willpower": 5.0, "charisma": 5.0}
var skill_levels: Dictionary = {}       ## {"skill_id": level 1-5}
var skill_last_used: Dictionary = {}    ## {"skill_id": 使用时的游戏日}
var skill_points: int = 2
var _skill_point_level := 1   ## 已按章节发放技能点的等级（避免重复发放）

# ---------- 家 / 建造 ----------
var has_home: bool = false
var home_type: String = ""
var home_center: Vector3 = Vector3.ZERO
var buildings: Array[Dictionary] = []
var shelter_level: int = 0
var build_mode: bool = false
# ---------- 图纸（自绘复用 / 一键导入他人）----------
var blueprints: Array[Dictionary] = []   # [{"name": String, "layout": [{"type","dx","dz","rot"}]}]

# ---------- 同伴 ----------
var companions: Variant = []

# ---------- 故事 ----------
var clues: Dictionary = {}
# ---------- E 系证据链 ----------
var evidence: Array[Dictionary] = []            # [{"id","state","readability","found_day"}]
var flags: Dictionary = {}
var player_name: String = ""
var profession: String = ""
var endings_seen: Array = []

# ---------- 天灾 ----------
var disaster_interval: float = 7.0             # 游戏天数；改为 168.0 即"现实一周"
var next_disaster_day: float = 7.0
var disaster_state: String = "idle"            # idle / warning / active / aftermath
var disaster_type: String = ""
var disaster_count: int = 0
var disaster_timer: float = 0.0
var disaster_intensity: float = 1.0            # 强度演进（每15天+10% × StressMultiplier）
var disaster_history: Array = []               # 历次灾难的游戏日时间戳（24h 窗口/最小间隔）
var last_disaster_at: float = -99.0            # 上次灾难的游戏日（浮点）

# ---------- 环境（由 day_night 每帧写入） ----------
var ambient_temp: float = -12.0
var night_mix: float = 0.0
var fire_strength: float = 0.0    # 0..1，由 survival 每帧写入
var indoors: bool = false         # 是否处于有顶庇护所内
var home_fire_bonus: float = 0.0  # 终端点亮后的广域供热

func near_fire_strength() -> float:
	return fire_strength

# ---------- 运行态 ----------
var started: bool = false
var game_over: bool = false
var game_minutes: float = 0.0
var disaster_cold: float = 0.0        # 寒潮附加降温
var pending_load: bool = false        # 菜单请求读档后重载场景
var load_pos: Vector3 = Vector3.ZERO
var load_rot: float = 0.0
var loaded_companions: Array = []

func _ready() -> void:
	inventory = Inventory.new()
	process_mode = Node.PROCESS_MODE_ALWAYS

func new_game() -> void:
	day = 1
	hour = 8.5
	weather = "clear"
	weather_left = 0.0
	wind = 0.0
	body_temp = 36.8
	core_temp = DV.CORE_TEMP_NORMAL
	perceived_temp = 36.8
	camp_temp = DV.CH01_TEMP
	heat_surplus = "tight"
	q_in = 0.0
	q_out = 0.0
	c_total = 50000.0
	season = "winter"
	disaster_lambda = DV.LAMBDA_BY_SEASON.winter
	hunger = 8.0
	thirst = 8.0
	fatigue = 8.0
	health = 100.0
	wet = 0.0
	sleeping = false
	hypothermia_tier = 0
	diseases.clear()
	drug_resist = {}
	drug_resist_day = {}
	inventory = Inventory.new()
	active_tool = ""
	known_recipes = {}
	attributes = {"physique": 5.0, "perception": 5.0, "intelligence": 5.0,
		"willpower": 5.0, "charisma": 5.0}
	skill_levels = {}
	skill_last_used = {}
	skill_points = 2
	_skill_point_level = 1
	for r in DEFAULT_RECIPES:
		known_recipes[r] = true
	has_home = false
	home_type = ""
	home_center = Vector3.ZERO
	buildings.clear()
	shelter_level = 0
	build_mode = false
	blueprints.clear()
	companions.clear()
	clues.clear()
	flags.clear()
	evidence.clear()
	player_name = ""
	profession = ""
	next_disaster_day = disaster_interval
	disaster_state = "idle"
	disaster_type = ""
	disaster_count = 0
	disaster_cold = 0.0
	disaster_intensity = 1.0
	disaster_history.clear()
	last_disaster_at = -99.0
	ui_events.clear()
	started = false
	game_over = false
	game_minutes = 0.0

# ---------- 时间 ----------

func advance_time(minutes: float) -> void:
	game_minutes += minutes
	hour += minutes / 60.0
	while hour >= 24.0:
		hour -= 24.0
		day += 1
		_on_new_day()
	if weather_left > 0.0:
		weather_left -= minutes
		if weather_left <= 0.0 and weather != "clear":
			weather = "clear"
			notify("风雪停了，天光重新透下来。", "good")

func _on_new_day() -> void:
	notify("第 %d 天。你还在。" % day, "info")
	# 章节等级提升 → 按 DV.SKILL_POINTS_PER_LEVEL 发放技能点（玩家成长文档）
	var lvl := player_level()
	if lvl > _skill_point_level:
		var gained := (lvl - _skill_point_level) * DV.SKILL_POINTS_PER_LEVEL
		skill_points += gained
		_skill_point_level = lvl
		notify("阅历又深了一层——技能点 +%d。" % gained, "good")
	# 一局走到尽头（DV.TOTAL_DAYS）：通知玩家，但绝不重置世界状态
	if day >= DV.TOTAL_DAYS and not get_flag("season_end"):
		set_flag("season_end", true)
		notify("一局的时间到了。风雪未停，但这一程，你走完了。", "review")
	# 同伴进食：人多意味着要养更多张嘴
	for c in companions:
		if c.has_method("on_new_day"):
			c.on_new_day()
	# 随机换天
	if randf() < 0.45:
		_set_random_weather()
	# 周制回看
	if day > 1 and fmod(float(day - 1), disaster_interval) < 0.001:
		weekly_review()

func _set_random_weather() -> void:
	var r := randf()
	if r < 0.45:
		weather = "clear"
		weather_left = 0.0
	elif r < 0.8:
		weather = "snow"
		weather_left = randf_range(180.0, 600.0)
		notify("又下雪了。雪片斜着打过来。", "info")
	else:
		weather = "blizzard"
		weather_left = randf_range(120.0, 360.0)
		notify("风吼起来了——暴风雪要来了。尽量在屋里躲着。", "bad")

func is_night() -> bool:
	return hour < 6.0 or hour >= 19.0

func time_text() -> String:
	var h := int(hour)
	var m := int((hour - float(h)) * 60.0)
	return "第%d天 %02d:%02d" % [day, h, m]

func weekly_review() -> void:
	var food := count_item("canned") + count_item("cooked_meat") + count_item("frozen_meat")
	var water := count_item("bottle_water") + count_item("clean_water")
	var wood := count_item("wood")
	var text := "【一周回看】第 %d 天\n庇护所：%s（%d 级）\n同伴：%d 人\n存水：%d 份 · 存粮：%d 份 · 木柴：%d 根\n线索：%d / 12" % [
		day, home_type if has_home else "尚无", shelter_level, companions.size(),
		water, food, wood, clues.size()]
	notify(text, "review")

# ---------- 天灾调度 ----------

func tick_disasters(minutes: float) -> void:
	# T2 叙事层（1/游戏日）：非齐次泊松过程
	if disaster_state == "idle":
		var n24: int = _disasters_in_last_24h()
		# 最小间隔 T_min = 2.0 + 0.5 × 过去24h灾难次数（游戏小时）——喘息窗口
		var min_gap_h: float = DV.DISASTER_MIN_GAP_BASE + 0.5 * float(n24)
		var now_d := float(day) + hour / 24.0
		var elapsed_h: float = (now_d - last_disaster_at) * 24.0
		if elapsed_h < min_gap_h:
			return
		# 泊松：本帧游戏分钟内至少一次的概率
		var p: float = 1.0 - exp(-disaster_lambda * (minutes / 1440.0))
		if randf() < p:
			_start_disaster_warning()
	elif disaster_state == "warning":
		disaster_timer -= minutes
		if disaster_timer <= 0.0:
			_strike_disaster()
	elif disaster_state == "active":
		disaster_timer -= minutes
		if disaster_timer <= 0.0:
			_end_disaster()

## 过去 24 游戏小时内的灾难次数
func _disasters_in_last_24h() -> int:
	var now_d := float(day) + hour / 24.0
	var n := 0
	for t in disaster_history:
		if now_d - float(t) <= 1.0:
			n += 1
	return n

func _start_disaster_warning() -> void:
	disaster_state = "warning"
	disaster_type = _pick_disaster()
	var d: Dictionary = DV.DISASTERS.get(disaster_type, {})
	# 前兆窗口（游戏分钟）：每种灾难独立，见 DV.DISASTERS.omen_min
	disaster_timer = float(d.get("omen_min", 30.0))
	disaster_count += 1
	push_shake(0.3)
	var hint := String(d.get("chain", "空气里有种不对劲的静。"))
	notify("【天灾征兆】" + hint + "\n把家弄得更结实，把水、柴和吃的备足。", "bad")

func _pick_disaster() -> String:
	var now_d := float(day) + hour / 24.0
	var n24: int = _disasters_in_last_24h()
	# R-04 复合灾难强制窗口：24h 内已 2 次 → 第 3 次强制复合
	if n24 >= 2:
		return _pick_compound()
	# 权重抽样（microbe 需 60 天后才可能出现；避免与上次重复）
	var weights := {
		"blizzard": 25.0, "meteor": 20.0, "dust": 15.0,
		"thaw": 15.0, "quake": 15.0, "microbe": 10.0 if now_d > 60.0 else 0.0,
	}
	var total := 0.0
	for w in weights.values():
		total += w
	var r := randf() * total
	for kind in weights:
		var w: float = weights[kind]
		if w <= 0.0:
			continue
		r -= w
		if r <= 0.0:
			return kind
	return "blizzard"

## 复合灾难：两种灾难叠加（4 种组合）
func _pick_compound() -> String:
	var keys := DV.COMPOUND_DISASTERS.keys()
	return keys[randi() % keys.size()]

func _strike_disaster() -> void:
	disaster_state = "active"
	push_shake(0.6)
	# 强度演进：Base×(1+0.1×day/15)×StressMultiplier
	var tier: int = int(float(day) / 15.0)
	var stress: float = DV.STRESS_MULT[mini(_disasters_in_last_24h(), 2)]
	disaster_intensity = (1.0 + DV.INTENSITY_PER_15D * float(tier)) * stress
	# 持续时长（游戏分钟）
	var d: Dictionary = DV.DISASTERS.get(disaster_type, {})
	var comp: Dictionary = DV.COMPOUND_DISASTERS.get(disaster_type, {})
	var dur_h: float = float(d.get("duration_h", 24.0))
	if not comp.is_empty():
		dur_h *= 1.5     # 复合灾难持续更久
	disaster_timer = dur_h * 60.0
	# 记录历史（算 24h 窗口与最小间隔）
	disaster_history.append(float(day) + hour / 24.0)
	if disaster_history.size() > 12:
		disaster_history.pop_front()
	last_disaster_at = float(day) + hour / 24.0
	# 世界侧效果
	if is_instance_valid(world) and world.has_method("trigger_disaster"):
		world.trigger_disaster(disaster_type)
	# D 系 AI 权重偏移（灾难是权重的极端压力测试）
	_apply_disaster_ai_shift()
	# 日记条目（灾难记录结构化模板）
	var dname := String(d.get("name", disaster_type))
	if comp.is_empty():
		comp = d
	var dname2 := String(comp.get("name", dname))
	notify("【%s】强度 ×%.2f。\n%s" % [dname2, disaster_intensity,
		String(d.get("chain", ""))], "bad")

## 灾难期间 AI 权重偏移（DV.DISASTER_AI_SHIFT，按分钟 rate 施加）
func _apply_disaster_ai_shift() -> void:
	var shift: Dictionary = DV.DISASTER_AI_SHIFT.get(disaster_type, {})
	if shift.is_empty():
		return
	for npc in companions:
		if not is_instance_valid(npc) or not (npc is SurvivorNPC):
			continue
		var snpc := npc as SurvivorNPC
		if not snpc.has_method("apply_weight_shift"):
			continue
		# 偏移速率/min × 前兆分钟数 = 灾难降临时的权重跳变
		var rate: float = float(shift.get("rate", 0.0))
		var omen_min: float = float(DV.DISASTERS.get(disaster_type, {}).get("omen_min", 30.0))
		snpc.apply_weight_shift(shift, rate * omen_min)

func _end_disaster() -> void:
	disaster_state = "idle"
	var finished := disaster_type
	disaster_type = ""
	disaster_cold = 0.0
	# 热遗产：灾难过后的世界状态绝不重置
	match finished:
		"meteor":
			# 反照率 -0.3：72h 后全局温度 -2℃
			camp_temp -= 2.0
		"blizzard":
			camp_temp -= 1.0
			if weather == "blizzard":
				weather = "clear"
				weather_left = 0.0
		"dust":
			camp_temp -= 1.0
	# 下一次：泊松过程自然到达（无固定间隔）
	notify("天灾过去了。你活着看到了这一次的天亮。", "good")

# ---------- 物品便捷接口 ----------

func add_item(id: String, n: int = 1) -> int:
	var left := inventory.add(id, n)
	if left < n:
		inventory_changed.emit()
		if left > 0:
			notify("背包满了，%s ×%d 掉了。" % [Items.name_of(id), left], "bad")
	# 线索纸页：拿到即入日志
	if id.begins_with("clue_"):
		add_clue(id)
	# 图纸类知识：拿到即会
	if Items.is_blueprint(id):
		var rid := Items.blueprint_recipe(id)
		if rid != "" and not known_recipes.has(rid):
			known_recipes[rid] = true
			notify("你学会了：%s。" % Recipes.name_of(rid), "good")
	return left

func remove_item(id: String, n: int = 1) -> bool:
	var ok := inventory.remove(id, n)
	if ok:
		inventory_changed.emit()
	return ok

func count_item(id: String) -> int:
	return inventory.count(id)

func has_item(id: String, n: int = 1) -> bool:
	return inventory.has(id, n)

func learn_recipe(rid: String) -> void:
	if not known_recipes.has(rid):
		known_recipes[rid] = true
		notify("你学会了：%s。" % Recipes.name_of(rid), "good")

func knows_recipe(rid: String) -> bool:
	return known_recipes.has(rid)

## 统一合成执行器：制作面板与徒手合成（背包里两件一碰）共用。
## 返回 {"ok": bool, "why": String, "out": String, "build": String, "heat": float}
func craft_recipe(rid: String) -> Dictionary:
	var r := Recipes.def(rid)
	if r.is_empty():
		return {"ok": false, "why": "没有这个做法。"}
	if not knows_recipe(rid):
		return {"ok": false, "why": "还不会这个。"}
	for id in r.get("inputs", {}):
		if count_item(String(id)) < int(r.inputs[id]):
			return {"ok": false, "why": "材料不够。"}
	if not Recipes.station_ok(rid):
		return {"ok": false, "why": "得挨着火源才能做这个。"}
	# 背包容量预检：别扣了料、产物却没处放（静默蒸发）
	var out_pre := Recipes.output_item(rid)
	if not Recipes.is_build(rid):
		var has_room := false
		for s in inventory.slots:
			if s.id == out_pre and s.count < Inventory.STACK_MAX:
				has_room = true
				break
		if not has_room and inventory.used() >= inventory.capacity():
			return {"ok": false, "why": "背包满了，先腾个地方。"}
	for id in r.get("inputs", {}):
		remove_item(String(id), int(r.inputs[id]))
	if Recipes.is_build(rid):
		if is_instance_valid(sound) and sound.has_method("play_craft"):
			sound.play_craft()
		return {"ok": true, "build": Recipes.build_key(rid)}
	var out := Recipes.output_item(rid)
	add_item(out, 1)
	# 相变热量真实结算（DV.TRANSFORMS）：吸热降温、放热升温
	var dh: float = recipe_heat_delta(rid)
	if dh != 0.0:
		camp_temp += dh
	if is_instance_valid(sound) and sound.has_method("play_craft"):
		sound.play_craft()
	return {"ok": true, "out": out, "heat": dh}

func add_clue(id: String) -> void:
	if clues.has(id):
		return
	clues[id] = true
	clue_added.emit(id)
	var entry := StoryLogs.entry(id)
	notify("【线索】" + entry.title + "\n" + entry.text, "clue")

func set_flag(k: String, v: bool = true) -> void:
	flags[k] = v

func get_flag(k: String) -> bool:
	return flags.get(k, false)

func notify(text: String, kind: String = "info") -> void:
	ui_events.append({"type": "notify", "text": text, "kind": kind})
	notified.emit(text, kind)

## 交互提示：由 player 在准星目标变化时入队
func push_prompt(text: String) -> void:
	ui_events.append({"type": "prompt", "text": text})

## 屏幕震动：由天灾系统入队
func push_shake(amount: float) -> void:
	ui_events.append({"type": "shake", "amount": amount})

func inventory_capacity() -> int:
	return DV.INV_BASE_SLOTS + DV.INV_BACKPACK_SLOTS * count_item("backpack")

## 背包是否满载（负重速度判据：满载 3.1 m/s）
func inventory_full() -> bool:
	if inventory == null:
		return false
	return inventory.used() >= inventory_capacity()

func tool_cycle() -> void:
	var tools := ["knife", "scissors", "spear", "lighter", "flashlight", "multitool", "wrench"]
	var owned: Array = []
	for t in tools:
		if count_item(t) > 0:
			owned.append(t)
	if owned.is_empty():
		active_tool = ""
		notify("你手里还没有趁手的工具。", "info")
		return
	var i := owned.find(active_tool)
	active_tool = owned[(i + 1) % owned.size()]
	notify("手持：%s" % Items.name_of(active_tool), "info")

func has_fire_source() -> bool:
	return count_item("lighter") > 0 or count_item("matches") > 0

## 审视（V）结算：扫描附近"evidence"分组的实体，触发其 on_survey()；没有则提示
func survey_reveal(pos: Vector3) -> void:
	var best = null
	var best_d := 10.0
	for n in get_tree().get_nodes_in_group("evidence"):
		if not (n is Node3D):
			continue
		var d: float = pos.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n
	if best != null and best.has_method("on_survey"):
		best.on_survey()
	else:
		notify("四周静悄悄的，没什么可记的。", "info")

# ---------- 配方相变热量（DV.TRANSFORMS 落地） ----------
## 配方相变对营地核心温度的真实影响：ΔT = -Q / C_total
## 吸热 Q>0（如化冰）→ 营地降温；放热 Q<0（如干馏）→ 营地升温。
func recipe_heat_delta(rid: String) -> float:
	var q: float = Recipes.transform_heat(rid)   # J
	if q == 0.0:
		return 0.0
	return -q / maxf(1000.0, c_total)

# ---------- 同伴 AI 逐帧结算（D系AI冲突引擎） ----------
## 驱动七权重自然衰减，并做两两冲突升级；冲突抵达最高档则离队。
func tick_companions(minutes: float) -> void:
	if companions.is_empty():
		return
	for c in companions:
		if c is SurvivorNPC and c.has_method("tick_ai"):
			c.tick_ai(minutes)
	# 两两冲突检测（仅在 ≥2 名同伴时）
	for i in range(companions.size()):
		for j in range(i + 1, companions.size()):
			var a = companions[i]
			var b = companions[j]
			if not (a is SurvivorNPC and b is SurvivorNPC):
				continue
			var cf: Dictionary = a.conflict_with(b)
			if cf.get("stage", 0) >= 3:
				var who: String = a.npc_name()
				_kick_companion(a)
				notify("%s 与%s争执到了尽头——她转身走进了风雪里。" % [who, b.npc_name()], "bad")
				return

func _kick_companion(npc) -> void:
	companions.erase(npc)
	if npc is SurvivorNPC:
		npc.state = "free"
		if npc.has_method("_set_state"):
			npc._set_state("free")

# ---------- 技能系统 ----------

## 玩家等级 = 章节进度（每 15 游戏日 1 级）
func player_level() -> int:
	return int((day - 1) / float(DV.CHAPTER_DAYS)) + 1

## 汇总某类 mods 的总加成（技能效果接口）
func skill_mod(key: String) -> float:
	var total := 0.0
	for id in skill_levels:
		var lv: int = int(skill_levels[id])
		if lv <= 0:
			continue
		var d := Skills.def(String(id))
		var mods: Dictionary = d.get("mods", {})
		if mods.has(key):
			total += float(mods[key]) * float(lv)
	return total

func skill_unlocked(unlock_id: String) -> bool:
	for id in skill_levels:
		var d := Skills.def(String(id))
		if int(skill_levels[id]) > 0 and String(d.get("mods", {}).get("unlock", "")) == unlock_id:
			return true
	return false

func can_learn_skill(id: String) -> Dictionary:
	var d := Skills.def(id)
	if d.is_empty():
		return {"ok": false, "why": "没有这个技能"}
	var cur: int = int(skill_levels.get(id, 0))
	if cur >= 5:
		return {"ok": false, "why": "已臻化境"}
	var lv_req: int = int(d.get("lv", 1))
	if player_level() < lv_req:
		return {"ok": false, "why": "需要第 %d 级的阅历（现在第 %d 级）" % [lv_req, player_level()]}
	var prev := String(d.get("prev", ""))
	if prev != "" and int(skill_levels.get(prev, 0)) < 1:
		return {"ok": false, "why": "前置未点亮：%s" % Skills.name_of(prev)}
	var cost := Skills.upgrade_cost(cur + 1)
	if skill_points < cost:
		return {"ok": false, "why": "技能点不足（需 %d）" % cost}
	return {"ok": true, "cost": cost, "heat": float(d.get("cost", [0, 0, 0])[1])}

func learn_skill(id: String) -> bool:
	var chk := can_learn_skill(id)
	if not chk.get("ok", false):
		notify(String(chk.get("why", "学不了。")), "info")
		return false
	var cur: int = int(skill_levels.get(id, 0))
	skill_levels[id] = cur + 1
	skill_points -= int(chk.get("cost", 0))
	skill_last_used[id] = float(day)
	# 学习即热汇：热量赤字时强行上课会让营地更冷（DV.T_LEARN_SKILL 作为热量代价系数）
	camp_temp -= DV.T_LEARN_SKILL * 0.06
	notify("你学会了「%s」（%d/5）。" % [Skills.name_of(id), cur + 1], "good")
	return true

## 用进废退：超过 7 游戏日未使用的技能开始衰减（调用方每游戏日触发）
func degrade_skills() -> void:
	for id in skill_levels:
		var lv: int = int(skill_levels[id])
		if lv <= 0:
			continue
		var last: float = float(skill_last_used.get(id, float(day)))
		if float(day) - last > float(DV.SKILL_DEGRADE_DAYS):
			var keep: float = DV.SKILL_DEGRADE_UNUSED
			if lv >= 5:
				keep = DV.SKILL_DEGRADE_MASTERED
			if randf() > keep:
				skill_levels[id] = lv - 1
				notify("「%s」荒疏了，退回到 %d 级。" % [Skills.name_of(String(id)), lv - 1], "bad")

func mark_skill_used(id: String) -> void:
	if int(skill_levels.get(id, 0)) > 0:
		skill_last_used[id] = float(day)

# ---------- 建筑升级 / 耐久 / 维修 ----------
## 升级到下一等级（DV.BUILD_UPGRADE 成本倍率 / 热阻 / 耐久 / 恒温 / 免灾）
func upgrade_building(idx: int) -> Dictionary:
	if idx < 0 or idx >= buildings.size():
		return {"ok": false, "why": "没有这栋建筑"}
	var b: Dictionary = buildings[idx]
	var lv: int = int(b.get("level", 1))
	if lv >= 5:
		return {"ok": false, "why": "已是最高级（5 级）"}
	var up: Dictionary = DV.BUILD_UPGRADE.get(lv + 1, {})
	if up.is_empty():
		return {"ok": false, "why": "无法继续升级"}
	var base: Dictionary = DV.BUILDINGS.get(String(b.get("type", "")), {})
	for rid in ["wood", "stone", "metal", "fuel"]:
		var need: int = int(ceil(float(base.get(rid, 0)) * float(up.get("cost_mult", 1.0))))
		if need > 0 and count_item(rid) < need:
			return {"ok": false, "why": "材料不足：%s×%d" % [Items.name_of(rid), need]}
	for rid in ["wood", "stone", "metal", "fuel"]:
		var need: int = int(ceil(float(base.get(rid, 0)) * float(up.get("cost_mult", 1.0))))
		if need > 0:
			remove_item(rid, need)
	b["level"] = lv + 1
	b["hp"] = minf(100.0, float(b.get("hp", 100.0)) + float(up.get("hp", 0.0)) * 100.0)
	if bool(up.get("auto_thermostat", false)):
		b["auto_thermostat"] = true
	if bool(up.get("immune_disaster", false)):
		b["immune_disaster"] = true
	notify("升级完成：%s → %d 级。" % [BuildingDefs.name_of(String(b.get("type", ""))), lv + 1], "good")
	return {"ok": true}

## 维修：按 DV.BUILD_REPAIR_COST 消耗材料，恢复指定耐久点
func repair_building(idx: int, points: float) -> Dictionary:
	if idx < 0 or idx >= buildings.size():
		return {"ok": false, "why": "没有这栋建筑"}
	var b: Dictionary = buildings[idx]
	var cur: float = float(b.get("hp", 100.0))
	if cur >= 100.0:
		return {"ok": false, "why": "完好无损，无需维修"}
	var need: float = minf(points, 100.0 - cur)
	var rc: Dictionary = DV.BUILD_REPAIR_COST
	for rid in ["wood", "metal"]:
		var n: int = int(ceil(need * float(rc.get(rid, 0.0))))
		if n > 0 and count_item(rid) < n:
			return {"ok": false, "why": "维修料不足：%s×%d" % [Items.name_of(rid), n]}
	for rid in ["wood", "metal"]:
		var n: int = int(ceil(need * float(rc.get(rid, 0.0))))
		if n > 0:
			remove_item(rid, n)
	b["hp"] = cur + need
	notify("%s 修好了（耐久 %.0f%%）。" % [BuildingDefs.name_of(String(b.get("type", ""))), b["hp"]], "good")
	return {"ok": true}

## 耐久结算（游戏分钟驱动）：基础损耗 + 暴风雪加成；归零标记濒危
func tick_buildings(minutes: float) -> void:
	if buildings.is_empty():
		return
	var decay := DV.BUILD_HP_TICK * (minutes / 60.0)
	if weather == "blizzard":
		decay *= DV.BUILD_HP_BLIZZARD
	for b in buildings:
		if bool(b.get("immune_disaster", false)):
			continue
		var hp: float = maxf(0.0, float(b.get("hp", 100.0)) - decay)
		b["hp"] = hp
		if hp <= DV.BUILD_CRITICAL_HP * 100.0 and not b.get("crit_warned", false):
			b["crit_warned"] = true
			notify("%s 快撑不住了（耐久 %.0f%%）——该维修了。" % [
				BuildingDefs.name_of(String(b.get("type", ""))), hp], "bad")

# ---------- 存档 ----------

func save_game() -> bool:
	if player == null:
		return false
	var data := {
		"day": day, "hour": hour, "weather": weather, "weather_left": weather_left,
		"wind": wind, "world_seed": world_seed,
		"body_temp": body_temp, "hunger": hunger, "thirst": thirst,
		"fatigue": fatigue, "health": health, "wet": wet,
		"core_temp": core_temp, "camp_temp": camp_temp, "heat_surplus": heat_surplus,
		"c_total": c_total, "season": season, "disaster_lambda": disaster_lambda,
		"diseases": diseases, "drug_resist": drug_resist, "drug_resist_day": drug_resist_day,
		"inventory": inventory.to_dict(),
		"active_tool": active_tool, "known_recipes": known_recipes,
		"attributes": attributes, "skill_levels": skill_levels,
		"skill_points": skill_points, "skill_last_used": skill_last_used,
		"has_home": has_home, "home_type": home_type,
		"home_center": [home_center.x, home_center.y, home_center.z],
		"buildings": _buildings_save(),
		"blueprints": blueprints,
		"companions": _companions_save(),
		"clues": clues, "flags": flags,
		"evidence": evidence,
		"player_name": player_name, "profession": profession,
		"next_disaster_day": next_disaster_day,
		"disaster_state": disaster_state, "disaster_type": disaster_type,
		"disaster_count": disaster_count, "game_minutes": game_minutes,
		"disaster_intensity": disaster_intensity,
		"disaster_history": disaster_history, "last_disaster_at": last_disaster_at,
		"player_pos": [player.global_position.x, player.global_position.y, player.global_position.z],
		"player_rot": player.rotation.y,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		notify("存档失败。", "bad")
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	notify("已记录下此刻。进度存在了 user:// 目录。", "good")
	return true

func _buildings_save() -> Array:
	var out := []
	for b in buildings:
		var c := b.duplicate()
		c.erase("node")
		out.append(c)
	return out

func _companions_save() -> Array:
	var out := []
	for c in companions:
		if c.has_method("to_save"):
			out.append(c.to_save())
	return out

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		notify("没有找到任何记录。", "bad")
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var data: Dictionary = JSON.parse_string(txt)
	if data == null:
		notify("记录损坏了。", "bad")
		return false
	day = data.get("day", 1)
	hour = data.get("hour", 8.0)
	weather = data.get("weather", "clear")
	weather_left = data.get("weather_left", 0.0)
	wind = data.get("wind", 0.0)
	world_seed = data.get("world_seed", 20261015)
	body_temp = data.get("body_temp", 36.8)
	core_temp = data.get("core_temp", DV.CORE_TEMP_NORMAL)
	camp_temp = data.get("camp_temp", -20.0)
	heat_surplus = data.get("heat_surplus", "tight")
	c_total = data.get("c_total", 50000.0)
	season = data.get("season", "winter")
	disaster_lambda = data.get("disaster_lambda", 0.15)
	diseases.clear()
	for d in data.get("diseases", []):
		if d is Dictionary:
			diseases.append(d)
	drug_resist = data.get("drug_resist", {})
	drug_resist_day = data.get("drug_resist_day", {})
	perceived_temp = body_temp
	hunger = data.get("hunger", 8.0)
	thirst = data.get("thirst", 8.0)
	fatigue = data.get("fatigue", 8.0)
	health = data.get("health", 100.0)
	wet = data.get("wet", 0.0)
	inventory = Inventory.new()
	inventory.from_dict(data.get("inventory", {}))
	active_tool = data.get("active_tool", "")
	known_recipes = data.get("known_recipes", {})
	attributes = data.get("attributes", attributes)
	skill_levels = data.get("skill_levels", {})
	skill_points = data.get("skill_points", 2)
	skill_last_used = data.get("skill_last_used", {})
	has_home = data.get("has_home", false)
	home_type = data.get("home_type", "")
	var hc: Array = data.get("home_center", [0, 0, 0])
	home_center = Vector3(hc[0], hc[1], hc[2])
	buildings.assign(data.get("buildings", []))
	blueprints.clear()
	for bp in data.get("blueprints", []):
		if bp is Dictionary:
			blueprints.append(bp)
	clues = data.get("clues", {})
	flags = data.get("flags", {})
	evidence.clear()
	for e in data.get("evidence", []):
		if e is Dictionary:
			evidence.append(e)
	player_name = data.get("player_name", "")
	profession = data.get("profession", "")
	next_disaster_day = data.get("next_disaster_day", 7.0)
	disaster_state = data.get("disaster_state", "idle")
	disaster_type = data.get("disaster_type", "")
	disaster_count = data.get("disaster_count", 0)
	disaster_intensity = data.get("disaster_intensity", 1.0)
	disaster_history.clear()
	for t in data.get("disaster_history", []):
		disaster_history.append(float(t))
	last_disaster_at = data.get("last_disaster_at", -99.0)
	game_minutes = data.get("game_minutes", 0.0)
	companions.clear()
	ui_events.clear()
	started = true
	game_over = false
	var pp: Array = data.get("player_pos", [0, 0, 26])
	load_pos = Vector3(pp[0], pp[1], pp[2])
	load_rot = float(data.get("player_rot", 0.0))
	loaded_companions = data.get("companions", [])
	notify("你醒过来，接上了昨天的自己。", "info")
	return true
