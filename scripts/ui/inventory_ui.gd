extends Control
class_name InventoryUI
## 背包面板：格子网格（大件占 2×2）/ 徒手合成 / 拖动整理 / 使用 / 装备
## 操作：左键拿起 → 点到另一件上合成（或点空格拖动整理）→ 再点自己放下；右键直接使用/手持
## 网格是视觉/整理层：数据层仍是栈式（存档与容量逻辑不变），位置仅 UI 侧记忆。

const COLS: int = DV.INV_GRID_COLS
const ROWS: int = DV.INV_GRID_ROWS
const CELL := 62.0

var grid_host: Control       ## 网格层（绝对定位，_draw 画格子）
var cap_lbl: Label
var detail_lbl: Label

var _held := ""              ## 当前"拿在手里"的物品（跟随鼠标）
var _held_panel: PanelContainer
var _held_lbl: Label
var _hover_id := ""
var _pos := {}               ## id -> Vector2i 网格位置（UI 侧布局记忆）

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.set_deferred("position", Vector2(-330, -290))
	panel.set_deferred("size", Vector2(660, 580))
	panel.add_theme_stylebox_override("panel", _sb())
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := Label.new()
	title.text = "背 包"
	title.add_theme_font_size_override("font_size", 22)
	head.add_child(title)
	cap_lbl = Label.new()
	cap_lbl.add_theme_font_size_override("font_size", 14)
	cap_lbl.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	head.add_child(cap_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var btn_close := Button.new()
	btn_close.text = "收起 (Tab)（上方标签可鼠标点选切换面板）"
	btn_close.pressed.connect(func(): visible = false; _hud().call("_close_all"))
	head.add_child(btn_close)
	var hint := Label.new()
	hint.text = "左键拿起 → 点到另一件上合成 · 点空格拖动整理 · 右键直接用手/吃掉 · 上方标签可鼠标点选切换面板"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))
	vb.add_child(hint)
	# 网格层：绝对定位 + _draw 画底格；物品按钮作为子节点盖在上面
	grid_host = Control.new()
	grid_host.custom_minimum_size = Vector2(COLS * CELL, ROWS * CELL)
	grid_host.set_deferred("size", Vector2(COLS * CELL, ROWS * CELL))
	grid_host.mouse_filter = Control.MOUSE_FILTER_STOP
	grid_host.gui_input.connect(_on_grid_gui)
	grid_host.draw.connect(_draw_grid)
	vb.add_child(grid_host)
	detail_lbl = Label.new()
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.custom_minimum_size = Vector2(0, 56)
	detail_lbl.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95))
	vb.add_child(detail_lbl)
	# 跟随鼠标的"手持物"面板（mouse_filter 忽略，不抢下面按钮的事件）
	_held_panel = PanelContainer.new()
	_held_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_held_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_panel.visible = false
	var hps := StyleBoxFlat.new()
	hps.bg_color = Color(0.12, 0.16, 0.22, 0.95)
	hps.corner_radius_top_left = 6
	hps.corner_radius_top_right = 6
	hps.corner_radius_bottom_left = 6
	hps.corner_radius_bottom_right = 6
	hps.content_margin_left = 10
	hps.content_margin_right = 10
	hps.content_margin_top = 6
	hps.content_margin_bottom = 6
	_held_panel.add_theme_stylebox_override("panel", hps)
	_held_lbl = Label.new()
	_held_lbl.add_theme_font_size_override("font_size", 15)
	_held_panel.add_child(_held_lbl)
	add_child(_held_panel)

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

func _process(_delta: float) -> void:
	if _held_panel == null:
		return
	_held_panel.visible = _held != ""
	if _held != "" and get_viewport():
		var mp := get_viewport().get_mouse_position()
		_held_panel.position = mp + Vector2(16, 16)
		_held_lbl.text = "%s ×%d" % [Items.name_of(_held), int(_g().call("count_item", _held))]

# ---------- 网格布局 ----------

## 物品占位（大件 2×2，其余 1×1）
func _footprint(id: String) -> Vector2i:
	var cat := Items.cat_of(id)
	if cat in DV.INV_FOOTPRINT_BIG:
		return Vector2i(2, 2)
	return Vector2i(1, 1)

## 目标位对 exclude 之外的占用是否空闲
func _cell_free_for(exclude_id: String, cell: Vector2i) -> bool:
	var fp := _footprint(exclude_id)
	if cell.x < 0 or cell.y < 0 or cell.x + fp.x > COLS or cell.y + fp.y > ROWS:
		return false
	var occ := _occ_grid(exclude_id)
	for dy in range(fp.y):
		for dx in range(fp.x):
			if occ[cell.y + dy][cell.x + dx]:
				return false
	return true

## 除 exclude 外所有物品的占用表
func _inv() -> Inventory:
	var g_i: Node = _g()
	if g_i == null:
		return null
	return g_i.get("inventory")

