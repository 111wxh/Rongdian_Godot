class_name BuildingDefs
extends RefCounted
## 建造物定义 + 庇护所等级判定（系统判级，玩家无等级）

const DEFS := {
	"wood_wall": {
		"name": "木墙", "cost": {"wood": 4}, "size": Vector3(3.0, 2.6, 0.25),
		"closure": 1.0, "insul": 0.6, "sturdy": 0.4, "color": Color(0.32, 0.23, 0.16),
		"stretch": true,   ## 可伸缩：滚轮调节长度（任意长度墙）
	},
	"wood_door": {
		"name": "木门", "cost": {"wood": 3, "rope": 1}, "size": Vector3(1.5, 2.2, 0.2),
		"closure": 0.6, "insul": 0.3, "sturdy": 0.35, "color": Color(0.28, 0.2, 0.14),
	},
	"wood_roof": {
		"name": "木屋顶", "cost": {"wood": 6, "cloth": 2}, "size": Vector3(4.0, 0.25, 4.0),
		"closure": 0.0, "insul": 0.8, "sturdy": 0.3, "roof": true, "color": Color(0.3, 0.22, 0.15),
		"stretch": true,
	},
	"stone_wall": {
		"name": "石墙", "cost": {"stone": 5}, "size": Vector3(3.0, 2.8, 0.4),
		"closure": 1.2, "insul": 0.5, "sturdy": 0.8, "color": Color(0.45, 0.47, 0.5),
		"stretch": true,
	},
	"snow_wall": {
		"name": "冰雪砖墙", "cost": {"snow_brick": 4}, "size": Vector3(3.0, 2.4, 0.5),
		"closure": 0.8, "insul": 0.7, "sturdy": 0.2, "color": Color(0.8, 0.88, 0.96),
		"stretch": true,
	},
	"campfire": {
		"name": "篝火", "cost": {"wood": 5, "matches": 1}, "size": Vector3(1.2, 0.5, 1.2),
		"closure": 0.0, "insul": 0.0, "sturdy": 0.3, "fire": true, "radius": 7.0, "power": 8.0,
		"color": Color(0.9, 0.5, 0.2),
	},
	"stone_fire": {
		"name": "石圈火塘", "cost": {"stone": 4, "wood": 6}, "size": Vector3(1.6, 0.4, 1.6),
		"closure": 0.0, "insul": 0.0, "sturdy": 0.6, "fire": true, "radius": 9.0, "power": 11.0,
		"color": Color(0.9, 0.55, 0.25),
	},
	"bed": {
		"name": "简易床", "cost": {"wood": 4, "cloth": 2}, "size": Vector3(1.2, 0.5, 2.1),
		"closure": 0.0, "insul": 0.2, "sturdy": 0.3, "bed": true, "color": Color(0.5, 0.4, 0.3),
	},
	"storage": {
		"name": "储物箱", "cost": {"wood": 5, "rope": 2}, "size": Vector3(1.4, 1.0, 1.0),
		"closure": 0.0, "insul": 0.1, "sturdy": 0.5, "storage": true, "color": Color(0.35, 0.27, 0.19),
	},
	# ---- 结构件（自由搭建套装：墙/地/柱/顶可严丝合缝拼装） ----
	"wood_floor": {
		"name": "木地板", "cost": {"wood": 3}, "size": Vector3(3.0, 0.2, 3.0),
		"closure": 0.0, "insul": 0.25, "sturdy": 0.3, "color": Color(0.36, 0.27, 0.19),
		"stretch": true,
	},
	"wood_pillar": {
		"name": "木柱", "cost": {"wood": 2}, "size": Vector3(0.35, 2.6, 0.35),
		"closure": 0.0, "insul": 0.1, "sturdy": 0.4, "color": Color(0.3, 0.22, 0.16),
	},
}

const LEVEL_NAMES := ["避风窝", "挡雪屋", "稳暖庇护所", "石木之家", "融点之家"]

