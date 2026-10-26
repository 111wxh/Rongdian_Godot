extends Node
class_name Builder
## 建造放置：幽灵预览（含亮边描边）/ 网格吸附 / 旋转 / 材料校验 / AABB 重叠 / 家附近限制
## 自由搭建：墙/地板/柱/屋顶按 1m 网格摆放，AABB 只拦真重叠——严丝合缝贴建是允许的

var ghost: MeshInstance3D
var ghost_edge: MeshInstance3D   ## 描边壳（CULL_FRONT 只画背面）：白雪地也看得见幽灵
var current_key := ""
var rot_y := 0.0
var _len := 0.0                  ## 伸缩长度（米，0=用定义默认）：滚轮调节，任意长度墙/地板
var _place_cd := 0.0   ## 放置建材冷却（DV.T_PLACE：放下后短暂不能连放，约束交互节奏）
var _last_prompt := "~none~"   ## 已推送的放置提示缓存（变化才推，避免每帧刷）
var _pulse_t := 0.0            ## 无效位置脉冲计时

const LEN_MIN := 1.0
const LEN_MAX := 12.0
const LEN_STEP := 0.5

func _ready() -> void:
	ghost = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	ghost.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.95, 0.6, 0.28)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(0.3, 0.8, 0.4)
	m.emission_energy_multiplier = 0.5
	ghost.material_override = m
	ghost.visible = false
	# 亮边壳：比幽灵大 2%，无光照、只渲染背面 → 透出"空心亮边"的预览感
	ghost_edge = MeshInstance3D.new()
	var ebm := BoxMesh.new()
	ebm.size = Vector3.ONE
	ghost_edge.mesh = ebm
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.78, 1.0, 0.88, 0.85)
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em.cull_mode = BaseMaterial3D.CULL_FRONT
	ghost_edge.material_override = em
	ghost_edge.scale = Vector3.ONE * 1.02
	ghost_edge.visible = false
	ghost.add_child(ghost_edge)
	var g_wd: Node = get_node_or_null("/root/Game")
	var world_node: Node = g_wd.get("world") if g_wd else null
	if is_instance_valid(world_node):
		world_node.add_child(ghost)

func clear_ghost() -> void:
	current_key = ""
	ghost.visible = false
	_clear_prompt_if_mine()

func set_key(k: String) -> void:
	current_key = k
	rot_y = 0.0   ## 换做法时朝向归零，避免沿用上一个建筑的斜角
	_len = 0.0    ## 长度也归零（用定义默认）
	ghost.visible = k != ""
	_last_prompt = "~none~"

## 当前做法的实际占地尺寸（可伸缩件按 _len 拉长 local X）
func _piece_size() -> Vector3:
	var d := BuildingDefs.def(current_key)
	var size: Vector3 = d.get("size", Vector3.ONE)
	if _len > 0.0 and bool(d.get("stretch", false)):
		return Vector3(_len, size.y, size.z)
	return size

func _adjust_len(delta: float) -> void:
	var d := BuildingDefs.def(current_key)
	if not bool(d.get("stretch", false)):
		return
	var base: float = float(d.get("size", Vector3.ONE).x)
	if _len <= 0.0:
		_len = base
	_len = clampf(snappedf(_len + delta, LEN_STEP), LEN_MIN, LEN_MAX)

func _unhandled_input(event: InputEvent) -> void:
	var g_bld: Node = get_node_or_null("/root/Game")
	if g_bld == null or not bool(g_bld.get("build_mode")) or current_key == "":
		return
	if event.is_action_pressed("rotate_build"):
		rot_y += PI / 4.0
	if event.is_action_pressed("build_extend"):
		_adjust_len(LEN_STEP)
	if event.is_action_pressed("build_shrink"):
		_adjust_len(-LEN_STEP)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_back_to_menu()
	if event.is_action_pressed("cancel"):
		_back_to_menu()
	# E 落位（interact 动作已绑 E，与直接鼠标点击等价）
	if event.is_action_pressed("interact"):
		_try_place()

func _back_to_menu() -> void:
	var g_bm: Node = get_node_or_null("/root/Game")
	g_bm.set("build_mode", false)
	ghost.visible = false
	var hud_bm: Node = g_bm.get("hud") if g_bm else null
	if is_instance_valid(hud_bm) and hud_bm.has_method("reopen_build_menu"):
		hud_bm.call("reopen_build_menu")

