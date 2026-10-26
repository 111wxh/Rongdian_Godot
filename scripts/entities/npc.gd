extends CharacterBody3D
class_name SurvivorNPC
## 幸存者：冰封中解冻的人。搬起到火边→解冻→交谈→达成条件后加入

var sid := ""
var def: Dictionary = {}
var state := "frozen"     # frozen / thawing / free / joined
var thaw := 0.0
var carried := false
var ice: MeshInstance3D
var body_root: Node3D
var follow_t := 0.0
# ---------- D 系 AI 七权重（保暖/饱足/安全/自主/归属/意义/健康） ----------
var weights := {"warmth": 50.0, "satiety": 50.0, "safety": 50.0,
	"autonomy": 50.0, "belonging": 50.0, "meaning": 50.0, "health": 50.0}
var trust: float = 50.0          ## 信任度（0-100）：<DV.AI_TRUST_LOW 无视非紧急指令；>DV.AI_TRUST_HIGH 盲从
var _ai_t: float = 0.0           ## AI tick 累加器（权重衰减按分钟结算）

## 灾难/环境对权重的偏移（game.gd 灾难结算调用）
## 注：参数名用 mul——"scale" 会遮蔽基类 Node3D.scale 属性（编辑器报 shadowing）
func apply_weight_shift(shift: Dictionary, mul: float = 1.0) -> void:
	for k in shift:
		if weights.has(k):
			weights[k] = clampf(weights[k] + float(shift[k]) * mul, 0.0, 100.0)

## 权重自然衰减：每分钟按 DV.AI_WEIGHT_DECAY 向基线 50 回归（D系AI冲突引擎）
func tick_ai(minutes: float) -> void:
	_ai_t += minutes
	if _ai_t < 1.0:
		return
	var steps: int = int(_ai_t)
	_ai_t -= steps
	for k in weights:
		weights[k] = clampf(lerpf(weights[k], 50.0, minf(1.0, DV.AI_WEIGHT_DECAY * float(steps))), 0.0, 100.0)

## 信任升降：分享物资/被救援 → +；被抢夺/长期饿肚子 → -
func adjust_trust(delta: float) -> void:
	trust = clampf(trust + delta, 0.0, 100.0)

## 是否服从一条非紧急指令（D系AI：信任阈值门控）
func obeys() -> bool:
	return trust >= DV.AI_TRUST_LOW

## 是否盲从（信任过高：自主大幅下降，无条件跟随）
func is_blind_obey() -> bool:
	return trust >= DV.AI_TRUST_HIGH

## 与另一名同伴的冲突强度与升级档（DV.AI_CONFLICT_BASE / AI_CONFLICT_STAGES）
## 返回 {intensity, stage(0..3), dim, cat, name}
func conflict_with(other: SurvivorNPC) -> Dictionary:
	if other == self:
		return {"intensity": 0.0, "stage": 0, "dim": "", "cat": "", "name": "无"}
	var max_div := 0.0
	var dim := ""
	for k in DV.AI_WEIGHTS:
		var d: float = absf(weights.get(k, 50.0) - other.weights.get(k, 50.0))
		if d > max_div:
			max_div = d
			dim = k
	# 权重维度 → 冲突类别（资源/秩序/风险/规则/信任破裂）
	var cat: String = {"warmth": "resource", "satiety": "resource", "safety": "risk",
		"autonomy": "rule", "belonging": "trust_break", "meaning": "order",
		"health": "risk"}.get(dim, "resource")
	var base: float = float(DV.AI_CONFLICT_BASE.get(cat, 40))
	var intensity: float = base * (max_div / 100.0)
	var stage: int = 0
	var sname: String = "无"
	var i := 0
	for st in DV.AI_CONFLICT_STAGES:
		if intensity >= float(st.get("max", 999.0)):
			stage = i
			sname = String(st.get("name", ""))
		i += 1
	return {"intensity": intensity, "stage": stage, "dim": dim, "cat": cat, "name": sname}

