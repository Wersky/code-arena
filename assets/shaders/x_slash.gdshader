shader_type canvas_item;
render_mode unshaded;

// 乱斩转场 v11（2026-11-09，Grock 专属，主人定稿）：
// 把「整张图燃烧」那套漂亮特效**逐块复制**——每个被斩出的碎块有自己独立的
// 噪声火场与前缘，各自烧穿（火线橙红 -> 短暂焦黑 -> 烧净露新立绘），互不同步。
// 1 五刀四面八方依次劈下，在完整旧立绘上留斩痕
// 2 停顿后各碎块按自己的火场燃烧殆尽（每块噪声相位不同，形态各异）
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

// 一个碎块的燃烧：本地噪声火场 + 前缘推进（与整图版同样的三段：火线/焦黑/烧净）
vec3 burn_piece(vec3 base, vec3 next_rgb, vec2 uv, float bt, float phase) {
	float n1 = vnoise(uv * 7.0 + vec2(phase * 13.7, phase * 4.1));
	float n2 = vnoise(uv * 21.0 + vec2(phase * 7.3, phase * 9.5));
	// 有机燃烧场：下限抬到 0.22（噪声天然会取到接近 0，会导致「一开始就烧穿了」），
	// 保证 bt=0（front=0）时没有任何像素被判为已烧
	float field = 0.22 + (n1 * 0.62 + n2 * 0.38) * 0.78;

	float ignite = smoothstep(0.0, 0.18, bt);      // 点火渐亮：起步不冒火
	float front = clamp(bt, 0.0, 1.0) * 1.25;     // 略超 1，保证整块烧透
	float burned = step(field, front);            // 1 = 已烧过
	float behind = front - field;                 // 烧过多久
	float ahead = field - front;                  // 离火线还多远

	vec3 ember = vec3(1.0, 0.42, 0.10)
			* (1.15 + 0.55 * vnoise(uv * 45.0 + vec2(TIME * 4.0 + phase)));
	vec3 char_c = vec3(0.045, 0.035, 0.038);

	// 火线：只在前缘前方一窄条
	float flame = (1.0 - burned) * (1.0 - smoothstep(0.0, 0.16, ahead));
	vec3 col = mix(base, ember, flame * 0.95);

	// 刚烧过的一小段短暂焦黑
	float char_t = burned * (1.0 - smoothstep(0.10, 0.30, behind));
	col = mix(col, char_c, char_t * 0.88 * ignite);

	// 焦黑退掉 -> 新立绘
	float clear_mask = burned * (1.0 - char_t);
	col = mix(col, next_rgb, clear_mask);
	return col;
}

void fragment() {
	vec2 q = (UV - vec2(0.5)) * vec2(aspect, 1.0);

	// 新立绘（登场缩放冲击）
	float punch = 1.0 + 0.08 * exp(-abs(progress - 0.82) * 9.0);
	vec2 nuv = (UV - vec2(0.5)) / punch + vec2(0.5);
	vec3 next_rgb = texture(tex_next, nuv).rgb;

	// --- 1 旧立绘 + 斩痕 ---
	vec3 col = texture(tex_prev, UV).rgb;

	for (int k = 0; k < 5; k++) {
		vec4 s = slashes[k];
		float d = dot(q, s.xy) - s.z;

		float tw = clamp((progress - s.w) / 0.07, 0.0, 1.0);
		float streak = exp(-abs(d) * 16.0) * (1.0 - tw) * step(0.001, progress)
				* step(s.w, progress);
		col += vec3(1.0) * streak * 0.95;

		float scar_a = step(s.w, progress) * (1.0 - smoothstep(0.55, 0.72, progress));
		col = mix(col, vec3(0.92, 0.96, 1.0), exp(-abs(d) * 60.0) * scar_a * 0.7);
		col = mix(col, vec3(0.05, 0.05, 0.09), exp(-abs(d) * 18.0) * scar_a * 0.35);
	}

	// --- 2 各碎块按自己的火场烧穿 ---
	float keep_all = 1.0;
	for (int k = 0; k < 5; k++) {
		vec4 s = slashes[k];
		float d = dot(q, s.xy) - s.z;
		float is_piece = keep_all * step(0.0, d);
		if (is_piece > 0.5) {
			// 每块错峰点火（0.34 起，每块 +0.025），错峰很小保证同时段整体烧
			float bt = clamp((progress - 0.38 - float(k) * 0.03) / 0.50, 0.0, 1.0);
			col = burn_piece(col, next_rgb, UV, bt, float(k) * 7.31 + seed_n);
		}
		keep_all *= (1.0 - step(0.0, d));
	}

	// 残余中心块：同样的燃烧，稍晚一点
	if (keep_all > 0.5) {
		float bt = clamp((progress - 0.44) / 0.48, 0.0, 1.0);
		col = burn_piece(col, next_rgb, UV, bt, seed_n + 41.7);
	}

	COLOR = vec4(col, 1.0);
}
