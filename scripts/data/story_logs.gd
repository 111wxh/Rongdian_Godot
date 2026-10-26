class_name StoryLogs
extends RefCounted
## 剧情线索：散落的旧世界记录，拼出"当年为什么冰冻"与"如何解"

const LOGS := {
	"clue_01": {
		"title": "冻住的清晨",
		"district": 1,
		"text": "值班日志，最后一页只写了一半：「凌晨四点，天白了。不是天亮的那种白。所有窗户外面都是白的。温度计爆了表……」",
	},
	"clue_02": {
		"title": "轨道上的镜子",
		"district": 1,
		"text": "一份被翻烂的科普传单：「白昼计划——在轨道部署反射镜阵，把阳光折进永夜区，为永夜城供暖。」传单背面有人用红笔画了一个巨大的叉。",
	},
	"clue_03": {
		"title": "碎裂的月亮",
		"district": 2,
		"text": "天文台遗册：「今晚起，月亮缺了一块。不，是碎了一块。陨石雨将持续数百年——不，数万年。地表将如月球般坑洼。」",
	},
	"clue_04": {
		"title": "陆续解封的人",
		"district": 2,
		"text": "一本旅行者的手记，字迹越往后越抖：「冰在退。有人在冰里醒来，像睡了一个太长太长的觉。别怕，慢慢呼吸，你会想起来自己是谁。」",
	},
	"clue_05": {
		"title": "融点计划",
		"district": 2,
		"text": "工程纲要封面：「融点计划——在地脉节点建立聚热终端，由点及面，把冰原一片片烤化。第一批终端共三座，代号：融点。」",
	},
	"clue_06": {
		"title": "终端节点图",
		"district": 3,
		"text": "一张手绘地图，三处红点。批注：「第一融点在旧地铁站，第二在湖畔塔，第三在冰下的城——还没点亮过。」",
	},
	"clue_07": {
		"title": "失败的一次",
		"district": 3,
		"text": "事故记录：「首次点燃失败。能量倒灌进冰层，冻得更厚，三座终端封了两座。活着的人封死了入口。」",
	},
	"clue_08": {
		"title": "守灯人",
		"district": 3,
		"text": "刻在断墙上的一行字，很深：「我把坐标留给下一个醒来的活人。火不是一个人能传远的。——守灯人」",
	},
	"clue_09": {
		"title": "冰下的城",
		"district": 3,
		"text": "无人机航拍说明：「冰盖以下三百米，旧城区完好。若终端网络重启，冰自会退。」",
	},
	"clue_10": {
		"title": "最后一课",
		"district": 3,
		"text": "教室黑板残留的粉笔字，被冰膜盖住：「今天讲热的传递——传导、对流、辐射。记住：热要一起传，才灭不掉。」",
	},
	"clue_11": {
		"title": "同伴名单",
		"district": 3,
		"text": "一张花名册，很多名字被冰花盖住。还能认出几个：「……苏一，医护；老赵，电工；韩木，修理；阿萤，跑得快；林晚，会讲课……」",
	},
	"clue_12": {
		"title": "未命名的信",
		"district": 3,
		"text": "没有收件人的信：「如果你读到这里，说明冰还没赢。别一个人扛，也别把火守小了。把它传出去。」",
	},
}

static func entry(id: String) -> Dictionary:
	return LOGS.get(id, {"title": "残页", "district": 0, "text": "字迹已经糊了。"})

static func ids_of_district(d: int) -> Array:
	var out := []
	for id in LOGS:
		if int(LOGS[id].get("district", 0)) == d:
			out.append(id)
	out.sort()
	return out

static func count_total() -> int:
	return LOGS.size()
