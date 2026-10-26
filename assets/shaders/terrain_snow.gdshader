shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 冰原地面：雪壳 / 风蚀纹 / 岩脉 / 冰壳 / 微光冰晶
uniform vec3 snow_color : source_color = vec3(0.790, 0.822, 0.895);
uniform vec3 snow_shade : source_color = vec3(0.560, 0.648, 0.788);
uniform vec3 rock_color : source_color = vec3(0.185, 0.195, 0.225);
uniform vec3 rock_warm : source_color = vec3(0.330, 0.300, 0.265);
uniform vec3 ice_color : source_color = vec3(0.520, 0.660, 0.790);
uniform float sparkle_amount = 1.0;
uniform float ripple_strength = 1.0;
uniform float rock_bias = 0.0;

// ---- 路面：直接画在地形上，彻底避免独立网格与地形穿模 ----
uniform float road_on = 0.0;
uniform float road_z_half = 4.2;      // 主街沿 z 延伸，半宽（米）
uniform float road_x_half = 3.3;      // 横街沿 x 延伸，半宽（米）
uniform float road_extent = 280.0;    // 街道长度的一半
uniform float road_gap = 11.0;        // 十字路口断开半径
// 注意：带 source_color 的 uniform 会被引擎从 sRGB 转换到线性空间。
// 原来的 asphalt 写 0.108，转成线性只剩 0.012 —— 那是黑漆，不是沥青。
// 真实老化沥青的反照率在线性空间约 0.07~0.10，也就是 sRGB 0.30 上下。
uniform vec3 asphalt : source_color = vec3(0.300, 0.312, 0.336);
uniform vec3 asphalt_lit : source_color = vec3(0.420, 0.432, 0.458);
uniform vec3 road_ice : source_color = vec3(0.470, 0.610, 0.740);

// 诊断通道：0=正常渲染

varying vec3 w_nrm;
varying vec3 w_pos;

float h12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// 五次平滑插值 f^3(f(6f-15)+10)：二阶导在格点处为 0。
// 原来的三次式 f*f*(3-2f) 只在格点处导数为 0、二阶导不为 0，
// 于是每个噪声格子沿对角线留一道折痕；单看一个格子没事，
// 但 grain 层用 26/61 周每米，近景一个格子正好十几个像素，
// 这些折痕连起来就是一片 45° 的斜向细密织纹——这就是
// "雪面像编织袋/颗粒感重"的真正来源。surface.gdshader 早已换成五次式，
// 这里漏改了。
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = h12(i);
	float b = h12(i + vec2(1.0, 0.0));
	float c = h12(i + vec2(0.0, 1.0));
	float d = h12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.877, -0.479), vec2(0.479, 0.877));
	// 第一层先整体转 41° 再偏移：所有倍频共用同一套格子轴向时，
	// 各层的折痕会叠在同一条对角线上，连成规则网格。
	mat2 r0 = mat2(vec2(0.755, -0.656), vec2(0.656, 0.755));
	p = r0 * p + vec2(5.31, 2.17);
	for (int i = 0; i < 5; i++) {
		if (i >= oct) {
			break;
		}
		v += vn(p) * a;
		p = r * p * 2.03 + vec2(11.3, 7.7);
		a *= 0.5;
	}
	return v;
}

// 龟裂线：对 fbm 取等值线，得到成网的细缝
float crack_net(vec2 p, float sc, float w) {
	float a = abs(fbm(p * sc, 3) - 0.5);
	float b = abs(fbm(p * sc + vec2(7.3, 4.1), 3) - 0.5);
	return smoothstep(w, 0.0, min(a, b));
}

// 一个像素在表面上跨过多少米（解析计算，跨三角形连续）。
//
// 之前这里用的是 fwidth(wp.x)：wp 是由顶点插值出来的世界坐标，而屏幕空间导数
// 在一个三角形的三个顶点上是同一个常数——于是每个 2.9m×2.9m 的地形三角形
// 各自得到一套"细节闸门"，整片雪原翻成一层规则三角拼贴。
// 根源不在噪声、不在光照、也不在阴影，而在用逐三角形的量去控制逐像素的细节。
//
// 解析解没有这个毛病：像素张角由投影矩阵反推，再按表面入射角修正
// （掠射时一像素在地面上跨得远得多），全部是连续量，光栅化到哪里都一样。
// 注意：内置量（相机位置、投影矩阵）只有 fragment 里能读，必须由调用方传进来，
// 写在自定义函数里会报 Unknown identifier。
float footprint_m(vec3 wp, vec3 wn, vec3 cam_p, float px_angle) {
	vec3 vd = wp - cam_p;
	float dist = length(vd);
	float cos_t = clamp(abs(dot(normalize(vd), normalize(wn))), 0.10, 1.0);
	return dist * px_angle / cos_t;
}


