extends Control
class_name MainMenuUI
## 开始页面主菜单：新的游戏 / 继续游戏 / 操作说明 / 退出
## 口径：
## - 只在有窗口的正式运行时出现；无头（headless）测试与读档重载一律不显示，
##   保证 smoke/intro/control/reload/content/systems_test 六套自检路径不变。
## - 全按钮鼠标可选：所有项都是 Button（Godot 默认支持键盘上下 + Enter 聚焦），
##   与「鼠标可进行标签选择」的要求一致。
## - 「继续游戏」复用现有读档流程：置 Game.pending_load 后重载当前场景，
##   main.gd 的 loading 分支会 _apply_save + Game.started=true + 捕获鼠标。

var _root: Control            ## 菜单根（含背景层），隐藏/显示只切它
var _panel: PanelContainer
var _btn_continue: Button
var _page := "menu"             ## 当前页：menu / help（字符串，勿与 Control 变量重名）
var _menu_page: Control
var _help_page: Control

func _ready() -> void:
	visible = false
	z_index = 100
	# 注意：不要在这里对自身 set_anchors_preset + 之后又赋值 size，
	# FULL_RECT 的 anchors 是相对的，交给父容器即可
	call_deferred("_build")

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	# 背景：冰封氛围（深蓝夜幕 + 顶部冷光）
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var glow := ColorRect.new()
	glow.color = Color(0.10, 0.18, 0.30, 0.55)
	glow.set_anchors_preset(Control.PRESET_TOP_WIDE)
	glow.custom_minimum_size = Vector2(0, 320)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(glow)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.set_deferred("position", Vector2(-260, -240))
	_panel.set_deferred("size", Vector2(520, 480))
	_panel.add_theme_stylebox_override("panel", _sb())
	_root.add_child(_panel)

	# 标题
	var title := Label.new()
	title.text = "融  点"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0))
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.set_deferred("position", Vector2(-260, -250))
	title.set_deferred("size", Vector2(520, 80))
	_root.add_child(title)
	var sub := Label.new()
	sub.text = "冰封之后，把人找回来，把火点起来。"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.66, 0.76, 0.88))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.set_deferred("position", Vector2(-260, -176))
	sub.set_deferred("size", Vector2(520, 26))
	_root.add_child(sub)

	_build_menu_page()
	_build_help_page()

# ---------------- 菜单页 ----------------

func _build_menu_page() -> void:
	_menu_page = VBoxContainer.new()
	_menu_page.add_theme_constant_override("separation", 14)
	_menu_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(_menu_page)
	# 顶部留白：标题已在面板外
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 54)
	_menu_page.add_child(pad)

	_btn_continue = _menu_button("继续游戏", _on_continue)
	_btn_continue.disabled = not has_save()
	var tag := Label.new()
	tag.text = "（有一个上次的记录）" if has_save() else "（还没有记录）"
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", Color(0.55, 0.64, 0.76))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_page.add_child(tag)

	_menu_button("新的游戏", _on_new_game)
	_menu_button("操作说明", _on_help)
	_menu_button("退出游戏", _on_quit)
	var foot := Label.new()
	foot.text = "鼠标点选 · 键盘 ↑↓ + Enter 亦可"
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.48, 0.56, 0.68))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_page.add_child(foot)

func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(cb)
	_menu_page.add_child(b)
	return b

# ---------------- 操作说明页 ----------------

func _build_help_page() -> void:
	_help_page = VBoxContainer.new()
	_help_page.add_theme_constant_override("separation", 10)
	_help_page.visible = false
	_panel.add_child(_help_page)
	var head := HBoxContainer.new()
	_help_page.add_child(head)
	var t := Label.new()
	t.text = "操 作 说 明"
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	head.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(_on_back)
	head.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_help_page.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
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
		vb.add_child(h)
		var k := Label.new()
		k.text = r[0]
		k.custom_minimum_size = Vector2(130, 0)
		k.add_theme_font_size_override("font_size", 14)
		k.add_theme_color_override("font_color", Color(0.72, 0.86, 1.0))
		h.add_child(k)
		var v := Label.new()
		v.text = r[1]
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_font_size_override("font_size", 14)
		v.add_theme_color_override("font_color", Color(0.82, 0.88, 0.95))
		h.add_child(v)
	var tip := Label.new()
	tip.text = "天冷就找火、找衣服、找背风处；饿了渴了就吃就喝；\n天黑前把家垒起来——庇护所级数越高，睡得越稳。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color(0.62, 0.72, 0.84))
	vb.add_child(tip)

# ---------------- 对外接口 ----------------

## 是否有存档（与 Game.load_game 同口径：SAVE_PATH 文件存在即可读）
func has_save() -> bool:
	var g := get_node_or_null("/root/Game")
	return g != null and FileAccess.file_exists(String(g.get("SAVE_PATH")))

## 显示主菜单（仅在正式运行、新游戏分流处调用）
func show_menu() -> void:
	visible = true
	if _root:
		_root.visible = true
	if _btn_continue:
		_btn_continue.disabled = not has_save()
	_show_page("menu")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_menu() -> void:
	visible = false
	if _root:
		_root.visible = false
	_show_page("menu")

# ---------------- 动作 ----------------

func _on_new_game() -> void:
	Player.title_open = false
	hide_menu()
	# Game.hud 是 Variant 类型，取子节点必须先判类型再转型（parse error: hud 解析不到）
	var hud_node: Node = get_node_or_null("/root/Main/HUD")
	if hud_node and hud_node.get("intro"):
		# 演出需要 player 实例；未接线时退回树上的 Player 节点
		var p := get_node_or_null("/root/Main/Player")
		hud_node.get("intro").start_intro(p)

func _on_continue() -> void:
	Player.title_open = false
	var g := get_node_or_null("/root/Game")
	if g:
		g.set("pending_load", true)
	get_tree().reload_current_scene()

func _on_help() -> void:
	# 复用 HUD 的操作说明层（与暂停菜单同一份内容，单一来源）
	var hud_node: Node = get_node_or_null("/root/Main/HUD")
	if hud_node and hud_node.get("help_layer"):
		hud_node.get("help_layer").visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_show_page("help")

func _on_back() -> void:
	_show_page("menu")

func _on_quit() -> void:
	get_tree().quit()

func _show_page(name: String) -> void:
	_page = name
	if _menu_page:
		_menu_page.visible = name == "menu"
	# 说明内容已并入 HUD 的 help_layer；这里只留菜单页/（兜底）帮助页
	if _help_page:
		var hud_node: Node = get_node_or_null("/root/Main/HUD")
		_help_page.visible = name == "help" and (hud_node == null or not hud_node.get("help_layer"))
		# 兜底页与 HUD help_layer 二选一，避免两份说明同时可见
		if hud_node and hud_node.get("help_layer") and name == "help":
			hud_node.get("help_layer").visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _sb() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.08, 0.12, 0.92)
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 14
	s.content_margin_bottom = 18
	return s
