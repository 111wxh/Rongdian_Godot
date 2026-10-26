extends Node
class_name ThermalEngine
## 热引擎：T0 层 10Hz tick 结算营地核心温度
## 核心方程：dT/dt = (ΣQ_in - ΣQ_out) / C_total（热引擎文档第二章）
## 分层策略（热引擎 1.4）：核心热区 10Hz / 建筑外壳 5Hz / 外部环境 1Hz——
##   原型期外部环境用解析曲线（章节温度基准 + 天气扰动）近似，保证性能可预测。

const HEAT_LOSS_AREA := 21.8   ## 有效散热面积 m²（由文档数值示例反解：55K/4R×A=300W → A≈21.8）

## 建筑类型 → 主材（用于查 DV.MATERIAL_R 计算真实热阻）
## 文档热引擎 4.4：热阻 R 单位 m²·K/W，材质越隔温 R 越大（wood 1.33 / rock 2.50 / metal 0.0001…）
const TYPE_MATERIAL := {
	"camp_center": "rock", "barracks": "wood", "medical": "wood", "warehouse": "wood",
	"furnace": "metal", "workbench": "wood", "brine_pool": "stone", "heat_exchanger": "metal",
	"ice_cellar": "stone", "farm": "wood", "trap": "wood", "campfire": "metal",
	"geothermal": "rock", "solar": "metal", "nuclear": "metal", "windmill": "metal",
	"wood_wall": "wood", "watchtower": "wood", "research": "wood", "diary_room": "wood",
	"antenna": "metal", "purifier": "stone", "counseling": "wood", "stone_fire": "stone",
	"stone_wall": "stone", "snow_wall": "snow", "wood_roof": "wood", "wood_door": "wood",
	"bed": "wood", "storage": "wood",
}

var _tick_interval: float = 1.0 / DV.TICK_HZ
var _tick_acc := 0.0

func _physics_process(delta: float) -> void:
	if not Game.started or Game.game_over:
		return
	_tick_acc += delta
	while _tick_acc >= _tick_interval:
		_tick_acc -= _tick_interval
		_tick()

## 营地总热阻 R（m²·K/W）：所有建筑主材 R 求和 + 升级热阻加成 + 保温技能
func _shelter_r() -> float:
	if not Game.has_home:
		return 0.5
	var r := 0.0
	for b in Game.buildings:
		var mat: String = TYPE_MATERIAL.get(String(b.get("type", "")), "wood")
		r += float(DV.MATERIAL_R.get(mat, 1.33))
		var lv: int = int(b.get("level", 1))
		if lv > 1:
			r += float(DV.BUILD_UPGRADE.get(lv, {}).get("r", 0.0))
	# 保温建筑学 / 皮毛加工：技能额外热阻
	r += Game.skill_mod("insul") * 0.1
	return maxf(0.1, r)

