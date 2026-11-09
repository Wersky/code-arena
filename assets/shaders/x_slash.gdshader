shader_type canvas_item;
render_mode unshaded;

// 乱斩转场 v12（2026-11-09，Grock 专属，主人定稿）：
// 1 五刀四面八方依次劈下，在完整旧立绘上留斩痕（细亮线+暗缝）
// 2 停顿后：**统一燃烧速度**——所有碎块共用同一条时间曲线，各自从**自己的外边界**
//    （切口线 / 画框边）向内烧（到边界距离场驱动），火线橙红 -> 短暂焦黑 -> 烧净露新立绘；
//    时间到（progress≈1）全部碎块烧毁，无残留。
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

	// 新立绘（登场缩放冲击）
	float punch = 1.0 + 0.08 * exp(-abs(progress - 0.82) * 9.0);
	vec2 nuv = (UV - vec2(0.5)) / punch + vec2(0.5);
	vec3 next_rgb = texture(tex_next, nuv).rgb;

	// ---- 1 旧立绘 + 斩痕 ----
	vec3 col = texture(tex_prev, UV).rgb;

	for (int k = 0; k < 5; k++) {
		vec4 s = slashes[k];
		float d = dot(q, s.xy) - s.z;

		// 斩线白光：起刀后 0.07 进度内闪一下
		float tw = clamp((progress - s.w) / 0.07, 0.0, 1.0);
		float streak = exp(-abs(d) * 16.0) * (1.0 - tw) * step(0.001, progress)
				* step(s.w, progress);
		col += vec3(1.0) * streak * 0.95;

		// 斩痕：燃烧全程保留为**暗缝**——它是碎块之间的分界，让人看得出「各块独立在烧」
		float scar_a = step(s.w, progress) * (1.0 - smoothstep(0.86, 0.96, progress));
		col = mix(col, vec3(0.92, 0.96, 1.0), exp(-abs(d) * 60.0) * scar_a * 0.55);
		col = mix(col, vec3(0.02, 0.02, 0.04), exp(-abs(d) * 26.0) * scar_a * 0.72);
	}

	// ---- 2 该像素所属碎块 + 到「自己边界」的距离 ----
	// 第 k 片的边界 = 画框四边 + d_0..d_k 这些切口线；残余中心块的边界 = 画框 + 全部 5 条线
	float bd = 10.0;     // 到本块边界的最短距离（= 燃烧起点，外侧为 0）
	float owner = -1.0;  // 所属块编号（-1 = 残余中心块）
	float keep_all = 1.0;
	for (int k = 0; k < 5; k++) {
		vec4 s = slashes[k];
		float d = dot(q, s.xy) - s.z;
		if (owner < 0.0) {
			bd = min(bd, abs(d));                       // 这条切口线是本块的边界
			if (keep_all > 0.5 && d > 0.0) {
				owner = float(k);                       // 本块确定为第 k 片
			} else {
				keep_all *= (1.0 - step(0.0, d));
			}
		}
	}
	// 边界只用切口线（不含画框边）：这样每条切口的**两侧**各烧各的，
	// 接缝处两条火线相向推进/对撞，视觉上才看得出「碎块各自独立在烧」。
	// 画框边只在不属于任何切口时兜底（避免最外层块永远烧不到）
	bd = min(bd, 0.52);

	// 有机烧沿（每块自己的噪声相位，形态各异；速度仍统一）
	float phase = (owner < 0.0) ? seed_n + 41.7 : owner * 13.7 + seed_n;
	bd += (vnoise(UV * 8.0 + vec2(phase)) - 0.5) * 0.085
			+ (vnoise(UV * 26.0 + vec2(phase * 2.3)) - 0.5) * 0.035;

	// ---- 3 统一燃烧时间轴：所有碎块同一速度，各自由外向内 ----
	float bt = clamp((progress - 0.38) / 0.55, 0.0, 1.0);   // 统一速度，不错峰
	float ignite = smoothstep(0.0, 0.15, bt);               // 点火渐亮（起步不冒火）
	// 前缘：线性推进但用平方缓入，前半段慢（能看到火线在内部游走）、尾段加速收净；
	// 系数保证 bt=1 时超过最大边界距离（中心最深 ≈0.45）→ 全部烧毁
	float front = (0.22 * bt + 0.48 * bt * bt);   // bt=1 → 0.70 > 0.52，所有块烧尽

	float burned = step(bd, front);                          // 1 = 已烧过（由外向内）
	float behind = front - bd;
	float ahead = bd - front;

	vec3 ember = vec3(1.0, 0.42, 0.10)
			* (1.15 + 0.55 * vnoise(UV * 45.0 + vec2(TIME * 4.0 + phase)));
	vec3 char_c = vec3(0.045, 0.035, 0.038);

	// 火线：前缘前方一窄条（收窄，火沿更锐，各块的火边看得清）
	float flame = (1.0 - burned) * (1.0 - smoothstep(0.0, 0.10, ahead));
	col = mix(col, ember, flame * 0.95 * ignite);

	// 刚烧过的一小段短暂焦黑
	float char_t = burned * (1.0 - smoothstep(0.10, 0.30, behind));
	col = mix(col, char_c, char_t * 0.88 * ignite);

	// 焦黑退掉 -> 新立绘
	col = mix(col, next_rgb, burned * (1.0 - char_t));

	COLOR = vec4(col, 1.0);
}
