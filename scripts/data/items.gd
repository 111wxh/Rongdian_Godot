class_name Items
extends RefCounted
## 物品数据库。cat: tool / food / drink / medical / material / clothing / special

const DB := {
	# ---- 工具 ----
	"knife":        {"name": "小刀",       "cat": "tool",    "desc": "削木、开箱、分割冻肉。便利店货架底下的收获。"},
	"scissors":     {"name": "剪子",       "cat": "tool",    "desc": "剪绳、剪布、处理材料。"},
	"multitool":    {"name": "多功能刀",   "cat": "tool",    "desc": "前世随身。刀、钳、锯、螺丝刀凑在一处。"},
	"wrench":       {"name": "扳手",       "cat": "tool",    "desc": "拧螺丝、拆零件。"},
	"screwdriver":  {"name": "螺丝刀",     "cat": "tool",    "desc": "细小处的活计靠它。"},
	"lighter":      {"name": "打火机",     "cat": "tool",    "desc": "有它，火就稳了。还能用很多次。"},
	"matches":      {"name": "火柴",       "cat": "tool",    "desc": "一根是一根的火种。省着用。"},
	"flashlight":   {"name": "手电",       "cat": "tool",    "desc": "照亮眼前三五步。按 F 开关。"},
	"battery":      {"name": "充电宝",     "cat": "tool",    "desc": "给手电续命，也能当个小小的暖手宝。"},
	"spear":        {"name": "长矛",       "cat": "tool",    "desc": "捕猎用的。握紧，靠近，一次了结。"},
	# ---- 医疗 ----
	"bandage":      {"name": "基础敷料",   "cat": "medical", "desc": "压住伤口，止住血。"},
	"disinfectant": {"name": "消毒片",     "cat": "medical", "desc": "清水化开，清洁伤口。"},
	# ---- 材料 ----
	"wood":         {"name": "木材",       "cat": "material","desc": "搭、烧、做框架。"},
	"stone":        {"name": "石块",       "cat": "material","desc": "垫、垒、挡风。"},
	"brick":        {"name": "砖块",       "cat": "material","desc": "垫高、垒墙，比石头齐整。"},
	"snow_brick":   {"name": "冰雪砖",     "cat": "material","desc": "临时垒墙挡风，天暖会化。"},
	"rope":         {"name": "绳索",       "cat": "material","desc": "捆扎、固定。"},
	"cloth":        {"name": "布条",       "cat": "material","desc": "从旧衣物上撕下来的。"},
	"fur":          {"name": "皮毛",       "cat": "material","desc": "还带着一点余温。做衣裳最好。"},
	"ice_block":    {"name": "冰块",       "cat": "material","desc": "化开就是水。"},
	"scrap":        {"name": "金属碎片",   "cat": "material","desc": "旧世界的骨头。磨尖了能用。"},
	# ---- 8 种核心资源（热力学合成树节点，属性见 DV.RESOURCES）----
	"ice":          {"name": "冰",         "cat": "core",    "desc": "固态水。冷量载体，比热 2.09，导热 2.18——化开要吃掉 334J/g 的热。", "heat": 0.0},
	"snow":         {"name": "雪",         "cat": "core",    "desc": "冰晶与空气。天然绝热层（导热仅 0.15），也是水源前体。", "heat": 0.0},
	"water":        {"name": "水",         "cat": "core",    "desc": "液态水。比热 4.18，系统里最有效的温度稳定剂。", "heat": 0.0},
	"rock":         {"name": "岩石",       "cat": "core",    "desc": "硅酸盐。热质量骨架，比热 0.84，导热 2.50。", "heat": 0.0},
	"metal":        {"name": "金属",       "cat": "core",    "desc": "金属键晶体。导热 50——热量的捷径，也是热桥的来源。", "heat": 0.0},
	"organic":      {"name": "有机物",     "cat": "core",    "desc": "碳基化合物。热值 15000J/g，主要的化学热源与生命基质。", "heat": 15000.0},
	"salt":         {"name": "盐",         "cat": "core",    "desc": "离子晶体。降低冰点创造卤水，也是消毒剂与防腐剂。", "heat": 0.0},
	"fuel":         {"name": "燃料",       "cat": "core",    "desc": "高能量密度碳氢化合物。热值 35000J/g——集中释放的热源。", "heat": 35000.0},
	# ---- 衣物 ----
	"fur_coat":     {"name": "皮袄",       "cat": "clothing","desc": "密实的皮毛最挡风。", "insul": 6.0},
	"cloth_coat":   {"name": "布衣",       "cat": "clothing","desc": "一层布也是一层暖。", "insul": 3.0},
	# ---- 食物饮水 ----
	"canned":       {"name": "罐头",       "cat": "food",    "desc": "旧世界的遗存。热一下更好。", "food": 45.0},
	"frozen_meat":  {"name": "冻肉",       "cat": "food",    "desc": "硬得像石头。烤过再吃。", "food": 20.0},
	"cooked_meat":  {"name": "烤肉",       "cat": "food",    "desc": "外焦里化开，香。", "food": 55.0},
	"bottle_water": {"name": "半冻饮料",   "cat": "drink",   "desc": "冰柜底剩下的。化一化再喝。", "drink": 35.0},
	"clean_water":  {"name": "饮用水",     "cat": "drink",   "desc": "化开的雪水，烧过或者干净冰化的一样能喝。", "drink": 40.0},
	# ---- 特殊 ----
	"backpack":     {"name": "背包",       "cat": "special", "desc": "让你能多拿十份东西。"},
	"old_photo":    {"name": "旧照片",     "cat": "special", "desc": "照片上是一对母女，背后写着：等春天。"},
	"toy_bear":     {"name": "旧玩偶",     "cat": "special", "desc": "掉了一只眼睛的熊。被谁攥了很久。"},
	"radio_part":   {"name": "收音机零件", "cat": "special", "desc": "还能拧上去的旋钮与线圈。"},
	"medical_kit":  {"name": "医疗包",     "cat": "special", "desc": "旧世界诊所剩下的完整一套。"},
	# ---- 图纸 ----
	"bp_stone_fire": {"name": "图纸：石圈火塘", "cat": "special", "desc": "照着搭，火更稳、更省柴。"},
	"bp_fur_coat":  {"name": "图纸：皮袄",   "cat": "special", "desc": "三张皮毛两张绳，缝一件挡风的衣裳。"},
}

