extends Node3D
## 大气与昼夜：自定义天穹（渐变 / 太阳 / 星空 / 极光 / 云）、日月双光源、
## 体积雾与分级调色、三档风雪粒子。仅表现层；对 Game 的状态写入语义保持不变。

# ---------------------------------------------------------------- 调色板
# 每个关键帧：天顶 / 地平线 / 地面 / 太阳光色 / 雾色 / 环境能量 / 雾浓度倍率
# 设计原则：天要够蓝够沉，雪地才能靠自身明度跳出来；地平线允许暖，
# 但暖只在太阳高度角低的时候出现，绝不把整片天冲成奶白。
const STOPS := [
	{ # 0:00 深夜
		"h": 0.0,
		"zen": Color(0.012, 0.022, 0.058),
		"hor": Color(0.042, 0.068, 0.124),
		"gnd": Color(0.014, 0.020, 0.034),
		"sun": Color(0.55, 0.68, 1.00),
		"fog": Color(0.044, 0.066, 0.112),
		"amb": 0.30,
		"den": 1.00,
	},
	{ # 4:40 极夜将尽
		"h": 4.7,
		"zen": Color(0.026, 0.048, 0.108),
		"hor": Color(0.115, 0.140, 0.205),
		"gnd": Color(0.030, 0.040, 0.062),
		"sun": Color(0.80, 0.66, 0.72),
		"fog": Color(0.100, 0.122, 0.172),
		"amb": 0.33,
		"den": 1.15,
	},
	{ # 6:20 日出
		"h": 6.4,
		"zen": Color(0.105, 0.155, 0.290),
		"hor": Color(0.880, 0.470, 0.290),
		"gnd": Color(0.140, 0.125, 0.155),
		"sun": Color(1.00, 0.55, 0.30),
		"fog": Color(0.480, 0.360, 0.360),
		"amb": 0.28,
		"den": 1.30,
	},
	{ # 8:00 清晨
		"h": 8.2,
		"zen": Color(0.125, 0.180, 0.268),
		"hor": Color(0.395, 0.442, 0.500),
		"gnd": Color(0.190, 0.215, 0.275),
		"sun": Color(1.00, 0.78, 0.60),
		"fog": Color(0.340, 0.392, 0.470),
		"amb": 0.40,
		"den": 1.00,
	},
	{ # 12:00 正午（冬日仍偏低、偏冷）
		"h": 12.0,
		"zen": Color(0.132, 0.190, 0.282),
		"hor": Color(0.408, 0.458, 0.520),
		"gnd": Color(0.230, 0.270, 0.340),
		"sun": Color(1.00, 0.94, 0.87),
		"fog": Color(0.352, 0.408, 0.486),
		"amb": 0.42,
		"den": 0.80,
	},
	{ # 16:30 午后斜阳
		"h": 16.5,
		"zen": Color(0.128, 0.178, 0.252),
		"hor": Color(0.462, 0.442, 0.452),
		"gnd": Color(0.215, 0.210, 0.245),
		"sun": Color(1.00, 0.74, 0.50),
		"fog": Color(0.372, 0.372, 0.430),
		"amb": 0.40,
		"den": 0.95,
	},
	{ # 18:20 日落
		"h": 18.3,
		"zen": Color(0.075, 0.115, 0.260),
		"hor": Color(0.900, 0.400, 0.220),
		"gnd": Color(0.110, 0.100, 0.130),
		"sun": Color(1.00, 0.44, 0.20),
		"fog": Color(0.420, 0.280, 0.280),
		"amb": 0.26,
		"den": 1.20,
	},
	{ # 19:40 暮蓝
		"h": 19.7,
		"zen": Color(0.030, 0.055, 0.140),
		"hor": Color(0.190, 0.200, 0.320),
		"gnd": Color(0.040, 0.048, 0.075),
		"sun": Color(0.70, 0.55, 0.60),
		"fog": Color(0.150, 0.165, 0.245),
		"amb": 0.34,
		"den": 1.15,
	},
	{ # 21:00 夜
		"h": 21.0,
		"zen": Color(0.012, 0.022, 0.058),
		"hor": Color(0.042, 0.068, 0.124),
		"gnd": Color(0.014, 0.020, 0.034),
		"sun": Color(0.55, 0.68, 1.00),
		"fog": Color(0.044, 0.066, 0.112),
		"amb": 0.30,
		"den": 1.00,
	},
]
const SKY_SHADER := """
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.15, 0.32, 0.60);
uniform vec3 horizon_color : source_color = vec3(0.76, 0.82, 0.90);
uniform vec3 ground_color : source_color = vec3(0.40, 0.44, 0.50);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.90);
uniform vec3 sun_dir = vec3(0.0, 0.3, 1.0);
uniform vec3 moon_dir = vec3(0.0, 0.6, -1.0);
uniform float sun_energy = 1.0;
uniform float night = 0.0;
uniform float aurora = 0.0;
uniform float stars = 0.0;
uniform float clouds = 0.0;
uniform float sun_disc = 1.0;
uniform float haze = 1.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// 五次插值。三次插值 f*f*(3-2f) 在格子的对角线上留一条折痕，
	// 云放大到原分辨率看，边缘是一段段直边——像用剪刀剪的纸。
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		if (i >= oct) {
			break;
		}
		v += vn(p) * a;
		p = p * 2.03 + vec2(19.3, 7.7);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float e = d.y;
	vec3 sdir = normalize(sun_dir);
	float sd = dot(d, sdir);

	// ---- 天穹渐变：地平线堆积的雾霭更亮更厚 ----
	float up = clamp(e, 0.0, 1.0);
	float grad = pow(1.0 - up, 3.1);
	vec3 col = mix(zenith_color, horizon_color, grad);

	// 地平线附近的雾霭带。
	// 这一层是"空气感"的来源，但一过量就变成一条贴在天边的奶白胶带——
	// 雪原本身已经很亮，天上再亮一条，两者就粘成一片，纵深全没了。
	// 所以只保留紧贴地平线的一薄层，且不再额外提亮。
	float band = exp(-pow(max(e, 0.0) * 11.5, 1.7));
	col = mix(col, horizon_color * 1.04, band * 0.30 * haze);

	// 地平线以下：压暗成远山/冰原的剪影色
	if (e < 0.0) {
		float g = smoothstep(0.0, 0.16, -e);
		col = mix(col, ground_color, g * 0.94);
	}

	// ---- 太阳：光晕 + 前向散射 + 日轮 ----
	// 只保留近太阳的紧致光斑和一圈柔和散射，宽晕（pow 3 项）会在大气雾里
	// 糊成一大团白斑，把整片天空和远山都冲掉。
	float sun_up = smoothstep(-0.10, 0.04, sdir.y);
	float halo = pow(max(sd, 0.0), 320.0) * 1.5 + pow(max(sd, 0.0), 42.0) * 0.34;
	halo += pow(max(sd, 0.0), 9.0) * 0.055;
	col += sun_color * halo * sun_energy * sun_up * 2.2;

	float disc = smoothstep(0.99955, 0.99985, sd);
	col += sun_color * disc * sun_energy * sun_up * 26.0 * sun_disc;

	// ---- 月亮：小盘 + 冷光晕 ----
	if (night > 0.01) {
		float md = dot(d, normalize(moon_dir));
		col += vec3(0.72, 0.80, 1.0) * smoothstep(0.99965, 0.99990, md) * night * 3.2;
		col += vec3(0.36, 0.46, 0.72) * pow(max(md, 0.0), 60.0) * night * 0.45;
	}

	// ---- 星空：立方格点 + 亮度分布 + 银河带 ----
	// 格点尺度决定星的疏密，但**星的半径必须按屏幕像素算**：
	// d*160 时一个格子在 75° 视场、1280 宽的画面上约 6px，
	// 原来 core 用 smoothstep(0.085, 0.0, dist) 只有 0.085*6 ≈ 0.5px，
	// 整片星空全是亚像素的点——渲染出来等于没有星星。
	// 现在把核心放大到 0.22（≈1.3px），并且让亮星有一个柔和的晕。
	if (stars > 0.01 && !AT_CUBEMAP_PASS) {
		vec3 sp = d * 160.0;
		vec3 cell = floor(sp);
		float r = h31(cell);
		if (r > 0.970) {
			vec3 off = vec3(h31(cell + 11.0), h31(cell + 23.0), h31(cell + 37.0));
			float dist = length(fract(sp) - off);
			float mag = clamp((r - 0.970) / 0.030, 0.0, 1.0);
			float core = smoothstep(0.230, 0.0, dist) * (0.30 + mag * 0.90);
			float halo = smoothstep(0.520, 0.0, dist) * 0.10 * (0.3 + mag);
			float tw = 0.74 + 0.26 * sin(TIME * 1.7 + r * 90.0);
			vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.88, 0.74), h31(cell + 5.0));
			col += tint * (core + halo) * tw * stars * 2.2 * smoothstep(-0.02, 0.10, e);
		}
		// 银河：一条被噪声打散的暗亮带
		float mw = exp(-pow(dot(d, normalize(vec3(0.34, 0.60, -0.72))) * 3.1, 2.0));
		float grain = fbm(vec2(atan(d.x, d.z) * 5.0, e * 9.0), 4);
		col += vec3(0.16, 0.18, 0.26) * mw * smoothstep(0.35, 0.85, grain) * stars * 0.55 * smoothstep(0.0, 0.25, e);
	}

	// ---- 极光：沿方位角展开的垂直光幕 ----
	if (aurora > 0.01 && !AT_CUBEMAP_PASS) {
		float az = atan(d.x, d.z);
		float t = TIME * 0.038;
		// 光幕的"上边界"是一条起伏的曲线：极光不是一片雾，是一片被风吹皱的帘子
		float fold = 0.0;
		for (int i = 0; i < 4; i++) {
			float fi = float(i);
			float w = az * (2.2 + fi * 1.35) + t * (0.8 + fi * 0.35) + fi * 5.7;
			fold += fbm(vec2(w, fi * 3.3 + t * 0.5), 3) * (1.0 - fi * 0.17);
		}
		fold /= 2.9;

		// ---- 光柱（ray）的独立高度 ----
		// 极光最要命的假，是每一根光柱一样高、一样平，读成一排栅栏。
		// 真实的光柱是一束束独立的：有的长、有的短，下缘也参差不齐。
		// 所以按方位切成一列列的"柱"，每根柱用哈希取自己的下缘与高度。
		float ray_warp = az * 15.0 + fbm(vec2(az * 3.4 + t * 0.6, 1.7), 2) * 2.6;
		float col_id = floor(ray_warp);
		float col_f = fract(ray_warp);
		// 每根柱的下缘高度与总高（0..1）
		float h1 = h21(vec2(col_id, 3.7));
		float h2 = h21(vec2(col_id, 9.2));
		float col_bot = 0.040 + 0.130 * h1;                // 帘脚参差
		float col_top = 0.26 + 0.52 * h2;                  // 帘顶参差
		// 单根柱内部沿方位渐变，避免出现硬边
		float col_fade = smoothstep(0.0, 0.30, col_f) * (1.0 - smoothstep(0.55, 1.0, col_f));
		// 高度窗：每根柱自己的上下边界
		float band = smoothstep(col_bot - 0.02, col_bot + 0.075, e)
			* (1.0 - smoothstep(col_top - 0.20, col_top + 0.06, e));
		// 帘脚亮带：极光下缘最亮，向上迅速衰减
		float hem = smoothstep(col_bot - 0.01, col_bot + 0.05, e)
			* (1.0 - smoothstep(col_bot + 0.05, col_bot + 0.30, e));
		// 柱内的细密竖纹
		float fine = vn(vec2(az * 210.0 + t * 1.2, e * 1.1));
		float rays = (0.30 + 0.70 * col_fade) * (0.55 + 0.60 * fine);
		// 明暗成组：几根亮柱聚在一起，中间夹着弱柱，也有整段暗下去的地方
		float group = vn(vec2(az * 5.5 + t * 0.35, 4.1)) * 0.65
			+ vn(vec2(az * 13.0 - t * 0.22, 8.3)) * 0.35;
		group = smoothstep(0.28, 0.78, group);
		rays *= 0.18 + 1.25 * group;

		float curtain = band * rays * (0.40 + 0.60 * hem) * (0.48 + 0.52 * fold);

		// 方位上的「分段」：极光不是一整圈，是几道弧。没有这一步，天空读成一堵绿墙。
		float arc = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float c0 = fi * 2.1 + 0.7 + t * 0.12;            // 每段弧的中心方位
			float dd = abs(atan(sin(az - c0), cos(az - c0)));  // 环绕角差
			float wdt = 0.66 + 0.38 * fbm(vec2(fi * 7.3 + t * 0.2, 1.7), 3);
			arc += smoothstep(wdt, wdt * 0.22, dd) * (0.55 + 0.45 * fbm(vec2(fi * 3.1, 2.2), 2));
		}
		curtain *= clamp(arc, 0.0, 1.0);

		vec3 acol = mix(vec3(0.06, 0.92, 0.46), vec3(0.20, 0.66, 0.62),
			smoothstep(col_bot, col_bot + 0.22, e));
		acol = mix(acol, vec3(0.34, 0.30, 0.95), smoothstep(0.26, 0.66, e));
		acol = mix(acol, vec3(0.86, 0.32, 0.56),
			smoothstep(0.60, 0.92, fbm(vec2(az * 5.0 + t * 0.6, e * 3.4), 3)) * 0.45);
		col += acol * curtain * aurora * 0.30;
	}

	// ---- 高层云：层积云 / 卷层云 ----
	// 空荡荡的一条纯渐变天空是最容易被识破的"渲染图"。
	// 但云不能只是"加一点白"：云本身要有厚度、有受光面与背光面、
	// 有被高空风切变抻出来的丝缕，天才有"空气层"的感觉。
	if (clouds > 0.01 && !AT_CUBEMAP_PASS) {
		// 关键：把视线投到一个高空平面上，而不是用 (方位角, 仰角) 采样噪声。
		// 方位角在接近天顶时会急骤变化，云会被拉成从头顶放射的竖条——
		// 这是最容易露馅的地方。平面投影的云会自然地在地平线收拢、
		// 在天顶铺开，透视关系天然正确。
		float ch = max(d.y, 0.045);
		// 平面投影的尺度要算准：平面上半径 = 1/tan(仰角)，
		// 25° 处只有 2.1，5° 处是 11.4。尺度给得太小，整片可见天空
		// 只覆盖半个噪声格子——云就被拉成一层平滑渐变，永远读不出团块。
		// 尺度实测：1.15 时 10°~25° 主视区只覆盖 2~5 个噪声格，
		// 于是整片天只有两三团云——团越大越像卡通棉花，因为真实的高云
		// 在同样视角里能数出十几片。放大到 2.35 让云"变小变多"，
		// 再把权重从积云那一层挪去丝缕层，天就从"夏日下午"变成"极地卷层"。
		vec2 cp = (d.xz / ch) * 2.35;
		// —— 抗走样：按像素足迹压掉高八度 ——
		// 平面投影在接近地平线时坐标急剧发散（ch 下限 0.045 时 cp≈52），
		// 一个像素会横跨 1~3 个噪声格。高八度（erosion 4.6×、fray 12.0×）
		// 因此在整片天空上混叠成一层规则的斜向点阵——放大到原分辨率看，
		// 天空像被铺了一张网，云反而成了网底下的灰雾。
		// 这不是"云画得不好"，是采样率不够：必须按足迹把高八度衰减掉，
		// 让远处只剩低频的大形，近处才长出絮边。
		float cpf = max(fwidth(cp.x), fwidth(cp.y));
		float hi_f  = 1.0 - smoothstep(0.30, 1.45, cpf);   // erosion / fray
		float mid_f = 1.0 - smoothstep(0.10, 0.62, cpf);   // n2 / streak
		// 域扭曲：不加这一层，云的轮廓是一团各向同性的胖棉花，
		// 一眼就看出是噪声阈值。把采样点按低频噪声整体推开一点，
		// 形状立刻带上被高空气流推挤的走向，边界也不再是圆的。
		vec2 warp = vec2(fbm(cp * 0.40 + 5.3, 3), fbm(cp * 0.40 + 19.7, 3)) - 0.5;
		vec2 cq = cp + warp * 0.70;
		// 三层：大团的积云体量、中团的碎块、被切变拉长的丝缕
		float n = fbm(cq * 0.60 + vec2(TIME * 0.0035, TIME * 0.0012), 4);
		float n2 = fbm(cq * 1.65 + vec2(-TIME * 0.006, TIME * 0.0028) + 3.1, 4);
		// 高八度在远处没有可靠采样，直接按足迹混回均值 0.5，
		// 不能留给它自己振荡——那正是走样的来源。
		n2 = mix(0.5, n2, mid_f);
		// 丝缕层必须斜着走。原先它是沿 cp.y 拉的，投影到画面上正好是
		// 一条条水平的平行刷痕，整片天空读成被抹布擦过。转 22° 之后
		// 它读作被高空风切变推斜的卷云，而不是印刷网屏。
		vec2 sr = vec2(cq.x * 0.927 + cq.y * 0.375, -cq.x * 0.375 + cq.y * 0.927);
		float streak = fbm(vec2(sr.x * 0.62, sr.y * 1.45) + vec2(TIME * 0.0026, 0.0), 3);
		streak = mix(0.5, streak, mid_f);
		// 边缘侵蚀：没有这一层，云的边界是一条干净的概率等值线，
		// 像用剪刀剪出来的；加上它才有絮状的、被打散的外轮廓。
		// 但这两层是最高频的，必须在远处完全退掉，否则整片天是网纹。
		float erosion = (fbm(cq * 4.6 + 17.0, 3) - 0.5) * hi_f;
		float fray = (fbm(cq * 12.0 + 41.0, 2) - 0.5) * hi_f;
		// 关键：fbm 的输出集中在 0.5 附近，直接加权求和会得到一张"平均灰"，
		// 阈值一卡就什么都不剩（这就是之前天空有云却看不见云的原因）。
		// 必须先减去均值、按权重拉开对比度，云的团块才有明确的黑白。
		// 权重配比就是云的"体量语言"。旧配比 2.60/1.10/0.34 是积云的语言：
		// 大团块为主，丝缕只是点缀 —— 那是夏天的下午。
		// 极地冬天的天几乎全是**卷层云与高层云**：没有垂直发展，
		// 只剩被高空风切变拉成一片一片的薄纱。所以把主导权交给丝缕层，
		// 团块层退到只负责给丝缕"打结"的地方加一点厚度。
		// 丝缕层的权重也不能超过团块太多：那一层是横向拉长的，
		// 权重一大，整片天就变成一道一道平行的刷痕（另一种一眼假）。
		float dens = (n - 0.5) * 1.30 + (n2 - 0.5) * 1.05 + (streak - 0.5) * 1.15 + 0.5;
		dens += erosion * 0.26 + fray * 0.07;

		// clouds 控制的是"天有多少被云占着"，不是"云有多厚"。
		// 把覆盖度做成阈值平移，云的边缘才会随天气整体进退，
		// 而不是整片天空一起变浓变淡（那种效果一眼假）。
		float thr = mix(0.700, 0.345, clamp(clouds, 0.0, 1.0));
		// 过渡带要宽：过渡带一窄，云的边界就是一圈刀口，
		// 远看是一堆撕碎的纸片。真实的云边是一段几十米的渐隐。
		// 宽度随云量变化：云少的时候（晴天几朵）边要更柔，
		// 否则那几朵云就是硬边的白剪纸，最扎眼。
		// soft 还要跟 thr 成比例地收：thr 移到 0.70 之后，原来的 0.26
		// 会让遮罩从 0.44 就开始起雾——fbm 输出均值就在 0.5 附近，
		// 于是"晴天"仍然是满天的霾。过渡带必须窄到只吃边缘：
		// 0.155 在 thr=0.70 时是 0.545 起雾，只影响最外侧那一圈絮。
		float soft = mix(0.155, 0.095, clamp(clouds, 0.0, 1.0));
		float mask = smoothstep(thr - soft, thr + soft * 2.2, dens);
		// 靠近地平线时云层被大气压扁、变淡；天顶不铺满（留出深色的顶）。
		// 下限必须很小：云正好是"贴着地平线排成一列"的时候最能读出纵深，
		// 之前用 0.02~0.20 把这一段整条砍掉，天空就只剩一片空蓝。
		mask *= smoothstep(0.008, 0.070, d.y) * (1.0 - smoothstep(0.70, 1.0, d.y) * 0.50);

		// 云的"第二种形态"：靠近地平线的那一层必须是**压扁的层云**，
		// 不是把高空的积云原样压小。投影坐标在低仰角处发散，
		// 同一团噪声会被拉成细长的条带——这本身是对的，
		// 但如果只让它变淡，画面就会是"一堆棉花球飘在半空"。
		// 这里单独叠一层沿水平方向拉长的卷层带，给天空一条明确的地平线层理。
		float band_y = exp(-pow((d.y - 0.085) * 7.0, 2.0));
		vec2 bp = vec2(atan(d.x, d.z) * 2.1, (d.y - 0.085) * 26.0);
		float band_n = fbm(bp + vec2(TIME * 0.004, 0.0), 3);
		float band_m = smoothstep(0.44, 0.72, band_n) * band_y;
		mask = clamp(mask + band_m * 0.55, 0.0, 1.0);

		// 云是有厚度的：薄的地方透出天光、发亮；厚的地方沉在自己的影子里。
		float thick = smoothstep(thr, thr + 0.42, dens);
		// 自阴影：把同一团云沿太阳方向偏移一点再采一次密度，
		// 邻居比这里更厚 → 这里就在别人的影子里。这是让"平面噪声"
		// 突然读成"有体积的云"最便宜的一招，没有它云永远是纸片。
		float n_sh = fbm((cq + normalize(sun_dir.xz + vec2(0.0001, 0.0)) * 0.16) * 0.60
			+ vec2(TIME * 0.0035, TIME * 0.0012), 4);
		// 稍微厚一点就吃别人的影，但永远不会全黑：云的次表面散射
		// 会把整团都填亮，这是云看起来"透光"而不是"石膏"的原因。
		float selfshadow = clamp((n_sh - n) * 3.4 + 0.46, 0.0, 1.0);
		// 太阳方位决定云缘的暖边：朝阳的一侧泛金，背光一侧发灰蓝
		float sun_lit = pow(max(dot(d, sun_dir), 0.0), 2.2);
		// 受光面的云必须比天空亮出一档、背光面必须暗出一档，
		// 否则云就只是"把天空再涂一遍同样的颜色"，画面上什么都看不见。
		// 但"暗"只允许出现在最厚的核心里：整片云都压暗，
		// 读出来就是一块撕碎的脏纸，而不是云。
		// 亮度标定（实测）：旧的 clit 是接近纯白的 mix(1.00,0.965,0.915)，
		// 叠上 1.04 的"云在发光"项之后，薄云处直接顶到 1.0 附近。
		// 而同期天空 p50 只有 0.44 → 云/天亮度比 **1.98**。
		// 真实冬日的层积云，云顶与天空的亮度比只有 1.2~1.4：
		// 超过 1.6 就不是"云在天上"，而是"白纸片贴在蓝板上"，
		// 一眼就是卡通。这里把云顶压到 0.74 一档，云底压到 0.5 一档，
		// 让云靠**形状和边缘**读出来，而不是靠亮度硬顶。
		//
		// —— 颜色必须从**天空自身**派生，绝不能写死 ——
		// 上面所有 uniform 都带 source_color，进 shader 时已经是线性值：
		// 8:00 的天顶 (0.125,0.180,0.268) 是 sRGB，线性只有 (0.014,0.027,0.058)。
		// 而写死的 vec3(0.760,0.752,0.735) 是 0.53 的线性亮度——
		// 比它脚下的天空亮 30 倍。旧代码把云从 1.00 压到 0.76 只是
		// 在这个已经错掉的比例上抠细节，成图必然是一片白剪纸贴在藏青板上。
		// 正确做法：云是受天光照亮的漫射体，反射率 ~0.6，
		// 所以它的颜色只能是"当前天空色 × 一个接近 1 的系数"。
		// 实测这份成图天空 p50=0.44、云 p99=0.88（1.98:1），
		// 而真实冬日层积云云顶/天空只有 1.2~1.4 —— 那就是"卡通"的量化定义。
		vec3 base_sky = col;
		float sky_lum = max(dot(base_sky, vec3(0.2126, 0.7152, 0.0722)), 0.0005);
		// 云底：略暗于天空、偏中性。云底朝下，只拿到地面反照与散射光。
		vec3 cbase = mix(base_sky * 0.98, horizon_color * 0.92, 0.34);
		// 云顶：受太阳直射。sun_color 只给很小权重，
		// 因为它在线性空间接近 1.0，权重一大就把云烧成纯白。
		vec3 clit = base_sky * 1.26 + sun_color * sky_lum * 0.85;
		// 顶部受光：云的上面朝着太阳，底部朝着地面。
		// 这个"上下"不是几何上的上下，而是用视线仰角近似——
		// 天顶方向的云是俯视看到的背面，地平线方向的云是仰视看到的底面。
		float topness = smoothstep(0.10, 0.72, d.y);
		clit *= 0.94 + 0.22 * topness;
		vec3 ccol = mix(clit, cbase * 0.92, thick * 0.70);
		// 自阴影压在云的基部，云顶保持亮——"顶亮底暗"是云的基本体量语言
		ccol = mix(ccol, cbase * 0.74, selfshadow * 0.46 * (1.0 - topness * 0.35));
		// 边缘的银边：逆光时云缘会亮成一条线，这是电影里最常见的天空层次。
		// 权重同样只能按比例给：这里乘的是云自身的亮度，不是绝对白。
		float rim = mask * (1.0 - mask) * 4.0;
		ccol += clit * rim * (0.10 + 0.34 * sun_lit);
		// 云顶的一层薄光：只有薄处才有，制造"云在发光"的通透感。
		ccol = mix(ccol, clit * 1.05, (1.0 - thick) * 0.22);
		// 贴近地平线的云会被大气压淡（同时也是抗走样：平面投影在 d.y 很小时
		// 坐标急剧发散，硬画出来只会得到一片闪烁）。注意这里只压到"半透明"，
		// 不能压成地平线色，否则地平线上那排最能读出纵深的云会整条消失。
		float hz_fade = 1.0 - smoothstep(0.008, 0.150, d.y);
		ccol = mix(ccol, horizon_color * (1.05 - night * 0.50), hz_fade * 0.55);
		// 夜里的云只剩一点被月光照亮的灰蓝，不能比夜空亮
		ccol *= mix(1.0, 0.16, night);
		// 云与天空的混合比：晴天也留一点，只靠 mask 控制形状
		col = mix(col, ccol, mask * 0.86);
	}

	COLOR = col;
}
"""

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var fill: DirectionalLight3D
var env: WorldEnvironment
var aurora_mesh: MeshInstance3D
var snow: GPUParticles3D
var cam: Camera3D

