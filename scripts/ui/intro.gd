extends Control
class_name IntroUI
## 苏醒日：电影化开场（不可跳过，约 20 秒）——
## 黑屏眨眼睁眼 → 低头 → 双手把腿拔出雪坑 → 向后倒在地上看天 →
## 记忆洪流 → 撑地起身 → 亲手输入名字 → 确认职业 → 自由沙盒
## 口径：演出期间 control_enabled=false；镜头经 player.set_facing 驱动
## （绕开视角平滑的抢夺），眼高/侧倾直接写 head；手部姿态走 viewmodel.cinematic。

var player: Player
var state := "idle"
var fade: ColorRect
var flash: ColorRect
var caption: Label
var sub: Label
var panel: PanelContainer
var _pitch := 0.0     ## 演出俯仰（经 set_facing 驱动，避免被平滑抢回）
var _head_y := 1.62   ## 演出眼高（后倒时降到 0.5，撑起时回 1.62）
var _roll := 0.0      ## 演出头部侧倾（后倒时轻歪）
var _skip_requested := false   ## 演出跳过标记：置上后所有等待点直接收工

const CINEMATIC_STATES := ["wake", "look_down", "pull_legs", "fall_back", "lie", "memory", "push_up"]

const MEMORY_SNIPPETS := [
	"凌晨四点的天，白了。不是天亮的那种白。",
	"电梯下行的失重，和一声没说完的话。",
	"雪落进领口，凉得像十六度的秋天。",
	"有人在很远的地方喊你的名字。",
	"然后，是万年的安静。",
]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	caption = Label.new()
	caption.set_anchors_preset(Control.PRESET_CENTER)
	caption.set_deferred("position", Vector2(-420, -40))
	caption.set_deferred("size", Vector2(840, 80))
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 20)
	caption.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	sub = Label.new()
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.set_deferred("position", Vector2(-420, 60))
	sub.set_deferred("size", Vector2(840, 40))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.7, 0.8, 0.92))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.set_deferred("position", Vector2(-260, -180))
	panel.set_deferred("size", Vector2(520, 360))
	panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.95)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

## 等待自检：场景树 timer/tween 不随本节点释放而取消，每次 await 后必须确认
## 自己还活着（读档/重开会重载场景；玩家按了跳过），否则向已释放实例赋值报 freed instance
func _alive() -> bool:
	return is_inside_tree() and not _skip_requested and is_instance_valid(player) and is_instance_valid(caption)

func _process(_delta: float) -> void:
	if not _alive():
		return
	# 演出期间的跳过提示
	if state in CINEMATIC_STATES and sub.text != "（按任意键跳过）":
		sub.text = "（按任意键跳过）"
	if state in ["look_down", "pull_legs", "fall_back", "lie", "push_up"]:
		player.set_facing(player.rotation.y, _pitch)
		if player.head:
			player.head.position.y = _head_y
			player.head.rotation.z = _roll

## 演出中按任意键/鼠标：跳过电影化开场，直接进起名
func _unhandled_input(event: InputEvent) -> void:
	if _skip_requested or not (state in CINEMATIC_STATES):
		return
	var pressed := false
	if event is InputEventKey and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.pressed:
		pressed = true
	if not pressed:
		return
	_skip_intro()

func _skip_intro() -> void:
	_skip_requested = true
	# 演出状态变量复位（测试与后续逻辑都读它们）
	_pitch = 0.0
	_head_y = 1.62
	_roll = 0.0
	# 杀掉本节点上所有进行中的 tween（create_tween 的 Tween 是本节点的子节点）
	var kids := get_children()
	for i in range(kids.size()):
		var ch: Object = kids[i]
		if ch is Tween:
			ch.kill()
	# 姿态复位：站起来、平视、手放下
	if is_instance_valid(player):
		player.set_facing(player.rotation.y, 0.0)
		if player.head:
			player.head.position.y = 1.62
			player.head.rotation.z = 0.0
		if is_instance_valid(player.viewmodel):
			player.viewmodel.cinematic = ""
	# 黑场快淡出
	if is_instance_valid(fade):
		var ft := create_tween()
		ft.tween_property(fade, "color:a", 0.0, 0.35)
	if is_instance_valid(caption):
		caption.text = ""
	if is_instance_valid(sub):
		sub.text = ""
	state = "name"
	_name_input()