func _tick() -> void:
	_update_season()
	# ---------- ΣQ_in：主动热源 → 被动热源 → 生物热源 ----------
	var qin := 0.0
	# 主动热源：玩家建造/控制的设备（熔炉/地热/太阳能/风电/核电池）
	for b in Game.buildings:
		var d: Dictionary = DV.BUILDINGS.get(String(b.get("type", "")), {})
		var w: float = float(d.get("heat_out", 0.0))
		if w > 0.0:
			var lv: int = int(b.get("level", 1))
			# 升级提升热产出（BUILD_UPGRADE[lv].prod，仅 Lv4 有 +25%）
			w *= 1.0 + float(DV.BUILD_UPGRADE.get(lv, {}).get("prod", 0.0))
			qin += w
	# 营火（火堆强度驱动：800W × fire_strength；篝火大师 fire_range 扩半径 → 折算产出）
	if Game.fire_strength > 0.05:
		qin += DV.HEAT_SOURCES.campfire.w * clampf(Game.fire_strength, 0.0, 1.0) \
			* (1.0 + Game.skill_mod("fire_range") * 0.05)
	# 熔炉产热强化（熔炉升级 furnace_q_in）
	qin *= (1.0 + Game.skill_mod("furnace_q_in") / 100.0)
	# 生物热源：玩家（静止静息 / 移动轻劳动）+ 同伴（在营地范围内才计入营地热平衡）
	if Game.player and Game.has_home \
			and Game.player.global_position.distance_to(Game.home_center) < 30.0:
		var moving := Game.player.velocity.length() > 0.5
		qin += DV.HEAT_PERSON_LIGHT if moving else DV.HEAT_PERSON_REST
		qin += DV.HEAT_PERSON_REST * Game.companions.size()
	Game.q_in = qin
	# ---------- ΣQ_out：传导 + 对流 ----------
	var r_total: float = _shelter_r()
	var dt_k: float = Game.camp_temp - _env_temp()
	var qout: float = absf(dt_k) * HEAT_LOSS_AREA / r_total
	qout *= 1.0 + Game.wind * 0.25            # 对流：风速放大热损
	if Game.player and Game.player.listening:
		qout *= DV.LISTEN_HEAT                  # 倾听模式：听得越久，暴露越多
	# 热交换器优化（exchanger 降 q_out 系数）与 q_out_coef（负 → 减损）
	qout *= maxf(0.3, 1.0 + Game.skill_mod("q_out_coef")) * (1.0 - Game.skill_mod("exchanger") * 0.1)
	Game.q_out = qout
	# ---------- dT/dt 积分 ----------
	var c_total: float = maxf(1000.0, Game.c_total + Game.buildings.size() * 500.0)
	Game.c_total = c_total
	var dtdt: float = (qin - qout) / c_total
	Game.camp_temp += dtdt * _tick_interval
	# ---------- 热量盈亏三档（驱动 UI 霜纹/火光/呼吸/音频频谱） ----------
	var net: float = qin - qout
	if net > 100.0:
		Game.heat_surplus = "rich"
	elif net > -100.0:
		Game.heat_surplus = "tight"
	else:
		Game.heat_surplus = "deficit"
	# ---------- 玩家核心体温（Cold Lag 判据） ----------
	_apply_core_temp(_tick_interval)

## 外部环境温度：章节基准曲线（CH01 -30℃ → CH12 +5℃）+ 天气扰动
func _env_temp() -> float:
	var base: float = lerpf(DV.CH01_TEMP, DV.CH12_TEMP,
		clampf((Game.day - 1) / float(DV.TOTAL_DAYS), 0.0, 1.0))
	match Game.weather:
		"blizzard": base -= 10.0
		"snow": base -= 3.0
	# 在家且室内：环境按营地温度计
	if Game.has_home and Game.indoors:
		return Game.camp_temp
	return base

func _apply_core_temp(dt: float) -> void:
	var target: float = _env_temp()
	if Game.heat_surplus == "rich":
		target = maxf(target, 15.0)
	elif Game.heat_surplus == "deficit":
		target = minf(target, 25.0)
	else:
		target = 30.0 if Game.has_home else 22.0
	# 每秒约 2% 指数趋近：37→35℃ 约 10 现实秒（≈20 游戏分钟）
	Game.core_temp += (target - Game.core_temp) * 0.002 * dt * 10.0
	Game.core_temp = clampf(Game.core_temp, DV.CORE_TEMP_LETHAL, DV.CORE_TEMP_NORMAL + 0.5)
	# 濒死线：核心体温 ≤28℃ 开始掉血（survival 的死亡判定接管）
	if Game.core_temp <= DV.CORE_TEMP_LETHAL + 0.01:
		Game.health = maxf(0.0, Game.health - 5.0 * dt * 10.0)

## 季节推进（DV.SEASON_DAYS 天/季，λ 随阶段上升）
func _update_season() -> void:
	var idx: int = 0
	if DV.SEASON_DAYS > 0:
		idx = clampi(int(floor(float(Game.day - 1) / float(DV.SEASON_DAYS))), 0, DV.SEASON_ORDER.size() - 1)
	Game.season = DV.SEASON_ORDER[idx]
	Game.disaster_lambda = DV.LAMBDA_BY_SEASON.get(Game.season, 0.15)
