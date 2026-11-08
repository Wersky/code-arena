shader_type canvas_item;
render_mode unshaded;

// 乱斩转场 v5（2026-11-08，Grock 专属，主人定稿两段式）：
// ① 先把全部斩击斩完：6 条随机斩线**依次**劈下，每刀闪一道白光并**留下斩痕**
//    （细亮线 + 暗缝，留在完整的立绘上）——此阶段立绘不散
// ② 全部斩完后，被切出的碎布才开始**统一边飞边烧**（火线橙红 → 黑痕 → 渐隐），
//    斩痕随碎片一起飞走；最后残余的中间小块自己烧尽，底下透出新立绘（缩放冲击）。
// slashes[k] = vec4(法线x, 法线y, 截距c, 起刀时刻)，由 GDScript 随机种子生成。

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.0;
uniform vec4 slashes[5];
uniform float seed_n = 0.0;

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

	// 新立绘：登场缩放冲击（碎片飞完时落定）
	float punch = 1.0 + 0.08 * exp(-abs(progress - 0.6) * 9.0);
	vec2 nuv = (UV - vec2(0.5)) / punch + vec2(0.5);
	vec4 next_c = texture(tex_next, nuv);
	vec4 col = next_c;

	float keep_all = 1.0;
	float n = vnoise(UV * 9.0 + vec2(seed_n * 37.0)) * 0.85
			+ vnoise(UV * 23.0 + vec2(seed_n * 11.0)) * 0.15;
	float char_tex = vnoise(UV * 31.0 + vec2(11.0));
	vec3 char_col = vec3(0.03, 0.024, 0.03) + vec3(char_tex * 0.06);
	vec3 ember_col = vec3(1.0, 0.42, 0.10) * (1.1 + 0.6 * vnoise(UV * 40.0 + vec2(TIME * 3.0)));
	float end_fade = 1.0 - smoothstep(0.9, 1.0, progress);

	for (int k = 0; k < 5; k++) {
		vec4 s = slashes[k];
		float d = dot(q, s.xy) - s.z;          // >0 = 被这一刀切走的一侧

		// ① 斩线白光：起刀后 0.07 进度内闪一下
		float tw = clamp((progress - s.w) / 0.07, 0.0, 1.0);
		float streak = exp(-abs(d) * 16.0) * (1.0 - tw) * step(0.001, progress)
				* step(s.w, progress);
		col.rgb += vec3(1.0) * streak * 0.95;

		// ② 斩痕：劈下后留着的细亮线 + 暗缝（第一阶段满屏都是痕，碎片起飞后跟着飞走淡出）
		float ft2 = clamp((progress - 0.30 - float(k) * 0.02) / 0.40, 0.0, 1.0);
		float scar_a = step(s.w, progress) * (1.0 - ft2);
		float scar_core = exp(-abs(d) * 60.0);
		float scar_seam = exp(-abs(d) * 18.0);
		col.rgb = mix(col.rgb, vec3(0.92, 0.96, 1.0), scar_core * scar_a * 0.7);
		col.rgb = mix(col.rgb, vec3(0.05, 0.05, 0.09), scar_seam * scar_a * 0.35);

		// ③ 第 k 片 = 前 k 刀都保留、且在第 k 刀的被切侧：第二阶段统一边飞边烧
		float is_piece = keep_all * step(0.0, d);
		if (is_piece > 0.5) {
			float ft = clamp((progress - 0.30 - float(k) * 0.02) / 0.42, 0.0, 1.0);
			float fly = 1.87 * (1.0 - pow(1.0 - ft, 2.0));
			vec2 off = s.xy * fly;
			float burn_t = clamp((progress - 0.34 - float(k) * 0.02) / 0.38, 0.0, 1.0);
			float dnb = n - burn_t;
			vec4 prev_c = texture(tex_prev, UV - off);
			vec3 pc;
			float pa;
			if (dnb > 0.06) {
				pc = prev_c.rgb;
				pa = 1.0;
			} else if (dnb > 0.0) {
				pc = mix(ember_col, prev_c.rgb, dnb / 0.06);
				pa = 1.0;
			} else if (dnb > -0.26) {
				pc = char_col;
				pa = 1.0;
			} else {
				pc = char_col;
				pa = smoothstep(-0.42, -0.26, dnb);
			}
			pa *= end_fade;
			col = mix(col, vec4(pc, 1.0), clamp(pa, 0.0, 1.0));
		}
		keep_all *= (1.0 - step(0.0, d));
	}

	// 残余区：所有刀都留下的中间小块，最后自己烧尽（微微漂移）
	if (keep_all > 0.5) {
		float bt = clamp((progress - 0.42) / 0.42, 0.0, 1.0);
		float dnb = n - bt;
		vec2 drift = vec2(0.12, 0.2) * bt;
		vec4 prev_c = texture(tex_prev, UV - drift);
		vec3 pc;
		float pa;
		if (dnb > 0.06) {
			pc = prev_c.rgb;
			pa = 1.0;
		} else if (dnb > 0.0) {
			pc = mix(ember_col, prev_c.rgb, dnb / 0.06);
			pa = 1.0;
		} else if (dnb > -0.26) {
			pc = char_col;
			pa = 1.0;
		} else {
			pc = char_col;
			pa = smoothstep(-0.4, -0.26, dnb);
		}
		pa *= end_fade;
		col = mix(col, vec4(pc, 1.0), clamp(pa, 0.0, 1.0));
	}

	COLOR = col;
}
