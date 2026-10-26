extends Node
class_name Survival
## 生存模拟：体温 / 饥渴 / 疲劳 / 生命。轻量体感温度链（v3.0 口径）
## 规则：环境越冷、天黑、起风、身体越湿 → 掉得快；靠近火源、进入封闭处、保持干燥、加衣物 → 缓得过来。

@onready var player: Player = get_parent() as Player

var _warn_low_temp := false
var _warn_mid_temp := false
var _warn_hunger := false
var _warn_thirst := false
var _warn_fatigue := false
var _warn_heat := false
var _last_day_notified := 0

const FIRE_DEFS := {
	"campfire": {"radius": 7.0, "power": 8.0},
	"stone_fire": {"radius": 9.0, "power": 11.0},
}

func _physics_process(delta: float) -> void:
	var g_sp: Node = get_node_or_null("/root/Game")
	if g_sp == null or player == null:
		return
	if bool(g_sp.get("game_over")) or bool(g_sp.get("sleeping")):
		return
	var minutes := delta * float(g_sp.get("MINUTES_PER_SECOND"))
	g_sp.call("advance_time", minutes)
	g_sp.call("tick_disasters", minutes)
	g_sp.call("tick_buildings", minutes)
	g_sp.call("tick_companions", minutes)
	_update_fire_and_shelter()
	_update_wet(minutes)
	_update_body_temp(minutes)
	_update_metabolism(minutes)
	_update_health(minutes)
	_update_perceived(delta)
	_check_warnings()

# ---------- 火源与庇护 ----------

func _update_fire_and_shelter() -> void:
	var g_fs: Node = get_node_or_null("/root/Game")
	if g_fs == null:
		return
	var best := 0.0
	var p := player.global_position
	var buildings: Array = g_fs.get("buildings")
	var home_center: Vector3 = g_fs.get("home_center")
	var has_home: bool = bool(g_fs.get("has_home"))
	for b in buildings:
		var kind := String(b.get("type", ""))
		if FIRE_DEFS.has(kind):
			var d := p.distance_to(Vector3(b.get("pos", [0, 0, 0])[0], b.get("pos", [0, 0, 0])[1], b.get("pos", [0, 0, 0])[2]))
			var r: float = FIRE_DEFS[kind].radius
			if d < r:
				best = maxf(best, (1.0 - d / r) * FIRE_DEFS[kind].power / 8.0)
	if float(g_fs.get("home_fire_bonus")) > 0.0 and has_home and p.distance_to(home_center) < 35.0:
		best = maxf(best, 1.0)
	g_fs.set("fire_strength", clampf(best, 0.0, 1.0))
	# 是否在"有顶"的庇护所内：家范围内且有屋顶建筑
	var has_roof := false
	if has_home and p.distance_to(home_center) < 18.0:
		for b in buildings:
			if String(b.get("type", "")) == "wood_roof":
				var d2 := p.distance_to(Vector3(b.get("pos", [0, 0, 0])[0], b.get("pos", [0, 0, 0])[1], b.get("pos", [0, 0, 0])[2]))
				if d2 < 6.0:
					has_roof = true
					break
	g_fs.set("indoors", has_roof)

# ---------- 体感温度链 ----------

func _update_wet(minutes: float) -> void:
	var g_wt: Node = get_node_or_null("/root/Game")
	if g_wt == null:
		return
	var weather: String = String(g_wt.get("weather"))
	var indoors: bool = bool(g_wt.get("indoors"))
	var fire_strength: float = float(g_wt.get("fire_strength"))
	if indoors:
		g_wt.set("wet", maxf(0.0, float(g_wt.get("wet")) - 2.0 * minutes))
	elif weather == "blizzard":
		g_wt.set("wet", minf(100.0, float(g_wt.get("wet")) + 0.9 * minutes))
	elif weather == "snow":
		g_wt.set("wet", minf(100.0, float(g_wt.get("wet")) + 0.3 * minutes))
	elif fire_strength > 0.3:
		g_wt.set("wet", maxf(0.0, float(g_wt.get("wet")) - 1.5 * minutes))
	else:
		g_wt.set("wet", maxf(0.0, float(g_wt.get("wet")) - 0.2 * minutes))

