class_name DiseaseSystem
extends Node
## 疾病动力学（疾病动力学与人口系统）
## 纪律：个体状态机（零传染性）/ 前兆窗口干预 / 环境动态耦合
## 四阶段：潜伏期(0) → 前兆期(1) → 发作期(2) → 终末期(3)
## 每阶段属性系数见 DV.DISEASE_STAGE_DEBUFF，传染性见 DV.DISEASE_CONTAGIOUS

var _tick_acc := 0.0
const TICK := 1.0                     ## 1 现实秒 ≈ 2 游戏分钟
const GAME_MIN_PER_TICK := 2.0

func _physics_process(delta: float) -> void:
	if not Game.started or Game.game_over:
		return
	_tick_acc += delta
	while _tick_acc >= TICK:
		_tick_acc -= TICK
		_tick()

func _tick() -> void:
	_check_trigger()
	for d in Game.diseases:
		d["t"] = float(d.get("t", 0.0)) + GAME_MIN_PER_TICK
		var did := String(d.get("id", ""))
		var def: Dictionary = DV.DISEASES.get(did, {})
		var incub_h: float = float(def.get("incubation_h", 6.0))
		# 阶段推进：潜伏期后每 incub/3 游戏分钟升一阶
		var t: float = float(d["t"])
		var stage := int(d.get("stage", 0))
		if stage < 3 and t > incub_h * 60.0 * float(stage + 1) / 3.0:
			stage += 1
			d["stage"] = stage
			if stage == 1:
				Game.notify("【前兆】%s的前兆开始了——现在干预还来得及。" % String(def.get("name", did)), "bad")
			elif stage == 2:
				Game.notify("%s发作了。" % String(def.get("name", did)), "bad")
			elif stage == 3:
				Game.notify("%s到了终末期。24 游戏小时内不处理，人就没了。" % String(def.get("name", did)), "bad")
		# 终末期持续掉血
		if stage >= 3:
			Game.health = maxf(0.0, Game.health - 0.06 * GAME_MIN_PER_TICK)
	# 属性影响：疾病阶段改写移动与交互（由 player/survival 读取）

## 当前疾病对某属性的总影响系数（0-1）
static func stage_factor() -> float:
	var worst := 1.0
	for d in Game.diseases:
		var s: int = clampi(int(d.get("stage", 0)), 0, 3)
		worst = minf(worst, DV.DISEASE_STAGE_DEBUFF[s])
	return worst

func _check_trigger() -> void:
	# ---- 失温链：核心体温低于阈值即触发，随体温降级 ----
	if Game.core_temp < DV.CORE_TEMP_MILD and not _has("hypothermia"):
		_infect("hypothermia")
	if Game.core_temp < DV.CORE_TEMP_SEVERE:
		_escalate("hypothermia", 2)
	if Game.core_temp < DV.CORE_TEMP_LETHAL + 2.0:
		_escalate("hypothermia", 3)
	# ---- 冻伤：极寒暴露 ----
	if Game.perceived_temp < -20.0 and randf() < 0.02 and not _has("frostbite"):
		_infect("frostbite")
	# ---- 伤口感染：低血量 + 潮湿 ----
	if Game.health < 75.0 and Game.wet > 40.0 and randf() < 0.01 and not _has("wound_infection"):
		_infect("wound_infection")
	# ---- 呼吸道感染：密闭空间 + 春夏季高发 ----
	var season_p := 0.0
	match Game.season:
		"early_spring": season_p = 0.004
		"mid_spring": season_p = 0.006
		"late_spring": season_p = 0.003
	if season_p > 0.0 and Game.indoors and randf() < season_p and not _has("respiratory"):
		_infect("respiratory")
	# ---- 坏血病：长期饥饿 ----
	if Game.hunger > 70.0 and randf() < 0.005 and not _has("scurvy"):
		_infect("scurvy")
	# ---- 饥饿性酮症：濒饿 ----
	if Game.hunger > 92.0 and randf() < 0.005 and not _has("ketosis"):
		_infect("ketosis")

func _has(id: String) -> bool:
	for d in Game.diseases:
		if String(d.get("id", "")) == id:
			return true
	return false

func _infect(id: String) -> void:
	Game.diseases.append({"id": id, "stage": 0, "t": 0.0})
	var def: Dictionary = DV.DISEASES.get(id, {})
	Game.notify("【疾病】你染上了%s。%s" % [String(def.get("name", id)),
		String(def.get("env", ""))], "bad")

