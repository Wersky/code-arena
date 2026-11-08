shader_type canvas_item;
render_mode unshaded;

// 实物扇子单边展开转场 v3（2026-11-08，Kweno 专属，主人定稿）：
// 扇轴在左下。合拢扇先出现在一边（底边侧），然后扇骨单方向一路舒展到另一边
// （左边），扫过之处露出真实扇贴图——从起始边到前缘之间的区域是「已展开的扇面」，
// 前缘之外是旧立绘（被 dim 压暗）；扇面贴图盖不到的角用暗幕兜底，背后换图无缝。

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
uniform sampler2D tex_fan : source_color, filter_linear_mipmap;
uniform float sweep : hint_range(0.0, 1.0) = 0.0;   // 0=全合拢 1=舒展到另一边底
uniform float dim : hint_range(0.0, 1.0) = 0.0;     // 未扫到区域的压暗
uniform float aspect = 1.0;
uniform vec2 pivot_s = vec2(0.06, 0.94);            // 画面侧扇轴（左下，uv）
uniform vec2 pivot_t = vec2(0.068, 0.903);          // 贴图侧扇钉（实测）
uniform float a_start = 5.0;                        // 起始边角（度，底边侧）
uniform float a_end = -95.0;                        // 终止边角（度，左边侧）
uniform float t_off = -15.0;                        // 屏幕角 → 贴图角 偏移（度）
uniform float r_scale = 0.95;                       // 屏幕半径 → 贴图半径

void fragment() {
	vec2 q = (UV - pivot_s) * vec2(aspect, 1.0);
	float r = length(q);
	float phi = degrees(atan(q.y, q.x));

	// 前缘角：sweep 0→1，从起始边一路转到终止边
	float front = mix(a_start, a_end, clamp(sweep, 0.0, 1.0));

	// 已展开区域：前缘与起始边之间（角度从 a_start 往 a_end 方向）
	float in_swept = step(front, phi) * step(phi, a_start) * step(r, 1.7);

	// 屏幕角 → 贴图角（1:1 映射 + 偏移）→ 采样真实扇贴图
	float tau = phi + t_off;
	float tau_rad = tau * 0.0174533;
	vec2 tuv = pivot_t + vec2(cos(tau_rad), sin(tau_rad)) * r * r_scale;
	vec4 fan_c = texture(tex_fan, tuv);
	float paper = step(0.4, fan_c.a);
	vec3 fan_area = mix(vec3(0.043, 0.055, 0.095), fan_c.rgb, paper);

	// 未扫到的区域：旧立绘（dim 压暗；盖满后背后已换新立绘）
	vec4 prev_c = texture(tex_prev, UV);
	vec4 base = prev_c;
	base.rgb *= (1.0 - dim * 0.94);

	vec4 col = mix(base, vec4(fan_area, 1.0), in_swept);

	// 前缘金光（正在展开的那条边）
	float glow = exp(-abs(phi - front) * 34.0) * step(r, 1.7)
			* step(0.0001, sweep) * step(sweep, 0.9999);
	col.rgb += vec3(1.0, 0.88, 0.55) * glow * 0.85;

	COLOR = col;
}