func start_intro(p: Player) -> void:
	player = p
	player.control_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	state = "wake"
	caption.text = ""
	sub.text = ""
	var g_si: Node = get_node_or_null("/root/Game")
	if g_si:
		g_si.call("notify", "……", "info")
	# ---- 一、眨眼：黑屏里眼皮颤几下，再缓缓睁开 ----
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.92, 0.14)
	tw.tween_property(fade, "color:a", 1.0, 0.10)
	tw.tween_property(fade, "color:a", 0.78, 0.14)
	tw.tween_property(fade, "color:a", 1.0, 0.12)
	tw.tween_property(fade, "color:a", 0.45, 0.18)
	tw.tween_property(fade, "color:a", 1.0, 0.14)
	tw.tween_property(fade, "color:a", 0.0, 1.3)
	await tw.finished
	if not _alive():
		return
	await get_tree().create_timer(0.6).timeout
	if not _alive():
		return
	# ---- 二、低头 ----
	state = "look_down"
	caption.text = "……头很沉。"
	var ld := create_tween()
	ld.tween_property(self, "_pitch", -1.15, 1.4)
	await ld.finished
	if not _alive():
		return
	# ---- 三、双手把腿拔出来 ----
	state = "pull_legs"
	caption.text = "腿陷在松软的雪里。\n用手，把它拔出来。"
	if is_instance_valid(player.viewmodel):
		player.viewmodel.cinematic = "reach_down"
	var pl := create_tween()
	pl.tween_property(self, "_pitch", -1.3, 0.5)
	await get_tree().create_timer(2.4).timeout
	if not _alive():
		return
	# ---- 四、向后倒在地上 ----
	state = "fall_back"
	caption.text = "身子往后倒下去——"
	if is_instance_valid(player.viewmodel):
		player.viewmodel.cinematic = ""
	var fb := create_tween()
	fb.tween_property(self, "_pitch", 1.25, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fb.parallel().tween_property(self, "_head_y", 0.5, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fb.parallel().tween_property(self, "_roll", 0.35, 0.85)
	await fb.finished
	if not _alive():
		return
	var g_fb: Node = get_node_or_null("/root/Game")
	if is_instance_valid(g_fb) and g_fb.get("sound"):
		var snd: Node = g_fb.get("sound")
		if snd.has_method("play_demolish"):
			snd.call("play_demolish")   # 后背落地的闷响
	# ---- 五、躺着看天 ----
	state = "lie"
	caption.text = "天是白的。不是天亮的那种白。"
	await get_tree().create_timer(1.6).timeout
	if not _alive():
		return
	# ---- 六、记忆洪流（躺着，雪落在脸上）----
	state = "memory"
	caption.text = ""
	player.add_shake(0.4)
	if g_fb:
		g_fb.call("notify", "腿拔出雪坑的一瞬，眩晕袭来——记忆呼啸而过。", "info")
	var sw := create_tween()
	sw.tween_property(player, "rotation:y", player.rotation.y + 1.2, 6.0)
	for t in MEMORY_SNIPPETS:
		var f := create_tween()
		f.tween_property(flash, "color:a", 0.85, 0.12)
		f.tween_property(flash, "color:a", 0.0, 0.7)
		caption.text = t
		var c := create_tween()
		c.tween_property(caption, "modulate:a", 1.0, 0.25)
		c.tween_interval(0.9)
		c.tween_property(caption, "modulate:a", 0.0, 0.5)
		await get_tree().create_timer(1.7).timeout
		# 等待期间场景可能已重载：自检后再继续
		if not _alive():
			return
	caption.text = ""
	if not _alive():
		return
	# ---- 七、撑起来 ----
	state = "push_up"
	caption.text = "撑起来。"
	if is_instance_valid(player.viewmodel):
		player.viewmodel.cinematic = "push_up"
	var pu := create_tween()
	pu.tween_property(self, "_pitch", 0.0, 1.4)
	pu.parallel().tween_property(self, "_head_y", 1.62, 1.4)
	pu.parallel().tween_property(self, "_roll", 0.0, 0.8)
	await pu.finished
	if not _alive():
		return
	if is_instance_valid(player.viewmodel):
		player.viewmodel.cinematic = ""
	if g_fb and g_fb.get("sound"):
		var snd2: Node = g_fb.get("sound")
		if snd2.has_method("play_place"):
			snd2.call("play_place")
	_name_input()

func _name_input() -> void:
	state = "name"
	panel.visible = true
	for c in panel.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var t := Label.new()
	t.text = "记忆落定。\n你想起了自己的名字——亲手把它写下来。"
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 17)
	vb.add_child(t)
	var input := LineEdit.new()
	input.placeholder_text = "你的名字"
	input.custom_minimum_size = Vector2(0, 40)
	vb.add_child(input)
	var btn := Button.new()
	btn.text = "就是这个名字"
	btn.custom_minimum_size = Vector2(0, 44)
	btn.pressed.connect(func():
		var n := input.text.strip_edges()
		var g_ni: Node = get_node_or_null("/root/Game")
		if g_ni:
			g_ni.set("player_name", n if n != "" else "幸存者")
			if n == "":
				g_ni.call("notify", "名字卡在喉咙里。往后，就叫你幸存者吧。", "info")
		_choose_profession()
	)
	vb.add_child(btn)

func _choose_profession() -> void:
	state = "profession"
	for c in panel.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var t := Label.new()
	t.text = "前世被冰冻之前的碎片浮上来——\n你是做什么的？（决定随身工具与常识）"
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 17)
	vb.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	vb.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	for pid in Professions.ids():
		var d := Professions.def(pid)
		var b := Button.new()
		b.text = "%s —— %s" % [String(d.get("name", "")), String(d.get("perk", ""))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_pick_profession.bind(pid))
		inner.add_child(b)

func _pick_profession(pid: String) -> void:
	var g_pp: Node = get_node_or_null("/root/Game")
	if g_pp:
		g_pp.set("profession", pid)
		for tool in Professions.tools_of(pid):
			g_pp.call("add_item", tool, 1)
		if not bool(g_pp.call("has_fire_source")):
			g_pp.call("add_item", "matches", 3)
		g_pp.call("notify", "身上还带着趁手的工具：%s。" % "、".join(Professions.tools_of(pid).map(func(x): return Items.name_of(x))), "good")
	_finish_intro()

func _finish_intro() -> void:
	state = "done"
	panel.visible = false
	caption.text = ""
	sub.text = ""
	visible = false
	var g_fi: Node = get_node_or_null("/root/Game")
	if g_fi:
		g_fi.call("set_flag", "intro_done", true)
		g_fi.set("started", true)
	player.control_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 2.0)
	if g_fi:
		g_fi.call("notify", "你站在被削顶的街道上。雪很安静。\n先四处搜刮（左键长按）：枯树给木头，冰岩给石头和冰。", "clue")
		g_fi.call("notify", "第一天。先搜刮，再生火，再睡下。Tab 背包 · X 制作 · B 建造 · Esc 看操作说明。", "info")
