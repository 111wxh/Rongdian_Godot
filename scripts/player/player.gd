extends CharacterBody3D
class_name Player
## 第一人称控制器：WASD 移动 / 鼠标视角 / 交互 / 捕猎 / 火把 / 建造入口
## 手感口径：《操作与交互手感规格 v1.0》——重、冷、慢
##   重：双手占用、负重影响转身速率
##   冷：低温迟滞窗（Cold Lag）在输入层实现，非动画层
##   慢：一切有意义的动作都耗时且可被打断

const MOUSE_SENS := 0.0022
const INTERACT_RANGE := 3.4
const GRAVITY := 18.0
const ACCEL := 12.0
const AIR_ACCEL := 2.5
const JUMP_VELOCITY := 5.0
const EYE_STAND := 1.62  # 站立眼高（Head 节点所在高度）
const EYE_CROUCH := 1.05  # 全蹲眼高
const WALK_MULT := 0.55   ## 静步倍率（倾听/端详时放轻脚步；Shift 冲刺倍率见 DV.SPRINT_MULT）
const LISTEN_SPEED_MULT := 0.6  ## 倾听模式移速降低
const ACTION_LIST := ["flashlight", "quick_drink", "quick_eat", "quick_med",
	"cycle_tool", "interact", "use", "drop", "listen", "survey", "rotate_build"]

var cam: Camera3D
var head: Node3D
var ray: RayCast3D
var _contact_probe: Area3D = null   ## 邻近探针：与物体接触体积(layer 8)重叠=人就在旁边
var flashlight: SpotLight3D
var hold: Node3D
var survival: Survival
var builder: Builder

var control_enabled := true
## 开始页面主菜单是否打开（main.gd 分流时置位）：为真时视角输入与
## 鼠标自愈捕获全部让位，标题界面保持鼠标可见可选。
static var title_open := false   ## 主菜单显示中：屏蔽玩家输入并让鼠标保持可见（main.gd 写入）
var carrying: Node = null
var interact_target: Node3D = null
var viewmodel: ViewModel = null
var flashlight_on := false
var gather_cd := 0.0
var _gather_t := 0.0      ## 长按采集进度（秒）：森林之子式按住累积
var _gather_total := 0.0  ## 当前采集所需秒数（0=未在采集）
var _swing_cd := 0.0      ## 采集挥动节奏计时
var _survey_t := 0.0       ## 审视（V）计时器
var bob_t := 0.0
var shake_amount := 0.0
var shiver_amount := 0.0  ## 失温/疲劳手抖幅度（0=不抖）：由相机FX计算，视图模型的手来抖
var sprinting := false    ## 本帧是否在冲刺（Shift）：供生存系统结算额外疲劳
var crouching := false
var crouch_amt := 0.0  # 0=站立 1=全蹲（平滑过渡用）
var listening := false  ## 倾听模式（Q）
var _prompt_text := ""
var _hunt_lock := 0.0
var _hurt_flash := 0.0
## 卡死自救：记录最近一次"躯干未嵌入实体"的安全位置；持续嵌入超过阈值就退回该点
var _safe_pos := Vector3.ZERO
var _has_safe := false
var _stuck_t := 0.0
# 视角平滑：0.12s 延迟插值，禁止 1:1 刚性跟随（手感规格硬上限）
var _view_yaw := 0.0
var _view_pitch := 0.0
# 低温迟滞窗（Cold Lag）
var _last_action := ""
var _last_action_ms := -99999

func _ready() -> void:
	add_to_group("player")
	head = get_node_or_null("Head") as Node3D
	cam = head.get_node("Camera3D") as Camera3D if head else null
	ray = cam.get_node("InteractRay") as RayCast3D if cam else null
	flashlight = cam.get_node("Flashlight") as SpotLight3D if cam else null
	hold = cam.get_node("HoldPoint") as Node3D if cam else null
	survival = get_node_or_null("Survival") as Survival
	builder = get_node_or_null("Builder") as Builder
	if ray:
		ray.target_position = Vector3(0, 0, -INTERACT_RANGE)
		ray.collide_with_areas = true                      # 射线要能打中接触体积(Area)
		ray.collision_mask = 1 | 4 | DV.LAYER_CONTACT     # 地形 | 旧交互体本体 | 接触体积
		# 碰撞体积(layer 4/16)挡玩家：让玩家不能穿模走过道具/生物/家具
		collision_mask = 1 | 4 | DV.LAYER_PROP
		# 接触探针：玩家身上的小感知球。与物体接触体积(layer 8)重叠即视为"人就站在旁边"，
		# 走近即出交互提示（不用非得瞄中）——体积接触的核心。
		_contact_probe = Area3D.new()
		_contact_probe.name = "ContactProbe"
		_contact_probe.collision_layer = DV.LAYER_PLAYER   # 2：不进射线 mask，不会被射线打到
		_contact_probe.collision_mask = DV.LAYER_CONTACT   # 8：只探测接触体积
		_contact_probe.monitorable = false                 # 不被别的物体探测
		var pcs := CollisionShape3D.new()
		var pss := SphereShape3D.new()
		pss.radius = 1.2
		pcs.shape = pss
		_contact_probe.add_child(pcs)
		add_child(_contact_probe)
	if flashlight:
		flashlight.visible = false
	# 第一人称手部视图模型（持物/空手）
	viewmodel = ViewModel.new()
	viewmodel.name = "ViewModel"
	viewmodel.setup(self)
	add_child(viewmodel)
	# 视角平滑目标初始化为当前朝向
	_view_yaw = rotation.y
	_view_pitch = head.rotation.x if head else 0.0

