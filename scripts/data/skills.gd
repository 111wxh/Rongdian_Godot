class_name Skills
## 玩家成长与技能树（玩家成长与技能树设计文档）
## 5 基础属性 + 5 分支 75 技能 + 用进废退退化
## 技能即选择：非对称网状；技能有代价（点/热量/时间）；用进废退

## ---------- 基础属性 ----------
const ATTRS := ["physique", "perception", "intelligence", "willpower", "charisma"]
const ATTR_NAMES := {"physique": "体能", "perception": "感知", "intelligence": "智力",
	"willpower": "意志", "charisma": "魅力"}

## ---------- 技能库 ----------
## 字段：lv 等级要求 / cost [点, 热量, 小时] / prev 前置 / bind 绑定 / mods 结构化效果
const SKILLS := {
	"survivalist": [
		{"id": "cold_adapt", "name": "耐寒适应", "lv": 1, "cost": [1, 50, 1], "prev": "", "bind": "",
			"desc": "基础耐寒+5，暴风雪热损耗-10%", "mods": {"cold_resist": 5, "blizzard_loss": -0.10}},
		{"id": "fire_master", "name": "篝火大师", "lv": 3, "cost": [2, 120, 3], "prev": "cold_adapt", "bind": "篝火",
			"desc": "篝火热辐射范围+2m，燃料消耗-15%", "mods": {"fire_range": 2.0, "fuel_burn": -0.15}},
		{"id": "igloo", "name": "冰屋建造", "lv": 5, "cost": [3, 200, 6], "prev": "cold_adapt", "bind": "冰屋",
			"desc": "解锁冰屋蓝图，隔热系数+0.3", "mods": {"insul": 0.3, "unlock": "igloo"}},
		{"id": "snow_stove", "name": "雪灶烹饪", "lv": 7, "cost": [3, 180, 4], "prev": "fire_master", "bind": "雪灶",
			"desc": "烹饪热耗-20%，食物中毒率-10%", "mods": {"cook_heat": -0.20, "poison": -0.10}},
		{"id": "fur_work", "name": "皮毛加工", "lv": 9, "cost": [4, 250, 8], "prev": "igloo", "bind": "工作台",
			"desc": "衣物保暖值+15%，制作时间-30%", "mods": {"insul": 0.15, "craft_time": -0.30}},
		{"id": "ice_fishing", "name": "冰钓精通", "lv": 11, "cost": [4, 300, 10], "prev": "snow_stove", "bind": "冰洞",
			"desc": "冰洞捕鱼效率+40%，稀有鱼概率+5%", "mods": {"fish_rate": 0.40, "rare_fish": 0.05}},
		{"id": "sled", "name": "雪橇制作", "lv": 13, "cost": [5, 350, 12], "prev": "fur_work", "bind": "工作台",
			"desc": "负重上限+20kg，移动热耗-10%", "mods": {"carry": 20.0, "move_heat": -0.10}},
		{"id": "greenhouse", "name": "暖房种植", "lv": 15, "cost": [5, 400, 15], "prev": "igloo", "bind": "暖房",
			"desc": "解锁暖房，作物生长周期-20%", "mods": {"grow": -0.20, "unlock": "greenhouse"}},
		{"id": "geothermal", "name": "地热利用", "lv": 18, "cost": [6, 500, 20], "prev": "greenhouse", "bind": "地热井",
			"desc": "解锁地热井，恒定 Q_in=50W", "mods": {"q_in": 50.0, "unlock": "geothermal_well"}},
		{"id": "brine_refine", "name": "盐卤提炼", "lv": 20, "cost": [6, 450, 18], "prev": "snow_stove", "bind": "盐卤池",
			"desc": "盐产量+30%，提炼热耗-25%", "mods": {"salt_rate": 0.30, "refine_heat": -0.25}},
		{"id": "insulation", "name": "保温建筑学", "lv": 22, "cost": [7, 600, 24], "prev": "geothermal", "bind": "全局",
			"desc": "所有建筑隔热系数+0.15", "mods": {"insul": 0.15}},
		{"id": "extreme_weather", "name": "极端天气适应", "lv": 25, "cost": [7, 700, 30], "prev": "insulation", "bind": "",
			"desc": "极寒/暴风雪创伤概率-50%", "mods": {"disaster_trauma": -0.50}},
		{"id": "field_aid", "name": "野外急救", "lv": 28, "cost": [8, 550, 20], "prev": "extreme_weather", "bind": "急救包",
			"desc": "野外治疗效率+30%，感染率-10%", "mods": {"aid": 0.30, "infection": -0.10}},
		{"id": "heat_recycle", "name": "热量回收", "lv": 30, "cost": [8, 800, 36], "prev": "insulation", "bind": "",
			"desc": "角色运动产生 Q_in=10/h", "mods": {"q_in": 10.0}},
		{"id": "campfire_social", "name": "篝火社交", "lv": 32, "cost": [9, 650, 24], "prev": "fire_master", "bind": "篝火",
			"desc": "篝火旁 AI 士气恢复+20/h", "mods": {"morale": 20.0}},
	],
	"engineer": [
		{"id": "basic_build", "name": "基础建造", "lv": 1, "cost": [1, 60, 2], "prev": "", "bind": "",
			"desc": "建造速度+10%，材料消耗-5%", "mods": {"build_speed": 0.10, "build_cost": -0.05}},
		{"id": "mech_repair", "name": "机械维修", "lv": 3, "cost": [2, 130, 4], "prev": "basic_build", "bind": "工作台",
			"desc": "设备故障率-15%，维修时间-20%", "mods": {"break_rate": -0.15, "repair_time": -0.20}},
		{"id": "heat_pipe", "name": "热管道铺设", "lv": 5, "cost": [3, 220, 7], "prev": "basic_build", "bind": "热管道",
			"desc": "热传输损耗-20%，解锁管道网络", "mods": {"pipe_loss": -0.20, "unlock": "heat_pipe"}},
		{"id": "circuit", "name": "电路系统", "lv": 7, "cost": [3, 190, 5], "prev": "mech_repair", "bind": "配电箱",
			"desc": "解锁电力设备，电路过载保护", "mods": {"unlock": "power"}},
		{"id": "solar_maint", "name": "太阳能板维护", "lv": 9, "cost": [4, 260, 9], "prev": "circuit", "bind": "太阳能板",
			"desc": "太阳能效率+15%，夜间损耗-10%", "mods": {"solar": 0.15, "night_loss": -0.10}},
		{"id": "exchanger_opt", "name": "热交换器优化", "lv": 11, "cost": [4, 320, 11], "prev": "heat_pipe", "bind": "热交换器",
			"desc": "热交换效率+25%，Q_out系数-0.2", "mods": {"exchanger": 0.25, "q_out_coef": -0.2}},
		{"id": "furnace_up", "name": "熔炉升级", "lv": 13, "cost": [5, 380, 14], "prev": "exchanger_opt", "bind": "熔炉",
			"desc": "熔炉Q_in+30，燃料转化率+20%", "mods": {"furnace_q_in": 30.0, "fuel_rate": 0.20}},
		{"id": "ice_cellar_build", "name": "冰洞仓库建造", "lv": 15, "cost": [5, 420, 16], "prev": "furnace_up", "bind": "冰洞仓库",
			"desc": "仓库容量+50%，保鲜时间+40%", "mods": {"storage": 0.50, "fresh": 0.40}},
		{"id": "brine_build", "name": "盐卤池建造", "lv": 18, "cost": [6, 520, 22], "prev": "ice_cellar_build", "bind": "盐卤池",
			"desc": "解锁盐卤池蓝图，产出+20%", "mods": {"brine_out": 0.20, "unlock": "brine_pool"}},
		{"id": "automation", "name": "自动化代理", "lv": 20, "cost": [6, 480, 20], "prev": "brine_build", "bind": "自动采集器",
			"desc": "解锁自动采集器，AI工作需求-10", "mods": {"unlock": "auto_miner", "ai_labor": -10.0}},
		{"id": "structure", "name": "结构加固", "lv": 22, "cost": [7, 620, 26], "prev": "automation", "bind": "全局",
			"desc": "建筑耐久+30%，灾难损伤-20%", "mods": {"hp": 0.30, "disaster_dmg": -0.20}},
		{"id": "trap_making", "name": "陷阱制作", "lv": 25, "cost": [7, 720, 32], "prev": "structure", "bind": "陷阱",
			"desc": "解锁狩猎/防御陷阱，触发率+15%", "mods": {"trap_rate": 0.15, "unlock": "trap"}},
		{"id": "scavenging", "name": "废土拾荒", "lv": 28, "cost": [8, 580, 22], "prev": "structure", "bind": "",
			"desc": "搜刮稀有部件概率+20%", "mods": {"rare_loot": 0.20}},
		{"id": "tool_craft", "name": "工具合成", "lv": 30, "cost": [8, 820, 38], "prev": "scavenging", "bind": "工作台",
			"desc": "高级工具合成解锁，耐久+25%", "mods": {"tool_hp": 0.25, "unlock": "adv_tools"}},
		{"id": "battery_charge", "name": "热电池充电", "lv": 32, "cost": [9, 680, 26], "prev": "tool_craft", "bind": "热电池",
			"desc": "热电池储能+40%，充放效率+15%", "mods": {"battery": 0.40, "charge": 0.15}},
	],
	"medic": [
		{"id": "basic_diag", "name": "初级诊断", "lv": 1, "cost": [1, 55, 1], "prev": "", "bind": "医疗站",
			"desc": "诊断准确率+10%，诊断时间-15%", "mods": {"diag": 0.10, "diag_time": -0.15}},
		{"id": "quarantine", "name": "疾病隔离", "lv": 3, "cost": [2, 125, 3], "prev": "basic_diag", "bind": "隔离室",
			"desc": "隔离区效率+20%，传播率-15%", "mods": {"quarantine": 0.20, "spread": -0.15}},
		{"id": "herb_gather", "name": "草药采集", "lv": 5, "cost": [3, 210, 6], "prev": "basic_diag", "bind": "",
			"desc": "草药产量+25%，辨识错误率-10%", "mods": {"herb": 0.25, "herb_err": -0.10}},
		{"id": "suture", "name": "伤口缝合", "lv": 7, "cost": [3, 185, 4], "prev": "quarantine", "bind": "医疗站",
			"desc": "外伤愈合速度+30%，感染率-20%", "mods": {"heal": 0.30, "infection": -0.20}},
		{"id": "counseling", "name": "心理疏导", "lv": 9, "cost": [4, 255, 8], "prev": "suture", "bind": "",
			"desc": "AI创伤恢复+25%，士气消耗-10", "mods": {"trauma_recover": 0.25, "morale_cost": -10.0}},
		{"id": "vaccine", "name": "疫苗研发", "lv": 11, "cost": [4, 310, 10], "prev": "counseling", "bind": "实验室",
			"desc": "解锁疫苗配方，群体免疫+15%", "mods": {"immunity": 0.15, "unlock": "vaccine"}},
		{"id": "resistance", "name": "耐药性研究", "lv": 13, "cost": [5, 370, 13], "prev": "vaccine", "bind": "实验室",
			"desc": "耐药性增长-20%，药物效力+15%", "mods": {"resist_grow": -0.20, "drug_power": 0.15}},
		{"id": "surgery", "name": "手术操作", "lv": 15, "cost": [5, 410, 15], "prev": "resistance", "bind": "手术室",
			"desc": "手术成功率+25%，术后恢复-30%", "mods": {"surgery": 0.25, "post_op": -0.30}},
		{"id": "nutrition", "name": "营养配餐", "lv": 18, "cost": [6, 510, 20], "prev": "surgery", "bind": "厨房",
			"desc": "营养不良率-30%，体力恢复+15%", "mods": {"malnutrition": -0.30, "stamina": 0.15}},
		{"id": "epidemic", "name": "传染病防控", "lv": 20, "cost": [6, 470, 18], "prev": "nutrition", "bind": "全局",
			"desc": "疫情爆发概率-25%，检测速度+20%", "mods": {"outbreak": -0.25, "detect": 0.20}},
		{"id": "toxicology", "name": "毒物辨识", "lv": 22, "cost": [7, 610, 24], "prev": "epidemic", "bind": "",
			"desc": "毒物识别率+30%，解毒效率+20%", "mods": {"poison_id": 0.30, "antidote": 0.20}},
		{"id": "anesthesia", "name": "麻醉术", "lv": 25, "cost": [7, 710, 30], "prev": "toxicology", "bind": "手术室",
			"desc": "手术痛苦-40%，AI恐慌-20%", "mods": {"pain": -0.40, "panic": -0.20}},
		{"id": "bonesetting", "name": "接骨术", "lv": 28, "cost": [8, 570, 22], "prev": "anesthesia", "bind": "医疗站",
			"desc": "骨折愈合+35%，后遗症-25%", "mods": {"fracture": 0.35, "sequela": -0.25}},
		{"id": "hygiene", "name": "卫生管理", "lv": 30, "cost": [8, 810, 36], "prev": "bonesetting", "bind": "全局",
			"desc": "营地卫生值+30，疾病基础率-10%", "mods": {"hygiene": 30.0, "disease_base": -0.10}},
		{"id": "hospice", "name": "临终关怀", "lv": 32, "cost": [9, 670, 24], "prev": "hygiene", "bind": "",
			"desc": "死亡AI创伤-30%，幸存者内疚-20%", "mods": {"death_trauma": -0.30, "guilt": -0.20}},
	],
	"diplomat": [
		{"id": "mobilize", "name": "团队动员", "lv": 1, "cost": [1, 50, 1], "prev": "", "bind": "",
			"desc": "AI工作意愿+10%，动员CD-15%", "mods": {"willingness": 10.0, "mobilize_cd": -0.15}},
		{"id": "conflict_mediate", "name": "AI冲突调解", "lv": 3, "cost": [2, 120, 3], "prev": "mobilize", "bind": "",
			"desc": "争执解决率+20%，暴力概率-15%", "mods": {"mediate": 0.20, "violence": -0.15}},
		{"id": "negotiate", "name": "谈判交易", "lv": 5, "cost": [3, 200, 6], "prev": "mobilize", "bind": "",
			"desc": "交易价格优惠+10%，成功率+15%", "mods": {"trade_price": -0.10, "trade_rate": 0.15}},
		{"id": "lie_detect", "name": "谎言辨识", "lv": 7, "cost": [3, 180, 4], "prev": "conflict_mediate", "bind": "",
			"desc": "识破谎言率+25%，情报准确度+10%", "mods": {"lie_detect": 0.25, "intel_acc": 0.10}},
		{"id": "leadership", "name": "领导力训练", "lv": 9, "cost": [4, 250, 8], "prev": "negotiate", "bind": "",
			"desc": "AI服从阈值+15，违令率-20%", "mods": {"obedience": 15.0, "disobey": -0.20}},
		{"id": "morale_boost", "name": "士气鼓舞", "lv": 11, "cost": [4, 300, 10], "prev": "leadership", "bind": "",
			"desc": "士气恢复+20/h，低落持续-25%", "mods": {"morale_recover": 20.0, "low_morale": -0.25}},
		{"id": "discipline", "name": "纪律管理", "lv": 13, "cost": [5, 350, 12], "prev": "morale_boost", "bind": "",
			"desc": "偷懒/逃跑概率-25，惩罚效果+15%", "mods": {"slack": -25.0, "punish": 0.15}},
		{"id": "etiquette", "name": "外交礼仪", "lv": 15, "cost": [5, 400, 15], "prev": "discipline", "bind": "",
			"desc": "新幸存者加入率+20%，初始忠诚+10", "mods": {"join_rate": 0.20, "init_loyalty": 10.0}},
		{"id": "intel", "name": "情报收集", "lv": 18, "cost": [6, 500, 20], "prev": "etiquette", "bind": "",
			"desc": "情报获取速度+30%，假情报率-15%", "mods": {"intel_speed": 0.30, "fake_intel": -0.15}},
		{"id": "interrogation", "name": "审讯技巧", "lv": 20, "cost": [6, 450, 18], "prev": "intel", "bind": "",
			"desc": "审讯成功率+25%，创伤风险-10%", "mods": {"interrogate": 0.25, "interro_trauma": -0.10}},
		{"id": "team_cook", "name": "团队烹饪", "lv": 22, "cost": [7, 600, 24], "prev": "discipline", "bind": "厨房",
			"desc": "烹饪时AI社交需求+15/h", "mods": {"social": 15.0}},
		{"id": "entertainment", "name": "娱乐活动", "lv": 25, "cost": [7, 700, 30], "prev": "team_cook", "bind": "娱乐室",
			"desc": "娱乐效果+30%，AI快乐值+20", "mods": {"fun": 0.30, "happiness": 20.0}},
		{"id": "ritual", "name": "仪式主持", "lv": 28, "cost": [8, 550, 20], "prev": "entertainment", "bind": "",
			"desc": "葬礼/庆典创伤-30%，凝聚力+15%", "mods": {"ritual_trauma": -0.30, "cohesion": 0.15}},
		{"id": "conflict_predict", "name": "矛盾预判", "lv": 30, "cost": [8, 800, 36], "prev": "ritual", "bind": "",
			"desc": "冲突预警提前2h，干预成功率+20%", "mods": {"conflict_warn": 2.0, "intervene": 0.20}},
		{"id": "sacrifice", "name": "牺牲决策", "lv": 32, "cost": [9, 650, 24], "prev": "conflict_predict", "bind": "",
			"desc": "处决/放逐AI士气惩罚-40%", "mods": {"exile_penalty": -0.40}},
	],
	"explorer": [
		{"id": "sneak", "name": "潜行", "lv": 1, "cost": [1, 60, 2], "prev": "", "bind": "",
			"desc": "被发现概率-15%，移动噪音-20%", "mods": {"detect": -0.15, "noise": -0.20}},
		{"id": "melee", "name": "近战格斗", "lv": 3, "cost": [2, 130, 4], "prev": "sneak", "bind": "",
			"desc": "近战伤害+15%，格挡率+10%", "mods": {"melee_dmg": 0.15, "block": 0.10}},
		{"id": "ranged", "name": "远程射击", "lv": 5, "cost": [3, 220, 7], "prev": "melee", "bind": "",
			"desc": "命中率+15%，弹药消耗-10%", "mods": {"accuracy": 0.15, "ammo": -0.10}},
		{"id": "trap_disarm", "name": "陷阱拆除", "lv": 7, "cost": [3, 190, 5], "prev": "ranged", "bind": "",
			"desc": "拆陷阱成功率+25%，受伤概率-20%", "mods": {"disarm": 0.25, "disarm_hurt": -0.20}},
		{"id": "terrain_read", "name": "地形阅读", "lv": 9, "cost": [4, 260, 9], "prev": "trap_disarm", "bind": "",
			"desc": "移动速度+10%，迷路概率-30%", "mods": {"move_speed": 0.10, "lost": -0.30}},
		{"id": "weather_read", "name": "气象预判", "lv": 11, "cost": [4, 320, 11], "prev": "terrain_read", "bind": "",
			"desc": "天气预警提前1h，灾害准备+15%", "mods": {"weather_warn": 1.0, "prepare": 0.15}},
		{"id": "tracking", "name": "追踪狩猎", "lv": 13, "cost": [5, 380, 14], "prev": "weather_read", "bind": "",
			"desc": "猎物发现率+20%，追踪距离+30%", "mods": {"prey_find": 0.20, "track_range": 0.30}},
		{"id": "bleed_control", "name": "急救止血", "lv": 15, "cost": [5, 420, 16], "prev": "tracking", "bind": "急救包",
			"desc": "战斗急救效率+30%，失血-25%", "mods": {"combat_aid": 0.30, "bleed": -0.25}},
		{"id": "driving", "name": "车辆驾驶", "lv": 18, "cost": [6, 480, 20], "prev": "bleed_control", "bind": "载具",
			"desc": "解锁雪地车驾驶，油耗-15%", "mods": {"unlock": "snowmobile", "fuel_use": -0.15}},
		{"id": "long_march", "name": "长途跋涉", "lv": 20, "cost": [6, 450, 18], "prev": "driving", "bind": "",
			"desc": "长途移动热耗-20%，耐力+15%", "mods": {"march_heat": -0.20, "stamina": 0.15}},
		{"id": "ice_travel", "name": "冰面行进", "lv": 22, "cost": [7, 600, 24], "prev": "long_march", "bind": "",
			"desc": "薄冰区通过率+40%，落水风险-30%", "mods": {"thin_ice": 0.40, "fall_risk": -0.30}},
		{"id": "meteorology_deep", "name": "陨石学", "lv": 25, "cost": [7, 700, 30], "prev": "ice_travel", "bind": "",
			"desc": "陨石雨前兆提前15min，坑区辐射伤害-25%", "mods": {"meteor_warn": 15.0, "radiation": -0.25}},
		{"id": "ruin_expert", "name": "遗迹专家", "lv": 28, "cost": [8, 550, 20], "prev": "meteorology_deep", "bind": "",
			"desc": "遗迹搜刮产量+25%，隐藏隔间发现率+20%", "mods": {"ruin_loot": 0.25, "hidden_room": 0.20}},
		{"id": "disaster_instinct", "name": "灾难直觉", "lv": 30, "cost": [8, 800, 36], "prev": "ruin_expert", "bind": "",
			"desc": "一级前兆感知范围×2，假阳性识别+30%", "mods": {"omen_range": 2.0, "false_alarm": 0.30}},
		{"id": "ancient_echo", "name": "远古回响", "lv": 32, "cost": [9, 700, 30], "prev": "disaster_instinct", "bind": "远古终端",
			"desc": "解锁远古终端深层档案，证据吻合度判定精度+25%，歧义降解识别+20%", "mods": {"evidence_read": 0.25, "ambiguity_id": 0.20}},
	],
}

## ---------- 查询接口 ----------

static func all() -> Dictionary:
	return SKILLS

static func branch_skills(branch: String) -> Array:
	return SKILLS.get(branch, [])

static func def(skill_id: String) -> Dictionary:
	for branch in SKILLS:
		for s in SKILLS[branch]:
			if String(s.get("id", "")) == skill_id:
				return s
	return {}

static func name_of(skill_id: String) -> String:
	return String(def(skill_id).get("name", skill_id))

static func branch_of(skill_id: String) -> String:
	for branch in SKILLS:
		for s in SKILLS[branch]:
			if String(s.get("id", "")) == skill_id:
				return branch
	return ""

static func total_count() -> int:
	var n := 0
	for branch in SKILLS:
		n += SKILLS[branch].size()
	return n

static func upgrade_cost(level: int) -> int:
	## 1→2级1点，2→3级2点，3→4级3点，4→5级4点（满级共10点）
	## 数值统一来自 DV.SKILL_UPGRADE_COST，避免散落硬编码
	if level < 1 or level > 4:
		return 999
	return int(DV.SKILL_UPGRADE_COST[level - 1])
