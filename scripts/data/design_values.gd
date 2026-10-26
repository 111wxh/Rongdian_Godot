class_name DV
## 《融点》全局数值字典（唯一数值源）
## 来源：16 份设计文档 + 融点_全局数值字典v1.0
## 纪律：任何系统需要数值从这里取，禁止在业务脚本里散落硬编码

# =====================================================================
# 一、时间尺度（sheet1/时间尺度与性能预算）
# =====================================================================
const SEC_PER_DAY := 3600.0         ## 1 游戏日 = 3600 现实秒（60 分钟/天，森林之子量级）
##  说明：原文档口径 120s/日，实测"一天瞬间蒸发"（12 游戏分钟/现实秒，
##  暴风雪夜 3.6 秒就失温）。用户拍板 60min/日后，所有 per-game-minute
##  速率已按 0.4 游戏分钟/现实秒重新调校（见 BODY_TEMP_*_RATE 注释）。
##  整局 180 天 ≈ 180 现实小时，为长期档；想改节奏只动这一个常数。
const DAY_HOURS := 24               ## 1 游戏日 = 24 游戏小时
const CHAPTER_DAYS := 15            ## 1 章 = 15 游戏日
const SEASON_DAYS := 45             ## 1 季 = 45 游戏日
const TOTAL_DAYS := 180             ## 12 章 = 4 季 = 完整一局
const TOTAL_CHAPTERS := 12
const TICK_HZ := 10.0               ## 热引擎 T0 层：10Hz（100ms）
const DIFFUSE_EVERY := 5            ## 全场扩散求解每 5×T0 一次（500ms）

# =====================================================================
# 二、视角与操作手感（操作与交互手感规格 v1.0 / sheet3）
# =====================================================================
const FOV_DEFAULT := 75.0
const FOV_MIN := 65.0
const FOV_MAX := 95.0
const HEAD_SWAY_SCALE := 0.5        ## 头部摆动幅度 = 标准值 50%（抗晕动）
const VIEW_LERP := 0.12             ## 视角平滑：0.12s 延迟插值，禁止 1:1 刚性跟随
const PITCH_MIN := -1.047           ## 垂直视角下限 -60°
const PITCH_MAX := 1.222            ## 垂直视角上限 +70°
const SPEED_EMPTY := 5.0            ## 空手基准 m/s
## 碰撞层位（Godot 4 bitmask，全工程统一口径）：
##   1=世界实体（地形/建筑/墙体，挡玩家也进建造射线）
##   2=玩家
##   4=生物/NPC（交互射线可命中，不挡玩家路）
##   8=接触体积（Area：比碰撞体积大一截的感知球——射线打中=瞄准了整物；
##     玩家的接触探针也是 8，与之重叠=人就在物体旁边）
##  16=道具实体（枯树/冰岩/货架：挡玩家，但建造射线穿透它——墙可以贴着树砌）
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_INTERACT := 4
const LAYER_CONTACT := 8
const LAYER_PROP := 16
const SPEED_CARRY_BIG := 2.2        ## 持大件 m/s
const SPEED_FULL := 3.1             ## 满载 m/s
const SPRINT_MULT := 1.45           ## Shift 冲刺倍率（本作 Shift=加速；减速请用 Ctrl/C 下蹲）
const SPRINT_FATIGUE_PER_MIN := 0.03  ## 冲刺额外疲劳累积（/游戏分钟）：跑不动会自己停
const SPRINT_MIN_FATIGUE := 92.0    ## 疲劳超过此值禁止冲刺（喘到腿软）
## 饥渴累积（%/游戏分钟）。按 3600s/日调校：饥饿约 2 游戏日一顿、口渴约 1.5 游戏日一次，
## 保证 60 分钟/天的尺度下每天都有明确的觅食/找水循环（原文档值 0.016/0.022 是
## 为 120s/日定的，在新尺度下 4 天才吃一顿，毫无压力）。
const HUNGER_PER_MIN := 0.035       ## 饥饿累积
const THIRST_PER_MIN := 0.045       ## 口渴累积（水比粮急）
const HUNGER_PER_MIN_SLEEP := 0.022  ## 睡眠中饥饿累积（睡着代谢慢）
const THIRST_PER_MIN_SLEEP := 0.028  ## 睡眠中口渴累积
## 背包网格（视觉/整理层）：列×行格子数 + 大件占位分类。
## 数据层仍是栈式（capacity 不变），网格只决定展示与拖动整理。
const INV_GRID_COLS := 8           ## 网格列数
const INV_GRID_ROWS := 5           ## 网格行数
const INV_FOOTPRINT_BIG := ["tool"]  ## 占 2×2 的大件分类（刀具/长矛等手持物）
const INV_BASE_SLOTS := 6          ## 开局槽位：只有身上几个口袋，逼你做取舍
const INV_BACKPACK_SLOTS := 8      ## 每个背包扩容槽位（搜刮到包才是扩仓正路）
const T_DEMOLISH := 1.5            ## 拆除自家建筑耗时（秒，长按 E）：拆墙比垒墙快半拍
const DEMOLISH_REFUND := 0.5       ## 拆除返还材料比例（每样至少 1）
## 动物 AI（捕食者狼）：感知/攻击/命中/伤害/冷却/脱战。猎物逃逸见 PREY_FLEE_RANGE。
## 玩家常速 5.0 > 狼 3.4：被盯上跑得掉，但落单搜刮会被骚扰——压力来自持续的。
const WOLF_AGGRO_RANGE := 50.0     ## 感知距离（米）：进入即潜行逼近
const WOLF_ATTACK_RANGE := 1.0     ## 攻击距离（米）：中心距进入即撕咬
const WOLF_HIT_DIAMETER := 3.0     ## 命中判定球直径（米，以狼为中心近似口部）
const WOLF_DAMAGE := 8.0           ## 每口伤害
const WOLF_ATTACK_CD := 2.5        ## 撕咬冷却（秒）
const WOLF_LEASH := 70.0           ## 脱战距离（米）：超出回巢游荡
const PREY_FLEE_RANGE := 12.0      ## 猎物逃逸距离（米）
## 区块野生动物（涌现生态）：每个块按哈希掷是否放狼/鹿，兔按个数掷。
## 设计区（苏醒日附近）另有手安的 2/2/2——走远才会遇到野外的群。
const CHUNK_WOLF_CHANCE := 0.18    ## 每块出狼概率（1-2 头）
const CHUNK_DEER_CHANCE := 0.18    ## 每块出鹿概率（1-2 头）
const CHUNK_RABBIT_MAX := 2        ## 每块兔子上限（0-2 只）
const SLOPE_UP := 0.7               ## 上坡速度修正
const SLOPE_DOWN := 1.1             ## 下坡速度修正（制动距离 +1.8m）
const DEEP_SNOW_HEAT := 2.4         ## 深雪区热量消耗倍率（并留足迹）
const LISTEN_HEAT := 1.5            ## 倾听模式(Q)热量流失倍率
const BUILD_TOLERANCE := 0.15       ## 建造容差 ±15cm（无障碍 ±40cm）
const ROTATE_SPEED := 0.785         ## 建筑旋转 45°/s（绕角色自身轴）
const NOVICE_DAYS := 7              ## 新手期：前 7 日交互耗时 ×0.7
const NOVICE_TIME_SCALE := 0.7
const FAMILIAR_TIME_SCALE := 0.6    ## 同类建筑第二次起耗时 ×0.6（永不降至 1 次确认）
const SKILL_TIME_CAP := 0.4         ## 技能缩短交互耗时上限 -40%
const FEEDBACK_VISUAL_MS := 100     ## 视觉反馈预算
const FEEDBACK_AUDIO_MS := 80       ## 听觉反馈预算
const RUMBLE_CAP := 0.4             ## 常规震动强度上限 40%

