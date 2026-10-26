shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// 褪色路面标线：漆面剥落 + 雪覆盖 + 胎痕磨白
uniform vec3 paint : source_color = vec3(0.72, 0.68, 0.44);
uniform vec3 snow_color : source_color = vec3(0.900, 0.930, 0.975);
uniform float wear = 1.0;
uniform float snow_amount = 1.0;

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
	for (int i = 0; i < 4; i++) {
		if (i >= oct) {
			break;
		}
		v += vn(p) * a;
		p = r * p * 2.04 + vec2(3.3, 8.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = w_pos.xz;

	// 漆面剥落：边缘被啃掉，中间留残
	float erode = fbm(p * 3.2, 3);
	float keep = smoothstep(0.30, 0.62, erode + 0.25 - (1.0 - wear) * 0.4);

	// 磨损变白/变灰
	vec3 col = mix(paint, paint * 0.55 + vec3(0.30, 0.32, 0.34) * 0.5, fbm(p * 1.6 + 12.0, 3));

	// 雪把标线盖掉一部分
	float snow = smoothstep(0.50, 0.78, fbm(p * 1.1 + 5.0, 3) + 0.18) * snow_amount;
	col = mix(col, snow_color, snow);

	ALBEDO = col;
	ROUGHNESS = mix(0.78, 0.30, snow);
	SPECULAR = mix(0.30, 0.55, snow);
	METALLIC = 0.0;

	// 剥落处透出沥青，用 ALPHA 直接切掉（更干净，不发灰）
	ALPHA = keep;
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	AO_LIGHT_AFFECT = 0.15;
}
