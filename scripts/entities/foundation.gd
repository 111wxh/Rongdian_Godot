extends StaticBody3D
class_name FoundationMarker
## 可占地基：保安亭、便利店、半塌门房、墙根——以现成为家

var fname := ""
var fdesc := ""
var claimed := false

## autoload「Game」在编译期不可见（game.gd 依赖本类所在解析链），
## 运行时按 /root/Game 取节点。
func _g() -> Node:
	var ml := Engine.get_main_loop()
	return ml.root.get_node_or_null("Game") if ml else null

func setup(_name: String, desc: String) -> void:
	fname = _name
	fdesc = desc
	collision_layer = 4
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 2.4, 2.2)
	cs.shape = bs
	add_child(cs)
	# 接触体积：瞄准整个地基即可占领，走近也出提示
	ContactVolume.attach(self, 2.0)
	# 一面小旗：这里是"可占"的提示
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = 2.0
	pole.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.3, 0.3, 0.33)
	pole.material_override = pm
	pole.position = Vector3(0, 1.0, 0)
	add_child(pole)
	var flag := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.4, 0.05)
	flag.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.85, 0.3, 0.25)
	flag.material_override = fm
	flag.position = Vector3(0.36, 1.75, 0)
	add_child(flag)

func get_prompt(_player) -> String:
	var g_fm: Node = _g()
	if claimed or bool(g_fm.get("has_home")):
		return ""
	return "把「%s」占为家 [E]" % fname

func interact(_player) -> void:
	var g_fi: Node = _g()
	if claimed or bool(g_fi.get("has_home")):
		return
	claimed = true
	g_fi.set("has_home", true)
	g_fi.set("home_type", fname)
	g_fi.set("home_center", global_position)
	g_fi.call("notify", "从今天起，「%s」就是你的地方了。\n%s\n按 B 可以在家附近搭墙、盖顶、生火、架床。" % [fname, fdesc], "good")
	g_fi.call("set_flag", "has_home", true)
