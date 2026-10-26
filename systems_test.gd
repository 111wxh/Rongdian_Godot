extends Node
## 数值系统专项测试：验证 16 份设计文档整合后的核心系统可运行且不崩溃
## 覆盖：热引擎 tick / 灾难泊松 λ（季节表）/ 技能学习 / 建筑成本 / 证据吻合度 / 三结局分支
## 诊断写到文件（headless 的 stdout 在 await 边界会被截断），路径见 LOG_PATH。

const LOG_PATH := "user://systems_log.txt"
var _log_lines: Array = []
var _done := false
var fails: Array = []

func _L(s: String) -> void:
	_log_lines.append(s)
	print(s)

func _dump() -> void:
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log_lines) + "\n")
		f.close()
		print("（诊断日志已写入 ", ProjectSettings.globalize_path(LOG_PATH), "）")
	else:
		# 写不出来时至少说一声，不要像以前那样静默丢弃
		push_warning("诊断日志写入失败：%s（错误 %d）" % [LOG_PATH, FileAccess.get_open_error()])

func _ready() -> void:
	if _done:
		return
	_done = true
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	if Game.hud and Game.hud.intro:
		Game.hud.intro.queue_free()
	Game.started = true
	await get_tree().create_timer(0.5).timeout

	await _test_thermal()
	await _test_disaster_lambda()
	await _test_skills()
	_test_buildings()
	_test_evidence()
	_test_endings()

	_L("")
	if fails.is_empty():
		_L("===== 数值系统测试全部通过 =====")
	else:
		_L("===== 失败项 =====")
		for x in fails:
			_L(" - " + x)
	_dump()
	get_tree().quit(0 if fails.is_empty() else 1)

# ---- 热引擎：无热源时营地核心温度应下降 ----
func _test_thermal() -> void:
	Game.has_home = false
	Game.fire_strength = 0.0
	Game.buildings = []
	Game.day = 1
	Game.weather = "clear"
	Game.wind = 0.0
	Game.camp_temp = 0.0
	await get_tree().create_timer(3.0).timeout
	_L("[热引擎] camp_temp 3s 后=%.3f（heat_surplus=%s）" % [Game.camp_temp, Game.heat_surplus])
	if Game.camp_temp > -0.01:
		fails.append("热引擎未结算（camp_temp 未下降）")
	if not (Game.heat_surplus in ["rich", "tight", "deficit"]):
		fails.append("heat_surplus 取值异常：%s" % Game.heat_surplus)

# ---- 灾难泊松 λ：随章节（季节）查表上升 ----
func _test_disaster_lambda() -> void:
	Game.day = 1      # 冬
	await get_tree().create_timer(0.6).timeout
	var w: float = Game.disaster_lambda
	Game.day = 170    # 晚春
	await get_tree().create_timer(0.6).timeout
	var sp: float = Game.disaster_lambda
	_L("[灾难λ] 冬=%.2f 晚春=%.2f" % [w, sp])
	if not (sp > w):
		fails.append("灾难 λ 未按季节上升（冬 %.2f 晚春 %.2f）" % [w, sp])
	if not _approx(w, 0.15) or not _approx(sp, 0.60):
		fails.append("灾难 λ 与文档基准不符（冬应0.15 晚春应0.60）")

# ---- 技能学习：扣点 / 升级 ----
func _test_skills() -> void:
	Game.skill_points = 99
	var before: int = int(Game.skill_levels.get("cold_adapt", 0))
	var ok: bool = Game.learn_skill("cold_adapt")
	await get_tree().process_frame
	var after: int = int(Game.skill_levels.get("cold_adapt", 0))
	_L("[技能] cold_adapt: %d -> %d (ok=%s 点数=%d 总技能数=%d)" % [
		before, after, ok, Game.skill_points, Skills.total_count()])
	if not ok or after != before + 1:
		fails.append("技能学习失败（cold_adapt %d -> %d）" % [before, after])
	if Skills.total_count() < 70:
		fails.append("技能表条目不足（%d < 70）" % Skills.total_count())

# ---- 建筑成本：从 DV.BUILDINGS 读取且数值合理 ----
func _test_buildings() -> void:
	var n: int = DV.BUILDINGS.size()
	var fire: Dictionary = DV.BUILDINGS.get("campfire", {})
	_L("[建筑] 共 %d 种；营火 wood=%s time=%.1fs" % [n, fire.get("wood", 0), float(fire.get("time", 0))])
	if n < 15:
		fails.append("建筑表条目不足（%d < 15）" % n)
	if int(fire.get("wood", -1)) <= 0:
		fails.append("营火木耗未配置")

# ---- 证据吻合度：发现 E01~E03 后三假说给出 0~1 分值 ----
func _test_evidence() -> void:
	Evidence.discover("E01", -30.0, 0.3)
	Evidence.discover("E02", -30.0, 0.3)
	Evidence.discover("E03", -30.0, 0.3)
	var coh: Dictionary = Evidence.all_coherence()
	_L("[证据] 已发现=%d 吻合度 H1=%.2f H2=%.2f H3=%.2f" % [
		Evidence.held_count(), coh.get("h1", -1), coh.get("h2", -1), coh.get("h3", -1)])
	if Evidence.held_count() < 3:
		fails.append("证据发现未记录（held=%d）" % Evidence.held_count())
	for h in ["h1", "h2", "h3"]:
		var v: float = float(coh.get(h, -1))
		if v < 0.0 or v > 1.0:
			fails.append("吻合度越界 %s=%.2f" % [h, v])

# ---- 三结局分支：全证据后 evaluate 返回非空且 unlock 逻辑合理 ----
func _test_endings() -> void:
	for e in DV.EVIDENCES.keys():
		Evidence.discover(e, -30.0, 0.3)
	var unlock: bool = Evidence.ending_unlocked()
	_L("[结局] 全证据后 ending_unlocked=%s" % unlock)
	var id: String = Endings.evaluate()
	_L("[结局] evaluate()=%s" % id)
	if id == "":
		fails.append("结局评估返回空")

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001