func _occ_grid(exclude_id: String = "") -> Array:
	var occ := []
	for r in range(ROWS):
		var row := []
		row.resize(COLS)
		for c in range(COLS):
			row[c] = false
		occ.append(row)
	var inv := _inv()
	if inv == null:
		return occ
	for it in inv.aggregated():
		var id := String(it.id)
		if id == exclude_id or not _pos.has(id):
			continue
		var p: Vector2i = _pos[id]
		var fp := _footprint(id)
		for dy in range(fp.y):
			for dx in range(fp.x):
				if p.y + dy < ROWS and p.x + dx < COLS:
					occ[p.y + dy][p.x + dx] = true
	return occ

## 计算布局：保留已记住的位置（放不下就重排），返回 [{id,count,col,row,w,h}]
## 两遍法：先摆所有有记忆位置的（互不冲突，因为移动时已校验过），
## 再对剩下的做 first-fit——避免"校验自己位置时把自己算成障碍"的死循环
func _layout() -> Array:
	# 先清掉已不存在物品的位置记忆
	var alive := {}
	var inv := _inv()
	if inv == null:
		return []
	for it in inv.aggregated():
		alive[String(it.id)] = true
	for id in _pos.keys():
		if not alive.has(id):
			_pos.erase(id)
	var occ := _empty_occ()
	var out := []
	var pending := []
	for it in inv.aggregated():
		var id := String(it.id)
		var fp := _footprint(id)
		var keep := false
		if _pos.has(id):
			var p: Vector2i = _pos[id]
			if p.x >= 0 and p.y >= 0 and p.x + fp.x <= COLS and p.y + fp.y <= ROWS:
				var free := true
				for dy in range(fp.y):
					for dx in range(fp.x):
						if occ[p.y + dy][p.x + dx]:
							free = false
				if free:
					_claim(occ, p, fp)
					out.append({"id": id, "count": int(it.count), "col": p.x, "row": p.y, "w": fp.x, "h": fp.y})
					keep = true
		if not keep:
			pending.append(it)
	for it in pending:
		var id2 := String(it.id)
		var fp2 := _footprint(id2)
		for r in range(ROWS - fp2.y + 1):
			var done := false
			for c in range(COLS - fp2.x + 1):
				var ok := true
				for dy in range(fp2.y):
					for dx in range(fp2.x):
						if occ[r + dy][c + dx]:
							ok = false
				if ok:
					_claim(occ, Vector2i(c, r), fp2)
					_pos[id2] = Vector2i(c, r)
					out.append({"id": id2, "count": int(it.count), "col": c, "row": r, "w": fp2.x, "h": fp2.y})
					done = true
					break
			if done:
				break
	return out

func _empty_occ() -> Array:
	var occ := []
	for r in range(ROWS):
		var row := []
		row.resize(COLS)
		for c in range(COLS):
			row[c] = false
		occ.append(row)
	return occ

func _claim(occ: Array, p: Vector2i, fp: Vector2i) -> void:
	for dy in range(fp.y):
		for dx in range(fp.x):
			if p.y + dy < ROWS and p.x + dx < COLS:
				occ[p.y + dy][p.x + dx] = true

func _draw_grid() -> void:
	if grid_host == null:
		return
	for r in range(ROWS):
		for c in range(COLS):
			var rect := Rect2(c * CELL + 1.0, r * CELL + 1.0, CELL - 2.0, CELL - 2.0)
			grid_host.draw_rect(rect, Color(0.10, 0.13, 0.18, 0.55))
	# 悬停目标格高亮：手里有货时提示"放这儿"
	if _hover_cell != Vector2i(-1, -1) and _held != "":
		var hr := Rect2(_hover_cell.x * CELL + 1.0, _hover_cell.y * CELL + 1.0, CELL - 2.0, CELL - 2.0)
		grid_host.draw_rect(hr, Color(0.3, 0.4, 0.5, 0.35))

var _hover_cell := Vector2i(-1, -1)

