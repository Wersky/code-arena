shader_type canvas_item;
render_mode unshaded;

// 像素扇布透明转场 v8（2026-11-08，Kweno 专属，主人定稿「要水波那种透明」）：
// 一开始扇子就是「左下→右上」的一条对角线；转场开始后扇形区域**向两边展开**，
// 展开的区域里**直接透出新立绘**（透明揭示，不是实心布）——扇子的存在感靠：
// 波浪扇沿的深色描边 + 放射状褶皱压暗 + 两侧开花前缘金光。盖满（背后已换图）
// 后逆向收回对角线，露出新立绘。

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
uniform float sweep : hint_range(0.0, 1.0) = 0.0;    // 0=对角线 1=盖满
uniform float dim : hint_range(0.0, 1.0) = 0.0;      // 扇面之外的压暗
uniform float aspect = 1.0;
uniform vec2 pivot_s = vec2(0.06, 0.94);             // 画面侧扇轴（左下，uv）
uniform float a_start = -95.0;                       // 起始边角（度）：底边侧
uniform float a_end = 8.0;                           // 终止边角（度）：另一边侧

uniform float a_mid_t = -59.0;                       // 贴图角中位（度）
// 扇布外沿半径。**必须 >= 画框最远角到扇轴的距离**，否则扫不到角落、盖不满全屏。
// pivot_s=(0.06,0.94)、aspect=16/9 时：左下 0.12 / 左上 0.95 / 右下 1.67 / 右上 1.92，
// 取 2.00 保证四个角全被覆盖（实测原值 1.02 会让右上角约一半面积扫不到）。
uniform float fan_r = 2.00;
uniform float blades = 12.0;                         // 扇骨尖数（波浪边沿瓣数）
uniform float r_scale = 0.6;                         // 屏幕半径 → 布贴图采样半径

void fragment() {
	// ── 扇面判定用**向量叉积**，不用 atan2 ──
	// 为什么：扇轴在左下角时画面可见角跨度接近 360°，atan2 的返回值在 ±180 处
	// 会绕回，角度数值比较必然出错（实测被切成 2~4 个分离色块）。
	// 叉积只关心方向向量的相对顺逆时针关系，天然无环绕问题。
	vec2 q = (UV - pivot_s) * vec2(aspect, 1.0);
	float r = length(q);
	vec2 d = q / max(r, 1.0e-6);          // 单位方向

	float a_s = radians(a_start);
	float a_e = radians(a_end);
	float a_f = mix(a_s, a_e, clamp(sweep, 0.0, 1.0));   // 前缘方向（从起始边扫向终止边）
	vec2 dir_s = vec2(cos(a_s), sin(a_s));
	vec2 dir_e = vec2(cos(a_e), sin(a_e));
	vec2 dir_f = vec2(cos(a_f), sin(a_f));

	// cross(v, d) > 0  ⇒ d 在 v 的逆时针侧
	float c_front = dir_f.x * d.y - dir_f.y * d.x;
	float c_end   = dir_e.x * d.y - dir_e.y * d.x;
	float c_start = dir_s.x * d.y - dir_s.y * d.x;

	// 角度带为 [a_end, a_start]（角度递减）。d 在带内 ⇔
	//   d 在 a_start 的顺时针侧（c_start <= 0）且 在 a_end 的逆时针侧（c_end >= 0）
	float in_cone = step(c_start, 0.0) * step(0.0, c_end);
	// 已展开 ⇔ d 已越过前缘（c_front <= 0）
	float passed = step(c_front, 0.0);
	float in_fan = in_cone * passed;

	// ── 弧沿（扇骨波浪边）只在展开早期有意义 ──
	float span = a_s - a_e;
	float blades_n = max(blades, 1.0);
	// 用方向角在带内的相对位置（atan 只在**带内**使用，跨度 <= 180° 不会绕回）
	float rel = clamp((atan(d.y, d.x) - a_e) / max(span, 1.0e-4), 0.0, 1.0);
	float cwave = cos(rel * blades_n * 3.14159);
	float r_edge = fan_r * (0.90 + 0.10 * cwave);
	float crease = (1.0 + cwave) * 0.5;

	// 半径门限：早期限制在弧沿内（扇形有边），末段放开保证整屏覆盖
	float r_gate = mix(r_edge, 1.0e9, smoothstep(0.40, 0.92, sweep));
	in_fan *= step(r, r_gate);

	// ── 末段补满：扇形只覆盖中心扇面，画面四角不在带内 ──
	// 线性过渡到「全屏都是新图」，保证 sweep→1 时 100% 覆盖
	float fill = smoothstep(0.80, 0.995, sweep);
	in_fan = max(in_fan, fill);

	// 透明揭示：展开区域透出新立绘，保留褶皱压暗
	vec4 next_c = texture(tex_next, UV);
	vec3 fan_area = next_c.rgb * (1.0 - 0.14 * crease);

	// 弧沿描边（仅早期可见）
	float edge_band = smoothstep(0.05, 0.015, abs(r - r_edge))
			* in_cone * passed * (1.0 - smoothstep(0.40, 0.85, sweep));
	fan_area = mix(fan_area, vec3(0.10, 0.13, 0.24), edge_band * 0.8);

	// 扇面之外：旧立绘
	vec4 prev_c = texture(tex_prev, UV);
	vec4 base = prev_c;
	base.rgb *= (1.0 - dim * 0.94);

	vec4 col = mix(base, vec4(fan_area, 1.0), in_fan);

	// 前缘金光
	float glow = exp(-abs(c_front) * 26.0) * step(r, r_edge) * in_cone
			* step(0.0001, sweep) * step(sweep, 0.9999);
	col.rgb += vec3(1.0, 0.88, 0.55) * glow * 0.85;

	COLOR = col;
}
