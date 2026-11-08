shader_type canvas_item;
render_mode unshaded;

// X 双斩 v3（2026-11-08，Grock 专属，主人反馈加张力）：
// ① 两道更宽更亮的剑光对角交叉扫过（带拖尾），交叉瞬间白闪更狠
// ② 旧立绘四片沿对角大幅飞出（1.7 倍位移 + 坠弧），干净利落
// ③ 飞出过程照旧火烧：火线橙红 → 黑色焦痕 → 渐隐
// ④ 新立绘登场带一记缩放冲击（先放大再落定），画面不闷

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

	// ① 双斩：主光带更宽（falloff 14），后面拖一条余光
	float sw1 = mix(-1.45, 1.45, clamp(progress / 0.26, 0.0, 1.0));
	float sw2 = mix(1.45, -1.45, clamp((progress - 0.15) / 0.26, 0.0, 1.0));
	float s1 = exp(-abs(d1 - sw1) * 14.0) * step(0.001, progress) * step(progress, 0.32);
	float s2 = exp(-abs(d2 - sw2) * 14.0) * step(0.13, progress) * step(progress, 0.46);
	float trail1 = exp(-abs(d1 - (sw1 - 0.22)) * 30.0) * step(0.001, progress) * step(progress, 0.32);
	float trail2 = exp(-abs(d2 - (sw2 + 0.22)) * 30.0) * step(0.13, progress) * step(progress, 0.46);

	// ② 交叉白闪（更狠）
	float flash = exp(-abs(progress - 0.30) * 24.0) * 0.45;

	// ③ 四片大幅飞出：位移 0.95（比 v2 大 70%），快起慢停，下片坠弧——
	//    位移别太大，四片要留在画面里边飞边烧
	float split_t = clamp((progress - 0.34) / 0.28, 0.0, 1.0);
	float split = 1.0 - pow(1.0 - split_t, 2.2);
	float side1 = step(0.0, d1);
	float side2 = step(0.0, d2);
	vec2 dir = normalize(vec2(side1 * 2.0 - 1.0, side2 * 2.0 - 1.0) + vec2(0.001, 0.001));
	float grav = (side2 > 0.5) ? 0.4 : -0.15;
	vec2 off = (dir * 0.95 + vec2(0.0, grav)) * split;

	// ④ 火烧（0.45 起，四片错峰）：火线 → 黑痕 → 渐隐
	float qidx = side1 * 2.0 + side2;
	float burn_p = clamp((progress - 0.45 - qidx * 0.055) / 0.40, -0.2, 1.6);
	float n = vnoise(UV * 9.0) * 0.85 + vnoise(UV * 23.0 + vec2(31.7)) * 0.15;
	float d = n - burn_p;

	vec4 prev_c = texture(tex_prev, UV - off);
	// 新立绘缩放冲击：先放大 8% 再落定
	float punch = 1.0 + 0.08 * exp(-abs(progress - 0.42) * 9.0);
	vec2 nuv = (UV - vec2(0.5)) / punch + vec2(0.5);
	vec4 next_c = texture(tex_next, nuv);

	float char_tex = vnoise(UV * 31.0 + vec2(11.0));
	vec3 char_col = vec3(0.03, 0.024, 0.03) + vec3(char_tex * 0.06);
	vec3 ember_col = vec3(1.0, 0.42, 0.10) * (1.1 + 0.6 * vnoise(UV * 40.0 + vec2(TIME * 3.0)));

	vec3 piece_col;
	float piece_a;
	if (d > 0.06) {
		piece_col = prev_c.rgb;
		piece_a = 1.0;
	} else if (d > 0.0) {
		piece_col = mix(ember_col, prev_c.rgb, d / 0.06);
		piece_a = 1.0;
	} else if (d > -0.28) {
		piece_col = char_col;
		piece_a = 1.0;
	} else {
		piece_col = char_col;
		piece_a = smoothstep(-0.46, -0.28, d);
	}
	float end_fade = 1.0 - smoothstep(0.9, 1.0, progress);
	float old_a = clamp(piece_a, 0.0, 1.0) * end_fade;

	vec4 col = mix(next_c, vec4(piece_col, 1.0), old_a);

	// 斩缝暗红残光
	float cut_vis = smoothstep(0.26, 0.38, progress) * (1.0 - smoothstep(0.7, 0.88, progress));
	float cut = exp(-abs(d1) * 26.0) + exp(-abs(d2) * 26.0);
	col.rgb += vec3(1.0, 0.25, 0.3) * cut * cut_vis * 0.5;

	// 剑光本体（白）+ 拖尾（淡红）+ 白闪
	col.rgb += vec3(1.0) * (s1 + s2) * 1.05;
	col.rgb += vec3(1.0, 0.55, 0.6) * (trail1 + trail2) * 0.5;
	col.rgb += vec3(1.0, 0.98, 0.9) * flash;

	COLOR = col;
}
