extends Node
class_name ChunkManager
## 世界分块随机扩充（涌现式冰原）。
## 方向：「冰原十字路」——苏醒日的半塌街道是锚点，向外是按块坐标哈希
## 确定性生成的冰原 POI：废墟群 / 枯树林 / 遗留营地 / 冰刺群 / 空旷。
## 同一种子同一世界；走远一点，世界自己长出来。
##
## 规则：
## - 块大小 CHUNK 米；(cx, cz) 为块坐标；内容由 (world_seed, cx, cz) 哈希决定
## - 玩家周围 LOAD_RADIUS 块内实例化，超出 UNLOAD_RADIUS 卸载（省节点省性能）
## - 道路走廊（|x| < ROAD_CORRIDOR）不放 POI：那是手工设计的苏醒日辖区

const CHUNK := 96.0
const LOAD_RADIUS := 1      ## 加载半径（块）：3×3
const UNLOAD_RADIUS := 2    ## 卸载半径（块）：5×5 之外清掉
const ROAD_CORRIDOR := 45.0 ## 道路走廊半宽：里面是手工内容，不放随机 POI

var world: Node3D = null
var loaded := {}            ## "cx,cz" -> Array[Node]（本块生成的节点）

## autoload「Game」在编译期不可见（解析环），运行时按 /root/Game 取节点
func _g() -> Node:
	var ml := Engine.get_main_loop()
	return ml.root.get_node_or_null("Game") if ml else null

func setup(w: Node3D) -> void:
	world = w

func _process(_delta: float) -> void:
	var g_cm: Node = _g()
	if world == null or g_cm == null or not is_instance_valid(g_cm.get("player")):
		return
	var pl: Node = g_cm.get("player")
	var pcx := int(floor(pl.global_position.x / CHUNK))
	var pcz := int(floor(pl.global_position.z / CHUNK))
	# 加载缺失的块
	for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var key := "%d,%d" % [pcx + dx, pcz + dz]
			if not loaded.has(key):
				loaded[key] = _gen_chunk(pcx + dx, pcz + dz)
	# 卸载走远的块
	for key in loaded.keys():
		var parts: PackedStringArray = String(key).split(",")
		var ccx := int(parts[0])
		var ccz := int(parts[1])
		if absi(ccx - pcx) > UNLOAD_RADIUS or absi(ccz - pcz) > UNLOAD_RADIUS:
			for n in loaded[key]:
				if is_instance_valid(n):
					n.queue_free()
			loaded.erase(key)

## 块内随机数（确定性）：同一 (种子, 块坐标) 永远得到同一结果
func _rnd(cx: int, cz: int, salt: int) -> float:
	var g_r: Node = _g()
	var wseed: int = int(g_r.get("world_seed")) if g_r else 20261015
	var h := (cx * 73856093) ^ (cz * 19349663) ^ (wseed * 83492791) ^ (salt * 5421017)
	h = h & 0x7fffffff
	return float(h % 1000003) / 1000003.0

## 生成一个块的内容，返回生成的节点数组
func _gen_chunk(cx: int, cz: int) -> Array:
	var out: Array = []
	var bx := float(cx) * CHUNK
	var bz := float(cz) * CHUNK
	# 每个块 1-3 个 POI
	var n_poi := 1 + int(_rnd(cx, cz, 1) * 3.0)
	for i in range(n_poi):
		var px := bx + _rnd(cx, cz, 10 + i) * CHUNK
		var pz := bz + _rnd(cx, cz, 20 + i) * CHUNK
		if not _in_corridor_ok(px, pz):
			continue   ## 落在道路走廊里：跳过（手工辖区）
		var roll := _rnd(cx, cz, 30 + i)
		if roll < 0.30:
			_spawn_ruins(px, pz, out)
		elif roll < 0.55:
			_spawn_grove(px, pz, out)
		elif roll < 0.75:
			_spawn_camp(px, pz, out)
		elif roll < 0.90:
			_spawn_spikes(px, pz, out)
		# 其余：空旷——冰原的白也是内容
	# 区块野生动物（涌现生态）：走远才会遇到的狼群/鹿群/兔群，随块加载/卸载
	_spawn_chunk_wildlife(cx, cz, bx, bz, out)
	return out

## 道路走廊检查：给 8 次偏移重试，都失败就放弃这个 POI
func _in_corridor_ok(x: float, _z: float) -> bool:
	return absf(x) >= ROAD_CORRIDOR