const RIDGE_SHADER := preload("res://assets/shaders/ridge.gdshader")

var _env: Environment
var _sky_mat: ShaderMaterial
var _near: GPUParticles3D
var _far: GPUParticles3D
var _drift: GPUParticles3D
var _ridges: Array = []      # 远景山脊（三层，跟随相机）
var _ridge_scale := 1.0
var _t := 0.0
var _wind_t := 0.0
var _wind_goal := 0.15
var _cur := {}          # 当前插值后的调色板
var _sun_dir := Vector3(0, 0.4, 0.9)
var _moon_dir := Vector3(0, 0.5, -0.9)


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# 分割比例必须把最多预算给最近的一档：玩家几乎全部注意力都在 30m 内。
	# 原先第一档只到 14m，墙角的接触阴影正好落在第一、二档的接缝上，
	# 于是墙与地面交接处出现一道阶梯状的硬边——那是"看得到像素"的阴影。
	sun.directional_shadow_split_1 = 0.11
	sun.directional_shadow_split_2 = 0.30
	sun.directional_shadow_split_3 = 0.62
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 180.0
	# bias 收小、normal_bias 加大：前者消除漂移（peter-panning），
	# 后者抑制自阴影痤疮。原先 0.035 的 bias 会让细小构件（窗套、
	# 落水管、钢筋）的阴影从根部脱开，整个立面读起来像贴纸。
	sun.shadow_bias = 0.018
	# normal_bias 2.4 是错的，它把阴影采样点沿表面法线推出去 2.4 米。
	# 地面是水平面（法线朝上），采样点被抬到 2.4 米高——高于绝大多数
	# 建筑投影的高度，于是**整座城没有一条落地的影子**，只有物件自己的
	# 一点接触阴影。这就是"明暗层次被压平"的最后一个、也是最硬的成因：
	# 太阳一直在那里，但它的阴影从来没画到地面上。
	# Godot 的 normal_bias 单位与 bias 同为"阴影贴图深度"，与米不完全等价，
	# 但 2.4 这个量级在任何方向上都是不合理的。收到 0.55：
	# 仍足以压掉雪面的自阴影痤疮，又不会把投影推离地面。
	#
	# 但 0.55 仍不够：地形是一整块 560m 的网格，4 档分割铺到 180m，
	# 最远一档一个阴影纹素在世界上跨十几厘米，雪面几乎是斜对着光，
	# 于是整片雪原浮出一层约 45° 的细密斜纹——放大看像编织袋。
	# 关掉阴影做对照，同一块地面立刻干净，说明它是自阴影痤疮而不是噪声。
	# 1.15 是"雪面斜光下的痤疮"与"投影不离地"之间的实测折中：
	# 抬 1.15m 时建筑投影下沿仍在墙脚两米内落地。
	sun.shadow_normal_bias = 1.15
	sun.light_volumetric_fog_energy = 1.6
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 120.0
	moon.light_volumetric_fog_energy = 0.5
	add_child(moon)

	# 雪地反弹光（fill / bounce card）
	# 现实里雪面反射率接近 0.85，等于在整片大地上铺了一张巨大的反光板：
	# 背光的墙面在雪原上绝不是黑的，它被脚下的雪照亮。
	# 少了这盏灯，逆光/侧光下的建筑会塌成纯黑剪影——测出来暗面只有 0.12，
	# 那不是"暗"，那是"没有信息"。
	# 不投影、不参与镜面，只是一个很便宜的补光方向。
	fill = DirectionalLight3D.new()
	fill.name = "BounceFill"
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	fill.light_volumetric_fog_energy = 0.0
	fill.light_energy = 0.0
	add_child(fill)

	env = WorldEnvironment.new()
	env.name = "WorldEnvironment"
	add_child(env)

	# 兼容保留：极光改由天空着色器绘制，此节点不再参与渲染
	aurora_mesh = MeshInstance3D.new()
	aurora_mesh.name = "Aurora"
	aurora_mesh.visible = false
	add_child(aurora_mesh)

	_build_ridges()

	snow = GPUParticles3D.new()
	snow.name = "Snow"
	add_child(snow)

	_build_sky()
	_build_snow()
	_update_atmosphere(0.0)