# =====================================================================
# 三、交互时长硬上限表（sheet4，单位：秒）
# =====================================================================
const T_PICK_SMALL := 1.2           ## 拾取小件
const T_PICK_BIG := 2.0             ## 拾取大件（双手）
const T_FIRE_WITH_TINDER := 3.5     ## 生火（有火种）——不可中断，刻意压在 4s 之下
const T_FIRE_FRICTION := 12.0       ## 生火（无火种，摩擦取火）中断保留 40%
const T_EXTINGUISH := 1.5           ## 熄灭营火
const T_PLACE := 2.8                ## 放置建材
const T_READ_EVIDENCE := 4.0        ## 阅读证据——不可跳过，全作唯一强制停顿
const T_DIARY_NOTE := 6.0           ## 写入日记批注（打字动画）
const T_CARE := 30.0                ## 照护伤员：每 30s 结算一次
const T_LEARN_SKILL := 8.0          ## 学习技能 + 热量消耗动画
const T_SURVEY := 3.0               ## 审视姿态(V)：时间不停止
const FIRE_BASE_CHANCE := 0.85      ## 点火基础成功率
const FIRE_WIND_PENALTY := 0.08     ## 风力每档 -8%
const FIRE_COLD_PENALTY := 0.12     ## 体温过低 -12%
const TORCH_RADIUS := 6.0           ## 火把/提灯光源半径 m
const EMBER_TRACE := 45.0           ## 火光残迹粒子残留 45s（迷路导航）

# =====================================================================
# 四、低温迟滞窗 Cold Lag 四档（sheet5）
## 体温档 | 响应延迟 | 其他影响
## 正常     | 0ms      | 无
## 轻度失温 | 15% 按键延迟 80-150ms | 长按容差 ±0.2s 收紧
## 重度失温 | 连续两次相同输入算一次 | 转身速率 -30%
## 濒死     | 只能行走，无法奔跑与持物 | 交互需队友协助
# =====================================================================
const CORE_TEMP_MILD := 35.0        ## 轻度失温阈值 °C
const CORE_TEMP_SEVERE := 32.0      ## 重度失温阈值 °C
const CORE_TEMP_LETHAL := 28.0      ## 致死阈值 °C
const CORE_TEMP_NORMAL := 37.0      ## 正常核心体温
const LAG_CHANCE := 0.15            ## 轻度：15% 概率触发
const LAG_MIN := 0.08               ## 延迟下限 80ms
const LAG_MAX := 0.15               ## 延迟上限 150ms
const LAG_HOLD_TOLERANCE := 0.2     ## 长按判定容差收紧 ±0.2s
const SEVERE_TURN_MULT := 0.7       ## 重度：转身速率 -30%
## 体温变化速率（°C / 游戏分钟 / 单位冷|暖压）。
## 按 3600s/日（0.4 游戏分钟/现实秒）调校：暴风雪夜无火无衣最惨 ≈0.04℃/现实分
## → 轻度失温 ≈4 分钟、濒死 ≈14 分钟；火边回暖 1.3℃ ≈45 秒。
const BODY_TEMP_COOL_RATE := 0.001     ## 失温速率（净冷压 × 本系数）
const BODY_TEMP_WARM_RATE := 0.012     ## 回暖速率（净暖压 × 本系数）
const BODY_TEMP_OVERHEAT_RATE := 0.005 ## 烤久了过热速率

