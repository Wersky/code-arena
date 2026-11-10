shader_type canvas_item;
render_mode unshaded;

// 立绘呼吸起伏 V3（2026-11-10 主人要求：头发细分成 5 段各自飘动）。
//
// ── 相对 V2 的改动 ────────────────────────────────────────────────────
// V2 只有 hair / face / body 三层，整片头发共用一条曲线 → 头发是一整块平移，
// 看不出「一缕一缕往上飘」的层次。主人要求按部位细分。
// V3 把头发拆成 5 段，外加 face / body / wing，共 8 个受控层。
//
// ── 五段头发的相位设计（默认值，面板可按角色改）─────────────────────
//   seg1 呆毛头顶   phase +0.10  gain 1.15   最轻最灵，抢先动
//   seg2 左鬓       phase +0.05  gain 1.00
//   seg3 右鬓       phase +0.05  gain 1.00
//   seg4 长垂发     phase -0.03  gain 0.80   主体，稍慢
//   seg5 末端发梢   phase -0.12  gain 0.60   最慢，形成「一波往下传」
// 从上到下依次滞后，视觉上是头发被气流带着飘，不是整片平移。
//
// ── 分层权重与归一化 ─────────────────────────────────────────────────
// 8 张遮罩天然会重叠（发梢压在长垂发上、翅膀压在身体上）。
// 用 sum 归一化：每个像素的权重 = 该层强度 × gain，再除以总和。
// 总权重恒为 1，叠加不会爆幅，重叠区是平滑混合而非双推。
//
// ── 单轴约束（V1 的教训）────────────────────────────────────────────
// 只允许 axis=0（纯上下）或 1（纯左右）。横竖同时有分量会合成椭圆轨迹，
// 观感就是「画面在转」，主人明确否掉过。
//
// 注意：本文件严禁出现 maxf —— Godot shader 只有 max，maxf 会静默白屏。

uniform sampler2D tex_src : source_color, filter_linear;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float amp : hint_range(0.0, 0.2) = 0.012;
uniform int axis : hint_range(0, 1) = 0;

// ── 头发 5 段（遮罩 + 各自 gain/phase）──
uniform sampler2D tex_h1 : hint_default_black, filter_linear;
uniform sampler2D tex_h2 : hint_default_black, filter_linear;
uniform sampler2D tex_h3 : hint_default_black, filter_linear;
uniform sampler2D tex_h4 : hint_default_black, filter_linear;
uniform sampler2D tex_h5 : hint_default_black, filter_linear;
uniform float g1 : hint_range(0.0, 2.0) = 1.15;
uniform float g2 : hint_range(0.0, 2.0) = 1.00;
uniform float g3 : hint_range(0.0, 2.0) = 1.00;
uniform float g4 : hint_range(0.0, 2.0) = 0.80;
uniform float g5 : hint_range(0.0, 2.0) = 0.60;
uniform float p1 : hint_range(-1.0, 1.0) = 0.10;
uniform float p2 : hint_range(-1.0, 1.0) = 0.05;
uniform float p3 : hint_range(-1.0, 1.0) = 0.05;
uniform float p4 : hint_range(-1.0, 1.0) = -0.03;
uniform float p5 : hint_range(-1.0, 1.0) = -0.12;

// ── 其余三层 ──
uniform sampler2D tex_face : hint_default_black, filter_linear;
uniform sampler2D tex_body : hint_default_black, filter_linear;
uniform sampler2D tex_wing : hint_default_black, filter_linear;
uniform float face_gain : hint_range(0.0, 2.0) = 0.62;
uniform float body_gain : hint_range(0.0, 2.0) = 0.34;
uniform float wing_gain : hint_range(0.0, 2.0) = 0.22;  // 翅膀幅度最小，只轻张合
uniform float face_phase : hint_range(-1.0, 1.0) = 0.00;
uniform float body_phase : hint_range(-1.0, 1.0) = -0.06;
uniform float wing_phase : hint_range(-1.0, 1.0) = -0.16; // 翅膀最滞后

uniform bool use_layers = false;

void fragment() {
	// ---- 1. 底边锚定权重 ----
	// 2026-11-10 修正：原来 smoothstep(0, 0.92, ...) 会把画面下半部全压死，
	// 而头发是**披下来**的、长发主体正好在画面下半 —— 实测发梢段位移只剩 0.18px，
	// 主人反馈「红框里的头发没动静」就是这个原因。
	// 现在只压最底部 15%（避免画面底边被拉出缝），其余区域接近满权重。
	float hh = clamp(1.0 - UV.y, 0.0, 1.0);
	float w_base = smoothstep(0.0, 0.15, hh);

	// ---- 2. 采样 8 层遮罩 ----
	float m1 = texture(tex_h1, UV).r;
	float m2 = texture(tex_h2, UV).r;
	float m3 = texture(tex_h3, UV).r;
	float m4 = texture(tex_h4, UV).r;
	float m5 = texture(tex_h5, UV).r;
	float mf = texture(tex_face, UV).r;
	float mb = texture(tex_body, UV).r;
	float mw = texture(tex_wing, UV).r;

	// ---- 3. 权重和（归一化用，保证总权重不超 1）----
	float sum = m1 * g1 + m2 * g2 + m3 * g3 + m4 * g4 + m5 * g5
			+ mf * face_gain + mb * body_gain + mw * wing_gain;
	float norm = max(sum, 1e-4);

	// ---- 4. 各层位移：每层用自己的 gain 与 phase ----
	// 五段头发从上到下相位依次滞后，形成「一波往下传」的飘动层次。
	float ph = progress * TAU;
	float d1 = g1 * sin(ph + p1 * TAU);
	float d2 = g2 * sin(ph + p2 * TAU);
	float d3 = g3 * sin(ph + p3 * TAU);
	float d4 = g4 * sin(ph + p4 * TAU);
	float d5 = g5 * sin(ph + p5 * TAU);
	float df = face_gain * sin(ph + face_phase * TAU);
	float db = body_gain * sin(ph + body_phase * TAU);
	float dw = wing_gain * sin(ph + wing_phase * TAU);

	// ---- 5. 加权合成 ----
	float dy_mix = (m1 * d1 + m2 * d2 + m3 * d3 + m4 * d4 + m5 * d5
			+ mf * df + mb * db + mw * dw) / norm;

	// 关掉分层时退化为全身统一呼吸
	float dy_flat = sin(ph);
	float dy = use_layers ? dy_mix : dy_flat;

	// ---- 6. 单轴位移（横竖互斥，杜绝旋转感）----
	vec2 shifted = UV;
	float d = amp * w_base * dy;
	if (axis == 0) {
		shifted.y -= d;
	} else {
		shifted.x -= d;
	}

	// ---- 7. 无条件 clamp，防边缘拉黑/透明 ----
	shifted = clamp(shifted, vec2(0.0), vec2(1.0));
	COLOR = texture(tex_src, shifted);
}