func _exit_tree() -> void:
	# 场景重载（读档/重开）时把全局引用置空：
	# 其他系统随后通过 is_instance_valid(Game.player) 即可识别旧玩家已失效，
	# 杜绝向已释放实例赋值/调用
	var g: Node = get_node_or_null("/root/Game")
	if g and g.get("player") == self:
		g.set("player", null)

## 视角：走 _input（GUI 链之前）而非 _unhandled_input，
## 任何全屏 Control（暗角/提示板/未来新增面板）都不可能再吞掉鼠标移动。
## 只累积目标角度，实际旋转在 _physics_process 里按 0.12s 平滑插值。
func _input(event: InputEvent) -> void:
	var g_ref: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_ref) or not bool(g_ref.get("started")) or bool(g_ref.get("game_over")):
		return
	var hud_ref: Node = get_node_or_null("/root/Game")
	if is_instance_valid(hud_ref):
		var hud_node: Node = hud_ref.get("hud")
		if is_instance_valid(hud_node):
			if int(hud_node.get("_open_panels")) > 0:
				return
			if bool(hud_node.call("menu_open")):
				return
	# 无 HUD（无头测试/异常路径）时正常放行鼠标视角
	if event is InputEventMouseMotion:
		# 重度失温转身速率 -30%（手指僵住）
		var turn_mult: float = DV.SEVERE_TURN_MULT if _cold_lag_tier() >= 2 else 1.0
		_view_yaw -= event.relative.x * MOUSE_SENS * turn_mult
		_view_pitch -= event.relative.y * MOUSE_SENS * turn_mult
		# 垂直视角限制 -60° / +70°：防止仰视纯白天空造成眩光不适
		_view_pitch = clampf(_view_pitch, DV.PITCH_MIN, DV.PITCH_MAX)

func _unhandled_input(event: InputEvent) -> void:
	var g_ref2: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_ref2) or not bool(g_ref2.get("started")) or bool(g_ref2.get("game_over")):
		return
	var hud_node: Node = get_node_or_null("/root/Game")
	if hud_node:
		hud_node = hud_node.get("hud")
	if is_instance_valid(hud_node) and int(hud_node.get("_open_panels")) > 0:
		return
	# 低温迟滞窗（Cold Lag）：在输入层实现，玩家感觉"手不听使唤"而非"游戏卡"
	var act := _pressed_action(event)
	if act != "" and _cold_lag_swallow(act):
		return
	if event.is_action_pressed("flashlight"):
		_toggle_flashlight()
	if event.is_action_pressed("quick_drink"):
		_quick_use("drink")
	if event.is_action_pressed("quick_eat"):
		_quick_use("food")
	if event.is_action_pressed("quick_med"):
		_quick_use("medical")
	if event.is_action_pressed("cycle_tool"):
		g_ref2.call("tool_cycle")
		_refresh_prompt()  # 换工具后立即刷新提示（如"捕猎 X"随长矛出现）
	if event.is_action_pressed("interact"):
		# E 只做情境交互（对话/开箱/床/终端等）；
		# 采集/拆建/拢雪/攻击一律左键 use，与 E 分工
		_do_interact()
	if event.is_action_pressed("survey"):
		_start_survey()
	if event.is_action_pressed("use"):
		_try_use()

## 取当前事件命中的动作名（供冷迟滞判定）
func _pressed_action(event: InputEvent) -> String:
	for a in ACTION_LIST:
		if event.is_action_pressed(a):
			return a
	return ""