## ---------- 营地高级建筑（DV.BUILDINGS 桥接） ----------
## 尺寸/颜色按建筑类型估算，让幽灵放置与庇护所判定直接复用现有逻辑
const ADV_META := {
	"camp_center": {"size": Vector3(4.0, 3.0, 4.0), "closure": 1.0, "insul": 0.9, "sturdy": 0.9, "color": Color(0.42, 0.34, 0.26)},
	"barracks": {"size": Vector3(5.0, 2.8, 4.0), "closure": 1.0, "insul": 0.8, "sturdy": 0.6, "color": Color(0.4, 0.32, 0.24)},
	"medical": {"size": Vector3(4.0, 2.6, 5.0), "closure": 0.8, "insul": 0.7, "sturdy": 0.5, "color": Color(0.75, 0.75, 0.72)},
	"warehouse": {"size": Vector3(5.0, 3.0, 6.0), "closure": 0.9, "insul": 0.6, "sturdy": 0.7, "color": Color(0.38, 0.36, 0.33)},
	"furnace": {"size": Vector3(2.5, 2.5, 2.5), "closure": 0.2, "insul": 0.3, "sturdy": 0.9, "color": Color(0.45, 0.25, 0.2)},
	"workbench": {"size": Vector3(2.0, 1.0, 1.5), "closure": 0.0, "insul": 0.1, "sturdy": 0.5, "color": Color(0.45, 0.33, 0.22)},
	"brine_pool": {"size": Vector3(4.0, 0.4, 4.0), "closure": 0.0, "insul": 0.0, "sturdy": 0.4, "color": Color(0.6, 0.68, 0.72)},
	"heat_exchanger": {"size": Vector3(1.5, 2.0, 1.5), "closure": 0.0, "insul": 0.2, "sturdy": 0.6, "color": Color(0.55, 0.58, 0.62)},
	"ice_cellar": {"size": Vector3(5.0, 2.6, 5.0), "closure": 0.8, "insul": 0.5, "sturdy": 0.7, "color": Color(0.55, 0.7, 0.82)},
	"farm": {"size": Vector3(6.0, 0.6, 6.0), "closure": 0.0, "insul": 0.2, "sturdy": 0.3, "color": Color(0.35, 0.4, 0.3)},
	"trap": {"size": Vector3(1.5, 0.4, 1.5), "closure": 0.0, "insul": 0.0, "sturdy": 0.3, "color": Color(0.4, 0.35, 0.28)},
	"campfire": {"size": Vector3(1.2, 0.5, 1.2), "closure": 0.0, "insul": 0.0, "sturdy": 0.3, "fire": true, "radius": 7.0, "power": 8.0, "color": Color(0.9, 0.5, 0.2)},
	"geothermal": {"size": Vector3(3.0, 2.5, 3.0), "closure": 0.2, "insul": 0.3, "sturdy": 0.9, "color": Color(0.5, 0.35, 0.3)},
	"solar": {"size": Vector3(3.0, 0.3, 2.0), "closure": 0.0, "insul": 0.0, "sturdy": 0.4, "color": Color(0.2, 0.3, 0.5)},
	"nuclear": {"size": Vector3(1.5, 1.5, 1.5), "closure": 0.0, "insul": 0.1, "sturdy": 0.9, "color": Color(0.6, 0.6, 0.3)},
	"windmill": {"size": Vector3(1.5, 4.0, 1.5), "closure": 0.0, "insul": 0.0, "sturdy": 0.6, "color": Color(0.6, 0.62, 0.65)},
	"wood_wall": {"size": Vector3(3.0, 2.6, 0.25), "closure": 1.0, "insul": 0.6, "sturdy": 0.4, "color": Color(0.32, 0.23, 0.16)},
	"watchtower": {"size": Vector3(2.0, 4.0, 2.0), "closure": 0.3, "insul": 0.4, "sturdy": 0.7, "color": Color(0.42, 0.34, 0.24)},
	"research": {"size": Vector3(3.0, 1.2, 2.0), "closure": 0.0, "insul": 0.1, "sturdy": 0.5, "color": Color(0.5, 0.42, 0.55)},
	"diary_room": {"size": Vector3(3.0, 2.5, 3.0), "closure": 0.8, "insul": 0.7, "sturdy": 0.6, "color": Color(0.48, 0.4, 0.3)},
	"antenna": {"size": Vector3(1.0, 6.0, 1.0), "closure": 0.0, "insul": 0.0, "sturdy": 0.5, "color": Color(0.55, 0.55, 0.58)},
	"purifier": {"size": Vector3(2.5, 2.0, 2.5), "closure": 0.2, "insul": 0.3, "sturdy": 0.6, "color": Color(0.4, 0.55, 0.6)},
	"counseling": {"size": Vector3(4.0, 2.5, 4.0), "closure": 0.9, "insul": 0.8, "sturdy": 0.6, "color": Color(0.55, 0.45, 0.5)},
}

## 高级建筑定义（成本换算为现有材料 id：wood/stone/metal/fuel）
static func advanced_def(key: String) -> Dictionary:
	var d: Dictionary = DV.BUILDINGS.get(key, {})
	if d.is_empty():
		return {}
	var meta: Dictionary = ADV_META.get(key, {})
	var cost := {}
	for rid in ["wood", "stone", "metal", "fuel"]:
		var v: int = int(d.get(rid, 0))
		if v > 0:
			cost[rid] = v
	var out := meta.duplicate()
	out["name"] = String(d.get("name", key))
	out["cost"] = cost
	out["build_time"] = float(d.get("time", 30.0))
	out["heat_cost"] = float(d.get("heat", 0.0))
	out["labor"] = int(d.get("labor", 1))
	out["heat_out_w"] = float(d.get("heat_out", 0.0))
	out["unlock_tech"] = String(d.get("unlock", ""))
	out["advanced"] = true
	return out

static func advanced_keys() -> Array:
	var out := DV.BUILDINGS.keys()
	out.sort()
	return out

static func def(key: String) -> Dictionary:
	if DEFS.has(key):
		return DEFS[key]
	return advanced_def(key)

static func name_of(key: String) -> String:
	return String(def(key).get("name", key))

static func cost_of(key: String) -> Dictionary:
	return def(key).get("cost", {})

static func is_fire(key: String) -> bool:
	return bool(def(key).get("fire", false))

static func keys() -> Array:
	var out := DEFS.keys()
	for k in advanced_keys():
		out.append(k)
	out.sort()
	return out

## 高级建筑材料清单文本（含金属/燃料）
static func cost_text_advanced(key: String) -> String:
	var c := cost_of(key)
	var parts: Array = []
	for id in c:
		parts.append("%s×%d" % [Items.name_of(id), int(c[id])])
	return "、".join(parts)

static func can_afford(key: String, discount: float = 0.0) -> bool:
	var g_ca: Node = Engine.get_main_loop().root.get_node_or_null("Game")
	for id in cost_of(key):
		var need: int = int(ceil(float(cost_of(key)[id]) * (1.0 - discount)))
		if int(g_ca.call("count_item", id)) < need:
			return false
	return true

static func pay(key: String, discount: float = 0.0) -> void:
	var g_py: Node = Engine.get_main_loop().root.get_node_or_null("Game")
	for id in cost_of(key):
		var need: int = int(ceil(float(cost_of(key)[id]) * (1.0 - discount)))
		g_py.call("remove_item", id, need)

static func level_name(lv: int) -> String:
	var i := clampi(lv - 1, 0, LEVEL_NAMES.size() - 1)
	return LEVEL_NAMES[i]
