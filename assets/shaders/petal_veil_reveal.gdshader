shader_type canvas_item;
// 千问专属转场：白色花瓣从左下角涌出、直奔右上，密集到遮满全屏后散开露出新立绘。
// （2026-11-11 主人要求，t2-qwen-petals）
//
// 为什么走 shader 而不是 Sprite2D 粒子：
//   · 本项目的转场架构是「一个 ColorRect + ShaderMaterial + progress」，
//     走同一套枚举/字典就能直接复用 swap_to / debug_prepare / debug_set_progress，
//     不用为它单独接一套节点生命周期；
//   · 花瓣要「密到遮满」，节点方案要几十上百个 Sprite 才够，shader 里是零节点；
//   · 逐帧验收（debug_set_progress）对 shader 是纯函数式的，像素可复现。
//
// ⚠ gl_compatibility 约束（本机实测踩过）：顶点着色器里 texture() 采样无效，
//   所以这里所有采样都只在 fragment；不要为了省 ALU 把它挪到 vertex()。
//
// 遮挡语义：三层花瓣在 progress 峰值区间会重叠到几乎无缝，
// 再叠一层白幕（veil）把剩余缝隙补满 —— swap 时才敢在 p≈0.56 处换图。

render_mode blend_mix;

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
// 花瓣图集：4×4 共 16 片（assets/art/fx/petals-sheet.png，透明底）
uniform sampler2D tex_petal : source_color, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.7777778;

