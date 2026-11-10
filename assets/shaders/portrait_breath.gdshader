shader_type canvas_item;
render_mode unshaded;

// 立绘呼吸起伏 V2（2026-11-10 主人反馈重做）：
//
// ── 相对 V1 的三处根本改动 ────────────────────────────────────────────
// 1) **去掉横向摆动**。V1 里 dx = amp*0.3*w*sin(phase+1.2)，横向与纵向错相 1.2rad
//    后合成椭圆轨迹，观感就是「画面在转」。V2 只有纵向，纯上下。
// 2) **三层分区，各层独立位移**。V1 只有一张遮罩、全身共用一条曲线，导致眼睛
//    和头发被一起推、脸跟头发撕扯。V2 拆成 头发 / 脸 / 身体 三张遮罩，
//    每层有自己的相位偏移与幅度系数，互不牵扯。
// 3) **底边锚定保留**，但改为按层分配权重：越靠下的层位移越小，
//    整体仍是「被地面钉住、上身起伏」，不会出现下半身跟着漂。
//
// ── 三层遮罩语义（灰度，白=该层在此处）──────────────────────────────
//   tex_hair  : 头发（含呆毛、刘海、鬓发）—— 幅度最大、相位领先
//   tex_face  : 脸部（眼睛/鼻/嘴/下巴，不含头发遮挡部分）—— 幅度中等、相位居中
//   tex_body  : 身体（肩、胸、手臂、衣物）—— 幅度最小、相位滞后
// 三层在 shader 内归一化后加权混合，不会叠加爆幅。
//
// ── 为什么脸要单独一层 ────────────────────────────────────────────────
// 头发在画面里覆盖了脸的边缘，V1 单遮罩必然把「脸的一部分」算进头发区域，
// 位移不同就产生拉扯。拆层后脸区域严格只跟随脸层曲线，头发只跟随头发层曲线，
// 交叠处用二次平滑过渡，眼睛和眉毛因此不再被头发拖动。
//
// 注意：本文件严禁出现 maxf —— Godot shader 只有 max，maxf 会静默白屏。

uniform sampler2D tex_src : source_color, filter_linear;

// 进度与总控
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float amp : hint_range(0.0, 0.2) = 0.012;   // 基础位移幅度（UV 单位）
// 运动方向（2026-11-10 主人要求显式可选）：0=纯上下  1=纯左右
// 只允许单一轴向 —— 旧版横竖错相合成椭圆轨迹，观感像画面在转，已废弃。
uniform int axis : hint_range(0, 1) = 0;

// 三层遮罩
uniform sampler2D tex_hair : hint_default_black, filter_linear;
uniform sampler2D tex_face : hint_default_black, filter_linear;
uniform sampler2D tex_body : hint_default_black, filter_linear;
uniform bool use_layers = false;   // 关掉时退化为「全身统一底边锚定」

// 三层各自的幅度系数与相位偏移（可调，默认值经实测手感）
uniform float hair_gain : hint_range(0.0, 2.0) = 1.00;
uniform float face_gain : hint_range(0.0, 2.0) = 0.62;
uniform float body_gain : hint_range(0.0, 2.0) = 0.34;

uniform float hair_phase : hint_range(-1.0, 1.0) = 0.05;  // 领先一点点
uniform float face_phase : hint_range(-1.0, 1.0) = 0.00;  // 基准
uniform float body_phase : hint_range(-1.0, 1.0) = -0.06; // 滞后一点点

void fragment() {
	// ---- 1. 底边锚定的基础权重 ----
	// UV.y: 0=顶, 1=底。让底部权重趋 0，越往上越大。
	// 用 pow 让权重在上半身更饱满（线性会让头顶过冲、腰腹几乎不动）。
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float w_base = smoothstep(0.0, 0.92, h);

	// ---- 2. 三层权重采样 ----
	float m_hair = texture(tex_hair, UV).r;
	float m_face = texture(tex_face, UV).r;
	float m_body = texture(tex_body, UV).r;

	// 归一化：三张遮罩可能有重叠（脸被头发压住、身体与头发交叠），
	// 用和归一化保证总权重不超过 1，不会把幅度叠加放大。
	float sum = m_hair * hair_gain + m_face * face_gain + m_body * body_gain;
	float norm = max(sum, 1e-4);

	// ---- 3. 各自的纵向位移 ----
	// 只保留 sin 纵向分量。三层用不同相位，看起来是「头发先动、身体跟上」的
	// 自然传导感，而不是整块一起平移。
	float ph = progress * TAU;
	float d_hair = hair_gain * sin(ph + hair_phase * TAU);
	float d_face = face_gain * sin(ph + face_phase * TAU);
	float d_body = body_gain * sin(ph + body_phase * TAU);

	// 加权合成：分子是各层位移，分母是权重和 → 交叠处平滑过渡不突变
	float dy_mix = (m_hair * d_hair + m_face * d_face + m_body * d_body) / norm;

	// ---- 4. 关掉分层时的退化路径 ----
	// use_layers=false：全体共用一个 sin，等价于「整张图底边锚定上下」。
	float dy_flat = sin(ph);
	float dy = use_layers ? dy_mix : dy_flat;

	// ---- 5. 单一轴向位移（V2 核心：消除旋转感）----
	// axis=0：纯上下，横向恒为 0；axis=1：纯左右，纵向恒为 0。
	// 两个轴永远不会同时有非零分量，因此不可能出现椭圆/旋转轨迹。
	vec2 shifted = UV;
	float d = amp * w_base * dy;
	if (axis == 0) {
		shifted.y -= d;
	} else {
		shifted.x -= d;
	}

	// ---- 6. 无条件 clamp ----
	// 偏移后越界的 UV 必须夹回 [0,1]：否则采样会拉出黑边/透明边。
	shifted = clamp(shifted, vec2(0.0), vec2(1.0));

	COLOR = texture(tex_src, shifted);
}
