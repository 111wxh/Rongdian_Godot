extends Node3D
class_name WorldGen
## 世界自动生成：噪声冰原地形 + 削顶废墟街道 + 冰原景物 + 陨坑
## 依据设计文档"苏醒日"场景：被削掉上半身的楼房、齐整断面覆雪、保安亭、便利店

const N := 192                     # 地形网格段数（细分足够，坡面不再色块化）
const SIZE := 560.0                 # 世界边长（米）
const ROAD_HALF := 9.0

const SHADER_SURFACE := preload("res://assets/shaders/surface.gdshader")
const SHADER_TERRAIN := preload("res://assets/shaders/terrain_snow.gdshader")
const SHADER_ROAD := preload("res://assets/shaders/road.gdshader")
const SHADER_MARK := preload("res://assets/shaders/road_mark.gdshader")
const SHADER_ICE := preload("res://assets/shaders/ice_rock.gdshader")
const SHADER_SNOWPILE := preload("res://assets/shaders/snow_pile.gdshader")
const SHADER_LAMP := preload("res://assets/shaders/lamp.gdshader")

# ---- Blender 程序化生成的模型（assets/models，随工程一起分发） ----
const MOD_DEAD_TREE := preload("res://assets/models/dead_tree.glb")
const MOD_DEAD_TREE_B := preload("res://assets/models/dead_tree_b.glb")
const MOD_ICE_ROCK := preload("res://assets/models/ice_rock.glb")
const MOD_ICE_ROCK_B := preload("res://assets/models/ice_rock_b.glb")

var hgrid: PackedFloat32Array
var terrain_mesh: MeshInstance3D
var terrain_body: StaticBody3D
var terrain_cs: CollisionShape3D
var craters: Array = []             # [{pos: Vector2, r: float, depth: float}]
var ruin_bodies: Array = []         # 可被二次垮塌的废墟节点
var district_flags := {"d1": false, "d2": false, "d3": false}

var _noise_c: FastNoiseLite
var _noise_d: FastNoiseLite
var _noise_s: FastNoiseLite
var _spawned := false

func _ready() -> void:
	var g_rd: Node = _g()
	if g_rd:
		g_rd.set("world", self)
	_generate()

func _exit_tree() -> void:
	# 同 player.gd：场景重载时置空全局引用，让 is_instance_valid(Game.world)
	# 检查真正生效，避免对已释放世界的调用/赋值
	var g_wd: Node = _g()
	if g_wd and g_wd.get("world") == self:
		g_wd.set("world", null)

## autoload「Game」在编译期不可见（本类被 game.gd 依赖，形成解析环），
## 运行时按 /root/Game 取节点。
func _g() -> Node:
	var ml := Engine.get_main_loop()
	return ml.root.get_node_or_null("Game") if ml else null

# =====================================================================
# 地形
# =====================================================================

func _noise_height(x: float, z: float) -> float:
	var h := _noise_c.get_noise_2d(x, z) * 11.0
	h += _noise_d.get_noise_2d(x, z) * 1.8
	# ---- 风吹出来的雪脊（sastrugi）----
	# 只靠 11m 一级的大起伏，雪原在中景上是一张白纸：
	# 第一人称平视时，1~3m 尺度的起伏才是"这里有一片雪地"的证据。
	# 用两组方向不同、被压扁的噪声叠加，读起来像被同一个风向啃出来的长垄。
	# 注意 _noise_s 的基频是 0.085，所以乘数 m 对应的波长是 1/(m*0.085)。
	# 之前写 0.045 得到的是 260m 波长的缓坡——那是地形大趋势，不是风纹，
	# 算出来的起伏在画面上完全不存在。要 10~30m 级的雪垄，m 必须给到 0.4~1.2。
	var sas_a := _noise_s.get_noise_2d(x * 0.196, z * 1.31) * 0.62   # 60m×9m 的顺风长垄
	var sas_b := _noise_s.get_noise_2d(x * 0.62 + 41.0, z * 0.28 - 17.0) * 0.38
	var sastrugi := (sas_a + sas_b) * 0.42
	# ---- 雪丘（dune）----
	# 只有 1~3m 的风脊，中景依然是一片平纸：掠射的冬日阳光下，
	# 只有十几米一级、接近一米高的雪丘才能投出足够长的影，
	# 把中景切成有前后关系的几层。低频、低幅、方向单一，
	# 才能读成"被同一场风堆出来的"而不是随机的鼓包。
	var dune := _noise_s.get_noise_2d(x * 0.21 + 7.0, z * 0.16 - 3.0) * 0.86   # ~55m 雪丘
	dune += _noise_s.get_noise_2d(x * 0.66 - 23.0, z * 0.52 + 11.0) * 0.34      # ~18m 叠加
	# 街道与建筑区要平，否则玩家在城里走路会一直在爬坡
	# 两条街都要算进去：只按 |x| 判断的话，横街（沿 x 的那条）上照样会堆雪丘
	var urban_d := minf(absf(x), absf(z))
	var urban := clampf((urban_d - ROAD_HALF - 3.0) / 18.0, 0.0, 1.0)
	urban = urban * urban * (3.0 - 2.0 * urban)
	h += (sastrugi + dune) * urban
	h += _noise_d.get_noise_2d(x * 3.1 + 13.0, z * 3.1 - 7.0) * 0.30 * urban
	# 街道压平
	# 这里必须把路面压成"完全水平"的平面，不能留任何横向路拱：
	# 地形格是 560/192 = 2.92m，一条 8.4m 宽的街横截面只有 3 个顶点。
	# 只要高度随横向距离变化，这 3 个点就不共面，整条街被切成几块
	# 互成折角的巨大三角形，顶点法线各不相同，天光一照就是一片一片
	# 深浅不一的黑斑——看起来像阴影 acne，其实是网格分辨率不足。
	# 压平之后路面所有顶点同高同法线，格再粗也不会显形。
	var road_d := minf(absf(x), absf(z))   # 到最近一条街道中心线的距离
	var flat := 0.55
	if road_d < ROAD_HALF:
		h = flat
	elif road_d < ROAD_HALF + 9.0:
		# 从路肩往外用二次曲线融回自然地形：一阶连续，不会在路肩拉出硬折角
		var t := (road_d - ROAD_HALF) / 9.0
		h = lerpf(flat, h, t * t)
	# 陨石坑
	for c in craters:
		var d := Vector2(x, z).distance_to(c.pos)
		if d < c.r * 2.0:
			var f := clampf(1.0 - d / c.r, 0.0, 1.0)
			h -= c.depth * f * f
			if d > c.r and d < c.r * 1.8:
				h += c.depth * 0.22 * (1.0 - absf(d - c.r * 1.4) / (c.r * 0.4))
	return h

func _build_height_grid() -> void:
	var cell := SIZE / float(N)
	hgrid.resize((N + 1) * (N + 1))
	for i in range(N + 1):
		for j in range(N + 1):
			var x := -SIZE / 2.0 + float(i) * cell
			var z := -SIZE / 2.0 + float(j) * cell
			hgrid[i * (N + 1) + j] = _noise_height(x, z)

