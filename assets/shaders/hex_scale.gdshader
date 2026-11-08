shader_type canvas_item;
render_mode unshaded;

// 龙鳞剥落转场（2026-11-08，ChatPPT 专属）：白龙千金的鳞片一片片掀落——
// 六边形鳞格按「底部先剥 + 每片随机」的次序消失，剥落沿线的鳞片微微翘起并镶金边，
// 露出底下的新立绘。

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.0;
uniform float scale_size = 0.055;  // 鳞片大小（uv 高度单位）

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

// 六边形网格：返回所在格 id 与格内局部坐标
vec2 hex_cell(vec2 p, out vec2 local) {
	vec2 h = vec2(1.0, 1.7320508);
	vec2 a1 = mod(p, h) - h * 0.5;
	vec2 a2 = mod(p + h * 0.5, h) - h * 0.5;
	vec2 gv = (dot(a1, a1) < dot(a2, a2)) ? a1 : a2;
	local = gv;
	return p - gv;
}

void fragment() {
	vec2 q = UV * vec2(aspect, 1.0) / scale_size;
	vec2 local;
	vec2 id = hex_cell(q, local);

	// 剥落次序：每片随机 + 底部优先（鳞从下往上 shed）
	float rnd = hash21(id + vec2(7.31, 3.17));
	float th = rnd * 0.72 + UV.y * 0.28;
	float pr = clamp(progress, 0.0, 1.0001);
	float gone = step(th, pr); // 1 = 已剥落（新图）

	// 剥落沿线：刚被掀起的鳞片微微翘起（往自身随机方向挪一点）
	float frontier = smoothstep(pr - 0.12, pr, th) * gone;
	vec2 drift = normalize(vec2(hash21(id + vec2(1.7, 9.2)), hash21(id + vec2(4.4, 2.8))) - vec2(0.5) + vec2(0.001));
	vec2 lift = drift * frontier * 0.02;

	vec4 prev_c = texture(tex_prev, UV + lift);
	vec4 next_c = texture(tex_next, UV);
	vec4 col = mix(prev_c, next_c, gone);

	// 翘起鳞片的金边（格内圆环近似六边形边框，鳞片小看不出来）
	float rim = smoothstep(0.36, 0.46, length(local)) * frontier;
	col.rgb += vec3(1.0, 0.9, 0.65) * rim * 0.45;
	col.rgb *= 1.0 + frontier * 0.15;

	COLOR = col;
}
