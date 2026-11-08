shader_type canvas_item;
render_mode unshaded;

// 水波扩散转场（2026-11-08 试验版，主人钦定）：
// 从立绘中心的「水波形状不规则圆」向外扩散，波内显现新立绘——
// 边缘 = 径向进度 + 三层角向正弦花瓣（整数倍角频，无接缝）+ uv 噪声细碎，
// 波外留衰减波纹余韵（亮度调制 + 折射），波前一条水面高光线。
// 参考素材：noise 扰动阈值揭示（liquid reveal）+ 角向花瓣边缘。
//
// 用法（RippleSwapPortrait 控件封装）：
//   tex_prev/tex_next 同宽高比；progress 0→1 由 GDScript tween 推进；
//   aspect/max_dist 由控件按自身尺寸算好传入。

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.0;        // 宽/高：把距离场修成圆
uniform float max_dist = 0.9;      // 中心到最远角（aspect 校正后）
uniform float wobble = 0.10;       // 水波边缘不规则幅度（uv 单位）
uniform float edge_w = 0.05;       // 波前过渡带宽度
uniform float ring_strength = 0.3; // 波纹余韵亮度强度

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.x *= aspect;
	float d = length(p);
	float ang = atan(p.y, p.x);

	// 三层角向正弦（5/9/13 倍角频）→ 有机花瓣状水波边缘；随进度缓缓旋进
	float petals = sin(ang * 5.0 + progress * 5.0) * 0.45
			+ sin(ang * 9.0 - progress * 3.0) * 0.30
			+ sin(ang * 13.0 + progress * 8.0) * 0.25;
	float fine = (vnoise(UV * 9.0 + progress * 2.0) - 0.5) * 0.8;

	float r = progress * (max_dist + wobble * 2.0 + edge_w);
	float grow = clamp(progress * 8.0, 0.0, 1.0);   // progress=0 时把花瓣幅度压到 0，保证初始整张是旧图
	float edge = r + (petals * 0.7 + fine) * wobble * grow;

	float dist_e = d - edge;
	float inside = 1.0 - smoothstep(-edge_w * 0.6, edge_w * 0.6, dist_e); // 1 = 波内（新图）
	float outside = 1.0 - inside;

	// 波纹余韵只在波外（旧图一侧）：波内必须干净，否则同心环会把新立绘搅成紫白螺旋；
	// normalize(p) 在中心附近方向乱跳（白星爆元凶），outside 门控顺带治好它
	float ring = sin(dist_e * 42.0 - progress * 7.0) * exp(-abs(dist_e) * 9.0) * outside * grow;
	vec2 refr = normalize(p + vec2(1e-5)) * ring * 0.014;

	vec4 prev_c = texture(tex_prev, UV + refr);
	vec4 next_c = texture(tex_next, UV);
	vec4 col = mix(prev_c, next_c, inside);

	// 2026-11-08 主人指示：去掉波前高光描边——水波只靠形状与折射余韵表达
	col.rgb *= 1.0 + ring * ring_strength;

	COLOR = col;
}
