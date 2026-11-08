shader_type canvas_item;
render_mode unshaded;

// 实物扇子展开转场 v2（2026-11-08，Kweno 专属，主人草图定稿）：
// 合拢扇沿「左下→右上」对角线啪在立绘上 → 绕左下扇轴，扇骨从对角线向两侧
// 逐片绽放（角度揭示真实扇贴图）→ 盖满画面（背后已换新立绘）→ 逆向收扇露出新立绘。
// 扇面之外（扫过区域内贴图透明处）用暗幕补——扇是斜的，四角靠暗幕兜底保证无缝。

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
uniform sampler2D tex_fan : source_color, filter_linear_mipmap;
uniform float sweep : hint_range(0.0, 1.0) = 0.0;   // 展开度：0 合拢 1 全开
uniform float dim : hint_range(0.0, 1.0) = 0.0;     // 扇面之外的压暗（盖住换卡瞬间）
uniform float aspect = 1.0;
uniform vec2 pivot_s = vec2(0.06, 0.94);            // 画面侧扇轴（左下，uv）
uniform vec2 pivot_t = vec2(0.068, 0.903);          // 贴图侧扇钉（实测）
uniform float a_mid_s = -43.9;                      // 画面角度带中位（度，实测自当前画框）
uniform float a_half_s = 48.8;                      // 画面角度带半跨
uniform float a_mid_t = -59.0;                      // 贴图扇骨角中位（度，实测）
uniform float a_half_t = 48.0;                      // 贴图扇骨角半跨
uniform float r_scale = 0.975;                      // 屏幕半径 → 贴图半径

void fragment() {
	vec2 q = (UV - pivot_s) * vec2(aspect, 1.0);
	float r = length(q);
	float phi = degrees(atan(q.y, q.x));

	// 绽放：可见扇骨角范围从对角线向两侧铺开（对称「开花」，合拢=一条对角线）
	float spread = sweep * min(a_half_s, a_half_t);
	float dphi = abs(phi - a_mid_s);
	float in_fan = step(dphi, spread) * step(r, 1.7);

	// 屏幕角 → 贴图角（1:1 映射，中位对齐）→ 采样真实扇贴图
	float tau = a_mid_t + (phi - a_mid_s);
	float tau_rad = tau * 0.0174533;
	vec2 tuv = pivot_t + vec2(cos(tau_rad), sin(tau_rad)) * r * r_scale;
	vec4 fan_c = texture(tex_fan, tuv);
	float paper = step(0.4, fan_c.a);
	vec3 fan_area = mix(vec3(0.043, 0.055, 0.095), fan_c.rgb, paper);

	// 未扫到的区域：旧立绘（已被 dim 压暗；换卡瞬间背后即新立绘）
	vec4 prev_c = texture(tex_prev, UV);
	vec4 base = prev_c;
	base.rgb *= (1.0 - dim * 0.94);

	vec4 col = mix(base, vec4(fan_area, 1.0), in_fan);

	// 绽放前缘双金光（两条开花边）
	float e1 = a_mid_s - spread;
	float e2 = a_mid_s + spread;
	float glow = (exp(-abs(phi - e1) * 34.0) + exp(-abs(phi - e2) * 34.0))
			* step(r, 1.7) * step(0.0001, sweep) * step(sweep, 0.9999);
	col.rgb += vec3(1.0, 0.88, 0.55) * glow * 0.8;

	COLOR = col;
}