## 低温迟滞窗四档：返回 0 正常 / 1 轻度 / 2 重度 / 3 濒死
func _cold_lag_tier() -> int:
	var g_lag: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_lag):
		return 0
	var core: float = float(g_lag.get("core_temp"))
	if core >= DV.CORE_TEMP_MILD:
		return 0
	if core >= DV.CORE_TEMP_SEVERE:
		return 1
	if core >= DV.CORE_TEMP_LETHAL:
		return 2
	return 3

## 返回 true = 该输入被"冻僵的手指"吞掉
func _cold_lag_swallow(action: String) -> bool:
	var tier := _cold_lag_tier()
	if tier <= 0:
		return false
	if tier == 1:
		# 轻度失温：15% 概率输入延迟 80-150ms（以概率吞掉模拟"手涩"）
		return randf() < DV.LAG_CHANCE
	if tier == 2:
		# 重度失温：连续两次相同输入被视为一次（"手指僵住"）
		var now := Time.get_ticks_msec()
		if action == _last_action and now - _last_action_ms < 400:
			_last_action = ""
			return true
		_last_action = action
		_last_action_ms = now
		return false
	# 濒死：交互需队友协助
	return true

func _physics_process(delta: float) -> void:
	_update_camera_fx(delta)
	_update_stuck_recovery(delta)
	_update_crouch(delta)
	_ensure_mouse_captured()
	_apply_view_smoothing(delta)
	# 倾听模式（Q）：降低移速，热量流失 ×1.5 在 survival 结算
	var hud_ref2: Node = get_node_or_null("/root/Game")
	if hud_ref2:
		hud_ref2 = hud_ref2.get("hud")
	var hud_open2: bool = is_instance_valid(hud_ref2) and int(hud_ref2.get("_open_panels")) > 0
	var menu_open2: bool = is_instance_valid(hud_ref2) and bool(hud_ref2.call("menu_open"))
	listening = Input.is_action_pressed("listen") and control_enabled and not hud_open2 and not menu_open2
	if gather_cd > 0.0:
		gather_cd -= delta
	# 审视（V）：按 T_SURVEY（3s）计时，不做硬锁，时间不停止
	if _survey_t > 0.0:
		_survey_t -= delta
		if _survey_t <= 0.0:
			_finish_survey()
	if _hunt_lock > 0.0:
		_hunt_lock -= delta
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCEL * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	var g_phys: Node = get_node_or_null("/root/Game")
	if not control_enabled or not is_instance_valid(g_phys) or not bool(g_phys.get("started")) or bool(g_phys.get("game_over")):
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCEL * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	_update_interact_target()
	_update_gather(delta)
	_move(delta)

## 卡死自救：躯干（胶囊中部）持续嵌入实体超过 0.6s，就退回最近一次"安全位置"。
## 根治薄墙被挤穿、被家具与墙夹住、掉进几何体内部导致的永久卡死。
func _update_stuck_recovery(delta: float) -> void:
	var g_stuck: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_stuck) or not bool(g_stuck.get("started")) or bool(g_stuck.get("game_over")) or not control_enabled:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	# 用"缩小胶囊"探测：只有身体深度嵌入实体(>0.2m，例如穿进墙里)才命中；
	# 只是贴着墙/顶墙站(胶囊表面接触)不会命中，避免误判把正常顶墙当成卡死。
	var sph := CapsuleShape3D.new()
	sph.radius = 0.2
	sph.height = 1.2
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sph
	q.transform = Transform3D(Basis(), global_position + Vector3(0, 0.9, 0))
	q.collision_mask = 1 | 4 | DV.LAYER_PROP
	q.exclude = [get_rid()]
	var hits := space.intersect_shape(q, 1)
	if hits.is_empty():
		_safe_pos = global_position
		_has_safe = true
		_stuck_t = 0.0
		return
	if not _has_safe:
		return
	# 只有"想走却走不动"才算真卡死：站着不动、或还能移动，都不触发，
	# 避免在坡面低头采集（躯干球与地形重叠）时被误判传送。
	var want_move := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1
	if not want_move or velocity.length() > 0.6:
		_stuck_t = 0.0
		return
	_stuck_t += delta
	if _stuck_t >= 0.8:
		global_position = _safe_pos + Vector3(0, 0.05, 0)
		velocity = Vector3.ZERO
		_stuck_t = 0.0
		g_stuck.call("notify", "你从夹缝里挪了出来。", "info")

