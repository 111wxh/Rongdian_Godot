extends Control
class_name JournalUI
## 日志面板：旧世界记录（线索）/ 同行者 / 处境

var body_vb: VBoxContainer

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.set_deferred("position", Vector2(-340, -300))
	panel.set_deferred("size", Vector2(680, 600))
	panel.add_theme_stylebox_override("panel", _sb())
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := Label.new()
	title.text = "日 志"
	title.add_theme_font_size_override("font_size", 22)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var btn_close := Button.new()
	btn_close.text = "收起 (J)（上方标签可鼠标点选切换面板）"
	btn_close.pressed.connect(func():
		visible = false
		_hud().call("_close_all"))
	head.add_child(btn_close)
	var tab_hint := Label.new()
	tab_hint.text = "（上方标签可鼠标点选切换面板）"
	tab_hint.add_theme_font_size_override("font_size", 12)
	tab_hint.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	head.add_child(tab_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	body_vb = VBoxContainer.new()
	body_vb.add_theme_constant_override("separation", 8)
	body_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body_vb)

func _sb() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.09, 0.13, 0.92)
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s

func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	body_vb.add_child(l)

func _para(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	body_vb.add_child(l)

func refresh() -> void:
	for c in body_vb.get_children():
		c.queue_free()
	var g_rf: Node = _g()
	var companions: Variant = g_rf.get("companions")
	var clues: Variant = g_rf.get("clues")
	var shelter_level: int = int(g_rf.get("shelter_level"))
	var has_home: bool = bool(g_rf.get("has_home"))
	var home_type: String = String(g_rf.get("home_type"))
	var day: int = int(g_rf.get("day"))
	var hour: float = float(g_rf.get("hour"))
	var next_disaster_day: float = float(g_rf.get("next_disaster_day"))
	# 处境
	_section("处境")
	_para("第 %d 天 · %s\n家：%s（%d 级 %s）\n同行者：%d 人 · 线索：%d / 12\n距下一次天灾：约 %.1f 天" % [
		day, String(g_rf.call("time_text")),
		home_type if has_home else "尚未落脚",
		shelter_level, BuildingDefs.level_name(shelter_level),
		int(companions.size()), int(clues.size()),
		maxf(0.0, next_disaster_day - (float(day) + hour / 24.0)),
	], Color(0.85, 0.9, 0.96))
	# 同行者
	_section("同行者")
	if companions.is_empty():
		_para("还没有人留下。火边的影子只有你一个。", Color(0.7, 0.76, 0.85))
	else:
		for c in companions:
			var skill := String(c.def.get("skill", ""))
			var skill_name: String = {"builder": "搭房子省料", "medic": "医护稳妥", "scout": "识路识迹", "electrician": "懂电与终端", "teacher": "讲述安人心", "cook": "烹煮有方"}.get(skill, skill)
			_para("%s（%s）——%s" % [c.npc_name(), String(c.def.get("profession", "")), skill_name], Color(0.85, 0.9, 0.96))
	# 线索
	_section("旧世界的记录（%d / 12）" % int(clues.size()))
	var found := 0
	for id in StoryLogs.LOGS:
		var e := StoryLogs.entry(id)
		if clues.has(id):
			found += 1
			_para("【%s】%s" % [e.title, e.text], Color(0.88, 0.92, 0.98))
		else:
			_para("【？？？】还没找到。（第 %d 区附近）" % int(e.get("district", 0)), Color(0.55, 0.6, 0.68))
	if found == 0:
		_para("纸页散落在各处。便利店、废墟、冰下的角落。", Color(0.7, 0.76, 0.85))
	# 幸存者动向
	_section("听说过的人")
	for sid in Survivors.ids():
		var d := Survivors.def(sid)
		var joined := false
		for c in companions:
			if c.sid == sid:
				joined = true
		if joined:
			_para("%s —— 已经在你身边。" % String(d.get("name", "")), Color(0.8, 0.95, 0.8))
		elif bool(g_rf.call("get_flag", "met_" + sid)):
			_para("%s —— 解冻了，还没留下。" % String(d.get("name", "")), Color(0.9, 0.9, 0.8))
		else:
			_para("%s —— 还没有踪迹。" % String(d.get("name", "")), Color(0.55, 0.6, 0.68))

func _g() -> Node:
	return get_node_or_null("/root/Game")

func _hud() -> Node:
	var hud: Node = get_node_or_null("/root/Main/HUD")
	return hud if is_instance_valid(hud) else null