// ── 手感参数（默认值即验收通过的组合，调参面板可覆写）──
uniform float density : hint_range(0.2, 1.0) = 0.92;   // 花瓣出现概率
uniform float petal_scale : hint_range(0.15, 2.0) = 1.0; // 花瓣尺寸（1.0 = 占满格子）
uniform float travel : hint_range(0.0, 3.0) = 1.0;     // 沿对角线行程
uniform float veil_gain : hint_range(0.0, 1.0) = 0.92; // 白幕浓度（补缝用）
uniform float seed : hint_range(0.0, 64.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 从 4×4 图集里取第 idx 片花瓣；local ∈ [0,1]^2
// ⚠ 图集里每片花瓣本体只占格子的 45~64%（生成时留了间距）。要让花瓣铺满
//   自己的四边形，采样窗口必须**收缩**到花瓣本体：local 0..1 映射到
//   cell 的 0.5±PETAL_INNER/2。写反成放大（>1）会采到格子边缘并被 clamp
//   成一圈糊边，花瓣反而缩小 —— 第一版就是这样变成「小圆点」的。
const float PETAL_INNER = 0.58;

vec4 sample_petal(float idx, vec2 local) {
	float i = floor(mod(idx, 16.0));
	vec2 cell = vec2(mod(i, 4.0), floor(i * 0.25));
	vec2 fit = 0.5 + (clamp(local, 0.0, 1.0) - 0.5) * PETAL_INNER;
	vec2 uv = (cell + clamp(fit, 0.002, 0.998)) * 0.25;
	return texture(tex_petal, uv);
}

// 单个花瓣层：返回 (预乘 rgb, alpha)
// 每个格子放一片，格子随 progress 沿「左下→右上」平移 → 视觉上就是整片花雨在飞。
// ⚠ scale 是「屏幕短边方向上有多少格」：格子边长 = 1/scale 个画面高。
//   连同 PETAL_FIT 放大后，单片直径 ≈ (1.85/scale) 画面高。
//   scale=5.2 → 约 35% 画面高（一片就很有存在感），靠三层错位铺满。
vec4 petal_layer(vec2 uv, float fk) {
	float scale = 5.2 + fk * 2.1;
	float speed = 1.05 + fk * 0.42;

	vec2 dir = normalize(vec2(aspect, -1.0));
	vec2 sp = vec2(uv.x * aspect, uv.y);
	// 位移直接按「格」计（不再乘 scale）：progress=1 时约走一个屏高，
	// 视觉上是花瓣飞过去、新花瓣从后面补上，而不是整片网格平移后露出空白。
	// 再加一层「逐格抖动」：每个格子的整格位移随格子 id 随机偏移，
	// 格线因此被打散 —— 否则相邻花瓣永远保持同样的相对位置，平铺感消不掉。
	// ⚠ 抖动幅度不能超过格子的「花瓣不重叠余量」：offset 让 warp 在格边界处
	//   不连续，过大会把花瓣整片切开、在屏幕上看成方块硬边（实测 0.85 就会）。
	//   0.35 足够打散朝向，又不会把格缝露出来。
	vec2 warp_src = sp * scale;
	vec2 wcell = floor(warp_src);
	vec2 jitter = vec2(
		hash21(wcell + fk * 17.3 + seed) - 0.5,
		hash21(wcell + fk * 71.9 + seed) - 0.5) * 0.35;
	vec2 q = warp_src + jitter - dir * progress * travel * speed * 8.0;

	vec2 cell = floor(q);
	vec2 f = fract(q);

	float r1 = hash21(cell + fk * 13.7 + seed);
	float r2 = hash21(cell + fk * 47.3 + seed);
	float r3 = hash21(cell + fk * 91.1 + seed);
	float r4 = hash21(cell + fk * 29.3 + seed);
	float r5 = hash21(cell + fk * 61.9 + seed);

	// 稀疏门槛：这一格是否长花瓣
	if (r1 > density) {
		return vec4(0.0);
	}

	// 花瓣中心在格内大幅抖动（0.15~0.85）。只抖 ±0.14 会排成规整网格，
	// 一眼就看出是平铺重复 —— 必须抖到接近整格，再靠旋转打散朝向。
	vec2 pc = vec2(0.15 + r2 * 0.70, 0.15 + r3 * 0.70);
	vec2 d = f - pc;

	// 自转：progress 推进时越转越快，且方向按 r1 分两批
	float spin = progress * (2.2 + r5 * 7.0) * ((r1 > 0.5) ? 1.0 : -1.0);
	float ang = r4 * 6.28318 + spin;
	float ca = cos(ang);
	float sa = sin(ang);
	vec2 dr = vec2(d.x * ca - d.y * sa, d.x * sa + d.y * ca);

	// 尺寸：petal_scale 是「花瓣直径占格子边长的比例」的倍率。
	// 基础取 0.62~0.92（不是接近 1.0）：相邻格的花瓣尺寸差够大，
	// 平铺感才会被打散；遮幕靠三层叠加 + 白幕补缝来完成。
	float s = petal_scale * (0.62 + r5 * 0.30) * (1.0 - fk * 0.07);
	vec2 local = dr / max(s, 1e-4) + 0.5;
	// 注：local 是「花瓣自身 uv」，所以 dr 的一半（0.5s）就是花瓣半径。

	// 只在实际占位范围内采样（atlas 每格有留白，形状不会被切）
	if (local.x <= 0.0 || local.x >= 1.0 || local.y <= 0.0 || local.y >= 1.0) {
		return vec4(0.0);
	}

	vec4 pt = sample_petal(floor(r5 * 15.999), local);
	if (pt.a <= 0.004) {
		return vec4(0.0);
	}
	// 近层稍实，远层淡一点，制造纵深
	float depth_a = 0.80 + fk * 0.07;
	return vec4(pt.rgb * pt.a * depth_a, pt.a * depth_a);
}

void fragment() {
	vec2 uv = UV;
	vec4 base = texture(tex_prev, uv);

	// 波前：progress 越大，可出现的区域越靠右上（花瓣「先从左下长出来」）
	float T = (uv.x + (1.0 - uv.y)) * 0.5;
	float front = smoothstep(T - 0.34, T + 0.02, progress * 1.85);

	// gate：0→满→0，控制花瓣的密度/尺寸/亮度整体起伏
	//   0.00~0.46 涌出并铺满（这个区间结束时屏幕已被遮住）
	//   0.46~0.60 满屏定住（swap 就发生在这里）
	//   0.60~1.00 散开露出新立绘
	float gate = smoothstep(0.0, 0.46, progress) * (1.0 - smoothstep(0.60, 1.0, progress));

	vec4 acc = vec4(0.0);
	// 三层：远→近（近层盖在上面）。acc 用预乘 alpha，over 合成不会在边缘发灰。
	for (int k = 0; k < 3; k++) {
		vec4 pl = petal_layer(uv, float(k));
		pl.a *= front * gate;
		pl.rgb *= front * gate;
		acc.rgb = pl.rgb + acc.rgb * (1.0 - pl.a);
		acc.a = pl.a + acc.a * (1.0 - pl.a);
	}

	// 白幕：把花瓣之间漏出来的缝隙补掉，保证 p≈0.56 换图时绝对看不到旧图
	float veil = smoothstep(0.30, 0.50, progress) * (1.0 - smoothstep(0.58, 0.80, progress));
	// 花瓣本体也是白的：它自己也出一份遮挡力，和白幕取并集（不是相加，
	// 否则两者叠加处会过曝成死白，散开段还会留下一层洗白的雾）
	float cover = 1.0 - (1.0 - clamp(veil * veil_gain, 0.0, 1.0)) * (1.0 - clamp(acc.a, 0.0, 1.0));
	// 花瓣色提亮到纯白（图集是白瓣，仍按 acc 的覆盖度混进去）
	vec3 petal_rgb = vec3(1.0);
	vec3 out_rgb = mix(base.rgb, petal_rgb, cover);

	COLOR = vec4(out_rgb, 1.0);
}