## POI：废墟群（削顶盒子 + 门口瓦砾 + 断面钢筋）
func _spawn_ruins(x: float, z: float, out: Array) -> void:
	var g: WorldGen = world as WorldGen
	if g == null:
		return
	var y := g.height_at(x, z)
	var w := 8.0 + _rnd(int(x), int(z), 41) * 6.0
	var d := 7.0 + _rnd(int(x), int(z), 42) * 5.0
	var h := 3.0 + _rnd(int(x), int(z), 43) * 1.6
	out.append(g.chunk_box(Vector3(x, y + h / 2.0, z), Vector3(w, h, d), Color(0.45, 0.47, 0.5)))
	out.append(g.chunk_box(Vector3(x, y + h + 0.06, z), Vector3(w * 0.98, 0.12, d * 0.98), Color(0.82, 0.86, 0.9)))
	# 门口瓦砾（可翻找）
	if _rnd(int(x), int(z), 44) < 0.7:
		var node := ResourceNode.new()
		node.setup({"id": "rubble", "name": "瓦砾堆", "uses": 2, "loot": [
			{"id": "stone", "min": 1, "max": 2, "chance": 0.7},
			{"id": "brick", "min": 1, "max": 2, "chance": 0.4},
			{"id": "wood", "min": 1, "max": 1, "chance": 0.3},
		]})
		node.position = Vector3(x - w / 2.0 - 1.2, y + 0.4, z)
		out.append(node)
		world.add_child(node)

## POI：枯树林（可砍伐）+ 冰岩（可敲凿）
func _spawn_grove(x: float, z: float, out: Array) -> void:
	var g: WorldGen = world as WorldGen
	if g == null:
		return
	var n := 3 + int(_rnd(int(x), int(z), 51) * 4.0)
	for i in range(n):
		var tx := x + (_rnd(int(x), int(z), 60 + i) - 0.5) * 24.0
		var tz := z + (_rnd(int(x), int(z), 70 + i) - 0.5) * 24.0
		var ty := g.height_at(tx, tz)
		var th := 2.6 + _rnd(int(tx), int(tz), 71) * 1.6
		out.append(g.chunk_cyl(Vector3(tx, ty + th / 2.0, tz), 0.16, th, Color(0.22, 0.19, 0.17)))
		var node := ResourceNode.new()
		node.setup({"id": "dead_tree", "name": "枯树", "uses": 3, "gather_time": 1.6, "gather_verb": "砍伐", "loot": [
			{"id": "wood", "min": 1, "max": 2, "chance": 0.9},
			{"id": "cloth", "min": 1, "max": 1, "chance": 0.1},
		]})
		node.position = Vector3(tx, ty + 0.8, tz)
		out.append(node)
		world.add_child(node)
	# 林子里常有一两处冰岩
	if _rnd(int(x), int(z), 52) < 0.6:
		var rx := x + (_rnd(int(x), int(z), 53) - 0.5) * 20.0
		var rz := z + (_rnd(int(x), int(z), 54) - 0.5) * 20.0
		var ry := g.height_at(rx, rz)
		var rad := 1.2 + _rnd(int(rx), int(rz), 55) * 0.8
		var rock := g.chunk_sphere(Vector3(rx, ry + rad * 0.5, rz), rad, Color(0.78, 0.86, 0.94))
		out.append(rock)
		var node2 := ResourceNode.new()
		node2.setup({"id": "ice_rock", "name": "冰岩", "uses": 3, "gather_time": 1.2, "gather_verb": "敲凿", "loot": [
			{"id": "ice_block", "min": 1, "max": 2, "chance": 0.9},
			{"id": "stone", "min": 1, "max": 1, "chance": 0.35},
		]})
		node2.position = Vector3(rx, ry + 0.8, rz)
		out.append(node2)
		world.add_child(node2)

