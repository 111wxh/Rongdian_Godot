extends StaticBody3D
class_name BedInteract
## 可睡的床：保安亭的旧床 / 自己搭的简易床

var bed_name := "床"

func setup(pos: Vector3, _name: String = "床") -> void:
	position = pos
	bed_name = _name
	collision_layer = 0
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.6, 0.7, 2.4)
	cs.shape = bs
	# 碰撞盒抬到床体高度（0.2~0.9m）：埋地只露 0.5m 时准星几乎照不到，交互失灵
	cs.position = Vector3(0, 0.55, 0)
	add_child(cs)
	# 接触体积：瞄准整张床即可睡，走近也出提示
	ContactVolume.attach(self, 1.3)

func get_prompt(_player) -> String:
	return "在%s上睡下 [E]" % bed_name

func interact(_player) -> void:
	var g_bd: Node = get_node_or_null("/root/Game")
	if g_bd == null:
		return
	var player_node: Node = g_bd.get("player")
	if not is_instance_valid(player_node):
		return
	var survival_node: Node = player_node.get("survival")
	if survival_node and survival_node.has_method("try_sleep"):
		survival_node.call("try_sleep", global_position)