# =====================================================================
# 五、热力学常量（sheet6 / 热引擎文档）
# =====================================================================
const LATENT_ICE := 334.0           ## 冰融化潜热 kJ/kg
const LATENT_VAPOR := 2260.0        ## 水汽化潜热 kJ/kg
const HEAT_PERSON_REST := 80.0      ## 人体静息产热 W/人
const HEAT_PERSON_LIGHT := 150.0    ## 轻劳动 W/人
const HEAT_PERSON_HEAVY := 300.0    ## 重劳动 W/人
const CH01_TEMP := -30.0            ## 第一章外部基准温度 °C
const CH12_TEMP := 5.0              ## 第十二章外部基准温度 °C
const ENDING_C_TEMP := 20.0         ## 结局C 可达最高外部温度 °C
const BUILD_FREEZE_TEMP := 0.0      ## 建筑冻结阈值（管道冻损）
const DUST_KAPPA_MIN := 0.1         ## 尘云遮蔽系数范围
const DUST_KAPPA_MAX := 1.0

## 主动热源表（热引擎 5.1）
const HEAT_SOURCES := {
	"campfire": {"w": 800.0, "fuel_per_hour": 0.2, "hours_per_bundle": 5.0, "unlock": "初始"},
	"furnace": {"w": 2000.0, "fuel_per_hour": 0.5, "hours_per_unit": 4.0, "unlock": "第2章"},
	"geothermal": {"w": 3000.0, "fuel_per_hour": 0.0, "hours_per_unit": 0.0, "unlock": "第4章"},
}

## 建筑材料热阻表（热引擎 4.4，R 单位 m²·K/W）
const MATERIAL_R := {
	"log": 1.33, "rammed_earth": 0.38, "metal_plate": 0.0001, "glass": 0.01,
	"double_glass": 1.00, "rock_wool": 2.50, "aerogel": 3.33, "ice_brick": 0.14,
	"snow": 0.15, "fabric": 0.04, "rock": 2.50, "metal": 0.0001, "wood": 1.33,
}
## 沙盒材质物性（涌现文档：导热系数 / 比热 / 密度 / 反照率）
const MATERIAL_PHYS := {
	"ice": {"k": 2.14, "cp": 2100.0, "rho": 917.0, "albedo": 0.62},
	"snow_dry": {"k": 0.15, "cp": 2100.0, "rho": 100.0, "albedo": 0.85},
	"snow_wet": {"k": 0.50, "cp": 2600.0, "rho": 450.0, "albedo": 0.55},
	"rock": {"k": 2.50, "cp": 800.0, "rho": 2700.0, "albedo": 0.20},
	"metal": {"k": 50.0, "cp": 490.0, "rho": 7850.0, "albedo": 0.35},
	"wood": {"k": 0.13, "cp": 1700.0, "rho": 600.0, "albedo": 0.25},
	"fabric": {"k": 0.04, "cp": 1300.0, "rho": 200.0, "albedo": 0.45},
	"brine": {"k": 1.90, "cp": 2600.0, "rho": 1200.0, "albedo": 0.30},
}

# =====================================================================
# 六、8 种核心资源热力学定义（8种核心资源与热力学合成树）
## ice 冰 / snow 雪 / water 水 / rock 岩 / metal 金属 / organic 有机物
## salt 盐 / fuel 燃料
# =====================================================================
const RESOURCES := {
	"ice": {"name": "冰", "heat": 0.0, "cp": 2.09, "k": 2.18, "albedo": 0.85,
		"melt": 0.0, "latent": 334.0, "role": "基础资源/冷量载体/建筑基材"},
	"snow": {"name": "雪", "heat": 0.0, "cp": 1.5, "k": 0.15, "albedo": 0.90,
		"melt": 0.0, "latent": 334.0, "role": "基础资源/绝热建材/水源前体"},
	"water": {"name": "水", "heat": 0.0, "cp": 4.18, "k": 0.60, "albedo": 0.06,
		"melt": 0.0, "latent": 334.0, "role": "生命必需品/热缓冲/工业溶剂"},
	"rock": {"name": "岩", "heat": 0.0, "cp": 0.84, "k": 2.50, "albedo": 0.30,
		"melt": 1200.0, "latent": 400.0, "role": "结构材料/金属前体"},
	"metal": {"name": "金属", "heat": 0.0, "cp": 0.45, "k": 50.0, "albedo": 0.60,
		"melt": 1538.0, "latent": 272.0, "role": "高级构件/热管理核心"},
	"organic": {"name": "有机物", "heat": 15000.0, "cp": 1.70, "k": 0.15, "albedo": 0.20,
		"melt": 200.0, "latent": 0.0, "role": "能源载体/食物与工业原料"},
	"salt": {"name": "盐", "heat": 0.0, "cp": 0.88, "k": 6.00, "albedo": 0.80,
		"melt": 801.0, "latent": 519.0, "role": "热工质添加剂/保鲜/化学试剂"},
	"fuel": {"name": "燃料", "heat": 35000.0, "cp": 2.00, "k": 0.12, "albedo": 0.10,
		"melt": 0.0, "latent": 0.0, "role": "高级能源/工业动力源"},
}

## 热力学转化矩阵（部分核心）：输入→输出 / 热量变化 J（正=吸热，负=放热）
const TRANSFORMS := {
	"ice_melt": {"in": {"ice": 100}, "out": {"water": 100}, "heat": 33400.0, "cond": "环境>0℃或接触热源"},
	"water_boil": {"in": {"water": 100}, "out": {}, "heat": 226000.0, "cond": "环境>100℃或强热源"},
	"snow_pack": {"in": {"snow": 200}, "out": {"ice": 100}, "heat": -5000.0, "cond": "压力>50kPa或反复踩踏"},
	"fuel_burn": {"in": {"fuel": 10}, "out": {}, "heat": -350000.0, "cond": "温度>闪点+氧气"},
	"organic_rot": {"in": {"organic": 100}, "out": {}, "heat": -2000.0, "cond": "20-40℃+湿度>60%"},
	"salt_ice": {"in": {"salt": 30, "ice": 100}, "out": {}, "heat": 8000.0, "cond": "接触混合（凝固点降低）"},
	"brine_evaporate": {"in": {"water": 100}, "out": {"salt": 12}, "heat": 226000.0, "cond": "蒸发结晶（卤水析盐）"},
	"ore_smelt": {"in": {"rock": 200}, "out": {"metal": 50}, "heat": 400000.0, "cond": ">1200℃+还原剂"},
	"water_freeze": {"in": {"water": 100}, "out": {"ice": 100}, "heat": -33400.0, "cond": "环境<0℃"},
	"dry_distill": {"in": {"organic": 100}, "out": {"fuel": 30}, "heat": 50000.0, "cond": "200-400℃+缺氧"},
}

