extends CanvasLayer
class_name HUD
## HUD：体感状态 / 通知 / 目标 / 面板调度 / 菜单 / 结局与死亡画面

var lbl_time: Label
var lbl_weather: Label
var lbl_objective: Label
var lbl_prompt: Label
var lbl_home: Label
var lbl_team: Label
var crosshair: Control
var gather_root: Control      ## 采集进度条底板（长按 E 时贴在准星下方）
var gather_fill: ColorRect    ## 采集进度条填充
var wheel_root: Control       ## 快捷轮盘（按住鼠标中键）
var wheel_lbl: Label
var wheel_btns := []
var _wheel_open := false
var _wheel_sel := -1
var _wheel_ents := []
var bars := {}
var notes_vbox: VBoxContainer
var toast_lbl: Label
var cold_vig: ColorRect
var hurt_vig: ColorRect
var hints_lbl: Label
var menu_panel: PanelContainer
var center_toast: PanelContainer
var stats_root: VBoxContainer
var panel_tabs: HBoxContainer      ## 面板页签（背包/制作/建造/日志）：鼠标可点切换
var _tab_panels := {}              ## 页签 key -> 面板节点
var _tab_btns := {}                ## 页签 key -> Button
var help_layer: PanelContainer     ## 操作说明层（主菜单/暂停菜单共用）

var inv_ui: InventoryUI
var craft_ui: CraftingUI
var build_ui: BuildUI
var journal_ui: JournalUI
var dialogue_ui: DialogueUI
var intro: IntroUI
var ending_layer: EndingUI

var _open_panels := 0
var _idle_t := 0.0   ## 闲置计时（秒）：超过 DV.HUD_IDLE_HIDE 隐藏交互层
## 通知列表，元素为 {"label": Control, "tw": Tween}——必须存 tween，
## 提前移除通知时先 kill 动画再释放节点（否则 tween 向已释放 Label 赋值报错）
var _notes := []
var _prompt_sample_cd := 0.0
var _prompt_bg_lum := -1.0

func _ready() -> void:
	var g_rd: Node = get_node_or_null("/root/Game")
	if g_rd:
		g_rd.set("hud", self)
	_build_ui()

func _exit_tree() -> void:
	# 场景重载：旧 HUD 离开时释放全局引用（仅当指向自己，避免误清新 HUD）
	var g_et: Node = get_node_or_null("/root/Game")
	if g_et and g_et.get("hud") == self:
		g_et.set("hud", null)

# =====================================================================
# UI 构建
# =====================================================================