func _move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var g_move: Node = get_node_or_null("/root/Game")
	# 负重速度：空手 5.0 / 持大件 2.2 / 满载 3.1（手感规格 2.3）
	var speed := DV.SPEED_EMPTY
	if carrying != null:
		speed = DV.SPEED_CARRY_BIG
	elif bool(g_move.call("inventory_full")):
		speed = DV.SPEED_FULL
	# Shift = 冲刺（加速）。门：不在搬大件/下蹲/倾听/建造中，且还没累趴、没冻僵
	var tier_move: int = int(g_move.get("hypothermia_tier"))
	sprinting = Input.is_action_pressed("sprint") and carrying == null and not crouching \
		and not listening and not bool(g_move.get("build_mode")) and dir.length() > 0.01 \
		and float(g_move.get("fatigue")) < DV.SPRINT_MIN_FATIGUE and tier_move < 3
	if sprinting:
		speed *= DV.SPRINT_MULT
	# 身体状态改写步伐
	var mult := 1.0
	match tier_move:
		1: mult = 0.92
		2: mult = 0.80
		3: mult = 0.62
	if float(g_move.get("fatigue")) > 80.0:
		mult *= 0.85
	if float(g_move.get("hunger")) > 85.0:
		mult *= 0.9
	if bool(g_move.get("indoors")) and bool(g_move.get("has_home")):
		mult *= 0.95
	if bool(g_move.get("build_mode")):
		mult *= 0.55
	if crouching:
		mult *= 0.45
	if listening:
		mult *= LISTEN_SPEED_MULT
	var hud_ref3: Node = get_node_or_null("/root/Game")
	if hud_ref3:
		hud_ref3 = hud_ref3.get("hud")
	var panels_open3: bool = is_instance_valid(hud_ref3) and int(hud_ref3.get("_open_panels")) > 0
	if panels_open3 and not bool(g_move.get("build_mode")):
		# 面板打开时不移动
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCEL * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	speed *= mult
	if dir.length() > 0.01:
		velocity.x = move_toward(velocity.x, dir.x * speed, ACCEL * delta * (1.0 if is_on_floor() else 0.4))
		velocity.z = move_toward(velocity.z, dir.z * speed, ACCEL * delta * (1.0 if is_on_floor() else 0.4))
	else:
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCEL * delta)
	if is_on_floor() and Input.is_action_just_pressed("jump") and tier_move < 3:
		velocity.y = JUMP_VELOCITY
	velocity.y -= GRAVITY * delta
	var was_grounded := is_on_floor()
	move_and_slide()
	if was_grounded and is_on_floor() and dir.length() > 0.1:
		bob_t += delta * (10.5 if sprinting else (4.0 if crouching or listening else 7.0))
	# 掉出世界的保险
	if global_position.y < -30.0:
		global_position = Vector3(global_position.x, 2.0, global_position.z)
		velocity = Vector3.ZERO

## 视角平滑：0.12s 延迟插值（一阶低通），禁止 1:1 刚性跟随
func _apply_view_smoothing(delta: float) -> void:
	var t := 1.0 - exp(-delta / DV.VIEW_LERP)
	rotation.y = lerp_angle(rotation.y, _view_yaw, t)
	if head:
		head.rotation.x = lerpf(head.rotation.x, _view_pitch, t)

## 设定朝向：同时写入平滑目标并即时落位。任何要直接指定朝向的代码
## （读档恢复 / 测试 / 计算式瞄准）都应走这里，而非直接改 rotation —— 否则会被
## _apply_view_smoothing 的插值每帧拉回 _view_yaw，导致朝向与准星错乱。
func set_facing(yaw: float, pitch: float) -> void:
	_view_yaw = yaw
	_view_pitch = clampf(pitch, -1.4, 1.4)
	rotation.y = yaw
	if head:
		head.rotation.x = _view_pitch

# ---------- 交互 ----------

func _update_interact_target() -> void:
	if not ray:
		return
	ray.force_raycast_update()
	var cand: Node3D = _ray_target()
	# 射线没瞄中时，再试两招：① 人就站在物体旁边（体积接触）；② 准星大致对着某物（瞄准辅助）
	if cand == null:
		cand = _proximity_target()
	if cand == null:
		cand = _aim_assist_target()
	if cand != interact_target:
		interact_target = cand
		_refresh_prompt()

## 射线命中解析：优先接触体积(Area, layer 8)→映射到整个物体（对准整物即可交互）；
## 否则命中可交互本体（layer 4 身体 / layer 1 建筑·地形 / 积雪）。
func _ray_target() -> Node3D:
	var col = ray.get_collider()
	if col == null:
		return null
	if col is Area3D and col.has_meta("interact_owner"):
		var owner_node = col.get_meta("interact_owner")
		if is_instance_valid(owner_node):
			return owner_node
	if col is Node3D and (col.has_method("get_prompt") or col.has_method("interact")
			or col.is_in_group("player_building") or col.is_in_group("terrain")
			or col.is_in_group("snow_ground")):
		return col
	return null

