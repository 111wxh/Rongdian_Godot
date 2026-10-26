extends Control
class_name BuildUI
## 建造面板：可选建筑 / 材料预览 / 放置入口

var list_vb: VBoxContainer
var detail_lbl: Label
var place_btn: Button
var selected := "wood_wall"
var bp_name_edit: LineEdit
var bp_list_vb: VBoxContainer

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.set_deferred("position", Vector2(-330, -330))
	panel.set_deferred("size", Vector2(660, 660))
	panel.add_theme_stylebox_override("panel", _sb())
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := Label.new()
	title.text = "建 造"
	title.add_theme_font_size_override("font_size", 22)
	head.add_child(title)
	var hint := Label.new()
	hint.text = "以现成为地基，把家一点点垒起来"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	head.add_child(hint)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var btn_close := Button.new()
	btn_close.text = "收起 (B)（上方标签可鼠标点选切换面板）"
	btn_close.pressed.connect(func():
		visible = false
		_hud().call("_close_all"))
	head.add_child(btn_close)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 400)
	body.add_child(scroll)
	list_vb = VBoxContainer.new()
	list_vb.add_theme_constant_override("separation", 6)
	list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vb)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(280, 0)
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	detail_lbl = Label.new()
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.custom_minimum_size = Vector2(0, 180)
	detail_lbl.add_theme_color_override("font_color", Color(0.8, 0.86, 0.94))
	right.add_child(detail_lbl)
	place_btn = Button.new()
	place_btn.text = "开 始 放 置"
	place_btn.custom_minimum_size = Vector2(0, 46)
	place_btn.pressed.connect(_on_place)
	right.add_child(place_btn)
	var rules := Label.new()
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_font_size_override("font_size", 12)
	rules.add_theme_color_override("font_color", Color(0.62, 0.7, 0.8))
	rules.text = "放置中：左键/E 落位 · R 旋转 · 滚轮调节墙/地板长度 · 右键/Esc 返回\n结构件（墙/地板/柱/顶）可严丝合缝拼装；幽灵变红=材料不够或位置被占。\n庇护所由系统判定：墙越齐、有顶、有火、有床有箱，级数越高。\n（上方标签可鼠标点选切换面板）"
	right.add_child(rules)
	# ---- 图纸区：自绘复用 / 一键导入他人 ----
	var bp_section := VBoxContainer.new()
	bp_section.add_theme_constant_override("separation", 6)
	vb.add_child(bp_section)
	var bp_title := Label.new()
	bp_title.text = "图 纸（把家存下来，或一键复刻别人的）"
	bp_title.add_theme_font_size_override("font_size", 15)
	bp_title.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	bp_section.add_child(bp_title)
	var bp_save_row := HBoxContainer.new()
	bp_save_row.add_theme_constant_override("separation", 6)
	bp_section.add_child(bp_save_row)
	bp_name_edit = LineEdit.new()
	bp_name_edit.placeholder_text = "给当前布置起个名"
	bp_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bp_name_edit.custom_minimum_size = Vector2(0, 34)
	bp_save_row.add_child(bp_name_edit)
	var bp_save_btn := Button.new()
	bp_save_btn.text = "存为图纸"
	bp_save_btn.custom_minimum_size = Vector2(90, 34)
	bp_save_btn.pressed.connect(_on_save_blueprint)
	bp_save_row.add_child(bp_save_btn)
	bp_list_vb = VBoxContainer.new()
	bp_list_vb.add_theme_constant_override("separation", 4)
	var bp_scroll := ScrollContainer.new()
	bp_scroll.custom_minimum_size = Vector2(0, 120)
	bp_scroll.add_child(bp_list_vb)
	bp_section.add_child(bp_scroll)
	var bp_note := Label.new()
	bp_note.text = "图纸只描述想建成什么样——料够、地形允许，才落得成。"
	bp_note.add_theme_font_size_override("font_size", 12)
	bp_note.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	bp_section.add_child(bp_note)

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

func refresh() -> void:
	for c in list_vb.get_children():
		c.queue_free()
	for key in BuildingDefs.keys():
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var ok := BuildingDefs.can_afford(key)
		b.text = BuildingDefs.name_of(key) if ok else "%s · 材料不足" % BuildingDefs.name_of(key)
		if not ok:
			b.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		b.pressed.connect(_on_select.bind(key))
		list_vb.add_child(b)
	_show_detail()
	_refresh_blueprints()

func _on_select(key: String) -> void:
	selected = key
	_show_detail()