func _process(_delta: float) -> void:
	var g_bp: Node = get_node_or_null("/root/Game")
	if g_bp == null:
		return
	if _place_cd > 0.0:
		_place_cd = maxf(0.0, _place_cd - _delta)
	var player_node: Node = g_bp.get("player")
	if not bool(g_bp.get("build_mode")) or current_key == "" or not is_instance_valid(player_node):
		ghost.visible = false
		if ghost_edge:
			ghost_edge.visible = false
		_clear_prompt_if_mine()
		return
	var d := BuildingDefs.def(current_key)
	if d.is_empty():
		ghost.visible = false
		return
	var size: Vector3 = _piece_size()
	(ghost.mesh as BoxMesh).size = size
	if ghost_edge:
		(ghost_edge.mesh as BoxMesh).size = size
		ghost_edge.visible = true
	var cam: Camera3D = player_node.get("cam")
	if cam == null:
		return
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var to := from + fwd * 6.5
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var hit: Dictionary = player_node.get_world_3d().direct_space_state.intersect_ray(q)
	var ground_y := 0.0
	if hit:
		ground_y = hit["position"].y
	else:
		var world_node: Node = g_bp.get("world")
		if is_instance_valid(world_node) and world_node.has_method("height_at"):
			ground_y = float(world_node.call("height_at", from.x + fwd.x * 5.0, from.z + fwd.z * 5.0))
	var hx: float = hit["position"].x if hit else from.x + fwd.x * 5.0
	var hz: float = hit["position"].z if hit else from.z + fwd.z * 5.0
	# +0.02 抬升：底面恰好贴地时会与地形 z-fighting（幽灵底半截闪）——穿模/闪面修复
	var pos := Vector3(round(hx), ground_y + size.y / 2.0 + 0.02, round(hz))
	ghost.position = pos
	ghost.rotation.y = rot_y
	var v := _validate(pos)
	var ok: bool = v.get("ok", false)
	var m: StandardMaterial3D = ghost.material_override as StandardMaterial3D
	var em: StandardMaterial3D = ghost_edge.material_override as StandardMaterial3D if ghost_edge else null
	# 无效位置：轻微脉冲 + 略微胀缩，把视线吸过来（不是刺眼的闪）
	_pulse_t += _delta
	var pulse := 0.0 if ok else (0.5 + 0.5 * sin(_pulse_t * 6.0))
	if ok:
		m.albedo_color = Color(0.5, 0.95, 0.6, 0.28)
		m.emission = Color(0.3, 0.8, 0.4)
		if em:
			em.albedo_color = Color(0.78, 1.0, 0.88, 0.85)
		ghost.scale = Vector3.ONE
	else:
		m.albedo_color = Color(0.95, 0.4, 0.4, 0.26 + pulse * 0.14)
		m.emission = Color(0.8, 0.25, 0.25)
		if em:
			em.albedo_color = Color(1.0, 0.55, 0.55, 0.6 + pulse * 0.3)
		ghost.scale = Vector3.ONE * (1.0 + pulse * 0.015)
	# 放置提示：名字+材料+操作指引，或不合格的原因（只在变化时推送）
	var prompt := _build_prompt(ok, String(v.get("why", "")))
	if prompt != _last_prompt:
		_last_prompt = prompt
		g_bp.call("push_prompt", prompt)

func _build_prompt(ok: bool, why: String) -> String:
	var head := "%s（%s）" % [BuildingDefs.name_of(current_key), _cost_text(current_key)]
	var ops := "[左键/E] 落位 · [R] 旋转"
	if bool(BuildingDefs.def(current_key).get("stretch", false)):
		ops += " · [滚轮] 长度 %.1fm" % _piece_size().x
	ops += " · [右键/Esc] 返回"
	if ok:
		return "%s\n%s" % [head, ops]
	return "%s\n%s" % [head, why]

func _clear_prompt_if_mine() -> void:
	if _last_prompt != "" and _last_prompt != "~none~":
		_last_prompt = ""
		var g_cp: Node = get_node_or_null("/root/Game")
		if g_cp:
			g_cp.call("push_prompt", "")

## 旋转后的 XY 占地范围（AABB 半宽对）：45° 斜放也按真实外接盒算
## len_override > 0 时按伸缩后的 local X 长度算（任意长度墙）
func _extents(key: String, rot: float, len_override: float = 0.0) -> Vector2:
	var size: Vector3 = BuildingDefs.def(key).get("size", Vector3.ONE)
	if len_override > 0.0:
		size = Vector3(len_override, size.y, size.z)
	var c := absf(cos(rot))
	var s := absf(sin(rot))
	return Vector2(size.x * c + size.z * s, size.x * s + size.z * c)