func height_at(x: float, z: float) -> float:
	var cell := SIZE / float(N)
	var fx := clampf((x + SIZE / 2.0) / cell, 0.0, float(N))
	var fz := clampf((z + SIZE / 2.0) / cell, 0.0, float(N))
	var i0 := int(fx)
	var j0 := int(fz)
	var i1 := mini(i0 + 1, N)
	var j1 := mini(j0 + 1, N)
	var tx := fx - float(i0)
	var tz := fz - float(j0)
	var h00: float = hgrid[i0 * (N + 1) + j0]
	var h10: float = hgrid[i1 * (N + 1) + j0]
	var h01: float = hgrid[i0 * (N + 1) + j1]
	var h11: float = hgrid[i1 * (N + 1) + j1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func _build_terrain_mesh() -> void:
	var cell := SIZE / float(N)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(N + 1):
		for j in range(N + 1):
			var x := -SIZE / 2.0 + float(i) * cell
			var z := -SIZE / 2.0 + float(j) * cell
			var h: float = hgrid[i * (N + 1) + j]
			# 法线必须和网格本身一致：对 hgrid 做中心差分，不是对解析高度求梯度。
			#
			# 这里长期用 _noise_height(x±1.5) 解析求梯度。问题是 hgrid 的采样间隔
			# 是 2.92m，而 e=1.5m 的差分把 3m 以下的起伏全部算了进去——那些起伏
			# 网格根本表达不出来。于是每个顶点拿到的是一个"理想光滑曲面"的法线，
			# 相邻顶点的法线互不相关；插值到三角形里，slope 就是一片片线性变化的
			# 斜坡，再被着色器的 smoothstep 一放大，整片地面就被切成一堆直边多边形，
			# 每片亮度不同。dc1/dc2 调试通道里那满地楔形就是它。
			# 改用 hgrid 的中心差分后，法线描述的就是这张网格的实际倾角，
			# 顶点之间连续、三角形之间没有台阶，明暗楔形随之消失。
			var hl: float = hgrid[(i - 1 if i > 0 else i) * (N + 1) + j]
			var hr: float = hgrid[(i + 1 if i < N else i) * (N + 1) + j]
			var hd: float = hgrid[i * (N + 1) + (j - 1 if j > 0 else j)]
			var hu: float = hgrid[i * (N + 1) + (j + 1 if j < N else j)]
			var n := Vector3(-(hr - hl), 2.0 * cell, -(hu - hd)).normalized()
			# 着色完全交给地形着色器（世界空间噪声），这里只留 UV 供引擎做缓存键
			st.set_uv(Vector2(x, z) * 0.02)
			st.set_normal(n)
			st.add_vertex(Vector3(x, h, z))
	for i in range(N):
		for j in range(N):
			var a := i * (N + 1) + j
			var b := (i + 1) * (N + 1) + j
			var c := (i + 1) * (N + 1) + j + 1
			var d := i * (N + 1) + j + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(a); st.add_index(c); st.add_index(d)
	var mesh := st.commit()
	terrain_mesh.mesh = mesh
	var shape := mesh.create_trimesh_shape()
	if terrain_cs:
		terrain_cs.shape = shape
	terrain_mesh.add_to_group("terrain")
	terrain_body.add_to_group("terrain")
	terrain_body.add_to_group("snow_ground")

func apply_crater(world_pos: Vector3, radius: float, depth: float) -> void:
	craters.append({"pos": Vector2(world_pos.x, world_pos.z), "r": radius, "depth": depth})
	_build_height_grid()
	_build_terrain_mesh()

# =====================================================================
# 总生成
# =====================================================================

func _generate() -> void:
	# 世界布局必须由种子唯一决定：否则每次读档重建出来的街景都是另一座城，
	# 存档点、玩家认定的"家"、走过的路口全部对不上。
	var g_wg: Node = _g()
	var wseed: int = int(g_wg.get("world_seed")) if g_wg else 20261015
	seed(wseed)
	_noise_c = FastNoiseLite.new()
	_noise_c.seed = wseed
	_noise_c.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_c.frequency = 0.0045
	_noise_c.fractal_octaves = 3
	_noise_d = FastNoiseLite.new()
	_noise_d.seed = wseed + 777
	_noise_d.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_d.frequency = 0.03
	_noise_d.fractal_octaves = 2
	# 风雪脊专用：高频、细碎，只用来在近处把雪面搓出纹理
	_noise_s = FastNoiseLite.new()
	_noise_s.seed = wseed + 1517
	_noise_s.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_s.frequency = 0.085
	_noise_s.fractal_octaves = 3
	# 预生成远古陨坑（世界像月球一样坑坑洼洼）
	for i in range(7):
		var ang := randf() * TAU
		var dist := randf_range(60.0, 240.0)
		craters.append({
			"pos": Vector2(cos(ang) * dist, sin(ang) * dist),
			"r": randf_range(12.0, 26.0),
			"depth": randf_range(2.0, 4.5),
		})
	terrain_mesh = MeshInstance3D.new()
	terrain_mesh.name = "TerrainMesh"
	var tmat := ShaderMaterial.new()
	tmat.shader = SHADER_TERRAIN
	# 路面直接画在地形着色器里：没有任何独立网格，因此不可能穿模或 z-fighting
	tmat.set_shader_parameter("road_on", 1.0)
	tmat.set_shader_parameter("road_z_half", 4.2)
	tmat.set_shader_parameter("road_x_half", 3.3)
	tmat.set_shader_parameter("road_extent", 280.0)
	tmat.set_shader_parameter("road_gap", 11.0)
	terrain_mesh.material_override = tmat
	terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(terrain_mesh)
	terrain_body = StaticBody3D.new()
	terrain_body.name = "Terrain"
	var cs := CollisionShape3D.new()
	terrain_cs = cs
	terrain_body.add_child(cs)
	add_child(terrain_body)
	_build_height_grid()
	_build_terrain_mesh()
	# 路面（先铺路，街道家具随后）
	_gen_roads()
	# 景物
	_gen_street_props()
	_gen_enterable_buildings()
	_gen_more_houses()
	_gen_ruins()
	_gen_nature()
	_gen_clue_trails()
	_gen_creatures()
	_gen_npcs()
	_gen_terminal()
	# 最后铺一层"野地细节"。必须放在最后：它要吃掉一批 randf()，
	# 放在前面会把后面所有随机布点整体挪位。
	_gen_field_detail()
	# 街道家具（垃圾桶/消防栓/路牌/长椅/报箱/自行车架）。
	# 放在最后并且用独立 RNG：它要吃掉一大批 randf()，混进主 RNG 会把
	# 整座城的随机布点整体挪位。
	_gen_street_furniture()
	_spawned = true

# =====================================================================
# 分块随机扩充原语：供 ChunkManager 生成区块内容用。
# 与内部 _box/_cyl 的区别：不自行 add_child（由调用方挂到目标父节点），
# 且入参是 Color（自动转 ShaderMaterial），返回类型显式可推断。
# =====================================================================

## 盒体（带碰撞），返回 StaticBody3D
func chunk_box(pos: Vector3, size: Vector3, c: Color, collision: bool = true, rot_y: float = 0.0, layer: int = 1) -> StaticBody3D:
	var body := _box(pos, size, _mat(c), collision, rot_y, layer)
	if body.get_parent():
		body.get_parent().remove_child(body)
	return body

## 圆柱（默认无碰撞），返回 Node3D
func chunk_cyl(pos: Vector3, r: float, h: float, c: Color, collision: bool = false, layer: int = 1) -> Node3D:
	var body := _cyl(pos, r, h, _mat(c), collision, layer)
	if body.get_parent():
		body.get_parent().remove_child(body)
	return body

## 球体（冰岩/雪球），带碰撞，返回 StaticBody3D
func chunk_sphere(pos: Vector3, rad: float, c: Color, collision: bool = true, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 0 if layer == 4 else 1
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = rad
	sm.height = rad * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _mat(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mi)
	if collision:
		var cs := CollisionShape3D.new()
		var ss := SphereShape3D.new()
		ss.radius = rad
		cs.shape = ss
		body.add_child(cs)
	return body

## 圆锥（冰刺），带碰撞，返回 StaticBody3D
func chunk_cone(pos: Vector3, r: float, h: float, c: Color, collision: bool = true, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 0 if layer == 4 else 1
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 9
	mi.mesh = cm
	mi.material_override = _mat(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mi)
	if collision:
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = r
		cy.height = h
		cs.shape = cy
		body.add_child(cs)
	return body

func _ground_y(x: float, z: float) -> float:
	return height_at(x, z)

func _place(node: Node3D, x: float, z: float, y_off := 0.0) -> void:
	node.position = Vector3(x, _ground_y(x, z) + y_off, z)
	add_child(node)

# =====================================================================
# 材质
# =====================================================================

var _mat_cache := {}
var _snow_pile: ShaderMaterial = null

## 通用表面材质：程序化混凝土/砖/木/金属 + 风积雪（取代原来的纯色 StandardMaterial3D）
func _mat(c: Color, rough := 0.9, metal := 0.0, kind := -1.0, snow := 1.0, grime := 1.0) -> ShaderMaterial:
	if kind < 0.0:
		# 由粗糙度/金属度反推表面类型，保持所有既有调用点的观感语义
		if metal > 0.45:
			kind = 3.0
		elif c.r > 0.55 and c.g > 0.55 and c.b > 0.55 and rough <= 0.35:
			kind = 3.0
		else:
			kind = 0.0
	var key := "%s|%.2f|%.2f|%.1f|%.2f|%.2f" % [c.to_html(), rough, metal, kind, snow, grime]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER_SURFACE
	m.set_shader_parameter("base_color", c)
	m.set_shader_parameter("roughness_v", rough)
	m.set_shader_parameter("metallic_v", metal)
	m.set_shader_parameter("surface_kind", kind)
	m.set_shader_parameter("snow_amount", snow)
	m.set_shader_parameter("grime", grime)
	_mat_cache[key] = m
	return m

## 立面基色：一座小镇不该只有一种灰。
## 取一组被冻裂、被风化过的旧建材色，按建筑位置哈希稳定取用——
## 同一个坐标永远得到同一个颜色，读档后小镇不会"换装"。
## 色相全部压在中低饱和，只靠明度与冷暖拉开差别，才协调不花。
const FACADE_PALETTE := [
	Color(0.395, 0.410, 0.435),   # 旧混凝土（冷灰）
	Color(0.455, 0.430, 0.390),   # 发黄的水刷石
	Color(0.360, 0.290, 0.265),   # 褪色砖墙
	Color(0.255, 0.310, 0.320),   # 剥落的墨绿漆
	Color(0.420, 0.355, 0.300),   # 锈蚀的旧木
	Color(0.470, 0.465, 0.450),   # 泛白的石棉板
	Color(0.330, 0.340, 0.370),   # 深灰水泥
	Color(0.500, 0.455, 0.420),   # 米色涂料（快掉光了）
]

func _facade_base(x: float, z: float, salt := 0.0) -> Color:
	var h := absf(sin(x * 37.13 + z * 91.71 + salt) * 43758.5453)
	var i := int(h) % FACADE_PALETTE.size()
	return FACADE_PALETTE[i]

## 玻璃（窗）：霜花 + 极少数的室内残光
func _mat_glass(c := Color(0.055, 0.075, 0.105), glow := 0.0, tint := Color(1.0, 0.70, 0.40)) -> ShaderMaterial:
	var key := "glass|%s|%.2f|%s" % [c.to_html(), glow, tint.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER_SURFACE
	m.set_shader_parameter("base_color", c)
	m.set_shader_parameter("roughness_v", 0.30)
	m.set_shader_parameter("metallic_v", 0.0)
	m.set_shader_parameter("surface_kind", 4.0)
	m.set_shader_parameter("snow_amount", 0.22)
	m.set_shader_parameter("window_glow", glow)
	m.set_shader_parameter("window_tint", tint)
	_mat_cache[key] = m
	return m

## 少数窗亮着灯（同一个位置永远得到同一个结果）
## 比例不能太低：一栋楼全黑就只是一个剪影，夜里整座城会读成"没人住"。
## 也不能太高：满城灯火会把冰封末世读成节日。约四分之一。
func _win_glow(x: float, z: float) -> float:
	var h := absf(fmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0))
	if h < 0.26:
		return randf_range(0.55, 1.0)
	return 0.0

## 发光体：路灯灯面 / 招牌 / 加油机屏。
## 白天是一块脏玻璃，入夜整片透出暖光——夜景里唯一的暖色锚点。
func _mat_lamp(glow := 2.2, seed_v := 0.0) -> ShaderMaterial:
	var key := "lamp|%.2f|%.2f" % [glow, seed_v]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER_LAMP
	m.set_shader_parameter("glow_energy", glow)
	m.set_shader_parameter("seed_v", seed_v)
	_mat_cache[key] = m
	return m

## 砖石/混凝土专用
func _mat_brick(c: Color, rough := 0.88) -> ShaderMaterial:
	return _mat(c, rough, 0.0, 1.0)

## 木料专用
func _mat_wood(c: Color, rough := 0.85) -> ShaderMaterial:
	return _mat(c, rough, 0.0, 2.0)

## 金属专用（锈蚀）
func _mat_metal(c: Color, rough := 0.6, metal := 0.45) -> ShaderMaterial:
	return _mat(c, rough, metal, 3.0)

## 冰：内部透光的芯 + 表面霜 + 顶部积雪。
## 用专门 shader 而不是通用 surface：冰必须有半透的体感，
## 直接给一个浅蓝纯色只会读成塑料块。
func _mat_ice(core := Color(0.30, 0.52, 0.70), frost := 0.0) -> ShaderMaterial:
	var key := "ice|%s|%.2f" % [core.to_html(), frost]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER_ICE
	m.set_shader_parameter("ice_core", core)
	m.set_shader_parameter("frost_amount", frost)
	m.set_shader_parameter("seed_v", float(_mat_cache.size()) * 3.7)
	_mat_cache[key] = m
	return m

func _emissive(c: Color, e := 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m

# =====================================================================
# 通用盒体（带碰撞）
# =====================================================================

func _box(pos: Vector3, size: Vector3, mat: Material, collision: bool = true, rot_y: float = 0.0, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	body.collision_layer = layer
	body.collision_mask = 0 if layer == 4 else 1
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mi)
	if collision:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
	add_child(body)
	return body

func _cyl(pos: Vector3, r: float, h: float, mat: Material, collision: bool = false, layer: int = 1) -> Node3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = layer
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	body.add_child(mi)
	if collision:
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = r
		cy.height = h
		cs.shape = cy
		body.add_child(cs)
	add_child(body)
	return body

# =====================================================================
# 街道家具
# =====================================================================

func _gen_street_props() -> void:
	var z := -170.0
	var idx := 0
	var iron := _mat(Color(0.150, 0.158, 0.168), 0.72, 0.55, 3.0)
	while z <= 170.0:
		var broken := randf() < 0.35
		var side := 1.0 if idx % 2 == 0 else -1.0
		var lx := side * (ROAD_HALF + 1.6)
		var gy := _ground_y(lx, z)
		var pole_h := 2.2 if broken else 4.2
		var p := Vector3(lx, gy + pole_h / 2.0, z)
		# 灯座：一段压在地上、被雪半埋的方形基座。
		# 光杆子插在地上读作「一根棍」，有基座才读作「路灯」。
		_box(Vector3(lx, gy + 0.24, z), Vector3(0.34, 0.48, 0.34), iron, false, 0.0)
		var lamp := _cyl(p, 0.062, pole_h, iron)
		# 杆底一圈加厚（锥形过渡），避免细杆从方基座里「凭空长出来」
		_cyl(Vector3(lx, gy + 0.58, z), 0.105, 0.60, iron, false)
		if broken:
			# 断杆：绕基座倾倒，断口朝路面
			lamp.rotation.z = side * randf_range(0.6, 1.05)
			lamp.position = Vector3(lx + side * 0.35, gy + 0.95, z)
			# 断口露出的螺栓盘
			_cyl(Vector3(lx, gy + 0.42, z), 0.115, 0.10, iron, false)
		else:
			# 灯臂：从杆顶伸向路面的一小段横臂 + 悬垂的灯头
			var arm_x: float = -side * 0.62
			var arm := _box(Vector3(lx + arm_x * 0.5, gy + pole_h - 0.18, z),
				Vector3(absf(arm_x) + 0.10, 0.075, 0.075), iron, false)
			arm.rotation.z = side * 0.06
			# 灯罩：一个倒扣的小圆台，比平板灯头多一层「灯具」的意思
			var head_p := Vector3(lx + arm_x, gy + pole_h - 0.36, z)
			var shade := _cyl(head_p + Vector3(0.0, 0.06, 0.0), 0.20, 0.16, iron, false)
			shade.rotation.z = PI
			# 灯面：白天是一块脏玻璃，入夜整片透出来。
			# 灯罩下方再挂一盏真的点光源——雪地上那一小圈暖黄，
			# 是整条街唯一能证明"这里还通着电"的东西。
			_box(head_p + Vector3(0.0, -0.10, 0.0), Vector3(0.30, 0.05, 0.22),
				_mat_lamp(2.6, float(idx) * 1.7), false)
			var glow := OmniLight3D.new()
			glow.name = "LampGlow"
			glow.position = head_p + Vector3(0.0, -0.26, 0.0)
			glow.light_color = Color(1.0, 0.76, 0.46)
			# 能量与半径都要给足：9m/1.35 在城市尺度下等于没有灯——
			# 从 20m 外看，灯下那圈暖黄根本照不亮雪面，只剩下一个亮点。
			# 15m/3.4 仍然不够：站在街心往前看，最近的灯在 30m 外，
			# 正好落在光照范围之外，整条街一盏灯都不亮。
			# 街灯间距 24m，所以范围必须≥30m 才能让相邻两盏互相接上。
			glow.light_energy = 5.2
			glow.omni_range = 30.0
			glow.omni_attenuation = 1.15
			glow.shadow_enabled = false
			glow.light_specular = 0.35
			glow.distance_fade_enabled = true
			glow.distance_fade_begin = 70.0
			glow.distance_fade_length = 30.0
			add_child(glow)
			# 灯杆上的小牌：给城市一点「有人管理过」的痕迹
			if idx % 3 == 0:
				_box(Vector3(lx, gy + 2.05, z + 0.10), Vector3(0.035, 0.30, 0.20),
					_mat(Color(0.42, 0.40, 0.30), 0.80), false)
		z += 24.0
		idx += 1
	# 冻结的汽车
	for i in range(9):
		var cz := randf_range(-160.0, 160.0)
		var cx := (ROAD_HALF - 2.2) * (1.0 if randf() < 0.5 else -1.0)
		_make_car(cx, cz)
	# 坍塌的高架残段
	# 原来只是把一块 5x0.5x16 的板悬在离地 1.2m 的空中，
	# 摄像机一低头就看见一块悬空的黑板子，读作「雪里有个洞」。
	# 现在按桥的构造做：桥面 + 两侧防撞墙 + 两根立柱 + 断口处的钢筋，
	# 并且一端压进雪里、一端翘起来，才读得出「垮掉的高架」。
	for i in range(4):
		var hx := randf_range(-60.0, 60.0)
		var hz := randf_range(-150.0, 150.0)
		if absf(hx) < 24.0:
			hx += 46.0
		_gen_bridge_stub(hx, hz, randf_range(-0.4, 0.4))

## 一段垮掉的高架桥：桥面 + 防撞墙 + 立柱 + 断口钢筋
## 全部无碰撞（原版是有碰撞的，但这类残骸玩家本来就走不上去，
## 而且旧的碰撞体只在桥面那一块，反而容易在门口挡路）。
func _gen_bridge_stub(hx: float, hz: float, yaw: float) -> void:
	var gy := _ground_y(hx, hz)
	var deck_w := randf_range(6.0, 8.4)
	var deck_len := randf_range(13.0, 19.0)
	# 整段桥面一头扎进雪里、一头翘起来
	var pitch := randf_range(-0.20, -0.05)
	var mat := _mat(_facade_base(hx, hz, 11.3), 0.92)
	var deck_y := gy + randf_range(1.1, 1.9)
	var deck := _box(Vector3(hx, deck_y, hz), Vector3(deck_w, 0.55, deck_len), mat, false, yaw)
	deck.rotation.x = pitch
	# 桥面沿它的轴向翘起后，两端高度不一样；用同一个变换推两侧构件的位置
	var basis := deck.transform.basis
	var fwd := (basis * Vector3(0.0, 0.0, 1.0)).normalized()

	# 两侧防撞墙：高度只有 0.75m，但它是「这是桥不是板」的关键读点
	for side in [-1.0, 1.0]:
		var off := basis * Vector3(side * (deck_w * 0.5 - 0.22), 0.55, 0.0)
		var wall := _box(deck.position + off, Vector3(0.30, 0.78, deck_len * 0.94), mat, false, yaw)
		wall.rotation.x = pitch
		# 墙顶压一道雪
		var snow := _box(deck.position + off + basis * Vector3(0.0, 0.46, 0.0),
			Vector3(0.42, 0.14, deck_len * 0.94), _mat(Color(0.815, 0.855, 0.925), 0.95), false, yaw)
		snow.rotation.x = pitch

	# 立柱：只在「还没塌下去」的那一端留两根，另一端是断的
	var pier_end: float = deck_len * 0.30
	for side in [-1.0, 1.0]:
		var px: float = hx + (basis * Vector3(side * (deck_w * 0.34), 0.0, pier_end)).x
		var pz: float = hz + (basis * Vector3(side * (deck_w * 0.34), 0.0, pier_end)).z
		var pg := _ground_y(px, pz)
		var ptop: float = deck_y - 0.3 + (basis * Vector3(0.0, 0.0, pier_end)).y + gy * 0.0
		var ph: float = maxf(ptop - pg, 0.8)
		_cyl(Vector3(px, pg + ph * 0.5, pz), 0.30, ph, mat, true)

	# 断口：十几根戳出来的钢筋，是残骸最强的「坏掉了」信号
	var cut := basis * Vector3(0.0, 0.0, -deck_len * 0.5)
	var cut_pos: Vector3 = deck.position + cut
	for k in range(14):
		var jx := randf_range(-deck_w * 0.42, deck_w * 0.42)
		var jy := randf_range(-0.22, 0.22)
		var base: Vector3 = cut_pos + basis * Vector3(jx, jy, 0.0)
		var leak := randf_range(0.5, 1.6)
		var tip: Vector3 = base + (basis * Vector3(randf_range(-0.30, 0.30), randf_range(-0.20, 0.35), -1.0)).normalized() * leak
		_wire_seg(base, tip, randf_range(0.020, 0.038),
			_mat(Color(0.34, 0.24, 0.20), 0.78, 0.55, 3.0))

	# 桥下的雪堆：让桥面看起来是「陷进去」而不是「浮着」
	_drift(Vector3(hx, gy + 0.05, hz), deck_w * 0.9, 1.4, deck_len * 0.55, yaw)

## 一辆被冻在路上的车
## 原来是一个 2x0.85x4.4 的方块加四个水平的圆盘，读作「雪堆里一块砖」。
## 车身是玩家在主街上最常擦身而过的东西，它必须一眼读出「车」：
## 所以按真车结构做——底盘裙边、引擎盖、行李厢、倾斜的风挡、车顶、
## 轮拱里的轮子（轴向必须沿 X，否则就是一个躺着的盘子）、保险杠、大灯。
func _make_car(x: float, z: float) -> void:
	var y := _ground_y(x, z)
	var yaw := randf() * TAU
	var base := Vector3(x, y, z)
	var rot := Basis(Vector3.UP, yaw)
	# 车漆：冰封多年，颜色只剩低饱和的几种
	var paint: Color = [
		Color(0.335, 0.110, 0.105),   # 暗红
		Color(0.115, 0.148, 0.205),   # 藏青
		Color(0.185, 0.192, 0.178),   # 军绿灰
		Color(0.405, 0.385, 0.345),   # 米白
		Color(0.150, 0.200, 0.172),   # 墨绿
	][randi() % 5]
	var body_mat := _mat(paint, 0.62, 0.35, 3.0)
	var dark := _mat(Color(0.110, 0.115, 0.125), 0.80, 0.12)
	var glass := _mat_glass(Color(0.046, 0.060, 0.080), 0.0)

	# 主车身（资源点的挂载基准，位置语义不能改）
	var body := _box(base + rot * Vector3(0.0, 0.72, 0.0), Vector3(1.94, 0.72, 4.30), body_mat, true, yaw)
	# 底盘裙边：让侧面有一道投影线，车身才不是一块实心砖
	_box(base + rot * Vector3(0.0, 0.40, 0.0), Vector3(1.86, 0.34, 4.10), dark, false, yaw)
	# 引擎盖 / 行李厢：比车顶低一档，压出三厢车的轮廓
	var hood := _box(base + rot * Vector3(0.0, 1.06, -1.30), Vector3(1.80, 0.20, 1.42), body_mat, false, yaw)
	hood.rotation = Vector3(-0.045, yaw, 0.0)
	var trunk := _box(base + rot * Vector3(0.0, 1.05, 1.60), Vector3(1.80, 0.18, 0.98), body_mat, false, yaw)
	trunk.rotation = Vector3(0.035, yaw, 0.0)
	# 驾驶仓玻璃 + 车顶
	_box(base + rot * Vector3(0.0, 1.33, 0.10), Vector3(1.76, 0.58, 2.14), glass, false, yaw)
	var roof := _box(base + rot * Vector3(0.0, 1.63, 0.10), Vector3(1.72, 0.11, 2.02), body_mat, false, yaw)
	roof.rotation = Vector3(0.0, yaw, 0.0)
	# 前后风挡：倾斜的薄片，是「车」这个形状最强的读点
	var windshield := _box(base + rot * Vector3(0.0, 1.34, -1.02), Vector3(1.66, 0.62, 0.09), glass, false, yaw)
	windshield.rotation = Vector3(deg_to_rad(-26.0), yaw, 0.0)
	var rear_glass := _box(base + rot * Vector3(0.0, 1.33, 1.18), Vector3(1.64, 0.54, 0.09), glass, false, yaw)
	rear_glass.rotation = Vector3(deg_to_rad(22.0), yaw, 0.0)
	# 保险杠
	_box(base + rot * Vector3(0.0, 0.56, -2.16), Vector3(1.88, 0.26, 0.16), dark, false, yaw)
	_box(base + rot * Vector3(0.0, 0.56, 2.16), Vector3(1.88, 0.26, 0.16), dark, false, yaw)
	# 轮子：圆柱的轴向必须转到 X（绕 Z 转 90°），否则是一个躺着的圆盘
	for wx in [-0.94, 0.94]:
		for wz in [-1.42, 1.42]:
			var wp: Vector3 = base + rot * Vector3(wx, 0.37, wz)
			var wheel := _cyl(wp, 0.37, 0.24, _mat(Color(0.098, 0.098, 0.105), 0.92), false)
			wheel.rotation = Vector3(0.0, yaw, PI / 2.0)
			_box(base + rot * Vector3(wx * 1.02, 0.74, wz), Vector3(0.12, 0.62, 0.94), dark, false, yaw)
	# 大灯：只在夜里反射一点冷光，不是亮的
	for sx in [-1.0, 1.0]:
		var lamp := _mat_glass(Color(0.30, 0.29, 0.24), 0.10)
		_box(base + rot * Vector3(sx * 0.62, 0.90, -2.10), Vector3(0.44, 0.20, 0.10), lamp, false, yaw)
	# 埋住轮胎的雪：车是被冻在路上的，不是停在路上
	_drift(base + rot * Vector3(0.0, 0.02, -1.30), 1.05, 0.34, 0.55, yaw)
	_drift(base + rot * Vector3(0.0, 0.02, 1.35), 1.00, 0.30, 0.50, yaw)
	_drift(base + rot * Vector3(-1.02, 0.02, 0.0), 0.44, 0.26, 1.70, yaw)
	var node := ResourceNode.new()
	node.setup({
		"id": "car", "name": "冻结的汽车", "uses": 2,
		"loot": [
			{"id": "scrap", "min": 1, "max": 2, "chance": 0.8},
			{"id": "wrench", "min": 1, "max": 1, "chance": 0.25},
			{"id": "flashlight", "min": 1, "max": 1, "chance": 0.15},
			{"id": "cloth", "min": 1, "max": 2, "chance": 0.5},
		],
	})
	node.position = body.position + Vector3(0, 1.4, 0)
	add_child(node)

# =====================================================================
# 可进入建筑：便利店 / 保安亭 / 门房 / 墙根
# =====================================================================

## 建筑的「三次轮廓」：墙裙、檐口、屋顶压顶。
## 纯装饰、全部无碰撞——门口通行路径与测试断言不受影响。
## 没有这三道线，房子会读成一坨方盒子；有了它们，剪影才有"建筑"的秩序感。
func _trim_building(c: Vector3, w: float, d: float, wall_h: float, t := 0.25) -> void:
	var hw := w / 2.0 + t / 2.0
	var hd := d / 2.0 + t / 2.0
	# 收边件用同一立面色的深浅变化，才像"同一栋楼的一部分"，
	# 而不是给灰盒子套了一圈白塑料条。
	var f := _facade_base(c.x, c.z)
	var plinth := _mat(f * 0.72, 0.94)
	var cornice := _mat(f * 1.10, 0.86)
	# ---- 墙裙：贴地一圈，比墙面凸出 7cm，高处受光、低处积灰 ----
	var ph := 0.34
	for s in [-1.0, 1.0]:
		_box(Vector3(c.x, c.y + ph * 0.5, c.z + s * (hd + 0.07)), Vector3(w + t + 0.14, ph, 0.14), plinth, false)
		_box(Vector3(c.x + s * (hw + 0.07), c.y + ph * 0.5, c.z), Vector3(0.14, ph, d + t + 0.14), plinth, false)
	# ---- 檐口：顶一圈薄檐，制造明暗分界与投影 ----
	var ch := 0.16
	var over := 0.20
	for s in [-1.0, 1.0]:
		_box(Vector3(c.x, c.y + wall_h - ch * 0.5, c.z + s * (hd + over * 0.5)), Vector3(w + t + over * 2.0, ch, over), cornice, false)
		_box(Vector3(c.x + s * (hw + over * 0.5), c.y + wall_h - ch * 0.5, c.z), Vector3(over, ch, d + t + 0.02), cornice, false)
	# ---- 壁柱 / 分段：把一整面长墙切成几跨 ----
	# 这是"建筑 vs 竖着的板"最关键的一层，而它只能是几何，不能是贴图。
	# 一面 15m 的墙如果是一个盒子，无论 shader 画多少板缝，剪影上都是一条直线；
	# 光不会在它上面产生任何明暗转折，眼睛立刻判定"假的"。
	# 加一排凸出 8~14cm 的壁柱之后，每一跨之间都会出现一条真正的明暗交界与自阴影，
	# 墙开始有"进深"，窗户也有了可以被夹住的凹进关系。
	_pilasters(c, w, d, wall_h, t)
	# ---- 墙脚雪堆：房子不能像从雪里"长出来"，要有一圈被风堆出来的雪 ----
	for k in range(7):
		var ang := TAU * float(k) / 7.0 + randf_range(-0.25, 0.25)
		var rx := hw + randf_range(0.30, 0.70)
		var rz := hd + randf_range(0.30, 0.70)
		_drift(Vector3(c.x + cos(ang) * rx, c.y + 0.02, c.z + sin(ang) * rz),
			randf_range(1.7, 3.4), randf_range(0.16, 0.30), randf_range(0.8, 1.5), ang + PI * 0.5)

## 立面壁柱：按跨距把四面长墙分段。
## 这不改变任何碰撞体（全部 collision=false），只是给剪影加转折。
##
## 跨距按建筑尺寸取整：3.2~4.2m 一跨，是 1970~80 年代砖混/装配式立面最常见的
## 开间模数。太少（2 跨）像临时棚屋，太多（每米一根）像栅栏。
## 柱子宽度 0.22~0.34m，凸出 0.10m——必须超出檐口 0.20m 以内，
## 否则侧面掠光时会在墙上投下一条比自己还黑的长影。
func _pilasters(c: Vector3, w: float, d: float, wall_h: float, t: float) -> void:
	var hw := w / 2.0 + t / 2.0
	var hd := d / 2.0 + t / 2.0
	var f := _facade_base(c.x, c.z)
	# 双色：柱子本身比墙面亮一档（更多面朝光），柱头再压一档
	var pw := 0.26
	var ph := 0.11
	var pmat := _mat(f * 1.06, 0.90)
	var capmat := _mat(f * 0.90, 0.90)
	# 每面墙独立决定：跨数 = round(长度/3.7)，最少 2 跨
	for s in [-1.0, 1.0]:
		var sf: float = s
		# ---- 沿 x 的两面墙（前/后）----
		var n_x := clampi(int(round(w / 3.7)), 2, 5)
		for k in range(1, n_x):
			var px: float = c.x - w * 0.5 + w * float(k) / float(n_x)
			var pz: float = c.z + sf * (hd + ph * 0.5)
			_box(Vector3(px, c.y + wall_h * 0.5, pz), Vector3(pw, wall_h - 0.05, ph), pmat, false)
			# 柱头：柱顶一圈略宽的方头，比"一整根竖条"多一层结构
			_box(Vector3(px, c.y + wall_h - 0.22, pz), Vector3(pw + 0.10, 0.14, ph + 0.06), capmat, false)
		# ---- 沿 z 的两面墙（左/右）----
		var n_z := clampi(int(round(d / 3.7)), 2, 4)
		for k in range(1, n_z):
			var pz2: float = c.z - d * 0.5 + d * float(k) / float(n_z)
			var px2: float = c.x + sf * (hw + ph * 0.5)
			_box(Vector3(px2, c.y + wall_h * 0.5, pz2), Vector3(ph, wall_h - 0.05, pw), pmat, false)
			_box(Vector3(px2, c.y + wall_h - 0.22, pz2), Vector3(ph + 0.06, 0.14, pw + 0.10), capmat, false)
	# ---- 腰线：一层水平的分割，把 2.9m 的墙分成"下重上轻"两段 ----
	# 单段整墙在低视角下永远读作"一块布"。腰线是最便宜有效的打破手段。
	if wall_h > 2.8:
		var bw := _mat(f * 0.94, 0.92)
		var by: float = c.y + wall_h * 0.62
		for s2 in [-1.0, 1.0]:
			var s2f: float = s2
			_box(Vector3(c.x, by, c.z + s2f * (hd + 0.03)), Vector3(w + t, 0.09, 0.07), bw, false)
			_box(Vector3(c.x + s2f * (hw + 0.03), by, c.z), Vector3(0.07, 0.09, d + t), bw, false)

## 檐下阴影槽：檐口与墙面之间那道 4cm 的深缝。
## 没有它，檐口只是一条贴在墙上的白线；有了它，檐口才"挑出去"。
func _eave_shadow(c: Vector3, w: float, d: float, wall_h: float, t: float) -> void:
	var hw := w / 2.0 + t / 2.0
	var hd := d / 2.0 + t / 2.0
	var f := _facade_base(c.x, c.z)
	var dark := _mat(f * 0.52, 0.96)
	var gap := 0.055
	for s in [-1.0, 1.0]:
		_box(Vector3(c.x, c.y + wall_h - 0.20, c.z + s * (hd + gap * 0.5)),
			Vector3(w + t, 0.055, gap), dark, false)
		_box(Vector3(c.x + s * (hw + gap * 0.5), c.y + wall_h - 0.20, c.z),
			Vector3(gap, 0.055, d + t), dark, false)

## 积雪丘：压扁的球体 + 顶点扰动，读起来是"被风堆出来的"，而不是一块方块。
## 无碰撞、不参与物理，只为了画面。
## 材质必须和地形雪面同源（风蚀纹 / 雪壳 / 雪粒），否则雪堆读成"光滑的白塑料抱枕"，
## 和脚下的雪原完全是两种物质。
##
## 几何也必须扰动：一个未经处理的 SphereMesh 是一个完美的椭球，
## 它出现在任何地方都在告诉玩家"这是程序生成的"。真实的雪堆是被风从一侧
## 啃出来的：迎风面收得紧、背风面拖出一条长尾、轮廓是圆钝但不规则的。
func _drift(pos: Vector3, w: float, h: float, d: float, rot := 0.0, mat: Material = null) -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	# 分段数翻倍：原先 20x10 下，一个被拉长到 4~6 米的雪堤每个面片近 0.5 米，
	# 顶点扰动根本表达不出"风蚀的棱"，轮廓永远是光滑的蛋白霜。
	sm.radial_segments = 32
	sm.rings = 18
	# 顶点扰动：每个雪堆一个独立相位，用世界坐标做参数保证读档后形状稳定。
	var seed_v: float = pos.x * 0.37 + pos.z * 0.61
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	# 风向：世界 +x 偏一点 -z。真实雪堤是垂直风向堆起来的，
	# 迎风面被削成一段直坡，背风面拖出长尾——不是左右对称的胖球。
	var wind := Vector2(0.86, -0.51)
	for i in range(verts.size()):
		var v := verts[i]
		var a := atan2(v.z, v.x)
		# 低频轮廓起伏（3~4 个大瓣），保证轮廓不圆
		var wob := sin(a * 2.0 + seed_v) * 0.10 + sin(a * 3.0 + seed_v * 1.7) * 0.06
		var lee := 1.0 + 0.22 * clampf(v.x * 2.0, -0.6, 1.0)
		var k := (1.0 + wob) * lee
		# 迎风/背风不对称：把顶点沿风向推开，背风侧拉长、迎风侧压扁
		var flat := Vector2(v.x, v.z)
		var along := flat.dot(wind)
		var side := flat.dot(Vector2(-wind.y, wind.x))
		# 背风侧（along>0）延长到 1.5 倍，迎风侧收到 0.86
		var stretch := 1.0 + 0.34 * smoothstep(-0.5, 0.5, along / max(0.001, flat.length()))
		along *= stretch;
		# 顶部被风削平：高度越低越接近原形，接近顶端则压平并往前倾
		var hh := clampf(v.y * 2.0, -1.0, 1.0)
		var cap := smoothstep(0.35, 1.0, hh)
		var shear := cap * 0.16 * stretch
		flat = wind * along + Vector2(-wind.y, wind.x) * side;
		var nv := Vector3(flat.x * (1.0 + wob * 0.4) + wind.x * shear * 0.35,
			v.y * k, flat.y * (1.0 + wob * 0.4) + wind.y * shear * 0.35)
		# 顶面轻微下压 + 边缘的"雪檐"：让轮廓在光下有硬边
		if cap > 0.0:
			nv.y -= cap * 0.055
		verts[i] = nv
	arr[Mesh.ARRAY_VERTEX] = verts
	if norms.size() == verts.size():
		# 法线跟着重算，否则扰动后的表面还是椭球的明暗
		for i in range(norms.size()):
			var v := verts[i]
			var n := Vector3(v.x * 0.5, v.y * 2.0, v.z * 0.5)
			if n.length() > 0.0001:
				norms[i] = n.normalized()
		arr[Mesh.ARRAY_NORMAL] = norms
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, mat if mat != null else _snow_pile_mat())
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat if mat != null else _snow_pile_mat()
	mi.position = pos
	mi.rotation.y = rot
	mi.scale = Vector3(w, h * 2.0, d)
	add_child(mi)

## 雪堆材质（缓存复用，避免每堆一个 ShaderMaterial）
func _snow_pile_mat() -> ShaderMaterial:
	if _snow_pile != null:
		return _snow_pile
	var m := ShaderMaterial.new()
	m.shader = SHADER_SNOWPILE
	m.set_shader_parameter("seed_v", float(_mat_cache.size()) * 5.3)
	_snow_pile = m
	return m

## 门套：门洞两侧的竖向边框 + 顶上一块过梁，让洞口不是"一个洞"
func _trim_door(c: Vector3, side: String, wall_h: float, door_w := 1.5, t := 0.25) -> void:
	var frame := _mat(_facade_base(c.x, c.z) * 0.66, 0.9)
	var fw := 0.16
	var fh := wall_h - 0.7
	# 位置由调用方给出 c（门洞中心的世界坐标）
	for s in [-1.0, 1.0]:
		if side in ["left", "right"]:
			_box(c + Vector3(0, fh * 0.5, s * (door_w * 0.5 + fw * 0.5)), Vector3(t + 0.06, fh, fw), frame, false)
		else:
			_box(c + Vector3(s * (door_w * 0.5 + fw * 0.5), fh * 0.5, 0), Vector3(fw, fh, t + 0.06), frame, false)
	# 过梁（门楣下方的一条压边）
	if side in ["left", "right"]:
		_box(c + Vector3(0, fh + 0.03, 0), Vector3(t + 0.10, 0.10, door_w + fw * 2.0), frame, false)
	else:
		_box(c + Vector3(0, fh + 0.03, 0), Vector3(door_w + fw * 2.0, 0.10, t + 0.10), frame, false)

## 门口雨棚：一块小挑檐 + 两根细柱 + 一级被雪埋住的台阶。
## 这是「建筑体量」最便宜的一招：墙面是平的，但门口一旦伸出东西，
## 剪影上就多出一个凹进去的暗部，眼睛立刻读得出「这里能进人」。
## 全部无碰撞——门洞净宽 1.5m，柱子在 ±0.92m，玩家胶囊半径 0.4m，
## 加碰撞反而会在窄处把玩家卡住（control_test 就是测这个门）。
func _door_canopy(c: Vector3, side: String, wall_h: float, door_w := 1.5, t := 0.25) -> void:
	var along_x := side in ["left", "right"]
	var n := 1.0
	if side == "left":
		n = -1.0
	elif side == "right":
		n = 1.0
	elif side == "back":
		n = -1.0
	# 0.9m 深的挑檐，压在门楣上方
	var depth := 0.90
	var cw := door_w + 0.55
	var top := wall_h - 0.62
	var f := _facade_base(c.x, c.z)
	var canopy := _mat(f * 0.70, 0.90)
	var post := _mat(Color(0.150, 0.145, 0.140), 0.86, 0.30, 3.0)
	var off := (t * 0.5 + depth * 0.5)
	var cp := c + (Vector3(n * off, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, n * off))
	var slab: StaticBody3D
	if along_x:
		slab = _box(cp + Vector3(0, top, 0), Vector3(depth, 0.10, cw), canopy, false)
	else:
		slab = _box(cp + Vector3(0, top, 0), Vector3(cw, 0.10, depth), canopy, false)
	# 挑檐上的一层雪：朝上面积雪最厚，不铺雪的话它会读成一块塑料板
	if along_x:
		_box(cp + Vector3(0, top + 0.09, 0), Vector3(depth * 0.96, 0.06, cw * 0.98),
			_mat(Color(0.828, 0.868, 0.932), 0.95), false)
	else:
		_box(cp + Vector3(0, top + 0.09, 0), Vector3(cw * 0.98, 0.06, depth * 0.96),
			_mat(Color(0.828, 0.868, 0.932), 0.95), false)
	# 两根细柱：把挑檐「撑」起来，剪影上才有框
	for s in [-1.0, 1.0]:
		var px := door_w * 0.5 + 0.16
		var pp: Vector3 = c + (Vector3(n * (depth - 0.10), 0.0, s * px) if along_x
			else Vector3(s * px, 0.0, n * (depth - 0.10)))
		var gy := _ground_y(pp.x, pp.z)
		_cyl(Vector3(pp.x, (gy + c.y + top) * 0.5, pp.z), 0.055, maxf(c.y + top - gy, 0.4), post,
			false)
	# 台阶：一级 0.14m 高的水泥台，被雪盖了一半
	if along_x:
		_box(c + Vector3(n * 0.26, 0.0, 0), Vector3(0.56, 0.16, door_w + 0.30),
			_mat(f * 0.80, 0.94), false)
	else:
		_box(c + Vector3(0, 0.0, n * 0.26), Vector3(door_w + 0.30, 0.16, 0.56),
			_mat(f * 0.80, 0.94), false)

## 外墙立管：一根从墙脚走到檐口的落水管 + 两副卡箍 + 一只配电箱。
## 这一根细管子是「这是建筑不是盒子」最便宜的读点：
## 它把高墙切成有上下的两段，剪影上多一道竖线，人眼立刻就知道墙有多高。
## 全部无碰撞（贴着墙面 0.06m，玩家撞不到）。
func _wall_pipes(c: Vector3, side: String, wall_h: float, span: float) -> void:
	var along_x := side in ["left", "right"]
	var nx := 1.0 if side == "right" else -1.0
	var nz := 1.0 if side == "front" else -1.0
	var off := span * 0.5 + 0.07
	var base: Vector3 = c + (Vector3(nx * off, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, nz * off))
	# 落水管：深灰镀锌管，从天沟一直落到地面
	var pipe := _mat(Color(0.235, 0.240, 0.250), 0.74, 0.35, 3.0)
	var px := base + (Vector3(0.0, 0.0, span * 0.34) if along_x else Vector3(span * 0.34, 0.0, 0.0))
	var top := wall_h - 0.05
	_cyl(Vector3(px.x, c.y + top * 0.5, px.z), 0.055, top, pipe, false)
	# 卡箍：两个小方块，管子才不像贴纸
	for t in [0.28, 0.72]:
		_box(Vector3(px.x, c.y + top * float(t), px.z), Vector3(0.16, 0.06, 0.16), pipe, false)
	# 檐口的弯头：管子拐进墙里，不然是一根悬空的棍
	_box(Vector3(px.x, c.y + top + 0.04, px.z), Vector3(0.20, 0.10, 0.20), pipe, false)
	# 配电箱：一只挂在墙上、被雪压出斜顶的铁盒子
	var bx := base + (Vector3(0.0, 0.0, -span * 0.22) if along_x else Vector3(-span * 0.22, 0.0, 0.0))
	var bxp := Vector3(bx.x + (nx * 0.10 if along_x else 0.0), c.y + 1.45,
		bx.z + (nz * 0.10 if not along_x else 0.0))
	var box_size := Vector3(0.34, 0.46, 0.16) if along_x else Vector3(0.16, 0.46, 0.34)
	_box(bxp, box_size, _mat(Color(0.300, 0.310, 0.315), 0.70, 0.40, 3.0), false)
	# 箱顶的雪：朝上的面一定会积雪
	var snow_size := Vector3(0.36, 0.05, 0.18) if along_x else Vector3(0.18, 0.05, 0.36)
	_box(bxp + Vector3(0.0, 0.25, 0.0), snow_size, _mat(Color(0.815, 0.855, 0.925), 0.95), false)

## 屋顶杂物：空调外机 / 排风帽 / 天线 / 落水管出口。
## 平屋顶在那条天际线上原本是一条完美的水平线——
## 一条完美的水平线只能读作「一块板」。屋顶上必须长出东西。
func _roof_clutter(c: Vector3, y: float, w: float, d: float) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	var iron := _mat(Color(0.270, 0.278, 0.288), 0.70, 0.42, 3.0)
	var snow := _mat(Color(0.815, 0.855, 0.925), 0.95)
	# 空调冷凝机组：两三台高低不一的铁箱，侧面有散热格栅的深色薄片
	var units := randi_range(2, 3)
	for k in range(units):
		var ux: float = c.x + randf_range(-hw + 1.2, hw - 1.2)
		var uz: float = c.z + randf_range(-hd + 1.2, hd - 1.2)
		var uh := randf_range(0.42, 0.62)
		var uw := randf_range(0.72, 0.95)
		_box(Vector3(ux, y + uh * 0.5, uz), Vector3(uw, uh, uw * 0.62), iron, false, randf_range(-0.2, 0.2))
		_box(Vector3(ux, y + uh + 0.03, uz), Vector3(uw * 0.95, 0.05, uw * 0.58), snow, false)
		# 风扇网罩：一块比机身暗、比机身小的薄片，读作「有个洞」
		_box(Vector3(ux, y + uh * 0.55, uz + 0.01), Vector3(uw * 0.52, uw * 0.52, uw * 0.64),
			_mat(Color(0.115, 0.120, 0.128), 0.86, 0.30, 3.0), false)
	# 排风帽：一根细管 + 顶上倒扣的伞，最高的一件，负责在天际线上戳一个尖
	for k in range(2):
		var vx: float = c.x + randf_range(-hw + 0.9, hw - 0.9)
		var vz: float = c.z + randf_range(-hd + 0.9, hd - 0.9)
		var vh := randf_range(0.55, 1.05)
		_cyl(Vector3(vx, y + vh * 0.5, vz), 0.085, vh, iron, false)
		var cap := _cyl(Vector3(vx, y + vh + 0.06, vz), 0.19, 0.09, iron, false)
		cap.rotation.z = PI
	# 电视天线：几根细杆交叉，雪国老楼的标配
	if randf() < 0.65:
		var ax: float = c.x + randf_range(-hw + 1.0, hw - 1.0)
		var az: float = c.z + randf_range(-hd + 1.0, hd - 1.0)
		var ah := randf_range(1.6, 2.6)
		_cyl(Vector3(ax, y + ah * 0.5, az), 0.024, ah, _mat(Color(0.180, 0.185, 0.195), 0.80, 0.55, 3.0), false)
		for k in range(3):
			var bw := 0.72 - float(k) * 0.18
			_box(Vector3(ax, y + ah - 0.10 - float(k) * 0.16, az),
				Vector3(bw, 0.018, 0.018), _mat(Color(0.180, 0.185, 0.195), 0.80, 0.55, 3.0), false)

## 外挂消防梯：两道竖梯梁 + 三层小平台 + 一段斜下的爬梯。
## 挂在侧墙上时，它把一面 15m 长的白墙切成一格一格，
## 让「这栋楼有几层」这件事在剪影上直接读出来。
## 全部无碰撞：玩家不可能爬上去，加碰撞只会在墙边形成一道看不见的坎。
func _fire_escape(c: Vector3, side: String, wall_h: float, span: float) -> void:
	var along_x := side in ["left", "right"]
	var nx := 1.0 if side == "right" else -1.0
	var nz := 1.0 if side == "front" else -1.0
	var off := span * 0.5 + 0.42
	var base: Vector3 = c + (Vector3(nx * off, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, nz * off))
	var steel := _mat(Color(0.195, 0.200, 0.210), 0.78, 0.55, 3.0)
	var snow := _mat(Color(0.815, 0.855, 0.925), 0.95)
	var pw := 1.7          # 平台沿墙长度
	# 层数按墙高推：平台必须挂在墙上，不能悬到檐口以上去
	var levels := 0
	var ly_probe := 1.5
	while ly_probe < wall_h - 0.55 and levels < 3:
		levels += 1
		ly_probe += 1.55
	for k in range(levels):
		var ly: float = c.y + 1.5 + float(k) * 1.55
		# 平台格栅：一块薄板，比栏杆暗
		_box(Vector3(base.x, ly, base.z), Vector3(pw if not along_x else 0.78, 0.06, 0.78 if not along_x else pw),
			_mat(Color(0.140, 0.145, 0.152), 0.86, 0.40, 3.0), false)
		# 平台上的雪：朝上的面
		_box(Vector3(base.x, ly + 0.06, base.z),
			Vector3(pw * 0.94 if not along_x else 0.70, 0.04, 0.70 if not along_x else pw * 0.94), snow, false)
		# 外侧栏杆：两根立柱 + 一道扶手
		var edge: Vector3 = base + (Vector3(nx * 0.34, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, nz * 0.34))
		_box(edge + Vector3(0.0, 0.48, 0.0),
			Vector3(0.05, 0.05, pw) if not along_x else Vector3(pw, 0.05, 0.05), steel, false)
		for s in [-1.0, 1.0]:
			var ppos: Vector3 = edge + (Vector3(0.0, 0.0, s * pw * 0.46) if not along_x else Vector3(s * pw * 0.46, 0.0, 0.0))
			_box(ppos + Vector3(0.0, 0.24, 0.0), Vector3(0.05, 0.50, 0.05), steel, false)
	# 斜爬梯：从最下层平台拐下去，斜靠在墙边
	var ladder_bottom: Vector3 = c + (Vector3(nx * (off + 0.10), 0.0, pw * 0.55) if along_x
		else Vector3(pw * 0.55, 0.0, nz * (off + 0.10)))
	var ladder_top: Vector3 = base + Vector3(0.0, 1.5, 0.0)
	var steps := 8
	for k in range(steps):
		var t := float(k) / float(steps - 1)
		var sp: Vector3 = ladder_bottom.lerp(ladder_top, t)
		var gy := _ground_y(sp.x, sp.z)
		if sp.y < gy + 0.15:
			continue
		_box(sp, Vector3(0.46, 0.04, 0.05) if along_x else Vector3(0.05, 0.04, 0.46), steel, false)
	# 两道梯梁
	for s in [-1.0, 1.0]:
		var a: Vector3 = ladder_bottom + (Vector3(0.0, 0.0, s * 0.22) if along_x else Vector3(s * 0.22, 0.0, 0.0))
		var b: Vector3 = ladder_top + (Vector3(0.0, 0.0, s * 0.22) if along_x else Vector3(s * 0.22, 0.0, 0.0))
		_wire_seg(a, b, 0.028, steel)

## 窗套：窗洞四周一圈窗框 + 窗台外挑 + 窗上的积雪
func _trim_window(pos: Vector3, size: Vector3, face: String, lit := 0.0) -> void:
	## face: "z+" / "z-" / "x+" / "x-" 表示窗朝向
	var frame := _mat(Color(0.47, 0.475, 0.480), 0.74, 0.12)
	var fw := 0.09
	var fh := 0.09
	var depth := 0.10
	var glass := _mat_glass(Color(0.045, 0.058, 0.080), lit)
	var along_x := face.begins_with("z")
	var half_along := (size.x if along_x else size.z) * 0.5
	var half_up := size.y * 0.5
	# 玻璃本体（略微内凹于墙面，形成窗洞的阴影）
	_box(pos, size, glass, false)
	if along_x:
		var nz := 1.0 if face == "z+" else -1.0
		# 上下框
		for s in [-1.0, 1.0]:
			_box(pos + Vector3(0, s * (half_up + fh * 0.5), nz * depth * 0.4),
				Vector3(size.x + fw * 2.0, fh, depth), frame, false)
		# 左右框
		for s in [-1.0, 1.0]:
			_box(pos + Vector3(s * (half_along + fw * 0.5), 0, nz * depth * 0.4),
				Vector3(fw, size.y + fh * 2.0, depth), frame, false)
		# 窗台（外挑，上面一层薄雪）
		_box(pos + Vector3(0, -half_up - fh - 0.05, nz * 0.09), Vector3(size.x + 0.34, 0.08, 0.26), frame, false)
		_box(pos + Vector3(0, -half_up - fh + 0.00, nz * 0.10),
			Vector3(size.x + 0.30, 0.05, 0.24), _mat(Color(0.835, 0.875, 0.940), 0.95), false)
		# 窗楣积雪
		_box(pos + Vector3(0, half_up + fh + 0.05, nz * 0.07), Vector3(size.x * 0.92, 0.06, 0.16),
			_mat(Color(0.835, 0.875, 0.940), 0.95), false)
	else:
		var nx := 1.0 if face == "x+" else -1.0
		for s in [-1.0, 1.0]:
			_box(pos + Vector3(nx * depth * 0.4, s * (half_up + fh * 0.5), 0),
				Vector3(depth, fh, size.z + fw * 2.0), frame, false)
		for s in [-1.0, 1.0]:
			_box(pos + Vector3(nx * depth * 0.4, 0, s * (half_along + fw * 0.5)),
				Vector3(depth, size.y + fh * 2.0, fw), frame, false)
		_box(pos + Vector3(nx * 0.09, -half_up - fh - 0.05, 0), Vector3(0.26, 0.08, size.z + 0.34), frame, false)
		_box(pos + Vector3(nx * 0.10, -half_up - fh + 0.00, 0),
			Vector3(0.24, 0.05, size.z + 0.30), _mat(Color(0.835, 0.875, 0.940), 0.95), false)
		_box(pos + Vector3(nx * 0.07, half_up + fh + 0.05, 0), Vector3(0.16, 0.06, size.z * 0.92),
			_mat(Color(0.835, 0.875, 0.940), 0.95), false)

func _make_room(cx: float, cz: float, w: float, d: float, wall_h: float, door: String) -> Dictionary:
	## door: left/right/front/back 之一（门洞开在哪面墙）
	var y := _ground_y(cx, cz)
	var facade := _facade_base(cx, cz)
	var mat_a := _mat(facade)
	var mat_b := _mat(facade * 0.86)
	# 地板：纯视觉。若做碰撞体，0.2m 台阶会让 CharacterBody3D 卡在门口进不去
	_box(Vector3(cx, y + 0.1, cz), Vector3(w, 0.2, d), mat_b, false)
	var t := 0.25
	var half_w := w / 2.0
	var half_d := d / 2.0
	var door_w := 1.5
	# 四面墙（门所在墙分三段）
	var walls := [
		{"side": "left",   "pos": Vector3(cx - half_w, y + wall_h / 2.0, cz), "size": Vector3(t, wall_h, d)},
		{"side": "right",  "pos": Vector3(cx + half_w, y + wall_h / 2.0, cz), "size": Vector3(t, wall_h, d)},
		{"side": "back",   "pos": Vector3(cx, y + wall_h / 2.0, cz - half_d), "size": Vector3(w, wall_h, t)},
		{"side": "front",  "pos": Vector3(cx, y + wall_h / 2.0, cz + half_d), "size": Vector3(w, wall_h, t)},
	]
	for wall in walls:
		if wall["side"] == door:
			var along := float(wall["size"].z if wall["side"] in ["left", "right"] else wall["size"].x)
			var seg := (along - door_w) / 2.0
			if seg > 0.05:
				if wall["side"] in ["left", "right"]:
					_box(wall["pos"] + Vector3(0, 0, -door_w / 2.0 - seg / 2.0), Vector3(t, wall_h, seg), mat_a)
					_box(wall["pos"] + Vector3(0, 0, door_w / 2.0 + seg / 2.0), Vector3(t, wall_h, seg), mat_a)
				else:
					_box(wall["pos"] + Vector3(-door_w / 2.0 - seg / 2.0, 0, 0), Vector3(seg, wall_h, t), mat_a)
					_box(wall["pos"] + Vector3(door_w / 2.0 + seg / 2.0, 0, 0), Vector3(seg, wall_h, t), mat_a)
				# 门楣
				if wall["side"] in ["left", "right"]:
					_box(wall["pos"] + Vector3(0, wall_h / 2.0 + 0.35, 0), Vector3(t, 0.7, door_w), mat_a)
				else:
					_box(wall["pos"] + Vector3(0, wall_h / 2.0 + 0.35, 0), Vector3(door_w, 0.7, t), mat_a)
		else:
			_box(wall["pos"], wall["size"], mat_a)

	# ---- 立面收边：墙裙 / 檐口 / 墙脚雪堆 / 门套 ----
	_trim_building(Vector3(cx, y, cz), w, d, wall_h, t)
	var door_pos := Vector3(cx, y, cz)
	match door:
		"left": door_pos = Vector3(cx - half_w, y, cz)
		"right": door_pos = Vector3(cx + half_w, y, cz)
		"front": door_pos = Vector3(cx, y, cz + half_d)
		"back": door_pos = Vector3(cx, y, cz - half_d)
	_trim_door(door_pos, door, wall_h, door_w, t)
	# 门头雨棚：让门口在剪影上凹进去一块
	# 便利店与仓库这类大跨度建筑不想要小雨棚，用 room 的返回值之外单独判断
	if wall_h < 3.4:
		_door_canopy(door_pos, door, wall_h, door_w, t)
	return {"center": Vector3(cx, y, cz), "y": y}

## 室内地面散落物：雪、碎纸、几个滚出来的罐子、一块塌下来的吊顶板。
## 空房间在任何引擎里都读作"还没做完的场景"；地上有东西，房间才有人住过。
func _interior_floors(c: Vector3, w: float, d: float) -> void:
	# 从门口吹进来的雪：靠门一侧厚、往里渐渐没有
	_drift(Vector3(c.x - w * 0.34, c.y, c.z), w * 0.20, 0.16, d * 0.44, 0.3)
	_drift(Vector3(c.x - w * 0.20, c.y, c.z + d * 0.30), w * 0.12, 0.10, d * 0.24, 1.1)
	# 碎纸/纸箱片：薄薄的浅色平面，贴着地面
	var paper := _mat(Color(0.560, 0.545, 0.500), 0.95)
	for k in range(9):
		var px: float = c.x + randf_range(-w * 0.42, w * 0.42)
		var pz: float = c.z + randf_range(-d * 0.42, d * 0.42)
		var pp := _box(Vector3(px, c.y + 0.035, pz), Vector3(randf_range(0.12, 0.26), 0.014, randf_range(0.16, 0.30)), paper, false, randf() * TAU)
		pp.rotation.z = randf_range(-0.05, 0.05)
	# 滚出来的罐头：小圆柱 + 一圈金属环
	for k in range(4):
		var kx: float = c.x + randf_range(-w * 0.36, w * 0.36)
		var kz: float = c.z + randf_range(-d * 0.36, d * 0.36)
		var can := _cyl(Vector3(kx, c.y + 0.06, kz), 0.055, 0.13,
			_mat(Color(0.400, 0.330, 0.250), 0.52, 0.42, 3.0), false)
		can.rotation = Vector3(PI * 0.5, randf() * TAU, randf_range(-0.3, 0.3))
	# 塌下来的一块吊顶板：斜靠在地上，边界不齐
	var dg := _box(Vector3(c.x + w * 0.26, c.y + 0.10, c.z - d * 0.28),
		Vector3(randf_range(1.0, 1.8), 0.05, randf_range(0.8, 1.4)),
		_mat(Color(0.480, 0.470, 0.440), 0.94), false, randf() * TAU)
	dg.rotation.x = randf_range(-0.16, 0.16)
	dg.rotation.z = randf_range(-0.20, 0.20)

func _gen_enterable_buildings() -> void:
	# ---- 便利店（苏醒日搜刮点）----
	var store := _make_room(17.0, -14.0, 10.0, 7.5, 3.2, "left")
	var sc: Vector3 = store["center"]
	var shelf := _mat_wood(Color(0.480, 0.425, 0.335), 0.88)
	_box(Vector3(sc.x + 4.2, sc.y + 1.1, sc.z - 2.2), Vector3(0.8, 2.2, 5.6), shelf)  # 货架
	_box(Vector3(sc.x + 4.2, sc.y + 1.1, sc.z + 2.4), Vector3(0.8, 2.2, 4.0), shelf)
	_box(Vector3(sc.x - 4.2, sc.y + 0.6, sc.z + 2.6), Vector3(2.0, 1.2, 1.4), _mat(Color(0.28, 0.33, 0.40), 0.42, 0.4, 3.0))  # 冰柜
	_box(Vector3(sc.x - 1.5, sc.y + 0.5, sc.z - 2.8), Vector3(2.6, 1.0, 0.9), _mat_wood(Color(0.400, 0.330, 0.255), 0.86))  # 柜台
	_add_node(sc + Vector3(3.6, 1.6, -2.2), "货架·即食", 2, [
		{"id": "canned", "min": 1, "max": 2, "chance": 0.75},
		{"id": "cloth", "min": 1, "max": 2, "chance": 0.6},
	])
	_add_node(sc + Vector3(3.6, 1.6, 2.4), "货架·杂物", 2, [
		{"id": "rope", "min": 1, "max": 2, "chance": 0.5},
		{"id": "bandage", "min": 1, "max": 1, "chance": 0.3},
	])
	_add_node(sc + Vector3(-4.2, 0.9, 2.6), "冰柜底", 2, [
		{"id": "bottle_water", "min": 1, "max": 2, "chance": 0.85},
		{"id": "ice_block", "min": 1, "max": 2, "chance": 0.6},
	])
	_add_node(sc + Vector3(-1.5, 1.1, -2.8), "柜台底下", 1, [
		{"id": "knife", "min": 1, "max": 1, "chance": 0.9},
		{"id": "scissors", "min": 1, "max": 1, "chance": 0.8},
		{"id": "backpack", "min": 1, "max": 1, "chance": 0.7},
		{"id": "matches", "min": 2, "max": 5, "chance": 0.9},
	])
	# 便利店内部：地面上的散落物与顶灯。
	# 一个空房间是读不出「这是便利店」的；地上有几罐滚出来的罐头、
	# 一辆翻倒的购物车、天花板还挂着两盏灭掉的灯管，故事才成立。
	_interior_floors(sc, 10.0, 7.5)
	# 收银机（一块歪着的方盒 + 掀开的钱箱）
	_box(Vector3(sc.x - 1.5, sc.y + 1.12, sc.z - 2.8), Vector3(0.46, 0.24, 0.38),
		_mat(Color(0.235, 0.230, 0.215), 0.66, 0.30, 3.0), false)
	_box(Vector3(sc.x - 1.5, sc.y + 1.30, sc.z - 2.62), Vector3(0.40, 0.14, 0.10),
		_mat_glass(Color(0.055, 0.070, 0.098), 0.0), false)
	# 翻倒的购物车：车篮 + 四轮 + 推把
	var cart := Vector3(sc.x + 1.4, sc.y, sc.z - 1.5)
	_box(cart + Vector3(0.0, 0.42, 0.0), Vector3(0.52, 0.34, 0.78),
		_mat(Color(0.520, 0.530, 0.545), 0.55, 0.55, 3.0), false)
	var cart_r := _box(cart + Vector3(0.0, 0.42, 0.0), Vector3(0.50, 0.02, 0.76),
		_mat(Color(0.150, 0.155, 0.165), 0.8, 0.4, 3.0), false)
	cart_r.rotation.z = 0.9
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(cart + Vector3(sx * 0.20, 0.20, sz * 0.30), Vector3(0.05, 0.30, 0.05),
				_mat(Color(0.150, 0.155, 0.165), 0.8, 0.4, 3.0), false)
	# 两盏坏掉的灯管：外壳在、光没有了，但形状还在
	for k in range(2):
		var lx2: float = sc.x + (float(k) - 0.5) * 4.6
		_box(Vector3(lx2, sc.y + 3.02, sc.z), Vector3(1.5, 0.09, 0.26),
			_mat(Color(0.300, 0.305, 0.300), 0.72, 0.35, 3.0), false)
		_box(Vector3(lx2, sc.y + 2.94, sc.z), Vector3(1.36, 0.05, 0.17),
			_mat_glass(Color(0.240, 0.250, 0.235), 0.0), false)
	# ---- 保安亭（苏醒日过夜点）----
	var booth := _make_room(-13.5, 9.0, 3.8, 3.4, 2.6, "right")
	var bc: Vector3 = booth["center"]
	# 床（塌了一条脚）
	_box(Vector3(bc.x - 0.6, bc.y + 0.35, bc.z), Vector3(1.1, 0.25, 2.0), _mat_wood(Color(0.390, 0.300, 0.235), 0.9))
	_box(Vector3(bc.x - 0.6, bc.y + 0.62, bc.z), Vector3(1.0, 0.12, 1.8), _mat(Color(0.54, 0.515, 0.475), 0.95))
	var bed := BedInteract.new()
	bed.setup(Vector3(bc.x - 0.6, bc.y, bc.z))
	add_child(bed)
	_add_node(bc + Vector3(0.9, 0.8, 1.1), "亭内抽屉", 1, [
		{"id": "matches", "min": 1, "max": 3, "chance": 0.8},
		{"id": "bandage", "min": 1, "max": 1, "chance": 0.4},
	])
	# ---- 半塌门房（可占地基）----
	var gh := _ground_y(-24.0, -40.0)
	var gf := _facade_base(-24.0, -40.0, 5.3)
	var g1 := _box(Vector3(-24.0, gh + 1.4, -40.0), Vector3(0.3, 2.8, 5.0), _mat(gf), true, 0.5)
	var g2 := _box(Vector3(-26.2, gh + 1.2, -42.0), Vector3(5.0, 2.4, 0.3), _mat(gf * 1.04), true, 0.2)
	_box(Vector3(-23.4, gh + 0.3, -41.4), Vector3(4.4, 0.3, 2.2), _mat(Color(0.30, 0.24, 0.19), 0.92, 0.0, 2.0), true, 0.9)  # 塌落的房梁
	ruin_bodies.append(g1)
	ruin_bodies.append(g2)
	_add_foundation(Vector3(-24.0, gh, -40.0), "半塌的门房", "有半面墙能挡风，梁木还能拆。")
	# ---- 挡风墙根（可占地基）----
	var wy := _ground_y(34.0, -62.0)
	var wf := _facade_base(34.0, -62.0, 9.1)
	var w1 := _box(Vector3(34.0, wy + 1.5, -62.0), Vector3(7.0, 3.0, 0.4), _mat(wf), true, 0.15)
	var w2 := _box(Vector3(30.8, wy + 1.5, -58.6), Vector3(0.4, 3.0, 6.4), _mat(wf * 0.94), true, 0.0)
	ruin_bodies.append(w1)
	ruin_bodies.append(w2)
	_add_foundation(Vector3(33.4, wy, -60.4), "一段挡风的墙根", "背风，能拆出砖石。")
	# ---- 民居（可进入：倒塌的家具 + 可翻找的容器 + 一个睡觉点）----
	var house := _make_room(-30.0, 30.0, 8.0, 6.5, 2.8, "front")
	var hc: Vector3 = house["center"]
	_box(Vector3(hc.x - 2.6, hc.y + 0.45, hc.z - 1.2), Vector3(2.4, 0.9, 1.2), _mat(Color(0.340, 0.265, 0.235), 0.94))   # 倒伏的沙发
	_box(Vector3(hc.x + 2.8, hc.y + 0.75, hc.z + 1.6), Vector3(1.6, 1.5, 0.8), _mat_wood(Color(0.375, 0.315, 0.245), 0.9))   # 翻倒的立柜
	_box(Vector3(hc.x + 0.2, hc.y + 0.3, hc.z - 2.4), Vector3(2.0, 0.6, 0.9), _mat_wood(Color(0.410, 0.340, 0.275), 0.88))    # 茶几
	var hbed := BedInteract.new()
	hbed.setup(Vector3(hc.x + 2.9, hc.y, hc.z - 1.8))
	add_child(hbed)
	# 民居内部：雪、碎纸、掉下来的相框、翻倒的椅子
	_interior_floors(hc, 8.0, 6.5)
	# 掉在地上的相框：一块小方板 + 一圈木边，正面反扣在地上
	var fr := _box(Vector3(hc.x - 0.9, hc.y + 0.04, hc.z + 1.1), Vector3(0.32, 0.05, 0.26),
		_mat_wood(Color(0.400, 0.320, 0.245), 0.88), false, 0.7)
	fr.rotation.z = 0.03
	_box(Vector3(hc.x - 0.9, hc.y + 0.075, hc.z + 1.1), Vector3(0.26, 0.02, 0.20),
		_mat_glass(Color(0.150, 0.160, 0.170), 0.0), false, 0.7)
	# 翻倒的餐椅：两条腿朝上，是这个家"最后一秒"的物证
	var chair := _box(Vector3(hc.x + 0.9, hc.y + 0.24, hc.z + 2.2), Vector3(0.44, 0.05, 0.44),
		_mat_wood(Color(0.375, 0.300, 0.235), 0.90), false, 0.4)
	chair.rotation.z = 1.42
	# 墙上掉下来的挂钟（只留一个圆盘，指针停在某个时刻）
	var clock_face := _cyl(Vector3(hc.x - 3.2, hc.y + 1.75, hc.z + 1.0), 0.17, 0.05,
		_mat(Color(0.640, 0.620, 0.580), 0.86), false)
	clock_face.rotation.x = PI * 0.5
	# 壁炉/暖气片：靠背墙一条横向的铸铁肋
	for k in range(7):
		_box(Vector3(hc.x - 2.2 + float(k) * 0.19, hc.y + 0.52, hc.z - 3.1),
			Vector3(0.09, 0.86, 0.14), _mat(Color(0.290, 0.295, 0.305), 0.78, 0.32, 3.0), false)
	_add_node(hc + Vector3(2.8, 1.2, 1.6), "立柜抽屉", 2, [
		{"id": "cloth", "min": 1, "max": 2, "chance": 0.7},
		{"id": "rope", "min": 1, "max": 1, "chance": 0.4},
		{"id": "canned", "min": 1, "max": 1, "chance": 0.3},
	])
	_add_node(hc + Vector3(-2.6, 0.9, -1.2), "沙发缝里", 1, [
		{"id": "matches", "min": 1, "max": 3, "chance": 0.8},
		{"id": "bandage", "min": 1, "max": 1, "chance": 0.5},
	])

# =====================================================================
# 削顶废墟群（街道两侧，像被削掉了上半身）
# =====================================================================

func _gen_ruins() -> void:
	for i in range(14):
		var side := 1.0 if randf() < 0.5 else -1.0
		var bx := side * randf_range(13.0, 42.0)
		var bz := randf_range(-190.0, 190.0)
		if absf(bx) < 12.0:
			bx += 12.0
		var w := randf_range(8.0, 15.0)
		var d := randf_range(7.0, 12.0)
		var h := randf_range(3.0, 4.6)
		var by := _ground_y(bx, bz)
		var rface := _facade_base(bx, bz, 3.1)
		var b := _box(Vector3(bx, by + h / 2.0, bz), Vector3(w, h, d), _mat(rface), true, randf_range(-0.06, 0.06))
		# 削顶断面的"齐整"感：顶盖一层浅色
		_box(Vector3(bx, by + h + 0.06, bz), Vector3(w * 0.98, 0.12, d * 0.98), _mat(rface.lerp(Color(0.82, 0.86, 0.9), 0.45)), false, b.rotation.y)
		# 门洞（纯视觉）
		var door_side := randf()
		if door_side < 0.5:
			_box(Vector3(bx - side * (w / 2.0 + 0.02), by + 1.1, bz), Vector3(0.08, 2.2, 1.6), _mat(Color(0.08, 0.09, 0.1)), false)
		else:
			_box(Vector3(bx, by + 1.1, bz + side * 0.0 + (d / 2.0 + 0.02) * (1.0 if randf() < 0.5 else -1.0)), Vector3(1.6, 2.2, 0.08), _mat(Color(0.08, 0.09, 0.1)), false)
		# 门口瓦砾
		if randf() < 0.6:
			for k in range(3):
				_add_node(Vector3(bx - side * (w / 2.0 + randf_range(0.5, 2.0)), by, bz + randf_range(-2.0, 2.0)), "瓦砾堆", 2, [
					{"id": "stone", "min": 1, "max": 2, "chance": 0.7},
					{"id": "brick", "min": 1, "max": 2, "chance": 0.4},
					{"id": "wood", "min": 1, "max": 1, "chance": 0.3},
				])
		# ---- 细节：连体侧翼 ----
		if randf() < 0.5:
			var wing_h := randf_range(1.6, 2.8)
			var wing := _box(Vector3(bx + side * (w / 2.0 + 2.2), by + wing_h / 2.0, bz + randf_range(-3.0, 3.0)),
				Vector3(4.6, wing_h, randf_range(5.0, 8.0)), _mat(_facade_base(bx + side * 3.0, bz, 7.7)), true, randf_range(-0.3, 0.3))
			ruin_bodies.append(wing)
		# ---- 细节：垮塌角（斜插进地面的断块）----
		if randf() < 0.6:
			var col_b := _box(Vector3(bx - side * (w / 2.0 - 1.0), by + 0.5, bz + (d / 2.0 - 1.0) * (1.0 if randf() < 0.5 else -1.0)),
				Vector3(3.0, 2.4, 3.0), _mat(rface * 0.92), true)
			col_b.rotation.z = randf_range(0.5, 1.0) * side
			ruin_bodies.append(col_b)
		# ---- 细节：断面钢筋 ----
		if randf() < 0.55:
			for k in range(4):
				var rebar := _cyl(Vector3(bx + randf_range(-w / 2.0, w / 2.0), by + h + 0.3, bz + randf_range(-d / 2.0, d / 2.0)),
					randf_range(0.015, 0.025), randf_range(0.4, 1.1), _mat(Color(0.45, 0.3, 0.25), 0.7, 0.6))
				rebar.rotation = Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
		# ---- 细节：窗列 ----
		if randf() < 0.45:
			for k in range(3):
				_box(Vector3(bx - w / 2.0 + (w / 2.5) * (float(k) + 0.6), by + randf_range(1.2, 2.2), bz + side * (d / 2.0 + 0.03)),
					Vector3(1.0, 0.9, 0.06), _mat(Color(0.08, 0.09, 0.11)), false)
		ruin_bodies.append(b)
		# ---- 细节：参差断面（一栋楼不可能是被一刀切平的）----
		# 在顶部随机挑一处，补一段高出去的残墙与一段挑出来的楼板。
		# 齐平的天际线是所有"程序生成废墟"最先露馅的地方。
		var jag_x: float = bx + randf_range(-w * 0.30, w * 0.30)
		var jag_h: float = randf_range(0.7, 1.9)
		_box(Vector3(jag_x, by + h + jag_h * 0.5, bz + randf_range(-d * 0.25, d * 0.25)),
			Vector3(randf_range(1.4, w * 0.42), jag_h, randf_range(1.2, d * 0.42)),
			_mat(rface), true, b.rotation.y)
		# 楼板断口：一块斜挑出去約 1.4m 的薄板，边缘挂着钢筋
		if randf() < 0.75:
			var slab := _box(Vector3(bx + side * (w * 0.5 + 0.55), by + h - randf_range(0.1, 0.9), bz + randf_range(-d * 0.3, d * 0.3)),
				Vector3(1.5, 0.20, randf_range(1.6, d * 0.7)), _mat(rface * 0.94), false, b.rotation.y)
			slab.rotation.z = randf_range(-0.16, 0.34) * side
			for k in range(3):
				var hang := _cyl(Vector3(slab.position.x + side * randf_range(0.2, 0.7), slab.position.y - 0.42, slab.position.z + randf_range(-0.9, 0.9)),
					0.014, randf_range(0.5, 1.0), _mat(Color(0.45, 0.30, 0.25), 0.7, 0.6), false)
				hang.rotation.x = randf_range(-0.25, 0.25)
		# ---- 细节：外墙剥落露出一段砖砌（只有一小块，多了就成砌石墙）----
		if randf() < 0.55:
			var px2: float = bx - side * (w * 0.5 + 0.02)
			_box(Vector3(px2, by + randf_range(1.0, h - 0.8), bz + randf_range(-d * 0.3, d * 0.3)),
				Vector3(0.06, randf_range(0.8, 1.7), randf_range(1.0, 2.6)),
				_mat_brick(Color(0.330, 0.245, 0.215), 0.92), false, b.rotation.y)
		# ---- 细节：室内看得见的隔墙残片（门洞后面要有"里面"）----
		_box(Vector3(bx + randf_range(-w * 0.2, w * 0.2), by + randf_range(0.9, 1.6), bz + randf_range(-d * 0.25, d * 0.25)),
			Vector3(randf_range(1.4, 2.8), randf_range(1.2, 2.4), 0.16),
			_mat(rface * 0.78), false, randf_range(-0.5, 0.5))
		# ---- 细节：楼前堆到半人高的碎砖与雪 ----
		for k in range(randf_range(2.0, 4.0) as int):
			var db := _box(Vector3(bx + side * randf_range(w * 0.42, w * 0.72), by + 0.16, bz + randf_range(-d * 0.55, d * 0.55)),
				Vector3(randf_range(0.4, 1.1), randf_range(0.22, 0.5), randf_range(0.4, 1.1)),
				_mat(rface * randf_range(0.68, 0.94), 0.94), false, randf() * TAU)
			db.rotation.z = randf_range(-0.20, 0.20)
		_drift(Vector3(bx + side * randf_range(w * 0.3, w * 0.6), by, bz + randf_range(-d * 0.5, d * 0.5)),
			randf_range(1.6, 3.4), randf_range(0.4, 0.9), randf_range(1.4, 2.8), randf() * TAU)

# =====================================================================
# 自然景物：冰岩 / 枯树 / 冰脉 / 瓦砾
# =====================================================================

## 把一个已导入的模型资源摆到世界里，返回它的根节点
## （Blender 生成的 GLB 都以"模型自身脚底 = 原点、Y 轴朝上"为约定）
func _place_model(scene: PackedScene, pos: Vector3, scl: float, rot_y: float) -> Node3D:
	var inst: Node3D = scene.instantiate()
	inst.position = pos
	inst.rotation.y = rot_y
	inst.scale = Vector3.ONE * scl
	# 建模资源多为多网格子节点，统一补上阴影投射
	_apply_shadow(inst)
	add_child(inst)
	return inst

## 把模型里所有网格换成指定材质（GLB 自带的 Principled 只做基色，太死板）
func _set_model_material(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
	for c in n.get_children():
		_set_model_material(c, mat)

func _apply_shadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children():
		_apply_shadow(c)

func _gen_nature() -> void:
	for i in range(40):
		var ang := randf() * TAU
		var dist := randf_range(14.0, 260.0)
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		if absf(x) < 12.0:
			x += 14.0
		var y := _ground_y(x, z)
		var rad := randf_range(0.8, 3.2)
		var rock_scene: PackedScene = MOD_ICE_ROCK if randf() < 0.55 else MOD_ICE_ROCK_B
		var rock := _place_model(rock_scene, Vector3(x, y - 0.1, z),
			rad * 0.62, randf() * TAU)
		rock.scale.y *= randf_range(0.85, 1.25)
		_set_model_material(rock, _mat_ice(Color(0.28, 0.50, 0.66).lerp(Color(0.36, 0.58, 0.74), randf())))
		# 冰岩也可敲出冰块（长按采集：敲凿）
		if randf() < 0.5:
			var node := ResourceNode.new()
			node.setup({"id": "ice_rock", "name": "冰岩", "uses": 3, "gather_time": 1.2, "gather_verb": "敲凿",
				"loot": [
					{"id": "ice_block", "min": 1, "max": 2, "chance": 0.9},
					{"id": "stone", "min": 1, "max": 1, "chance": 0.35},
				]})
			node.position = Vector3(x, y + rad * 0.5, z)
			add_child(node)
	# 枯树
	for i in range(28):
		var ang := randf() * TAU
		var dist := randf_range(16.0, 250.0)
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		if absf(x) < 11.0:
			x += 13.0
		var y := _ground_y(x, z)
		var th := randf_range(2.6, 5.0)
		var tree_scene: PackedScene = MOD_DEAD_TREE if randf() < 0.6 else MOD_DEAD_TREE_B
		# 模型自带高度约 5.2m / 3.6m，按需要的树高缩放
		var base_h := 5.2 if tree_scene == MOD_DEAD_TREE else 3.6
		_place_model(tree_scene, Vector3(x, y - 0.05, z), th / base_h, randf() * TAU)
		# 枯木可伐（长按采集：砍伐，每击 1-2 木，3 击采空）
		var node := ResourceNode.new()
		node.setup({"id": "dead_tree", "name": "枯树", "uses": 3, "gather_time": 1.6, "gather_verb": "砍伐", "loot": [
			{"id": "wood", "min": 1, "max": 2, "chance": 0.9},
			{"id": "cloth", "min": 1, "max": 1, "chance": 0.1},
		]})
		node.position = Vector3(x, y + 0.8, z)
		add_child(node)
	# 冰脉（远处更冷更肥）
	for i in range(10):
		var ang := randf() * TAU
		var dist := randf_range(80.0, 250.0)
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		var y := _ground_y(x, z)
		var vein := MeshInstance3D.new()
		var om := SphereMesh.new()
		om.radial_segments = 4
		om.rings = 2
		om.radius = randf_range(0.7, 1.6)
		om.height = om.radius * 2.0
		vein.mesh = om
		vein.material_override = _mat_ice(Color(0.34, 0.60, 0.80), 0.7)
		vein.position = Vector3(x, y + 0.5, z)
		vein.scale = Vector3(1.0, randf_range(1.4, 2.4), 1.0)
		add_child(vein)
		var node := ResourceNode.new()
		node.setup({"id": "ice_vein", "name": "冰脉", "uses": 3, "gather_time": 1.4, "gather_verb": "开采", "loot": [
			{"id": "ice_block", "min": 2, "max": 4, "chance": 1.0},
			{"id": "clean_water", "min": 1, "max": 1, "chance": 0.25},
		]})
		node.position = vein.position
		add_child(node)
	# ---- 出生点附近的"教学林"：开局走几步就能砍到树、敲到冰 ----
	_spawn_grove()

## 苏醒点周边保证有可采之物：3 枯树 + 2 冰岩（固定位，改种子也在这儿）
func _spawn_grove() -> void:
	for tp in [Vector3(13.0, 0, 18.0), Vector3(-13.0, 0, 33.0), Vector3(16.0, 0, 8.0)]:
		var y := _ground_y(tp.x, tp.z)
		var th := randf_range(2.6, 4.0)
		var tree_scene: PackedScene = MOD_DEAD_TREE if randf() < 0.6 else MOD_DEAD_TREE_B
		var base_h := 5.2 if tree_scene == MOD_DEAD_TREE else 3.6
		_place_model(tree_scene, Vector3(tp.x, y - 0.05, tp.z), th / base_h, randf() * TAU)
		var node := ResourceNode.new()
		node.setup({"id": "dead_tree", "name": "枯树", "uses": 3, "gather_time": 1.6, "gather_verb": "砍伐", "loot": [
			{"id": "wood", "min": 1, "max": 2, "chance": 0.9},
			{"id": "cloth", "min": 1, "max": 1, "chance": 0.1},
		]})
		node.position = Vector3(tp.x, y + 0.8, tp.z)
		add_child(node)
	for rp in [Vector3(12.0, 0, 38.0), Vector3(-15.0, 0, 20.0)]:
		var ry := _ground_y(rp.x, rp.z)
		var rad := randf_range(1.2, 2.0)
		var rock_scene: PackedScene = MOD_ICE_ROCK if randf() < 0.55 else MOD_ICE_ROCK_B
		var rock2 := _place_model(rock_scene, Vector3(rp.x, ry - 0.1, rp.z), rad * 0.62, randf() * TAU)
		_set_model_material(rock2, _mat_ice(Color(0.30, 0.52, 0.70)))
		var node2 := ResourceNode.new()
		node2.setup({"id": "ice_rock", "name": "冰岩", "uses": 3, "gather_time": 1.2, "gather_verb": "敲凿", "loot": [
			{"id": "ice_block", "min": 1, "max": 2, "chance": 0.9},
			{"id": "stone", "min": 1, "max": 1, "chance": 0.35},
		]})
		node2.position = Vector3(rp.x, ry + rad * 0.5, rp.z)
		add_child(node2)

# =====================================================================
# 野地细节：雪原上的"可读性锚点"
# =====================================================================
## 一片 560m 见方的雪原，只有 40 块冰岩和 28 棵树，走起来就是无限白纸。
## 这一层专门往野地里撒小东西：不是为了好看，是为了给眼睛一个尺度参照——
## 有了 0.3m 的草茎，人才知道远处的楼有多大、雪有多深。
## 全部无碰撞、不投影，纯视觉。
func _gen_field_detail() -> void:
	var rng := RandomNumberGenerator.new()
	var g_fd: Node = _g()
	rng.seed = (int(g_fd.get("world_seed")) if g_fd else 20261015) + 9001

	# ---- 1. 从雪里戳出来的枯草（最廉价也最有效的尺度参照）----
	var grass_mesh := _grass_mesh()
	var grass_mat := _mat_wood(Color(0.300, 0.255, 0.195), 0.95)
	# 用多实例批量画：几百丛草如果各自一个 MeshInstance3D，draw call 会很难看。
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = grass_mesh
	var tufts: Array[Transform3D] = []
	var tries := 0
	while tufts.size() < 620 and tries < 9000:
		tries += 1
		var gx := rng.randf_range(-SIZE * 0.47, SIZE * 0.47)
		var gz := rng.randf_range(-SIZE * 0.47, SIZE * 0.47)
		# 街道与场坪上不长草
		if absf(gx) < ROAD_HALF + 2.5 or absf(gz) < ROAD_HALF * 0.8:
			continue
		if _near_building(gx, gz, 3.0):
			continue
		var gy := _ground_y(gx, gz)
		var s := rng.randf_range(0.55, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.25), s))
		tufts.append(Transform3D(basis, Vector3(gx, gy - 0.06, gz)))
	mm.instance_count = tufts.size()
	for i in range(tufts.size()):
		mm.set_instance_transform(i, tufts[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FieldGrass"
	mmi.multimesh = mm
	mmi.material_override = grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	# ---- 2. 半埋的碎石与建筑废墟碎块（打破雪面的连续性）----
	for i in range(180):
		var sx := rng.randf_range(-SIZE * 0.46, SIZE * 0.46)
		var sz := rng.randf_range(-SIZE * 0.46, SIZE * 0.46)
		if absf(sx) < ROAD_HALF + 1.5 or _near_building(sx, sz, 2.0):
			continue
		var sy := _ground_y(sx, sz)
		var sw := rng.randf_range(0.28, 1.5)
		var sh := rng.randf_range(0.14, 0.55)
		var sd := rng.randf_range(0.28, 1.3)
		# 一半露头、一半埋进雪里：完全躺在雪上的石块会读成"贴纸"
		var b := _box(Vector3(sx, sy + sh * 0.22, sz), Vector3(sw, sh, sd),
			_mat(Color(0.30, 0.31, 0.33), 0.94), false, rng.randf() * TAU)
		b.rotation.z = rng.randf_range(-0.30, 0.30)
		b.rotation.x = rng.randf_range(-0.22, 0.22)

	# ---- 3. 露出雪面的钢筋混凝土梁（灾难的痕迹，也是强尺度参照）----
	for i in range(16):
		var bx := rng.randf_range(-SIZE * 0.42, SIZE * 0.42)
		var bz := rng.randf_range(-SIZE * 0.42, SIZE * 0.42)
		if absf(bx) < ROAD_HALF + 4.0 or _near_building(bx, bz, 5.0):
			continue
		var by := _ground_y(bx, bz)
		var ln := rng.randf_range(2.4, 6.5)
		var beam := _box(Vector3(bx, by + 0.10, bz), Vector3(ln, 0.34, 0.42),
			_mat(Color(0.34, 0.345, 0.360), 0.9), false, rng.randf() * TAU)
		# 一头扎进雪里，一头翘起来——完全平的梁看起来像一块木板
		beam.rotation.z = rng.randf_range(0.10, 0.38) * (1.0 if rng.randf() < 0.5 else -1.0)
		beam.rotation.x = rng.randf_range(-0.12, 0.12)

	# ---- 4. 被风吹歪的路牌/标杆（直立物在雪原上特别醒目，能撑起纵深）----
	for i in range(9):
		var px := rng.randf_range(-SIZE * 0.40, SIZE * 0.40)
		var pz := rng.randf_range(-SIZE * 0.40, SIZE * 0.40)
		if absf(px) < ROAD_HALF + 6.0 or _near_building(px, pz, 6.0):
			continue
		var py := _ground_y(px, pz)
		var post := _cyl(Vector3(px, py + 1.15, pz), 0.055, 2.3,
			_mat(Color(0.30, 0.31, 0.32), 0.72, 0.42, 3.0))
		post.rotation.z = rng.randf_range(-0.22, 0.22)
		post.rotation.x = rng.randf_range(-0.18, 0.18)

	# ---- 5. 防雪栅栏（雪国的公路旁本来就会有这东西）----
	# 它是画面里最好用的"透视尺"：一排等距的板条从近处一直排到远处，
	# 眼睛立刻就能读出这段雪原有多远。用 MultiMesh 一次画完，几百根板条只花一个 draw call。
	_gen_snow_fences(rng)

	# ---- 6. 电线杆与下垂的电线（撑起天际线，也给远景一个高度参照）----
	_gen_power_line(rng)

# =====================================================================
# 街道家具：垃圾桶 / 消防栓 / 路牌 / 长椅 / 报箱 / 自行车架
# =====================================================================
## 主街两侧现在只有路灯、栅栏、电线杆和九辆车，人行道上空无一物。
## 这些 0.3~1.2m 的小东西是画面里唯一的“人的尺度”：
## 没有它们，路宽多少、楼有多高、门槛多厚，眼睛全都判断不出来。
## 全部无碰撞：人行道本来可以走，加上碰撞只会在窄处卡住玩家。
func _gen_street_furniture() -> void:
	var rng := RandomNumberGenerator.new()
	var g_sf: Node = _g()
	rng.seed = (int(g_sf.get("world_seed")) if g_sf else 20261015) + 4242
	var iron := _mat(Color(0.145, 0.152, 0.160), 0.74, 0.50, 3.0)
	var dark_metal := _mat(Color(0.105, 0.110, 0.118), 0.82, 0.40, 3.0)
	var wood := _mat_wood(Color(0.300, 0.245, 0.190), 0.94)
	var sign_cols := [
		Color(0.520, 0.180, 0.150),   # 禁停红
		Color(0.180, 0.290, 0.380),   # 蓝底指示牌
		Color(0.430, 0.400, 0.290),   # 泛黄旧漆
		Color(0.240, 0.330, 0.270),   # 墨绿
	]
	# 沿主街 z 轴布 22 处，左右交替；x 贴在路肩外 1.2~2.0m 的人行道上
	for i in range(22):
		var fz := -168.0 + float(i) * 15.6 + rng.randf_range(-3.5, 3.5)
		var side := 1.0 if i % 2 == 0 else -1.0
		var fx: float = side * (ROAD_HALF + rng.randf_range(1.2, 2.0))
		if absf(fz) < 15.0:
			continue
		var gy := _ground_y(fx, fz)
		var kind := rng.randi_range(0, 5)
		var yaw := rng.randf_range(-0.35, 0.35)
		match kind:
			0:
				# 垃圾桶：一个略歪的铁皮桶，桶口有雪
				var h := rng.randf_range(0.72, 0.95)
				var bin := _cyl(Vector3(fx, gy + h * 0.5, fz), 0.24, h, iron, false)
				bin.rotation.z = rng.randf_range(-0.10, 0.10)
				_cyl(Vector3(fx, gy + h + 0.02, fz), 0.26, 0.05,
					_mat(Color(0.815, 0.855, 0.925), 0.96), false)
			1:
				# 消防栓：矮、粗、有顶盖和两侧出水口，是街上最结实的红色符号
				var body_h := 0.62
				var hcol := _mat(Color(0.360, 0.115, 0.100), 0.80, 0.20, 3.0)
				_cyl(Vector3(fx, gy + 0.09, fz), 0.20, 0.18, iron, false)
				_cyl(Vector3(fx, gy + body_h * 0.5 + 0.16, fz), 0.132, body_h, hcol, false)
				_cyl(Vector3(fx, gy + body_h + 0.22, fz), 0.088, 0.16, hcol, false)
				for sx in [-1.0, 1.0]:
					_cyl(Vector3(fx + sx * 0.16, gy + 0.52, fz), 0.072, 0.20, iron, false)
			2:
				# 交通标志牌：杆 + 一块因为腐蚀而歪掉的牌面
				var sh := rng.randf_range(2.0, 2.6)
				var scol: Color = sign_cols[rng.randi_range(0, 3)]
				_box(Vector3(fx, gy + sh * 0.5, fz), Vector3(0.10, sh, 0.10), iron, false, yaw)
				var plate := _box(Vector3(fx, gy + sh - 0.28, fz), Vector3(0.62, 0.62, 0.045),
					_mat(scol, 0.72, 0.15), false, yaw)
				plate.rotation.z = rng.randf_range(-0.24, 0.20)
			3:
				# 长椅：两块板 + 四条腿，座面上压着一层雪
				var bl := rng.randf_range(1.5, 1.9)
				for k in range(2):
					_box(Vector3(fx, gy + 0.44, fz) + Vector3(0.0, 0.0, (float(k) - 0.5) * 0.20),
						Vector3(bl, 0.06, 0.18), wood, false, yaw)
				_box(Vector3(fx, gy + 0.70, fz + 0.24), Vector3(bl, 0.30, 0.06), wood, false, yaw)
				for lx2 in [-1.0, 1.0]:
					for lz2 in [-1.0, 1.0]:
						var lp: Vector3 = Vector3(fx, gy + 0.22, fz) + Vector3(lx2 * (bl * 0.5 - 0.12), 0.0, lz2 * 0.16)
						_box(lp, Vector3(0.07, 0.44, 0.07), iron, false)
				_drift(Vector3(fx, gy + 0.44, fz + 0.02), bl * 0.45, 0.09, 0.12, yaw)
			4:
				# 报箱 / 邮筒：方形铁箱，前面一条投递缝
				var bh := rng.randf_range(0.58, 0.74)
				_box(Vector3(fx, gy + bh * 0.5 + 0.10, fz), Vector3(0.42, bh, 0.34), dark_metal, false, yaw)
				_box(Vector3(fx, gy + bh + 0.14, fz), Vector3(0.46, 0.07, 0.38),
					_mat(Color(0.815, 0.855, 0.925), 0.96), false, yaw)
				_box(Vector3(fx, gy + bh * 0.68 + 0.10, fz) + Vector3(0.0, 0.0, 0.18),
					Vector3(0.26, 0.05, 0.03), _mat(Color(0.06, 0.06, 0.07), 0.9), false, yaw)
			5:
				# 倒地的自行车架 + 一辆只剩车架的车：铁锈色，细细的管子
				var rust := _mat(Color(0.290, 0.215, 0.170), 0.70, 0.55, 3.0)
				for k in range(3):
					_box(Vector3(fx, gy + 0.30, fz + (float(k) - 1.0) * 0.55),
						Vector3(0.06, 0.60, 0.06), iron, false, yaw)
				_box(Vector3(fx, gy + 0.58, fz), Vector3(1.72, 0.05, 0.05), iron, false, yaw)
				# 车架：一段倒在地上、已被雪埋住一半的三角架
				var bike := _box(Vector3(fx + 0.42, gy + 0.16, fz + 0.30),
					Vector3(1.02, 0.05, 0.05), rust, false, yaw + 0.6)
				bike.rotation.z = 1.18
				for wxx in [-0.52, 0.52]:
					var wr: Vector3 = Vector3(fx + 0.42, gy + 0.16, fz + 0.30) + Vector3(wxx, 0.0, 0.0).rotated(Vector3.UP, yaw + 0.6)
					var wh := _cyl(wr, 0.33, 0.05, rust, false)
					wh.rotation = Vector3(PI / 2.0 + 0.30, yaw + 0.6, 0.0)

## 防雪栅栏：贴着路肩竖起来的木板条挡风墙，几段已经塌了
func _gen_snow_fences(rng: RandomNumberGenerator) -> void:
	var slat_mesh := BoxMesh.new()
	slat_mesh.size = Vector3(0.055, 1.45, 0.16)
	var slat_mat := _mat_wood(Color(0.335, 0.275, 0.215), 0.94)
	var post_mat := _mat_wood(Color(0.290, 0.235, 0.185), 0.95)
	# 分段布点：贴着主街两侧的路肩。
	# 关键约束是「必须挨着路」——早先版本把它扔在离路 20m 的野地里，
	# 相机根本框不到，等于白做。这里 x 卡在 ROAD_HALF+2.6 左右，
	# 就在雪堤外侧一步的位置，从街上任何角度都能看见它一路排过去。
	var spans: Array = []
	var z_cursor := 52.0
	for si in range(5):
		var side := 1.0 if si % 2 == 0 else -1.0
		var seg_len := rng.randf_range(16.0, 26.0)
		spans.append({
			"z0": z_cursor - seg_len * 0.5,
			"x": side * (ROAD_HALF + rng.randf_range(2.4, 3.4)),
			"len": seg_len,
			"si": si,
			"side": side,
		})
		z_cursor -= seg_len + rng.randf_range(9.0, 20.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = slat_mesh
	var mats: Array[Transform3D] = []
	for sp in spans:
		var zc: float = sp["z0"]
		var xc: float = sp["x"]
		var seg_len: float = sp["len"]
		var yaw := deg_to_rad(rng.randf_range(-5.0, 5.0))
		var tilt := rng.randf_range(-0.08, 0.13)
		# 每段栅栏只有一部分还立着，剩下的被雪埋掉或压垮
		var dip := rng.randf_range(0.20, 0.62)
		var n := int(seg_len / 0.175)
		for k in range(n):
			var t := float(k) / float(maxi(n - 1, 1))
			var lz := -seg_len * 0.5 + t * seg_len
			var wob := sin(t * 6.1 + float(sp["si"])) * 0.05
			var gy := _ground_y(xc + wob, zc + lz)
			# 高度沿段起伏：像被风一段段压下去过
			var h := 1.45 * (1.0 - dip * (0.30 + 0.70 * absf(sin(t * 4.3 + float(sp["si"])))))
			if h < 0.16:
				continue
			var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt) \
				* Basis.from_scale(Vector3(1.0, h / 1.45, 1.0))
			mats.append(Transform3D(basis, Vector3(xc + wob, gy + h * 0.5 - 0.14, zc + lz)))
		# 立柱：比板条粗，是栅栏的骨架
		for k in range(int(seg_len / 2.25) + 1):
			var lz := -seg_len * 0.5 + float(k) * 2.25
			if lz > seg_len * 0.5:
				break
			var gy := _ground_y(xc, zc + lz)
			_box(Vector3(xc, gy + 0.40, zc + lz), Vector3(0.13, 1.45, 0.13), post_mat, false, yaw)
	mm.instance_count = mats.size()
	for i in range(mats.size()):
		mm.set_instance_transform(i, mats[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SnowFence"
	mmi.multimesh = mm
	mmi.material_override = slat_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)

## 沿街的电线杆：从出生点一路排到北边，电线按悬链线垂下去
func _gen_power_line(rng: RandomNumberGenerator) -> void:
	var pole_mat := _mat_wood(Color(0.255, 0.215, 0.175), 0.95)
	var wire_mat := _mat(Color(0.145, 0.150, 0.160), 0.72, 0.30, 3.0)
	var insul_mat := _mat(Color(0.62, 0.60, 0.55), 0.42, 0.10)
	# 放在横街的另一侧（x 为负），免得和右边的路灯、栅栏挤在一起
	var px := -(ROAD_HALF + 4.2)
	# 间距 34m，从玩家出生点前方一直排到远处。
	# 之前是 44m 且总数只有 8 根、整段都压在 z<-100，
	# 结果相机前 200m 内一根都看不见——有节奏的东西必须铺在镜头上。
	var tops: Array = []
	for k in range(11):
		var pz := 96.0 - float(k) * 34.0 + rng.randf_range(-2.5, 2.5)
		var gy := _ground_y(px, pz)
		var ph := rng.randf_range(6.4, 7.6)
		var lean := rng.randf_range(-0.030, 0.030)
		var pole := _cyl(Vector3(px, gy + ph * 0.5, pz), 0.115, ph, pole_mat)
		pole.rotation.z = lean
		pole.rotation.x = rng.randf_range(-0.02, 0.02)
		var top := Vector3(px + lean * ph * 0.5, gy + ph - 0.55, pz)
		# 两根横担 + 四个白瓷绝缘子：远看是「十」字，近看有细节
		for ci in range(2):
			var ch := 1.55 - float(ci) * 0.45
			_box(Vector3(top.x, top.y - float(ci) * 0.62, top.z), Vector3(ch, 0.08, 0.09),
				pole_mat, false, 0.0)
			for cs in [-1.0, 1.0]:
				_cyl(Vector3(top.x + cs * ch * 0.44, top.y - float(ci) * 0.62 + 0.12, top.z),
					0.055, 0.18, insul_mat)
		tops.append(top)

	# 电线：相邻两根杆之间按悬链线分成 6 段
	for k in range(tops.size() - 1):
		var a: Vector3 = tops[k]
		var b: Vector3 = tops[k + 1]
		if rng.randf() < 0.14:
			continue  # 有几档断了，雪原上本来就该有断掉的电线
		for cs in [-1.0, 1.0]:
			var off := Vector3(cs * 0.68, 0.0, 0.0)
			var prev: Vector3 = a + off
			for s in range(1, 7):
				var t := float(s) / 6.0
				var sag := sin(t * PI) * 0.85
				var cur: Vector3 = (a + off).lerp(b + off, t) - Vector3(0.0, sag, 0.0)
				_wire_seg(prev, cur, 0.018, wire_mat)
				prev = cur

## 一小段悬空的电线（细圆柱，沿两点连线摆放）
func _wire_seg(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 0.02:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = ln
	cm.radial_segments = 5
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	# 电线不投阴影：太细了，采样出来的影子只是一片噪点
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y := d / ln
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	add_child(mi)

## 一丛枯草：几片交错的窄三角面，从雪里戳出来
func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for b in range(7):
		var a := rng.randf() * TAU
		var lean := rng.randf_range(0.12, 0.42)
		var h := rng.randf_range(0.28, 0.62)
		var w := rng.randf_range(0.010, 0.022)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-sin(a), 0.0, cos(a))
		var base := dir * rng.randf_range(0.0, 0.06)
		var tip := dir * lean * h + Vector3(0.0, h, 0.0)
		var mid := base + (tip - base) * 0.55 + side * rng.randf_range(-0.012, 0.012)
		for tri in [[base - side * w, base + side * w, mid],
				[mid - side * w * 0.6, mid + side * w * 0.6, tip]]:
			for v in tri:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()

## 粗筛：这个位置附近有没有建筑（避免细节长进墙里）
func _near_building(x: float, z: float, pad: float) -> bool:
	for n in get_tree().get_nodes_in_group("structures"):
		var p: Vector3 = (n as Node3D).global_position
		if absf(p.x - x) < 14.0 + pad and absf(p.z - z) < 14.0 + pad:
			return true
	return false

# =====================================================================
# 线索：脚印 + 遗物（幸存者以物的形式先登场）
# =====================================================================

func _add_node(pos: Vector3, _name: String, uses: int, loot: Array) -> ResourceNode:
	var node := ResourceNode.new()
	node.setup({"id": "generic", "name": _name, "uses": uses, "loot": loot})
	node.position = pos + Vector3(0, 0.4, 0)
	add_child(node)
	return node

func _add_foundation(pos: Vector3, _name: String, desc: String) -> void:
	var f := FoundationMarker.new()
	f.setup(_name, desc)
	f.position = pos + Vector3(0, 0.1, 0)
	add_child(f)

func _add_footprints(from: Vector3, to: Vector3) -> void:
	var steps := 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.4, 0.5, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(steps):
		var t := float(i) / float(steps - 1)
		var px := lerpf(from.x, to.x, t) + sin(t * 9.0) * 1.2
		var pz := lerpf(from.z, to.z, t)
		var py := _ground_y(px, pz)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.16, 0.26)
		mi.mesh = pm
		mi.material_override = mat
		mi.position = Vector3(px, py + 0.06, pz)
		mi.rotation.x = -PI / 2.0
		add_child(mi)

func _gen_clue_trails() -> void:
	# 每条线索：一个遗物点 + 一串脚印通向冰封的人
	var relic_items := ["old_photo", "radio_part", "medical_kit", "scrap", "toy_bear", "clue_06"]
	var i := 0
	for sid in Survivors.ids():
		var def: Dictionary = Survivors.def(sid)
		var sp: Vector3 = def.get("spawn", Vector3.ZERO)
		var relic_pos := sp + Vector3(randf_range(-7, 7), 0, randf_range(-7, 7))
		var relic_loot: Array = [{"id": relic_items[i], "min": 1, "max": 1, "chance": 0.8}]
		if randf() < 0.5:
			relic_loot.append({"id": "wood", "min": 1, "max": 2, "chance": 0.5})
		_add_node(relic_pos, "被翻动过的痕迹", 2, relic_loot)
		_add_footprints(relic_pos, sp)
		i += 1
	# 散落的旧世界记录
	var placements := {
		"clue_01": Vector3(8, 0, 40), "clue_02": Vector3(-30, 0, -20),
		"clue_03": Vector3(-120, 0, 120), "clue_04": Vector3(90, 0, 150),
		"clue_05": Vector3(150, 0, 200), "clue_07": Vector3(-60, 0, 430),
		"clue_08": Vector3(30, 0, 460), "clue_09": Vector3(-100, 0, 480),
		"clue_10": Vector3(70, 0, 500), "clue_11": Vector3(-20, 0, 540),
		"clue_12": Vector3(80, 0, 560),
	}
	for cid in placements:
		var p: Vector3 = placements[cid]
		_add_node(p, "冻住的纸页", 1, [{"id": cid, "min": 1, "max": 1, "chance": 1.0}])

# =====================================================================
# 生物
# =====================================================================

func _gen_creatures() -> void:
	for i in range(6):
		var ang := randf() * TAU
		var dist := randf_range(45.0, 230.0)
		_spawn_creature("wolf", cos(ang) * dist, sin(ang) * dist)
	for i in range(5):
		var ang := randf() * TAU
		var dist := randf_range(50.0, 240.0)
		_spawn_creature("deer", cos(ang) * dist, sin(ang) * dist)
	for i in range(8):
		var ang := randf() * TAU
		var dist := randf_range(30.0, 200.0)
		_spawn_creature("rabbit", cos(ang) * dist, sin(ang) * dist)

func _spawn_creature(species: String, x: float, z: float) -> void:
	var c := Creature.new()
	c.setup(species, Vector3(x, _ground_y(x, z), z))
	add_child(c)

# =====================================================================
# 幸存者（冰封中）
# =====================================================================

func _gen_npcs() -> void:
	for sid in Survivors.ids():
		var def: Dictionary = Survivors.def(sid)
		var sp: Vector3 = def.get("spawn", Vector3.ZERO)
		var npc := SurvivorNPC.new()
		npc.setup(sid, Vector3(sp.x, _ground_y(sp.x, sp.z), sp.z))
		add_child(npc)

# =====================================================================
# 融点终端（第三区）
# =====================================================================

func _gen_terminal() -> void:
	var tx := -12.0
	var tz := 560.0
	var ty := _ground_y(tx, tz)
	_box(Vector3(tx, ty + 0.5, tz), Vector3(6.0, 1.0, 4.0), _mat(Color(0.4, 0.43, 0.47)))
	_box(Vector3(tx, ty + 2.2, tz - 1.2), Vector3(1.2, 3.4, 1.0), _mat(Color(0.45, 0.47, 0.5)))
	_box(Vector3(tx, ty + 2.2, tz - 1.2), Vector3(1.3, 0.5, 1.1), _emissive(Color(0.3, 0.9, 1.0), 0.4))
	for k in range(4):
		var a := float(k) / 4.0 * TAU
		_box(Vector3(tx + cos(a) * 3.4, ty + 0.6, tz + sin(a) * 3.0), Vector3(0.5, 1.2, 0.5), _mat(Color(0.42, 0.44, 0.47)))
	var term := TerminalInteract.new()
	term.position = Vector3(tx, ty + 1.1, tz - 1.2)
	add_child(term)

# =====================================================================
# 天灾的世界侧效果
# =====================================================================

func trigger_disaster(kind: String) -> void:
	var g_td: Node = _g()
	var player_td: Node = g_td.get("player") if g_td else null
	var p: Vector3 = player_td.global_position if is_instance_valid(player_td) else Vector3.ZERO
	match kind:
		"cold_wave":
			g_td.set("disaster_cold", 14.0)
			g_td.call("notify", "寒潮扑了下来。气温陡然一沉。", "bad")
		"blizzard":
			g_td.set("weather", "blizzard")
			g_td.set("weather_left", 2400.0)
			g_td.call("notify", "暴风雪砸了下来，几步之外只剩白。", "bad")
		"ice_collapse":
			_ice_collapse(p)
		"ruin_collapse":
			_ruin_collapse(p)
		"meteor":
			_meteor_shower(p)
		# ---- 灾难泊松模型六类型（CAT-01~06）----
		"quake":
			# 冰震：冰架应力累积→裂隙带，比冰面塌陷更猛
			g_td.call("notify", "大地深处一声闷响——冰震！裂隙像蜘蛛网一样铺开。", "bad")
			_ice_collapse(p)
			_ice_collapse(p + Vector3(8, 0, 6))
			if is_instance_valid(player_td):
				player_td.add_shake(1.0)
		"thaw":
			# 暖春异常：相变潜热雪崩，局部升温+湿度暴涨
			_thaw_event(p)
		"dust":
			# 尘云蔽日：光照切断，辐射热通量 -70%
			_dust_event()
		"microbe":
			# 远古微生物释放：污染区+代谢产热
			_microbe_event(p)

## 暖春异常：冰面渗水→异响→局部塌陷；局部温度+5℃，湿度+60%
func _thaw_event(center: Vector3) -> void:
	var g_th: Node = _g()
	g_th.set("weather", "snow")
	g_th.set("weather_left", 1800.0)
	g_th.set("camp_temp", float(g_th.get("camp_temp")) + 5.0)
	g_th.set("wet", minf(100.0, float(g_th.get("wet")) + 60.0))
	g_th.call("notify", "冰面渗出水来，滴答声越来越密——暖春来了，冰在哭。", "bad")
	# 融水洼（视觉）
	for i in range(5):
		var a := randf() * TAU
		var d := randf_range(3.0, 14.0)
		var pos := center + Vector3(cos(a) * d, 0, sin(a) * d)
		var y := height_at(pos.x, pos.z)
		var puddle := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = randf_range(1.0, 2.2)
		cm.bottom_radius = cm.top_radius
		cm.height = 0.06
		puddle.mesh = cm
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.25, 0.4, 0.5, 0.8)
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.roughness = 0.1
		puddle.material_override = wm
		puddle.position = Vector3(pos.x, y + 0.05, pos.z)
		add_child(puddle)

## 尘云蔽日：天色泛黄→风速骤降→能见度骤降；全局温度-15℃，燃料消耗+30%
func _dust_event() -> void:
	var g_du: Node = _g()
	g_du.set("weather", "clear")       # 无雪，但灰暗
	g_du.set("weather_left", 4320.0)   # 48-96h
	g_du.set("wind", 0.05)             # 风速骤降
	g_du.set("camp_temp", float(g_du.get("camp_temp")) - 15.0)
	g_du.call("notify", "天泛黄了，风忽然不动——尘云蔽日，连呼吸都嫌脏。", "bad")

## 远古微生物释放：污染区+代谢产热（+500kJ/h → 局部+3℃）
func _microbe_event(center: Vector3) -> void:
	var g_mi: Node = _g()
	g_mi.set("camp_temp", float(g_mi.get("camp_temp")) + 3.0)
	g_mi.call("notify", "冰层底下冒泡，一股腥甜味——有什么醒了。水源不能再碰。", "bad")
	# 污染斑块（视觉+标记）
	for i in range(4):
		var a := randf() * TAU
		var d := randf_range(2.0, 10.0)
		var pos := center + Vector3(cos(a) * d, 0, sin(a) * d)
		var y := height_at(pos.x, pos.z)
		var blot := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(2.0, 4.5), 0.08, randf_range(2.0, 4.5))
		blot.mesh = bm
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.35, 0.3, 0.2)
		mm.roughness = 1.0
		blot.material_override = mm
		blot.position = Vector3(pos.x, y + 0.04, pos.z)
		add_child(blot)

func _ice_collapse(center: Vector3) -> void:
	var g_ic: Node = _g()
	var player_ic: Node = g_ic.get("player") if g_ic else null
	g_ic.call("notify", "脚下传来空的回响——冰层在塌！", "bad")
	for i in range(3):
		var ang := randf() * TAU
		var d := randf_range(4.0, 12.0)
		apply_crater(center + Vector3(cos(ang) * d, 0, sin(ang) * d), randf_range(3.5, 6.0), randf_range(2.5, 4.0))
	if is_instance_valid(player_ic):
		var p: Vector3 = player_ic.global_position
		for idx in range(maxi(0, craters.size() - 3), craters.size()):
			var c: Dictionary = craters[idx]
			if Vector2(p.x, p.z).distance_to(c.pos) < float(c.r) + 1.5:
				player_ic.hurt(18.0, "冰面塌下去一角，你重重摔在冰碴上。")
				break
		player_ic.add_shake(0.8)

func _ruin_collapse(center: Vector3) -> void:
	var candidates: Array = []
	for b in ruin_bodies:
		if not is_instance_valid(b) or b == self:
			continue
		if b.global_position.distance_to(center) < 60.0:
			candidates.append(b)
	var target: Node3D = null
	if not candidates.is_empty():
		target = candidates[randi() % candidates.size()]
	if target == null:
		# 没有邻近废墟：塌一处Placeholder——用瓦砾代替
		var g_rc0: Node = _g()
		g_rc0.call("notify", "远处有楼塌了，声浪隔着雪传来。", "info")
		return
	var pos := target.global_position
	var g_rc1: Node = _g()
	g_rc1.call("notify", "一栋残楼没撑住，轰然垮塌！", "bad")
	# 尘雾
	for i in range(10):
		var ang := randf() * TAU
		var dust := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(1.0, 2.5), randf_range(1.0, 2.0), randf_range(1.0, 2.5))
		dust.mesh = bm
		dust.material_override = _mat(Color(0.6, 0.62, 0.65), 1.0)
		dust.position = pos + Vector3(cos(ang) * 2.0, randf_range(0.5, 3.0), sin(ang) * 2.0)
		add_child(dust)
		var tw := create_tween()
		tw.tween_property(dust, "position:y", dust.position.y + randf_range(2.0, 5.0), 2.5)
		tw.parallel().tween_property(dust, "scale", Vector3.ZERO, 2.5)
		tw.tween_callback(dust.queue_free)
	target.queue_free()
	ruin_bodies.erase(target)
	var g_rc2: Node = _g()
	var player_rc: Node = g_rc2.get("player") if g_rc2 else null
	if is_instance_valid(player_rc) and player_rc.global_position.distance_to(pos) < 12.0:
		player_rc.hurt(28.0, "垮塌的楼体砸中了避之不及的你。")
	# 家当受损：庇护所等级低时丢一两处搭建
	if bool(g_rc2.get("has_home")) and int(g_rc2.get("shelter_level")) < 3 and g_rc2.get("buildings").size() > 0:
		var lost: Dictionary = g_rc2.get("buildings").pop_back()
		g_rc2.call("notify", "家里的%s 被震塌了。" % BuildingDefs.name_of(lost.get("type", "")), "bad")
		if is_instance_valid(g_rc2.get("world")) and g_rc2.get("world").has_method("rebuild_shelter_level"):
			g_rc2.get("world").rebuild_shelter_level()

