class_name Recipes
extends RefCounted
## 配方表。station: "" 随手可做 / "fire" 需在火源边
## output 若以 "build:" 开头，则产物是一处建筑（进入建造放置）。

const RECIPES := {
	"rope_from_cloth": {
		"name": "捻绳", "station": "", "inputs": {"cloth": 3}, "output": "rope",
		"desc": "三股布条拧成一股绳。",
	},
	"snow_brick_press": {
		"name": "压实冰雪砖", "station": "", "inputs": {"ice_block": 2}, "output": "snow_brick",
		"desc": "把碎冰压实成砖，垒墙挡风。",
	},
	"campfire": {
		"name": "生起篝火", "station": "", "inputs": {"wood": 5, "matches": 1}, "output": "build:campfire",
		"desc": "五根木柴一根火柴。火是这冰原上唯一讲理的东西。",
	},
	"stone_circle_fire": {
		"name": "石圈火塘", "station": "", "inputs": {"stone": 4, "wood": 6}, "output": "build:stone_fire",
		"desc": "石块圈住火，风小些，柴省些。",
	},
	"wood_wall": {
		"name": "木墙", "station": "", "inputs": {"wood": 4}, "output": "build:wood_wall",
		"desc": "四面墙挡风，家就有了形状。",
	},
	"wood_door": {
		"name": "木门", "station": "", "inputs": {"wood": 3, "rope": 1}, "output": "build:wood_door",
		"desc": "留一个能关上的口。",
	},
	"wood_roof": {
		"name": "木屋顶", "station": "", "inputs": {"wood": 6, "cloth": 2}, "output": "build:wood_roof",
		"desc": "有顶胜过露天。雪落在头顶，不落在身上。",
	},
	"stone_wall": {
		"name": "石墙", "station": "", "inputs": {"stone": 5}, "output": "build:stone_wall",
		"desc": "比木头更挡风，也更经得起灾。",
	},
	"snow_wall": {
		"name": "冰雪砖墙", "station": "", "inputs": {"snow_brick": 4}, "output": "build:snow_wall",
		"desc": "应急的墙。冷了能挡一阵。",
	},
	"bed": {
		"name": "简易床", "station": "", "inputs": {"wood": 4, "cloth": 2}, "output": "build:bed",
		"desc": "垫高离地，睡得踏实。",
	},
	"storage": {
		"name": "储物箱", "station": "", "inputs": {"wood": 5, "rope": 2}, "output": "build:storage",
		"desc": "东西归拢一处，灾来了也少丢。",
	},
	"spear": {
		"name": "制长矛", "station": "", "inputs": {"wood": 3, "rope": 1, "scrap": 1}, "output": "spear",
		"desc": "木杆绑上磨尖的金属。捕猎的家伙。",
	},
	"fur_coat": {
		"name": "缝皮袄", "station": "", "inputs": {"fur": 3, "rope": 2}, "output": "fur_coat",
		"desc": "三张皮毛缝成一件衣裳。",
	},
	"cloth_coat": {
		"name": "缝布衣", "station": "", "inputs": {"cloth": 6, "rope": 1}, "output": "cloth_coat",
		"desc": "一层布也是一层暖。",
	},
	"bandage": {
		"name": "包扎", "station": "", "inputs": {"cloth": 2, "disinfectant": 1}, "output": "bandage",
		"desc": "清洁，压住，缠好。",
	},
	"melt_water": {
		"name": "融雪取水", "station": "fire", "inputs": {"ice_block": 2}, "output": "clean_water",
		"desc": "在火边，把冰化成能喝的水。",
	},
	"cook_meat": {
		"name": "烤肉", "station": "fire", "inputs": {"frozen_meat": 1}, "output": "cooked_meat",
		"desc": "冻肉架在火上，化开再烤透。",
	},
	# ---- 热力学合成树（8种核心资源转化矩阵落地）----
	"dry_distill": {
		"name": "干馏制燃料", "station": "fire", "inputs": {"organic": 5}, "output": "fuel",
		"desc": "200-400℃ 缺氧热解：5 份有机物换 1 份燃料。吸热 50kJ，是热量的浓缩。",
	},
	"melt_ice_core": {
		"name": "化冰取水", "station": "fire", "inputs": {"ice": 2}, "output": "water",
		"desc": "冰吸热熔化：每 100g 要吃掉 33.4kJ。火边的账，一寸一寸算。",
	},
	"pack_snow": {
		"name": "压实积雪", "station": "", "inputs": {"snow": 2}, "output": "ice",
		"desc": "反复踩踏或压雪板：200g 雪出 100g 冰，放热 5kJ。",
	},
	"smelt_ore": {
		"name": "矿石冶炼", "station": "furnace", "inputs": {"rock": 4, "fuel": 1}, "output": "metal",
		"desc": ">1200℃ 还原反应：4 份岩 1 份燃料，换 2 份金属。吸热 400kJ。",
	},
	"brine_salt": {
		"name": "卤水析盐", "station": "fire", "inputs": {"water": 3}, "output": "salt",
		"desc": "蒸发结晶：盐是相变的调节剂，也是防腐与消毒的老伙计。",
	},
	"herb_bandage": {
		"name": "草药敷料", "station": "", "inputs": {"cloth": 2, "organic": 1}, "output": "bandage",
		"desc": "布条裹上捣碎的有机草药。野外急救的底子。",
	},
}