# =====================================================================
# 七、灾难泊松节奏模型（灾难泊松节奏模型）
# =====================================================================
## λ 值季节表（基础 λ/游戏日）
const LAMBDA_BY_SEASON := {"winter": 0.15, "early_spring": 0.25, "mid_spring": 0.40, "late_spring": 0.60}
const SEASON_ORDER := ["winter", "early_spring", "mid_spring", "late_spring"]
const DISASTER_MIN_GAP_BASE := 2.0     ## T_min = 2.0 + 0.5 × 过去24h灾难次数（小时）
const INTENSITY_PER_15D := 0.1         ## 每 15 游戏天强度 +10%
const STRESS_MULT := [1.0, 1.2, 1.5]   ## 过去24h 灾难 0/1/2 次的 StressMultiplier

## 六种灾难（CAT-01~06）
const DISASTERS := {
	"meteor": {"name": "陨石撞击", "omen_min": 30.0, "duration_h": 72.0,
		"temp_effect": 50.0, "heat_inject_kj": 5000.0, "albedo_drop": 0.3,
		"res": "岩/金属暴露，冰/雪气化", "ai": "安全+40 归属-20 恐慌",
		"chain": "大气电离闪光→低频轰鸣→局部热浪"},
	"dust": {"name": "尘云事件", "omen_min": 60.0, "duration_h": 72.0,
		"temp_effect": -15.0, "light_drop": 0.8, "fuel_up": 0.3,
		"res": "光照↓80%，燃料消耗+30%", "ai": "意义-30 自主+20 绝望",
		"chain": "天空泛黄→风速骤降→能见度<5格"},
	"blizzard": {"name": "暴风雪", "omen_min": 20.0, "duration_h": 18.0,
		"temp_effect": -40.0, "conv_mult": 3.0, "gather_drop": 0.9,
		"res": "采集效率-90%，冰层加厚", "ai": "保暖+50 健康-10 争夺庇护所",
		"chain": "气压骤降→风向突变→雪花横飞"},
	"thaw": {"name": "暖春异常", "omen_min": 45.0, "duration_h": 36.0,
		"temp_effect": 5.0, "humidity_up": 0.6,
		"res": "冰→水加速，有机物腐烂", "ai": "饱足+20 安全-30 食物腐败",
		"chain": "冰面渗水→异响→局部塌陷"},
	"quake": {"name": "冰震", "omen_min": 15.0, "duration_h": 12.0,
		"temp_effect": 0.0, "conv_mult": 4.0,
		"res": "深层岩/金属暴露，建筑损毁", "ai": "安全+60 信任-20 背叛/离队",
		"chain": "冰层龟裂声→地面微震→裂隙扩展"},
	"microbe": {"name": "远古微生物释放", "omen_min": 90.0, "duration_h": 96.0,
		"temp_effect": 3.0, "metabolic_kj_h": 500.0,
		"res": "有机物污染，水源不可用", "ai": "健康+70 归属-40 隔离/驱逐",
		"chain": "冰层冒泡→异味→皮肤刺痛"},
}

## 复合灾难（4 种）
const COMPOUND_DISASTERS := {
	"microbe_release": {"parts": ["dust", "thaw"], "name": "远古微生物释放", "special": "微生物随水流传播"},
	"thermal_shock": {"parts": ["meteor", "quake"], "name": "热震", "special": "冰层热应力断裂，蒸汽喷泉"},
	"ice_dust_storm": {"parts": ["dust", "blizzard"], "name": "冰封尘暴", "special": "能见度<2格，窒息风险"},
	"melt_plague": {"parts": ["thaw", "microbe"], "name": "融水瘟疫", "special": "水源100%污染"},
}

## 灾难期间 AI 权重偏移（/min）
const DISASTER_AI_SHIFT := {
	"meteor": {"warmth": 10, "satiety": -5, "safety": 40, "autonomy": -10, "belonging": -20, "meaning": -15, "health": 5, "rate": 5},
	"dust": {"warmth": 15, "satiety": -10, "safety": 10, "autonomy": 20, "belonging": -10, "meaning": -30, "health": -5, "rate": 2},
	"blizzard": {"warmth": 50, "satiety": -10, "safety": 20, "autonomy": -5, "belonging": -10, "meaning": -10, "health": -10, "rate": 8},
	"thaw": {"warmth": -10, "satiety": 20, "safety": -30, "autonomy": 5, "belonging": -5, "meaning": -5, "health": 10, "rate": 3},
	"quake": {"warmth": 20, "satiety": -5, "safety": 60, "autonomy": -15, "belonging": -20, "meaning": -20, "health": -10, "rate": 10},
	"microbe": {"warmth": 10, "satiety": -20, "safety": 30, "autonomy": -10, "belonging": -40, "meaning": -20, "health": 70, "rate": 6},
}

