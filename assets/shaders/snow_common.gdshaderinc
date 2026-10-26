// 《融点》程序化材质基座：噪声、覆雪、风蚀、细节法线
// 所有世界材质共用，保证"同一场雪"覆盖整张地图

float dsh_hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float dsh_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = dsh_hash12(i);
	float b = dsh_hash12(i + vec2(1.0, 0.0));
	float c = dsh_hash12(i + vec2(0.0, 1.0));
	float d = dsh_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 8 边形可分离 fbm，避免方向性拉伸
float dsh_fbm(vec2 p, int oct) {
	float v = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.877, -0.479), vec2(0.479, 0.877));
	for (int i = 0; i < 6; i++) {
		if (i >= oct) {
			break;
		}
		v += dsh_vnoise(p) * amp;
		p = rot * p * 2.07 + vec2(13.7, 7.3);
		amp *= 0.5;
	}
	return v;
}

// 雪覆盖：法线朝上 + 大尺度噪声打散，避免整片死白
float dsh_snow_coverage(vec3 wn, vec2 wp, float bias, float soft) {
	float up = clamp(wn.y, 0.0, 1.0);
	float n = dsh_fbm(wp * 0.045, 3);
	float m = up * 0.86 + n * 0.34 - 0.28 + bias;
	return smoothstep(0.52 - soft, 0.52 + soft, m);
}

// 风吹雪纹：沿 +x 拉长的条带，模拟风蚀的雪面起伏
float dsh_wind_ripple(vec2 wp) {
	vec2 p = vec2(wp.x * 0.11, wp.y * 1.15);
	float a = dsh_fbm(p, 3);
	float b = dsh_vnoise(vec2(wp.x * 0.5, wp.y * 5.5)) * 0.5;
	return a * 0.7 + b;
}

// 由高度场梯度扰动法线（视图空间输出）
vec3 dsh_perturb_normal(vec3 wn, float gx, float gy, float gz, float strength) {
	vec3 t = normalize(vec3(1.0, 0.0, 0.0) + wn * 0.0);
	vec3 b = normalize(cross(wn, t));
	vec3 n = wn - t * gx * strength - b * gz * strength + vec3(0.0, gy * 0.0, 0.0);
	return normalize(n);
}

// 雪面细碎高光（冰晶闪烁），只在很密的像素上挑出来
float dsh_sparkle(vec2 wp, float t) {
	vec2 g = wp * 26.0;
	float s = dsh_vnoise(g + vec2(t * 0.6, t * 0.35));
	return smoothstep(0.955, 1.0, s);
}
