shader_type canvas_item;
render_mode unshaded;

// X 双斩转场（2026-11-08，Grock 专属）：扛 X 巨斧的毒舌小恶魔——
// 两道剑光沿对角线交叉劈过（↘↙），旧立绘被 X 线切成四片，各自沿对角滑开坠落，
// 缝里透出新立绘；斩缝留一线暗红残光。

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.0;

void fragment() {
	vec2 q = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	// 两道斩线的垂直投影：↘ 线（x−y=c）与 ↙ 线（x+y=c）
	float d1 = (q.x - q.y) * 0.7071;
	float d2 = (q.x + q.y) * 0.7071;

	// ① 斩击闪线：亮线各从一角扫到对角（第一道 0~0.36，第二道 0.2~0.5）
	float sw1 = mix(-1.3, 1.3, clamp(progress / 0.32, 0.0, 1.0));
	float sw2 = mix(1.3, -1.3, clamp((progress - 0.22) / 0.32, 0.0, 1.0));
	float slash1 = exp(-abs(d1 - sw1) * 26.0) * step(0.001, progress) * step(progress, 0.36);
	float slash2 = exp(-abs(d2 - sw2) * 26.0) * step(0.2, progress) * step(progress, 0.5);

	// ② 四象限被 X 线切开，各自沿对角方向滑开 + 下片带坠感
	float split = smoothstep(0.42, 0.95, progress);
	float side1 = step(0.0, d1);
	float side2 = step(0.0, d2);
	vec2 dir = normalize(vec2(side1 * 2.0 - 1.0, side2 * 2.0 - 1.0) + vec2(0.001, 0.001));
	float grav = (side2 > 0.5) ? 0.35 : -0.12;
	vec2 off = (dir * 1.25 + vec2(0.0, grav)) * split;
	float old_a = 1.0 - smoothstep(0.8, 1.0, progress); // 尾段旧图整体退场，盖住滑动采样拖尾

	vec4 prev_c = texture(tex_prev, UV - off);
	vec4 next_c = texture(tex_next, UV);
	vec4 col = mix(next_c, prev_c, old_a);

	// 斩缝暗红残光（X 线在 0.3~0.85 间可见，随后熄灭）
	float cut_vis = smoothstep(0.3, 0.45, progress) * (1.0 - smoothstep(0.85, 1.0, progress));
	float cut = exp(-abs(d1) * 30.0) + exp(-abs(d2) * 30.0);
	col.rgb += vec3(1.0, 0.25, 0.3) * cut * cut_vis * 0.55;

	// 剑光本体（白）
	col.rgb += vec3(1.0) * (slash1 + slash2) * 0.9;

	COLOR = col;
}