func _meteor_shower(center: Vector3) -> void:
	var g_ms: Node = _g()
	g_ms.call("notify", "天幕裂开细亮的痕——陨石雨落下来了！", "bad")
	for i in range(7):
		var ang := randf() * TAU
		var d := randf_range(10.0, 45.0)
		var impact := center + Vector3(cos(ang) * d, 0, sin(ang) * d)
		_spawn_meteor(impact, randf_range(0.4, 1.6) + float(i) * 0.35)

func _spawn_meteor(impact: Vector3, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	# 等待期间场景可能已重载：本节点（世界）随之释放，不能继续 add_child
	var g_sm: Node = _g()
	if not is_inside_tree() or (g_sm and bool(g_sm.get("game_over"))):
		return
	var start := impact + Vector3(randf_range(-30, 30), 160.0, randf_range(-30, 30))
	var meteor := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = randf_range(0.5, 1.4)
	sm.height = sm.radius * 2.0
	meteor.mesh = sm
	meteor.material_override = _emissive(Color(1.0, 0.55, 0.2), 3.0)
	meteor.position = start
	add_child(meteor)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 6.0
	light.omni_range = 30.0
	meteor.add_child(light)
	var tw := create_tween()
	tw.tween_property(meteor, "position", impact + Vector3(0, 1.0, 0), 1.6)
	await tw.finished
	if not is_instance_valid(meteor):
		return
	meteor.queue_free()
	# 爆炸
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.35)
	flash.light_energy = 12.0
	flash.omni_range = 40.0
	flash.position = impact + Vector3(0, 3.0, 0)
	add_child(flash)
	var fw := create_tween()
	fw.tween_property(flash, "light_energy", 0.0, 0.8)
	fw.tween_callback(flash.queue_free)
	apply_crater(impact, randf_range(3.0, 5.5), randf_range(2.0, 3.5))
	var player_mt: Node = g_sm.get("player") if g_sm else null
	if is_instance_valid(player_mt) and player_mt.global_position.distance_to(impact) < 8.0:
		player_mt.hurt(30.0, "陨石砸在不远处，气浪把你掀翻在雪里。")
	# 陨石带来新的可搜刮之物
	_add_node(impact + Vector3(1.5, 0, 1.5), "陨石坑边", 3, [
		{"id": "scrap", "min": 1, "max": 3, "chance": 0.9},
		{"id": "stone", "min": 1, "max": 3, "chance": 0.7},
		{"id": "ice_block", "min": 1, "max": 2, "chance": 0.5},
	])

