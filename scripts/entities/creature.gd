extends CharacterBody3D
class_name Creature
## 冰原野生动物。设计口径：无血条、无战斗升级——捕猎是一次了结的博弈。
## 捕食者（狼）：感知 50m → 潜行逼近 → 8m 内突袭 → 1m 撕咬（命中判定直径 3m 球），
##   脱战 70m 回巢；玩家跑速快过狼，被盯上跑得掉，但落单搜刮会被骚扰。
## 猎物（鹿/兔）：12m 内逃逸，其余时间游荡觅食。

var species := "wolf"
var home := Vector3.ZERO
var target := Vector3.ZERO
var speed := 3.0
var flee_t := 0.0
var repick_t := 0.0
var dead := false
## AI 状态（捕食者）：wander 游荡 / stalk 潜行 / charge 突袭 / attack 撕咬 / recover 收势
var ai_state := "wander"
var attack_cd := 0.0
var recover_t := 0.0
var _lunge_t := 0.0   ## 扑咬视觉：前冲小爆冲

const SPECIES := {
	"wolf":   {"name": "冰原狼", "speed": 3.4, "color": Color(0.35, 0.37, 0.42), "scale": 1.0,
		"predator": true, "damage": 8.0,
		"loot": [{"id": "frozen_meat", "min": 1, "max": 3, "chance": 1.0}, {"id": "fur", "min": 1, "max": 2, "chance": 0.8}]},
	"deer":   {"name": "雪鹿", "speed": 3.8, "color": Color(0.5, 0.4, 0.32), "scale": 1.15,
		"loot": [{"id": "frozen_meat", "min": 2, "max": 4, "chance": 1.0}, {"id": "fur", "min": 1, "max": 2, "chance": 0.9}]},
	"rabbit": {"name": "雪兔", "speed": 3.0, "color": Color(0.85, 0.87, 0.9), "scale": 0.4,
		"loot": [{"id": "frozen_meat", "min": 1, "max": 1, "chance": 1.0}, {"id": "fur", "min": 1, "max": 1, "chance": 0.5}]},
}

func setup(sp: String, pos: Vector3) -> void:
	species = sp
	position = pos
	home = pos
	collision_layer = 4
	collision_mask = 1
	add_to_group("creatures")
	# 碰撞体：没有形状时 move_and_slide 撞不到地面，动物会沉到地下去；
	# 同时交互射线也命中不了，捕猎提示无从出现
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.75, 1.0, 1.5)
	cs.shape = bs
	cs.position = Vector3(0, 0.55, 0)
	add_child(cs)
	var s: Dictionary = SPECIES.get(sp, SPECIES.wolf)
	speed = float(s.get("speed", 3.0))
	var col: Color = s.get("color", Color(0.5, 0.5, 0.5))
	var sc: float = float(s.get("scale", 1.0))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.85
	# 身体
	var body_mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.5, 1.15)
	body_mi.mesh = bm
	body_mi.material_override = mat
	body_mi.position = Vector3(0, 0.62, 0)
	add_child(body_mi)
	# 头
	var head_mi := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.36, 0.36, 0.5)
	head_mi.mesh = hm
	head_mi.material_override = mat
	head_mi.position = Vector3(0, 0.78, 0.72)
	add_child(head_mi)
	# 腿
	for lx in [-0.2, 0.2]:
		for lz in [0.42, -0.42]:
			var leg := MeshInstance3D.new()
			var lm := CylinderMesh.new()
			lm.top_radius = 0.07
			lm.bottom_radius = 0.06
			lm.height = 0.42
			leg.mesh = lm
			leg.material_override = mat
			leg.position = Vector3(lx, 0.21, lz)
			add_child(leg)
	if sp == "wolf":
		var tail := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.14, 0.14, 0.5)
		tail.mesh = tm
		tail.material_override = mat
		tail.position = Vector3(0, 0.75, -0.72)
		add_child(tail)
	if sp == "deer":
		for sx in [-0.18, 0.18]:
			var ant := MeshInstance3D.new()
			var am := CylinderMesh.new()
			am.top_radius = 0.02
			am.bottom_radius = 0.05
			am.height = 0.5
			ant.mesh = am
			ant.material_override = mat
			ant.position = Vector3(sx, 1.05, 0.66)
			ant.rotation.x = -0.35
			add_child(ant)
	scale = Vector3.ONE * sc
	target = pos + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
	# 接触体积：瞄准整个身体即可捕猎，走近也出提示（不用再瞄某个点）
	ContactVolume.attach(self, 1.4)

func species_name() -> String:
	return String(SPECIES.get(species, {}).get("name", "野兽"))

## autoload「Game」在编译期不可见（game.gd 依赖本类所在解析链），
## 运行时按 /root/Game 取节点。
func _g() -> Node:
	var ml := Engine.get_main_loop()
	return ml.root.get_node_or_null("Game") if ml else null

func get_prompt(_player) -> String:
	var g_gp: Node = _g()
	if String(g_gp.get("active_tool")) == "spear":
		return "捕猎 %s [左键]" % species_name()
	return "%s（需要一柄长矛）" % species_name()

func interact(player) -> void:
	try_harvest(player)

