shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// 冰封沥青路面：龟裂 / 积雪补丁 / 车辙冰面 / 油污 / 边缘雪埋
uniform vec3 asphalt : source_color = vec3(0.105, 0.112, 0.125);
uniform vec3 asphalt_light : source_color = vec3(0.185, 0.190, 0.205);
uniform vec3 snow_color : source_color = vec3(0.900, 0.930, 0.975);
uniform vec3 ice_color : source_color = vec3(0.470, 0.610, 0.740);
uniform float road_half = 4.2;
uniform float road_axis = 0.0;     // 0 = 沿 z 延伸，1 = 沿 x 延伸
uniform float snow_bias = 0.0;

varying vec3 w_pos;
varying vec3 w_nrm;

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
		if (i >= oct) {
			break;
		}
		v += vn(p) * a;
		p = r * p * 2.05 + vec2(7.1, 3.9);
		a *= 0.5;
	}
	return v;
}

// 龟裂：细线网格，用两个方向的脊线交叉
float cracks(vec2 p, float scale) {
	vec2 q = p * scale;
	float a = abs(fbm(q, 3) - 0.5);
	float b = abs(fbm(q + vec2(4.7, 9.2), 3) - 0.5);
	float line_a = smoothstep(0.055, 0.0, a);
	float line_b = smoothstep(0.040, 0.0, b);
	return clamp(line_a + line_b * 0.7, 0.0, 1.0);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 wp = w_pos;
	// 沿路方向 u，横向 v
	float u = (road_axis < 0.5) ? wp.z : wp.x;
	float v = (road_axis < 0.5) ? wp.x : wp.z;
	float edge = abs(v) / road_half;              // 0=中线 1=路肩

	// ---- 沥青底色：大块斑驳 ----
	float patch = fbm(vec2(u * 0.09, v * 0.55), 4);
	vec3 col = mix(asphalt, asphalt_light, smoothstep(0.35, 0.75, patch) * 0.85);
	col *= 0.88 + 0.20 * fbm(vec2(u * 0.9, v * 4.0), 3);

	// 骨料颗粒
	float grit = vn(vec2(u * 26.0, v * 26.0));
	col *= 0.92 + 0.16 * grit;

	// ---- 龟裂 ----
	float cr = cracks(vec2(u, v), 0.55) * 0.7 + cracks(vec2(u + 21.0, v * 1.7), 1.6) * 0.3;
	col = mix(col, col * 0.45, cr * 0.85);

	// ---- 车辙：两条被压出冰面的暗带 ----
	float rut = exp(-pow((abs(v) - road_half * 0.46) * 5.6, 2.0));
	float rut2 = exp(-pow((abs(v) - road_half * 0.74) * 7.0, 2.0));
	float rut_mask = clamp(rut * 0.9 + rut2 * 0.35, 0.0, 1.0);
	// 车辙里积冰：更亮更光滑
	float rut_ice = rut_mask * smoothstep(0.42, 0.72, fbm(vec2(u * 0.22, v * 1.6), 3));
	col = mix(col, ice_color * 0.72, rut_ice * 0.55);

	// ---- 油污/雪泥条纹（沿行进方向拉长） ----
	float smear = smoothstep(0.55, 0.85, fbm(vec2(u * 0.35, v * 2.2), 4));
	col = mix(col, col * 0.72, smear * 0.5);

	// ---- 边缘积雪：从路肩向中心蔓延，噪声边界 ----
	float sn = fbm(vec2(u * 0.30, v * 1.35), 4);
	float edge_snow = smoothstep(0.62, 1.02, edge + (sn - 0.5) * 0.55 + snow_bias);
	// 路面上零散雪斑
	float blotch = smoothstep(0.66, 0.86, fbm(vec2(u * 0.42 + 3.0, v * 0.9), 4));
	edge_snow = clamp(edge_snow + blotch * 0.55, 0.0, 1.0);
	edge_snow *= smoothstep(0.2, 0.55, 1.0 - rut_ice * 0.8);

	vec3 snow_c = snow_color * (0.93 + 0.10 * fbm(vec2(u * 2.4, v * 2.4), 3));
	col = mix(col, snow_c, edge_snow);

	ALBEDO = col;
	ROUGHNESS = mix(0.86, 0.45, rut_ice);
	ROUGHNESS = mix(ROUGHNESS, 0.70, edge_snow);
	SPECULAR = mix(0.35, 0.62, rut_ice);
	METALLIC = 0.0;

	AO = clamp(1.0 - cr * 0.22, 0.6, 1.0);
	AO_LIGHT_AFFECT = 0.25;

	// 冰面反光的一点闪烁
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - wp);
	float graze = 1.0 - clamp(dot(normalize(w_nrm), vdir), 0.0, 1.0);
	EMISSION = vec3(0.42, 0.55, 0.72) * rut_ice * graze * 0.12;

	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(w_nrm), 0.0)).xyz);
}