func _escalate(id: String, stage: int) -> void:
	for d in Game.diseases:
		if String(d.get("id", "")) == id and int(d.get("stage", 0)) < stage:
			d["stage"] = stage
			return

## 治疗：消耗治疗资源，成功则降级一阶/痊愈
func treat(disease_id: String) -> bool:
	for d in Game.diseases:
		if String(d.get("id", "")) != disease_id:
			continue
		var def: Dictionary = DV.DISEASES.get(disease_id, {})
		var need: Array = def.get("treat", [])
		# 资源检查（治疗物品映射）
		for rid in need:
			if not _has_treat_item(String(rid)):
				Game.notify("缺治疗的料：%s。" % _treat_item_name(String(rid)), "info")
				return false
		# 消耗
		for rid in need:
			_consume_treat_item(String(rid))
		var stage: int = int(d.get("stage", 0))
		if stage <= 1:
			Game.diseases.erase(d)
			Game.notify("%s压下去了。" % String(def.get("name", disease_id)), "good")
		else:
			d["stage"] = stage - 1
			Game.notify("%s稳住了一些（降到 %d 阶）。" % [String(def.get("name", disease_id)), stage - 1], "good")
		return true
	return false

## 治疗资源 → 背包物品映射
func _has_treat_item(rid: String) -> bool:
	match rid:
		"fuel": return Game.count_item("wood") > 0 or Game.count_item("fuel") > 0
		"organic": return Game.count_item("canned") > 0 or Game.count_item("cooked_meat") > 0 \
			or Game.count_item("frozen_meat") > 0 or Game.count_item("organic") > 0
		"water": return Game.count_item("clean_water") > 0 or Game.count_item("water") > 0
		"rock": return Game.count_item("stone") > 0
		"metal": return Game.count_item("scrap") > 0 or Game.count_item("metal") > 0
		"salt": return Game.count_item("salt") > 0
	return false

func _treat_item_name(rid: String) -> String:
	match rid:
		"fuel": return "木材或燃料"
		"organic": return "食物"
		"water": return "水"
		"rock": return "石块"
		"metal": return "金属"
		"salt": return "盐"
	return rid

func _consume_treat_item(rid: String) -> void:
	match rid:
		"fuel":
			if Game.count_item("wood") > 0: Game.remove_item("wood", 1)
			else: Game.remove_item("fuel", 1)
		"organic":
			for f in ["canned", "cooked_meat", "frozen_meat", "organic"]:
				if Game.count_item(f) > 0:
					Game.remove_item(f, 1)
					return
		"water":
			if Game.count_item("clean_water") > 0: Game.remove_item("clean_water", 1)
			else: Game.remove_item("water", 1)
		"rock": Game.remove_item("stone", 1)
		"metal":
			if Game.count_item("scrap") > 0: Game.remove_item("scrap", 1)
			else: Game.remove_item("metal", 1)
		"salt": Game.remove_item("salt", 1)

## 耐药性：同一药物连用 3 次耐药 +20%，停用每 7 日 -10%
func drug_resistance(disease_id: String) -> float:
	var r: float = float(Game.drug_resist.get(disease_id, 0.0))
	var last_day: float = float(Game.drug_resist_day.get(disease_id, -99.0))
	var elapsed := float(Game.day) - last_day
	if elapsed > float(DV.DRUG_RESIST_DECAY_DAYS):
		r = maxf(0.0, r - 0.1 * float(int(elapsed / float(DV.DRUG_RESIST_DECAY_DAYS))))
	return r

func note_drug_used(disease_id: String) -> void:
	var r: float = float(Game.drug_resist.get(disease_id, 0.0))
	Game.drug_resist[disease_id] = minf(0.9, r + DV.DRUG_RESIST_ADD)
	Game.drug_resist_day[disease_id] = float(Game.day)

## 当前疾病列表文本（HUD）
static func summary() -> String:
	if Game.diseases.is_empty():
		return ""
	var parts: Array = []
	for d in Game.diseases:
		var def: Dictionary = DV.DISEASES.get(String(d.get("id", "")), {})
		var stage_names := ["潜伏", "前兆", "发作", "终末"]
		var s: int = clampi(int(d.get("stage", 0)), 0, 3)
		parts.append("%s·%s" % [String(def.get("name", "?")), stage_names[s]])
	return "、".join(parts)