## POI：遗留营地（有人来过的痕迹：容器 + 石圈火塘 + 半面雪墙）
func _spawn_camp(x: float, z: float, out: Array) -> void:
	var g: WorldGen = world as WorldGen
	if g == null:
		return
	var y := g.height_at(x, z)
	out.append(g.chunk_box(Vector3(x + 2.0, y + 0.45, z + 1.5), Vector3(2.4, 0.9, 1.2), Color(0.4, 0.33, 0.26)))   # 倒伏的箱柜
	out.append(g.chunk_cyl(Vector3(x - 2.0, y + 0.2, z - 1.0), 1.4, 0.4, Color(0.5, 0.52, 0.55)))                # 石圈火塘
	out.append(g.chunk_box(Vector3(x - 3.5, y + 1.2, z - 2.5), Vector3(3.0, 2.4, 0.4), Color(0.8, 0.88, 0.96)))  # 冰雪砖墙
	for i in range(2):
		var node := ResourceNode.new()
		node.setup({"id": "cache", "name": ["遗落的背包", "压住的木箱"][i], "uses": 1, "loot": [
			{"id": "canned", "min": 1, "max": 2, "chance": 0.6},
			{"id": "cloth", "min": 1, "max": 2, "chance": 0.5},
			{"id": "bandage", "min": 1, "max": 1, "chance": 0.3},
			{"id": "backpack", "min": 1, "max": 1, "chance": 0.25},
		]})
		node.position = Vector3(x + (2.0 if i == 0 else -2.0), y + 0.4, z + (1.5 if i == 0 else -1.0))
		out.append(node)
		world.add_child(node)

## POI：冰刺群（地标 + 可开采）
func _spawn_spikes(x: float, z: float, out: Array) -> void:
	var g: WorldGen = world as WorldGen
	if g == null:
		return
	var n := 3 + int(_rnd(int(x), int(z), 81) * 3.0)
	for i in range(n):
		var sx := x + (_rnd(int(x), int(z), 90 + i) - 0.5) * 30.0
		var sz := z + (_rnd(int(x), int(z), 95 + i) - 0.5) * 30.0
		var sy := g.height_at(sx, sz)
		var h := 2.5 + _rnd(int(sx), int(sz), 96) * 3.5
		var r := 0.35 + _rnd(int(sx), int(sz), 97) * 0.5
		out.append(g.chunk_cone(Vector3(sx, sy + h / 2.0, sz), r, h, Color(0.78, 0.86, 0.94)))
		if _rnd(int(sx), int(sz), 98) < 0.4:
			var node := ResourceNode.new()
			node.setup({"id": "ice_vein", "name": "大冰刺", "uses": 3, "gather_time": 1.4, "gather_verb": "开采", "loot": [
				{"id": "ice_block", "min": 2, "max": 4, "chance": 1.0},
				{"id": "clean_water", "min": 1, "max": 1, "chance": 0.25},
			]})
			node.position = Vector3(sx, sy + 0.4, sz)
			out.append(node)
			world.add_child(node)

## 区块野生动物（涌现生态）：种类/数量/位置全由块哈希决定，随块流式加载
func _spawn_chunk_wildlife(cx: int, cz: int, bx: float, bz: float, out: Array) -> void:
	var n_wolf := 0
	if _rnd(cx, cz, 101) < DV.CHUNK_WOLF_CHANCE:
		n_wolf = 1 + int(_rnd(cx, cz, 102) * 2.0)
	var n_deer := 0
	if _rnd(cx, cz, 103) < DV.CHUNK_DEER_CHANCE:
		n_deer = 1 + int(_rnd(cx, cz, 104) * 2.0)
	var n_rabbit := int(_rnd(cx, cz, 105) * float(DV.CHUNK_RABBIT_MAX + 1))
	for i in range(n_wolf):
		_spawn_wild("wolf", cx, cz, 110 + i, bx, bz, out)
	for i in range(n_deer):
		_spawn_wild("deer", cx, cz, 120 + i, bx, bz, out)
	for i in range(n_rabbit):
		_spawn_wild("rabbit", cx, cz, 130 + i, bx, bz, out)

## 在块内找一处走廊外的开阔落点放一只野生动物（找不到就跳过这只）
func _spawn_wild(sp: String, cx: int, cz: int, salt: int, bx: float, bz: float, out: Array) -> void:
	var g: WorldGen = world as WorldGen
	if g == null:
		return
	for try_i in range(6):
		var x := bx + _rnd(cx, cz, salt + try_i * 7) * CHUNK
		var z := bz + _rnd(cx, cz, salt + 500 + try_i * 7) * CHUNK
		if not _in_corridor_ok(x, z):
			continue
		var c := Creature.new()
		c.setup(sp, Vector3(x, g.height_at(x, z), z))
		world.add_child(c)
		out.append(c)
		return