## 邻近候选：玩家接触探针与某物体接触体积重叠，且大致在面前 → 走近也能交互
func _proximity_target() -> Node3D:
	if _contact_probe == null or cam == null:
		return null
	var best: Node3D = null
	var best_score := -INF
	var fwd := -cam.global_transform.basis.z
	var origin := cam.global_position
	for area in _contact_probe.get_overlapping_areas():
		if not (area is Area3D) or not area.has_meta("interact_owner"):
			continue
		var owner_node = area.get_meta("interact_owner")
		if not is_instance_valid(owner_node):
			continue
		var to_vec: Vector3 = owner_node.global_position - origin
		var dist: float = to_vec.length()
		var dot: float = 1.0 if dist < 0.001 else fwd.dot(to_vec.normalized())
		if dot < 0.0:
			continue   # 在背后不强行交互；正面/侧面的物体都能交互
		var score: float = dot * 10.0 - dist * 0.2
		if score > best_score:
			best_score = score
			best = owner_node
	return best

## 瞄准辅助：射线没直接瞄中、人也未贴上去时，在 4m 内挑一个与准星方向最对齐的可交互体。
## 让"对着物体的大致方向"就能锁定整物，不必精确压在接触球上——优化"对准整物即可交互"的手感。
func _aim_assist_target() -> Node3D:
	if cam == null:
		return null
	var fwd := -cam.global_transform.basis.z
	var origin := cam.global_position
	var best: Node3D = null
	var best_dot := 0.92          # 约 23° 半角内才算"大致对着"
	for n in get_tree().get_nodes_in_group("interactables"):
		var node: Node3D = n
		if not is_instance_valid(node):
			continue
		var to_vec: Vector3 = node.global_position - origin
		var d := to_vec.length()
		if d > 4.0 or d < 0.001:
			continue
		var dd := fwd.dot(to_vec.normalized())
		if dd <= best_dot:
			continue
		best_dot = dd
		best = node
	return best

func _refresh_prompt() -> void:
	var g_pr: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_pr) or bool(g_pr.get("build_mode")):
		return   ## 建造模式下提示由 Builder 负责（放置指引），这里不抢
	var text := ""
	if interact_target != null and interact_target.has_method("get_prompt"):
		text = interact_target.call("get_prompt", self)
	elif interact_target != null and interact_target.is_in_group("player_building"):
		text = "拆除 %s [按住左键]" % BuildingDefs.name_of(String(interact_target.get_meta("key", "")))
	elif interact_target != null and interact_target.is_in_group("terrain"):
		text = "按住[左键] 拢雪"
	elif interact_target != null and interact_target.is_in_group("snow_ground"):
		text = "按住[左键] 拢雪"
	_prompt_text = text
	g_pr.call("push_prompt", text)

func _do_interact() -> void:
	var g_in: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_in) or bool(g_in.get("build_mode")):
		return
	if interact_target != null and interact_target.has_method("interact"):
		# 长按采集物（枯树/冰岩/冰脉）瞬按不触发：交给 E 键 use 的 _update_gather
		if interact_target.has_method("gather_time") and float(interact_target.call("gather_time")) > 0.0:
			return
		interact_target.call("interact", self)
		if viewmodel:
			viewmodel.punch()
		return

## 审视姿态（V）：不可跳过、时间不停止（操作手感规格 hard 上限 T_SURVEY=3s）
func _start_survey() -> void:
	var g_sv: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_sv) or bool(g_sv.get("build_mode")) or _survey_t > 0.0:
		return
	_survey_t = DV.T_SURVEY
	g_sv.call("notify", "你停步，细细打量四周……", "info")

func _finish_survey() -> void:
	var g_fs: Node = get_node_or_null("/root/Game")
	var world: Node = g_fs.get("world") if g_fs else null
	if is_instance_valid(world) and world.has_method("survey_reveal"):
		world.survey_reveal(global_position)
	else:
		g_fs.call("notify", "四周静悄悄的，没什么可记的。", "info")

func _yield_snow() -> void:
	var g_ys: Node = get_node_or_null("/root/Game")
	g_ys.call("add_item", "snow_brick", 1)
	g_ys.call("notify", "拢起一捧雪，压实就是一块冰雪砖。", "info")

# ---------- 长按采集（森林之子式：按住左键 累积，松手取消，完成才产出） ----------

