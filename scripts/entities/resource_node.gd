extends StaticBody3D
class_name ResourceNode
## 可搜刮/采集的物：货架、瓦砾、枯树、冰岩、遗迹、纸页……
## 体积体系（用户口径：碰撞体积 + 接触体积）：
##   碰撞体积 = StaticBody3D 本体，layer 16（道具实体：挡玩家，建造射线穿透）
##   接触体积 = ContactVolume（layer 8）：射线打中就算瞄准整物，人在旁边就算候选

var data: Dictionary = {}
var uses_left := 1
var glint: MeshInstance3D

## autoload「Game」在编译期不可见（game.gd 依赖本类所在解析链），
## 运行时按 /root/Game 取节点。
func _g() -> Node:
	var ml := Engine.get_main_loop()
	return ml.root.get_node_or_null("Game") if ml else null

## 按物体类型的碰撞/接触体积默认值（kind: cyl 圆柱 / sphere 球 / box 盒）
const COL_DEFAULTS := {
	"dead_tree": {"kind": "cyl", "r": 0.18, "h": 3.0, "contact": 1.6},
	"ice_vein": {"kind": "cyl", "r": 0.5, "h": 3.0, "contact": 1.8},
	"ice_rock": {"kind": "sphere", "r": 1.1, "contact": 1.7},
	"paper": {"kind": "box", "size": Vector3(0.5, 0.5, 0.5), "contact": 1.2},
}
const COL_FALLBACK := {"kind": "box", "size": Vector3(1.4, 1.6, 1.4), "contact": 1.5}

func setup(d: Dictionary) -> void:
	data = d
	uses_left = int(d.get("uses", 1))
	# 碰撞体积：layer 16 道具实体（挡玩家；建造射线 mask=1 穿透它）
	collision_layer = DV.LAYER_PROP
	collision_mask = 0
	var spec: Dictionary = COL_DEFAULTS.get(String(d.get("id", "")), COL_FALLBACK)
	var cs := CollisionShape3D.new()
	match String(spec.get("kind", "box")):
		"cyl":
			var cyl := CylinderShape3D.new()
			cyl.radius = float(spec.get("r", 0.2))
			cyl.height = float(spec.get("h", 3.0))
			cs.shape = cyl
			# 节点位置在地上方 0.8m：圆柱按"立在地面的树干"居中
			cs.position = Vector3(0, float(spec.get("h", 3.0)) * 0.5 - 0.8, 0)
		"sphere":
			var sph := SphereShape3D.new()
			sph.radius = float(spec.get("r", 1.0))
			cs.shape = sph
			cs.position = Vector3(0, float(spec.get("r", 1.0)) - 0.8, 0)
		_:
			var bs := BoxShape3D.new()
			var sz: Vector3 = spec.get("size", Vector3(1.4, 1.6, 1.4))
			bs.size = sz
			cs.shape = bs
	add_child(cs)
	# 接触体积：射线打中=瞄准整物，人在旁边=候选目标
	ContactVolume.attach(self, float(spec.get("contact", 1.5)))
	# 一点微光提示"这里有东西"
	glint = MeshInstance3D.new()
	var om := SphereMesh.new()
	om.radial_segments = 4
	om.rings = 2
	om.radius = 0.09
	om.height = 0.18
	glint.mesh = om
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.9, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.4, 0.7, 1.0)
	m.emission_energy_multiplier = 1.2
	glint.material_override = m
	glint.position = Vector3(0, 0.7, 0)
	add_child(glint)

func _ready() -> void:
	if glint:
		var tw := create_tween()
		tw.set_loops()
		tw.tween_property(glint, "position:y", 0.95, 1.2)
		tw.tween_property(glint, "position:y", 0.7, 1.2)

func get_prompt(_player) -> String:
	if uses_left <= 0:
		return ""
	if gather_time() > 0.0:
		# 长按采集物（枯树/冰岩/冰脉）：森林之子式，必须按住
		return "%s %s [按住左键]" % [_gather_verb(), String(data.get("name", "残迹"))]
	return "搜刮 %s [E]" % String(data.get("name", "残迹"))

func gather_time() -> float:
	## >0 = 长按采集节点（秒）；0 = 瞬按搜刮节点
	return float(data.get("gather_time", 0.0))

func _gather_verb() -> String:
	var v := String(data.get("gather_verb", ""))
	return v if v != "" else "采集"

func interact(_player) -> void:
	if uses_left <= 0:
		return
	# 长按采集物：瞬按不产出——手感由 _update_gather 的按住循环驱动
	if gather_time() > 0.0:
		return
	_roll_loot()
	if uses_left <= 0:
		_deplete()

## 长按采集完成一击：走同一套掉落，挥动/进度由玩家侧驱动
func harvest(_player) -> void:
	if uses_left <= 0:
		return
	_roll_loot()
	if uses_left <= 0:
		_deplete()

func _roll_loot() -> void:
	var g_rl: Node = _g()
	uses_left -= 1
	var gained := {}
	for l in data.get("loot", []):
		if randf() < float(l.get("chance", 1.0)):
			var id := String(l.get("id", ""))
			var n := randi_range(int(l.get("min", 1)), int(l.get("max", 1)))
			if n > 0:
				g_rl.call("add_item", id, n)
				gained[id] = int(gained.get(id, 0)) + n
	if not gained.is_empty():
		var parts := []
		for id in gained:
			parts.append("%s×%d" % [Items.name_of(id), int(gained[id])])
		g_rl.call("notify", "%s：%s" % [String(data.get("name", "残迹")), "、".join(parts)], "info")

func _deplete() -> void:
	var g_dp: Node = _g()
	g_dp.call("notify", "%s 被采空了。" % String(data.get("name", "残迹")), "info")
	if glint:
		glint.visible = false
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.55, 0.35, 0.55), 0.4)
