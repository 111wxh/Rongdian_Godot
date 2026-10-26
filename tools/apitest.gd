extends SceneTree

func _init() -> void:
	print("=== Environment props ===")
	var names := []
	for p in ClassDB.class_get_property_list("Environment", true):
		names.append(p.name)
	names.sort()
	print(", ".join(names))
	print("=== TonemapMode ===")
	for k in ClassDB.class_get_enum_constants("Environment", "ToneMapper"):
		print("  ", k)
	print("=== Sky process modes ===")
	for k in ClassDB.class_get_enum_constants("Sky", "ProcessMode"):
		print("  ", k)
	print("=== DirectionalLight3D key props ===")
	var dl := []
	for p in ClassDB.class_get_property_list("DirectionalLight3D", true):
		dl.append(p.name)
	dl.sort()
	print(", ".join(dl))
	print("=== Light3D shadow props ===")
	var ll := []
	for p in ClassDB.class_get_property_list("Light3D", true):
		if String(p.name).begins_with("shadow") or String(p.name).begins_with("light"):
			ll.append(p.name)
	ll.sort()
	print(", ".join(ll))
	quit()