# =====================================================================
# 八、建造系统（建造与营地系统 + sheet10）
## 成本：木/石/金/燃；时间秒；初始热量消耗 J；人力
# =====================================================================
const BUILDINGS := {
	"camp_center": {"name": "营地中心", "wood": 50, "stone": 30, "metal": 10, "fuel": 5,
		"time": 120.0, "heat": -500.0, "labor": 3, "heat_out": 200.0, "unlock": "初始"},
	"barracks": {"name": "基础宿舍", "wood": 20, "stone": 10, "metal": 2, "fuel": 0,
		"time": 45.0, "heat": -100.0, "labor": 1, "cap": 4, "unlock": "庇护所"},
	"medical": {"name": "医疗帐篷", "wood": 15, "stone": 5, "metal": 5, "fuel": 2,
		"time": 60.0, "heat": -150.0, "labor": 1, "cap": 2, "unlock": "基础医疗"},
	"warehouse": {"name": "基础仓库", "wood": 25, "stone": 15, "metal": 3, "fuel": 0,
		"time": 50.0, "heat": -80.0, "labor": 1, "cap": 200, "unlock": "仓储"},
	"furnace": {"name": "木柴熔炉", "wood": 30, "stone": 20, "metal": 10, "fuel": 0,
		"time": 90.0, "heat": -200.0, "labor": 2, "heat_out": 150.0, "unlock": "冶炼"},
	"workbench": {"name": "基础工作台", "wood": 15, "stone": 5, "metal": 5, "fuel": 0,
		"time": 30.0, "heat": -50.0, "labor": 1, "unlock": "手工"},
	"brine_pool": {"name": "盐卤池", "wood": 10, "stone": 30, "metal": 15, "fuel": 5,
		"time": 100.0, "heat": -300.0, "labor": 2, "unlock": "盐业"},
	"heat_exchanger": {"name": "热交换器", "wood": 5, "stone": 10, "metal": 25, "fuel": 0,
		"time": 80.0, "heat": -150.0, "labor": 1, "efficiency": 0.7, "unlock": "热力学I"},
	"ice_cellar": {"name": "冰洞仓库", "wood": 0, "stone": 40, "metal": 10, "fuel": 0,
		"time": 120.0, "heat": -400.0, "labor": 2, "cap": 500, "unlock": "极地仓储"},
	"farm": {"name": "基础农场", "wood": 20, "stone": 10, "metal": 5, "fuel": 10,
		"time": 150.0, "heat": -250.0, "labor": 2, "unlock": "农业"},
	"trap": {"name": "狩猎陷阱", "wood": 15, "stone": 5, "metal": 5, "fuel": 0,
		"time": 40.0, "heat": -50.0, "labor": 1, "unlock": "狩猎"},
	"campfire": {"name": "营火", "wood": 10, "stone": 5, "metal": 0, "fuel": 0,
		"time": 20.0, "heat": -20.0, "labor": 1, "heat_out": 80.0, "unlock": "初始"},
	"geothermal": {"name": "地热接口", "wood": 10, "stone": 50, "metal": 30, "fuel": 20,
		"time": 300.0, "heat": -1000.0, "labor": 4, "heat_out": 500.0, "unlock": "深层钻探"},
	"solar": {"name": "太阳能板", "wood": 5, "stone": 5, "metal": 20, "fuel": 0,
		"time": 60.0, "heat": -100.0, "labor": 1, "heat_out": 120.0, "unlock": "光电"},
	"nuclear": {"name": "核电池", "wood": 5, "stone": 20, "metal": 40, "fuel": 0,
		"time": 200.0, "heat": -2000.0, "labor": 3, "heat_out": 300.0, "unlock": "核能"},
	"windmill": {"name": "风力发电机", "wood": 10, "stone": 15, "metal": 25, "fuel": 0,
		"time": 90.0, "heat": -120.0, "labor": 2, "heat_out": 150.0, "unlock": "风能"},
	"wood_wall": {"name": "木围墙", "wood": 10, "stone": 5, "metal": 2, "fuel": 0,
		"time": 15.0, "heat": -2.0, "labor": 1, "r_bonus": 5.0, "unlock": "防御"},
	"watchtower": {"name": "哨塔", "wood": 20, "stone": 15, "metal": 10, "fuel": 5,
		"time": 80.0, "heat": -15.0, "labor": 1, "unlock": "警戒"},
	"research": {"name": "E系证据研究台", "wood": 20, "stone": 20, "metal": 15, "fuel": 10,
		"time": 90.0, "heat": -40.0, "labor": 1, "unlock": "第一章末"},
	"diary_room": {"name": "日记室", "wood": 15, "stone": 10, "metal": 5, "fuel": 5,
		"time": 60.0, "heat": -20.0, "labor": 1, "unlock": "人文"},
	"antenna": {"name": "通讯天线", "wood": 10, "stone": 15, "metal": 30, "fuel": 20,
		"time": 120.0, "heat": -100.0, "labor": 2, "unlock": "通讯"},
	"purifier": {"name": "净水站", "wood": 15, "stone": 25, "metal": 10, "fuel": 10,
		"time": 100.0, "heat": -50.0, "labor": 1, "unlock": "净化"},
	"counseling": {"name": "心理疏导室", "wood": 20, "stone": 10, "metal": 10, "fuel": 10,
		"time": 80.0, "heat": -25.0, "labor": 1, "unlock": "心理学"},
}

## 建筑等级升级（Lv2-5 消耗倍率/效果）
const BUILD_UPGRADE := {
	2: {"cost_mult": 0.5, "r": 0.20, "hp": 0.30},
	3: {"cost_mult": 1.0, "r": 0.40, "auto_thermostat": true},
	4: {"cost_mult": 2.0, "prod": 0.25, "heat": -0.15},
	5: {"cost_mult": 4.0, "r": 0.60, "immune_disaster": true},
}
const BUILD_HP_TICK := 0.1          ## 每 Tick 基础耐久扣除
const BUILD_HP_BLIZZARD := 2.0      ## 暴风雪期间扣除
const BUILD_REPAIR_COST := {"wood": 0.5, "metal": 0.2, "time": 10.0}  ## 每 1 点耐久
const BUILD_CRITICAL_HP := 0.3      ## <30% 濒危

