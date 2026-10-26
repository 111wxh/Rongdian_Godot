shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
//  冰岩 / 冰脉 —— 冻结的冰块，不是白色多面体
//  关键：内部要有"透光的芯"，表面要有霜与积雪，边缘要有磨亮的棱
// ============================================================================

uniform vec3 ice_core : source_color = vec3(0.30, 0.52, 0.70);   // 冰内部（背光透出的蓝）
uniform vec3 ice_frost : source_color = vec3(0.78, 0.86, 0.95);  // 表面霜
uniform vec3 snow_color : source_color = vec3(0.905, 0.935, 0.980);
uniform float snow_amount = 1.0;
uniform float frost_amount = 1.0;
uniform float seed_v = 0.0;

global uniform float g_night;
global uniform vec3 g_sun_dir;

varying vec3 w_nrm;
varying vec3 w_pos;

float h12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), u.x),
		mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.877, -0.479), vec2(0.479, 0.877));
	for (int i = 0; i < 5; i++) {
		if (i >= oct) { break; }
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

void fragment() {
	vec3 n = normalize(w_nrm);
	float up = clamp(n.y, 0.0, 1.0);
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - w_pos);

	// 按法线主轴取平面坐标，无 UV 也能贴噪声
	vec2 plane;
	if (abs(n.y) > 0.72) {
		plane = w_pos.xz;
	} else if (abs(n.x) > abs(n.z)) {
		plane = vec2(w_pos.z, w_pos.y);
	} else {
		plane = vec2(w_pos.x, w_pos.y);
	}
	plane += seed_v;

	// ---- 冰的体色：脏冰，不是游泳池 ----
	// 之前的版本把冰当作"发光的蓝宝石"来处理，结果每一块都在雪原上读成
	// 一颗亮蓝色的糖果蛋。真实的冻结水坑/冰壳是**脏的**：里面混着泥沙、
	// 气泡、被冻住的草叶，颜色接近灰白，只在裂面深处才透一点冷蓝。
	// 所以整体往灰白拉、把饱和度压到极低，蓝色只留给"深处"和"背光透光"。
	float deep = fbm(plane * 0.55, 3);
	float mid = fbm(plane * 2.1 + 13.0, 3);
	float fine = vn(plane * 9.0);
	// 主色：脏白带一丝青，明度由噪声拉开
	vec3 col = mix(vec3(0.400, 0.452, 0.500), vec3(0.700, 0.752, 0.792), deep);
	// 只有真正的深处才透出冷蓝（少量）
	col = mix(col, ice_core * 1.15, smoothstep(0.62, 0.92, mid) * 0.34);
	// 气泡/杂质：极细的亮点与暗点，冰块才不像塑料
	col *= 0.86 + 0.26 * fine;
	// 泥沙/被冻住的东西：低频脏斑，把"糖果感"彻底压掉
	float grime = smoothstep(0.30, 0.74, fbm(plane * 0.42 + 31.0, 4));
	col = mix(col, vec3(0.226, 0.232, 0.238), grime * 0.34);

	// ---- 裂面：冰是被冻裂的，不是被打磨的 ----
	// 用低频噪声的等值线切出十字/斜交的裂面，再按裂面两侧做明暗差，
	// 读起来才有"一块冰"的体积，而不是一个椭球。
	float cr1 = abs(fbm(plane * 0.30 + 3.0, 3) - 0.5);
	float cr2 = abs(fbm(plane * 0.30 + 17.0, 3) - 0.5);
	float facet = min(cr1, cr2);
	float seam = smoothstep(0.030, 0.0, facet);
	// 裂面本身发白（断面粗糙、积霜），侧面略暗（斜角反光少）
	col = mix(col, vec3(0.760, 0.800, 0.840), seam * 0.42);
	col *= 1.0 - smoothstep(0.030, 0.120, facet) * 0.10;

	// ---- 棱：面与面之间被磨得发白 ----
	// 掠射角 + 高频噪声，模拟被风沙打磨过的边
	float graze = 1.0 - clamp(dot(n, vdir), 0.0, 1.0);
	float rim = pow(graze, 3.2) * (0.5 + 0.5 * vn(plane * 5.0));
	col = mix(col, ice_frost * 0.86, rim * 0.34 * frost_amount);

	// ---- 表面霜：薄薄一层，成片不匀 ----
	float frost = smoothstep(0.42, 0.78, fbm(plane * 1.35 + 7.0, 4));
	col = mix(col, ice_frost * 0.90, frost * 0.46 * frost_amount);

	// ---- 顶部积雪：朝上的面被雪盖住 ----
	float sn = fbm(plane * 0.85, 4);
	float cover = up * 1.02 + sn * 0.42 - 0.42;
	// 侧面的雪：只留很少的斑
	float side = smoothstep(0.86, 1.02, fbm(vec2(plane.x * 2.6, plane.y * 2.0), 3)) * 0.22;
	cover = max(cover, (1.0 - up) * side);
	cover *= snow_amount;
	cover = smoothstep(0.34, 0.66, cover);
	vec3 snow_c = snow_color * (0.94 + 0.10 * fbm(plane * 3.6, 3));
	col = mix(col, snow_c, cover);

	ALBEDO = col;
	// 冰本身是低粗糙度的；被雪盖住的地方变粗糙。但"低粗糙度"不等于镜面：
	// 粗糙度 0.10 会把它变成一个高光球，在任何光照下都读成塑料。
	ROUGHNESS = mix(0.30, 0.78, cover);
	ROUGHNESS = mix(ROUGHNESS, 0.46, frost * (1.0 - cover));
	METALLIC = 0.0;
	SPECULAR = mix(0.46, 0.30, cover);
	// 冰是半透的：让背光面透出一点内部的光，否则读成白石头。
	// 但这个量必须极小——之前 0.10 + back*0.55 会让每块冰自己发光，
	// 在夜里比路灯还亮。
	float trans = (1.0 - up) * (1.0 - cover) * 0.40;
	float back = clamp(dot(-n, normalize(g_sun_dir)), 0.0, 1.0);
	EMISSION = ice_core * trans * (0.02 + back * 0.16) * (1.0 - g_night * 0.80);
	// 雪面微闪
	float crystal = smoothstep(0.972, 1.0, vn(plane * 42.0));
	EMISSION += vec3(0.60, 0.72, 0.90) * crystal * cover * (0.25 + graze * 0.75) * 0.30;

	AO = mix(1.0, 0.82, cover);
	AO_LIGHT_AFFECT = 0.35;

	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
