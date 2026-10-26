extends CanvasLayer
## 全屏电影感后处理：暗角、胶片颗粒、边缘色散、冷暖分离。
## 纯表现层，不接触任何游戏状态；层级低于 HUD（同为 1，但先入树），
## 高于手部视图模型（HandsLayer = 0），所以手也能吃到同一套调色。

const SHADER := preload("res://assets/shaders/cinematic.gdshader")

var _rect: ColorRect
var _mat: ShaderMaterial
var _t := 0.0
var _fade := 1.0

func _ready() -> void:
	layer = 1
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.name = "CinematicOverlay"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(1, 1, 1, 1)
	_rect.material = _mat
	add_child(_rect)

func _process(delta: float) -> void:
	if _mat == null:
		return
	_t += delta
	# 夜的比重直接取 Game.night_mix（由 day_night 每帧写入，语义不变）。
	# autoload 节点名在编译期不可见，运行时按 /root/Game 取（game.gd 是 autoload）。
	var g_fx: Node = get_node_or_null("/root/Game")
	var nm: float = clampf(float(g_fx.get("night_mix")) if g_fx else 0.0, 0.0, 1.0)
	_mat.set_shader_parameter("night", nm)
	# 夜里暗角更重、颗粒更明显，白天收住——这是"电影感"随光比呼吸
	_mat.set_shader_parameter("vignette", lerpf(0.80, 1.15, nm))
	_mat.set_shader_parameter("grain", lerpf(0.026, 0.042, nm))
	_mat.set_shader_parameter("aberration", lerpf(0.95, 1.35, nm))
	_mat.set_shader_parameter("cold_lift", lerpf(0.030, 0.060, nm))
	_mat.set_shader_parameter("warm_gain", lerpf(0.070, 0.020, nm))
	_mat.set_shader_parameter("contrast", lerpf(1.040, 1.075, nm))
	_mat.set_shader_parameter("saturation", lerpf(1.03, 0.97, nm))
	# 开场淡入（第一秒从黑里浮出来，避免"啪"一下出现世界）
	if _fade < 1.0:
		_fade = minf(1.0, _fade + delta * 1.2)
	_mat.set_shader_parameter("fade", 1.0)
