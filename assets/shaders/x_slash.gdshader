shader_type canvas_item;
render_mode unshaded;

// X 双斩 v2（2026-11-08，Grock 专属，主人定稿）：
// ① 两道剑光沿对角交叉劈过（有先后、有白闪张力）
// ② 旧立绘被 X 线切成四片，沿对角滑开（下片带坠感）
// ③ 四片像被火烧一样消散：火线橙红 → 留下黑色焦痕 → 焦痕逐渐变透明
// 底下全程透出新立绘（斩击出现即显现）。

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float e = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, e, u.x), u.y);
}

void fragment() {
	vec2 q = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float d1 = (q.x - q.y) * 0.7071;
	float d2 = (q.x + q.y) * 0.7071;

	// ① 双斩闪线（第一道 0~0.30，第二道 0.13~0.44）
	float sw1 = mix(-1.3, 1.3, clamp(progress / 0.26, 0.0, 1.0));
	float sw2 = mix(1.3, -1.3, clamp((progress - 0.15) / 0.26, 0.0, 1.0));
	float slash1 = exp(-abs(d1 - sw1) * 22.0) * step(0.001, progress) * step(progress, 0.32);
	float slash2 = exp(-abs(d2 - sw2) * 22.0) * step(0.13, progress) * step(progress, 0.46);

	// ② 交叉瞬间白闪（张力帧）
	float flash = exp(-abs(progress - 0.30) * 26.0) * 0.32;

	// ③ 四片沿对角滑开（0.36~0.70）+ 下片坠感
	float split = smoothstep(0.36, 0.72, progress);
	float side1 = step(0.0, d1);
	float side2 = step(0.0, d2);
	vec2 dir = normalize(vec2(side1 * 2.0 - 1.0, side2 * 2.0 - 1.0) + vec2(0.001, 0.001));
	float grav = (side2 > 0.5) ? 0.30 : -0.10;
	vec2 off = (dir * 0.55 + vec2(0.0, grav)) * split;

	// ④ 火烧消散（0.45 起，四片错峰）：噪声阈值，火线→焦痕→渐隐
	float qidx = side1 * 2.0 + side2; // 0..3
	float burn_p = clamp((progress - 0.45 - qidx * 0.055) / 0.40, -0.2, 1.6);
	float n = vnoise(UV * 9.0) * 0.85 + vnoise(UV * 23.0 + vec2(31.7)) * 0.15;
	float d = n - burn_p;

	vec4 prev_c = texture(tex_prev, UV - off);
	vec4 next_c = texture(tex_next, UV);

	float char_tex = vnoise(UV * 31.0 + vec2(11.0));
	vec3 char_col = vec3(0.03, 0.024, 0.03) + vec3(char_tex * 0.06);
	vec3 ember_col = vec3(1.0, 0.42, 0.10) * (1.1 + 0.6 * vnoise(UV * 40.0 + vec2(TIME * 3.0)));

	vec3 piece_col;
	float piece_a;
	if (d > 0.06) {
		piece_col = prev_c.rgb;      // 未烧：本片还完整
		piece_a = 1.0;
	} else if (d > 0.0) {
		piece_col = mix(ember_col, prev_c.rgb, d / 0.06); // 火线
		piece_a = 1.0;
	} else if (d > -0.28) {
		piece_col = char_col;        // 黑色焦痕（留着）
		piece_a = 1.0;
	} else {
		piece_col = char_col;        // 焦痕逐渐变透明消失
		piece_a = smoothstep(-0.46, -0.28, d);
	}
	// 收尾全局退场，保证 progress=1 干净
	float end_fade = 1.0 - smoothstep(0.9, 1.0, progress);
	float old_a = clamp(piece_a, 0.0, 1.0) * end_fade;

	vec4 col = mix(next_c, vec4(piece_col, 1.0), old_a);

	// 斩缝暗红残光（交叉后短暂可见）
	float cut_vis = smoothstep(0.28, 0.4, progress) * (1.0 - smoothstep(0.7, 0.88, progress));
	float cut = exp(-abs(d1) * 26.0) + exp(-abs(d2) * 26.0);
	col.rgb += vec3(1.0, 0.25, 0.3) * cut * cut_vis * 0.5;

	// 剑光本体 + 白闪
	col.rgb += vec3(1.0) * (slash1 + slash2) * 0.95;
	col.rgb += vec3(1.0, 0.98, 0.9) * flash;

	COLOR = col;
}