func _warmth_total() -> float:
	var g_wm: Node = get_node_or_null("/root/Game")
	if g_wm == null:
		return 0.0
	var w := 0.0
	# 衣物（穿着即生效）
	w += Items.insul_of("fur_coat") * float(int(g_wm.call("count_item", "fur_coat")) > 0)
	w += Items.insul_of("cloth_coat") * float(int(g_wm.call("count_item", "cloth_coat")) > 0)
	# 衣物/建筑保暖技能（皮毛加工 insul / 保温建筑学 insul）
	w += float(g_wm.call("skill_mod", "insul")) * 0.3
	# 耐寒适应：基础耐寒（cold_resist，每级 +5 → 直接折算温暖度）
	w += float(g_wm.call("skill_mod", "cold_resist")) * 0.5
	# 火源
	w += float(g_wm.get("fire_strength")) * 9.0
	# 封闭处
	if bool(g_wm.get("indoors")):
		w += 4.0 + float(g_wm.get("shelter_level"))
	# 同伴在旁（人多，热能也聚一些）
	var nearby := 0
	for c in g_wm.get("companions"):
		if c.has_method("is_near") and c.is_near(player):
			nearby += 1
	w += float(mini(nearby, 3)) * 1.2
	# 终端广域供热
	if float(g_wm.get("home_fire_bonus")) > 0.0 and bool(g_wm.get("has_home")) and player.global_position.distance_to(g_wm.get("home_center")) < 35.0:
		w += 6.0
	return w

func _cold_pressure() -> float:
	var g_cp: Node = get_node_or_null("/root/Game")
	if g_cp == null:
		return 4.0
	var cp := 4.0
	cp += maxf(0.0, -float(g_cp.get("ambient_temp")) - 8.0) * 0.28
	cp += float(g_cp.get("wind")) * 0.6
	cp += float(g_cp.get("wet")) * 0.02
	if bool(g_cp.call("is_night")):
		cp += 1.5
	if String(g_cp.get("disaster_state")) == "active":
		cp += 2.0
	# 暴风雪热损耗减免（篝火大师 blizzard_loss 为负 → 降低冷压）
	if String(g_cp.get("weather")) == "blizzard":
		cp += float(g_cp.call("skill_mod", "blizzard_loss")) * 10.0
	return cp

func _update_body_temp(minutes: float) -> void:
	var g_bt: Node = get_node_or_null("/root/Game")
	if g_bt == null:
		return
	var net := _warmth_total() - _cold_pressure()
	if net >= 0.0:
		# 回暖（火边、封闭处、干衣）比降温慢一截，但方向明确
		g_bt.set("body_temp", float(g_bt.get("body_temp")) + minf(net, 6.0) * DV.BODY_TEMP_WARM_RATE * minutes)
		g_bt.set("body_temp", minf(float(g_bt.get("body_temp")), 37.6))
	else:
		# 失温：轻量体感链，慢而持续（速率见 DV.BODY_TEMP_COOL_RATE，
		# 已按 120s/日尺度调校——原先按"每分钟"直觉定的系数在 12 游戏分钟/秒下
		# 会几秒内掉到濒死，玩家反馈"失温太快"）
		g_bt.set("body_temp", float(g_bt.get("body_temp")) + maxf(net, -14.0) * DV.BODY_TEMP_COOL_RATE * minutes)
	# 烤久了也会过热
	if net > 8.0:
		g_bt.set("body_temp", float(g_bt.get("body_temp")) + (net - 8.0) * DV.BODY_TEMP_OVERHEAT_RATE * minutes)
	g_bt.set("body_temp", clampf(float(g_bt.get("body_temp")), 28.0, 41.0))
	# 失温分档
	var t: float = float(g_bt.get("body_temp"))
	if t < 32.0:
		g_bt.set("hypothermia_tier", 3)
	elif t < 34.0:
		g_bt.set("hypothermia_tier", 2)
	elif t < 35.5:
		g_bt.set("hypothermia_tier", 1)
	else:
		g_bt.set("hypothermia_tier", 0)