func _validate(pos: Vector3) -> Dictionary:
	var g_v: Node = get_node_or_null("/root/Game")
	var d := BuildingDefs.def(current_key)
	if d.is_empty():
		return {"ok": false, "why": "没有这个做法。"}
	var discount := _discount()
	if not BuildingDefs.can_afford(current_key, discount):
		return {"ok": false, "why": "材料不够：%s。" % _cost_text(current_key)}
	if g_v and bool(g_v.get("has_home")):
		var home_center: Vector3 = g_v.get("home_center")
		var hd := Vector2(pos.x - home_center.x, pos.z - home_center.z).length()
		if hd > 22.0:
			return {"ok": false, "why": "离家太远了（%.0f 米）。家在那儿。" % hd}
	# AABB 重叠：允许严丝合缝地贴建（自由搭建的关键），只拦真重叠（留 6cm 容差）
	var mine := _extents(current_key, rot_y, _len if bool(d.get("stretch", false)) else 0.0)
	for b in g_v.get("buildings") if g_v else []:
		var bp: Array = b.get("pos", [0, 0, 0])
		var blen: float = float(b.get("len", 0.0))
		var theirs := _extents(String(b.get("type", "")), float(b.get("rot", 0.0)), blen)
		var dx := absf(pos.x - float(bp[0]))
		var dz := absf(pos.z - float(bp[2]))
		if dx < (mine.x + theirs.x) * 0.5 - 0.06 and dz < (mine.y + theirs.y) * 0.5 - 0.06:
			return {"ok": false, "why": "这儿放不下，和已有的挨得太紧。"}
	return {"ok": true, "why": ""}

func _cost_text(key: String) -> String:
	var parts := []
	for id in BuildingDefs.cost_of(key):
		parts.append("%s×%d" % [Items.name_of(id), int(BuildingDefs.cost_of(key)[id])])
	return "、".join(parts)

func _discount() -> float:
	var g_dc: Node = get_node_or_null("/root/Game")
	for c in g_dc.get("companions") if g_dc else []:
		if c is SurvivorNPC and String(c.def.get("skill", "")) == "builder":
			return 0.2
	return 0.0

func _try_place() -> void:
	var g_tp: Node = get_node_or_null("/root/Game")
	if g_tp == null or not bool(g_tp.get("build_mode")) or current_key == "":
		return
	if _place_cd > 0.0:
		return
	var v := _validate(ghost.position)
	if not v.get("ok", false):
		g_tp.call("notify", v.get("why", ""), "bad")
		return
	var discount := _discount()
	BuildingDefs.pay(current_key, discount)
	var entry := {
		"type": current_key,
		"pos": [ghost.position.x, ghost.position.y, ghost.position.z],
		"rot": rot_y,
		"len": _len,
		"level": 1,
		"hp": 100.0,
	}
	var buildings: Array = g_tp.get("buildings")
	buildings.append(entry)
	spawn_building(entry)
	var home_center: Vector3 = g_tp.get("home_center")
	g_tp.set("shelter_level", ShelterJudge.compute(buildings, home_center))
	var extra := ""
	if BuildingDefs.is_fire(current_key):
		extra = "火生起来了——靠近就暖。"
	g_tp.call("notify", "搭好了：%s。%s\n庇护所：%s（%d 级）" % [
		BuildingDefs.name_of(current_key), extra,
		BuildingDefs.level_name(int(g_tp.get("shelter_level"))), int(g_tp.get("shelter_level"))], "good")
	var sound: Node = g_tp.get("sound")
	if is_instance_valid(sound) and sound.has_method("play_place"):
		sound.call("play_place")
	_place_cd = DV.T_PLACE   ## 放置冷却：约束连续建造节奏（操作手感规格 T_PLACE）

# ---------- 图纸：自绘保存 / 一键放置 ----------

func capture_blueprint(bp_name: String) -> Dictionary:
	## 把当前家里的布置存为图纸（相对 home_center 的偏移）
	var g_cb: Node = get_node_or_null("/root/Game")
	if g_cb == null:
		return {"name": bp_name, "layout": []}
	var home_center: Vector3 = g_cb.get("home_center")
	var layout := []
	for b in g_cb.get("buildings"):
		var p: Array = b.get("pos", [0, 0, 0])
		layout.append({
			"type": String(b.get("type", "")),
			"dx": float(p[0]) - home_center.x,
			"dz": float(p[2]) - home_center.z,
			"rot": float(b.get("rot", 0.0)),
			"len": float(b.get("len", 0.0)),
		})
	return {"name": bp_name, "layout": layout}

func _bp_ground_y(x: float, z: float, size_y: float) -> float:
	var g_by: Node = get_node_or_null("/root/Game")
	var g := 0.0
	if g_by:
		var home_center: Vector3 = g_by.get("home_center")
		g = home_center.y
		var world_node: Node = g_by.get("world")
		if is_instance_valid(world_node) and world_node.has_method("height_at"):
			g = float(world_node.call("height_at", x, z))
	return g + size_y / 2.0

