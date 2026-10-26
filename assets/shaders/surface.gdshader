shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// ============================================================================
//  通用建筑表面 —— 混凝土 / 砖 / 木 / 金属 + 风积雪 + 冻融流痕 + 冰晶
//  坐标全部取世界空间，靠法线主轴选平面，避免任何 UV 接缝
// ============================================================================

uniform vec3 base_color : source_color = vec3(0.44, 0.46, 0.49);
uniform vec3 snow_color : source_color = vec3(0.862, 0.878, 0.906);
uniform float surface_kind = 0.0;   // 0=混凝土 1=砖 2=木 3=金属 4=玻璃
uniform float snow_amount = 1.0;
uniform float roughness_v = 0.86;
uniform float metallic_v = 0.0;
uniform float grime = 1.0;
uniform float wetness = 0.0;
uniform float window_glow = 0.0;    // 玻璃：室内残余灯光的强度
uniform vec3 window_tint : source_color = vec3(1.0, 0.72, 0.42);
uniform float seed_v = 0.0;

// 全局量：由 day_night.gd 每帧写入，省掉给成千上万个材质逐个赋值的开销
global uniform float g_night;

varying vec3 w_nrm;
varying vec3 w_pos;

float h12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// 五次平滑而非三次：三次插值在格子对角线上会留下一道折痕，
	// 一大片平墙（仓库那种 20m 无特征的立面）上会连成一片"人字形"暗纹——
	// 那不是混凝土，那是噪声晶格的指纹。
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), u.x),
		mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	// 每层用不同的旋转：第一层也转，避免所有层共享同一个轴向，
	// 那会让晶格在叠加后相互对齐、越叠越明显。
	mat2 r0 = mat2(vec2(0.732, -0.681), vec2(0.681, 0.732));
	mat2 r = mat2(vec2(0.877, -0.479), vec2(0.479, 0.877));
	p = r0 * p + vec2(3.7, 1.9);
	for (int i = 0; i < 5; i++) {
		if (i >= oct) {
			break;
		}
		v += vn(p) * a;
		p = r * p * 2.07 + vec2(9.1, 5.3);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 屋顶/朝上积雪的高度场：沿风向被吹出的长脊。
// 反复用在三处（色调、法线、细节闸门），必须共用一个定义，
// 否则三处的脊线对不上，雪面会读成"底色和起伏各走各的"。
// 频率按米给：0.42/米 ≈ 2.4m 一道坎，1.45/米 ≈ 70cm 一道细纹——
// 真实积雪在屋顶上是"风把雪吹成一条条平行的小坎"，不是一片均匀颗粒。
float snow_field(vec2 p) {
	vec2 wd = normalize(vec2(0.86, -0.51));
	vec2 wc = vec2(-wd.y, wd.x);
	return fbm(vec2(dot(p, wd) * 0.42, dot(p, wc) * 1.45) + 7.0, 3);
}

void fragment() {
	vec3 wp = w_pos;
	vec3 n = normalize(w_nrm);
	float up = clamp(n.y, 0.0, 1.0);

	// ---- 按法线主轴挑平面坐标（免 UV、无接缝） ----
	// 同时给出该平面的世界切/副切向量，后面做凹凸（法线微扰）要用。
	vec2 plane;
	vec3 tg;
	vec3 bt;
	if (abs(n.y) > 0.72) {
		plane = wp.xz;
		tg = vec3(1.0, 0.0, 0.0);
		bt = vec3(0.0, 0.0, 1.0);
	} else if (abs(n.x) > abs(n.z)) {
		plane = vec2(wp.z, wp.y);
		tg = vec3(0.0, 0.0, 1.0);
		bt = vec3(0.0, 1.0, 0.0);
	} else {
		plane = vec2(wp.x, wp.y);
		tg = vec3(1.0, 0.0, 0.0);
		bt = vec3(0.0, 1.0, 0.0);
	}

	vec3 col = base_color;

	// ---- 距离分层：程序化细节必须随距离退场 ----
	// 这些噪声是逐像素算的，一旦投到远处几十个像素的面片上就会互相打架，
	// 整片建筑群会读成"电视雪花"。所以按"一个像素跨多少米"分两道门：
	// 粗门管接缝/斑驳/流痕（特征尺度 ~1m），细门管裂纹/颗粒/凹凸（~5cm）。
	// 阈值必须按特征尺度定：一个 1.15m 的模板缝投到墙上还有 30px，
	// 就不该被砍掉；而 5cm 的雪粒一旦小于 2px，就只能变成噪点。
	float fp = max(fwidth(plane.x), fwidth(plane.y));
	float near_f = 1.0 - smoothstep(0.055, 0.240, fp);   // 粗：~1m 级特征
	float micro_f = 1.0 - smoothstep(0.012, 0.055, fp);  // 细：~5cm 级特征

	// ---------------- 立面分格：模板缝 / 板缝 ----------------
	// 竖直墙面按 1.15m 一道横向缝，读起来像浇筑模板留下的接缝
	float joint = 0.0;
	if (abs(n.y) < 0.72) {
		float jy = wp.y * 0.87;
		float jd = abs(fract(jy) - 0.5);
		joint = smoothstep(0.478, 0.5, jd);
		// 竖向分缝（每 2.3m），与横向交错
		float jx = (abs(n.x) > abs(n.z) ? wp.z : wp.x) * 0.435;
		float jdx = abs(fract(jx + 0.25) - 0.5);
		joint = max(joint, smoothstep(0.482, 0.5, jdx) * 0.8);
		// 远处的缝密到小于一个像素，只会产生摩尔纹
		joint *= near_f;
	}

	// ---------------- 混凝土：模板板缝 + 对拉螺栓孔 + 砂粒 ----------------
	// 这里曾经用一层 4 阶 fbm 做"斑驳"，幅度 ±26%：那在近处就是一整片
	// 大尺度漩涡，墙面读成抛光大理石，跟混凝土没有任何关系。
	// 真实浇筑混凝土的表面几乎是一块平色，能认出它的只有三样东西：
	// ①横向模板板缝（一块模板 25cm 高，缝里有阴影）
	// ②对拉螺栓留下的一排圆孔（间距约 1.2m，孔心比板面深一档）
	// ③砂粒级的细颗粒。所以色差全部压到 ±8% 以内，结构交给前两样。
	float board = 0.0;
	float tie_hole = 0.0;
	float tie_ring = 0.0;
	if (abs(n.y) < 0.72) {
		float board_y = wp.y / 0.25;                 // 25cm 一块模板
		float bf = abs(fract(board_y) - 0.5);
		board = smoothstep(0.470, 0.500, bf);        // 板缝：一条细阴影
		// 每一块模板的木纹/含潮量都不同，整块板整体深一档
		float board_id = floor(board_y);
		float board_u = (abs(n.x) > abs(n.z) ? wp.z : wp.x) / 1.22;
		float board_tone = h12(vec2(floor(board_u) * 0.37 + board_id * 1.9, board_id * 2.7));
		col *= 0.955 + 0.075 * board_tone;
		// 对拉螺栓孔：横向 1.22m、纵向 0.5m（两块模板高）一格，错开半格
		vec2 tp = vec2(board_u, board_y * 0.5);
		tp.x += mod(floor(tp.y), 2.0) * 0.5;
		vec2 tf = fract(tp) - 0.5;
		float tr = length(tf * vec2(1.0, 0.55));
		tie_hole = 1.0 - smoothstep(0.030, 0.055, tr);   // 孔心
		tie_ring = smoothstep(0.030, 0.055, tr) * (1.0 - smoothstep(0.060, 0.095, tr));
		tie_hole *= near_f;
		tie_ring *= near_f;
	}
	// 斑驳：只保留 ±8% 的低频色差，绝不参与"漩涡"
	float mottle = fbm(plane * 0.55, 3);
	col *= 0.94 + 0.12 * mottle;
	// 砂粒：高频细颗粒，近处才有
	col *= 1.0 + (0.085 * vn(plane * 24.0) - 0.042) * micro_f;
	// 大尺度色差：整面墙有"这一块比那一块脏"的观感（低频，永远不会走样）。
	// 幅度必须收到 0.06 以内：仓库那种 20m 的大平墙上，0.22 的低频
	// 会连成一大片对角线暗块，读起来是"贴了一张脏纸"，不是混凝土。
	col *= 0.955 + 0.075 * fbm(plane * 0.19 + 21.0, 3);

	// ---- 浇筑分层：真实大体积混凝土是一次次立模浇上去的 ----
	// 每 1.5m 有一道横向的施工缝，缝上下模板的对位略有差、水化色也不同。
	// 这是唯一能让人"读出这面墙有多高"的尺度线索，没有它，
	// 一面 12m 高的仓库墙和一个 2m 的邮箱在质感上没有区别。
	if (abs(n.y) < 0.72) {
		float lift = wp.y / 1.5;
		float lf = abs(fract(lift) - 0.5);
		float lift_seam = smoothstep(0.480, 0.500, lf) * near_f;
		col *= 1.0 - lift_seam * 0.20;
		// 每一层浇筑的色差（同一批水泥但含水/养护不同）
		float lid = floor(lift);
		col *= 0.975 + 0.05 * h12(vec2(lid * 3.7, 11.3));
		// 缝下方一条浅浅的水渍（析出的白色泛碱）
		float below = smoothstep(0.065, 0.0, lf) * smoothstep(0.470, 0.500, lf);
		col = mix(col, col * 1.05, below * 0.55 * grime);
	}

	// ---- 剥落的水泥皮：露出深色骨料，边缘发白 ----
	// 这是"旧"最关键的一层：墙不再是一块完整的板，而是一块块掉的。
	// 但必须克制：面积一大、边缘一亮，混凝土板就变成麻点花岗岩，
	// 整栋楼读不出"人造建筑"。所以只留极少数几块，且落差很小。
	float spall_src = fbm(plane * 0.30 + 61.0, 3);
	float spall = smoothstep(0.820, 0.845, spall_src);              // 硬边：剥落边界清晰
	float spall_rim = smoothstep(0.808, 0.820, spall_src) * (1.0 - spall);  // 边缘一圈断口
	col = mix(col, col * 0.86 + vec3(0.004, 0.004, 0.005), spall * 0.50 * grime * micro_f);
	col = mix(col, col * 1.04, spall_rim * 0.24 * grime * micro_f);

	// 模板板缝与对拉螺栓孔压暗（这两样是混凝土可辨识的根本）
	col *= 1.0 - board * 0.26 * near_f;
	col *= 1.0 - tie_hole * 0.42;
	col = mix(col, col * 1.05, tie_ring * 0.30);

	// 细裂纹（更细更稀，避免整面像碎瓷）
	// fbm 的等值线天然会连成一张蛛网，整面墙铺满就成了"涂鸦"。
	// 用一层大尺度掩码把它压成零星几处，才像混凝土真的裂了那么几下。
	float crack_gate = smoothstep(0.62, 0.86, fbm(plane * 0.13 + 33.0, 3));
	float cline = abs(fbm(plane * 5.2 + 4.0, 3) - 0.5);
	col = mix(col, col * 0.70, smoothstep(0.022, 0.0, cline) * 0.45 * grime * crack_gate * micro_f);

	// ---------------- 砖 ----------------
	if (surface_kind > 0.5 && surface_kind < 1.5) {
		vec2 bp = plane * vec2(2.6, 1.3);
		float row = floor(bp.y);
		bp.x += mod(row, 2.0) * 0.5;
		vec2 f = fract(bp);
		float mortar = clamp(step(0.93, f.x) + step(0.87, f.y), 0.0, 1.0);
		col *= 0.80 + 0.36 * h12(floor(bp));
		col = mix(col, col * 0.55, mortar * 0.85);
	}

	// ---------------- 木 ----------------
	if (surface_kind > 1.5 && surface_kind < 2.5) {
		float grain = fbm(vec2(plane.x * 1.1, plane.y * 6.5), 4);
		col *= 0.76 + 0.40 * grain;
		col = mix(col, col * 0.66, smoothstep(0.70, 0.94, grain) * 0.55);
	}

	// ---------------- 金属 ----------------
	if (surface_kind > 2.5 && surface_kind < 3.5) {
		float rust = smoothstep(0.54, 0.84, fbm(plane * 2.2 + 11.0, 4));
		col = mix(col, vec3(0.32, 0.17, 0.10), rust * 0.70 * grime);
		col = mix(col, col * 1.32, smoothstep(0.90, 1.0, vn(vec2(plane.x * 26.0, plane.y * 3.5))) * 0.45);
	}

	// ---------------- 玻璃：霜花 + 室内残光 ----------------
	float glass_emit = 0.0;
	if (surface_kind > 3.5) {
		// 霜：从边缘往里长的针状冰晶
		vec2 gp = plane * 3.1;
		float frost_n = fbm(gp, 4);
		float needle = smoothstep(0.55, 0.95, abs(fbm(gp * 2.2 + 4.0, 3) - 0.5) * 6.0);
		float frost = smoothstep(0.30, 0.78, frost_n + needle * 0.30);
		col = mix(col, vec3(0.80, 0.86, 0.94), frost * 0.88);
		// 玻璃本身：暗镜面
		col *= 0.70 + 0.45 * fbm(gp * 0.7, 3);
		// 窗框阴影：矩形边框压暗，让"窗"读得出来
		col *= 0.92;
		// 室内灯：哪个窗亮、哪个窗灭，由 world_generator 的 _win_glow() 在世界侧
		// 逐窗决定并作为 uniform 传进来（window_glow > 0 即这扇窗亮着）。
		// 这里只负责「光是怎么从玻璃里透出来的」：窗中心透得最亮，
		// 靠窗框处被霜吃掉。之前在这里又按世界坐标 hash 二次筛选，
		// 结果一扇 1m 宽的窗横跨两三个格子、半扇亮半扇灭，
		// 读起来像玻璃上贴了一块亮纸——窗户必须整扇同状态。
		float center = 1.0 - smoothstep(0.0, 1.4, length(fract(gp * 0.5) - 0.5) * 2.0);
		// 霜厚的地方光更闷：不是所有窗一样亮
		float seal = 1.0 - frost * 0.72;
		glass_emit = window_glow * (0.34 + 0.86 * center) * seal;
	}

	// ---------------- 竖向流痕（冻融/雨水） ----------------
	// 频率不能太高：1.7/0.22 在整面墙上会拉出上百条等距细线，像帘子。
	// 收成"几股粗的脏水流"，只从檐口往下淌。
	float streak = fbm(vec2(plane.x * 0.55, plane.y * 0.16), 4);
	float streak_m = smoothstep(0.56, 0.84, streak) * (1.0 - up * 0.85);
	col *= 1.0 - streak_m * 0.26 * grime;

	// 贴近地面的脏污
	col *= 1.0 - smoothstep(1.8, 0.0, wp.y) * 0.12 * grime;

	// ---------------- 积雪 ----------------
	// 关键：垂直面几乎不挂雪，只有风檐、接缝、墙脚三处堆一点，
	// 否则整面墙会被雪糊成白板，混凝土的脏与灰全丢了。
	float sn = fbm(plane * 0.78, 4);
	float cover = up * 0.95 + sn * 0.40 - 0.32;          // 只对朝上的面生效
	// 侧面积雪：稀疏的雪带 + 接缝积雪 + 墙脚堆雪
	// 频率要高、幅度要低：低频大块的侧墙雪会读成"贴上去的白纸"，
	// 真实的立面雪是被风打成一条条细缝里的白，边角碎。
	float band = fbm(vec2(plane.x * 2.3, plane.y * 1.1), 3);
	float band2 = fbm(vec2(plane.x * 6.1 + 5.0, plane.y * 2.6), 2);
	float side_snow = smoothstep(0.84, 1.02, band * 0.72 + band2 * 0.38 * micro_f) * 0.30;
	side_snow = max(side_snow, joint * 0.32 * smoothstep(0.55, 0.85, sn));
	// 墙脚堆雪：高度必须被噪声打乱，否则整面墙下方会出现一条笔直的白漆带
	float foot = smoothstep(0.85, 0.0, wp.y + (band - 0.5) * 0.9 + (sn - 0.5) * 0.7);
	side_snow += foot * 0.42 * smoothstep(0.30, 0.66, band + sn * 0.5);
	cover = max(cover, (1.0 - up) * min(side_snow, 0.92));
	cover *= snow_amount;
	// 阈值必须软：硬切（原 0.40→0.72）会把 fbm 切成二值雪块，
	// 在平整屋顶上读成 20~40cm 的"颗粒"——实测这块屋顶的自相关
	// 在 6~8 像素就掉到 0.44，即短相关长度的块状斑，不是像素噪点。
	cover = smoothstep(0.22, 0.86, cover);
	// 背风面（-x/-z 朝向）雪略厚，但幅度必须小
	if (abs(n.y) < 0.5) {
		float lee = dot(n.xz, normalize(vec2(-0.55, -0.35)));
		cover = clamp(cover + lee * 0.10, 0.0, 1.0);
	}

	// 屋顶雪不能只靠 base_color 常色 + 一层中频 fbm：
	// 那块 fbm 的相关长度就是被测出来的"颗粒"，而真正的积雪是被风
	// 吹出一条条平行的小坎（2~3m 一道）再叠细砂纹。坎的背风侧偏冷、
	// 迎风侧偏暖——这是屋顶雪唯一能读出厚度的地方。
	float sf = snow_field(plane);
	vec2 wd2 = normalize(vec2(0.86, -0.51));
	float sf_fine = fbm(vec2(dot(plane, wd2) * 3.6, dot(plane, vec2(-wd2.y, wd2.x)) * 9.5), 3);
	vec3 snow_c = snow_color * (0.955 + 0.075 * sf);
	// 凹处（坎的背风侧）不是简单变暗，而是变冷：雪在阴影里只反射天光。
	snow_c = mix(snow_c, snow_color * vec3(0.855, 0.895, 0.985),
			(1.0 - smoothstep(0.30, 0.72, sf)) * 0.60);
	snow_c *= 1.0 + (sf_fine - 0.5) * 0.075 * micro_f;
	col = mix(col, snow_c, cover);

	// 混凝土的"脏"：贴地的泥水痕、檐口下方的滴水痕
	float dirt_low = smoothstep(2.4, 0.15, wp.y) * (1.0 - up);
	col = mix(col, col * 0.62, dirt_low * 0.55 * grime);

	ALBEDO = col;
	ROUGHNESS = mix(roughness_v, 0.70, cover);
	ROUGHNESS = mix(ROUGHNESS, 0.16, wetness * (1.0 - cover));
	if (surface_kind > 3.5) {
		ROUGHNESS = mix(0.34, 0.66, smoothstep(0.30, 0.78, fbm(plane * 3.1, 4)));
		METALLIC = 0.0;
		SPECULAR = 0.62;
	} else {
		METALLIC = mix(metallic_v, 0.0, cover);
		SPECULAR = mix(0.42, 0.30, cover);
	}

	AO = mix(1.0, 0.80 + 0.20 * up, cover);
	AO_LIGHT_AFFECT = 0.30;

	// ---- 表面微凹凸：用噪声梯度扰动法线 ----
	// 只偏几度，但在掠射光（清晨长长的斜光）下足以把"墙"从一块平板
	// 变成有颗粒、有起伏的实体表面。没有这层，再好的 albedo 也像贴图板。
	// 幅度必须极小：一旦把噪声梯度放大，混凝土就读成乱石堆了。
	float bump_scale = 3.2;
	vec2 bq = plane * bump_scale;
	float bh = fbm(bq, 3) + vn(bq * 3.7) * 0.30;
	float bhx = fbm(bq + vec2(0.11, 0.0), 3) + vn((bq + vec2(0.11, 0.0)) * 3.7) * 0.30;
	float bhy = fbm(bq + vec2(0.0, 0.11), 3) + vn((bq + vec2(0.0, 0.11)) * 3.7) * 0.30;
	// 粗糙度越高、雪越少，颗粒越明显
	float bump_amt = 0.055 * (1.0 - cover * 0.85) * micro_f;
	// 雪面本身必须有起伏：原式在 cover≈1 时 bump 几乎归零，
	// 于是整片屋顶雪既无反光转折也无坎——只剩底色，读成一张白纸。
	// 用 snow_field 的解析梯度单独给雪面一层"风坎"法线。
	//
	// 但幅度必须很小：0.38 时这片雪在斜光下变成一层油亮的斜向刷痕，
	// 因为 snow_field 是各向异性的（横向 70cm、纵向 2.4m），
	// 法线被整片朝同一个方向掰 20 度，等于给整块屋顶刷了一层清漆。
	// 真实屋顶积雪的坎在 2~3m 外几乎看不出起伏，只在掠射时闪一下。
	// 收到 0.12，并且按像素足迹退场。
	float sfp = max(fwidth(plane.x), fwidth(plane.y));
	float snow_bump = 0.12 * cover * (1.0 - smoothstep(0.010, 0.075, sfp));
	vec2 sq = plane;
	float se = 0.10;
	float s0 = snow_field(sq);
	float shx = snow_field(sq + vec2(se, 0.0)) - s0;
	float shy = snow_field(sq + vec2(0.0, se)) - s0;
	vec2 sgrad = vec2(shx, shy) / se * 0.85;
	vec3 nrm_p = normalize(n + (tg * (bh - bhx) + bt * (bh - bhy)) * bump_amt * 22.0
			+ (tg * sgrad.x + bt * sgrad.y) * snow_bump);


	// 雪面冰晶微闪（只在掠射角）
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - wp);
	float graze = 1.0 - clamp(dot(n, vdir), 0.0, 1.0);
	float crystal = smoothstep(0.965, 1.0, vn(plane * 38.0)) * micro_f;
	EMISSION = vec3(0.58, 0.70, 0.88) * crystal * cover * (0.20 + graze * 0.70) * 0.34;
	// 窗内残光：夜越深越显眼
	EMISSION += window_tint * glass_emit * (0.35 + g_night * 1.9);

	NORMAL = normalize((VIEW_MATRIX * vec4(nrm_p, 0.0)).xyz);
}
