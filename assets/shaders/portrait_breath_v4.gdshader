shader_type canvas_item;
render_mode unshaded;

// 立绘呼吸 V4 —— **网格形变**版（2026-11-10 主人要求「商业级方案，UV shader 太差」）。
//
// ── 为什么放弃 V1~V3 的 UV 平移 ────────────────────────────────────────
// UV 位移本质是「整片像素按同一方向滑动」，数学上是刚体平移：
//   · 做不出胸廓横向扩张（那需要左右两侧向相反方向走）
//   · 做不出「上提 + 外扩」的复合，只能选一个
//   · 位移量一大，图层边界就会露缝/穿模（所以只能给极小 amplitude，观感就是"图片在抖"）
// 商业方案（Live2D warp deformer / Spine 骨骼蒙皮）都是**顶点级形变**，
// 每个顶点有自己的位移向量 → 同一时刻画面里既有外扩也有上提。
//
// ── 本方案 ────────────────────────────────────────────────────────────
// 立绘细分 32x18 网格（MeshInstance2D + ArrayMesh），顶点色 RGBA 四个通道存权重场：
//   R = 胸腔（横向扩张 + 上提，主导）
//   G = 腹部（次级，滞后相位）
//   B = 头颈（只跟垂直，避免五官变形）
//   A = 头发（横向飘动；相位随**高度**连续滞后，形成一波往下传，
//       比 V3 的 5 段离散更自然，也不需要在面板里调 10 个相位参数）
// 权重由 GDScript 在用遮罩生成网格时烘进顶点色（见 portrait_breath_mesh.gd）。
// 着色器只做：读权重 → 按相位算位移 → 写 VERTEX。1 draw call、纯 GPU。
//
// ── 关键约束（都是踩过的坑）──────────────────────────────────────────
// · COLOR 在 vertex() 里已被 CanvasItem.modulate 乘过 → 上层 modulate 必须纯白
// · VERTEX 单位是**局部像素**，幅度要用像素给（不是 UV）
// · 只允许一套相位参数，横竖分量同时存在是刻意的（扩张+上提本就是复合），
//   但**不能有旋转分量**，否则就是 V3 之前主人否掉的"图在转"
// · Godot shader 只有 max，没有 maxf（写了会静默白屏）

uniform float phase : hint_range(0.0, 6.2832) = 0.0;   // 弧度，由 GDScript 推进
uniform float amp : hint_range(0.0, 3.0) = 1.0;        // 总幅度倍率

// 各层相对幅度（像素）。1600x900 画布下这些值对应「身高的 0.5~1.5%」
uniform float chest_x : hint_range(0.0, 20.0) = 4.5;   // 胸腔横向外扩
uniform float chest_y : hint_range(0.0, 20.0) = 3.6;   // 胸腔上提
uniform float belly_x : hint_range(0.0, 20.0) = 2.6;   // 腹部外扩（更小）
uniform float belly_y : hint_range(0.0, 20.0) = 1.4;
uniform float head_y : hint_range(0.0, 20.0) = 2.0;    // 头颈垂直
uniform float hair_x : hint_range(0.0, 30.0) = 4.2;    // 头发横向飘（7.0 偏大像抖，收到 4.2）
uniform float hair_y : hint_range(0.0, 30.0) = 1.6;    // 头发轻微上下

// 相位滞后（度，转弧度后使用）。商业基线：腹→胸→肩→头 依次滞后 15~60°
uniform float belly_lag_deg : hint_range(0.0, 180.0) = 55.0;
uniform float head_lag_deg : hint_range(0.0, 180.0) = 100.0;
// 头发相位随高度连续滞后：每下降 1.0（全高）滞后这么多度。
// 240° 表示发梢比发根晚约 2/3 个周期 —— 视觉上是「一波往下传」
uniform float hair_lag_per_height : hint_range(0.0, 720.0) = 240.0;

// 底部锁定：画面最下方 12% 不位移，避免脚/桌边被拉出画面
uniform float lock_bottom : hint_range(0.0, 0.5) = 0.12;

void vertex() {
	// 顶点色即权重场（R=胸 G=腹 B=头）。注意已被 modulate 乘过 → 上层必须 modulate 白
	vec4 w = COLOR;
	float wc = w.r;
	float wb = w.g;
	float wh = w.b;
	float wr = w.a;      // 头发

	// 底部锁定：越靠下权重越小，保证画面下沿不动
	float lock = smoothstep(0.0, lock_bottom, 1.0 - UV.y);

	// 三个部位的相位（滞后用弧度）
	float lag_b = radians(belly_lag_deg);
	float lag_h = radians(head_lag_deg);
	float s_chest = sin(phase);
	float s_belly = sin(phase - lag_b);
	float s_head = sin(phase - lag_h);

	// 胸腔：**横向外扩 + 上提**同时进行（这是 UV 方案做不到的核心）
	// sign(VERTEX.x - 中心x) 让左右两侧朝相反方向走 = 真正的扩张而非平移
	// 网格局部坐标原点在立绘中心，所以直接用 VERTEX.x 的符号
	float chest_x_dir = sign(VERTEX.x);
	VERTEX.x += chest_x_dir * wc * s_chest * chest_x * amp * lock;
	VERTEX.y -= wc * s_chest * chest_y * amp * lock;

	// 腹部：更小幅度、滞后相位
	VERTEX.x += sign(VERTEX.x) * wb * s_belly * belly_x * amp * lock;
	VERTEX.y -= wb * s_belly * belly_y * amp * lock;

	// 头颈：只垂直，不做横向（避免五官被左右拉扯）
	VERTEX.y += wh * s_head * head_y * amp * lock;

	// 头发：相位随高度连续滞后（UV.y 越大越靠下 = 越发梢）
	float hair_lag = radians(hair_lag_per_height) * UV.y;
	float s_hair = sin(phase - hair_lag);
	// 横向飘：整片同向摆（头发是被气流带着走，不是左右对称扩张）
	VERTEX.x += wr * s_hair * hair_x * amp * lock;
	VERTEX.y += wr * cos(phase - hair_lag) * hair_y * amp * lock * 0.5;
}

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
