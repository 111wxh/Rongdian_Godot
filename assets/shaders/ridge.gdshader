shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, fog_disabled;

// ============================================================================
//  远景山脊：三层剪影，全部由 day_night 每帧喂入雾色做空气透视。
//  不参与光照——远景要的是"层次"，不是"正确"。
//  形态靠"低处沉入雾、高处露出岩"的垂直梯度 + 横向沟壑来读，不靠法线。
// ============================================================================

uniform vec3 haze_color : source_color = vec3(0.72, 0.78, 0.86);
uniform vec3 rock_color : source_color = vec3(0.20, 0.24, 0.32);
uniform vec3 snow_color : source_color = vec3(0.86, 0.90, 0.96);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.90);
uniform vec3 sun_dir = vec3(0.3, 0.4, 0.8);

uniform float layer_mix = 0.4;      // 该层被雾吃掉的程度（越远越大）
uniform float height_scale = 60.0;  // 该层山峰的世界高度上限
uniform float night = 0.0;
uniform float sun_energy = 1.0;
uniform float seed_v = 0.0;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

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
		p = r * p * 2.05 + vec2(7.3, 3.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float hn = clamp(w_pos.y / max(height_scale, 1.0), 0.0, 1.0);

	// 横向坐标（绕山脊一周的弧度 × 半径），让沟壑沿山势走
	float ang = atan(w_pos.z, w_pos.x);
	// 半径也是变量：山脊是"圈"，近处的峰比远处的峰张角大得多，
	// 只按角度索取噪声会让相邻的峰吃到同一块纹理，读起来像一根梳齿排。
	float rr = length(w_pos.xz);
	vec2 hp = vec2(ang * 42.0 + seed_v, rr * 0.006 + hn * 26.0);

	// 沟壑：竖向拉长的噪声，像被冰川切开的岩槽
	float gully = fbm(hp * vec2(1.0, 0.34), 4);
	float gully2 = fbm(hp * vec2(2.6, 0.9) + 13.0, 3);
	float shade = mix(gully, gully2, 0.42);

	// 迎光面：远景山没有可信的法线，用「方位角相对太阳的夹角」伪造左右受光。
	// 只靠 radial 法线的话，整条山脊会是一片死平的黑带。
	vec3 sd = normalize(sun_dir);
	float sun_az = atan(sd.z, sd.x);
	float rel = cos(ang - sun_az);                 // ±1：面向/背向太阳的一侧
	float lam = clamp(rel * 0.5 + 0.5, 0.0, 1.0);
	lam = pow(lam, 0.80);
	// 沟壑里的阴影：谷底更深
	lam *= 0.74 + 0.42 * shade;

	// ---- 岩体 ----
	// 关键教训：远山如果只是"压暗的灰"，读出来就是一张剪影纸片。
	// 它必须有内部的明暗结构——受光坡是冷灰蓝、背光坡沉到深靛、
	// 再叠一层水平层理，山才有"体量"。
	vec3 rock = rock_color * (0.86 + 0.78 * lam) * (0.86 + 0.26 * hn);
	rock *= 0.88 + 0.24 * fbm(vec2(hn * 22.0 + seed_v, ang * 8.0), 3);
	// 水平层理：沉积岩一层一层堆上去，远看就是一组横向的深浅条纹。
	// 这是远景山唯一能被眼睛抓住的"内部结构"——没有它，
	// 山就只是一块被雾染色的板子。
	float strata = fbm(vec2(ang * 3.2 + seed_v, hn * 46.0), 3);
	float strata2 = vn(vec2(ang * 2.0, hn * 88.0));
	rock *= 0.74 + 0.44 * (strata * 0.72 + strata2 * 0.28);

	// ---- 积雪 ----
	// 这是一片被冰封的世界，山应该是白头的，但"白头"不等于"整座山刷白"。
	// 雪线必须到山腰以上才起，且只在缓坡与雪槽里挂得住；
	// 陡直的岩肋上雪是挂不住的——那正是一条条深色的竖纹，
	// 山体的体量全靠这组竖纹撑起来。
	float snowline = smoothstep(0.26, 0.66, hn);
	float rib = fbm(vec2(ang * 44.0 + seed_v * 2.0, hn * 2.4), 4);
	float rib_hard = smoothstep(0.46, 0.66, rib);
	float chute = smoothstep(0.34, 0.62, fbm(vec2(ang * 20.0 + seed_v, hn * 5.0), 3));
	// 陡壁判定：用噪声的一阶差近似"坡面的陡缓"，陡处不留雪
	float steep = smoothstep(0.030, 0.090, abs(fbm(vec2(ang * 60.0 + seed_v, hn * 3.0), 3) - rib));
	float cap = snowline * (0.30 + 0.70 * chute) * (1.0 - rib_hard * 0.80);
	cap *= 1.0 - steep * 0.45;
	// 背光坡上的雪不是白的，是被天光染成灰蓝的——这是体积感的一半来源
	vec3 snowc = mix(haze_color * 1.05, snow_color, 0.42 + 0.58 * lam);
	vec3 col = mix(rock, snowc, clamp(cap, 0.0, 0.94));

	// 山脚的雪坡：远处山峰底部要有一条"雪往上爬"的过渡带，
	// 否则岩体会浮在雪原上，像一块贴上去的剪影。
	float foot_snow = smoothstep(0.24, 0.0, hn) * (0.55 + 0.45 * fbm(vec2(ang * 14.0, hn * 3.0), 3));
	col = mix(col, snow_color * 0.90, clamp(foot_snow * 0.85, 0.0, 0.88));

	// 空气透视：不能是均匀的一层纱。山脚几乎完全融进霾里，
	// 越往上越实——这才是"远"的读法。曾经把这一项写成常数，
	// 结果整条山脊悬在一条硬边白雾带上，像贴纸。
	float aerial = clamp(layer_mix, 0.0, 0.95);
	aerial *= mix(1.65, 0.52, smoothstep(0.02, 0.78, hn));
	col = mix(col, haze_color, aerial);

	// 阳光擦过山脊的一层辉光
	col += sun_color * pow(clamp(lam, 0.0, 1.0), 4.0) * 0.10 * (1.0 - night) * (0.25 + cap);

	// 夜里压暗
	col *= 1.0 - night * 0.42;

	ALBEDO = col;
	ALPHA = 1.0;
}
