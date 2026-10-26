extends StaticBody3D
class_name TerminalInteract
## 融点终端：旧世界最后的工程。点亮它，决定结局。

var activated := false

## autoload「Game」在编译期不可见（game.gd 依赖本类所在解析链），
## 运行时按 /root/Game 取节点。
func _g() -> Node:
	var ml := Engine.get_main_loop()
	return ml.root.get_node_or_null("Game") if ml else null

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.6, 2.6, 1.4)
	cs.shape = bs
	add_child(cs)
	# 接触体积：瞄准整座终端即可点亮，走近也出提示
	ContactVolume.attach(self, 1.8)

func get_prompt(_player) -> String:
	var g_gp: Node = _g()
	if activated:
		return ""
	if bool(g_gp.call("get_flag", "terminal_done")):
		return ""
	return "融点终端 [E]"

func interact(_player) -> void:
	var g_in: Node = _g()
	if activated or bool(g_in.call("get_flag", "terminal_done")):
		return
	if int(g_in.get("clues").size()) < 8:
		g_in.call("notify", "终端沉默着，面板上暗着八个卦位。\n你手里的旧记录还不够（%d/8）。把散落的纸页找齐再来。" % int(g_in.get("clues").size()), "info")
		return
	activated = true
	g_in.call("set_flag", "terminal_done", true)
	g_in.set("home_fire_bonus", 1.0)
	g_in.call("notify", "你把纸页一张张按进面板。\n深处传来一声沉闷的共鸣——像大地咳出一口积压万年的寒气。\n某个地方，有暖意开始流动。", "clue")
	# 全场的暖：庇护所范围内瞬间回暖
	g_in.call("notify", "以家为圆心，暖意一圈圈荡开。冰，在退。", "good")
	# 结局判定
	var hud_in: Node = g_in.get("hud")
	if is_instance_valid(hud_in) and hud_in.has_method("show_ending"):
		hud_in.show_ending(Endings.evaluate())
