shader_type canvas_item;
render_mode unshaded;

// 乱斩转场 v10（2026-11-08，Grock 专属，主人定稿「全部燃烧」）：
// 1 五刀四面八方依次劈下，在完整的旧立绘上留下斩痕（细亮线+暗缝）
// 2 停顿后：整张立绘作为一整体开始燃烧——噪声火线斜扫过全图（不分碎块）
//   火线橙红 -> 刚烧过的一小段短暂焦黑 -> 彻底烧净露新立绘（带登场缩放冲击）
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

	// --- 1 旧立绘 + 斩痕 ---
	vec4 prev_c = texture(tex_prev, UV);
	vec3 col = prev_c.rgb;

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

	// --- 2 整张图燃烧：噪声火线斜扫全图 ---
	float sweep = (UV.x * 0.55 + (1.0 - UV.y) * 0.45);
	float n = vnoise(UV * 7.0 + vec2(seed_n * 19.0));
	float n2 = vnoise(UV * 21.0 + vec2(seed_n * 43.0));
	float field = sweep * 0.62 + n * 0.28 + n2 * 0.10;

	float bt = clamp((progress - 0.34) / 0.62, 0.0, 1.0);
	float front = bt * 1.12;

	vec3 ember_col = vec3(1.0, 0.42, 0.10)
			* (1.15 + 0.55 * vnoise(UV * 45.0 + vec2(TIME * 4.0)));
	vec3 char_col = vec3(0.045, 0.035, 0.038);

	float burned = step(field, front);
	float behind = front - field;          // 已烧过多久（>0 = 已烧）
	float ahead = field - front;           // 离火线还多远（>0 = 未烧）

	// 火焰只在前缘前方一窄条（0.16 内），其余未烧区域保持原图
	float flame = (1.0 - burned) * (1.0 - smoothstep(0.0, 0.16, ahead));
	col = mix(col, ember_col, flame * 0.95);

	float char_t = burned * (1.0 - smoothstep(0.10, 0.30, behind));
	col = mix(col, char_col, char_t * 0.88);

	// --- 3 烧尽区 -> 新立绘 ---
	float punch = 1.0 + 0.08 * exp(-abs(progress - 0.82) * 9.0);
	vec2 nuv = (UV - vec2(0.5)) / punch + vec2(0.5);
	vec3 next_rgb = texture(tex_next, nuv).rgb;
	float clear_mask = burned * (1.0 - char_t);
	col = mix(col, next_rgb, clear_mask);

	COLOR = vec4(col, 1.0);
}
