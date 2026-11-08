shader_type canvas_item;
render_mode unshaded;

// 乱斩转场 v9（2026-11-08，Grock 专属，主人定稿「纸片燃烧」模型）：
// ① 全部斩击依次劈下，在**旧立绘**上留下斩痕（细亮线+暗缝）
// ② 停顿后：每一条斩痕 + 画框四边**同时着火**——宽火焰区沿所有边界向内推进
//    （像素到最近边界的距离场驱动，像纸从四边烧向中心），烧过即净见新立绘，无黑渣。
// 合成顺序（v9 修正）：旧立绘+斩痕 → 火焰带叠加 → 已烧区替换为新立绘。
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

	vec3 ember_col = vec3(1.0, 0.42, 0.10) * (1.1 + 0.6 * vnoise(UV * 40.0 + vec2(TIME * 3.0)));

	// ── ① 旧立绘 + 斩痕（全部在旧图上叠加）──────────────────────
	vec4 prev_c = texture(tex_prev, UV);
	vec3 col = prev_c.rgb;

	float bd = 2.0;   // 到最近边界（斩线或画框边缘）的距离
	for (int k = 0; k < 5; k++) {
		vec4 s = slashes[k];
		float d = dot(q, s.xy) - s.z;
		bd = min(bd, abs(d));

		// 斩线白光：起刀后 0.07 进度内闪一下
		float tw = clamp((progress - s.w) / 0.07, 0.0, 1.0);
		float streak = exp(-abs(d) * 16.0) * (1.0 - tw) * step(0.001, progress)
				* step(s.w, progress);
		col += vec3(1.0) * streak * 0.95;

		// 斩痕：细亮线 + 暗缝（燃烧开始后淡出）
		float scar_a = step(s.w, progress) * (1.0 - smoothstep(0.55, 0.7, progress));
		col = mix(col, vec3(0.92, 0.96, 1.0), exp(-abs(d) * 60.0) * scar_a * 0.7);
		col = mix(col, vec3(0.05, 0.05, 0.09), exp(-abs(d) * 18.0) * scar_a * 0.35);
	}

	// 画框四边也是边界
	bd = min(bd, min(0.5 * aspect - abs(q.x), 0.5 - abs(q.y)));
	// 有机烧沿：加噪声抖动
	bd += (vnoise(UV * 9.0 + vec2(seed_n * 23.0)) - 0.5) * 0.05
			+ (vnoise(UV * 28.0 + vec2(seed_n * 7.0)) - 0.5) * 0.02;

	// ── ② 纸片燃烧：火焰区沿所有边界向内推进 ───────────────────
	float bt = clamp((progress - 0.26) / 0.60, 0.0, 1.0);
	float front = bt * 0.45;
	float ignite = smoothstep(0.0, 0.25, bt);
	float burn_mask = step(bd, front);                       // 1 = 已烧尽
	float band_t = clamp((bd - front) / 0.22, 0.0, 1.0);     // 0=火线 1=未烧
	float band_mask = (1.0 - burn_mask) * step(front, bd);

	// 火焰区：以火色为主，靠未烧侧渐回纸面
	vec3 band_col = mix(ember_col * 1.15, col, band_t * 0.55);
	band_col *= 0.9 + 0.25 * vnoise(UV * 55.0 + vec2(TIME * 5.0));
	col = mix(col, band_col, band_mask * ignite);

	// ── ③ 已烧尽区域 → 新立绘（带登场缩放冲击）────────────────
	float punch = 1.0 + 0.08 * exp(-abs(progress - 0.8) * 9.0);
	vec2 nuv = (UV - vec2(0.5)) / punch + vec2(0.5);
	vec3 next_rgb = texture(tex_next, nuv).rgb;
	col = mix(col, next_rgb, burn_mask);

	COLOR = vec4(col, 1.0);
}
