class_name Evidence
extends RefCounted
## E 系证据链（E系证据链详细设计）
## 16 条证据（E01-E16）+ 三假说（H1 自然耦合 / H2 干预失控 / H3 有意封存）
## 三条宪章：无剧本真相 / 证据三态降解（不可逆）/ 只给吻合度不给对错
##
## 玩家持有证据存在 Game.evidence：[{"id", "state", "readability", "found_day"}]
## state: pristine / degraded / unintelligible

## ---------- 查询 ----------

static func all_ids() -> Array:
	var out := DV.EVIDENCES.keys()
	out.sort()
	return out

static func def(id: String) -> Dictionary:
	return DV.EVIDENCES.get(id, {})

static func name_of(id: String) -> String:
	return String(def(id).get("name", id))

static func carrier_of(id: String) -> String:
	return String(def(id).get("carrier", ""))

## ---------- 发现与降解 ----------

## 发现一条证据（按环境参数决定初始降解态）
static func discover(id: String, env_temp_c: float = -30.0, env_humidity: float = 0.3) -> Dictionary:
	var g_ds: Node = _g()
	if def(id).is_empty():
		return {"ok": false, "why": "没有这条证据"}
	for e in _held_list(g_ds):
		if String(e.get("id", "")) == id:
			return {"ok": false, "why": "已经拿到过了"}
	# 降解判定：字面读数中的阈值（高温/高湿加速降解）
	var state := "pristine"
	if env_temp_c > -5.0 or env_humidity > 0.85:
		state = "degraded"
	if env_temp_c > 5.0 and env_humidity > 0.9:
		state = "unintelligible"
	g_ds.get("evidence").append({
		"id": id, "state": state,
		"readability": clampf(float(def(id).get("readability", 0.5)), 0.0, 1.0),
		"found_day": float(g_ds.get("day")),
	})
	# 日记联动：首次发现自动写入日记
	g_ds.call("add_clue", "ev_" + id)
	return {"ok": true, "state": state, "reading": reading_of(id)}

## 证据当前字面读数（按降解状态过滤）
static func reading_of(id: String) -> String:
	var e := held(id)
	var raw := String(def(id).get("reading", ""))
	if e.is_empty():
		return raw
	var st := String(e.get("state", "pristine"))
	match st:
		"degraded":
			# 受损：截断为前半可读 + 模糊标记
			var half := int(raw.length() / 2.0)
			return raw.substr(0, half) + "…[墨迹模糊]"
		"unintelligible":
			return "[乱码]…" + raw.substr(0, mini(8, raw.length())) + "…[乱码]"
	return raw

static func held(id: String) -> Dictionary:
	var g_hd: Node = _g()
	for e in _held_list(g_hd):
		if String(e.get("id", "")) == id:
			return e
	return {}

static func held_count() -> int:
	var g_hc: Node = _g()
	return int(g_hc.get("evidence").size()) if g_hc else 0

## autoload「Game」在编译期不可见（本类被 game.gd 依赖，形成解析环），
## 运行时按 /root/Game 取节点。
static func _g() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("Game") if Engine.get_main_loop() else null

## 持有的证据数组（统一入口，避免各处重复 get）
static func _held_list(g: Node) -> Array:
	return g.get("evidence") if g else []

## ---------- 吻合度公式（E 系 5.1） ----------
## Score(Hi|E) = Σ[W(Ej) × H(Hi|Ej)] × C(E) × D(t)
## W(Ej) = AMBIGUITY_W[歧义强度] × Readability
## C(E)   = 1 / (1 + Σ|H(Hi|Ej) - Mean(H(Hi))|)   （证据集合一致性修正）
## D(t)   = DEGRADE_D[降解状态]

static func coherence(h: String) -> float:
	var g_coh: Node = _g()
	var held_list := _held_list(g_coh)
	if held_list.is_empty():
		return 0.0
	var sum := 0.0
	var max_sum := 0.0
	var affins: Array = []
	for e in held_list:
		var id := String(e.get("id", ""))
		var d := def(id)
		if d.is_empty():
			continue
		var amb: int = int(d.get("ambiguity", 3))
		var w: float = float(DV.AMBIGUITY_W.get(amb, 0.4)) * float(e.get("readability", 0.5))
		var aff: Dictionary = d.get("affinity", {})
		var hv: float = float(aff.get(h, 0.0))
		var dt: float = float(DV.DEGRADE_D.get(String(e.get("state", "pristine")), 0.0))
		sum += w * hv * dt
		max_sum += w * dt
		affins.append(hv)
	if max_sum <= 0.0:
		return 0.0
	# C(E)：证据间倾向一致性
	var mean := 0.0
	for a in affins:
		mean += float(a)
	mean /= float(affins.size())
	var dev := 0.0
	for a in affins:
		dev += absf(float(a) - mean)
	var c_e := 1.0 / (1.0 + dev)
	# 归一化到 0-1（负倾向归零，保留"反对"信息但不产生负分）
	var score: float = (sum / max_sum) * c_e
	return clampf((score + 1.0) * 0.5, 0.0, DV.COHERENCE_MAX)

## 三假说吻合度一览
static func all_coherence() -> Dictionary:
	var out := {}
	for h in ["h1", "h2", "h3"]:
		out[h] = coherence(h)
	return out

## 吻合度描述文本（只给描述，不给对错）
static func coherence_text(score: float) -> String:
	for row in DV.COHERENCE_TEXT:
		if score >= float(row.get("min", 0.0)):
			return String(row.get("text", ""))
	return "证据不足"

## 当前最契合的假说（>=60% 才形成信念）
static func leaning() -> String:
	var best := ""
	var best_v := 0.6
	for h in ["h1", "h2", "h3"]:
		var v: float = coherence(h)
		if v > best_v:
			best = h
			best_v = v
	return best

## 是否解锁终局接管选择（任假说 ≥85%）
static func ending_unlocked() -> bool:
	for h in ["h1", "h2", "h3"]:
		if coherence(h) >= DV.COHERENCE_UNLOCK:
			return true
	return false