# =====================================================================
# 九、玩家成长（玩家成长与技能树）
# =====================================================================
const ATTRIBUTES := ["physique", "perception", "intelligence", "willpower", "charisma"]
const ATTR_NAMES := {"physique": "体能", "perception": "感知", "intelligence": "智力",
	"willpower": "意志", "charisma": "魅力"}
const ATTR_CAP_BASE := 20.0
const ATTR_CAP_PER_LEVEL := 0.2
const SKILL_POINTS_PER_LEVEL := 2
## 技能升级消耗：1→2级1点，2→3级2点，3→4级3点，4→5级4点（满级共10点）
const SKILL_UPGRADE_COST := [1, 2, 3, 4]
const SKILL_RESET_HEAT := 500.0     ## 重置消耗 500×Skill_Level 热量

## 五分支定位
const SKILL_BRANCHES := {
	"survivalist": {"name": "生存专家", "color": "蓝"},
	"engineer": {"name": "工程技师", "color": "绿"},
	"medic": {"name": "医者", "color": "橙"},
	"diplomat": {"name": "交涉者", "color": "紫"},
	"explorer": {"name": "探索者", "color": "红"},
}

## 技能退化（用进废退）：7 游戏日未使用开始衰减
const SKILL_DEGRADE_DAYS := 7
const SKILL_DEGRADE_UNUSED := 0.3   ## 保留概率 = 0.3×(1-降解系数)
const SKILL_DEGRADE_MASTERED := 0.6 ## 已满节点 = 0.6+0.2×阅读率

# =====================================================================
# 十、疾病系统（疾病动力学）
# =====================================================================
const DISEASES := {
	"frostbite": {"name": "冻伤", "kind": "cold", "incubation_h": 4.0,
		"treat": ["fuel", "organic"], "env": "暴风雪(+)，暖春(-)"},
	"hypothermia": {"name": "失温", "kind": "cold", "incubation_h": 2.5,
		"treat": ["fuel", "water", "rock"], "env": "室外强风(+)，室内聚集(-)"},
	"gangrene": {"name": "冻伤坏疽", "kind": "cold", "incubation_h": 18.0,
		"treat": ["metal", "salt", "organic"], "env": "极寒(+)，高湿度(+)"},
	"wound_infection": {"name": "伤口感染", "kind": "infect", "incubation_h": 9.0,
		"treat": ["salt", "organic", "metal"], "env": "潮湿(+)，干燥寒冷(-)"},
	"respiratory": {"name": "呼吸道感染", "kind": "infect", "incubation_h": 24.0,
		"treat": ["organic", "water", "fuel"], "env": "密闭空间(+)，室外通风(-)"},
	"salt_fever": {"name": "盐卤热病", "kind": "infect", "incubation_h": 36.0,
		"treat": ["water", "organic"], "env": "盐矿区域(+)，淡水充足(-)"},
	"scurvy": {"name": "坏血病", "kind": "nutrition", "incubation_h": 120.0,
		"treat": ["organic"], "env": "春季(+)，冬季(-)"},
	"ketosis": {"name": "饥饿性酮症", "kind": "nutrition", "incubation_h": 180.0,
		"treat": ["organic", "fuel"], "env": "极寒(+)，暖季(-)"},
}
const DISEASE_STAGE_DEBUFF := [1.0, 0.95, 0.85, 0.6]  ## 潜伏/轻度/中度/重度 属性系数
const DISEASE_CONTAGIOUS := [0.0, 1.0, 1.5, 2.0]      ## 各阶段传染性
const DRUG_RESIST_ADD := 0.2        ## 同药连用 3 次耐药 +20%
const DRUG_RESIST_DECAY_DAYS := 7   ## 停用每 7 日耐药 -10%
const IMMUNITY_DAYS := 30           ## 康复临时免疫 30 游戏日

## 季节疾病加成
const SEASON_DISEASE := {
	"deep_winter": {"temp": [-40, -20], "cold": 0.5, "infect": -0.3},
	"melt_spring": {"temp": [-10, 5], "infect": 0.4, "salt_fever": 1.0},
	"warm_summer": {"temp": [5, 15], "nutrition": 0.3, "infect": 0.2},
	"late_autumn": {"temp": [-20, 0], "cold": 0.2, "nutrition": 0.5},
}

# =====================================================================
# 十一、D 系 AI 七权重（D系AI冲突引擎）
# =====================================================================
const AI_WEIGHTS := ["warmth", "satiety", "safety", "autonomy", "belonging", "meaning", "health"]
const AI_WEIGHT_DECAY := 0.5        ## 基础衰减率 0.5/min
const AI_TRUST_LOW := 20.0          ## 信任<20：无视非紧急指令
const AI_TRUST_HIGH := 80.0         ## 信任>80：盲从（自主大幅下降）
const AI_CONFLICT_BASE := {          ## 争执基础强度
	"resource": 40, "order": 60, "risk": 50, "rule": 30, "trust_break": 70,
}
const AI_CONFLICT_STAGES := [       ## 争执升级链条
	{"max": 30, "name": "口角"}, {"max": 60, "name": "推搡"},
	{"max": 85, "name": "暴力"}, {"max": 100, "name": "离队/敌对"},
]