## 热力学合成树配方 → DV.TRANSFORMS 矩阵键（让 8 种核心资源转化矩阵成为唯一数值源）。
## 这样配方相变吸/放热量全部来自 DV.TRANSFORMS，不再于此处另写一份。
const TRANSFORM_KEY := {
	"dry_distill": "dry_distill",
	"melt_ice_core": "ice_melt",
	"pack_snow": "snow_pack",
	"smelt_ore": "ore_smelt",
	"brine_salt": "brine_evaporate",
}

## 该配方对应的 DV.TRANSFORMS 键；无相变账的配方返回空串
static func transform_key(rid: String) -> String:
	return TRANSFORM_KEY.get(rid, "")

## 该配方触发的相变净吸/放热（J，正=吸热、负=放热），取自 DV.TRANSFORMS。
## crafting 时由 Game.recipe_heat_delta 折算成 ΔT，真实地注入/抽离营地核心温度。
static func transform_heat(rid: String) -> float:
	var k := transform_key(rid)
	if k == "":
		return 0.0
	return float(DV.TRANSFORMS.get(k, {}).get("heat", 0.0))

static func def(rid: String) -> Dictionary:
	return RECIPES.get(rid, {})

## 徒手合成配对：两件物品在手里凑一起能做的配方（森林之子式）。
## 规则：station=""（随手可做）且输入种类 ≤2；同种物品自组合也允许（冰+冰、木+木）。
## 火边/熔炉配方不在此列——那些去制作面板。凑不到返回 ""。
static func combo_id(a: String, b: String) -> String:
	if a == "" or b == "":
		return ""
	for rid in RECIPES:
		var r: Dictionary = RECIPES[rid]
		if String(r.get("station", "")) != "":
			continue
		var ins: Dictionary = r.get("inputs", {})
		if ins.size() == 1:
			var k := String(ins.keys()[0])
			if a == k and b == k:
				return rid
		elif ins.size() == 2:
			var ka := String(ins.keys()[0])
			var kb := String(ins.keys()[1])
			if (a == ka and b == kb) or (a == kb and b == ka):
				return rid
	return ""

## 徒手合成的账目预览："木头×4、火柴×1 → 生起篝火"
static func combo_cost_text(rid: String) -> String:
	var ins: Dictionary = def(rid).get("inputs", {})
	var parts := []
	for id in ins:
		parts.append("%s×%d" % [Items.name_of(String(id)), int(ins[id])])
	return "、".join(parts)

static func name_of(rid: String) -> String:
	return def(rid).get("name", rid)

static func all_ids() -> Array:
	var out := RECIPES.keys()
	out.sort()
	return out

static func is_build(rid: String) -> bool:
	return String(def(rid).get("output", "")).begins_with("build:")

static func build_key(rid: String) -> String:
	return String(def(rid).get("output", "")).replace("build:", "")

static func output_item(rid: String) -> String:
	return String(def(rid).get("output", ""))

## autoload「Game」在编译期不可见（解析环），静态函数里按 /root/Game 取节点
static func _g() -> Node:
	var ml := Engine.get_main_loop()
	return ml.root.get_node_or_null("Game") if ml else null

static func can_make(rid: String) -> bool:
	var r := def(rid)
	if r.is_empty():
		return false
	var g_cm: Node = _g()
	if g_cm == null or not bool(g_cm.call("knows_recipe", rid)):
		return false
	for id in r.get("inputs", {}):
		if int(g_cm.call("count_item", String(id))) < int(r.inputs[id]):
			return false
	return true

static func station_ok(rid: String) -> bool:
	var r := def(rid)
	if r.get("station", "") == "fire":
		var g_so: Node = _g()
		return g_so != null and float(g_so.call("near_fire_strength")) > 0.0
	return true
