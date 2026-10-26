class_name Survivors
extends RefCounted
## 幸存者档案：以物证先行登场，找到冰封的人，带回火边解冻，再谈加入
## skill: builder(建造省料) / medic(医护) / scout(侦察) / electrician(终端) / teacher(讲述) / cook(烹饪)
## join_need: 加入条件（物资 / 庇护所等级 / 线索）

const LIST := {
	"linwan": {
		"name": "林晚", "profession": "教师", "skill": "teacher",
		"join_shelter": 1,
		"need": {"item": "old_photo", "count": 1},
		"need_text": "她反复念着一张照片：等春天。找到那张照片，她才能安心留下。",
		"hello": "我讲了十二年课，最怕安静。你来了，挺好。",
		"joined": "我留下。往后这地方，也算我一份。",
		"spawn": Vector3(18, 0, -46), "district": 1,
	},
	"su yi": {
		"name": "苏一", "profession": "医护", "skill": "medic",
		"join_shelter": 1,
		"need": {"item": "bandage", "count": 1},
		"need_text": "她的腿上有旧伤，冻了太久。一份基础敷料，她才能跟上你的脚步。",
		"hello": "别晃我……我的腿没坏，就是麻。你是活的？活的就好。",
		"joined": "处理伤口我比你在行。我加入，但别叫我拼命。",
		"spawn": Vector3(-95, 0, 150), "district": 2,
	},
	"laozhao": {
		"name": "老赵", "profession": "电工", "skill": "electrician",
		"join_shelter": 2,
		"need": {"item": "radio_part", "count": 1},
		"need_text": "他的宝贝收音机缺个零件。修好它，他说能听见「远方」的信号。",
		"hello": "线路我熟。人……我得再看看。",
		"joined": "那些 terminal，我看一眼就知道通没通电。算我一个。",
		"spawn": Vector3(120, 0, 210), "district": 2,
	},
	"hanmu": {
		"name": "韩木", "profession": "司机", "skill": "builder",
		"join_shelter": 1,
		"need": {"item": "scrap", "count": 3},
		"need_text": "他说手头的家伙都锈死了。三块金属碎片，他能敲打出像样的工具。",
		"hello": "我会修车，也会修房子。你这儿……看着像回事。",
		"joined": "搭房子叫我，省料，结实。",
		"spawn": Vector3(-160, 0, 260), "district": 2,
	},
	"aying": {
		"name": "阿萤", "profession": "学生", "skill": "scout",
		"join_shelter": 2,
		"need": {"item": "toy_bear", "count": 1},
		"need_text": "她怀里空空如也，总说「熊熊不见了」。找到那只掉眼的旧玩偶。",
		"hello": "我跑得快！我……我就是有点怕黑。",
		"joined": "我认识近处的路！遗迹在哪边，问我！",
		"spawn": Vector3(60, 0, 430), "district": 3,
	},
	"zhenggong": {
		"name": "郑工", "profession": "工程师", "skill": "electrician",
		"join_shelter": 3,
		"need": {"item": "clue_06", "count": 1},
		"need_text": "他要确认你手里有「节点图」——他守了一辈子的东西。",
		"hello": "融点计划……你还知道这个名词。拿来，我看看你走对路了没有。",
		"joined": "终端要三个人同时送电。人凑不齐，火点不着。我留下，等他们到齐。",
		"spawn": Vector3(-40, 0, 520), "district": 3,
	},
}

static func def(sid: String) -> Dictionary:
	return LIST.get(sid, {})

static func name_of(sid: String) -> String:
	return def(sid).get("name", sid)

static func ids() -> Array:
	var out := LIST.keys()
	out.sort()
	return out