# =====================================================================
# 区域解锁提示
# =====================================================================

func _process(_delta: float) -> void:
	var g_pr: Node = _g()
	var player_pr: Node = g_pr.get("player") if g_pr else null
	if not _spawned or not is_instance_valid(player_pr) or not bool(g_pr.get("started")):
		return
	var p: Vector3 = player_pr.global_position
	var r := Vector2(p.x, p.z).length()
	if r > 150.0 and not district_flags.d2:
		district_flags.d2 = true
		g_pr.call("notify", "你走到了从未踏足的街区。更远，也更冷。", "clue")
	if r > 380.0 and not district_flags.d3:
		district_flags.d3 = true
		g_pr.call("notify", "这里的楼更高，冰更老。冰下仿佛有什么在呼吸。", "clue")

func rebuild_shelter_level() -> void:
	var g_rs: Node = _g()
	var lv := ShelterJudge.compute(g_rs.get("buildings"), g_rs.get("home_center"))
	g_rs.set("shelter_level", lv)

# =====================================================================
# 路面：裂沥青 + 积雪补丁 + 褪色车道线 + 路肩雪堤 + 碎块
# 全部纯视觉（无碰撞）：贴着地形起伏铺设，绝不产生台阶卡人
# =====================================================================

func _hash2(x: float, z: float) -> float:
	var v := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return absf(fmod(v, 1.0))

