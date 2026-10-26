extends Node
class_name SoundBox
## 程序化音频层：零外部素材，全部用 AudioStreamWAV 运行时生成。
## 组成：环境风（棕噪声循环，音量随风力/暴风雪）/ 雪地脚步（按移动距离触发）/
##       营火噼啪（临近火源时循环）/ 放置·拆除·合成闷响（单发）。
## 挂载：main.gd 创建并赋给 Game.sound；所有调用点已做 is_instance_valid 守卫。

const RATE := 22050

var _wind: AudioStreamPlayer
var _fire: AudioStreamPlayer
var _step: AudioStreamPlayer
var _sfx_place: AudioStreamPlayer
var _sfx_demolish: AudioStreamPlayer
var _sfx_craft: AudioStreamPlayer

var _walk_dist := 0.0
var _last_pos := Vector3.ZERO
var _has_last := false

func _ready() -> void:
	var wind_stream := _brown_noise_wav(2.5)
	wind_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_wind = _player(wind_stream, -30.0)
	var fire_stream := _crackle_wav(3.0)
	fire_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_fire = _player(fire_stream, -30.0)
	_step = _player(_snow_step_wav(), -8.0)
	_sfx_place = _player(_thud_wav(0.28, 0.6), -2.0)
	_sfx_demolish = _player(_thud_wav(0.34, 0.45), -2.0)
	_sfx_craft = _player(_thud_wav(0.16, 0.9), -3.0)

func _player(stream: AudioStreamWAV, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	return p

func _process(delta: float) -> void:
	if Game == null or not Game.started or Game.game_over:
		_fade(_wind, -30.0, delta)
		_fade(_fire, -30.0, delta)
		return
	# ---- 风：风力 0-6+，暴风雪额外抬一档 ----
	var wf := clampf(Game.wind / 6.0, 0.0, 1.0)
	if Game.weather == "blizzard":
		wf = clampf(wf + 0.45, 0.0, 1.0)
	var indoor := 0.65 if Game.indoors else 1.0
	_fade(_wind, lerpf(-28.0, -1.0, wf) * indoor, delta)
	# ---- 火：靠近火源才听得见噼啪 ----
	var near_fire := Game.fire_strength > 0.25
	_fade(_fire, -7.0 if near_fire else -30.0, delta)
	# ---- 脚步：按实际移动距离触发，雪地闷响 ----
	_update_steps(delta)

func _fade(p: AudioStreamPlayer, target_db: float, delta: float) -> void:
	if not is_instance_valid(p):
		return
	p.volume_db = lerpf(p.volume_db, target_db, minf(1.0, delta * 3.0))

func _update_steps(_delta: float) -> void:
	if not is_instance_valid(Game.player):
		_has_last = false
		return
	var p := Game.player
	if not _has_last:
		_last_pos = p.global_position
		_has_last = true
		return
	var moved := Vector2(p.global_position.x - _last_pos.x, p.global_position.z - _last_pos.z).length()
	_last_pos = p.global_position
	var speed2 := Vector2(p.velocity.x, p.velocity.z).length()
	if speed2 < 0.6:
		_walk_dist = 0.0
		return
	_walk_dist += moved
	var stride := 2.3 if not p.sprinting else 2.9
	if _walk_dist >= stride:
		_walk_dist = 0.0
		if is_instance_valid(_step):
			_step.pitch_scale = randf_range(0.88, 1.14)
			var v := lerpf(-14.0, -5.0, clampf(speed2 / DV.SPEED_EMPTY, 0.0, 1.0))
			if p.crouching:
				v -= 5.0
			_step.volume_db = v
			_step.play()

# ---------- 对外音效 ----------

func play_place() -> void:
	if is_instance_valid(_sfx_place):
		_sfx_place.pitch_scale = randf_range(0.92, 1.08)
		_sfx_place.play()

func play_demolish() -> void:
	if is_instance_valid(_sfx_demolish):
		_sfx_demolish.pitch_scale = randf_range(0.9, 1.1)
		_sfx_demolish.play()

func play_craft() -> void:
	if is_instance_valid(_sfx_craft):
		_sfx_craft.pitch_scale = randf_range(0.95, 1.12)
		_sfx_craft.play()

# ---------- 缓冲生成（16bit 单声道 22.05kHz） ----------

func _new_buf(n: int) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(n * 2)
	return d

func _brown_noise_wav(seconds: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var d := _new_buf(n)
	var last := 0.0
	for i in range(n):
		var white := randf() * 2.0 - 1.0
		last = (last + 0.02 * white) / 1.02
		last *= 3.5
		d.encode_s16(i * 2, int(clampf(last * 9000.0, -32000.0, 32000.0)))
	return _wrap(d)

## 营火噼啪：静音底上随机撒稀疏爆点（短噪声脉冲，指数衰减）
func _crackle_wav(seconds: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var d := _new_buf(n)
	for k in range(randi_range(24, 40)):
		var at := randi_range(0, n - 900)
		var amp := randf_range(4000.0, 13000.0)
		var dur := randi_range(60, 420)
		for j in range(dur):
			var idx := at + j
			if idx >= n:
				break
			var env := 1.0 - float(j) / float(dur)
			var s := int((randf() * 2.0 - 1.0) * amp * env * env)
			d.encode_s16(idx * 2, s)
	return _wrap(d)

## 雪地脚步：短促衰减噪声（雪沫感）+ 一记低频闷踩
func _snow_step_wav() -> AudioStreamWAV:
	var n := int(RATE * 0.16)
	var d := _new_buf(n)
	for i in range(n):
		var t := float(i) / float(n)
		var env := exp(-t * 9.0)
		var crunch := (randf() * 2.0 - 1.0) * 8000.0 * env
		var thump := sin(float(i) / RATE * TAU * 90.0) * 3500.0 * exp(-t * 14.0)
		d.encode_s16(i * 2, int(clampf(crunch + thump, -32000.0, 32000.0)))
	return _wrap(d)

## 闷响（放置/拆除/合成）：低频噪声，brightness 控制"硬"感
func _thud_wav(seconds: float, brightness: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var d := _new_buf(n)
	var last := 0.0
	for i in range(n):
		var t := float(i) / float(n)
		var white := randf() * 2.0 - 1.0
		last = (last + (0.02 + 0.10 * brightness) * white) / (1.02 + 0.10 * brightness)
		var env := exp(-t * (5.0 + 8.0 * brightness))
		d.encode_s16(i * 2, int(clampf(last * 16000.0 * env, -32000.0, 32000.0)))
	return _wrap(d)

func _wrap(d: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = d
	return w