func _update_metabolism(minutes: float) -> void:
	var g_mt: Node = get_node_or_null("/root/Game")
	if g_mt == null:
		return
	g_mt.set("hunger", minf(100.0, float(g_mt.get("hunger")) + DV.HUNGER_PER_MIN * minutes))
	g_mt.set("thirst", minf(100.0, float(g_mt.get("thirst")) + DV.THIRST_PER_MIN * minutes))
	var f_rate := 0.010
	if String(g_mt.get("weather")) != "clear":
		f_rate += 0.004
	# 冲刺额外耗体力（DV.SPRINT_FATIGUE_PER_MIN）：跑得越快，歇得越久
	if is_instance_valid(player) and player.sprinting:
		f_rate += DV.SPRINT_FATIGUE_PER_MIN
	# 体力技能（营养配餐/长途跋涉 stamina 减免疲劳累积）
	f_rate *= maxf(0.5, 1.0 - clampf(float(g_mt.call("skill_mod", "stamina")), 0.0, 0.6))
	g_mt.set("fatigue", minf(100.0, float(g_mt.get("fatigue")) + f_rate * minutes))
	if float(g_mt.get("hunger")) > 85.0 or float(g_mt.get("thirst")) > 85.0:
		# 饥渴交加掉体温（与 DV.BODY_TEMP_COOL_RATE 同尺度：约 0.012℃/现实秒）
		g_mt.set("body_temp", float(g_mt.get("body_temp")) - 0.001 * minutes)

func _update_health(minutes: float) -> void:
	var g_hl: Node = get_node_or_null("/root/Game")
	if g_hl == null:
		return
	var regen := 0.0
	if float(g_hl.get("hunger")) < 55.0 and float(g_hl.get("thirst")) < 55.0 and float(g_hl.get("body_temp")) >= 35.5 and not bool(g_hl.call("get_flag", "wounded")):
		regen = 0.35
		if String(g_hl.get("profession")) == "medic":
			regen += 0.15
	var drain := 0.0
	if float(g_hl.get("hunger")) >= 95.0:
		drain += 0.4
	if float(g_hl.get("thirst")) >= 95.0:
		drain += 0.6
	if float(g_hl.get("body_temp")) < 32.0:
		drain += 2.2
	if float(g_hl.get("body_temp")) > 39.0:
		drain += 0.8
	g_hl.set("health", clampf(float(g_hl.get("health")) + (regen - drain) * minutes, 0.0, 100.0))
	if float(g_hl.get("health")) <= 0.0 and not bool(g_hl.get("game_over")):
		g_hl.set("game_over", true)
		g_hl.call("notify", "眼皮重得抬不起来……", "bad")
		var hud_sv: Node = g_hl.get("hud")
		if is_instance_valid(hud_sv) and hud_sv.has_method("show_game_over"):
			hud_sv.call("show_game_over")

func _update_perceived(delta: float) -> void:
	var g_pc: Node = get_node_or_null("/root/Game")
	if g_pc == null:
		return
	# 迟滞窗：体感滞后于真实体温——抖得厉害时，往往已经更冷了
	g_pc.set("perceived_temp", float(g_pc.get("perceived_temp")) + (float(g_pc.get("body_temp")) - float(g_pc.get("perceived_temp"))) * minf(1.0, delta * 0.12))