func _road_surface(along_axis: String, width: float, half_len: float, gap: float) -> void:
	## 路面由地形着色器直接铺在地面上（见 terrain_snow.gdshader 的 road_on 分支），
	## 这里只保留一个分组标记节点，维持 "roads" 契约，不产生任何几何，
	## 因此永远不会出现独立网格穿模 / z-fighting。
	var mi := Node3D.new()
	mi.name = "RoadSurface_" + along_axis
	mi.add_to_group("roads")
	add_child(mi)

func _road_markings(along_axis: String, width: float, half_len: float, gap: float) -> void:
	## 车道线同样由地形着色器绘制。
	var mi := Node3D.new()
	mi.name = "RoadMarkings_" + along_axis
	mi.add_to_group("roads")
	add_child(mi)

func _gen_roads() -> void:
	_road_surface("z", 8.4, 280.0, 11.0)
	_road_surface("x", 6.6, 280.0, 11.0)
	_road_markings("z", 8.4, 280.0, 11.0)
	_road_markings("x", 6.6, 280.0, 11.0)
	# 路肩雪堤 + 碎块
	for axis in ["z", "x"]:
		var half := 280.0
		var step := 22.0
		var n := int(half * 2.0 / step)
		for i in range(n):
			var along := -half + float(i) * step + randf_range(-4.0, 4.0)
			var side := 1.0 if randf() < 0.5 else -1.0
			var off := (8.4 if axis == "z" else 6.6) / 2.0 + randf_range(0.4, 1.2)
			var px := side * off if axis == "z" else along
			var pz := along if axis == "z" else side * off
			if absf(along) < 13.0:
				continue
			var gy := _ground_y(px, pz)
			if randf() < 0.55:
				# 路肩雪堤：三层雪丘叠出被风推挤的形状
				for k in range(2):
					var t := float(k)
					_drift(Vector3(px + randf_range(-0.2, 0.2), gy + 0.06 + t * 0.10, pz),
						randf_range(1.2, 2.4) * (1.0 - t * 0.3), 0.24 + t * 0.12,
						randf_range(1.8, 3.6) * (1.0 - t * 0.3), randf() * TAU)
			else:
				# 塌落的沥青块：半埋进雪里。整块浮在地面上会读成一张黑纸片，
				# 只有露出小半截、边缘被雪压住，才像被冻土拱出来的碎块。
				var bw := randf_range(0.34, 0.92)
				var bh := randf_range(0.14, 0.26)
				var bd := randf_range(0.34, 0.92)
				var slab := _box(Vector3(px, gy + bh * 0.34, pz), Vector3(bw, bh, bd),
					_mat(Color(0.175, 0.180, 0.195), 0.96), false, randf() * TAU)
				slab.rotation.x = randf_range(-0.16, 0.16)
				slab.rotation.z = randf_range(-0.16, 0.16)
				# 围住碎块的两团雪，把生硬的直角边吃掉
				for k in range(2):
					_drift(Vector3(px + randf_range(-0.5, 0.5), gy + 0.02, pz + randf_range(-0.5, 0.5)),
						randf_range(0.35, 0.7), randf_range(0.10, 0.18), randf_range(0.35, 0.7), randf() * TAU)