func _physics_process(delta: float) -> void:
	if dead:
		return
	var g_cr: Node = _g()
	var player: Node3D = g_cr.get("player")
	var valid_player := is_instance_valid(player) and not bool(g_cr.get("game_over"))
	var s: Dictionary = SPECIES.get(species, SPECIES.wolf)
	var predator: bool = bool(s.get("predator", false))
	if _lunge_t > 0.0:
		_lunge_t -= delta
	if predator:
		_update_predator(delta, valid_player, player, s)
	else:
		_update_prey(delta, valid_player, player)
	# 同类分离：CharacterBody3D 之间默认不互撞，狼群会叠成一件——
	# AI 级分离力补上（穿模修复），不影响与世界的碰撞
	if not dead:
		var sep := Vector3.ZERO
		for other in get_tree().get_nodes_in_group("creatures"):
			if other == self or not is_instance_valid(other):
				continue
			var dd := global_position.distance_to(other.global_position)
			if dd < 1.3 and dd > 0.001:
				sep += (global_position - other.global_position).normalized() * (1.3 - dd)
		velocity.x += sep.x * 8.0 * delta
		velocity.z += sep.z * 8.0 * delta
	velocity.y -= 18.0 * delta
	move_and_slide()
	# 朝向
	if Vector2(velocity.x, velocity.z).length() > 0.2:
		rotation.y = lerpf(rotation.y, atan2(velocity.x, velocity.z), 0.15)

## 捕食者（狼）状态机：游荡 → 感知 50m 潜行 → 8m 突袭 → 1m 撕咬 → 收势后撤
func _update_predator(delta: float, valid_player: bool, player: Node3D, s: Dictionary) -> void:
	var d := 1e9
	if valid_player:
		d = global_position.distance_to(player.global_position)
	match ai_state:
		"wander":
			if valid_player and d < DV.WOLF_AGGRO_RANGE:
				ai_state = "stalk"
				return
			_wander(delta)
		"stalk":
			if not valid_player or d > DV.WOLF_LEASH:
				ai_state = "wander"
				return
			if d < 8.0:
				ai_state = "charge"
				return
			if d < DV.WOLF_AGGRO_RANGE:
				_seek(player.global_position, speed)
			else:
				_wander(delta)
		"charge":
			if not valid_player or d > DV.WOLF_LEASH:
				ai_state = "wander"
				return
			if d <= DV.WOLF_ATTACK_RANGE:
				ai_state = "attack"
				_do_attack(player, s)
				return
			if d > 12.0:
				ai_state = "stalk"
				return
			_seek(player.global_position, speed * 1.55)
		"attack":
			# 撕咬判定瞬间完成，这里做前扑（0.25s 爆冲）与收势
			attack_cd -= delta
			if _lunge_t > 0.0 and valid_player:
				var ldir := (player.global_position - global_position).normalized()
				velocity.x = ldir.x * speed * 2.2
				velocity.z = ldir.z * speed * 2.2
			else:
				velocity.x = 0.0
				velocity.z = 0.0
			if attack_cd <= 0.0:
				ai_state = "recover"
				recover_t = 0.9
		"recover":
			recover_t -= delta
			if valid_player:
				var away := (global_position - player.global_position).normalized()
				velocity.x = away.x * speed * 0.7
				velocity.z = away.z * speed * 0.7
			if recover_t <= 0.0:
				ai_state = "stalk" if valid_player else "wander"

## 撕咬：命中判定为直径 3m 的球（以狼为中心近似口部），冷却 DV.WOLF_ATTACK_CD
func _do_attack(player: Node3D, s: Dictionary) -> void:
	var g_da: Node = _g()
	attack_cd = DV.WOLF_ATTACK_CD
	_lunge_t = 0.25
	var d := global_position.distance_to(player.global_position)
	if d <= DV.WOLF_HIT_DIAMETER * 0.5:
		if player.has_method("hurt"):
			player.hurt(float(s.get("damage", 8.0)), "狼群")
		var sound_da: Node = g_da.get("sound")
		if is_instance_valid(sound_da) and sound_da.has_method("play_demolish"):
			sound_da.play_demolish()
	else:
		# 咬空了（玩家擦着边缘躲开）
		g_da.call("notify", "狼扑了个空。", "info")

## 猎物（鹿/兔）：12m 内逃逸，否则游荡
func _update_prey(delta: float, valid_player: bool, player: Node3D) -> void:
	if valid_player:
		var d := global_position.distance_to(player.global_position)
		if d < DV.PREY_FLEE_RANGE:
			if flee_t <= 0.0:
				flee_t = 2.2
	if flee_t > 0.0:
		flee_t -= delta
		if is_instance_valid(player):
			var away := (global_position - player.global_position).normalized()
			velocity.x = away.x * speed * 1.8
			velocity.z = away.z * speed * 1.8
	else:
		_wander(delta)

## 游荡：在家附近随机取点，走到或超时重取
func _wander(delta: float) -> void:
	repick_t -= delta
	if repick_t <= 0.0 or global_position.distance_to(target) < 1.5:
		repick_t = randf_range(3.0, 7.0)
		target = home + Vector3(randf_range(-22, 22), 0, randf_range(-22, 22))
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var dir := (target - global_position).normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed

## 走向某个点（追击用）
func _seek(to: Vector3, spd: float) -> void:
	var dir := (to - global_position).normalized()
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd

func try_harvest(player) -> void:
	var g_th: Node = _g()
	if dead:
		return
	var d := global_position.distance_to(player.global_position)
	if d > 3.6:
		flee_t = 2.5
		g_th.call("notify", "%s 警觉地跑开了。" % species_name(), "info")
		return
	dead = true
	g_th.call("learn_recipe", "spear")
	var s: Dictionary = SPECIES.get(species, {})
	var got: Array = []
	for l in s.get("loot", []):
		if randf() < float(l.get("chance", 1.0)):
			var n := randi_range(int(l.get("min", 1)), int(l.get("max", 1)))
			g_th.call("add_item", String(l.get("id", "")), n)
			got.append("%s×%d" % [Items.name_of(String(l.get("id", ""))), n])
	g_th.call("notify", "一次了结。收获：" + ("、".join(got) if not got.is_empty() else "什么也没剩下"), "good")
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.5)
	tw.tween_callback(queue_free)