func _label(text: String, size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	# 统一细描边：冰原/暴风雪/极光背景下保证可读（prompt/通知会覆盖为更粗的描边）
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	return l

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.13, 0.82)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _build_ui() -> void:
	# 顶部左：时间天气
	var tl := VBoxContainer.new()
	tl.set_deferred("position", Vector2(16, 12))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tl)
	lbl_time = _label("", 20, Color(0.92, 0.95, 1.0))
	tl.add_child(lbl_time)
	lbl_weather = _label("", 14, Color(0.7, 0.78, 0.88))
	tl.add_child(lbl_weather)
	# 顶部中：目标
	lbl_objective = _label("", 16, Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_objective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl_objective.set_deferred("position", Vector2(-320, 14))
	lbl_objective.set_deferred("size", Vector2(640, 30))
	lbl_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl_objective)
	# 顶部右：家与同行者
	var top_right := VBoxContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.set_deferred("position", Vector2(-280, 12))
	top_right.set_deferred("size", Vector2(264, 60))
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_right)
	lbl_home = _label("", 15, Color(0.9, 0.93, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	top_right.add_child(lbl_home)
	lbl_team = _label("", 15, Color(0.9, 0.93, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	top_right.add_child(lbl_team)
	# 状态条（右上，家面板下方）
	stats_root = VBoxContainer.new()
	stats_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stats_root.set_deferred("position", Vector2(-280, 78))
	stats_root.set_deferred("size", Vector2(264, 140))
	stats_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stats_root)
	stats_root.add_child(_label("身 体", 13, Color(0.65, 0.75, 0.9)))
	for key in ["temp", "hunger", "thirst", "fatigue", "health"]:
		var names := {"temp": "体感温度", "hunger": "饥饿", "thirst": "干渴", "fatigue": "疲惫", "health": "身子"}
		var row := HBoxContainer.new()
		var l := _label(names[key], 13, Color(0.75, 0.82, 0.92))
		l.custom_minimum_size = Vector2(64, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 100.0
		bar.custom_minimum_size = Vector2(150, 12)
		bar.show_percentage = false
		bar.add_theme_stylebox_override("fill", _bar_style(key))
		row.add_child(bar)
		var v := _label("", 12, Color(0.85, 0.9, 0.95))
		v.custom_minimum_size = Vector2(52, 0)
		row.add_child(v)
		stats_root.add_child(row)
		bars[key] = {"bar": bar, "val": v}
	# 十字准星
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.set_deferred("position", Vector2(-3, -3))
	crosshair.set_deferred("size", Vector2(6, 6))
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair)
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.8)
	dot.set_deferred("size", Vector2(6, 6))
	crosshair.add_child(dot)
	# 交互提示（三层可读保障：半透明底板 + 动态对比色 + 反色描边）
	lbl_prompt = _label("", 17, Color(0.95, 0.97, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lbl_prompt.set_deferred("position", Vector2(-300, -110))
	lbl_prompt.set_deferred("size", Vector2(600, 28))
	lbl_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_prompt.add_theme_constant_override("outline_size", 7)
	lbl_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	# 半透明深色底板：无论背景采样是否生效，文字始终有对比
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.03, 0.05, 0.08, 0.52)
	psb.corner_radius_top_left = 6
	psb.corner_radius_top_right = 6
	psb.corner_radius_bottom_left = 6
	psb.corner_radius_bottom_right = 6
	psb.content_margin_left = 14
	psb.content_margin_right = 14
	psb.content_margin_top = 4
	psb.content_margin_bottom = 4
	lbl_prompt.add_theme_stylebox_override("normal", psb)
	add_child(lbl_prompt)
	# 采集进度条：长按 E 采集时出现在准星正下方（森林之子式进度反馈）
	gather_root = Control.new()
	gather_root.set_anchors_preset(Control.PRESET_CENTER)
	gather_root.set_deferred("position", Vector2(-72, 22))
	gather_root.set_deferred("size", Vector2(144, 8))
	gather_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gather_root.visible = false
	add_child(gather_root)
	var gbg := ColorRect.new()
	gbg.color = Color(0.02, 0.03, 0.05, 0.6)
	gbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	gbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gather_root.add_child(gbg)
	gather_fill = ColorRect.new()
	gather_fill.color = Color(0.78, 0.9, 1.0, 0.95)
	gather_fill.set_deferred("position", Vector2(1, 1))
	gather_fill.set_deferred("size", Vector2(0, 6))
	gather_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gather_root.add_child(gather_fill)
	# 快捷轮盘：按住鼠标中键打开（工具/消耗品径向菜单，松开执行悬停项）
	wheel_root = Control.new()
	wheel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	wheel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel_root.visible = false
	add_child(wheel_root)
	var wdim := ColorRect.new()
	wdim.color = Color(0.02, 0.04, 0.07, 0.45)
	wdim.set_anchors_preset(Control.PRESET_FULL_RECT)
	wdim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel_root.add_child(wdim)
	wheel_lbl = Label.new()
	wheel_lbl.set_anchors_preset(Control.PRESET_CENTER)
	wheel_lbl.set_deferred("position", Vector2(-120, -16))
	wheel_lbl.set_deferred("size", Vector2(240, 32))
	wheel_lbl.add_theme_font_size_override("font_size", 17)
	wheel_lbl.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	wheel_lbl.add_theme_constant_override("outline_size", 6)
	wheel_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	wheel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wheel_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel_root.add_child(wheel_lbl)
	# 底部操作提示
	hints_lbl = _label("WASD 移动 · Shift 冲刺 · Ctrl 下蹲 · E 交互 · 左键 采集/捕猎 · 中键 快捷轮盘 · V 审视 · Q 倾听 · 1 喝 2 吃 3 用药 4 换工具 · Tab/X/B/J 背包/制作/建造/日志 · Esc 菜单与说明（上方标签可用鼠标点选切换面板）", 12, Color(0.6, 0.68, 0.78))
	hints_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hints_lbl.set_deferred("position", Vector2(0, -26))
	hints_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints_lbl.add_theme_constant_override("outline_size", 4)
	hints_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	add_child(hints_lbl)
	# 通知
	notes_vbox = VBoxContainer.new()
	notes_vbox.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	notes_vbox.set_deferred("position", Vector2(16, -320))
	notes_vbox.set_deferred("size", Vector2(430, 300))
	notes_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(notes_vbox)
	# 中央大字（线索/回看）
	center_toast = PanelContainer.new()
	center_toast.set_anchors_preset(Control.PRESET_CENTER)
	center_toast.set_deferred("position", Vector2(-300, -90))
	center_toast.set_deferred("size", Vector2(600, 180))
	center_toast.visible = false
	center_toast.add_theme_stylebox_override("panel", _panel_style())
	add_child(center_toast)
	toast_lbl = _label("", 16, Color(0.92, 0.95, 1.0))
	toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center_toast.add_child(toast_lbl)
	# 暗角
	cold_vig = ColorRect.new()
	cold_vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	cold_vig.color = Color(0.25, 0.45, 0.9, 0.0)
	cold_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cold_vig)
	hurt_vig = ColorRect.new()
	hurt_vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_vig.color = Color(0.8, 0.1, 0.1, 0.0)
	hurt_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hurt_vig)
	# 菜单
	_build_menu()
	# 子面板（页签要在它们存在之后才能建）
	inv_ui = load("res://scripts/ui/inventory_ui.gd").new()
	inv_ui.name = "InventoryUI"
	add_child(inv_ui)
	craft_ui = load("res://scripts/ui/crafting_ui.gd").new()
	craft_ui.name = "CraftingUI"
	add_child(craft_ui)
	build_ui = load("res://scripts/ui/build_ui.gd").new()
	build_ui.name = "BuildUI"
	add_child(build_ui)
	journal_ui = load("res://scripts/ui/journal_ui.gd").new()
	journal_ui.name = "JournalUI"
	add_child(journal_ui)
	dialogue_ui = load("res://scripts/ui/dialogue_ui.gd").new()
	dialogue_ui.name = "DialogueUI"
	add_child(dialogue_ui)
	intro = load("res://scripts/ui/intro.gd").new()
	intro.name = "Intro"
	add_child(intro)
	# 结局层
	ending_layer = load("res://scripts/ui/ending.gd").new()
	ending_layer.name = "Ending"
	add_child(ending_layer)
	# 面板页签（鼠标可点切换；快捷键 Tab/X/B/J 保留）
	_build_panel_tabs()
	# 操作说明层
	_build_help()

func _bar_style(key: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var colors := {
		"temp": Color(0.35, 0.75, 0.95),
		"hunger": Color(0.85, 0.65, 0.3),
		"thirst": Color(0.35, 0.6, 0.9),
		"fatigue": Color(0.6, 0.5, 0.85),
		"health": Color(0.8, 0.3, 0.35),
	}
	sb.bg_color = colors.get(key, Color(0.5, 0.5, 0.5))
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	return sb

func _build_menu() -> void:
	var g_bm: Node = get_node_or_null("/root/Game")
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_panel.set_deferred("position", Vector2(-140, -150))
	menu_panel.set_deferred("size", Vector2(280, 300))
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	menu_panel.visible = false
	add_child(menu_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	menu_panel.add_child(vb)
	vb.add_child(_label("融 点", 26, Color(0.9, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	var time_txt := String(g_bm.call("time_text")) if g_bm else ""
	vb.add_child(_label(time_txt, 14, Color(0.7, 0.78, 0.88), HORIZONTAL_ALIGNMENT_CENTER))
	var b_continue := Button.new()
	b_continue.text = "继续（Esc）"
	b_continue.pressed.connect(_close_menu)
	vb.add_child(b_continue)
	var b_save := Button.new()
	b_save.text = "记录此刻（F5）"
	b_save.pressed.connect(func():
		if g_bm:
			g_bm.call("save_game"))
	vb.add_child(b_save)
	var b_load := Button.new()
	b_load.text = "回到上次记录（F9）"
	b_load.pressed.connect(func(): _load_pressed())
	vb.add_child(b_load)
	var b_help := Button.new()
	b_help.text = "操作说明"
	b_help.pressed.connect(func(): _toggle_help(true))
	vb.add_child(b_help)
	var b_restart := Button.new()
	b_restart.text = "重新开始"
	b_restart.pressed.connect(func(): get_tree().reload_current_scene())
	vb.add_child(b_restart)

func _load_pressed() -> void:
	_close_menu()
	var g_lp: Node = get_node_or_null("/root/Game")
	if g_lp:
		g_lp.set("pending_load", true)
	get_tree().reload_current_scene()

# =====================================================================
# 面板页签：背包 / 制作 / 建造 / 日志 —— 鼠标点标签即切换
# （原有快捷键 Tab/X/B/J 完全保留，行为不变）
# =====================================================================

func _build_panel_tabs() -> void:
	panel_tabs = HBoxContainer.new()
	panel_tabs.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel_tabs.set_deferred("position", Vector2(-320, 92))
	panel_tabs.set_deferred("size", Vector2(640, 44))
	panel_tabs.add_theme_constant_override("separation", 8)
	panel_tabs.visible = false
	add_child(panel_tabs)
	_tab_panels = {
		"inv": inv_ui,
		"craft": craft_ui,
		"build": build_ui,
		"journal": journal_ui,
	}
	for key in ["inv", "craft", "build", "journal"]:
		var b := Button.new()
		b.text = _tab_name(key)
		b.custom_minimum_size = Vector2(148, 44)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_on_tab_pressed.bind(key))
		panel_tabs.add_child(b)
		_tab_btns[key] = b
		var panel: Node = _tab_panels[key]
		if panel:
			panel.set_meta("tab_key", key)

func _tab_name(key: String) -> String:
	match key:
		"inv": return "背包 (Tab)"
		"craft": return "制作 (X)"
		"build": return "建造 (B)"
		"journal": return "日志 (J)"
	return key

## 页签被鼠标/键盘按下：打开对应面板并高亮
func _on_tab_pressed(key: String) -> void:
	if not _tab_panels.has(key):
		return
	var target: Control = _tab_panels[key]
	# 再点一次当前页签 = 收起（和快捷键 toggle 行为一致）
	if target.visible:
		_close_all()
		return
	_show_tab(key)

func _show_tab(key: String) -> void:
	if not _tab_panels.has(key):
		return
	_close_all()
	var target: Control = _tab_panels[key]
	target.visible = true
	if target.has_method("refresh"):
		target.call("refresh")
	_open_panels = 1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var g_st: Node = get_node_or_null("/root/Game")
	if g_st:
		g_st.set("build_mode", false)
	_refresh_tab_style()

func _refresh_tab_style() -> void:
	for k in _tab_btns:
		var b: Button = _tab_btns[k]
		if not is_instance_valid(b):
			continue
		if not _tab_panels.has(k) or not is_instance_valid(_tab_panels[k]):
			continue
		var on: bool = _tab_panels[k].visible
		b.button_pressed = on
		b.modulate = Color(1.0, 0.98, 0.9) if on else Color(0.72, 0.78, 0.86)

## 打开某个面板（供快捷键调用）：同时显示页签条
func _toggle_panel(p: Node) -> void:
	var was_open: bool = p.visible
	_close_all()
	if not was_open:
		p.visible = true
		if p.has_method("refresh"):
			p.call("refresh")
		_open_panels = 1
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var g_tp: Node = get_node_or_null("/root/Game")
		if g_tp:
			g_tp.set("build_mode", false)
		if panel_tabs:
			panel_tabs.visible = true
		_refresh_tab_style()

# =====================================================================
# 操作说明层：主菜单与暂停菜单共用，鼠标可点返回
# =====================================================================

func _build_help() -> void:
	help_layer = PanelContainer.new()
	help_layer.set_anchors_preset(Control.PRESET_CENTER)
	help_layer.set_deferred("position", Vector2(-300, -320))
	help_layer.set_deferred("size", Vector2(600, 640))
	help_layer.add_theme_stylebox_override("panel", _panel_style())
	help_layer.visible = false
	add_child(help_layer)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	help_layer.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := _label("操 作 说 明", 22, Color(0.9, 0.95, 1.0))
	head.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := Button.new()
	back.text = "返回（Esc）"
	back.pressed.connect(func(): _toggle_help(false))
	head.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var rows := [
		["W A S D", "移动"],
		["Shift", "冲刺（空手、不累时）"],
		["Ctrl", "下蹲（慢而稳）"],
		["E", "情境交互：对话 / 点火 / 睡下 / 点亮终端"],
		["鼠标左键", "采集 / 砍伐 / 敲凿 / 拢雪 / 捕猎（长按累积）"],
		["鼠标中键", "按住打开快捷轮盘：手电、工具、吃喝用药"],
		["V", "审视四周（3 秒，找旧世界的痕迹）"],
		["Q", "倾听（放慢脚步，听得更远）"],
		["F", "手电"],
		["1 / 2 / 3 / 4", "喝水 / 进食 / 用药 / 换工具"],
		["Tab / X / B / J", "背包 / 制作 / 建造 / 日志"],
		["Esc", "暂停菜单；打开面板时先收起面板"],
		["F5 / F9", "记录此刻 / 回到上次记录"],
	]
	for r in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		body.add_child(h)
		var k := _label(r[0], 14, Color(0.72, 0.86, 1.0))
		k.custom_minimum_size = Vector2(130, 0)
		h.add_child(k)
		var v := _label(r[1], 14, Color(0.82, 0.88, 0.95))
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
	var tip := _label("天冷就找火、找衣服、找背风处；饿了渴了就吃就喝；\n天黑前把家垒起来——庇护所级数越高，睡得越稳。", 13, Color(0.62, 0.72, 0.84))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(tip)

## 显示/隐藏操作说明（open=true 时打开；false 时若是从主菜单来的则回主菜单）
func _toggle_help(open: bool) -> void:
	if not is_instance_valid(help_layer):
		return
	if open:
		help_layer.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# 说明层打开时提升 z_index，保证盖住主菜单面板与四个功能面板
		help_layer.z_index = 200
	else:
		help_layer.visible = false
		# 主菜单开着时，关说明要回到主菜单（鼠标保持可见）
		var g_th: Node = get_node_or_null("/root/Game")
		if Player.title_open:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif not (g_th and bool(g_th.get("game_over"))):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _close_help() -> void:
	if is_instance_valid(help_layer) and help_layer.visible:
		_toggle_help(false)

func reopen_build_menu() -> void:
	_close_all()
	build_ui.visible = true
	if build_ui.has_method("refresh"):
		build_ui.refresh()
	_open_panels = 1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# =====================================================================
# UI 事件队列：Game/场景系统入队，HUD 每帧在自身存活时消费。
# 不再用信号直连——重载场景时广播到已释放 HUD 会报
# "Trying to assign invalid previously freed instance"。
# =====================================================================

func _drain_ui_events() -> void:
	var g_de: Node = get_node_or_null("/root/Game")
	if g_de == null:
		return
	var events: Array = g_de.get("ui_events")
	while not events.is_empty():
		var ev: Dictionary = events.pop_front()
		if not is_inside_tree():
			return  # 已离开场景：剩余事件留给新 HUD
		match String(ev.get("type", "")):
			"notify":
				_show_notify(String(ev.get("text", "")), String(ev.get("kind", "info")))
			"prompt":
				_apply_prompt(String(ev.get("text", "")))
			"shake":
				var p: Node = g_de.get("player")
				if is_instance_valid(p) and p.has_method("add_shake"):
					p.call("add_shake", float(ev.get("amount", 0.0)))

func _show_notify(text: String, kind: String) -> void:
	# 三重保险：树外 / 子节点已释放 / 子节点已标记删除（queue_free 后 flush 前，
	# is_instance_valid 仍为 true 但 add_child 会炸）——任一不满足直接丢弃，
	# 绝不向半死实例赋值（热重载/场景重载时的 freed instance 来源）
	if not is_inside_tree() or not is_instance_valid(notes_vbox) or not notes_vbox.is_inside_tree():
		return
	if kind == "review" or kind == "clue":
		_show_toast(text)
		return
	var l := _label(text, 14, _notify_color(kind))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	# 通知也加半透明底板：白雪/明亮废墟上灰白字同样看不清
	var nb := StyleBoxFlat.new()
	nb.bg_color = Color(0.03, 0.05, 0.08, 0.45)
	nb.corner_radius_top_left = 5
	nb.corner_radius_top_right = 5
	nb.corner_radius_bottom_left = 5
	nb.corner_radius_bottom_right = 5
	nb.content_margin_left = 10
	nb.content_margin_right = 10
	nb.content_margin_top = 5
	nb.content_margin_bottom = 5
	l.add_theme_stylebox_override("normal", nb)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	notes_vbox.add_child(l)
	_notes.append({"label": l, "tw": null})
	var tw := create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	# 双保险：l 可能已被"超出 6 条上限"逻辑提前释放，回调前必须校验
	tw.tween_callback(func(): if is_instance_valid(l): l.queue_free())
	# 回填 tween 引用：提前移除通知时先 kill 动画，否则 tween 会向已释放的 Label 赋值
	# （正是 "Trying to assign invalid previously freed instance" 的来源）
	_notes[-1]["tw"] = tw
	while _notes.size() > 6:
		var old: Dictionary = _notes.pop_front()
		# 用无类型变量接字典里的旧引用：Label 可能已被自己的淡出 tween 释放，
		# 带类型的赋值（var x: Control = 已释放实例）正是
		# "Trying to assign invalid previously freed instance" 的来源
		var old_tw = old.get("tw")
		if old_tw is Tween and old_tw.is_valid():
			old_tw.kill()
		var old_l = old.get("label")
		if is_instance_valid(old_l):
			old_l.queue_free()

func _ui_color(color_id: String, fallback: Color) -> Color:
	## UI 配色统一来源：DV.UI_COLORS（UI_UX 文档规范）
	## 注：参数名用 color_id——"name" 会遮蔽基类 Node.name 属性（编辑器报 shadowing）
	return DV.UI_COLORS.get(color_id, fallback)

func _notify_color(kind: String) -> Color:
	match kind:
		"good": return _ui_color("warm_safe", Color(0.65, 0.95, 0.7))
		"bad": return _ui_color("cold_danger", Color(0.95, 0.6, 0.6))
		"clue": return _ui_color("story", Color(0.7, 0.9, 1.0))
		"review": return _ui_color("rare", Color(1.0, 0.95, 0.75))
	return Color(0.85, 0.88, 0.93)

func _show_toast(text: String) -> void:
	if not is_instance_valid(toast_lbl) or not is_instance_valid(center_toast):
		return
	if not toast_lbl.is_inside_tree() or not center_toast.is_inside_tree():
		return
	toast_lbl.text = text
	center_toast.visible = true
	center_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(center_toast, "modulate:a", 0.0, 1.5)
	tw.tween_callback(func(): if is_instance_valid(center_toast): center_toast.visible = false)

# =====================================================================
# 快捷轮盘（按住鼠标中键）：工具 / 消耗品径向菜单
# =====================================================================

## 轮盘条目：手电（如有）+ 背包里的工具与消耗品，最多 8 项
func _wheel_entries() -> Array:
	var g_we: Node = get_node_or_null("/root/Game")
	if g_we == null:
		return []
	var out := []
	if int(g_we.call("count_item", "flashlight")) > 0 or int(g_we.call("count_item", "battery")) > 0:
		out.append({"kind": "flash", "id": "", "label": "手电"})
	for it in g_we.get("inventory").aggregated():
		var id := String(it.id)
		var cat := Items.cat_of(id)
		if cat == "tool":
			out.append({"kind": "tool", "id": id, "label": Items.name_of(id)})
		elif cat in ["food", "drink", "medical"]:
			out.append({"kind": "item", "id": id, "label": Items.name_of(id)})
		if out.size() >= 8:
			break
	return out

func _open_wheel() -> void:
	_wheel_ents = _wheel_entries()
	if _wheel_ents.is_empty():
		return
	for c in wheel_btns:
		if is_instance_valid(c):
			c.queue_free()
	wheel_btns.clear()
	_wheel_sel = -1
	var r := 110.0
	for i in range(_wheel_ents.size()):
		var ang := -PI / 2.0 + TAU * float(i) / float(_wheel_ents.size())
		var b := Button.new()
		b.text = String(_wheel_ents[i]["label"])
		b.custom_minimum_size = Vector2(96, 40)
		b.set_anchors_preset(Control.PRESET_CENTER)
		b.set_deferred("position", Vector2(cos(ang) * r - 48.0, sin(ang) * r - 20.0))
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx := i
		b.mouse_entered.connect(func(): _wheel_sel = idx; _highlight_wheel())
		b.pressed.connect(func(): _wheel_sel = idx; _close_wheel(true))
		wheel_root.add_child(b)
		wheel_btns.append(b)
	wheel_lbl.text = "快 捷"
	wheel_root.visible = true
	_wheel_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _highlight_wheel() -> void:
	for i in range(wheel_btns.size()):
		var b: Button = wheel_btns[i]
		if not is_instance_valid(b):
			continue
		b.modulate = Color(1.0, 0.95, 0.7) if i == _wheel_sel else Color.WHITE

func _close_wheel(execute: bool) -> void:
	if execute and _wheel_sel >= 0 and _wheel_sel < _wheel_ents.size():
		_wheel_execute(_wheel_ents[_wheel_sel])
	wheel_root.visible = false
	_wheel_open = false
	_wheel_sel = -1
	for c in wheel_btns:
		if is_instance_valid(c):
			c.queue_free()
	wheel_btns.clear()
	var g_cw: Node = get_node_or_null("/root/Game")
	if g_cw and is_instance_valid(g_cw.get("player")) and bool(g_cw.get("started")) and not bool(g_cw.get("game_over")):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _wheel_execute(e: Dictionary) -> void:
	var g_wx: Node = get_node_or_null("/root/Game")
	var player_node: Node = g_wx.get("player") if g_wx else null
	match String(e.get("kind", "")):
		"tool":
			var tid := String(e.get("id", ""))
			if tid != "" and g_wx:
				g_wx.set("active_tool", tid)
				g_wx.call("notify", "手持：%s" % Items.name_of(tid), "info")
		"item":
			var iid := String(e.get("id", ""))
			if iid != "" and is_instance_valid(player_node) and player_node.has_method("_consume"):
				player_node.call("_consume", iid)
		"flash":
			if is_instance_valid(player_node) and player_node.has_method("_toggle_flashlight"):
				player_node.call("_toggle_flashlight")

func _apply_prompt(text: String) -> void:
	if not is_instance_valid(lbl_prompt) or not lbl_prompt.is_inside_tree():
		return
	lbl_prompt.text = text
	lbl_prompt.visible = text != ""
	if text != "":
		# 立即按最近一次采样的背景亮度校正颜色，避免闪现不可读状态
		if _prompt_bg_lum >= 0.0:
			_apply_prompt_contrast(_prompt_bg_lum)

func add_shake(v: float) -> void:
	var g_as: Node = get_node_or_null("/root/Game")
	var player_node: Node = g_as.get("player") if g_as else null
	if is_instance_valid(player_node) and player_node.has_method("add_shake"):
		player_node.call("add_shake", v)

# =====================================================================
# 每帧刷新
# =====================================================================

func _process(delta: float) -> void:
	_drain_ui_events()
	var g_pr: Node = get_node_or_null("/root/Game")
	if g_pr == null or not bool(g_pr.get("started")):
		return
	var player_node: Node = g_pr.get("player")
	var game_over: bool = bool(g_pr.get("game_over"))
	var weather: String = String(g_pr.get("weather"))
	var wind: float = float(g_pr.get("wind"))
	var ambient: float = float(g_pr.get("ambient_temp"))
	var companions: Variant = g_pr.get("companions")
	var home_type: String = String(g_pr.get("home_type"))
	var shelter_level: int = int(g_pr.get("shelter_level"))
	var has_home: bool = bool(g_pr.get("has_home"))
	var day: int = int(g_pr.get("day"))
	# ---- 快捷轮盘：按住鼠标中键打开，松开执行悬停项 ----
	var wdown := Input.is_action_pressed("wheel")
	if wdown and not _wheel_open and _open_panels == 0 and not bool(g_pr.get("build_mode")) and not game_over:
		_open_wheel()
	elif not wdown and _wheel_open:
		_close_wheel(true)
	_update_prompt_contrast(delta)
	lbl_time.text = String(g_pr.call("time_text"))
	var wname: String = {"clear": "寒夜初晴", "snow": "落雪", "blizzard": "暴风雪"}.get(weather, "")
	var wind_txt := "无风" if wind < 0.3 else ("微风" if wind < 1.0 else "大风")
	lbl_weather.text = "%s · %s · 环境 %.0f℃" % [wname, wind_txt, ambient]
	lbl_objective.text = _objective_text()
	lbl_home.text = ("家：%s（%d 级 %s）" % [home_type, shelter_level, BuildingDefs.level_name(shelter_level)]) if has_home else "家：尚未落脚"
	lbl_team.text = "同行者：%d 人" % companions.size()
	# 状态条（第一天不弹数值，只用身体语言）
	var show_numeric := day >= 2
	stats_root.visible = show_numeric
	for key in bars:
		var row: Dictionary = bars[key]
		var bar: ProgressBar = row.bar
		var val: Label = row.val
		match key:
			"temp":
				var t := float(g_pr.get("perceived_temp"))
				bar.value = clampf((t - 28.0) / 12.0 * 100.0, 0.0, 100.0)
				val.text = "%.1f℃" % t
			"hunger":
				var hv := float(g_pr.get("hunger"))
				bar.value = hv
				val.text = "%d%%" % int(hv)
			"thirst":
				var tv := float(g_pr.get("thirst"))
				bar.value = tv
				val.text = "%d%%" % int(tv)
			"fatigue":
				var fv := float(g_pr.get("fatigue"))
				bar.value = fv
				val.text = "%d%%" % int(fv)
			"health":
				var hv2 := float(g_pr.get("health"))
				bar.value = hv2
				val.text = "%d" % int(hv2)
	# 闲置计时（用于交互层淡出）
	_idle_t += delta
	# 交互层（提示+操作提示）在静止 HUD_IDLE_HIDE 秒后隐藏（探索沉浸）
	var idle_hide := _idle_t > DV.HUD_IDLE_HIDE
	if is_instance_valid(lbl_prompt):
		if lbl_prompt.visible and idle_hide and lbl_prompt.text != "":
			lbl_prompt.visible = false
		elif not idle_hide and lbl_prompt.text != "":
			lbl_prompt.visible = true
	if is_instance_valid(hints_lbl):
		hints_lbl.visible = not idle_hide
	# 采集进度（长按 E）：森林之子式，条子贴在准星下，随采集出现/消失
	var gp := 0.0
	if is_instance_valid(player_node) and player_node.has_method("gather_progress"):
		gp = float(player_node.call("gather_progress"))
	gather_root.visible = gp > 0.0
	if gp > 0.0:
		gather_fill.size = Vector2(142.0 * gp, 6.0)
	# 暗角
	var cold_a: float = [0.0, 0.10, 0.2, 0.32][int(g_pr.get("hypothermia_tier"))]
	# 热量危急（HUD_CRITICAL_HEAT）：营地热量赤字且极冷时全 HUD 脉动
	if String(g_pr.get("heat_surplus")) == "deficit" and float(g_pr.get("camp_temp")) < DV.CH01_TEMP * 0.5:
		var pulse := 0.18 + 0.18 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
		cold_vig.color.a = lerpf(cold_vig.color.a, pulse, 0.2)
	else:
		cold_vig.color.a = lerpf(cold_vig.color.a, cold_a, 0.05)
	var hurt_a := 0.0
	if is_instance_valid(player_node) and player_node.has_method("get_hurt_flash"):
		hurt_a = clampf(float(player_node.call("get_hurt_flash")), 0.0, 1.0) * 0.4
	hurt_vig.color.a = lerpf(hurt_vig.color.a, hurt_a, 0.2)

# =====================================================================
# 提示板动态对比色：采样提示板上方的画面亮度，亮底黑字、暗底白字
# =====================================================================

func _update_prompt_contrast(delta: float) -> void:
	if not lbl_prompt.visible:
		return
	_prompt_sample_cd -= delta
	if _prompt_sample_cd > 0.0:
		return
	_prompt_sample_cd = 0.3
	# 无渲染上下文（headless/命令行）时跳过采样，保留默认白字+黑描边
	if DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport()
	var tex: ViewportTexture = vp.get_texture() if vp else null
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	var sz: Vector2i = vp.get_visible_rect().size
	# 采样点：提示板正上方一小块（避开 HUD 自身文字与底部提示行）
	var cx := int(sz.x * 0.5)
	var cy := int(sz.y) - 170
	var x0 := clampi(cx - 10, 0, sz.x - 1)
	var x1 := clampi(cx + 10, 0, sz.x - 1)
	var y0 := clampi(cy - 5, 0, sz.y - 1)
	var y1 := clampi(cy + 5, 0, sz.y - 1)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var c: Color = img.get_pixel(x, y)
			r += c.r
			g += c.g
			b += c.b
			n += 1
	if n == 0:
		return
	_prompt_bg_lum = (0.299 * r + 0.587 * g + 0.114 * b) / float(n)
	_apply_prompt_contrast(_prompt_bg_lum)

## 纯颜色逻辑：按背景亮度选黑/白字，描边取反色，双保险保证可读
func _apply_prompt_contrast(lum: float) -> void:
	if lum >= 0.45:
		lbl_prompt.add_theme_color_override("font_color", Color(0.04, 0.04, 0.05))
		lbl_prompt.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.92))
	else:
		lbl_prompt.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
		lbl_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))

func _objective_text() -> String:
	var g_ob: Node = get_node_or_null("/root/Game")
	if g_ob == null:
		return ""
	if bool(g_ob.get("game_over")):
		return ""
	if bool(g_ob.call("get_flag", "terminal_done")):
		return "火已经点起来了。往后的日子，是你们自己的。"
	# 第一天：给一条能立刻照着做的话，而不是抽象的「找地方过夜」
	if int(g_ob.get("day")) == 1:
		return "第一天：先搜刮（左键长按）→ 找枯树/冰岩弄到木头石头 →  Tab 背包 · X 制作 · B 建造 · Esc 看说明"
	# 注意：这些字段是 Variant，不能显式标成 Array（Game 里的 clues/companions 在
	# 解析环下类型不可见），否则运行期会报 Dictionary→Array 赋值错误
	var clues: Variant = g_ob.get("clues")
	var companions: Variant = g_ob.get("companions")
	if int(clues.size()) >= 8:
		return "目标：去第三区，点亮融点终端（线索 %d/12）" % int(clues.size())
	if not bool(g_ob.get("has_home")):
		return "目标：找一处能过夜的地方，留意别人的痕迹"
	if int(companions.size()) < 2 and int(clues.size()) < 8:
		return "目标：顺脚印找一找还活着的人；把家垒得更严实"
	return "目标：把家弄得更稳，囤水、柴和吃的（线索 %d/12）" % int(clues.size())

# =====================================================================
# 输入：面板开关
# =====================================================================

func _unhandled_input(event: InputEvent) -> void:
	var g_ui: Node = get_node_or_null("/root/Game")
	if g_ui == null or not bool(g_ui.get("started")) or bool(g_ui.get("game_over")):
		return
	_idle_t = 0.0   # 任意操作即重置闲置计时（交互层淡出用）
	if event.is_action_pressed("inventory"):
		_toggle_panel(inv_ui)
	elif event.is_action_pressed("crafting"):
		_toggle_panel(craft_ui)
	elif event.is_action_pressed("build"):
		if bool(g_ui.get("build_mode")):
			_exit_build()
		else:
			_toggle_panel(build_ui)
	elif event.is_action_pressed("journal"):
		_toggle_panel(journal_ui)
	elif event.is_action_pressed("cancel"):
		if is_instance_valid(help_layer) and help_layer.visible:
			_toggle_help(false)
		elif _open_panels > 0:
			_close_all()
		elif not menu_panel.visible:
			_open_menu()
	elif event.is_action_pressed("quick_save"):
		g_ui.call("save_game")
	elif event.is_action_pressed("quick_load"):
		_load_pressed()

func _close_all() -> void:
	var g_ca: Node = get_node_or_null("/root/Game")
	for p in [inv_ui, craft_ui, build_ui, journal_ui, dialogue_ui]:
		p.visible = false
	_open_panels = 0
	if g_ca and not bool(g_ca.get("game_over")) and not Player.title_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if g_ca:
		g_ca.set("build_mode", false)
	if panel_tabs:
		panel_tabs.visible = false
	_refresh_tab_style()

func _exit_build() -> void:
	var g_eb: Node = get_node_or_null("/root/Game")
	if g_eb:
		g_eb.set("build_mode", false)
	build_ui.visible = false
	var player_node: Node = g_eb.get("player") if g_eb else null
	if is_instance_valid(player_node) and player_node.get("builder"):
		player_node.get("builder").call("clear_ghost")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_open_panels = 0
	if panel_tabs:
		panel_tabs.visible = false
	_refresh_tab_style()

func _open_menu() -> void:
	_close_all()
	_close_help()
	menu_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_menu() -> void:
	menu_panel.visible = false
	var g_cm: Node = get_node_or_null("/root/Game")
	if g_cm and not bool(g_cm.get("game_over")) and not Player.title_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## 菜单是否打开（供 player 判断是否该收鼠标/转视角）
func menu_open() -> bool:
	if is_instance_valid(menu_panel) and menu_panel.visible:
		return true
	return is_instance_valid(help_layer) and help_layer.visible

# =====================================================================
# 对外接口
# =====================================================================

func open_dialogue(npc) -> void:
	_close_all()
	_close_help()
	dialogue_ui.open_with(npc)
	dialogue_ui.visible = true
	_open_panels = 1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func open_build_with(key: String) -> void:
	_close_all()
	build_ui.visible = false
	if build_ui.has_method("select_key"):
		build_ui.select_key(key)
	_open_panels = 0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var g_ow: Node = get_node_or_null("/root/Game")
	if g_ow:
		g_ow.set("build_mode", true)
	# 关键：把选中的做法交给 Builder，否则 build_mode 开了但幽灵永远不显示
	var player_node: Node = g_ow.get("player") if g_ow else null
	if is_instance_valid(player_node) and player_node.get("builder"):
		player_node.get("builder").call("set_key", key)

func show_ending(id: String) -> void:
	_close_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ending_layer and ending_layer.has_method("play_ending"):
		ending_layer.play_ending(id)

func show_game_over() -> void:
	_close_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ending_layer and ending_layer.has_method("play_ending"):
		ending_layer.play_ending(Endings.death_id())