## 当前准星目标需要的采集秒数（0=不可采集）
## 三类目标：① 自带 gather_time() 的世界物件（枯树/冰岩/冰脉……）
##          ② 自家建筑（长按拆除，DV.T_DEMOLISH）
##          ③ 地形/积雪（拢雪，耗时 T_PICK_SMALL）
func _gather_need() -> float:
	if interact_target == null:
		return 0.0
	if interact_target.has_method("gather_time"):
		return float(interact_target.call("gather_time"))
	if interact_target.is_in_group("player_building"):
		return DV.T_DEMOLISH
	if interact_target.is_in_group("terrain") or interact_target.is_in_group("snow_ground"):
		return DV.T_PICK_SMALL
	return 0.0

func _update_gather(delta: float) -> void:
	# 面板/建造/濒死（核心≤28℃ 手指僵住）时不许采集
	var hud_ref7: Node = get_node_or_null("/root/Game")
	if hud_ref7:
		hud_ref7 = hud_ref7.get("hud")
	var hud_busy: bool = is_instance_valid(hud_ref7) and int(hud_ref7.get("_open_panels")) > 0
	var g_gt: Node = get_node_or_null("/root/Game")
	var blocked: bool = (g_gt != null and bool(g_gt.get("build_mode"))) or (g_gt != null and bool(g_gt.get("game_over"))) or not control_enabled or hud_busy or _cold_lag_tier() >= 3
	var need := 0.0 if blocked else _gather_need()
	if need <= 0.0 or not Input.is_action_pressed("use"):
		if _gather_t > 0.0:
			_cancel_gather()
		return
	if _gather_total != need:
		_gather_total = need
		_gather_t = 0.0
	_gather_t += delta
	# 挥动节奏：约每 0.4s 一次（工具/手套真实挥动；相机不抖——屏幕抖只留给受击/天灾）
	_swing_cd -= delta
	if _swing_cd <= 0.0:
		if viewmodel:
			viewmodel.punch()
		_swing_cd = 0.4
	if _gather_t >= _gather_total:
		_gather_t = 0.0
		_complete_gather()

func _cancel_gather() -> void:
	_gather_t = 0.0
	_gather_total = 0.0

func _complete_gather() -> void:
	if interact_target != null and interact_target.has_method("harvest"):
		# 世界物件（枯树/冰岩）：掉落在节点侧，挥动也在玩家侧补一下
		interact_target.call("harvest", self)
		if viewmodel:
			viewmodel.punch()
	elif interact_target != null and interact_target.is_in_group("player_building"):
		_demolish_target()
	elif interact_target != null and (interact_target.is_in_group("terrain") or interact_target.is_in_group("snow_ground")):
		_yield_snow()
	_cancel_gather()
	_refresh_prompt()   ## 采空/拆毁后提示要立即更新

## 长按拆除自家建筑：返还一半材料（每样至少 1），移除并重算庇护所
func _demolish_target() -> void:
	var t := interact_target
	if t == null:
		return
	var key := String(t.get_meta("key", ""))
	var g_dm: Node = get_node_or_null("/root/Game")
	# 从建造列表移除（按 node 引用匹配）
	var found := -1
	var buildings: Array = g_dm.get("buildings")
	for i in range(buildings.size()):
		var b: Dictionary = buildings[i]
		if b.get("node", null) == t:
			found = i
			break
	var cost := BuildingDefs.cost_of(key)
	var parts := []
	var lost := []
	for id in cost:
		var n := maxi(1, int(float(cost[id]) * DV.DEMOLISH_REFUND))
		var left := int(g_dm.call("add_item", String(id), n))
		if left > 0:
			lost.append("%s×%d" % [Items.name_of(String(id)), left])
		else:
			parts.append("%s×%d" % [Items.name_of(String(id)), n])
	if found >= 0:
		buildings.remove_at(found)
	g_dm.set("shelter_level", ShelterJudge.compute(buildings, g_dm.get("home_center")))
	if not lost.is_empty():
		# 包满：拆下来的材料没处放，明说，不静默蒸发
		g_dm.call("notify", "拆了%s，但包满了：%s 拿不下。" % [BuildingDefs.name_of(key), "、".join(lost)], "bad")
	else:
		g_dm.call("notify", "拆了%s，收回：%s。" % [BuildingDefs.name_of(key), "、".join(parts)], "info")
	var sound: Node = g_dm.get("sound")
	if is_instance_valid(sound) and sound.has_method("play_demolish"):
		sound.play_demolish()
	t.queue_free()

## HUD 采集进度条读数（0..1，0=不在采集）
func gather_progress() -> float:
	if _gather_total <= 0.0:
		return 0.0
	return clampf(_gather_t / _gather_total, 0.0, 1.0)

# ---------- 攻击 / 使用（鼠标左键） ----------