# ------------------------------------------------------------------ 天空 / 环境
func _build_sky() -> void:
	_env = Environment.new()
	env.environment = _env

	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	_sky_mat.shader = sh
	sky.sky_material = _sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	_env.sky = sky

	_env.background_mode = Environment.BG_SKY
	# 环境光必须完全可控，所以不用"取天空的辐照"这一档。
	# 用 AMBIENT_SOURCE_SKY + sky_contribution=1.0 时，阴影里的补光
	# 等于头顶那片晴天的蓝光辐照：所有背光面都被抬到同一个亮度，
	# 阴影不暗，只是变蓝。实测背光屋顶 L=0.389、R-B=-0.269——
	# 既不黑也不白，是一块发蓝的灰。这就是"明暗层次被压平"的来历。
	# 而且那一档下 ambient_light_color 被完全忽略，
	# 下面为夜里精心调的月光蓝一直是死代码。
	# 改成显式颜色：补光的量与色都留在自己手里。
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	# 白点从 6.0 收到 2.1。
	# 6.0 意味着只有亮度达到 6.0 的像素才算"纯白"，于是 0~1.5 这段
	# ——雪面正好全部落在这里——被压进色调曲线的线性前段：
	# 亮部没有压缩、没有滚降，雪地就是一片贴到 0.95 的灰白，
	# 而凡是接近 0.95 的像素在 ACES 里都会被"去色"趋向中性白，
	# 暖色的直射光根本留不住色相（实测最亮 2% 的 R-B = +0.01）。
	# 2.1 让雪面落在中高调，高光有真正的滚降，暖光才有地方显色。
	_env.tonemap_white = 2.1

	# 泛光：让灯、火光、日轮有真实的溢出
	_env.glow_enabled = true
	_env.glow_intensity = 0.55
	_env.glow_strength = 1.0
	_env.glow_bloom = 0.045
	_env.glow_hdr_threshold = 1.05
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.set("glow_levels/2", 0.0)
	_env.set("glow_levels/3", 0.55)
	_env.set("glow_levels/4", 0.70)
	_env.set("glow_levels/5", 0.55)
	_env.set("glow_levels/6", 0.30)

	# 环境光遮蔽：雪地上的接触阴影，直接决定"扎实感"
	_env.ssao_enabled = true
	_env.ssao_radius = 1.6
	_env.ssao_intensity = 1.55
	_env.ssao_power = 1.6
	_env.ssao_detail = 0.6
	_env.ssao_light_affect = 0.25
	_env.ssao_horizon = 0.06
	_env.ssao_sharpness = 0.98

	# 雾：深度分层 + 贴地雾，近处通透、远处乳白
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_depth_begin = 6.0
	_env.fog_depth_end = 240.0
	_env.fog_depth_curve = 1.9
	_env.fog_density = 1.0
	_env.fog_light_energy = 1.0
	_env.fog_sun_scatter = 0.32
	_env.fog_aerial_perspective = 0.55
	_env.fog_sky_affect = 0.45
	_env.fog_height = 3.2
	_env.fog_height_density = 0.42

	# 体积雾：让天光在空气里可视，暴风雪时是主要氛围
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.010
	_env.volumetric_fog_albedo = Color(0.86, 0.90, 0.97)
	_env.volumetric_fog_anisotropy = 0.45
	_env.volumetric_fog_length = 72.0
	_env.volumetric_fog_detail_spread = 1.4
	_env.volumetric_fog_ambient_inject = 0.35
	_env.volumetric_fog_sky_affect = 0.25

	# 调色：略降饱和、抬对比，压向冷调
	_env.adjustment_enabled = true
	_env.adjustment_brightness = 1.0
	_env.adjustment_contrast = 1.06
	_env.adjustment_saturation = 0.94

	# 镜头属性：轻微远景虚化 + 自动曝光收敛
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 85.0
	ca.dof_blur_far_transition = 70.0
	ca.dof_blur_amount = 0.055
	ca.auto_exposure_enabled = true
	ca.auto_exposure_scale = 0.42
	ca.auto_exposure_speed = 0.35
	ca.auto_exposure_min_sensitivity = 20.0
	ca.auto_exposure_max_sensitivity = 420.0
	env.camera_attributes = ca