func setup(id: String, pos: Vector3) -> void:
	sid = id
	def = Survivors.def(id)
	position = pos
	collision_layer = 4
	collision_mask = 0
	add_to_group("npcs")
	# 交互射线命中用碰撞体：没有它，准星会直接穿过人，永远弹不出交谈提示
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.8, 1.85, 0.7)
	cs.shape = bs
	cs.position = Vector3(0, 0.925, 0)
	add_child(cs)
	# 接触体积：瞄准整个人即可交谈，走近也出提示
	ContactVolume.attach(self, 1.5)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.45, 0.5, 0.6)
	cloth.roughness = 0.9
	body_root = Node3D.new()
	add_child(body_root)
	var torso := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.75, 0.3)
	torso.mesh = bm
	torso.material_override = cloth
	torso.position = Vector3(0, 1.05, 0)
	body_root.add_child(torso)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.34
	head.mesh = sm
	head.material_override = cloth
	head.position = Vector3(0, 1.58, 0)
	body_root.add_child(head)
	for lx in [-0.13, 0.13]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.16, 0.7, 0.18)
		leg.mesh = lm
		leg.material_override = cloth
		leg.position = Vector3(lx, 0.35, 0)
		body_root.add_child(leg)
	# 冰封外壳
	ice = MeshInstance3D.new()
	var im := BoxMesh.new()
	im.size = Vector3(0.95, 1.9, 0.75)
	ice.mesh = im
	var imat := StandardMaterial3D.new()
	imat.albedo_color = Color(0.65, 0.85, 0.98, 0.55)
	imat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	imat.roughness = 0.1
	imat.metallic = 0.2
	ice.material_override = imat
	ice.position = Vector3(0, 0.95, 0)
	body_root.add_child(ice)

func npc_name() -> String:
	return String(def.get("name", "她"))

## 状态机统一入口：状态变化时若准星正对着我，立即刷新交互提示
## （否则"守在火边…"不会自动变成"与XX交谈"）
func _set_state(s: String) -> void:
	state = s
	var g_st: Node = get_node_or_null("/root/Game")
	var p: Node = g_st.get("player") if g_st else null
	if is_instance_valid(p) and p.get("interact_target") == self and p.has_method("_refresh_prompt"):
		p.call("_refresh_prompt")

func get_prompt(_player) -> String:
	match state:
		"frozen":
			return "搬起冰封的%s [E]" % npc_name()
		"thawing":
			return "守在火边，等%s化开……" % npc_name()
		"free":
			return "与%s交谈 [E]" % npc_name()
		"joined":
			return "与%s交谈 [E]" % npc_name()
	return ""

func interact(player) -> void:
	var g_in: Node = get_node_or_null("/root/Game")
	match state:
		"frozen":
			carried = true
			player.carrying = self
			if g_in:
				g_in.call("notify", "你把%s背了起来。沉，但是活的。搬到火边去。" % npc_name(), "info")
		"free", "joined":
			var hud_np: Node = g_in.get("hud") if g_in else null
			if is_instance_valid(hud_np) and hud_np.has_method("open_dialogue"):
				hud_np.call("open_dialogue", self)

func _process(delta: float) -> void:
	var g_pc: Node = get_node_or_null("/root/Game")
	if g_pc == null:
		return
	var player_node: Node = g_pc.get("player")
	# 搬运跟随
	if carried and is_instance_valid(player_node) and player_node.get("hold"):
		global_position = player_node.get("hold").global_position
		return
	# 靠近火源自动开始解冻
	if state == "frozen":
		var warm := float(g_pc.get("fire_strength")) > 0.25 or float(g_pc.get("home_fire_bonus")) > 0.0
		if warm:
			_set_state("thawing")
			carried = false
			if is_instance_valid(player_node):
				player_node.set("carrying", null)
			g_pc.call("notify", "背上的冰层开始化了……把她放到火边，守着别走开。", "good")
	if state == "thawing":
		var warming := float(g_pc.get("fire_strength")) > 0.12 or float(g_pc.get("home_fire_bonus")) > 0.0
		if warming:
			thaw += delta
			if ice:
				ice.scale = Vector3.ONE * maxf(0.05, 1.0 - thaw / 22.0)
			if thaw >= 22.0:
				_finish_thaw()
		else:
			thaw = maxf(0.0, thaw - delta * 0.4)
	# 同伴跟随
	if state == "joined" and is_instance_valid(player_node):
		var ppos: Vector3 = player_node.global_position
		var d := global_position.distance_to(ppos)
		if d > 3.2:
			follow_t -= delta
			if follow_t <= 0.0:
				follow_t = 0.1
				var dir := (ppos - global_position).normalized()
				global_position += dir * minf(d - 3.0, 3.4) * delta * 1.4
				global_position.y = lerpf(global_position.y, ppos.y, 0.2)

