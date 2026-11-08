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
uniform float a_mid_s = -53.0;                       // 开花中心 = 合拢对角线角（度，GDScript 算）
uniform float a_half_s = 48.0;                       // 半跨（度，GDScript 按 48 给）
uniform float a_mid_t = -59.0;                       // 贴图角中位（度）
uniform float fan_r = 1.02;                          // 扇布外沿半径（弧沿露在画框内）
uniform float blades = 12.0;                         // 扇骨尖数（波浪边沿瓣数）
uniform float r_scale = 0.6;                         // 屏幕半径 → 布贴图采样半径

void fragment() {
	vec2 q = (UV - pivot_s) * vec2(aspect, 1.0);
	float r = length(q);
	float phi = degrees(atan(q.y, q.x));

	// 扇面几何：半跨内 6 瓣 → 波浪外沿（骨尖凸、瓣间凹）+ 放射布褶
	float pitch = a_half_s / 6.0;
	float u = (phi - a_mid_s) / pitch;
	float cwave = cos(u * 3.14159);
	float r_edge = fan_r * (0.93 + 0.07 * cwave);
	float crease = (1.0 + cwave) * 0.5;

	// 向两边展开：可见区域 = 对角线两侧 ±(sweep * 半跨)，半径压在弧沿内
	float dphi = abs(phi - a_mid_s);
	float spread = sweep * a_half_s;
	float in_fan = step(dphi, spread) * step(r, r_edge);

	// 透明揭示：展开区域直接透出新立绘，只保留褶皱压暗做布的存在感
	vec4 next_c = texture(tex_next, UV);
	vec3 fan_area = next_c.rgb * (1.0 - 0.14 * crease);

	// 边沿描边（像素风深蓝描边，勾出波浪弧沿）
	float edge_band = smoothstep(0.05, 0.015, r_edge - r) * in_fan;
	fan_area = mix(fan_area, vec3(0.10, 0.13, 0.24), edge_band * 0.8);

	// 扇面之外：旧立绘（dim 压暗；盖满后背后已换新立绘）
	vec4 prev_c = texture(tex_prev, UV);
	vec4 base = prev_c;
	base.rgb *= (1.0 - dim * 0.94);

	vec4 col = mix(base, vec4(fan_area, 1.0), in_fan);

	// 两侧开花前缘金光
	float glow = exp(-abs(dphi - spread) * 30.0) * step(r, r_edge)
			* step(0.0001, sweep) * step(sweep, 0.9999);
	col.rgb += vec3(1.0, 0.88, 0.55) * glow * 0.8;

	COLOR = col;
}