## 左键 = 攻击+使用：对准生物→捕猎突刺；资源/积雪/自家建筑→由 _update_gather 在按住时处理
## （采集/拢雪/拆建）。与交互键（E）严格分工：E 只做情境交互（对话/开箱/床/终端）。
func _try_use() -> void:
	var g_tu: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_tu) or bool(g_tu.get("build_mode")) or not control_enabled or bool(g_tu.get("game_over")):
		return
	if interact_target != null and interact_target.has_method("try_harvest"):
		_try_hunt()
		return
	# 其余（资源/积雪/建筑）交给 _update_gather 的按住逻辑；这里不必即时动作

# ---------- 捕猎 ----------

func _try_hunt() -> void:
	var g_th: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_th) or bool(g_th.get("build_mode")) or _hunt_lock > 0.0:
		return
	if String(g_th.get("active_tool")) != "spear":
		if int(g_th.call("count_item", "spear")) > 0:
			g_th.call("notify", "手里不是长矛。按 4 换上手。", "info")
		else:
			g_th.call("notify", "捕猎需要一柄长矛。木材、绳索和金属碎片可以先做一柄。", "info")
		return
	var best: Node = null
	var best_d := 3.0
	for cn in get_tree().get_nodes_in_group("creatures"):
		var c: Node3D = cn
		if not c.has_method("try_harvest"):
			continue
		var d := global_position.distance_to(c.global_position)
		var facing := (c.global_position - global_position).normalized().dot(-cam.global_transform.basis.z)
		if d < best_d and facing > 0.55:
			best = c
			best_d = d
	if best == null:
		g_th.call("notify", "太远了，或者它不在你正面。", "info")
		return
	_hunt_lock = 0.5
	if viewmodel:
		viewmodel.thrust()
	control_enabled = false
	await get_tree().create_timer(0.45).timeout
	# 等待期间若场景被重载（读档/死亡重开），本节点已释放，先自检再赋值
	if not is_inside_tree():
		return
	control_enabled = bool(g_th.get("started")) and not bool(g_th.get("game_over"))
	if is_instance_valid(best):
		best.call("try_harvest", self)

# ---------- 火把 / 手电 ----------

func _toggle_flashlight() -> void:
	var g_fl: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_fl):
		return
	if int(g_fl.call("count_item", "flashlight")) <= 0:
		g_fl.call("notify", "你没有手电。", "info")
		return
	flashlight_on = not flashlight_on
	flashlight.visible = flashlight_on
	if flashlight_on and int(g_fl.call("count_item", "battery")) <= 0:
		flashlight.light_energy = 0.6
		g_fl.call("notify", "手电暗了一下——充电宝见了底。", "info")
	else:
		flashlight.light_energy = 2.2

func _quick_use(cat: String) -> void:
	var g_qu: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_qu):
		return
	var inv: Node = g_qu.get("inventory")
	var id := String(inv.call("first_of_cat", cat)) if inv else ""
	if id == "":
		g_qu.call("notify", "没有可用的%s。" % {"drink": "水", "food": "吃的", "medical": "药品"}.get(cat, ""), "info")
		return
	_consume(id)

func _consume(id: String) -> void:
	var g_cn: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_cn):
		return
	match Items.cat_of(id):
		"food":
			g_cn.set("hunger", maxf(0.0, float(g_cn.get("hunger")) - float(Items.def(id).get("food", 20.0))))
			g_cn.call("remove_item", id, 1)
			g_cn.call("notify", "吃下一份%s。身上松快了些。" % Items.name_of(id), "good")
		"drink":
			g_cn.set("thirst", maxf(0.0, float(g_cn.get("thirst")) - float(Items.def(id).get("drink", 20.0))))
			g_cn.call("remove_item", id, 1)
			g_cn.call("notify", "冰水下去，喉咙缓过来了。", "good")
		"medical":
			_use_medical(id)
		"tool":
			g_cn.set("active_tool", id)
			g_cn.call("notify", "手持：%s" % Items.name_of(id), "info")
			_refresh_prompt()  # 手持变化可能改变交互提示（如捕猎）

func _use_medical(id: String) -> void:
	var g_md: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_md):
		return
	match id:
		"bandage":
			if bool(g_md.call("get_flag", "wounded")):
				g_md.call("set_flag", "wounded", false)
				g_md.set("health", minf(100.0, float(g_md.get("health")) + 18.0))
				g_md.call("remove_item", id, 1)
				g_md.call("notify", "压住、清洁、缠好。伤口稳住了。", "good")
			else:
				g_md.set("health", minf(100.0, float(g_md.get("health")) + 6.0))
				g_md.call("remove_item", id, 1)
				g_md.call("notify", "眼下没有伤口，敷料先收着。", "info")
		"disinfectant":
			if bool(g_md.call("get_flag", "wounded")):
				g_md.set("health", minf(100.0, float(g_md.get("health")) + 8.0))
				g_md.call("remove_item", id, 1)
				g_md.call("notify", "清洁过伤口，好得更快些。", "good")
			else:
				g_md.call("notify", "没有需要清洁的伤口。", "info")

