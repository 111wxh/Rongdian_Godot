extends Control
class_name CraftingUI
## 制作面板：已知配方列表 / 材料校验 / 火边限制

var list_vb: VBoxContainer
var detail_lbl: Label
var selected := ""
var make_btn: Button

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.set_deferred("position", Vector2(-340, -290))
	panel.set_deferred("size", Vector2(680, 580))
	panel.add_theme_stylebox_override("panel", _sb())
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := Label.new()
	title.text = "制 作"
	title.add_theme_font_size_override("font_size", 22)
	head.add_child(title)
	var hint := Label.new()
	hint.text = "（标「火边」的，要挨着火源做 · 上方标签可鼠标点选切换面板）"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	head.add_child(hint)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var btn_close := Button.new()
	btn_close.text = "收起 (X)（上方标签可鼠标点选切换面板）"
	btn_close.pressed.connect(func(): visible = false; _hud().call("_close_all"))
	head.add_child(btn_close)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 420)
	body.add_child(scroll)
	list_vb = VBoxContainer.new()
	list_vb.add_theme_constant_override("separation", 6)
	list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vb)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	detail_lbl = Label.new()
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.custom_minimum_size = Vector2(0, 200)
	detail_lbl.add_theme_color_override("font_color", Color(0.8, 0.86, 0.94))
	right.add_child(detail_lbl)
	make_btn = Button.new()
	make_btn.text = "制 作"
	make_btn.custom_minimum_size = Vector2(0, 44)
	make_btn.pressed.connect(_on_make)
	right.add_child(make_btn)

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
	var g_rf: Node = _g()
	var all_ids: Array = Recipes.all_ids()
	for rid in all_ids:
		if not bool(g_rf.call("knows_recipe", rid)):
			continue
		var r := Recipes.def(rid)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var station := String(r.get("station", ""))
		var tag := "（火边）" if station == "fire" else ""
		var afford := Recipes.can_make(rid)
		b.text = ("%s %s" % [Recipes.name_of(rid), tag]) if afford else ("%s %s · 材料不足" % [Recipes.name_of(rid), tag])
		if not afford:
			b.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		b.pressed.connect(_on_select.bind(rid))
		list_vb.add_child(b)
	if selected == "" or not bool(g_rf.call("knows_recipe", selected)):
		selected = all_ids[0] if all_ids.size() > 0 else ""
	_show_detail()

func _on_select(rid: String) -> void:
	selected = rid
	_show_detail()

func _show_detail() -> void:
	if selected == "":
		detail_lbl.text = "还没有会做的做法。"
		make_btn.disabled = true
		return
	var g_sd: Node = _g()
	var r := Recipes.def(selected)
	var lines := ["【%s】" % Recipes.name_of(selected), String(r.get("desc", "")), ""]
	for id in r.get("inputs", {}):
		var need := int(r.inputs[id])
		var have := int(g_sd.call("count_item", String(id)))
		lines.append("· %s  %d/%d" % [Items.name_of(String(id)), have, need])
	if String(r.get("station", "")) == "fire":
		lines.append("· 需要：挨着火源")
	if Recipes.is_build(selected):
		lines.append("· 制成后进入放置")
	detail_lbl.text = "\n".join(lines)
	var ok := Recipes.can_make(selected) and Recipes.station_ok(selected)
	make_btn.disabled = not ok
	make_btn.text = "制 作" if ok else "条件不足"

func _on_make() -> void:
	if selected == "":
		return
	# 统一走 Game.craft_recipe（与背包徒手合成同一执行器，不再各写一份）
	var g_mk: Node = _g()
	var r: Dictionary = g_mk.call("craft_recipe", selected)
	if not r.get("ok", false):
		g_mk.call("notify", String(r.get("why", "")), "bad")
		return
	if r.has("build"):
		var key := String(r["build"])
		g_mk.call("notify", "料备齐了。选个好位置放下它。", "info")
		visible = false
		var h_mk: Node = _hud()
		if is_instance_valid(h_mk) and h_mk.has_method("open_build_with"):
			h_mk.call("open_build_with", key)
		return
	var out := String(r.get("out", ""))
	var dh: float = float(r.get("heat", 0.0))
	if dh != 0.0:
		if dh < 0.0:
			g_mk.call("notify", "相变吸热，营地凉了一截。", "info")
		else:
			g_mk.call("notify", "相变放热，营地暖了一截。", "info")
	g_mk.call("notify", "做成了：%s。" % Items.name_of(out), "good")
	refresh()

func _g() -> Node:
	return get_node_or_null("/root/Game")

func _hud() -> Node:
	var hud: Node = get_node_or_null("/root/Main/HUD")
	return hud if is_instance_valid(hud) else null
