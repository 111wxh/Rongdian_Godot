extends Node
class_name ViewModel
## 第一人称手部视图模型。
## 用独立 SubViewport（自有 World3D + 环境光）渲染手臂与手持物，
## 再以 TextureRect 覆盖在画面上——不会被场景几何体裁剪，也不受世界光照影响。
## 空手只显示手套；持有工具时按 Game.active_tool 切换模型。
## 动画：待机摇晃 / 走路摆动 / 视角滞后 / 下蹲降低 / E 出拳 / 捕猎突刺 / 搬运双臂。

var player: Player = null
var vp: SubViewport
var vcam: Camera3D
var rig: Node3D
var arm_r: Node3D
var arm_l: Node3D
var item_root: Node3D
var item_node: Node3D = null
var _lens_mat: StandardMaterial3D = null

var _cur_tool := "~none~"
var cinematic := ""    ## 演出姿态（开场苏醒用）：reach_down 双手拔腿 / push_up 撑地起身 / "" 正常动画
var _sway_t := 0.0
var _punch_t := 1.0
var _thrust_t := 1.0
var _lag_yaw := 0.0
var _lag_pitch := 0.0
var _prev_yaw := 0.0
var _prev_pitch := 0.0

func setup(p: Player) -> void:
	player = p
	_build_viewport()
	_build_hands()

# =====================================================================
# 视图层
# =====================================================================

func _build_viewport() -> void:
	vp = SubViewport.new()
	vp.name = "HandsVP"
	vp.world_3d = World3D.new()
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.size = Vector2i(1152, 648)
	# 独立世界环境光：没有光源时手也看得见
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.88)
	env.ambient_light_energy = 0.6
	vp.world_3d.environment = env
	vcam = Camera3D.new()
	vcam.name = "HandsCam"
	vcam.fov = 55.0
	vp.add_child(vcam)
	# 手上补一盏暖光，手持物有立体感
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.95, 0.88)
	lamp.light_energy = 1.15
	lamp.omni_range = 3.0
	lamp.position = Vector3(0.3, 0.1, -0.3)
	vcam.add_child(lamp)
	add_child(vp)
	# 覆盖层（layer 3：在世界与 HUD 之上——双手永远不被任何面板/暗角遮住）
	var layer := CanvasLayer.new()
	layer.name = "HandsLayer"
	layer.layer = 3
	var tex_rect := TextureRect.new()
	tex_rect.name = "HandsTexture"
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.texture = vp.get_texture()
	layer.add_child(tex_rect)
	add_child(layer)
	if get_viewport():
		get_viewport().size_changed.connect(_on_viewport_resized)
		_on_viewport_resized()

func _on_viewport_resized() -> void:
	if vp and get_viewport():
		vp.size = get_viewport().get_visible_rect().size

# =====================================================================
# 手臂
# =====================================================================