# =====================================================================
# 房屋多样化：冰封民居 / 平顶公寓一层 / 加油站 / 小餐馆 / 大仓库
# =====================================================================

func _marker(kind: String, pos: Vector3) -> void:
	var m := Node3D.new()
	m.name = "M_" + kind
	m.position = pos
	m.add_to_group("structures")
	m.set_meta("kind", kind)
	add_child(m)

func _icicles(x: float, z: float, y: float) -> void:
	for k in range(4):
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = randf_range(0.02, 0.045)
		cm.height = randf_range(0.2, 0.55)
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = _mat(Color(0.72, 0.85, 0.95), 0.15, 0.1)
		mi.position = Vector3(x + randf_range(-0.8, 0.8), y - cm.height / 2.0 - 0.05, z + randf_range(-0.5, 0.5))
		add_child(mi)

func _snow_bank(x: float, z: float, w: float, d: float) -> void:
	var y := _ground_y(x, z)
	# 三层雪丘叠出坡度，避免门口出现一块突兀的白砖
	for k in range(3):
		var t := float(k) / 2.0
		_drift(Vector3(x + randf_range(-0.3, 0.3), y + 0.10 + t * 0.14, z + randf_range(-0.2, 0.2)),
			w * (1.0 - t * 0.38), 0.20 + t * 0.10, d * (1.0 - t * 0.32), randf() * TAU)

