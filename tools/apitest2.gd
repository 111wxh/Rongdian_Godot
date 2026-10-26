extends SceneTree
## 探测 Godot 4.7 环境/天空/光照的实际属性名，避免凭记忆写错属性

func _dump(obj: Object, prefix: String, filter: Array) -> void:
	print("--- ", prefix)
	for p in obj.get_property_list():
		var n: String = p["name"]
		for f in filter:
			if n.find(f) >= 0:
				print("  ", n, "  [", p["type"], "]")
				break

func _init() -> void:
	var e := Environment.new()
	_dump(e, "Environment", ["fog", "glow", "ssao", "tonemap", "adjust", "ambient", "reflected", "volumetric", "background", "sky"])
	var s := Sky.new()
	_dump(s, "Sky", ["radiance", "process", "material", "energy"])
	var l := DirectionalLight3D.new()
	_dump(l, "DirLight3D", ["light", "shadow", "sky", "distance", "blend", "angular", "cull"])
	var g := GPUParticles3D.new()
	_dump(g, "GPUParticles3D", ["amount", "lifetime", "draw", "emit", "visib", "fixed", "explosive", "interp", "transform"])
	var n := NoiseTexture2D.new()
	_dump(n, "NoiseTexture2D", ["noise", "width", "height", "seamless", "as_normal", "bump", "generate_mipmaps", "in_3d", "normalize", "color"])
	var v := VideoStreamPlayer.new()
	v.free()
	var w := WorldEnvironment.new()
	_dump(w, "WorldEnvironment", ["environment", "camera"])
	var cam := Camera3D.new()
	_dump(cam, "Camera3D", ["near", "far", "fov", "dof", "exposure", "keep", "cull"])
	var cm := CameraAttributesPractical.new()
	_dump(cm, "CamAttrPractical", ["dof", "auto", "exposure", "sensitivity"])
	print("--- enums")
	print("TONE_MAPPER_ACES=", Environment.TONE_MAPPER_ACES, " AGX=", Environment.TONE_MAPPER_AGX, " FILMIC=", Environment.TONE_MAPPER_FILMIC)
	print("SKY_PROCESS_REALTIME=", Sky.PROCESS_MODE_REALTIME, " INCREMENTAL=", Sky.PROCESS_MODE_INCREMENTAL, " QUALITY=", Sky.PROCESS_MODE_QUALITY)
	print("FOG_MODE_EXP=", Environment.FOG_MODE_EXPONENTIAL, " DEPTH=", Environment.FOG_MODE_DEPTH)
	e.free()
	s.free()
	l.free()
	g.free()
	n.free()
	w.free()
	cam.free()
	cm.free()
	quit()