func apply_blueprint(bp: Dictionary) -> Dictionary:
	## 一键放置：先整张预演，全部可行才动工（避免半张图纸的烂尾）
	var g_ab: Node = get_node_or_null("/root/Game")
	if g_ab == null or not bool(g_ab.get("has_home")):
		return {"ok": false, "why": "还没有家。先找一处地基占下来。"}
	var home_center: Vector3 = g_ab.get("home_center")
	var buildings: Array = g_ab.get("buildings")
	var layout: Array = bp.get("layout", [])
	if layout.is_empty():
		return {"ok": false, "why": "图纸是空的。"}
	var discount := _discount()
	var planned: Array = []
	var taken: Array = []   # 本批已占用的落点（图纸内部也不能互相压）
	for item in layout:
		var key := String(item.get("type", ""))
		var d := BuildingDefs.def(key)
		if d.is_empty():
			return {"ok": false, "why": "图纸里有不认得的做法。"}
		var size: Vector3 = d.get("size", Vector3.ONE)
		var px: float = home_center.x + float(item.get("dx", 0.0))
		var pz: float = home_center.z + float(item.get("dz", 0.0))
		var hd := Vector2(px - home_center.x, pz - home_center.z).length()
		if hd > 22.0:
			return {"ok": false, "why": "图纸铺得太开，超出了家的范围。"}
		if not BuildingDefs.can_afford(key, discount):
			return {"ok": false, "why": "材料不够：%s（%s）。" % [BuildingDefs.name_of(key), _cost_text(key)]}
		var pos := Vector3(px, _bp_ground_y(px, pz, size.y), pz)
		for b in buildings:
			var bp2: Array = b.get("pos", [0, 0, 0])
			if Vector2(pos.x - float(bp2[0]), pos.z - float(bp2[2])).length() < 1.0:
				return {"ok": false, "why": "家里已经有东西挡在图纸的位置上。"}
		for t in taken:
			if Vector2(pos.x - float(t[0]), pos.z - float(t[2])).length() < 1.0:
				return {"ok": false, "why": "图纸内部有互相压着的部件。"}
		taken.append([pos.x, pos.y, pos.z])
		planned.append({"type": key, "pos": [pos.x, pos.y, pos.z], "rot": float(item.get("rot", 0.0)), "len": float(item.get("len", 0.0))})
	# 预演通过：动工
	for item in planned:
		BuildingDefs.pay(String(item["type"]), discount)
		buildings.append(item)
		spawn_building(item)
	g_ab.set("shelter_level", ShelterJudge.compute(buildings, home_center))
	return {"ok": true, "why": ""}

func spawn_building(b: Dictionary) -> Node3D:
	var key := String(b.get("type", ""))
	var d := BuildingDefs.def(key)
	var size: Vector3 = d.get("size", Vector3.ONE)
	# 任意长度墙/地板：读档与图纸复刻都按存档里的 len 还原实际占地
	var blen: float = float(b.get("len", 0.0))
	if blen > 0.0 and bool(d.get("stretch", false)):
		size = Vector3(blen, size.y, size.z)
	var pos: Array = b.get("pos", [0, 0, 0])
	var body := StaticBody3D.new()
	body.name = "B_" + key
	body.add_to_group("player_building")   ## 自家建筑：可长按 E 拆除回收
	body.set_meta("key", key)
	body.position = Vector3(pos[0], pos[1], pos[2])
	body.rotation.y = float(b.get("rot", 0.0))
	body.collision_layer = 1
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = d.get("color", Color(0.5, 0.5, 0.5))
	m.roughness = 0.85
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	if bool(d.get("fire", false)):
		var flame := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.3
		cm.height = 0.9
		flame.mesh = cm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(1.0, 0.6, 0.2)
		fm.emission_enabled = true
		fm.emission = Color(1.0, 0.5, 0.15)
		fm.emission_energy_multiplier = 2.5
		flame.material_override = fm
		flame.position = Vector3(0, 0.7, 0)
		body.add_child(flame)
		var li := OmniLight3D.new()
		li.light_color = Color(1.0, 0.6, 0.3)
		li.light_energy = 3.2
		li.omni_range = 13.0
		li.position = Vector3(0, 1.1, 0)
		body.add_child(li)
	if bool(d.get("bed", false)):
		var bed := BedInteract.new()
		bed.setup(body.position, BuildingDefs.name_of(key))
		body.add_child(bed)
	var g_sb: Node = get_node_or_null("/root/Game")
	if g_sb:
		var world_node: Node = g_sb.get("world")
		if is_instance_valid(world_node):
			world_node.add_child(body)
	b["node"] = body
	return body