func _on_grid_gui(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var cell := Vector2i(int(mm.position.x / CELL), int(mm.position.y / CELL))
		if cell != _hover_cell:
			_hover_cell = cell
			grid_host.queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		var c := Vector2i(clampi(int(mb.position.x / CELL), 0, COLS - 1), clampi(int(mb.position.y / CELL), 0, ROWS - 1))
		_on_cell(c)

## 点空格：手里有货就整理到这儿；没货就看看提示
func _on_cell(cell: Vector2i) -> void:
	if _held == "":
		return
	var g_oc: Node = _g()
	if _cell_free_for(_held, cell):
		_pos[_held] = cell
		g_oc.call("notify", "%s 挪了个顺手的位置。" % Items.name_of(_held), "info")
		refresh()
	else:
		g_oc.call("notify", "那儿放不下（被占着或超出包）。", "bad")

# ---------- 刷新与渲染 ----------

func _hud() -> Node:
	var hud: Node = get_node_or_null("/root/Main/HUD")
	return hud if is_instance_valid(hud) else null

func _g() -> Node:
	return get_node_or_null("/root/Game")

func refresh() -> void:
	for c in grid_host.get_children():
		c.queue_free()
	var inv := _inv()
	var used := 0
	if inv != null:
		used = inv.slots.size()
	var layout := _layout()
	var cells_used := 0
	for e in layout:
		var fp := Vector2i(int(e["w"]), int(e["h"]))
		cells_used += fp.x * fp.y
	var cap_txt := "槽位 %d / %d · 格子 %d / %d" % [used, inv.capacity(), cells_used, COLS * ROWS] if inv != null else ""
	cap_lbl.text = cap_txt
	for e in layout:
		var id := String(e["id"])
		var n := int(e["count"])
		var col := int(e["col"])
		var row := int(e["row"])
		var w := int(e["w"])
		var h := int(e["h"])
		var b := Button.new()
		b.position = Vector2(col * CELL + 2.0, row * CELL + 2.0)
		b.size = Vector2(w * CELL - 4.0, h * CELL - 4.0)
		b.tooltip_text = Items.desc_of(id)
		b.clip_text = true
		var txt := Items.name_of(id)
		if n > 1:
			txt += " ×%d" % n
		b.text = txt
		b.add_theme_font_size_override("font_size", 14 if w * h > 1 else 13)
		b.pressed.connect(_on_slot.bind(id))
		b.mouse_entered.connect(func():
			_hover_id = id
			if _held == "":
				return
			var rid := Recipes.combo_id(_held, id)
			b.modulate = Color(0.65, 1.0, 0.72) if rid != "" else Color(1.0, 0.68, 0.68)
			_update_combo_hint())
		b.mouse_exited.connect(func():
			b.modulate = Color.WHITE
			if _hover_id == id:
				_hover_id = "")
		b.gui_input.connect(_on_slot_gui.bind(id, b))
		grid_host.add_child(b)
	if _held != "" and int(_g().call("count_item", _held)) <= 0:
		_held = ""   ## 合成把最后一件用掉了：手里的货没了
	_update_combo_hint()
	grid_host.queue_redraw()

func _on_slot_gui(event: InputEvent, id: String, _b: Button) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_quick_action(id)

func _on_slot(id: String) -> void:
	if _held == "":
		_held = id
		detail_lbl.text = "拿起了%s——点到另一件上凑凑，或点空格挪个顺手的位置。" % Items.name_of(id)
	elif _held == id:
		# 点自己：能自组合（布+布/冰+冰）就合成，否则放回
		if Recipes.combo_id(id, id) != "":
			_try_combo(id)
		else:
			_held = ""
			detail_lbl.text = "放下了%s。" % Items.name_of(id)
	else:
		_try_combo(id)
	refresh()

func _try_combo(other_id: String) -> void:
	var rid := Recipes.combo_id(_held, other_id)
	if rid == "":
		detail_lbl.text = "%s 和 %s 凑不到一起。" % [Items.name_of(_held), Items.name_of(other_id)]
		_held = ""
		refresh()
		return
	var g_tc: Node = _g()
	var r: Dictionary = g_tc.call("craft_recipe", rid)
	if not r.get("ok", false):
		g_tc.call("notify", String(r.get("why", "做不了。")), "bad")
		_held = ""
		refresh()
		return
	g_tc.call("notify", "两件一碰：%s。" % Recipes.name_of(rid), "good")
	if r.has("build"):
		# 建筑类徒手合成：直接进入幽灵放置
		var h_n: Node = _hud()
		if is_instance_valid(h_n) and h_n.has_method("open_build_with"):
			h_n.call("open_build_with", String(r["build"]))
		return
	# 普通产物：手里这件若还剩着，继续拿着（连搓）；否则放下
	if int(g_tc.call("count_item", _held)) <= 0:
		_held = ""
	refresh()

func _update_combo_hint() -> void:
	if _held == "":
		return
	if _hover_id == "":
		return
	var rid := Recipes.combo_id(_held, _hover_id)
	if rid != "":
		detail_lbl.text = "%s → %s（点下去就成了）" % [Recipes.combo_cost_text(rid), Recipes.name_of(rid)]
	else:
		detail_lbl.text = "%s 和 %s 凑不到一起。" % [Items.name_of(_held), Items.name_of(_hover_id)]

## 右键快速动作：手持工具 / 吃掉喝掉用掉（原点击行为）
func _quick_action(id: String) -> void:
	var cat := Items.cat_of(id)
	var g_qa: Node = _g()
	if cat == "tool":
		g_qa.set("active_tool", id)
		detail_lbl.text = "%s——%s\n已持在手中。" % [Items.name_of(id), Items.desc_of(id)]
		g_qa.call("notify", "手持：%s" % Items.name_of(id), "info")
	elif cat in ["food", "drink", "medical"]:
		var pn: Node = g_qa.get("player")
		if is_instance_valid(pn) and pn.has_method("_consume"):
			pn.call("_consume", id)
		refresh()
	elif cat == "special" and id.begins_with("clue_"):
		var e := StoryLogs.entry(id)
		detail_lbl.text = "【%s】\n%s" % [e.title, e.text]
	else:
		detail_lbl.text = "%s——%s" % [Items.name_of(id), Items.desc_of(id)]