func _show_detail() -> void:
	var g_sd: Node = _g()
	var d := BuildingDefs.def(selected)
	var lines := ["【%s】" % BuildingDefs.name_of(selected)]
	for id in d.get("cost", {}):
		lines.append("· %s  %d/%d" % [Items.name_of(String(id)), int(g_sd.call("count_item", String(id))), int(d.cost[id])])
	if bool(d.get("fire", false)):
		lines.append("· 火源：半径内持续回暖")
	if bool(d.get("bed", false)):
		lines.append("· 可以睡下")
	if bool(d.get("roof", false)):
		lines.append("· 挡雪挡风（算作有顶）")
	if bool(d.get("storage", false)):
		lines.append("· 囤货更稳")
	# 高级营地建筑：热力学信息（建造即热消耗）
	if bool(d.get("advanced", false)):
		var w: float = float(d.get("heat_out_w", 0.0))
		if w > 0.0:
			lines.append("· 热产出：+%d W（计入营地 Q_in）" % int(w))
		var hc: float = float(d.get("heat_cost", 0.0))
		if hc != 0.0:
			lines.append("· 建造抽取热量：%d J" % int(hc))
		var bt: float = float(d.get("build_time", 0.0))
		if bt > 0.0:
			lines.append("· 建造耗时：%d 秒 · 人力 %d" % [int(bt), int(d.get("labor", 1))])
		var tech := String(d.get("unlock_tech", ""))
		if tech != "":
			lines.append("· 解锁：%s" % tech)
	var sl: int = int(g_sd.get("shelter_level"))
	lines.append("")
	lines.append("当前庇护所：%s（%d 级）" % [BuildingDefs.level_name(sl), sl])
	detail_lbl.text = "\n".join(lines)
	place_btn.disabled = not BuildingDefs.can_afford(selected)

func _on_place() -> void:
	if not BuildingDefs.can_afford(selected):
		_g().call("notify", "材料不够。", "bad")
		return
	visible = false
	var h_op: Node = _hud()
	if is_instance_valid(h_op) and h_op.has_method("open_build_with"):
		h_op.call("open_build_with", selected)

func select_key(key: String) -> void:
	selected = key
	_show_detail()

# ---------- 图纸 ----------

func _refresh_blueprints() -> void:
	if bp_list_vb == null:
		return
	for c in bp_list_vb.get_children():
		c.queue_free()
	var g_rb: Node = _g()
	var bps: Variant = g_rb.get("blueprints")
	for i in bps.size():
		var bp: Dictionary = bps[i]
		var layout: Array = bp.get("layout", [])
		_add_bp_row(String(bp.get("name", "无名图纸")), "自绘 · %d 件" % layout.size(),
			func(): _on_place_blueprint(bp), func(): _on_delete_blueprint(i))
	for bp2 in BlueprintPresets.all():
		_add_bp_row("%s（%s）" % [String(bp2.get("name", "")), String(bp2.get("author", ""))],
			String(bp2.get("desc", "")), func(): _on_place_blueprint(bp2), Callable())

func _add_bp_row(title: String, desc: String, on_place: Callable, on_delete: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	var d := Label.new()
	d.text = desc
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.add_theme_font_size_override("font_size", 12)
	d.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))
	row.add_child(d)
	var pb := Button.new()
	pb.text = "放置"
	pb.custom_minimum_size = Vector2(56, 28)
	pb.pressed.connect(on_place)
	row.add_child(pb)
	if on_delete.is_valid():
		var db := Button.new()
		db.text = "删"
		db.custom_minimum_size = Vector2(36, 28)
		db.pressed.connect(on_delete)
		row.add_child(db)
	bp_list_vb.add_child(row)

func _on_save_blueprint() -> void:
	var g_bs: Node = _g()
	var player_node: Node = g_bs.get("player")
	if not is_instance_valid(player_node) or player_node.get("builder") == null:
		return
	var buildings: Variant = g_bs.get("buildings")
	if not bool(g_bs.get("has_home")) or buildings.is_empty():
		g_bs.call("notify", "家里还空着，没什么可存的。", "bad")
		return
	var n := bp_name_edit.text.strip_edges() if bp_name_edit else ""
	if n == "":
		n = "图纸 %d" % (g_bs.get("blueprints").size() + 1)
	var bps: Variant = g_bs.get("blueprints")
	bps.append(player_node.get("builder").capture_blueprint(n))
	g_bs.call("notify", "图纸「%s」存好了。随时能一键复刻。" % n, "good")
	if bp_name_edit:
		bp_name_edit.text = ""
	_refresh_blueprints()

func _on_place_blueprint(bp: Dictionary) -> void:
	var g_bp: Node = _g()
	var player_node: Node = g_bp.get("player")
	if not is_instance_valid(player_node) or player_node.get("builder") == null:
		return
	var r: Dictionary = player_node.get("builder").apply_blueprint(bp)
	var sl: int = int(g_bp.get("shelter_level"))
	if r.get("ok", false):
		g_bp.call("notify", "照着「%s」落成了。\n庇护所：%s（%d 级）" % [
			String(bp.get("name", "")), BuildingDefs.level_name(sl), sl], "good")
		refresh()
	else:
		g_bp.call("notify", String(r.get("why", "")), "bad")

func _on_delete_blueprint(i: int) -> void:
	var g_db: Node = _g()
	var bps: Variant = g_db.get("blueprints")
	if i < 0 or i >= bps.size():
		return
	var bp: Dictionary = bps[i]
	bps.remove_at(i)
	g_db.call("notify", "图纸「%s」撕了。" % String(bp.get("name", "")), "info")
	_refresh_blueprints()

func _g() -> Node:
	return get_node_or_null("/root/Game")

func _hud() -> Node:
	var hud: Node = get_node_or_null("/root/Main/HUD")
	return hud if is_instance_valid(hud) else null
