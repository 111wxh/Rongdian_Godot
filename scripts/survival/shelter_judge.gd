class_name ShelterJudge
extends RefCounted
## 庇护所等级：系统依据材料、封闭度、保温、抗灾能力综合判定（1-5）

static func compute(buildings: Array, _home_center: Vector3) -> int:
	if buildings.is_empty():
		return 0
	var walls := 0.0
	var roofs := 0.0
	var fire := false
	var bed := false
	var storage := 0.0
	var sturdy_sum := 0.0
	var n := 0
	for b in buildings:
		var key := String(b.get("type", ""))
		var d := BuildingDefs.def(key)
		if d.is_empty():
			continue
		n += 1
		walls += float(d.get("closure", 0.0))
		if bool(d.get("roof", false)):
			roofs += 1.0
		if bool(d.get("fire", false)):
			fire = true
		if bool(d.get("bed", false)):
			bed = true
		if bool(d.get("storage", false)):
			storage += 1.0
		sturdy_sum += float(d.get("sturdy", 0.3))
	var avg_sturdy := sturdy_sum / float(maxi(n, 1))
	var score := 0.0
	score += minf(walls * 0.11, 0.32)          # 封闭度
	score += minf(roofs * 0.15, 0.20)          # 有顶
	score += 0.16 if fire else 0.0             # 火源
	score += 0.10 if bed else 0.0              # 能睡下
	score += minf(storage * 0.05, 0.10)        # 囤货
	score += minf(avg_sturdy * 0.22, 0.16)     # 材料与抗灾
	return 1 + int(score * 4.99)

static func detail(buildings: Array) -> String:
	var lv := compute(buildings, Vector3.ZERO)
	return "%s（%d 级）" % [BuildingDefs.level_name(lv), lv]
