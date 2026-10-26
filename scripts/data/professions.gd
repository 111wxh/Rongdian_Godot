class_name Professions
extends RefCounted
## 职业：影响随身工具与常识倾向（不改变核心规则）

const LIST := {
	"medic": {
		"name": "医护",
		"tools": ["bandage", "bandage", "disinfectant", "multitool"],
		"desc": "你懂伤口要压、要清洁，懂失温不能拿火猛烤。处置比常人稳。",
		"perk": "医疗处置更有效：绷带回复更多，同伴伤势好得快。",
	},
	"electrician": {
		"name": "电工",
		"tools": ["screwdriver", "wrench", "flashlight", "battery"],
		"desc": "线路、开关、旧世界的电，你一看就懂。",
		"perk": "面对融点终端时，你比别人多懂三分。",
	},
	"teacher": {
		"name": "教师",
		"tools": ["multitool", "matches", "matches"],
		"desc": "你习惯把复杂的事讲简单。同伴愿意听你的。",
		"perk": "同伴状态恢复更快，讲述时更能让人安心。",
	},
	"driver": {
		"name": "司机",
		"tools": ["wrench", "flashlight", "multitool", "matches"],
		"desc": "你跑过很长的夜路，认得风雪前的天。",
		"perk": "走路更省劲，负重时步伐更稳。",
	},
	"cook": {
		"name": "厨子",
		"tools": ["knife", "matches", "matches"],
		"desc": "你能把一点吃的变出花样来。",
		"perk": "烹饪回复更多，同伴吃得更好。",
	},
}

static func ids() -> Array:
	var out := LIST.keys()
	out.sort()
	return out

static func def(pid: String) -> Dictionary:
	return LIST.get(pid, {})

static func name_of(pid: String) -> String:
	return def(pid).get("name", pid)

static func tools_of(pid: String) -> Array:
	return def(pid).get("tools", [])
