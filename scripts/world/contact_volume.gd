extends Area3D
class_name ContactVolume
## 接触体积：比碰撞体积大一截的感知球（layer 8）。
## 用途一：交互射线（collide_with_areas）打中它，等同于瞄准了整个物体——
##   不用再瞄树干上某个点，瞄树就算树。
## 用途二：玩家的接触探针（同层 Area）与它重叠，等同于"人就在物体旁边"，
##   走近即出交互提示（森林之子式）。
## 所有可交互物体（枯树/冰岩/货架/床/地基/终端/NPC/生物）都挂一个。

static func attach(parent: Node3D, radius: float) -> Area3D:
	var a := Area3D.new()
	a.name = "ContactVolume"
	a.collision_layer = DV.LAYER_CONTACT
	a.collision_mask = 0
	a.set_meta("interact_owner", parent)
	parent.add_to_group("interactables")   # 供玩家"瞄准辅助"在范围内挑选对齐目标
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = radius
	cs.shape = ss
	# 球心略高于脚：覆盖物体主体，不埋进地里
	cs.position = Vector3(0, radius * 0.55, 0)
	a.add_child(cs)
	parent.add_child(a)
	return a
