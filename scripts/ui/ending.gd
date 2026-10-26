extends Control
class_name EndingUI
## 结局 / 死亡画面

var title_lbl: Label
var text_lbl: Label
var stats_lbl: Label
var cont_btn: Button

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.02, 0.04, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.set_deferred("position", Vector2(-380, -240))
	vb.set_deferred("size", Vector2(760, 480))
	vb.add_theme_constant_override("separation", 18)
	add_child(vb)
	var spacer_t := Control.new()
	spacer_t.custom_minimum_size = Vector2(0, 40)
	vb.add_child(spacer_t)
	title_lbl = Label.new()
	title_lbl.add_theme_font_size_override("font_size", 40)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title_lbl)
	text_lbl = Label.new()
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.add_theme_font_size_override("font_size", 16)
	text_lbl.add_theme_color_override("font_color", Color(0.82, 0.87, 0.94))
	text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(text_lbl)
	stats_lbl = Label.new()
	stats_lbl.add_theme_font_size_override("font_size", 14)
	stats_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(stats_lbl)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	cont_btn = Button.new()
	cont_btn.text = "继续活在这个世界"
	cont_btn.custom_minimum_size = Vector2(220, 44)
	cont_btn.pressed.connect(_on_continue)
	hb.add_child(cont_btn)
	var restart := Button.new()
	restart.text = "重新开始"
	restart.custom_minimum_size = Vector2(160, 44)
	restart.pressed.connect(func(): get_tree().reload_current_scene())
	hb.add_child(restart)

func play_ending(id: String) -> void:
	var g_pe: Node = get_node_or_null("/root/Game")
	var e := Endings.entry(id)
	title_lbl.text = "—— %s ——" % String(e.get("title", ""))
	var body := String(e.get("text", ""))
	# 真相结局附证据完整度与三假说吻合度（只给吻合度，不给对错）
	if id in ["observer", "restorer", "liberator", "mixed"]:
		body += Endings.completeness_note()
	text_lbl.text = body
	var coh := Evidence.all_coherence()
	var companions: Variant = g_pe.get("companions") if g_pe else []
	var player_name: String = String(g_pe.get("player_name")) if g_pe else ""
	if player_name == "":
		player_name = "无名之人"
	stats_lbl.text = "第 %d 天 · 庇护所 %s（%d 级）· 同行者 %d 人 · 证据 %d/16\n假说吻合度——自然耦合 %d%%（%s） · 干预失控 %d%%（%s） · 有意封存 %d%%（%s）\n%s" % [
		int(g_pe.get("day")) if g_pe else 0,
		String(g_pe.get("home_type")) if g_pe and bool(g_pe.get("has_home")) else "无",
		int(g_pe.get("shelter_level")) if g_pe else 0,
		int(companions.size()),
		Evidence.held_count(),
		int(coh.get("h1", 0.0) * 100), Evidence.coherence_text(coh.get("h1", 0.0)),
		int(coh.get("h2", 0.0) * 100), Evidence.coherence_text(coh.get("h2", 0.0)),
		int(coh.get("h3", 0.0) * 100), Evidence.coherence_text(coh.get("h3", 0.0)),
		player_name,
	]
	cont_btn.visible = id != Endings.death_id()
	visible = true
	if g_pe:
		g_pe.set("game_over", id == Endings.death_id())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_continue() -> void:
	visible = false
	var h_oc: Node = get_node_or_null("/root/Main/HUD")
	if is_instance_valid(h_oc):
		h_oc.call("_close_all")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