# ------------------------------------------------------------------ 风雪
func _make_flake(size: float, soft: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float softness = 0.55;
uniform float alpha = 0.85;
uniform vec3 tint : source_color = vec3(0.95, 0.97, 1.0);
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float a = smoothstep(1.0, 1.0 - softness, r);
	ALBEDO = tint;
	ALPHA = a * alpha;
}
"""
	m.shader = sh
	m.set_shader_parameter("softness", soft)
	q.material = m
	return q


func _build_snow() -> void:
	# 近景大雪片
	_near = _make_layer(0.052, 2.2, 3.9, 26.0, 0.30)
	_near.name = "SnowNear"
	# 中景雪片
	_far = _make_layer(0.030, 1.7, 3.0, 40.0, 0.22)
	_far.name = "SnowFar"
	# 贴地吹雪（横向流动的雪雾）
	_drift = _make_layer(0.42, 0.7, 1.6, 18.0, 0.10, true)
	_drift.name = "SnowDrift"
	_drift.position = Vector3(0, -6.0, 0)

	# 主雪引用近景层（保持旧代码/外部只读 snow 的语义）
	snow = _near


func _make_layer(size: float, vmin: float, vmax: float, box: float, alpha: float, flat := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(box, box * 0.55 if not flat else 9.0, box)
	mat.direction = Vector3(-0.22, -1.0, -0.12)
	mat.spread = 6.0
	mat.initial_velocity_min = vmin
	mat.initial_velocity_max = vmax
	mat.gravity = Vector3(0.0, -0.9, 0.0)
	mat.scale_min = 0.55
	mat.scale_max = 1.5
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.55
	mat.turbulence_noise_scale = 2.2
	mat.turbulence_influence_min = 0.02
	mat.turbulence_influence_max = 0.10
	mat.particle_flag_rotate_y = true
	p.process_material = mat
	p.draw_pass_1 = _make_flake(size, 0.6 if not flat else 0.95)
	var sm := p.draw_pass_1.material as ShaderMaterial
	sm.set_shader_parameter("alpha", alpha)
	p.amount = 600
	p.lifetime = 6.0
	p.visibility_aabb = AABB(Vector3(-90, -40, -90), Vector3(180, 110, 180))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


# ------------------------------------------------------------------ 远景山脊
# 三层同心山脊，永远跟着相机走 —— 相当于"有体积的天空盒下半部"。
# 不投影、不参与光照、不吃雾（自己按层混雾色），因此开销可以忽略。
func _build_ridges() -> void:
	# 三层同心山脊：内圈（近）最清晰、外圈（远）最沉进雾里。
	# 这个顺序不能反——曾经把 mix 写反过，结果最近的山最淡、最远的山最实，
	# 远景整个读成一堆浮在天空里的白云。
	var cfg := [
		{"r": 700.0, "h": 150.0, "mix": 0.10, "seed": 3.1, "name": "RidgeNear"},
		{"r": 900.0, "h": 205.0, "mix": 0.26, "seed": 11.7, "name": "RidgeMid"},
		{"r": 1120.0, "h": 272.0, "mix": 0.44, "seed": 27.3, "name": "RidgeFar"},
	]
	for c in cfg:
		var mi := MeshInstance3D.new()
		mi.name = String(c["name"])
		mi.mesh = _ridge_mesh(float(c["r"]), float(c["h"]), float(c["seed"]))
		var m := ShaderMaterial.new()
		m.shader = RIDGE_SHADER
		m.set_shader_parameter("layer_mix", float(c["mix"]))
		m.set_shader_parameter("height_scale", float(c["h"]))
		m.set_shader_parameter("seed_v", float(c["seed"]))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4096.0
		add_child(mi)
		_ridges.append(mi)


## 生成一圈"山峰剪影"：外轮廓在半径上抖动、顶边按噪声起伏
## 关键：不能做成一面直上直下的墙。用若干圈"往里收"的环带把山体做成
## 有坡度的山面——峰越高、收得越多，剪影才有立面可读。
func _ridge_mesh(radius: float, max_h: float, seed_v: float) -> ArrayMesh:
	const SEG := 300
	const RINGS := 7
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()

	# 山脊线：用「尖齿」叠加，而不是平滑正弦——平滑的顶边读起来像云
	var top := PackedFloat32Array()
	var rad := PackedFloat32Array()
	for i in range(SEG + 1):
		var a := float(i) / float(SEG) * TAU
		# 三角波（|sin| 的尖点）叠四个频率：主峰 + 次峰 + 碎齿 + 碎屑
		var c1: float = 1.0 - absf(sin(a * 2.0 + seed_v))
		var c2: float = 1.0 - absf(sin(a * 5.0 - seed_v * 1.7))
		var c3: float = 1.0 - absf(sin(a * 11.0 + seed_v * 2.9))
		var c4: float = 1.0 - absf(sin(a * 23.0 - seed_v * 4.3))
		var t: float = c1 * 0.50 + c2 * 0.27 + c3 * 0.15 + c4 * 0.08
		# 主峰再锐化一次，形成"尖顶—陡壁—缓脚"的山形
		var peak: float = clampf(pow(clampf(t, 0.0, 1.0), 1.6) * 1.55, 0.0, 1.0)
		# 「大尺度起伏」：整条山脊要有高低错落，而不是一根等高的锯齿带。
		var macro: float = 0.34 + 0.66 * (0.5 + 0.5 * sin(a * 1.0 + seed_v * 0.7)) * (0.62 + 0.38 * (0.5 + 0.5 * sin(a * 3.0 - seed_v * 1.1)))
		# 少数几处"主峰"再拔高一截，形成画面的视觉锚点
		var spire: float = 1.0 + 0.55 * pow(maxf(0.0, sin(a * 2.0 + seed_v * 2.2)), 6.0)
		# 峰高的个体差异：没有这一层，等高锯齿会读成一把梳子。
		# 用两个不可通约的低频调制，让"这座高、旁边矮"的节奏不重复。
		var vary: float = 0.52 + 0.48 * (0.5 + 0.5 * sin(a * 7.0 + seed_v * 3.1)) * (0.55 + 0.45 * (0.5 + 0.5 * sin(a * 13.0 - seed_v * 5.7)))
		# 峰高公式里的"底"必须很小：原先写 0.18，等于整条山脊任何角度
		# 都不会低于 18% 峰高——三层山脊各有一条这样的水平底线，
		# 叠起来就是一条横贯画面的深色带，而带子上方那些"峰"因为
		# 只比底线高几个像素，完全读不出形状。
		# 真实山脊线是"几座峰 + 很深的垭口"，谷要能一直掉到接近地平线。
		top.append(max_h * (0.055 + 0.945 * peak * macro) * spire * vary)
		rad.append(radius * (1.0 + 0.075 * (c2 - 0.5) + 0.030 * sin(a * 7.0 + seed_v * 3.3)))

	# 逐角度、逐环带构建山面
	for j in range(RINGS):
		var f := float(j) / float(RINGS - 1)
		# 高度按幂次分配：底部环带密、顶部稀，山脚才有"缓坡"的体积
		var fy: float = pow(f, 1.18)
		for i in range(SEG + 1):
			var a := float(i) / float(SEG) * TAU
			var y: float = lerpf(-150.0, top[i], fy)
			# 峰顶朝外倾：越往上半径越大 → 从谷底往上看是"迎面立起来"的山坡
			var lean: float = 1.0 + 0.085 * fy * fy + 0.045 * fy
			var rr: float = rad[i] * lean
			verts.append(Vector3(cos(a) * rr, y, sin(a) * rr))
			norms.append(Vector3(-cos(a), 0.25 + 0.35 * fy, -sin(a)).normalized())

	for j in range(RINGS - 1):
		for i in range(SEG):
			var i0: int = j * (SEG + 1) + i
			var i1: int = i0 + 1
			var i2: int = i0 + (SEG + 1)
			var i3: int = i2 + 1
			# 法线朝内（相机在圆心），绕序要保证正面朝里
			idx.append(i0); idx.append(i2); idx.append(i1)
			idx.append(i1); idx.append(i2); idx.append(i3)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


func _update_ridges() -> void:
	if cam == null:
		return
	for mi in _ridges:
		mi.global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)


# ------------------------------------------------------------------ 每帧
func _process(delta: float) -> void:
	if cam == null:
		cam = get_viewport().get_camera_3d()
		if cam == null:
			return
	_t += delta
	_update_sun(delta)
	_update_atmosphere(delta)
	_update_weather_visual(delta)
	_update_ridges()
	if _near:
		_near.global_position = cam.global_position + Vector3(0, 13.0, 0)
	if _far:
		_far.global_position = cam.global_position + Vector3(0, 15.0, 0)
	if _drift:
		_drift.global_position = cam.global_position + Vector3(0, -1.2, 0)
		_drift.global_rotation = Vector3(0, deg_to_rad(-22.0), 0)


# ------------------------------------------------------------------ 日月

## 直射光增益。
## 1.50 时实测地面雪 L=0.775（参考照片的雪地是 0.37~0.51），
## 整片近景被推进高光肩部，风纹和雪坎全部压平——"雪面很灰/很白"的
## 另一半原因其实在这里，不只是环境光。
func _sun_gain() -> float:
	return 1.50


func _update_sun(delta: float) -> void:
	var h := Game.hour
	# 太阳轨迹：6 点东升、18 点西落。
	# 最高点从 52° 压到 34°：这不只是"更冷"，而是**画面语言**的差别。
	# 52° 的正午光几乎是顶光，影子短到脚边，建筑立面全是均匀的灰，
	# 整个场景读起来像一张没有时间信息的渲染图。
	# 34° 意味着全天都是斜射：影子长度是物体高度的 1.5 倍以上，
	# 立面上有明确的受光面/背光面，雪原上有一道道被拉长的雪坎阴影——
	# 这才是"极地冬天的太阳"，也才是电影摄影真正在用光的角度。
	var ang := (h - 6.0) / 12.0 * PI
	var elev := sin(ang)
	var azim := cos(ang)
	var elev_deg := elev * 34.0
	var azim_deg := 96.0 * azim

	var er := deg_to_rad(elev_deg)
	var ar := deg_to_rad(azim_deg)
	_sun_dir = Vector3(cos(er) * sin(ar), sin(er), cos(er) * cos(ar)).normalized()
	_moon_dir = -_sun_dir

	var daylight := clampf(elev, 0.0, 1.0)
	# 太阳在地平线附近时仍有一点点直射（金色时刻）
	var sun_up := smoothstep(-0.06, 0.10, elev)
	var low_sun := 1.0 - smoothstep(0.0, 0.62, elev)   # 1=贴地，0=高悬
	var warm := Color(1.0, 0.52, 0.26)
	# 冬天低角度的太阳，即使"正午"也不该是纯白。
	# 原先 pale = (1.0, 0.97, 0.92)、且 low_sun 在 0.42 以上就归零，
	# 于是 9 点以后整片场景的光全是中性白，天空冷、地面冷、光也冷，
	# 画面里没有一个暖色落点——这正是一眼看过去"平"和"假"的原因。
	# 太阳高度角不到 34°，光穿过的大气层厚度一直很大：
	# 现实中这种高度角的直射光永远是偏金黄的。
	# 冬天的低角度太阳确实偏暖，但暖到 (1.0, 0.885, 0.775) 就是另一回事了：
	# 那是 3800K 左右的炉火色。雪的反照率接近中性，被这种光一照，
	# 整片雪原变成米黄色的硬纸板——用户说的"雪面很灰"就是这个颜色，
	# 不是明度低，是它已经不白了。真实 27° 太阳大约 4500~5000K，
	# 色温应该只比中性白暖一点点。
	var pale := Color(1.0, 0.940, 0.878)

	sun.visible = sun_up > 0.001
	# 光源朝向：+Z 指向太阳
	sun.global_transform = Transform3D(Basis.looking_at(-_sun_dir, Vector3.UP), Vector3.ZERO)
	sun.light_color = pale.lerp(warm, low_sun * 0.95)
	# 峰值能量从 2.30 收到 2.00：雪面反照率本身就有 0.85，再叠 2.3 的直射，
	# 大片雪地被推到 1.0 之上（实测 14% 的雪面像素被削平在纯白），
	# 风蚀纹、雪丘的明暗全部被压掉——过曝不会让画面"亮"，只会让它"平"。
	# 之后再上调到 2.55：环境光被压到 0.42 倍之后，只有把太阳补回来，
	# 受光面才不会跟着一起变暗。明暗比要从 1.27:1 提到 2.5:1 左右，
	# 唯一的做法是"减补光、加直射"这一对操作，单做任何一个都只是整体变亮或变暗。
	sun.light_energy = sun_up * (0.50 + 1.50 * pow(daylight, 0.65)) * _sun_gain()
	sun.light_specular = 0.9
	# 阴影随日光变软
	sun.shadow_opacity = 0.72 + 0.24 * daylight
	sun.shadow_blur = lerpf(2.4, 1.0, daylight)

	moon.visible = Game.night_mix > 0.06
	moon.global_transform = Transform3D(Basis.looking_at(-_moon_dir, Vector3.UP), Vector3.ZERO)
	moon.light_color = Color(0.52, 0.66, 1.0)
	# 月光：夜里的主体照明，给雪地留下可读的明暗与蓝色阴影
	moon.light_energy = 0.10 + Game.night_mix * 1.55
	moon.light_specular = 0.35
	moon.shadow_opacity = 0.62

	# 雪地反弹：光从地面往上打，方向与太阳的水平方向相反、略微上扬。
	# 强度跟太阳高度走（太阳越高，雪面被照得越亮，反弹也越强），
	# 夜里则只剩月光打在雪上的一点冷色回光。
	#
	# 这里曾经是画面"平"的元凶：方向和能量都写反了。
	# 原式 fill_dir = (-sun_h*0.78 + UP*0.52)，而方向光沿 -fill_dir 传播，
	# 于是这盏"反弹光"实际是从太阳的**背面、由上往下**打过来的，
	# 能量还有太阳的 0.62 倍——等于给每一块背光面都补了一盏主光。
	# 实测把 _env 环境光直接归零，画面 p5 阴影只从 0.188 掉到 0.174，
	# 就是这个原因：真正抬亮阴影的不是环境光，是这盏假反弹。
	# 真实的雪面反弹是从地面往上的：它只能照亮物体的底面和竖直面的下缘，
	# 不该在水平面上和中光平起平坐。所以方向翻成真·上行、能量降到 0.26。
	var sun_h := Vector3(_sun_dir.x, 0.0, _sun_dir.z)
	if sun_h.length() < 0.01:
		sun_h = Vector3(0.0, 0.0, 1.0)
	sun_h = sun_h.normalized()
	# 传播方向 = -fill_dir，要让它朝上，fill_dir 就必须朝下。
	var fill_dir := (sun_h * 0.34 - Vector3.UP * 0.94).normalized()
	fill.global_transform = Transform3D(
		Basis.looking_at(-fill_dir, Vector3(-sun_h.z, 0.0, sun_h.x)), Vector3.ZERO)
	# 雪弹回来的光是被太阳染过的：偏暖一点，但比直射光灰得多
	fill.light_color = Color(0.94, 0.94, 0.96).lerp(Color(0.90, 0.88, 0.86), 0.35)
	fill.light_color = fill.light_color.lerp(Color(0.62, 0.70, 0.92), Game.night_mix)
	fill.light_energy = sun_up * 0.42 + Game.night_mix * 0.10
	fill.light_specular = 0.0
	# 补光再压一半：这盏灯的可见效果几乎全部落在"背光面"上（它由下往上打），
	# 所以它的能量直接决定阴影有多亮——阴影亮度就是明暗比的分母。
	fill.light_energy *= 0.46

	Game.night_mix = 1.0 - daylight

	# 环境温度（保持原有数值语义，勿改）
	var base := -11.0 - 13.0 * Game.night_mix
	match Game.weather:
		"snow": base -= 3.0
		"blizzard": base -= 8.0
	base -= Game.wind * 1.2
	if Game.disaster_state == "active":
		base -= Game.disaster_cold
	Game.ambient_temp = base

	# 风：随机目标 + 平滑逼近（比原来逐帧抖动更自然）
	_wind_t -= delta
	if _wind_t <= 0.0:
		_wind_t = randf_range(3.0, 7.0)
		_wind_goal = _target_wind()
	Game.wind = lerpf(Game.wind, _wind_goal, 1.0 - exp(-delta * 0.6))


func _target_wind() -> float:
	match Game.weather:
		"blizzard": return randf_range(2.2, 3.0)
		"snow": return randf_range(0.4, 1.2)
	return randf_range(0.0, 0.3)


# ------------------------------------------------------------------ 调色与大气
func _palette(h: float) -> Dictionary:
	var n := STOPS.size()
	var a: Dictionary = STOPS[n - 1]
	var b: Dictionary = STOPS[0]
	for i in range(n):
		var s: Dictionary = STOPS[i]
		var t: Dictionary = STOPS[(i + 1) % n]
		var h0: float = s["h"]
		var h1: float = t["h"] if i + 1 < n else 24.0
		if h >= h0 and h <= h1:
			a = s
			b = t
			break
	var span := maxf(0.001, float(b["h"]) - float(a["h"]))
	var k: float = clampf((h - float(a["h"])) / span, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return {
		"zen": (a["zen"] as Color).lerp(b["zen"], k),
		"hor": (a["hor"] as Color).lerp(b["hor"], k),
		"gnd": (a["gnd"] as Color).lerp(b["gnd"], k),
		"sun": (a["sun"] as Color).lerp(b["sun"], k),
		"fog": (a["fog"] as Color).lerp(b["fog"], k),
		"amb": lerpf(a["amb"], b["amb"], k),
		"den": lerpf(a["den"], b["den"], k),
		"k": k,
	}


func _update_atmosphere(delta: float) -> void:
	var p := _palette(Game.hour)
	# 真正的“暗”只由太阳高度角决定：太阳还在地平线上时，天就是亮的，
	# 绝不能让极光/星空在上午 8 点就透出来。
	var elev: float = _sun_dir.y
	var dusk: float = 1.0 - smoothstep(-0.26, 0.06, elev)          # 0=白天 1=太阳沉到地平线下
	var night: float = 1.0 - smoothstep(-0.30, -0.02, elev)        # 更严格：只有真入夜才 1
	var daylight: float = clampf(smoothstep(-0.04, 0.22, elev), 0.0, 1.0)

	# 天气对能见度与天色的影响
	var blizzard: float = 1.0 if Game.weather == "blizzard" else 0.0
	var snowfall: float = 1.0 if Game.weather == "snow" else 0.0
	var wx: float = maxf(blizzard, snowfall * 0.55)
	var w_den: float = 1.0 + blizzard * 2.6 + snowfall * 0.7

	_sky_mat.set_shader_parameter("zenith_color", (p["zen"] as Color).lerp(p["fog"], wx * 0.55))
	_sky_mat.set_shader_parameter("horizon_color", (p["hor"] as Color).lerp((p["fog"] as Color) * 1.05, wx * 0.7))
	_sky_mat.set_shader_parameter("ground_color", p["gnd"])
	_sky_mat.set_shader_parameter("sun_color", p["sun"])
	_sky_mat.set_shader_parameter("sun_energy", 1.0 - wx * 0.85)
	_sky_mat.set_shader_parameter("sun_dir", _sun_dir)
	_sky_mat.set_shader_parameter("moon_dir", _moon_dir)
	_sky_mat.set_shader_parameter("night", night)
	# 星与极光只在真正入夜后出现，且黄昏有很长的淡入
	_sky_mat.set_shader_parameter("stars", pow(night, 2.2) * (1.0 - wx * 0.92))
	_sky_mat.set_shader_parameter("aurora", pow(night, 1.7) * (1.0 - wx * 0.8))
	# 晴天的天也必须有云：一条纯渐变的天是最先露馅的地方。
	# 但云量要克制——留出足够的蓝，天才有"高"的感觉。
	_sky_mat.set_shader_parameter("clouds", clampf(0.34 + wx * 0.58, 0.0, 1.0))
	_sky_mat.set_shader_parameter("haze", clampf(0.55 * (1.0 - wx * 0.35) + dusk * 0.25, 0.0, 1.0))
	_sky_mat.set_shader_parameter("sun_disc", 1.0 - wx * 0.9)

	# 环境光：天空带来的补光必须压住，否则雪地把整幅画面抬成一片奶白
	#
	# 量化依据（tools/shots 的 A/B 实测，同一机位把 sun+fill 全部关掉再渲一张）：
	#   正常成图   L p5/p25/p50/p75/p95 = 0.220/0.356/0.485/0.596/0.821
	#   只留补光   L p5/p25/p50/p75/p95 = 0.102/0.260/0.369/0.503/0.690
	#   逐像素拆分：64% 的像素几乎不受落日影响（= 背光面），它们的均值 0.460；
	#   真正被太阳照到的只有 12%，均值 0.585 —— **受光/背光只有 1.27:1**。
	# 真实的冬日晴天，直射太阳对地面的照度是天空光的 5~8 倍，
	# 雪地上的明亮面与阴影应该是 2.5:1 以上。1.27:1 意味着
	# 太阳几乎没参与塑形，画面读起来是一张均匀打亮的平面图 ——
	# 这正是用户说的"环境光过亮把阴影冲淡、明暗层次被压平"。
	# 所以补光整体压到原来的 0.42 倍，省下来的量交给太阳（见 _update_sun）。
	var amb: float = float(p["amb"]) * (1.0 + wx * 0.28) * 0.26
	# 夜里没有太阳可借，环境光必须自己顶上：否则屋顶、墙角的转折全部塌成剪影，
	# 整座城只剩一片黑块和天上那道极光。
	amb *= lerpf(1.0, 1.45, night)
	_env.ambient_light_energy = amb
	# 补光色决定"阴影是什么颜色"，这是明暗层次之外的第二根支柱。
	# 之前它无脑跟雾色走，而雾色是一整片很蓝的深色 → 阴影拿到的全是蓝光，
	# 实测背光屋顶 R-B = -0.269（参考照片接近 0）。
	# 于是阴影既不暗也不中性，只是一块发蓝的灰：眼睛读不出"背光"，
	# 只读出"这块面颜色不对"。
	# 现在白天用近中性的冷灰——里面积雪的反照本来就是中性偏暖的，
	# 天光那点蓝被雪面反弹中和掉；蓝只留给天空自己。
	# 夜里才切到月光蓝。
	var amb_day := Color(0.815, 0.822, 0.838)
	var amb_col: Color = amb_day.lerp(Color(0.42, 0.52, 0.72), night * 0.88)
	_env.ambient_light_color = amb_col

	# 雾：冷蓝、薄、拉得很远——只做空气透视，不做“白幕”。
	# 深度雾的起雾点必须推到中景之外：雾一开始就在 26m 处起，
	# 30~150m 这段正是雪丘与长影所在的地带，被雾压成一片均匀的浅灰，
	# 关掉雾对比就能看到——起伏和影子全都存在，只是被雾抹平了。
	# 现在的分工：130m 以内基本无雾（近中景的雪面留住所有层次），
	# 130m 之外迅速堆积，让远山与地平线融进天色里。
	_env.fog_light_color = (p["fog"] as Color).lerp((p["hor"] as Color), 0.22 * (1.0 - night))
	_env.fog_light_energy = 0.80
	_env.fog_density = 1.0
	_env.fog_depth_begin = lerpf(130.0, 4.0, blizzard)
	_env.fog_depth_end = lerpf(620.0, 110.0, blizzard) * float(p["den"]) * (1.0 + snowfall * 0.05)
	# 曲线略陡：起雾点之后快速堆起来，中景不糊、远景有纵深
	_env.fog_depth_curve = lerpf(1.85, 1.10, blizzard)
	_env.fog_height = 6.5
	# 贴地雾只在暴风雪里出现。晴天给一点点也会把雪原整个抬成灰白——
	# 雪面本身已经很亮，任何近地的雾都是在雪上加霜。
	_env.fog_height_density = lerpf(0.006, 0.42, blizzard)
	_env.fog_sky_affect = lerpf(0.22, 0.80, blizzard)
	_env.fog_sun_scatter = lerpf(0.55, 0.18, blizzard)

	# 体积雾：只保留极薄一层（它会把整个画面洗白，所以白天几乎不用）
	_env.volumetric_fog_density = lerpf(0.0016, 0.021, blizzard) + snowfall * 0.0035
	_env.volumetric_fog_albedo = (p["fog"] as Color).lerp(Color(0.88, 0.92, 1.0), 0.35)
	_env.volumetric_fog_emission = (p["fog"] as Color) * 0.008 * (1.0 - night)
	_env.volumetric_fog_anisotropy = 0.62

	# 曝光：白天收光，夜里只微开；再往上抬会连天一起提亮，
	# 星星与极光的对比就被冲掉了——夜里的亮度必须由地面物体自己发，
	# 而不是靠把整幅画面推亮。
	# 白天从 0.92 收到 0.80：雪面是全场最亮的表面，实测成图里雪地均值 0.92、
	# 13.5% 的像素超过 0.90——那已经不是"亮"，是削顶。削顶的雪面会把所有
	# 细节（雪壳缝、风吹波纹、车辙）一起压成死白，然后在屏幕上读成一张纸。
	# 对照真实雪景照片（tools/ref，均值 0.66），我们要的是"亮而有余量"。
	_env.tonemap_exposure = lerpf(0.96, 1.02, dusk)

	# 调色：白天保冷、日落偏暖、夜里压饱和
	var sat: float = lerpf(0.96, 1.08, clampf((p["sun"] as Color).r - (p["sun"] as Color).b, 0.0, 1.0) * (1.0 - night))
	_env.adjustment_saturation = sat
	_env.adjustment_contrast = lerpf(1.12, 1.06, dusk)
	_env.adjustment_brightness = lerpf(0.99, 1.02, night)

	# 镜头自动曝光：关掉。它会与调色板互相追尾，是画面泛白的直接原因。
	var ca := env.camera_attributes as CameraAttributesPractical
	if ca:
		ca.auto_exposure_enabled = false

	# 全局量：窗口残光 / 地面冰晶等所有 surface shader 共用，一次写入全场生效
	RenderingServer.global_shader_parameter_set("g_night", night)
	RenderingServer.global_shader_parameter_set("g_sun_dir", _sun_dir)
	RenderingServer.global_shader_parameter_set("g_snow_cover", lerpf(1.0, 1.35, wx))

	# 远景山脊：用雾色做空气透视，越远越沉进雾里。
	# 注意岩体色不能直接从地面色推——地面色在白天本来就深，
	# 乘完系数之后山会变成一片比天空还暗的糊块，然后整座山只剩
	# 雪帽是亮的，读成一排白色的软糖。岩体要取"雾色的暗调"，
	# 这样它永远比天空沉一档，又不会黑成剪影。
	var ridge_haze: Color = (p["fog"] as Color).lerp(p["hor"] as Color, lerpf(0.20, 0.72, blizzard))
	var ridge_rock: Color = (p["fog"] as Color).lerp(Color(0.085, 0.105, 0.160), 0.74)
	ridge_rock = ridge_rock.lerp(Color(0.030, 0.040, 0.070), night * 0.55)
	for mi in _ridges:
		var m := mi.material_override as ShaderMaterial
		if m == null:
			continue
		m.set_shader_parameter("haze_color", ridge_haze)
		m.set_shader_parameter("rock_color", ridge_rock)
		m.set_shader_parameter("snow_color", Color(0.815, 0.860, 0.945) * lerpf(1.0, 0.38, night))
		m.set_shader_parameter("sun_color", p["sun"])
		m.set_shader_parameter("sun_dir", _sun_dir)
		m.set_shader_parameter("night", night)
		m.set_shader_parameter("sun_energy", 1.0 - blizzard * 0.85)


func _update_weather_visual(_delta: float) -> void:
	var w: float = Game.wind
	var on: bool = Game.weather != "clear" and Game.started

	if _near:
		_near.emitting = on
		_near.amount = 900 if Game.weather == "blizzard" else (420 if Game.weather == "snow" else 1)
		var m := _near.process_material as ParticleProcessMaterial
		m.direction = Vector3(-0.25 - w * 0.30, -1.0, -0.12 - w * 0.12).normalized()
		m.initial_velocity_min = 2.0 + w * 1.1
		m.initial_velocity_max = 3.9 + w * 1.6
	if _far:
		_far.emitting = on
		_far.amount = 1200 if Game.weather == "blizzard" else (520 if Game.weather == "snow" else 1)
		var m2 := _far.process_material as ParticleProcessMaterial
		m2.direction = Vector3(-0.22 - w * 0.34, -1.0, -0.12 - w * 0.14).normalized()
	if _drift:
		_drift.emitting = on
		_drift.amount = 340 if Game.weather == "blizzard" else (90 if Game.weather == "snow" else 1)
		var m3 := _drift.process_material as ParticleProcessMaterial
		m3.direction = Vector3(-1.0, -0.06, -0.25).normalized()
		m3.initial_velocity_min = 3.0 + w * 2.4
		m3.initial_velocity_max = 7.0 + w * 3.4
		var dm := _drift.draw_pass_1.material as ShaderMaterial
		dm.set_shader_parameter("alpha", 0.055 + w * 0.018)