func _finish_thaw() -> void:
	_set_state("free")
	if ice:
		ice.visible = false
	var hello := String(def.get("hello", "……谢谢。"))
	var g_ft: Node = get_node_or_null("/root/Game")
	if g_ft:
		g_ft.call("notify", "%s睁开了眼。\n「%s」" % [npc_name(), hello], "clue")
		g_ft.call("set_flag", "met_" + sid, true)

# ---------- 加入条件 ----------

func max_companions() -> int:
	var g_mc: Node = get_node_or_null("/root/Game")
	return 2 + (int(g_mc.get("shelter_level")) if g_mc else 0)

func join_check() -> Dictionary:
	var g_jc: Node = get_node_or_null("/root/Game")
	# 信任阈值门控（D系AI）：信任过低时不听劝留
	if trust < DV.AI_TRUST_LOW:
		return {"ok": false, "reason": "%s还在防着你——信任没攒够（%.0f/%0.f）。" % [npc_name(), trust, DV.AI_TRUST_LOW]}
	if int(g_jc.get("shelter_level") if g_jc else 0) < int(def.get("join_shelter", 1)):
		return {"ok": false, "reason": "她打量着四周：这儿还不够遮风。庇护所再结实些（%d 级），她才好留下。" % int(def.get("join_shelter", 1))}
	var need: Dictionary = def.get("need", {})
	var need_id := String(need.get("item", ""))
	var need_n := int(need.get("count", 1))
	# 盲从（信任>AI_TRUST_HIGH）：哪怕缺一样东西，也愿意留下
	if not is_blind_obey() and need_id != "" and int(g_jc.call("count_item", need_id) if g_jc else 0) < need_n:
		return {"ok": false, "reason": String(def.get("need_text", "她还缺一样东西。"))}
	if int(g_jc.get("companions").size() if g_jc else 0) >= max_companions():
		return {"ok": false, "reason": "她摇头：人多了，嘴也多。你这儿现在养不起更多。"}
	return {"ok": true, "reason": ""}

func join() -> void:
	var g_jo: Node = get_node_or_null("/root/Game")
	adjust_trust(20.0)   # 决定留下，信任显著上升
	var need: Dictionary = def.get("need", {})
	var need_id := String(need.get("item", ""))
	if need_id != "" and g_jo:
		g_jo.call("remove_item", need_id, int(need.get("count", 1)))
	_set_state("joined")
	if g_jo:
		var companions: Array = g_jo.get("companions")
		companions.append(self)
		g_jo.call("notify", "%s加入了。\n「%s」" % [npc_name(), String(def.get("joined", "我留下。"))], "good")
		g_jo.call("emit_signal", "companion_joined", npc_name())

func is_near(player) -> bool:
	return state == "joined" and is_instance_valid(self) and global_position.distance_to(player.global_position) < 6.0

func on_new_day() -> void:
	if state != "joined":
		return
	var g_nd: Node = get_node_or_null("/root/Game")
	if g_nd == null:
		return
	# 人多意味着要养更多张嘴
	for food in ["cooked_meat", "canned", "frozen_meat"]:
		if int(g_nd.call("count_item", food)) > 0:
			g_nd.call("remove_item", food, 1)
			adjust_trust(5.0)   # 吃饱了，信任回升
			return
	g_nd.set("health", maxf(0.0, float(g_nd.get("health")) - 2.0))
	adjust_trust(-10.0)   # 没吃饱，信任下滑
	g_nd.call("notify", "今天有人没吃饱。%s 的嘴唇发白。" % npc_name(), "bad")

func to_save() -> Dictionary:
	return {
		"sid": sid, "state": state, "thaw": thaw,
		"pos": [global_position.x, global_position.y, global_position.z],
	}

func from_save(d: Dictionary) -> void:
	state = String(d.get("state", "frozen"))
	thaw = float(d.get("thaw", 0.0))
	var p: Array = d.get("pos", [0, 0, 0])
	global_position = Vector3(p[0], p[1], p[2])
	if state != "frozen" and ice:
		ice.visible = state == "thawing"
		ice.scale = Vector3.ONE * maxf(0.05, 1.0 - thaw / 22.0)
	var g_fs: Node = get_node_or_null("/root/Game")
	if state == "joined" and g_fs and not g_fs.get("companions").has(self):
		g_fs.get("companions").append(self)