# =====================================================================
# 十二、E 系证据链（E系证据链详细设计）
# =====================================================================
## 三假说
const HYPOTHESES := {
	"h1": {"name": "自然耦合", "claim": "异常热力学是行星系统自然演化的必然结果", "ending": "观察者"},
	"h2": {"name": "干预失控", "claim": "远古文明干预热平衡失败导致冰封", "ending": "修复者"},
	"h3": {"name": "有意封存", "claim": "世界是被有意设计并封存的容器", "ending": "解放者"},
}
## 歧义强度 → 权重系数（5.2）
const AMBIGUITY_W := {1: 0.80, 2: 0.60, 3: 0.40, 4: 0.25, 5: 0.10}
const AMBIGUITY_GRADE := {1: "A确凿", 2: "B可靠", 3: "C参考", 4: "D存疑", 5: "E推测"}
## 降解状态折扣
const DEGRADE_D := {"pristine": 1.0, "degraded": 0.6, "unintelligible": 0.0}
## 吻合度区间 → 描述
const COHERENCE_TEXT := [
	{"min": 0.8, "text": "高度自洽"}, {"min": 0.6, "text": "较为合理"},
	{"min": 0.4, "text": "有一定依据"}, {"min": 0.2, "text": "尚存疑点"},
	{"min": 0.0, "text": "证据不足"},
]
const EVIDENCE_TOTAL := 16          ## E01-E16
const EVIDENCE_POINTS := 12         ## 12 个点，其中 4 个点含 2 条
const COHERENCE_UNLOCK := 0.85      ## 任假说 ≥85 分解锁终局接管选择
const COHERENCE_MAX := 1.0          ## 永远不存在 100 分

## 16 条证据（id: 载体/位置/获取代价/降解/字面读数/三假说倾向/歧义）
const EVIDENCES := {
	"E01": {"name": "冰芯同位素记录#7", "carrier": "冰芯样本", "spot": "深冰层-热异常区",
		"method": "DIG", "cost": "工具Lv2/45s/风险2/热量15",
		"degrade": "受损/T>260K或t>72h",
		"reading": "δ¹⁸O=-34.2‰; 沉积速率:0.04mm/yr; 异常层:深度12m, 温度骤升记录",
		"affinity": {"h1": 0.8, "h2": -0.3, "h3": 0.1}, "ambiguity": 2},
	"E02": {"name": "自动调节器残骸", "carrier": "金属铭牌", "spot": "遗迹核心区",
		"method": "READ", "cost": "工具Lv3/60s/风险4/热量25",
		"degrade": "完好/T>310K或损伤>70%",
		"reading": "UNIT-774: 热平衡干预协议已激活。目标温度:273.15K。当前偏差:+14.8K。干预失败。",
		"affinity": {"h1": -0.7, "h2": 0.9, "h3": -0.2}, "ambiguity": 3},
	"E03": {"name": "岩壁热应力刻痕", "carrier": "岩壁刻痕", "spot": "深层洞穴-热应力带",
		"method": "AUTO", "cost": "无/0s/风险1/热量0",
		"degrade": "不可辨/湿度>85%或t>120h",
		"reading": "[乱码]…封存阵列…第三节点…热寂协议…[乱码]",
		"affinity": {"h1": 0.2, "h2": 0.1, "h3": 0.8}, "ambiguity": 5},
	"E04": {"name": "研究员日记残页", "carrier": "日记残页", "spot": "旧研究营地",
		"method": "READ", "cost": "无/10s/风险1/热量5",
		"degrade": "受损/T>280K或t>48h",
		"reading": "第412天。他们说是自然演化，但冰层下的热源分布太均匀了。这不是地质运动，这是…[墨迹模糊]",
		"affinity": {"h1": -0.5, "h2": 0.6, "h3": 0.4}, "ambiguity": 4},
	"E05": {"name": "骨骼钙化异常报告", "carrier": "骨骼标记", "spot": "废弃生物实验室",
		"method": "DIG", "cost": "工具Lv1/30s/风险3/热量10",
		"degrade": "完好/T>290K或损伤>50%",
		"reading": "样本B-09: 骨密度异常增加300%。体内检测到非自然同位素Tc-99。结论: 人为辐射暴露。",
		"affinity": {"h1": -0.8, "h2": 0.7, "h3": 0.3}, "ambiguity": 2},
	"E06": {"name": "壁画热力学图谱", "carrier": "壁画", "spot": "远古神庙-地下祭坛",
		"method": "READ", "cost": "工具Lv2/90s/风险2/热量20",
		"degrade": "受损/湿度>90%或t>96h",
		"reading": "[图案: 同心圆热源分布] 注释: 封印之环。热量即枷锁。勿使温度低于临界点。",
		"affinity": {"h1": 0.1, "h2": -0.4, "h3": 0.9}, "ambiguity": 4},
	"E07": {"name": "化学残留分析报告", "carrier": "化学残留", "spot": "地下合成实验室",
		"method": "CRAFT", "cost": "合成台Lv2/120s/风险3/热量30",
		"degrade": "不可辨/T>270K或t>24h",
		"reading": "[数据损坏]…反应物: 未知有机催化剂…产物: 稳定化冰晶…[数据损坏]",
		"affinity": {"h1": -0.3, "h2": 0.5, "h3": 0.7}, "ambiguity": 3},
	"E08": {"name": "AI争执记录#44", "carrier": "电子日志", "spot": "AI核心机房",
		"method": "DIALOGUE", "cost": "无/15s/风险2/热量8",
		"degrade": "完好/电磁干扰>50dB或t>168h",
		"reading": "AI-Alpha: 协议要求维持低温。AI-Beta: 低温将导致封存失效。Alpha: 失效是预期结果。Beta: 否定。",
		"affinity": {"h1": -0.6, "h2": 0.4, "h3": 0.8}, "ambiguity": 5},
	"E09": {"name": "地热梯度测绘图", "carrier": "测绘图", "spot": "地质勘探站",
		"method": "READ", "cost": "工具Lv3/90s/风险3/热量20",
		"degrade": "受损/温度>275K或t>60h",
		"reading": "地下热源分布与板块构造应力带重合度97.3%。无异常热源集中点。结论: 自然地质活动。",
		"affinity": {"h1": 0.9, "h2": -0.5, "h3": -0.3}, "ambiguity": 3},
	"E10": {"name": "远古气象站日志", "carrier": "电子日志", "spot": "高山气象站",
		"method": "READ", "cost": "工具Lv2/60s/风险2/热量15",
		"degrade": "受损/T>280K或t>72h",
		"reading": "连续1024天气象记录。温度波动符合米兰科维奇周期。预测误差<5%。系统状态: 正常。",
		"affinity": {"h1": 0.8, "h2": -0.4, "h3": -0.2}, "ambiguity": 3},
	"E11": {"name": "陨石合金碎片", "carrier": "金属碎片", "spot": "陨石撞击坑-中心点",
		"method": "DIG", "cost": "工具Lv2/60s/风险4/热量20",
		"degrade": "完好/物理损伤>60%或t>200h",
		"reading": "合金成分: Ti-6Al-4V + 未知掺杂。制造工艺: 分子级自组装。年代测定: >10000年。",
		"affinity": {"h1": -0.3, "h2": 0.7, "h3": 0.6}, "ambiguity": 4},
	"E12": {"name": "冰下录音", "carrier": "冰壁录音", "spot": "冰川洞穴-冰壁裂缝",
		"method": "DIG", "cost": "工具Lv3/120s/风险3/热量25",
		"degrade": "受损/温度>265K或t>48h",
		"reading": "[音频: 低频震动] 频谱分析显示规律性脉冲。重复频率: 1.000Hz。来源: 冰层深处。",
		"affinity": {"h1": 0.2, "h2": 0.5, "h3": 0.8}, "ambiguity": 4},
	"E13": {"name": "古菌培养皿", "carrier": "培养皿", "spot": "旧医疗站-冷藏柜",
		"method": "DIG", "cost": "工具Lv1/30s/风险2/热量10",
		"degrade": "不可辨/温度>275K或t>24h",
		"reading": "[培养物已死亡] 残留DNA序列含非天然碱基对Z-P。来源: 未知古菌。",
		"affinity": {"h1": -0.2, "h2": 0.5, "h3": 0.7}, "ambiguity": 3},
	"E14": {"name": "石板铭刻", "carrier": "石板", "spot": "地下图书馆-中央石柱",
		"method": "AUTO", "cost": "无/0s/风险1/热量0",
		"degrade": "完好/物理损伤>80%或t>500h",
		"reading": "致后来者: 三条路径。记录者见真相。修复者承重负。解放者赌一切。选择即定义。",
		"affinity": {"h1": 0.3, "h2": 0.3, "h3": 0.3}, "ambiguity": 5},
	"E15": {"name": "电路基板", "carrier": "电路基板", "spot": "地下设施-配电中心",
		"method": "READ", "cost": "工具Lv3/90s/风险4/热量30",
		"degrade": "受损/电磁干扰>30dB或t>120h",
		"reading": "主电源: 地热。备用电源: 同位素电池(剩余12%)。系统状态: 封存协议运行中。倒计时: ---",
		"affinity": {"h1": -0.3, "h2": 0.6, "h3": 0.8}, "ambiguity": 4},
	"E16": {"name": "全息投影残影", "carrier": "全息影像", "spot": "核心控制室-投影台",
		"method": "DIALOGUE", "cost": "无/30s/风险3/热量15",
		"degrade": "受损/电磁干扰>40dB或t>96h",
		"reading": "[全息影像: 远古科学家] …如果你们看到这段记录，说明封存已经…[影像闪烁] …选择权在你们手中。",
		"affinity": {"h1": 0.2, "h2": 0.5, "h3": 0.8}, "ambiguity": 5},
}