func _check_warnings() -> void:
	var g_cw: Node = get_node_or_null("/root/Game")
	if g_cw == null or not bool(g_cw.get("started")):
		return
	var day: int = int(g_cw.get("day"))
	var day_changed := day != _last_day_notified
	_last_day_notified = day
	if day_changed:
		_warn_low_temp = false
		_warn_mid_temp = false
		_warn_hunger = false
		_warn_thirst = false
		_warn_fatigue = false
		_warn_heat = false
	var tier: int = int(g_cw.get("hypothermia_tier"))
	var hunger: float = float(g_cw.get("hunger"))
	var thirst: float = float(g_cw.get("thirst"))
	var fatigue: float = float(g_cw.get("fatigue"))
	var body_temp: float = float(g_cw.get("body_temp"))
	if tier == 1 and not _warn_low_temp:
		_warn_low_temp = true
		g_cw.call("notify", "你在抖。手有点不听使唤——该找热源了。", "bad")
	if tier == 2 and not _warn_mid_temp:
		_warn_mid_temp = true
		g_cw.call("notify", "视线在发沉，动作也钝了。再冷下去会出事。", "bad")
	if hunger > 70.0 and not _warn_hunger:
		_warn_hunger = true
		g_cw.call("notify", "胃在叫。得找点吃的了。", "bad")
	if thirst > 70.0 and not _warn_thirst:
		_warn_thirst = true
		g_cw.call("notify", "喉咙干得发紧。化点雪水喝。", "bad")
	if fatigue > 75.0 and not _warn_fatigue:
		_warn_fatigue = true
		g_cw.call("notify", "乏意一波一波地上来。该躺下了。", "bad")
	# 第一天：只用身体语言，不弹数值
	if day == 1 and hunger > 25.0 and not bool(g_cw.call("get_flag", "day1_hunger")):
		g_cw.call("set_flag", "day1_hunger", true)
		g_cw.call("notify", "肚子叫了一声，腿有点软。——该找点吃的了。", "bad")
	if day == 1 and thirst > 30.0 and not bool(g_cw.call("get_flag", "day1_thirst")):
		g_cw.call("set_flag", "day1_thirst", true)
		g_cw.call("notify", "喉咙干得发紧。——化点雪水喝。", "bad")
	if body_temp > 38.5 and not _warn_heat:
		_warn_heat = true
		g_cw.call("notify", "烤得太久了，头晕。离火远一点。", "bad")

# ---------- 睡眠 ----------

func try_sleep(_bed_pos: Vector3) -> bool:
	var g_sl: Node = get_node_or_null("/root/Game")
	if g_sl == null or bool(g_sl.get("sleeping")):
		return false
	var has_home: bool = bool(g_sl.get("has_home"))
	var home_center: Vector3 = g_sl.get("home_center")
	var quality := 0
	if has_home and player.global_position.distance_to(home_center) < 20.0:
		quality += int(g_sl.get("shelter_level"))
	if float(g_sl.get("fire_strength")) > 0.2:
		quality += 2
	if String(g_sl.get("weather")) == "blizzard":
		quality -= 2
	if int(g_sl.get("hypothermia_tier")) >= 2:
		quality -= 2
	quality = maxi(quality, 0)
	g_sl.set("sleeping", true)
	g_sl.call("notify", "你躺下来，听着风声睡去。", "info")
	# 睡到下一个早晨七点
	var hour: float = float(g_sl.get("hour"))
	var mins := 0.0
	if hour < 7.0:
		mins = (7.0 - hour) * 60.0
	else:
		mins = (24.0 - hour + 7.0) * 60.0
	var total := mins
	var chunk := 15.0
	while total > 0.0 and not bool(g_sl.get("game_over")):
		var step: float = minf(chunk, total)
		total -= step
		g_sl.call("advance_time", step)
		g_sl.call("tick_disasters", step)
		g_sl.set("hunger", minf(100.0, float(g_sl.get("hunger")) + DV.HUNGER_PER_MIN_SLEEP * step))
		g_sl.set("thirst", minf(100.0, float(g_sl.get("thirst")) + DV.THIRST_PER_MIN_SLEEP * step))
		# 睡处太冷会被冻醒
		var unsafe := String(g_sl.get("weather")) == "blizzard" and float(g_sl.get("fire_strength")) <= 0.0 and not bool(g_sl.get("indoors"))
		if unsafe and float(g_sl.get("body_temp")) < 34.5:
			g_sl.call("notify", "半夜冻醒了，火灭了，身子僵得发硬。", "bad")
			g_sl.set("body_temp", float(g_sl.get("body_temp")) - 1.2)
			break
	g_sl.set("fatigue", maxf(0.0, float(g_sl.get("fatigue")) - (45.0 + 18.0 * float(quality))))
	if float(g_sl.get("body_temp")) < 35.0:
		g_sl.set("body_temp", float(g_sl.get("body_temp")) + 0.8)
	g_sl.set("sleeping", false)
	g_sl.call("notify", "你醒过来，第 %d 天的早晨。" % int(g_sl.get("day")), "good")
	return true

func companion_near_count() -> int:
	var g_cnc: Node = get_node_or_null("/root/Game")
	if g_cnc == null:
		return 0
	var n := 0
	for c in g_cnc.get("companions"):
		if c.has_method("is_near") and c.is_near(player):
			n += 1
	return n
