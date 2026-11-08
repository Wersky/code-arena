shader_type canvas_item;
render_mode unshaded;

// 像素扇布转场 v6（2026-11-08，Kweno 专属，主人草图两段式定稿）：
// ① 先出现**折痕**：从左下扇轴放射的折叠线（金线）一条条画出来，
//    铺满整个立绘——这是扇子收拢时的折印
// ② 然后**扇布从单边划出**：布从左缘沿折痕一路扫到另一侧，布上的褶皱
//    正好接上折痕，盖满全画框（背后换图）后逆向收回，露出新立绘。
// 全程只有布，没有支架。creases[j] = vec4(角度deg, 起画时刻, 0, 0)，GDScript 生成。

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
uniform sampler2D tex_fan : source_color, filter_nearest, repeat_enable; // 像素布：NEAREST 才脆
uniform float fan_p : hint_range(0.0, 1.0) = 0.0;    // 整套动作的原始进度（折痕淡出用）
uniform float sweep : hint_range(0.0, 1.0) = 0.0;    // 0=合拢（竖在左缘） 1=盖满全画框
uniform float dim : hint_range(0.0, 1.0) = 0.0;      // 未扫到区域的压暗
uniform float aspect = 1.0;
uniform vec2 pivot_s = vec2(0.06, 0.94);             // 画面侧扇轴（左下，uv）
uniform float a_start = -95.0;                       // 起始角（度）：左边缘略过一点
uniform float a_end = 8.0;                           // 终止角（度）：右边略过一点
uniform float r_scale = 0.6;                         // 屏幕半径 → 布贴图采样半径
uniform float fan_r = 1.02;                          // 扇布外沿半径（弧沿露在画框内）
uniform vec4 creases[5];                             // 折痕：(角度deg, 起画时刻, 0, 0)

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
	vec2 q = (UV - pivot_s) * vec2(aspect, 1.0);
	float r = length(q);
	float phi = degrees(atan(q.y, q.x));

	// 扇面几何：12 等分扇骨距 → 折痕在偶数位，外沿波浪（骨尖凸、瓣间凹）
	float pitch = (a_end - a_start) / 12.0;
	float u = (phi - a_start) / pitch;
	float cwave = cos(u * 3.14159);
	float r_edge = fan_r * (0.93 + 0.07 * cwave);
	float crease = (1.0 + cwave) * 0.5;

	// 前缘：sweep 0→1，扇布从左边缘向右扫到另一侧
	float front = mix(a_start, a_end, clamp(sweep, 0.0, 1.0));

	// 已展开区域：左边缘与前缘之间，半径压在弧沿内
	float in_swept = step(a_start, phi) * step(phi, front) * step(r, r_edge);

	// 像素布采样：极坐标随扇轴转，图案跟着扇布一起「转开」
	float phi_rad = phi * 0.0174533;
	vec2 tuv = vec2(0.5) + vec2(cos(phi_rad), sin(phi_rad)) * r * r_scale;
	vec4 fan_c = texture(tex_fan, tuv);
	vec3 fan_area = fan_c.rgb * (1.0 - 0.10 * crease);

	// 边沿描边（像素风深蓝描边，勾出波浪弧沿）
	float edge_band = smoothstep(0.05, 0.015, r_edge - r) * in_swept;
	fan_area = mix(fan_area, vec3(0.10, 0.13, 0.24), edge_band * 0.8);

	// 未扫到的区域：旧立绘（dim 压暗；盖满后背后已换新立绘）
	vec4 prev_c = texture(tex_prev, UV);
	vec4 base = prev_c;
	base.rgb *= (1.0 - dim * 0.94);

	vec4 col = mix(base, vec4(fan_area, 1.0), in_swept);

	// ① 折痕：金线从扇轴向外「画」出来（起画时刻错峰），扫过前一直留着
	float crease_fade = 1.0 - smoothstep(0.9, 1.0, fan_p);
	for (int j = 0; j < 5; j++) {
		vec4 cr = creases[j];
		float dt = clamp((fan_p - cr.y) / 0.16, 0.0, 1.0);
		float dline = abs(phi - cr.x);
		float line_a = (1.0 - smoothstep(0.0, 1.0, dline))
				* step(0.001, dt) * step(r, r_edge * dt);
		col.rgb += vec3(1.0, 0.88, 0.55) * line_a * 0.75 * (1.0 - sweep * 0.92) * crease_fade;
	}

	// 前缘金光（正在划出的那条边）
	float glow = exp(-abs(phi - front) * 30.0) * step(r, r_edge)
			* step(0.0001, sweep) * step(sweep, 0.9999);
	col.rgb += vec3(1.0, 0.88, 0.55) * glow * 0.8;

	COLOR = col;
}