# =====================================================================
# 十三、UI/UX（UI_UX交互设计文档）
# =====================================================================
const HUD_FADE_EXPLORE := 5.0       ## 探索模式 HUD 淡出 5s
const HUD_IDLE_HIDE := 30.0         ## 静止 30s 无操作隐藏交互层
const HUD_CRITICAL_HEAT := 0.1      ## 热量 <10% 全 HUD 闪烁
const DIARY_FLOAT := 3.0            ## 日记条目浮现 3s
const S3_SILENCE_USES := 3          ## S3 绝对静默全局仅 3 次
const S3_SILENCE_SEC := 2.5
const UI_COLORS := {                ## UI 颜色规范（HSL 转 RGB 近似）
	"warm_safe": Color(0.95, 0.55, 0.25),
	"warm_warn": Color(0.95, 0.35, 0.15),
	"cold_danger": Color(0.25, 0.5, 0.85),
	"cold_neutral": Color(0.6, 0.7, 0.78),
	"story": Color(0.6, 0.4, 0.85),
	"rare": Color(0.95, 0.8, 0.3),
}

# =====================================================================
# 十四、动态出生点（日记继承与团队系统）
# =====================================================================
const SPAWN_DISTANCE := [           ## D_spawn = min(1.0+0.8×(N-1), 5.0) km
	{"n": 1, "min": 1.0, "max": 1.5}, {"n": 2, "min": 1.8, "max": 2.5},
	{"n": 3, "min": 2.6, "max": 3.5}, {"n": 4, "min": 3.5, "max": 5.0},
]
const CORPSE_PROTECT_MIN := 10.0    ## 尸体 10 分钟不可被环境破坏
const DESPAIR_THRESHOLD_MIN := 40.0 ## 寻尸 40 分钟未果触发记忆闪回兜底