func _make_gable_house(cx: float, cz: float, claimable: bool) -> void:
	## 双尖顶冰封民居：可进入，屋里有床，可占地基
	var w := randf_range(6.5, 8.5)
	var d := randf_range(5.5, 7.0)
	var wall_h := randf_range(2.7, 3.0)
	var room := _make_room(cx, cz, w, d, wall_h, "front")
	var c: Vector3 = room["center"]
	var y: float = room["y"]
	_marker("gable_house", Vector3(cx, y, cz))
	var hw := w / 2.0
	var hd := d / 2.0
	var slope := 0.85
	var gf2 := _facade_base(c.x, c.z, 1.7)
	# 双尖顶 + 屋顶积雪
	for s in [-1.0, 1.0]:
		var rb := _box(Vector3(c.x + s * hw * 0.5, y + wall_h + slope * hw * 0.42, c.z),
			Vector3(hw * 1.2, 0.16, d + 0.7), _mat(gf2 * 0.62, 0.86), true)
		rb.rotation.z = -s * atan(slope)
		var sn := _box(rb.position + Vector3(0, 0.13, 0), Vector3(hw * 1.2, 0.05, d + 0.7),
			_mat(Color(0.815, 0.855, 0.925)), false)
		sn.rotation.z = rb.rotation.z
	# 屋脊 + 烟囱
	_box(Vector3(c.x, y + wall_h + slope * hw + 0.06, c.z), Vector3(0.3, 0.22, d + 0.8), _mat(gf2 * 0.52))
	_box(Vector3(c.x + hw * 0.55, y + wall_h + slope * hw * 0.6 + 0.4, c.z - d * 0.25),
		Vector3(0.55, 1.3, 0.55), _mat_brick(gf2 * 0.86, 0.9))
	# 窗（带窗套、窗台积雪；有的被风压歪了）
	for s in [-1.0, 1.0]:
		var wx: float = c.x + s * hw * 0.55
		var wz: float = c.z + hd + 0.03
		_trim_window(Vector3(wx, y + 1.45, wz), Vector3(1.1, 1.0, 0.10), "z+", _win_glow(wx, wz))
		_trim_window(Vector3(wx, y + 1.45, c.z - hd - 0.03), Vector3(0.9, 0.9, 0.10), "z-",
			_win_glow(wx, c.z - hd))
	# 电视天线残杆
	_cyl(Vector3(c.x + hw + 0.25, y + 1.0, c.z + hd * 0.3), 0.02, 2.0, _mat(Color(0.2, 0.2, 0.22)))
	# 屋檐冰棱 + 门口雪堆
	_icicles(c.x - hw, c.z + hd, y + wall_h)
	_icicles(c.x + hw, c.z + hd, y + wall_h)
	_snow_bank(c.x, c.z + hd + 0.9, 2.6, 1.2)
	# 室内：床 + 碗柜
	var bed := BedInteract.new()
	bed.setup(Vector3(c.x - hw * 0.45, y, c.z - d * 0.1))
	add_child(bed)
	_add_node(c + Vector3(hw * 0.5, 0.0, d * 0.25), "碗柜抽屉", 1, [
		{"id": "canned", "min": 1, "max": 1, "chance": 0.5},
		{"id": "cloth", "min": 1, "max": 2, "chance": 0.6},
		{"id": "matches", "min": 1, "max": 2, "chance": 0.4},
	])
	if claimable:
		_add_foundation(Vector3(c.x, y, c.z + hd + 0.7), "冰封的民居", "四堵墙一个顶，炕是凉的，但到底是间屋子。")

