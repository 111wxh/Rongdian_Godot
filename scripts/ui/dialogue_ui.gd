extends Control
class_name DialogueUI
## 交涉面板：交谈 / 询问 / 邀请留下（去日程化——火边坐下就能谈）

var npc: SurvivorNPC = null
var name_lbl: Label
var text_lbl: Label
var options_vb: VBoxContainer

const CHITCHAT := [
	"外头的风，比昨天更尖了。",
	"你身上有火的味道。好事。",
	"我数过，这条街一共有七盏不亮的路灯。",
	"冰底下偶尔有声音。不像风。",
	"饿了就说。我这儿还有半份冻肉。",
]

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.set_deferred("position", Vector2(-360, -330))
	panel.set_deferred("size", Vector2(720, 300))
	panel.add_theme_stylebox_override("panel", _sb())
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	name_lbl = Label.new()
	name_lbl.add_theme_font_size_override("font_size", 20)
	vb.add_child(name_lbl)
	text_lbl = Label.new()
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.custom_minimum_size = Vector2(0, 90)
	text_lbl.add_theme_font_size_override("font_size", 15)
	text_lbl.add_theme_color_override("font_color", Color(0.88, 0.91, 0.96))
	vb.add_child(text_lbl)
	options_vb = VBoxContainer.new()
	options_vb.add_theme_constant_override("separation", 6)
	vb.add_child(options_vb)

func _sb() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.09, 0.13, 0.94)
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s

func open_with(n) -> void:
	npc = n
	visible = true
	_refresh()

func _refresh() -> void:
	if npc == null:
		return
	name_lbl.text = "%s（%s）" % [npc.npc_name(), String(npc.def.get("profession", ""))]
	var state := String(npc.state)
	if state == "free":
		text_lbl.text = "「%s」" % String(npc.def.get("hello", "……"))
	elif state == "joined":
		text_lbl.text = "「又在火边坐下了。这儿越来越像个家了。」"
	else:
		text_lbl.text = "「……」"
	for c in options_vb.get_children():
		c.queue_free()
	_add_option("问问近况", _chitchat_line())
	_add_option("问问她/他的事", _need_line())
	if npc.state == "free":
		_add_option("邀请留下", _invite_line(), _on_invite)
	elif npc.state == "joined":
		_add_option("聊一聊这条街", _clue_line())
	_add_option("结束交谈", "你站起身。", _close)

func _add_option(text: String, response: String, act: Callable = Callable()) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if act.is_valid():
		b.pressed.connect(act)
	else:
		b.pressed.connect(func(): text_lbl.text = "「%s」" % response)
	options_vb.add_child(b)

func _chitchat_line() -> String:
	return CHITCHAT[randi() % CHITCHAT.size()]

func _need_line() -> String:
	return String(npc.def.get("need_text", "她没说什么，只是看着火。"))

func _clue_line() -> String:
	var clues: Variant = _g().get("clues")
	if int(clues.size()) >= 8:
		return "终端的卦位，还差最后几页纸。快齐了。"
	return "散落的纸页我见过几张。拼起来，说的是同一件事：冰不是天灾，是实验。"

func _invite_line() -> String:
	var chk: Dictionary = npc.join_check()
	if chk.ok:
		return "她/他沉默了一会儿，点了头。"
	return String(chk.reason)

func _on_invite() -> void:
	var chk: Dictionary = npc.join_check()
	if chk.ok:
		npc.join()
		_refresh()
	else:
		text_lbl.text = "「%s」" % String(chk.reason)

func _close() -> void:
	visible = false
	var h_cl: Node = get_node_or_null("/root/Main/HUD")
	if is_instance_valid(h_cl):
		h_cl.call("_close_all")

func _g() -> Node:
	return get_node_or_null("/root/Game")