# ---------- 伤害 ----------

func hurt(amount: float, reason: String) -> void:
	var g_ht: Node = get_node_or_null("/root/Game")
	if not is_instance_valid(g_ht) or bool(g_ht.get("game_over")):
		return
	g_ht.set("health", float(g_ht.get("health")) - amount)
	g_ht.call("set_flag", "wounded", true)
	_hurt_flash = 0.6
	shake_amount = maxf(shake_amount, 0.5)
	g_ht.call("notify", reason, "bad")
	if float(g_ht.get("health")) <= 0.0:
		g_ht.set("health", 0.0)
		g_ht.set("game_over", true)
		g_ht.call("notify", "视野一点点沉下去……", "bad")
		var hud_ref4: Node = g_ht.get("hud")
		if is_instance_valid(hud_ref4) and hud_ref4.has_method("show_game_over"):
			hud_ref4.call("show_game_over")

func add_shake(v: float) -> void:
	shake_amount = maxf(shake_amount, v)

func get_hurt_flash() -> float:
	return _hurt_flash

# ---------- 相机反馈 ----------

func _update_camera_fx(delta: float) -> void:
	if cam == null:
		return
	# 走路颠簸（cam 是 Head 的子节点，眼高由 Head 承载 1.62，这里只做相对偏移）
	var speed2 := Vector2(velocity.x, velocity.z).length()
	var bob := 0.0
	if is_on_floor() and speed2 > 0.5:
		bob = sin(bob_t) * 0.035 * minf(speed2 / DV.SPEED_EMPTY, 1.6)
	cam.position.y = lerpf(0.0, -(EYE_STAND - EYE_CROUCH), crouch_amt) + bob
	# 发抖（迟滞窗：抖的时候往往已经更冷了）。
	# 注意：抖的是第一人称的"手"（viewmodel 读 shiver_amount 施加到 rig/手臂），
	# 相机/屏幕不抖——否则变成整个画面在晃，那是受击/天灾的效果，不是手抖
	shiver_amount = 0.0
	var g_fx: Node = get_node_or_null("/root/Game")
	match int(g_fx.get("hypothermia_tier")) if g_fx else 0:
		1: shiver_amount = 0.006
		2: shiver_amount = 0.016
		3: shiver_amount = 0.038
	if g_fx and float(g_fx.get("fatigue")) > 80.0:
		shiver_amount += 0.008
	# 受击闪红 + 屏幕震动
	if _hurt_flash > 0.0:
		_hurt_flash -= delta
		shake_amount = maxf(shake_amount, 0.25)
	if shake_amount > 0.0:
		shake_amount = maxf(0.0, shake_amount - delta * 1.8)
		cam.rotation.z = randf_range(-1.0, 1.0) * shake_amount * 0.03
	else:
		cam.rotation.z = 0.0
	# 火把微光
	if flashlight_on and g_fx and int(g_fx.call("count_item", "battery")) <= 0:
		flashlight.light_energy = 0.6 + sin(Time.get_ticks_msec() * 0.01) * 0.15

# ---------- 下蹲（Ctrl） ----------

func _update_crouch(delta: float) -> void:
	var g_cr: Node = get_node_or_null("/root/Game")
	var want := Input.is_action_pressed("crouch") and is_instance_valid(g_cr) and bool(g_cr.get("started")) and not bool(g_cr.get("game_over"))
	var hud_ref5: Node = g_cr.get("hud") if g_cr else null
	if is_instance_valid(hud_ref5) and int(hud_ref5.get("_open_panels")) > 0:
		want = false
	crouching = want
	crouch_amt = move_toward(crouch_amt, 1.0 if crouching else 0.0, delta * 8.0)

## 鼠标模式自愈：游戏中（无面板/菜单/未结束）却处于非捕获状态时自动抓回。
## 防止某些路径漏设 mouse_mode 导致“能走不能转视角”。
func _ensure_mouse_captured() -> void:
	var g_mc: Node = get_node_or_null("/root/Game")
	if title_open or not is_instance_valid(g_mc) or not bool(g_mc.get("started")) or bool(g_mc.get("game_over")):
		return
	var hud_ref6: Node = g_mc.get("hud")
	if is_instance_valid(hud_ref6) and (int(hud_ref6.get("_open_panels")) > 0 or bool(hud_ref6.call("menu_open"))):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