func _make_flat_house(cx: float, cz: float, claimable: bool) -> void:
	## 平顶旧公寓一楼：可进入，带水塔和女墙
	var w := randf_range(7.0, 9.0)
	var d := randf_range(6.0, 7.5)
	var wall_h := 2.9
	var room := _make_room(cx, cz, w, d, wall_h, "left")
	var c: Vector3 = room["center"]
	var y: float = room["y"]
	_marker("flat_house", Vector3(cx, y, cz))
	var hw := w / 2.0
	var hd := d / 2.0
	var ff := _facade_base(c.x, c.z)
	# 平顶 + 积雪 + 女墙
	_box(Vector3(c.x, y + wall_h + 0.12, c.z), Vector3(w + 0.5, 0.24, d + 0.5), _mat(ff * 0.80))
	_box(Vector3(c.x, y + wall_h + 0.3, c.z), Vector3(w + 0.5, 0.12, d + 0.5), _mat(Color(0.815, 0.855, 0.925)), false)
	var par := _mat(ff * 0.88)
	_box(Vector3(c.x, y + wall_h + 0.45, c.z - hd - 0.15), Vector3(w + 0.5, 0.6, 0.18), par)
	_box(Vector3(c.x, y + wall_h + 0.45, c.z + hd + 0.15), Vector3(w + 0.5, 0.6, 0.18), par)
	_box(Vector3(c.x - hw - 0.15, y + wall_h + 0.45, c.z), Vector3(0.18, 0.6, d + 0.5), par)
	_box(Vector3(c.x + hw + 0.15, y + wall_h + 0.45, c.z), Vector3(0.18, 0.6, d + 0.5), par)
	# 屋顶水塔
	_cyl(Vector3(c.x + hw * 0.5, y + wall_h + 1.1, c.z - hd * 0.5), 0.7, 1.4, _mat(Color(0.5, 0.53, 0.57)), true)
	_cyl(Vector3(c.x + hw * 0.5, y + wall_h + 2.0, c.z - hd * 0.5), 0.75, 0.18, _mat(Color(0.26, 0.28, 0.31)))
	# 背墙窗列 + 空调外机
	for k in range(3):
		var wx: float = c.x - hw + (w / 3.0) * (float(k) + 0.5)
		_trim_window(Vector3(wx, y + 1.5, c.z - hd - 0.03), Vector3(0.95, 1.0, 0.10), "z-",
			_win_glow(wx, c.z - hd))
	# 空调外机：带支架、带锈、带一块被雪埋的顶
	_box(Vector3(c.x + hw - 0.6, y + 2.1, c.z - hd - 0.16), Vector3(0.72, 0.52, 0.34),
		_mat(Color(0.46, 0.48, 0.50), 0.66, 0.42, 3.0))
	_box(Vector3(c.x + hw - 0.6, y + 1.80, c.z - hd - 0.16), Vector3(0.62, 0.06, 0.28),
		_mat(Color(0.24, 0.25, 0.28), 0.9), false)
	_box(Vector3(c.x + hw - 0.6, y + 2.38, c.z - hd - 0.16), Vector3(0.70, 0.05, 0.32),
		_mat(Color(0.828, 0.868, 0.932), 0.95), false)
	_icicles(c.x, c.z - hd, y + wall_h)
	# 屋顶杂物：平屋顶的天际线不能是一条完美直线
	_roof_clutter(Vector3(c.x - w * 0.20, 0.0, c.z + d * 0.12), y + wall_h + 0.30, w * 0.46, d * 0.42)
	# 立管 + 外挂消防梯：把一面白墙切成有上下、有层次的立面
	_wall_pipes(c, "back", wall_h, w)
	# 平房也挂一段：从 1.5m 平台斜下的外挂楼梯，正是这种老楼的标配
	if wall_h > 2.85:
		_fire_escape(c, "right", wall_h, d)
	# 室内：床 + 冰箱底
	var bed := BedInteract.new()
	bed.setup(Vector3(c.x + hw * 0.4, y, c.z + hd * 0.3))
	add_child(bed)
	_add_node(c + Vector3(-hw * 0.5, 0.0, hd * 0.4), "冰箱底", 1, [
		{"id": "bottle_water", "min": 1, "max": 2, "chance": 0.7},
		{"id": "frozen_meat", "min": 1, "max": 1, "chance": 0.4},
	])
	if claimable:
		_add_foundation(Vector3(c.x - hw + 0.9, y, c.z), "旧公寓的一楼", "墙厚，窗小，关上门就听不见风。")

func _make_gas_station(cx: float, cz: float) -> void:
	var y := _ground_y(cx, cz)
	_marker("gas_station", Vector3(cx, y, cz))
	# 场坪（纯视觉）
	_box(Vector3(cx, y + 0.06, cz - 0.5), Vector3(16.0, 0.3, 14.0), _mat(Color(0.3, 0.32, 0.35)), false)
	# 罩棚四柱 + 棚顶 + 积雪
	var col := _mat(Color(0.54, 0.53, 0.52), 0.62, 0.38, 3.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(Vector3(cx + sx * 6.0, y + 2.1, cz + sz * 4.0), 0.16, 4.2, col)
	var canopy := _mat(Color(0.58, 0.55, 0.50), 0.82)
	_box(Vector3(cx, y + 4.35, cz), Vector3(14.5, 0.3, 9.5), canopy)
	_box(Vector3(cx, y + 4.55, cz), Vector3(14.5, 0.08, 9.5), _mat(Color(0.810, 0.850, 0.920)), false)
	# 一条褪成砖红的罩棚腰线——加油站唯一的彩色记忆
	var fascia := _mat(Color(0.46, 0.19, 0.16), 0.84)
	_box(Vector3(cx, y + 4.16, cz + 4.78), Vector3(14.5, 0.30, 0.12), fascia, false)
	_box(Vector3(cx, y + 4.16, cz - 4.78), Vector3(14.5, 0.30, 0.12), fascia, false)
	_box(Vector3(cx + 7.28, y + 4.16, cz), Vector3(0.12, 0.30, 9.5), fascia, false)
	_box(Vector3(cx - 7.28, y + 4.16, cz), Vector3(0.12, 0.30, 9.5), fascia, false)
	# 加油机 ×2（可搜刮）
	for k in range(2):
		var px := cx - 3.0 + float(k) * 3.0
		_box(Vector3(px, y + 0.85, cz + 1.5), Vector3(0.7, 1.7, 0.5), _mat(Color(0.56, 0.24, 0.20), 0.7, 0.25))
		_box(Vector3(px, y + 1.35, cz + 1.78), Vector3(0.5, 0.4, 0.06),
			_mat_lamp(1.5, float(k) * 3.1), false)
		_add_node(Vector3(px, y, cz + 1.5), "加油机", 1, [
			{"id": "scrap", "min": 1, "max": 2, "chance": 0.6},
			{"id": "cloth", "min": 1, "max": 1, "chance": 0.4},
		])
	# 小卖部（可进入）
	var shop := _make_room(cx, cz - 7.5, 6.0, 4.5, 2.8, "front")
	var sc: Vector3 = shop["center"]
	var sy: float = shop["y"]
	_box(Vector3(sc.x, sy + 3.0, sc.z), Vector3(6.6, 0.4, 5.1), _mat(_facade_base(sc.x, sc.z, 4.4) * 0.8))
	_box(Vector3(sc.x, sy + 1.4, sc.z + 2.3), Vector3(3.6, 1.2, 0.08), _mat_glass(Color(0.055, 0.070, 0.098), 0.85), false)
	_add_node(sc + Vector3(0, 0.0, 1.2), "店里角落", 2, [
		{"id": "canned", "min": 1, "max": 2, "chance": 0.6},
		{"id": "bandage", "min": 1, "max": 1, "chance": 0.3},
		{"id": "bottle_water", "min": 1, "max": 1, "chance": 0.4},
	])
	_snow_bank(cx + 6.5, cz + 3.0, 2.0, 3.0)

func _make_diner(cx: float, cz: float) -> void:
	var y := _ground_y(cx, cz)
	_marker("diner", Vector3(cx, y, cz))
	var w := 8.0
	var d := 6.0
	var wall_h := 3.0
	var hw := w / 2.0
	var hd := d / 2.0
	# 主体：五十年代那种奶油色搪瓷板 + 一圈墨绿腰线。
	# 整条街上只有这家店是"有颜色"的——它就是这条街的记忆锚点。
	var df := Color(0.560, 0.545, 0.500)
	_box(Vector3(cx, y + wall_h / 2.0, cz), Vector3(w, wall_h, d), _mat(df))
	_box(Vector3(cx, y + wall_h + 0.15, cz), Vector3(w + 0.4, 0.3, d + 0.4), _mat(Color(0.235, 0.300, 0.285)))
	_box(Vector3(cx, y + wall_h + 0.36, cz), Vector3(w + 0.4, 0.1, d + 0.4), _mat(Color(0.815, 0.855, 0.925)), false)
	# 墨绿腰线（一圈，高 0.34，外挑 0.04）
	var band := _mat(Color(0.205, 0.290, 0.275), 0.78)
	for s in [-1.0, 1.0]:
		_box(Vector3(cx, y + 0.86, cz + s * (hd + 0.03)), Vector3(w + 0.08, 0.34, 0.07), band, false)
		_box(Vector3(cx + s * (hw + 0.03), y + 0.86, cz), Vector3(0.07, 0.34, d + 0.08), band, false)
	# 临街大窗 + 门（带窗套。餐车式的橱窗是这栋房子的脸）
	_trim_window(Vector3(cx - 0.8, y + 1.35, cz + hd + 0.05), Vector3(4.6, 1.5, 0.10), "z+",
		_win_glow(cx - 0.8, cz + hd))
	# 门：门口一块踏脚石 + 门框
	_box(Vector3(cx + 2.9, y + 1.1, cz + hd + 0.05), Vector3(1.0, 2.2, 0.10),
		_mat(Color(0.075, 0.085, 0.080), 0.9), false)
	_box(Vector3(cx + 2.9, y + 1.1, cz + hd + 0.02), Vector3(1.05, 2.25, 0.06),
		_mat(Color(0.300, 0.245, 0.205), 0.85, 0.0, 2.0), false)
	_box(Vector3(cx + 2.9, y + 0.04, cz + hd + 0.55), Vector3(1.5, 0.09, 0.9),
		_mat(Color(0.36, 0.37, 0.38), 0.92, 0.0, 3.0), false)
	# 褪色红白条纹雨棚（红条已经洗成粉砖色，白条发黄）
	var stripes := [Color(0.480, 0.215, 0.190), Color(0.680, 0.640, 0.575)]
	for k in range(6):
		var sw := 0.85
		var sx := cx - 2.55 + float(k) * sw
		var aw := _box(Vector3(sx, y + 2.55, cz + hd + 0.7), Vector3(sw, 0.08, 1.3), _mat(stripes[k % 2]), false)
		aw.rotation.x = -0.32
	# 招牌：一根铁杆挑出去的老式霓虹箱体。
	# 白天是块蒙灰的塑料字牌，入夜才是这条街上唯一的暖光——
	# 远处看整条街，就靠这一点橙黄认出"那儿有家店"。
	_cyl(Vector3(cx - hw - 0.5, y + 1.6, cz + hd + 0.4), 0.06, 3.2, _mat(Color(0.25, 0.26, 0.28), 0.7, 0.4, 3.0))
	_box(Vector3(cx - hw - 0.5, y + 3.2, cz + hd + 0.4), Vector3(1.6, 0.5, 0.12),
		_mat(Color(0.075, 0.080, 0.085), 0.55, 0.30, 3.0), false)
	_box(Vector3(cx - hw - 0.5, y + 3.2, cz + hd + 0.42), Vector3(1.44, 0.36, 0.05),
		_mat_lamp(1.9, 5.3), false)
	# 烟囱 + 冰棱 + 门口雪堆
	_box(Vector3(cx + hw * 0.4, y + wall_h + 0.7, cz - hd * 0.4), Vector3(0.5, 1.1, 0.5), _mat_brick(Color(0.400, 0.330, 0.300), 0.9))
	# 屋顶上的通风机与天线：餐车的轮廓全靠这些小件撑住，否则就是一个长方形
	_roof_clutter(Vector3(cx - hw * 0.35, 0.0, cz - hd * 0.30), y + wall_h + 0.36, w * 0.42, d * 0.44)
	_wall_pipes(Vector3(cx, y, cz), "back", wall_h, w)
	# 门口的两只旧餐椅：一只立着、一只翻倒——街上唯一「人刚走开」的证据
	for k in range(2):
		var chx: float = cx + 2.05 + float(k) * 1.05
		var chz: float = cz + hd + 0.85
		var chm := _mat(Color(0.430, 0.190, 0.170), 0.82, 0.15, 3.0)
		_box(Vector3(chx, y + 0.42, chz), Vector3(0.44, 0.05, 0.44), chm, false)
		_box(Vector3(chx, y + 0.68, chz - 0.20), Vector3(0.44, 0.42, 0.05), chm, false)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_box(Vector3(chx + sx * 0.18, y + 0.21, chz + sz * 0.18),
					Vector3(0.04, 0.42, 0.04), _mat(Color(0.200, 0.205, 0.212), 0.80, 0.40, 3.0), false)
	var fallen := _box(Vector3(cx + 4.6, y + 0.26, cz + hd + 1.0), Vector3(0.44, 0.44, 0.05),
		_mat(Color(0.430, 0.190, 0.170), 0.82, 0.15, 3.0), false, 0.6)
	fallen.rotation.z = 1.35
	_icicles(cx, cz + hd, y + 2.6)
	_snow_bank(cx + 2.9, cz + hd + 1.0, 2.0, 1.0)
	# 打碎的橱窗（搜刮点）
	_add_node(Vector3(cx - 2.4, y, cz + hd + 0.8), "打碎的橱窗", 2, [
		{"id": "canned", "min": 1, "max": 1, "chance": 0.5},
		{"id": "bottle_water", "min": 1, "max": 1, "chance": 0.4},
		{"id": "cloth", "min": 1, "max": 1, "chance": 0.4},
	])

func _make_warehouse(cx: float, cz: float) -> void:
	var y := _ground_y(cx, cz)
	_marker("warehouse", Vector3(cx, y, cz))
	var w := 15.0
	var d := 10.0
	var wall_h := 4.6
	var hw := w / 2.0
	var hd := d / 2.0
	var sag := randf_range(-0.03, 0.03)
	# 可进入大间（侧门）
	var room := _make_room(cx, cz, w, d, wall_h, "left")
	var c: Vector3 = room["center"]
	var ry: float = room["y"]
	# 平顶（略下垂）+ 积雪
	var wf2 := _facade_base(c.x, c.z, 6.2)
	_box(Vector3(c.x, ry + wall_h + 0.15, c.z), Vector3(w + 0.6, 0.3, d + 0.6), _mat(wf2 * 0.72), true, sag)
	_box(Vector3(c.x, ry + wall_h + 0.34, c.z), Vector3(w + 0.6, 0.1, d + 0.6), _mat(Color(0.815, 0.855, 0.925)), false, sag)
	# 后墙卷帘门（锈死的装饰）
	for k in range(7):
		_box(Vector3(c.x - 1.8 + float(k) * 0.6, ry + 1.3, c.z - hd - 0.05), Vector3(0.55, 2.6, 0.1),
			_mat(Color(0.30, 0.31, 0.32), 0.62, 0.5, 3.0), false)
	# 高窗列（带窗套）
	for k in range(4):
		var wx: float = c.x - hw + 2.0 + float(k) * 3.2
		_trim_window(Vector3(wx, ry + 3.4, c.z + hd + 0.05), Vector3(1.2, 0.7, 0.10), "z+", 0.0)
	# 月台
	_box(Vector3(c.x, ry + 0.2, c.z + hd + 1.2), Vector3(6.0, 0.4, 2.4), _mat(Color(0.36, 0.38, 0.41)), false)
	# 月台上方的装卸雨棚：一根横梁 + 四根斜撑，把仓库正面切成有进退的两层。
	# 15m 长的白墙如果不打断，就只是一块竖着的板。
	var yard_iron := _mat(Color(0.235, 0.240, 0.250), 0.74, 0.48, 3.0)
	_box(Vector3(c.x, ry + 4.05, c.z + hd + 2.0), Vector3(7.6, 0.14, 2.6),
		_mat(Color(0.300, 0.305, 0.310), 0.86, 0.35, 3.0), false)
	_box(Vector3(c.x, ry + 4.14, c.z + hd + 2.0), Vector3(7.6, 0.05, 2.6),
		_mat(Color(0.815, 0.855, 0.925), 0.95), false)
	for s in [-1.0, 1.0]:
		var cxp: float = c.x + s * 3.6
		_cyl(Vector3(cxp, ry + 2.05, c.z + hd + 3.2), 0.07, 4.0, yard_iron, false)
		# 45° 斜撑：棚架凭什么立住，靠的就是这两根
		var br := _box(Vector3(cxp, ry + 3.35, c.z + hd + 3.05), Vector3(0.07, 1.35, 0.07), yard_iron, false)
		br.rotation.x = 0.55
	# 屋顶杂物与外墙立管：让大跨度平顶仓库也有「上面」和「侧面」
	_roof_clutter(Vector3(c.x, 0.0, c.z), ry + wall_h + 0.34, w * 0.70, d * 0.70)
	_wall_pipes(c, "front", wall_h, w)
	# 通风气楼：屋脊上一条连续的小凸起，是工业建筑最好认的轮廓
	_box(Vector3(c.x, ry + wall_h + 0.62, c.z), Vector3(w * 0.42, 0.44, 1.1),
		_mat(_facade_base(c.x, c.z, 6.2) * 0.86, 0.88, 0.20, 3.0), false)
	_box(Vector3(c.x, ry + wall_h + 0.87, c.z), Vector3(w * 0.42, 0.06, 1.1),
		_mat(Color(0.815, 0.855, 0.925), 0.95), false)
	# 室内板条箱
	var crate := _mat(Color(0.45, 0.36, 0.26))
	for k in range(5):
		var px := c.x + randf_range(-hw + 2.0, hw - 2.0)
		var pz := c.z + randf_range(-hd + 2.0, hd - 2.0)
		var s := randf_range(0.9, 1.4)
		_box(Vector3(px, ry + s / 2.0, pz), Vector3(s, s, s), crate, true, randf() * TAU)
	_add_node(c + Vector3(-hw + 1.5, 0.0, hd - 1.5), "板条箱堆", 2, [
		{"id": "wood", "min": 2, "max": 4, "chance": 0.8},
		{"id": "rope", "min": 1, "max": 2, "chance": 0.5},
		{"id": "scrap", "min": 1, "max": 2, "chance": 0.4},
	])
	_add_node(c + Vector3(hw - 1.5, 0.0, -hd + 1.5), "月台角落", 1, [
		{"id": "brick", "min": 1, "max": 2, "chance": 0.5},
		{"id": "multitool", "min": 1, "max": 1, "chance": 0.15},
	])

func _water_tower(x: float, z: float) -> void:
	var y := _ground_y(x, z)
	_marker("water_tower", Vector3(x, y, z))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(Vector3(x + sx * 1.2, y + 2.2, z + sz * 1.2), 0.09, 4.4, _mat(Color(0.33, 0.34, 0.36), 0.72, 0.42, 3.0))
	_cyl(Vector3(x, y + 5.0, z), 1.6, 2.2, _mat(Color(0.44, 0.45, 0.45), 0.8, 0.28, 3.0), true)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.75
	cone.height = 1.0
	var cm := MeshInstance3D.new()
	cm.mesh = cone
	cm.material_override = _mat(Color(0.29, 0.30, 0.31), 0.8, 0.35, 3.0)
	cm.position = Vector3(x, y + 6.6, z)
	add_child(cm)
	_box(Vector3(x, y + 6.15, z), Vector3(3.4, 0.1, 3.4), _mat(Color(0.810, 0.850, 0.920)), false)

func _gen_more_houses() -> void:
	_make_gable_house(30.0, 34.0, true)
	_make_flat_house(-34.0, 52.0, true)
	_make_gas_station(42.0, -34.0)
	_make_diner(-42.0, -12.0)
	_make_warehouse(-52.0, 20.0)
	for i in range(2):
		_water_tower(randf_range(-200.0, 200.0), randf_range(-180.0, 180.0))
