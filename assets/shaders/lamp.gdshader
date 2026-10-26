shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

// 灯罩玻璃 / 招牌 / 加油机显示屏。
// 白天读作一块脏玻璃（几乎不发光），入夜整片透出暖光——
// 这是"这座城还有人住"的唯一证据，也是夜景里唯一的暖色锚点。
// 用 unshaded：小面积自发光不需要参与光照，省一遍 PBR 计算。

uniform vec3 glass_color : source_color = vec3(0.050, 0.052, 0.058);
uniform vec3 glow_color : source_color = vec3(1.0, 0.78, 0.46);
uniform float glow_energy = 2.2;
uniform float seed_v = 0.0;

global uniform float g_night;

void fragment() {
	// 灯管不是绝对稳定的：一点点呼吸与闪烁，才不像贴上去的贴纸。
	float flick = 0.94
		+ 0.05 * sin(TIME * 2.7 + seed_v * 11.0)
		+ 0.02 * sin(TIME * 13.1 + seed_v * 3.0);
	// 开关：黄昏偏后段才亮起来，天亮前先灭。
	float on = clamp(g_night * 1.25 - 0.16, 0.0, 1.0);
	on *= flick;

	// 灯罩里不是均匀一片：中心更亮、边缘被灯罩压暗。
	vec3 c = mix(glass_color, glow_color * glow_energy, on);
	ALBEDO = c;
}