func _m(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _mesh_node(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	return mi

func _build_hands() -> void:
	rig = Node3D.new()
	rig.name = "Rig"
	vcam.add_child(rig)
	arm_r = _make_arm(Vector3(0.26, -0.27, -0.30), 1.0)
	arm_l = _make_arm(Vector3(-0.30, -0.30, -0.34), -1.0)
	arm_l.visible = false
	rig.add_child(arm_r)
	rig.add_child(arm_l)
	item_root = Node3D.new()
	item_root.name = "ItemRoot"
	item_root.position = Vector3(-0.02, 0.01, -0.44)
	item_root.rotation.x = -1.35
	arm_r.add_child(item_root)

func _make_arm(base: Vector3, side: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Arm"
	root.position = base
	# 袖筒（冬衣外侧）
	var sleeve := CapsuleMesh.new()
	sleeve.radius = 0.072
	sleeve.height = 0.38
	root.add_child(_mesh_node(sleeve, _m(Color(0.23, 0.27, 0.35), 0.85), Vector3(-0.01 * side, 0.0, -0.19), Vector3(-1.55, 0.0, 0.0)))
	# 手套
	var glove := BoxMesh.new()
	glove.size = Vector3(0.115, 0.10, 0.16)
	root.add_child(_mesh_node(glove, _m(Color(0.16, 0.13, 0.11), 0.8), Vector3(-0.02 * side, 0.01, -0.38), Vector3(-1.5, 0.0, 0.0)))
	# 袖口翻毛
	var cuff := CylinderMesh.new()
	cuff.top_radius = 0.085
	cuff.bottom_radius = 0.075
	cuff.height = 0.05
	root.add_child(_mesh_node(cuff, _m(Color(0.55, 0.52, 0.48), 0.9), Vector3(-0.005 * side, -0.02, -0.22), Vector3(-1.55, 0.0, 0.0)))
	return root

# =====================================================================
# 手持物模型（沿 -z 向前，约 10cm 量级）
# =====================================================================

func _set_tool(t: String) -> void:
	_cur_tool = t
	if item_node and is_instance_valid(item_node):
		item_node.queue_free()
	item_node = null
	_lens_mat = null
	item_node = _build_item(t)
	if item_node:
		item_root.add_child(item_node)

func _build_item(tool: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Item_" + tool
	match tool:
		"knife":
			var hb := BoxMesh.new(); hb.size = Vector3(0.028, 0.032, 0.095)
			root.add_child(_mesh_node(hb, _m(Color(0.35, 0.2, 0.12), 0.8), Vector3(0, 0, 0.035)))
			var gb := BoxMesh.new(); gb.size = Vector3(0.036, 0.009, 0.009)
			root.add_child(_mesh_node(gb, _m(Color(0.6, 0.6, 0.62), 0.4, 0.8), Vector3(0, 0, -0.015)))
			var bl := BoxMesh.new(); bl.size = Vector3(0.012, 0.05, 0.115)
			root.add_child(_mesh_node(bl, _m(Color(0.78, 0.8, 0.84), 0.25, 0.9), Vector3(0, 0.004, -0.105)))
		"scissors":
			for s in [-1.0, 1.0]:
				var b := BoxMesh.new(); b.size = Vector3(0.01, 0.022, 0.11)
				root.add_child(_mesh_node(b, _m(Color(0.7, 0.72, 0.75), 0.35, 0.85), Vector3(s * 0.012, 0, -0.05), Vector3(0, 0, s * 0.06)))
				var rg := CylinderMesh.new(); rg.top_radius = 0.016; rg.bottom_radius = 0.016; rg.height = 0.012
				root.add_child(_mesh_node(rg, _m(Color(0.75, 0.2, 0.18), 0.5), Vector3(s * 0.02, 0, 0.03), Vector3(PI / 2.0, 0, 0)))
		"multitool":
			var bd := BoxMesh.new(); bd.size = Vector3(0.036, 0.062, 0.115)
			root.add_child(_mesh_node(bd, _m(Color(0.3, 0.32, 0.36), 0.45, 0.7), Vector3(0, 0, 0.02)))
			var bl := BoxMesh.new(); bl.size = Vector3(0.014, 0.045, 0.085)
			root.add_child(_mesh_node(bl, _m(Color(0.76, 0.78, 0.82), 0.25, 0.9), Vector3(0, 0.03, -0.09), Vector3(0.5, 0, 0)))
			var pl := BoxMesh.new(); pl.size = Vector3(0.03, 0.02, 0.06)
			root.add_child(_mesh_node(pl, _m(Color(0.4, 0.42, 0.46), 0.4, 0.8), Vector3(0, -0.03, -0.1)))
		"wrench":
			var hd := CylinderMesh.new(); hd.top_radius = 0.017; hd.bottom_radius = 0.017; hd.height = 0.15
			root.add_child(_mesh_node(hd, _m(Color(0.55, 0.57, 0.6), 0.4, 0.8), Vector3(0, 0, 0.02)))
			var h1 := BoxMesh.new(); h1.size = Vector3(0.052, 0.042, 0.028)
			root.add_child(_mesh_node(h1, _m(Color(0.6, 0.62, 0.66), 0.35, 0.85), Vector3(0, 0, -0.075)))
			var h2 := BoxMesh.new(); h2.size = Vector3(0.026, 0.042, 0.028)
			root.add_child(_mesh_node(h2, _m(Color(0.6, 0.62, 0.66), 0.35, 0.85), Vector3(0, 0, -0.075)))
		"screwdriver":
			var hd := CylinderMesh.new(); hd.top_radius = 0.021; hd.bottom_radius = 0.024; hd.height = 0.085
			root.add_child(_mesh_node(hd, _m(Color(0.75, 0.3, 0.18), 0.6), Vector3(0, 0, 0.03)))
			var sh := CylinderMesh.new(); sh.top_radius = 0.006; sh.bottom_radius = 0.007; sh.height = 0.11
			root.add_child(_mesh_node(sh, _m(Color(0.72, 0.74, 0.78), 0.3, 0.9), Vector3(0, 0, -0.09)))
			var tp := BoxMesh.new(); tp.size = Vector3(0.012, 0.003, 0.02)
			root.add_child(_mesh_node(tp, _m(Color(0.72, 0.74, 0.78), 0.3, 0.9), Vector3(0, 0, -0.148)))
		"spear":
			var pole := CylinderMesh.new()
			pole.top_radius = 0.016
			pole.bottom_radius = 0.019
			pole.height = 1.55
			root.add_child(_mesh_node(pole, _m(Color(0.4, 0.3, 0.2), 0.85), Vector3(0, 0, -0.68)))
			var tip := CylinderMesh.new()
			tip.top_radius = 0.0
			tip.bottom_radius = 0.032
			tip.height = 0.17
			root.add_child(_mesh_node(tip, _m(Color(0.75, 0.77, 0.8), 0.3, 0.9), Vector3(0, 0, -1.5)))
			var bind := CylinderMesh.new()
			bind.top_radius = 0.023
			bind.bottom_radius = 0.023
			bind.height = 0.05
			root.add_child(_mesh_node(bind, _m(Color(0.5, 0.42, 0.3), 0.9), Vector3(0, 0, -1.36)))
		"lighter":
			var bd := CylinderMesh.new(); bd.top_radius = 0.013; bd.bottom_radius = 0.015; bd.height = 0.055
			root.add_child(_mesh_node(bd, _m(Color(0.65, 0.15, 0.12), 0.4, 0.5), Vector3(0, 0, 0.0)))
			var fl := SphereMesh.new(); fl.radius = 0.009; fl.height = 0.018
			var fm := StandardMaterial3D.new()
			fm.albedo_color = Color(0.9, 0.75, 0.4)
			fm.emission_enabled = true
			fm.emission = Color(1.0, 0.8, 0.45)
			fm.emission_energy_multiplier = 1.6
			root.add_child(_mesh_node(fl, fm, Vector3(0, 0.022, 0.0)))
		"flashlight":
			var bd := CylinderMesh.new(); bd.top_radius = 0.026; bd.bottom_radius = 0.03; bd.height = 0.15
			root.add_child(_mesh_node(bd, _m(Color(0.2, 0.22, 0.25), 0.5, 0.4), Vector3(0, 0, -0.01)))
			var hd := CylinderMesh.new(); hd.top_radius = 0.042; hd.bottom_radius = 0.03; hd.height = 0.04
			root.add_child(_mesh_node(hd, _m(Color(0.6, 0.62, 0.65), 0.4, 0.7), Vector3(0, 0, -0.1)))
			var lens := StandardMaterial3D.new()
			lens.albedo_color = Color(0.9, 0.92, 0.95)
			lens.emission_enabled = true
			lens.emission = Color(1.0, 0.95, 0.85)
			lens.emission_energy_multiplier = 0.0
			_lens_mat = lens
			var lb := CylinderMesh.new(); lb.top_radius = 0.036; lb.bottom_radius = 0.036; lb.height = 0.012
			root.add_child(_mesh_node(lb, lens, Vector3(0, 0, -0.118)))
		"matches":
			var bx := BoxMesh.new(); bx.size = Vector3(0.022, 0.014, 0.07)
			root.add_child(_mesh_node(bx, _m(Color(0.55, 0.42, 0.28), 0.85), Vector3(0, 0, 0.0)))
			var tp := BoxMesh.new(); tp.size = Vector3(0.023, 0.006, 0.012)
			root.add_child(_mesh_node(tp, _m(Color(0.7, 0.2, 0.15), 0.6), Vector3(0, 0, -0.04)))
		"battery":
			var bd := BoxMesh.new(); bd.size = Vector3(0.045, 0.075, 0.024)
			root.add_child(_mesh_node(bd, _m(Color(0.15, 0.17, 0.2), 0.5, 0.3), Vector3(0, 0, 0.0)))
			var led := BoxMesh.new(); led.size = Vector3(0.008, 0.008, 0.004)
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(0.4, 0.9, 0.5)
			lm.emission_enabled = true
			lm.emission = Color(0.4, 0.9, 0.5)
			lm.emission_energy_multiplier = 1.2
			root.add_child(_mesh_node(led, lm, Vector3(0, 0.03, -0.014)))
		_:
			return null  # 空手：只显示手套
	return root

# =====================================================================
# 每帧动画
# =====================================================================

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or rig == null:
		return
	var cam: Camera3D = player.cam
	if cam == null:
		return
	# 开场/结局期间不显示手（演出姿态除外：苏醒时要看到自己的手）
	var g_vm: Node = get_node_or_null("/root/Game")
	rig.visible = (bool(g_vm.get("started")) or cinematic != "") and not bool(g_vm.get("game_over")) if g_vm else (cinematic != "")
	if not rig.visible:
		return
	# 相机同步：手跟着视角走
	vcam.global_transform = cam.global_transform
	# 视角滞后：手比头慢半拍
	var yaw := player.rotation.y
	var pitch := player.head.rotation.x if player.head else 0.0
	var dyaw := wrapf(yaw - _prev_yaw, -PI, PI)
	var dpitch := wrapf(pitch - _prev_pitch, -PI, PI)
	_prev_yaw = yaw
	_prev_pitch = pitch
	var inv := 1.0 / maxf(delta, 0.0001)
	_lag_yaw = lerpf(_lag_yaw, clampf(-dyaw * inv * 0.012, -0.05, 0.05), minf(1.0, delta * 9.0))
	_lag_pitch = lerpf(_lag_pitch, clampf(dpitch * inv * 0.010, -0.045, 0.045), minf(1.0, delta * 9.0))
	# 工具切换
	var g_tl: Node = get_node_or_null("/root/Game")
	var t := String(g_tl.get("active_tool")) if g_tl else ""
	if t != _cur_tool:
		_set_tool(t)
	# 动作进度
	if _punch_t < 1.0:
		_punch_t = minf(1.0, _punch_t + delta / 0.22)
	if _thrust_t < 1.0:
		_thrust_t = minf(1.0, _thrust_t + delta / 0.3)
	var punch_amt := sin(_punch_t * PI) * 0.13
	var thrust_amt := sin(_thrust_t * PI) * 0.32
	# 走路摆动 / 待机漂浮 / 下蹲 / 搬运
	_sway_t += delta
	var speed2 := Vector2(player.velocity.x, player.velocity.z).length()
	var bob := sin(player.bob_t) * 0.011 * minf(speed2 / 3.4, 1.6)
	var idle := sin(_sway_t * 1.4) * 0.0035
	var crouch := player.crouch_amt
	var carry := 1.0 if player.carrying != null else 0.0
	rig.position = Vector3(_lag_yaw + idle, -0.14 * crouch + bob - 0.05 * carry + punch_amt * 0.5 + thrust_amt * 0.35, -(punch_amt + thrust_amt))
	rig.rotation = Vector3(_lag_pitch + crouch * 0.10 + thrust_amt * 0.18 + carry * 0.22, _lag_yaw * 0.9, 0.0)
	# 左臂：长矛双手持 / 搬运时抬起
	var two_handed := (t == "spear")
	arm_l.visible = two_handed or carry > 0.5
	if two_handed:
		arm_l.position = Vector3(0.10, -0.26, -0.72)
		arm_l.rotation = Vector3(-1.5, 0.0, 0.08)
	elif carry > 0.5:
		arm_l.position = Vector3(-0.30, -0.28, -0.34)
		arm_l.rotation = Vector3(-1.55, 0.0, -0.25)
	# ---- 演出姿态（开场苏醒）：覆盖常规手臂动画 ----
	if cinematic != "":
		_apply_cinematic()
	# 失温/疲劳手抖：高频小幅度震颤施加在"手"上（rig + 右臂），
	# 相机不抖（screen shake 只留给受击/天灾）。频率 ≈7-10Hz，幅度随失温档位
	var shiver: float = player.shiver_amount
	if shiver > 0.0:
		var st := Time.get_ticks_msec() * 0.02
		rig.position.x += sin(st * 2.3) * shiver
		rig.position.y += sin(st * 3.1) * shiver * 0.6
		rig.rotation.z += sin(st * 1.9) * shiver * 0.5
		# 持物的右手抖得更明显：手腕两个轴各一份不同频率，避免像正弦巡逻
		arm_r.rotation.z += sin(st * 3.3 + 1.3) * shiver * 0.8
		arm_r.rotation.x += sin(st * 2.7 + 0.7) * shiver * 0.4
	# 手电镜片随手电开关亮灭
	if _lens_mat:
		_lens_mat.emission_energy_multiplier = 2.2 if player.flashlight_on else 0.0

# =====================================================================
# 对外动作
# =====================================================================

## 演出姿态：双手下探（拔腿）/ 双手下撑（起身）。带低频摆动，像真的在使劲
func _apply_cinematic() -> void:
	var t := Time.get_ticks_msec() * 0.006
	arm_l.visible = true
	arm_r.visible = true
	if cinematic == "reach_down":
		var pull := sin(t * 2.2) * 0.06
		arm_r.position = Vector3(0.30, -0.52 - pull, -0.42)
		arm_r.rotation = Vector3(-1.15, 0.0, 0.18)
		arm_l.position = Vector3(-0.30, -0.52 - pull, -0.42)
		arm_l.rotation = Vector3(-1.15, 0.0, -0.18)
	elif cinematic == "push_up":
		var push := sin(t * 2.6) * 0.03
		arm_r.position = Vector3(0.34, -0.48 + push, -0.30)
		arm_r.rotation = Vector3(-0.55, 0.0, 0.28)
		arm_l.position = Vector3(-0.34, -0.48 + push, -0.30)
		arm_l.rotation = Vector3(-0.55, 0.0, -0.28)

func punch() -> void:
	_punch_t = 0.0

func thrust() -> void:
	_thrust_t = 0.0
