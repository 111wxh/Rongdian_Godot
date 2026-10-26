extends Node
## 输入映射：在代码中注册全部键位，避免手写 project.godot 输入表出错
## 注意：Godot 的 Key 枚举与 MouseButton 枚举数值重叠，必须分开注册

const KEY_ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],          ## 冲刺（加速；静步减速用 Ctrl/C 下蹲或 Q 倾听）
	"crouch": [KEY_C, KEY_CTRL],    ## 蹲下/贴近地面（手感规格主键 C，兼容 Ctrl）
	"jump": [KEY_SPACE],
	"interact": [KEY_E],             ## 情境交互（对话/开箱/床/终端/占家/搬起）：E 键
	"flashlight": [KEY_F],          ## 点火/熄灭（长按 1.5s）
	"inventory": [KEY_TAB],
	"crafting": [KEY_X],            ## 制作（C 让位给蹲下，V 让位给审视姿态）
	"build": [KEY_B],
	"journal": [KEY_J],
	"rotate_build": [KEY_R],
	"listen": [KEY_Q],              ## 环顾/倾听模式（降低移速，热量流失 ×1.5）
	"survey": [KEY_V],              ## 审视姿态（建造灵魂操作，3s）
	"drop": [KEY_G],                ## 丢弃（燃料不可回收，需二次确认）
	"quick_drink": [KEY_1],
	"quick_eat": [KEY_2],
	"quick_med": [KEY_3],
	"cycle_tool": [KEY_4],
	"quick_save": [KEY_F5],
	"quick_load": [KEY_F9],
	"cancel": [KEY_ESCAPE],
}

const MOUSE_ACTIONS := {
	"use": [MOUSE_BUTTON_LEFT],       ## 攻击+使用：捕猎突刺 / 长按采集 / 拢雪 / 拆除（鼠标左键）
	"wheel": [MOUSE_BUTTON_MIDDLE],   ## 快捷轮盘（按住打开，松开执行悬停项）
	"build_extend": [MOUSE_BUTTON_WHEEL_UP],    ## 建造中：滚轮上=加长（墙/地板）
	"build_shrink": [MOUSE_BUTTON_WHEEL_DOWN],  ## 建造中：滚轮下=缩短
}

func _ready() -> void:
	_setup_cjk_font()
	for action in KEY_ACTIONS:
		_ensure_action(action)
		for k in KEY_ACTIONS[action]:
			# 防呆：鼠标键常量(1..9)与键盘键数值空间不重叠，若被误放进 KEY_ACTIONS，
			# 必须按鼠标键注册——否则 physical_keycode=1 只是绑到某个键盘键，鼠标永远点不动。
			if _is_mouse_button(k):
				push_warning("[input_setup] %s 绑定 %d 是鼠标键，已按鼠标键注册" % [action, k])
				_push_mouse_event(action, k)
			else:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(action, ev)
	for action in MOUSE_ACTIONS:
		_ensure_action(action)
		for b in MOUSE_ACTIONS[action]:
			_push_mouse_event(action, b)

## 鼠标键常量范围（LEFT=1 .. XBUTTON2=9）；键盘键最小是 SPACE=32，不会误判
func _is_mouse_button(v: int) -> bool:
	return v >= int(MOUSE_BUTTON_LEFT) and v <= int(MOUSE_BUTTON_XBUTTON2)

func _push_mouse_event(action: String, b: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = b as MouseButton
	InputMap.action_add_event(action, ev)

func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

## 中文字体：手写 .tres 主题在不同 Godot 小版本间不兼容，
## 改为运行时向 ThemeDB 注入系统字体（4.2 / 4.3 / 4.4 均稳定）。
func _setup_cjk_font() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei", "Microsoft YaHei UI", "SimHei",
		"DengXian", "Noto Sans CJK SC", "PingFang SC", "sans-serif",
	])
	ThemeDB.fallback_font = f
