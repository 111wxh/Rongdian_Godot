// 雪丘 / 雪堆 / 雪堤专用表面着色器。
// 这些物体是压扁的球体，形状本身没问题，但用表面的通用材质渲染时会读成
// "光滑的白塑料抱枕"——因为它们没有任何世界尺度的纹理，法线又完全光滑。
// 这里把地形雪面的那套风蚀纹 / 雪壳 / 颗粒搬到它们身上，
// 让墙脚堆雪和路肩雪堤跟脚下的雪原连成一种材质。
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 snow_color : source_color = vec3(0.855, 0.885, 0.945);
uniform vec3 snow_shade : source_color = vec3(0.615, 0.700, 0.830);
uniform float ripple_strength : hint_range(0.0, 2.0) = 1.0;
uniform float sparkle_amount : hint_range(0.0, 2.0) = 0.7;
uniform float seed_v = 0.0;

global uniform float g_night;

varying vec3 w_nrm;
varying vec3 w_pos;

float sp_h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 五次平滑：见 terrain_snow.gdshader 里的同款注释。
// 三次式 f*f*(3-2f) 的二阶导在格点处不为 0，会把每个噪声格子的
// 对角线折成一道硬痕；雪堆的 grain 层频率很高，折痕连起来就是织纹。
float sp_vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(sp_h12(i), sp_h12(i + vec2(1.0, 0.0)), u.x),
	           mix(sp_h12(i + vec2(0.0, 1.0)), sp_h12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float sp_fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.877, -0.479), vec2(0.479, 0.877));
	// 每层换轴向：所有倍频共用一套格子轴向时，各层折痕会重合，
	// 雪面上会浮出一层规则的正交网格。
	vec2 q = r * p + vec2(17.3, 9.1);
	for (int i = 0; i < 6; i++) {
		if (i >= oct) break;
		v += a * sp_vn(q);
		q = r * q * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(w_nrm);
	float up = clamp(n.y, 0.0, 1.0);
	vec2 wp = w_pos.xz + seed_v;

	// 风向（与 world_generator 的 _drift 保持一致）：世界 +x 偏 -z。
	// 雪丘上的纹理必须**沿风向拉长**，否则就是一身匀质的皮肤——
	// 之前就是这样：噪声各向同性平铺，近看是一层光滑的霜壳。
	vec2 wdir = normalize(vec2(0.86, -0.51));
	vec2 cross_d = vec2(-wdir.y, wdir.x);
	float al = dot(wp, wdir);
	float ac = dot(wp, cross_d);

	// 风蚀纹：沿风向拉长 3 倍以上的条带
	float drift = sp_fbm(vec2(al * 0.14, ac * 0.58), 4);
	float drift2 = sp_fbm(vec2(al * 0.52, ac * 2.05) + 31.0, 3);
	float drift3 = sp_fbm(vec2(al * 1.9 + 7.0, ac * 6.4 + 3.0), 3);
	float ripple = (drift * 0.50 + drift2 * 0.30 + drift3 * 0.20) * ripple_strength;
	float ridge = smoothstep(0.42, 0.78, ripple);

	vec3 col = snow_color * (0.88 + 0.18 * ripple);
	col = mix(col, snow_shade, (1.0 - ridge) * 0.40);
	col = mix(col, snow_shade * 0.90, (1.0 - up) * 0.45);

	// 背风侧的"檐口"：雪丘上缘被风削出一条硬边，
	// 光从侧面来时这条边是全画面最亮的一笔。用高度 + 朝向来定位。
	float lip = smoothstep(0.55, 0.95, up) * smoothstep(0.2, 0.8, dot(normalize(vec3(n.x, 0.0, n.z) + vec3(0.001)), vec3(wdir.x, 0.0, wdir.y)));
	col = mix(col, snow_color * 1.10, lip * 0.30);

	// 迎风面的砂蚀：迎风侧被吹得更实、更暗、更灰
	float windward = smoothstep(0.15, -0.55, dot(normalize(n.xz + vec2(0.001)), wdir));
	float sand = sp_fbm(vec2(al * 2.6, ac * 9.0), 3);
	col = mix(col, col * vec3(0.90, 0.895, 0.90), windward * (0.35 + 0.30 * sand));

	// 雪壳碎裂：近处才看得见的细缝
	float t_fp = max(fwidth(w_pos.x), fwidth(w_pos.z));
	float near_f = 1.0 - smoothstep(0.016, 0.090, t_fp);
	float plate = sp_fbm(wp * 1.35 + 3.1, 3);
	float seam = smoothstep(0.035, 0.0, abs(plate - 0.5)) * 0.50;
	col *= 1.0 - seam * near_f * 0.55;
	// 雪粒
	float grain = sp_vn(wp * 26.0) * 0.5 + sp_vn(wp * 61.0) * 0.5;
	col *= 1.0 + (0.08 * grain - 0.04) * near_f;

	// 底部贴地的一圈脏雪：雪堆不能像浮在雪面上
	float foot = smoothstep(0.30, 0.01, w_pos.y);
	col = mix(col, col * 0.80, clamp(foot, 0.0, 1.0) * 0.55);

	ALBEDO = col;
	ROUGHNESS = 0.94;
	SPECULAR = 0.22;
	METALLIC = 0.0;

	// 冰晶微闪
	float graze = 1.0 - clamp(dot(n, normalize(CAMERA_POSITION_WORLD - w_pos)), 0.0, 1.0);
	float crystal = smoothstep(0.955, 1.0, sp_vn(wp * 34.0));
	EMISSION = vec3(0.55, 0.68, 0.85) * crystal * (0.3 + graze * 0.8) * 0.5 * sparkle_amount;

	// 世界空间噪声扰动法线：掠射光下有起伏。
	// 采样方向必须和 albedo 的条带方向一致，否则明暗和纹理对不上，
	// 读起来是"贴了一张纸在光滑的球上"。
	float e = 0.07;
	float h0 = sp_fbm(vec2(al * 0.14, ac * 0.58), 4) + sp_fbm(vec2(al * 0.52, ac * 2.05) + 31.0, 3) * 0.5;
	float hx = sp_fbm(vec2((al + e) * 0.14, ac * 0.58), 4) + sp_fbm(vec2((al + e) * 0.52, ac * 2.05) + 31.0, 3) * 0.5;
	float hz = sp_fbm(vec2(al * 0.14, (ac + e) * 0.58), 4) + sp_fbm(vec2(al * 0.52, (ac + e) * 2.05) + 31.0, 3) * 0.5;
	// 0.05 的斜率太软了：几乎不改变着色法线，雪丘因此还是"光滑"的。
	// 风蚀雪面在斜射光下有明显的小落差，给到 0.16。
	vec2 grad = vec2(hx - h0, hz - h0) / e * 0.16;
	vec3 nrm = normalize(n - vec3(grad.x, 0.0, grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);

	AO = clamp(0.94 - (1.0 - up) * 0.10, 0.7, 1.0);
	AO_LIGHT_AFFECT = 0.30;
}