# 线索物品
const CLUE_PREFIX := "clue_"
const BLUEPRINTS := {
	"bp_stone_fire": "stone_circle_fire",
	"bp_fur_coat": "fur_coat",
}

static func def(id: String) -> Dictionary:
	if id.begins_with(CLUE_PREFIX):
		var e := StoryLogs.entry(id)
		return {"name": e.title, "cat": "special", "desc": e.text}
	return DB.get(id, {"name": id, "cat": "special", "desc": "……"})

static func name_of(id: String) -> String:
	return def(id).get("name", id)

static func cat_of(id: String) -> String:
	return def(id).get("cat", "special")

static func desc_of(id: String) -> String:
	return def(id).get("desc", "")

## 核心资源热力学属性（cp/k/albedo/melt/latent/heat），取自 DV.RESOURCES。
## 8 种核心资源构成热力学合成树节点，其真实相变物性从这里取，避免散落硬编码。
static func thermo_of(id: String) -> Dictionary:
	return DV.RESOURCES.get(id, {})

static func insul_of(id: String) -> float:
	return float(DB.get(id, {}).get("insul", 0.0))

static func is_clothing(id: String) -> bool:
	return DB.get(id, {}).get("cat", "") == "clothing"

static func is_blueprint(id: String) -> bool:
	return BLUEPRINTS.has(id)

static func blueprint_recipe(id: String) -> String:
	return BLUEPRINTS.get(id, "")

static func all_ids() -> Array:
	var out := DB.keys()
	out.sort()
	return out
