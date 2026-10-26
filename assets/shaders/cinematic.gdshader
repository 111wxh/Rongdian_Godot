shader_type canvas_item;
render_mode blend_disabled, unshaded;

// 全屏电影感后处理：暗角 / 胶片颗粒 / 边缘色散 / 冷暖分离调色 / 轻微镜头呼吸
// 全部基于屏幕纹理，一层 CanvasLayer 就够，不影响 3D 与 HUD 的逻辑。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform float vignette : hint_range(0.0, 2.0) = 0.85;
uniform float grain : hint_range(0.0, 0.2) = 0.030;
uniform float aberration : hint_range(0.0, 6.0) = 1.15;
uniform float cold_lift : hint_range(0.0, 0.2) = 0.045;   // 暗部往冷蓝抬
uniform float warm_gain : hint_range(0.0, 0.3) = 0.055;   // 高光往暖偏
uniform float contrast : hint_range(0.5, 2.0) = 1.045;
uniform float saturation : hint_range(0.0, 2.0) = 1.02;
uniform float night : hint_range(0.0, 1.0) = 0.0;         // 由脚本写入 Game.night_mix
uniform float fade : hint_range(0.0, 1.0) = 1.0;          // 开场淡入用

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 ctr = uv - 0.5;
	float r2 = dot(ctr, ctr);
	float r = sqrt(r2);

	// ---- 边缘色散：只在画面外侧轻微分离，中心保持锐利 ----
	vec2 dir = (r > 0.0001) ? ctr / r : vec2(0.0);
	float ab = aberration * 0.0016 * smoothstep(0.22, 0.78, r);
	vec3 col;
	col.r = texture(screen_tex, uv + dir * ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * ab).b;

	// ---- 高光肩部：现实世界里没有任何一块雪是"纯白"的 ----
	// 量化：我们的成图有 7.0% 的像素亮度 >0.95、2.2% >0.98，
	// 而三张参考雪景照片里 >0.95 的像素是 **0.0%**。
	// 这不是"我们的画面太亮"，而是"我们的亮部没有容积"：
	// 一旦雪面推到 1.0，风蚀纹、雪丘的受光面、屋脊的转折全部被削平，
	// 眼睛看到的就是一块没有形状的白纸——过曝不会更亮，只会更平。
	// 胶片和真实传感器的亮部是一条渐近线，永远接近但碰不到顶。
	// 这里用一条按亮度归一化的指数肩部：0.70 以下完全不动，
	// 0.70 以上逐渐压进 1.0，最亮的像素也只能到 0.99 左右。
	// 按亮度缩放而不是逐通道截断，是为了保住雪的色相（逐通道会让高光泛白）。
	float lum_pre = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float knee = 0.70;
	if (lum_pre > knee) {
		float k = 1.0 - knee;
		float over = lum_pre - knee;
		float lum_c = knee + k * (1.0 - exp(-over / k));
		col *= lum_c / max(lum_pre, 1e-5);
	}

	// ---- 调色：先做对比，再冷暖分离（lift shadows / gain highlights）----
	col = (col - 0.5) * contrast + 0.5;
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	// 高光偏暖、暗部偏冷，但整体冷却——冰原的味道
	vec3 warm = vec3(1.02, 1.0, 0.965);
	vec3 cold = vec3(0.945, 0.985, 1.06);
	col *= mix(cold, warm, smoothstep(0.35, 0.95, lum)) ;
	col += cold * cold_lift * (1.0 - smoothstep(0.0, 0.45, lum));
	col += warm * warm_gain * smoothstep(0.55, 1.0, lum);

	// 饱和：夜里收一点，白天保持
	float s = saturation * mix(1.0, 0.86, night);
	col = mix(vec3(lum), col, s);

	// ---- 暗角：两层，外层压角、内层做柔边 ----
	float vig_outer = smoothstep(0.92, 0.34, r);
	float vig_inner = smoothstep(0.86, 0.18, r);
	float v = mix(1.0, vig_outer, vignette * 0.55) * mix(1.0, vig_inner, vignette * 0.20);
	col *= clamp(v, 0.0, 1.0);

	// ---- 胶片颗粒：只在中间调最明显，暗部与高光都收住 ----
	float lum2 = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float gmask = smoothstep(0.02, 0.28, lum2) * (1.0 - smoothstep(0.72, 1.0, lum2));
	float gn = hash21(uv * vec2(1920.0, 1080.0) + fract(TIME) * 137.0) - 0.5;
	col += gn * grain * gmask;
	// 极轻的竖向扫描抖动，让静态截图有"胶片在走"的错觉
	col += (hash21(vec2(uv.y * 1460.0, floor(TIME * 24.0))) - 0.5) * grain * 0.35 * gmask;

	// ---- 边缘轻微失焦的呼吸（极弱，只在最外圈）----
	float edge = smoothstep(0.62, 1.05, r);
	col = mix(col, col * 0.985 + vec3(0.004, 0.006, 0.010), edge * 0.6);

	col = max(col, vec3(0.0));
	COLOR = vec4(col * fade, 1.0);
}
