extends Node

# 探针：同一机位拍两张——关 HUD / 开 HUD，用来判断那条灰带是 UI 还是 3D。

var _main: Node
var _out := "res://tools/shots"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_main = load("res://Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node3D = _main.get_node_or_null("Player")
	var world: Node = _main.get_node_or_null("World")
	player.global_position = Vector3(0.0, world.height_at(0.0, 90.0) + 1.62, 90.0)
	player.call("set_facing", 0.0, 0.06)

	var hud: CanvasLayer = _main.get_node_or_null("HUD")
	if hud != null and hud.get("intro") != null:
		var it = hud.get("intro")
		if it != null:
			it.queue_free()
	Game.started = true
	var fx: CanvasLayer = _main.get_node_or_null("PostFX")
	if fx != null:
		fx.visible = false
	await _wait(1.2)
	await _shot("dbg_hud_on.png")
	if hud != null:
		hud.visible = false
	await _wait(0.4)
	await _shot("dbg_hud_off.png")
	print("done")
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(nm))
