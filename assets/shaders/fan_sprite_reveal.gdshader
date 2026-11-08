shader_type canvas_item;
render_mode unshaded;

// 像素扇布转场 v5（2026-11-08，Kweno 专属，主人草图定稿）：
// 扇轴在左下角，合拢的扇布**竖着贴在立绘左边缘**；展开时扇布从左边缘
// 向右一路扫过整个立绘（像素布贴图按角度揭示），盖满后背后换图，
// 再逆向收回左边缘，露出新立绘。全程只有布，没有支架。

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
uniform sampler2D tex_fan : source_color, filter_nearest, repeat_enable; // 像素布：NEAREST 才脆
uniform float sweep : hint_range(0.0, 1.0) = 0.0;   // 0=合拢（竖在左缘） 1=盖满全画框
uniform float dim : hint_range(0.0, 1.0) = 0.0;     // 未扫到区域的压暗
uniform float aspect = 1.0;
uniform vec2 pivot_s = vec2(0.06, 0.94);            // 画面侧扇轴（左下，uv）
uniform float a_start = -95.0;                      // 起始角（度）：左边缘略过一点，兜住左上角
uniform float a_end = 8.0;                          // 终止角（度）：右边略过一点，兜住右下角
uniform float r_scale = 0.6;                        // 屏幕半径 → 布贴图采样半径

void fragment() {
	vec2 q = (UV - pivot_s) * vec2(aspect, 1.0);
	float r = length(q);
	float phi = degrees(atan(q.y, q.x));

	// 前缘：sweep 0→1，扇布从左边缘向右扫到另一侧
	float front = mix(a_start, a_end, clamp(sweep, 0.0, 1.0));

	// 已展开区域：左边缘与前缘之间
	float in_swept = step(a_start, phi) * step(phi, front) * step(r, 1.7);

	// 像素布采样：极坐标随扇轴转，图案跟着扇布一起「转开」
	float phi_rad = phi * 0.0174533;
	vec2 tuv = vec2(0.5) + vec2(cos(phi_rad), sin(phi_rad)) * r * r_scale;
	vec4 fan_c = texture(tex_fan, tuv);
	vec3 fan_area = fan_c.rgb;   // 布满幅不透明，扫到即布

	// 未扫到的区域：旧立绘（dim 压暗；盖满后背后已换新立绘）
	vec4 prev_c = texture(tex_prev, UV);
	vec4 base = prev_c;
	base.rgb *= (1.0 - dim * 0.94);

	vec4 col = mix(base, vec4(fan_area, 1.0), in_swept);

	// 前缘金光（正在展开的那条边）
	float glow = exp(-abs(phi - front) * 30.0) * step(r, 1.7)
			* step(0.0001, sweep) * step(sweep, 0.9999);
	col.rgb += vec3(1.0, 0.88, 0.55) * glow * 0.8;

	COLOR = col;
}
