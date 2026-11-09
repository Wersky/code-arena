shader_type canvas_item;
render_mode unshaded;

// 立绘呼吸起伏（2026-11-09，选角界面四张大立绘专用）：
// 对整幅立绘做极轻的 UV 微起伏，像人被地面固定住、上身随呼吸起伏——
// 底边锚定（UV.y = 1 处位移恒为 0），越往上幅度越大；
// 纵向主位移 + 横向极轻摆动（错相 1.2rad），避免机械的活塞感。
//
// 用法（每张立绘一个 ShaderMaterial）：
//   tex_src    = 立绘纹理；
//   progress   0→1 循环，由 GDScript tween 推进（周期 4.0s，四人各自错相）；
//   amp        位移幅度（UV 单位），默认 0.008 = 0.8%；
//   tex_region 可选灰度遮罩（白 = 位移大、黑 = 几乎不动），用生图做出胸腔/头部的差异；
//   use_region 关掉时遮罩完全不参与，w 退化为纯底边锚定的线性权重。
//
// 注意：本文件严禁出现 maxf —— Godot shader 只有 max，maxf 会静默白屏（本项目踩过）。

uniform sampler2D tex_src : source_color, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float amp : hint_range(0.0, 0.05) = 0.008;     // 位移幅度（UV 单位）
uniform float head_weight : hint_range(0.0, 2.0) = 1.0;  // 头部区域额外权重倍率
uniform float chest_weight : hint_range(0.0, 2.0) = 0.6; // 胸部区域额外权重倍率
uniform sampler2D tex_region : hint_default_black, filter_linear;
uniform bool use_region = false;

void fragment() {
	// ---- 1. 底边锚定的基础权重 ----
	// UV.y 在 Godot canvas_item 里 0 = 顶、1 = 底；这里 (1.0 - UV.y) 让底边权重为 0、
	// 越往头顶越大 —— 立绘像被地面钉住，只有上半身随呼吸抬起。
	float w = 1.0 - UV.y;

	// ---- 2. 可选灰度遮罩：生图差异（胸腔白、头部灰、边缘黑） ----
	// use_region 关闭时 mix 的第三个参数为 0，遮罩完全不参与，行为与无遮罩一致。
	float mask = texture(tex_region, UV).r;
	w *= mix(1.0, mask, use_region ? 1.0 : 0.0);

	// ---- 3. 头部 / 胸部区域分层倍率 ----
	// 在遮罩之上再叠一层手动微调：头区用 head_weight、胸区用 chest_weight、其余按 1.0。
	// smoothstep 的 edge0 > edge1 表示反向插值（UV.y 小 = 靠头顶），两条带之间用
	// (1.0 - zone_head) 做互斥，保证三段权重加起来恒为 1，不会把幅度叠爆。
	float zone_head = smoothstep(0.36, 0.20, UV.y);
	float zone_chest = smoothstep(0.60, 0.48, UV.y) * (1.0 - zone_head);
	float zone_rest = max(1.0 - zone_head - zone_chest, 0.0);
	w *= zone_head * head_weight + zone_chest * chest_weight + zone_rest * 1.0;

	// ---- 4. 纵向主位移 + 横向极轻摆动 ----
	// sin 在 progress 半个周期内向上、半个周期内向下，幅度都受 w 压制，静止边始终不动；
	// 横向错相 1.2rad、幅度取 0.3 倍，让左右有一点点不对称的漂移感。
	float phase = progress * TAU;
	float dy = -amp * w * sin(phase);
	float dx = amp * 0.3 * w * sin(phase + 1.2);
	vec2 shifted = UV + vec2(dx, dy);

	// ---- 5. 无条件 clamp ----
	// 偏移后越界的 UV 必须夹回 [0,1]：否则采样会拉出黑边 / 透明边，
	// clamp 后越界处重复边缘像素，视觉上只是边缘被轻微拉长，不会露底。
	shifted = clamp(shifted, vec2(0.0), vec2(1.0));

	COLOR = texture(tex_src, shifted);
}