// 雪面微起伏场（用于求梯度做 bump）。比 fbm 便宜，只取 3 层
// 全部沿风向拉长：真实雪原的起伏是风堆出来的，纹理主轴一律顺风，
// 各向同性的起伏在掠射光下只会读成一片"砂纸"，不会读成"雪"。
float bump_field(vec2 p) {
	vec2 wd = normalize(vec2(0.86, -0.51));
	vec2 wc = vec2(-wd.y, wd.x);
	float al = dot(p, wd);
	float ac = dot(p, wc);
	float a = fbm(vec2(al * 0.55, ac * 2.10), 3);          // 顺风长脊
	float b = fbm(vec2(al * 2.20, ac * 7.60) + 31.0, 2);   // 细一波的风纹
	float c = fbm(p * 0.22 + 9.0, 2);                      // 缓坡起伏
	float d = fbm(p * 0.031 + 2.7, 3);                     // 大尺度雪包
	return a * 0.40 + b * 0.22 + c * 0.13 + d * 0.25;
}

void vertex() {
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wp = w_pos;
	float slope = 1.0 - clamp(w_nrm.y, 0.0, 1.0);

	// 像素在地面上的足迹（米）。全 shader 只算这一次：
	// 内置量只有 fragment 作用域能读，而且重复解析求值会引入细微台阶。
	float px_angle = 2.0 * atan(1.0 / max(abs(INV_PROJECTION_MATRIX[1][1]), 1e-4))
		/ max(VIEWPORT_SIZE.y, 1.0);
	float fp_all = footprint_m(wp, w_nrm, INV_VIEW_MATRIX[3].xyz, px_angle);

	// ---- 风蚀纹：沿风向（-x）拉长的雪脊 ----
	// 拉长比不能太狠：0.55/0.055 会让每条纹在 z 上拖出十几米，
	// 近景读成一笔一笔的水彩拖痕。保持在 3:1 左右的"风纹"尺度才像雪。
	float drift = fbm(vec2(wp.x * 0.34, wp.z * 0.13), 4);
	float drift2 = fbm(vec2(wp.x * 1.35 + 31.0, wp.z * 0.52), 3);
	// 反向的第二组风纹：真实雪面是被反复风向刮出来的，单一方向太像刷子
	float drift3 = fbm(vec2(wp.x * 0.16 - 7.0, wp.z * 0.62 + 3.0), 3);
	float ripple = (drift * 0.52 + drift2 * 0.26 + drift3 * 0.22) * ripple_strength;
	float ridge = smoothstep(0.42, 0.78, ripple);

	// 大尺度的雪包：几米到几十米一级的起伏，让雪原不是一块平地。
	// 只靠细风纹的话，中景会糊成一张白纸。
	float coarse = fbm(wp.xz * 0.028 + 2.7, 4);
	float coarse2 = fbm(wp.xz * 0.075 + 19.0, 3);
	float swell = coarse * 0.70 + coarse2 * 0.30;

	// ---- 岩脉：只由噪声决定，绝不交给坡度 ----
	//
	// 这里曾经写 slope * 1.35 + rock_n * 0.55，再塞进 smoothstep(0.30, 0.62)。
	// slope 来自逐顶点法线插值：顶点之间是 C0，跨过三角形边之后导数会跳。
	// 用一个只有 0.32 宽的过渡带把它放大成 0/1，地面就被切成一堆直边多边形
	// —— 每片亮度不同、边界笔直，看起来像被打湿的大理石纹或三角亮楔。
	// 逐三角形恒定值是光栅化本身带进来的，着色器再怎么调噪声也盖不住它，
	// 唯一的解法是让这个量根本不参与二值化。
	// 现在岩与雪只由噪声分区，过渡带宽到接近线性：真实雪原上本来也没有
	// 一条笔直的雪-岩分界，只有被风一点点吹薄吹透的过渡。
	float rock_n = fbm(wp.xz * 0.085, 4);
	float rock_n2 = fbm(wp.xz * 0.021 + 5.0, 3);
	float rock_mask = smoothstep(0.56, 0.88, rock_n * 0.62 + rock_n2 * 0.38);
	// 陡坡确实露岩，但权重压得很低、过渡带宽到几乎没有硬边
	float rock_slope = smoothstep(0.26, 0.98, slope);
	rock_mask = clamp(rock_mask + rock_slope * 0.42, 0.0, 1.0);

	// ---- 冰壳：低洼处的蓝冰 ----
	float low = fbm(wp.xz * 0.035 + 17.0, 4);
	float ice_mask = smoothstep(0.58, 0.92, low) * (1.0 - rock_mask) * 0.85;

	// ---- 颜色装配 ----
	vec3 rock_c = mix(rock_color, rock_warm, smoothstep(0.35, 0.75, fbm(wp.xz * 0.16 + 3.0, 3)));
	rock_c *= 0.78 + 0.42 * fbm(wp.xz * 1.4, 3);

	vec3 snow_c = snow_color * (0.90 + 0.17 * ripple);
	// 雪脊背光面偏蓝（空气透视）
	snow_c = mix(snow_c, snow_shade, (1.0 - ridge) * 0.42);

	// 雪包的高低差：迎风侧更白更干、背风侧压暗偏蓝。
	// 这是让大片雪地在没有几何起伏的地方仍然"有体积"的关键。
	float lift = smoothstep(0.34, 0.78, swell);
	float sinkm = smoothstep(0.30, 0.72, 1.0 - swell);
	snow_c *= 0.84 + 0.30 * lift;
	snow_c = mix(snow_c, snow_shade * 0.88, sinkm * 0.55);

	// 风刮出的硬雪面：一层几乎不长纹路的亮壳，只有零星雪粒，
	// 视觉上像被风吹实了的雪，比周围的松雪更亮更平。
	float crust = smoothstep(0.58, 0.86, fbm(wp.xz * 0.017 + 41.0, 4));
	crust *= smoothstep(0.62, 0.30, abs(swell - 0.52) * 3.0);
	snow_c = mix(snow_c, snow_color * 1.06, crust * 0.55);

	// ---- 雪况区块：几十米一级的"这片雪和那片雪不一样" ----
	// 中景发白不是缺细节，是缺大尺度的明暗分区：如果 30m 外的每一个像素
	// 都落在同一个亮度上，眼睛找不到任何边界，整片雪原就读成一张纸。
	// 真实的雪原是被风分区刮出来的：吹实发亮的冰壳带、被砂石染灰的脏雪带、
	// 背风积起来的松雪。这三种质地必须各自成片，而不是均匀地拌在一起。
	float tract = fbm(wp.xz * 0.0125 + 51.0, 3);
	float tract2 = fbm(wp.xz * 0.038 - 13.0, 3);
	tract = tract * 0.72 + tract2 * 0.28;
	float polish = smoothstep(0.54, 0.78, tract);       // 风蚀冰壳带
	float powder = smoothstep(0.47, 0.26, tract);       // 背风松雪带
	// 冰壳带：更暗、更蓝、更光滑（后面 ROUGHNESS 会一起降）
	snow_c = mix(snow_c, mix(snow_color * 0.78, ice_color * 0.72, 0.35), polish * 0.46);
	// 松雪带：稍暗一点点，压住整体亮度，给冰壳带留出对比空间
	snow_c = mix(snow_c, snow_c * 0.86, powder * 0.55);

	// ---- 近景雪壳的破碎感 ----
	// 中远景靠大尺度雪包就够了，但脚下这块地方必须"粒粒分明"，
	// 否则第一人称在雪地上走，画面下半屏永远是一张白纸。
	//
	// 这里曾经用各向同性的 plate/plate2 叠一张"雪壳斑块"，再用它的等值线
	// 画缝。结果近景是一层 45° 的规则织纹：等值线天生连成网，各向同性的
	// fbm 又让网眼大小一致，两条加起来就是编织袋。
	// 真实雪面近看只有一件事——风把雪吹成一条条平行小坎，坎的方向就是
	// 风向，横向 60~80cm、纵向连续好几米。所以改成各向异性：
	float t_fp = fp_all;
	vec2 wdir = normalize(vec2(0.86, -0.51));
	vec2 wcro = vec2(-wdir.y, wdir.x);
	float al = dot(wp.xz, wdir);
	float ac = dot(wp.xz, wcro);
	// 细节的可见距离：原先 0.014~0.085m/px，30m 外 near_f 就归零，
	// 于是 30m 以外的雪面只剩低频起伏——实测参考照片在中频段
	// （屏幕上 4~16 像素）的能量占比 0.11~0.15，我们只有 0.05~0.10，
	// 这就是"我们的雪像一张白纸"的量化原因。放宽到 0.18m/px（约 45m）
	// 让中频结构一直活到中景。
	float near_f = 1.0 - smoothstep(0.020, 0.180, t_fp);
	float plate = fbm(vec2(al * 0.40, ac * 1.55) + 3.1, 3);
	// 第二层波长约 24cm，用同一个 near_f 也会在 20m 外欠采样；
	// 给它单独一档更短的可见距离。
	float plate2_f = 1.0 - smoothstep(0.010, 0.070, t_fp);
	float plate2 = fbm(vec2(al * 1.05, ac * 4.20) - 9.0, 2) * plate2_f;
	// 只留坎的横向亮度差，不再用等值线画缝
	snow_c *= 1.0 + (0.085 * plate - 0.042) * near_f;
	snow_c *= 1.0 + (0.050 * plate2 - 0.025 * plate2_f) * near_f;
	// 坎背的浅阴影：把 plate 的低值区（坎与坎之间凹下去的地方）压一点冷灰。
	// 权重远低于原来的 seam（0.62*0.30~0.55），且不形成闭合网。
	float trough = smoothstep(0.36, 0.18, plate) * near_f;
	snow_c = mix(snow_c, mix(snow_shade, snow_c, 0.55), trough * 0.16);

	// 雪粒：极细的高频颗粒，只在近处可见。
	// 这里必须用**独立的、更严的**距离闸门：grain 的波长是 3.8cm 和 1.6cm，
	// 近景的 near_f 要到 18cm/px 才归零，等于允许"一个像素跨过 4 个噪声周期"
	// 的区域继续画 3.8cm 的纹理——那是标准的欠采样，屏幕上会浮出一层
	// 周期约 45px 的规则斜纹（实测 FFT 峰在 fy=0.022，与阴影开不开、
	// 后处理开不开都无关，因为它是采样问题不是光照问题）。
	// 颗粒只有在"一个像素小于半个周期"时才有意义，所以闸门收到 5cm/px。
	float grain_f = 1.0 - smoothstep(0.006, 0.050, t_fp);
	float grain = vn(wp.xz * 26.0) * 0.5 + vn(wp.xz * 61.0) * 0.5;
	snow_c *= 1.0 + (0.07 * grain - 0.035) * grain_f;

	// ---- 中频结构：2~8 米一级的风吹波纹与雪坎 ----
	// 尺度谱实测（见 tools/ref/compare_energy.py）：参考照片在屏幕上 4~16 像素
	// 这一档的能量占比 0.11~0.15，我们只有 0.05~0.10，而 64 像素以上的粗尺度
	// 反而占到 0.35。也就是说我们的雪只有"大起伏"，没有"中结构"，
	// 读起来像一张被灯光揉出明暗的纸。这一层就是补中频。
	// 频率按米给：0.42/米 ≈ 2.4m 周期，1.15 周/米 ≈ 不到 1m，两者叠加成
	// 顺风方向的短波痕。衰减闸门比近景细节宽得多，中景仍然是满权重。
	// 同样必须走 al/ac 的分轴坐标：各向同性的 fbm 不会长出"顺风的条"，
	// 只会长出等轴的斑，而斑一旦被挑成脊就是网格。
	float mid_a = fbm(vec2(al * 0.30, ac * 0.90) + 8.3, 4);
	float mid_b = fbm(vec2(al * 0.85, ac * 2.60) - 4.0, 3);
	float mid = mid_a * 0.66 + mid_b * 0.34;
	float mid_w = 1.0 - smoothstep(0.120, 0.520, t_fp);
	// 雪坎：现在 mid 已经是沿风向拉长的，它的等值线自然是顺风的条，
	// 不会连成闭合网。再用一层大尺度遮罩决定"哪里长坎、哪里是平雪"——
	// 真实雪原上的 sastrugi 是成片出现的，不可能整片地均匀排满。
	// 最后乘一层沿风向的断续，让每条坎在纵向有始有终。
	float field_m = smoothstep(0.34, 0.66, fbm(vec2(al * 0.045, ac * 0.16) + 23.0, 3));
	float along_break = smoothstep(0.30, 0.70, fbm(vec2(al * 0.22, ac * 0.05) + 51.0, 3));
	float crag = smoothstep(0.085, 0.0, abs(mid - 0.5)) * mid_w * field_m * along_break;
	// 脊的迎风面略亮、背风面略暗——没有几何，只能靠明暗把"坎"画出来
	float face = smoothstep(0.40, 0.62, mid) - smoothstep(0.62, 0.86, mid);
	snow_c *= 1.0 + (0.13 * face) * mid_w;
	// 坎背的浅阴影：偏冷、偏暗，这是雪面在漫射光下唯一能长出的"结构"
	snow_c = mix(snow_c, mix(snow_shade, snow_c, 0.42), crag * 0.30);
	// 坎脊边缘的一线亮边
	snow_c += snow_color * crag * 0.05;

	// 风蚀出的冰面斑块：雪被吹薄，露出下面发蓝的暗冰。
	// 这些暗斑是雪原上唯一的"深色锚点"，没有它们画面会糊成一片白。
	// 尺度必须收小、形状必须碎：大块的暗斑在地面上会读成脏污拖影。
	float scour = smoothstep(0.76, 0.94, fbm(vec2(wp.x * 0.17, wp.z * 0.15) + 7.0, 4));
	scour *= smoothstep(0.48, 0.82, fbm(wp.xz * 0.10 + 61.0, 3));
	scour *= 1.0 - smoothstep(0.55, 0.90, fbm(wp.xz * 0.42 + 13.0, 3)) * 0.6;
	snow_c = mix(snow_c, ice_color * 0.80, scour * 0.42);

	// ---- 反照率归一 ----
	// 真实新雪的反照率是 0.80~0.90，而那指的是**线性反射率**。
	// snow_color 写的 sRGB (0.79, 0.82, 0.89) 转成线性已经是 (0.59, 0.64, 0.76)，
	// 再加上下面这一串 0.84~1.13 的增益，雪面实际反照率被推到 0.9 以上。
	// 后果不是"雪太亮"，而是它一路贴到高光肩部的拐点上：实测近景地面 L=0.775，
	// 参考照片的雪地是 0.37~0.51。风纹、雪坎、脚下的雪壳结构全部被
	// 压成一张平滑的白纸——看起来"灰"，其实是"没有任何可读的起伏"。
	// 这里把重复的那一层系数收回来，让雪落在能看清结构的亮度区间。
	snow_c *= 0.78;

	vec3 col = mix(snow_c, rock_c, rock_mask);
	col = mix(col, ice_color, ice_mask * 0.75);

	// 雪与岩的交界处挂一层薄雪
	float fringe = smoothstep(0.18, 0.0, abs(rock_mask - 0.35)) * 0.5;
	col = mix(col, snow_c, fringe * 0.35);

	float rough = mix(0.68, 0.88, rock_mask);
	rough = mix(rough, 0.20, ice_mask);
	// 风蚀冰壳带不是"白一点"，而是"被吹实、反光"：粗糙度必须跟着降，
	// 否则涂暗了只会读成一片脏雪，出不来那种被风磨过的硬壳反光。
	rough = mix(rough, 0.34, polish * 0.85);
	rough = mix(rough, 0.90, powder * 0.70);
	float spec = mix(0.42, 0.26, rock_mask);
	spec = mix(spec, 0.68, polish * 0.80);
	spec = mix(spec, 0.30, powder * 0.60);
	float spark = sparkle_amount;
	float ao = 1.0;

	// ================= 路面 =================
	// road_on=0 时不产生任何额外开销以外的效果；>0 时按世界坐标判断是否落在街道上
	float road_w = 0.0;
	if (road_on > 0.5) {
		float uz = (abs(wp.x) <= road_z_half) ? 1.0 : 0.0;   // 主街（沿 z）
		float ux = (abs(wp.z) <= road_x_half) ? 1.0 : 0.0;   // 横街（沿 x）
		float in_z = uz * step(abs(wp.z), road_extent);
		float in_x = ux * step(abs(wp.x), road_extent);
		// 十字路口由两条街自然重叠覆盖；路口中心让雪盖多一点
		float road = max(in_z, in_x);
		// 路面边缘用噪声打碎，避免笔直的刀切线
		float edge_n = (fbm(wp.xz * 0.55, 4) - 0.5) * 0.95;
		float half_now = (in_z >= in_x) ? road_z_half : road_x_half;
		float across = (in_z >= in_x) ? wp.x : wp.z;
		road *= step(abs(across), half_now + edge_n);

		// 沿路的坐标（用于材质铺展）
		float along = (in_z >= in_x) ? wp.z : wp.x;
		float lat = (in_z >= in_x) ? wp.x : wp.z;
		float latn = clamp(abs(lat) / max(half_now, 0.001), 0.0, 1.0);

		// ---- 抗走样：一个像素在路面上跨多少米 ----
		// 判断依据只能是 fwidth：一个周期至少要有 2~3 个像素才画得干净，
		// 所以波长 L 的细节必须满足 fp < L/2.5 才能留。
		// 之前把骨料级（4cm）的闸门开到 0.115m/px，等于让 0.8 像素一个周期
		// 的噪声照样满权重参与混色——整条街就是这样长出斜向的摩尔纹。
		float fp_road = fp_all;
		float fine_r = 1.0 - smoothstep(0.010, 0.024, fp_road);   // 4cm 骨料
		float mid_r = 1.0 - smoothstep(0.055, 0.130, fp_road);    // 30cm 细纹
		float coarse_r = 1.0 - smoothstep(0.400, 1.200, fp_road); // 2m 修补斑

		// 沥青底：大块修补 + 中频斑驳 + 骨料颗粒
		// 注意各噪声的**各向异性方向**：along 是沿路方向（几十米长的一段），
		// lat 是横向（几米宽）。如果两个方向给相近的系数，画出来的是等方斑，
		// 在透视下会被拉成一条条斜向的碎块——玩家看到的就是"满地迷彩"。
		// 沥青的真实结构是**沿路延伸**的：纹理必须在 along 方向拉长 3~5 倍。
		//
		// 更要紧的是**振幅**。沥青是一条 8.4m 宽的路，横向只有三四个"块"的位置。
		// 之前用 smoothstep(0.34,0.74) 在 asphalt(0.300) 与 asphalt_lit(0.420)
		// 之间整段插值，等于让横向每 2.4m 就出现一次 40% 的明暗起伏 ——
		// 那不是沥青，那是被水磨过的大理石：路面上出现一条条顺着透视方向
		// 铺开的、边缘柔软的亮带和暗带。真实的沥青是**一整块安静的深灰**，
		// 变化只来自几厘米的骨料、几米的稀疏修补、以及车辙。
		// 所以大尺度色差先压到 ±4%，修补斑单独用稀疏掩码去做。
		float drift = fbm(vec2(along * 0.050, lat * 0.16), 3) - 0.5;
		vec3 as_c = asphalt * (1.0 + drift * 0.085);
		// 修补斑：稀疏、边界硬（沥青补丁本来就有直边），只在近处出现
		float patch = fbm(vec2(along * 0.058, lat * 0.30) + vec2(17.0, 5.0), 3);
		float patch_m = smoothstep(0.615, 0.700, patch) * coarse_r;
		as_c = mix(as_c, asphalt_lit, patch_m * 0.62);
		// 中频斑驳：沿路拉长的条痕（不是斑），波长 ~3m×0.5m。振幅必须是**
		// 细节级**的（±4%），一旦到 ±16% 就变成上面那种大理石条纹的细版本。
		as_c *= 1.0 + (fbm(vec2(along * 0.34, lat * 3.6), 3) - 0.5) * 0.085 * mid_r;
		// 骨料：10 周/米（10cm 一粒）。骨料本来该是等方的，
		// 但屏幕上只有近处 1~2m 内看得见，不需要牺牲它去换方向性。
		as_c *= 1.0 + (vn(vec2(along * 10.0, lat * 10.0)) - 0.5) * 0.16 * fine_r;

		// 龟裂：路面的裂缝是**纵向**的（沿行车方向），横裂稀疏。
		// 等方的 crack_net 在透视下会画出一片碎瓷，必须给两个方向不同的频率。
		float cr_a = crack_net(vec2(along * 0.30, lat * 1.35), 1.0, 0.045);
		float cr_b = crack_net(vec2(along * 0.72, lat * 0.55), 1.0, 0.038);
		float cr = cr_a * 0.78 + cr_b * 0.22;
		// 裂纹在远处会变成满地的黑点，按 footprint 让它整条淡出
		cr *= mid_r;
		cr *= 0.82;   // 整体削弱：路面已经够花，再密就脏
		as_c = mix(as_c, as_c * 0.52, clamp(cr, 0.0, 1.0) * 0.9);

		// 车辙：两条被压出的冰面
		float rut = exp(-pow((latn - 0.44) * 5.2, 2.0));
		float rut2 = exp(-pow((latn - 0.72) * 6.4, 2.0));
		float rut_m = clamp(rut * 0.95 + rut2 * 0.35, 0.0, 1.0);
		float rut_ice = rut_m * smoothstep(0.40, 0.72, fbm(vec2(along * 0.20, lat * 1.7), 3));
		// 车辙里的冰只能是**碎冰**，不能是一整条连续冰带。
		// 连续冰带在透视里就是两条光滑的镜面条，跟路面其余部分脱节。
		// 再叠一层高频碎裂掩码，把冰带腐蚀成一串斑。
		float rut_break = smoothstep(0.30, 0.62, fbm(vec2(along * 1.9, lat * 5.5), 4));
		rut_ice *= mix(0.35, 1.0, rut_break);
		// 冰面不能比沥青暗太多，否则会读成两条黑色的水沟；
		// 真实车辙冰是被砂石磨脏的灰白色。mix 的目标色也一起提亮。
		as_c = mix(as_c, mix(road_ice, vec3(0.44, 0.47, 0.50), 0.35) * 0.86, rut_ice * 0.46);

		// 油污/雪泥：沿行进方向拉长
		float smear = smoothstep(0.56, 0.86, fbm(vec2(along * 0.34, lat * 2.1), 4)) * coarse_r;
		as_c = mix(as_c, as_c * 0.70, smear * 0.55);

		// 路面上的积雪：从路肩往里蔓延 + 零散雪斑
		float sn_r = fbm(vec2(along * 0.28, lat * 1.4), 4);
		float road_snow = smoothstep(0.64, 1.04, latn + (sn_r - 0.5) * 0.62);
		float blotch = smoothstep(0.70, 0.90, fbm(vec2(along * 0.38 + 3.0, lat * 0.9), 4));
		road_snow = clamp(road_snow + blotch * 0.62, 0.0, 1.0);
		road_snow *= smoothstep(0.15, 0.55, 1.0 - rut_ice * 0.85);
		// 路口中央被彻底埋掉
		float junction = (in_z > 0.5 && in_x > 0.5) ? 1.0 : 0.0;
		road_snow = clamp(road_snow + junction * smoothstep(0.30, 0.75, fbm(wp.xz * 0.9, 3)) * 0.85, 0.0, 1.0);

		// ---- 车道线：直接画在地上，永远不会悬空/穿模 ----
		// 中线虚线：8m 周期（亮 3m 空 5m）。原来的 3.6 亮 0.7 空读成一条连续
		// 的粗黄条，像卡通画的路，而不是被雪埋了一半的旧马路。
		float dm = abs(mod(along + 1.0, 8.0));
		float dash = smoothstep(0.0, 0.12, dm) * (1.0 - smoothstep(2.9, 3.15, dm));
		// 线宽 0.22m（真实道路中线 0.15m，稍加宽以保证远距离还能读到）
		float center_line = (1.0 - smoothstep(0.055, 0.105, abs(lat))) * dash;
		float edge_line = (1.0 - smoothstep(0.040, 0.090, abs(abs(lat) - (half_now - 0.55))));
		float paint_m = clamp(center_line + edge_line, 0.0, 1.0);
		// 只在各自街道上画：主街有中线，横街也有
		paint_m *= road;
		// 漆面剥落 + 被雪盖住
		float peel = mix(1.0, smoothstep(0.30, 0.60, fbm(vec2(along * 2.6, lat * 2.6), 3) + 0.28), mid_r);
		paint_m *= peel;
		paint_m *= 1.0 - road_snow * 0.92;

		vec3 as_snow = snow_c * (0.96 + 0.06 * sn_r);
		vec3 road_c = mix(as_c, as_snow, road_snow);
		// 漆面早就不是新的：褪色、发灰、被砂石磨掉半边。纯亮的黄线会让
		// 整条街读成"刚画好的赛车道"，与这个冻了二十年的世界不搭。
		vec3 paint_c = mix(vec3(0.58, 0.53, 0.33), vec3(0.50, 0.52, 0.55), edge_line);
		road_c = mix(road_c, paint_c, clamp(paint_m, 0.0, 1.0) * 0.70);

		col = mix(col, road_c, road);
		// 路面 roughness / specular 必须几乎和雪一样"哑"。
		// 这里曾经写过 mix(0.86, 0.46, rut_ice)：0.46 的粗糙度 + 0.60 的镜面
		// 会让车辙在低角度阳光下变成一条条镜面反光，整条街读成"结冰的黑河"。
		// 真实的老沥青在冬天是**粗糙**的：磨光的车辙最多到 0.62，
		// 而镜面强度要压下来，否则暗底一衬，高光就是唯一可见的东西。
		rough = mix(rough, mix(0.90, 0.62, rut_ice), road);
		rough = mix(rough, 0.86, road * road_snow);
		spec = mix(spec, mix(0.34, 0.42, rut_ice), road);
		spark = mix(1.0, 0.25, road * (1.0 - road_snow) * rut_ice);

		// 路面裂缝的凹陷阴影
		ao = 1.0 - cr * road * 0.18;
		road_w = road;
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = 0.0;

	// 雪面凹陷处的柔和自遮蔽
	float crev = smoothstep(0.30, 0.72, 1.0 - ripple);
	AO = clamp(ao - crev * 0.30 - rock_mask * 0.22, 0.30, 1.0);
	AO_LIGHT_AFFECT = 0.35;

	// ---- 冰晶微闪：只在掠射角与特定噪声上出现 ----
	// 闪点是一种"每像素重新抽签"的效果：噪声波长 3cm，只要一个像素跨过
	// 2cm 以上，画面就会变成满地跳动的雪花噪点。所以必须按 footprint 关掉。
	float flash_r = 1.0 - smoothstep(0.008, 0.030, fp_all);
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - wp);
	float graze = 1.0 - clamp(dot(normalize(w_nrm), vdir), 0.0, 1.0);
	float crystal = smoothstep(0.955, 1.0, vn(wp.xz * 34.0));
	float twinkle = 0.55 + 0.45 * sin(TIME * 2.3 + h12(floor(wp.xz * 34.0)) * 30.0);
	float glint = crystal * twinkle * (1.0 - rock_mask) * (0.35 + graze * 0.9) * flash_r;
	EMISSION = vec3(0.55, 0.68, 0.85) * glint * 0.55 * spark;

	// ---- 雪面微起伏：用高度场梯度扰动法线，让掠射光下有细节 ----
	// 只在非路面、非裸岩处生效；距离越远权重越小，避免远处闪烁
	// 同样的道理：0.06m 步长采出来的梯度在远处是一个完全随机方向的法线，
	// 掠射阳光下那一片会翻成"电视雪花"。按 footprint 让它平滑退出。
	float bump_amt = (1.0 - rock_mask) * (1.0 - ice_mask * 0.5);
	bump_amt *= 1.0 - smoothstep(0.030, 0.150, fp_all);
	if (road_on > 0.5) {
		bump_amt *= 1.0 - road_w * 0.85;
	}
	vec2 bp = wp.xz;
	// 步长必须跟着像素足迹走：固定 6cm 的差分步长在掠射角下
	// 等于在每个像素里塞进好几个随机方向的梯度，法线乱跳，
	// 那片雪面会翻成一层电视雪花（屏上表现为细密斜纹）。
	float e = clamp(t_fp * 1.2, 0.06, 0.60);
	float h0 = bump_field(bp);
	float hx = bump_field(bp + vec2(e, 0.0));
	float hz = bump_field(bp + vec2(0.0, e));
	vec2 grad = vec2(hx - h0, hz - h0) / e;
	// 雪脊方向正是风纹方向，梯度强度随噪声大小起伏
	grad *= 0.075 * bump_amt;
	vec3 nrm_w = normalize(w_nrm - vec3(grad.x, 0.0, grad.y));

	// 远景雪面的空气透视由雾负责，这里只补一点边缘散射
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm_w, 0.0)).xyz);
}
