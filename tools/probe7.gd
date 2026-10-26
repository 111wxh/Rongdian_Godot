extends Node

# 探针：打印 HUD 下所有可见 Control 的名字/位置/尺寸，找出那条盖在画面上的灰带。

var _main: Node

func _ready() -> void:
	_main = load("res://Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	var hud: CanvasLayer = _main.get_node_or_null("HUD")
	if hud == null:
		print("NO HUD")
		get_tree().quit()
		return
	print("HUD children:")
	for c in hud.get_children():
		_dump(c, 0)
	get_tree().quit()

func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		var txt := ""
		if n is Label:
			txt = " text='" + (n as Label).text.substr(0, 20) + "'"
		elif n is RichTextLabel:
			txt = " rt"
		print(pad, c.name, " ", c.get_class(), " vis=", c.visible, " rect=", r, txt,
			" sb=", (c.get_theme_stylebox("panel").get_class() if c.has_theme_stylebox("panel") else "-"))
		for ch in n.get_children():
			_dump(ch, depth + 1)
	else:
		print(pad, n.name, " (", n.get_class(), ")")
		for ch in n.get_children():
			_dump(ch, depth + 1)
