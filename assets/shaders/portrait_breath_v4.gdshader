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

// ── 翅膀（第 5 通道，2026-11-11 t4-gpt-wing-breath）────────────────────
// 翅膀权重不走顶点色（RGBA 已满），走 **CUSTOM0.x**（ARRAY_CUSTOM0 / R_FLOAT）。
// 只有 chatppt 有翅膀遮罩，其余角色 CUSTOM0 恒为 0 → 下面两项自动无效。
uniform float wing_x : hint_range(0.0, 30.0) = 6.0;    // 翅膀横向展开
uniform float wing_y : hint_range(0.0, 30.0) = 4.0;    // 翅膀纵向起伏
// 翅膀相位滞后。**必须与胸/腹/头/发错开**，否则翅膀只是跟着身体一起晃，
// 看不出「翅膀自己在呼吸」。150° ≈ 反相，观感是「胸腔收、翅膀张」的交替。
uniform float wing_lag_deg : hint_range(0.0, 360.0) = 150.0;

// 相位滞后（度，转弧度后使用）。商业基线：腹→胸→肩→头 依次滞后 15~60°
uniform float belly_lag_deg : hint_range(0.0, 180.0) = 55.0;
uniform float head_lag_deg : hint_range(0.0, 180.0) = 100.0;
// 头发相位随高度连续滞后：每下降 1.0（全高）滞后这么多度。
// 240° 表示发梢比发根晚约 2/3 个周期 —— 视觉上是「一波往下传」
uniform float hair_lag_per_height : hint_range(0.0, 720.0) = 240.0;

// ── 横竖分离（2026-11-10 主人反馈：整体观感像旋转）─────────────────
// 根因：原来横向(chest_x)与纵向(chest_y)共用同一个 sin(phase)，两者同相且幅度固定，
//       合成后是沿固定斜线的往复运动；再叠加头发的横向摆动，整体就像在「转」。
// 修法：横向与纵向各用**独立相位**（可各自设滞后角），并且纵向改用「半波整流偏移」——
//       纵向只做吸/呼单向推进（上提-回落），横向才做完整往复（外扩-回收），
//       不再是同一条斜线来回，所以不会出现旋转观感。
uniform float x_lag_deg : hint_range(0.0, 180.0) = 0.0;    // 横向相对纵向的相位滞后
uniform float y_bias : hint_range(0.0, 1.0) = 0.35;        // 纵向偏移：越大越偏「持续上提」
uniform bool use_horiz = true;             // 关掉横向 = 纯上下呼吸

// 底部锁定：画面最下方 12% 不位移，避免脚/桌边被拉出画面
uniform float lock_bottom : hint_range(0.0, 0.5) = 0.12;

// ── 眼睛保护（2026-11-10 主人要求「仅头纵影响双眼，头发不碰眼睛」）─────────
// 已实现，但**在 GDScript 端烘焙权重时做**（portrait_breath_mesh._build_mesh 的 face_gate）：
//   脸上的头发权重直接烘成 0，被剥掉的份额转给头颈通道，眼睛只跟 head_y 走。
// 为什么不在这里用 texture(face_tex, UV) 做顶点采样门控：
//   gl_compatibility 下**顶点着色器里的纹理采样不生效**（实测开/关该 uniform
//   渲染结果字节级完全相同），写了也是死代码，别再加回来。
// 记录一次踩坑：靠「顶点色权重为 0」不足以保证脸上像素不动 —— 顶点色只存在顶点上，
// 三角形内部靠插值，边界三角形仍会把少量头发权重渗进脸边羽化带
// （实测脸芯 p50=0、只有边缘一圈在动，属可接受）。

void vertex() {
	// 顶点色即权重场（R=胸 G=腹 B=头 A=发）。注意已被 modulate 乘过 → 上层必须 modulate 白
	vec4 w = COLOR;
	float wc = w.r;
	float wb = w.g;
	float wh = w.b;
	float wr = w.a;      // 头发
	// 第 5 通道（翅膀）来自 CUSTOM0（ARRAY_CUSTOM0 / R_FLOAT，见 gdshader 头注释）。
	// 为什么不用顶点色：RGBA 四通道已满，翅膀需要**独立相位**，并进任一通道都会
	// 按比例削掉原通道幅度。为什么不在 fragment 用纹理采样：本项目 gl_compatibility，
	// **顶点着色器里的 texture() 不生效**，而位移必须发生在 vertex()。
	float wg = CUSTOM0.x;

	// 底部锁定：越靠下权重越小，保证画面下沿不动
	// 底部锁定。lock_bottom=0 表示「不锁底」，但 smoothstep(0,0,x) 在 GLSL 里是
	// 未定义行为（实测 NVIDIA 上整段返回 0 → 全图位移归零，看起来像呼吸完全失效）。
	// 显式分支：0 直接给 1，否则走 smoothstep。
	float lock = lock_bottom <= 0.0001 ? 1.0 : smoothstep(0.0, lock_bottom, 1.0 - UV.y);

	// 三个部位的相位（滞后用弧度）
	float lag_b = radians(belly_lag_deg);
	float lag_h = radians(head_lag_deg);
	float lag_x = radians(x_lag_deg);
	float lag_w = radians(wing_lag_deg);

	// 横向与纵向用**不同相位**：x 走完整 cos 往复，y 走带偏移的 sin（偏上提）
	float sx = cos(phase - lag_x);
	float sy = sin(phase) * (1.0 - y_bias) + y_bias;
	float sx_b = cos(phase - lag_b - lag_x);
	float sy_b = sin(phase - lag_b) * (1.0 - y_bias) + y_bias;
	float sy_h = sin(phase - lag_h) * (1.0 - y_bias) + y_bias;

	float hx = use_horiz ? 1.0 : 0.0;   // 横向总开关

	// 胸腔：横向外扩（左右反向）与纵向起伏各自独立
	float chest_x_dir = sign(VERTEX.x);
	VERTEX.x += chest_x_dir * wc * sx * chest_x * amp * lock * hx;
	VERTEX.y -= wc * (sy - y_bias) * chest_y * amp * lock;

	// 腹部：更小幅度、滞后相位
	VERTEX.x += sign(VERTEX.x) * wb * sx_b * belly_x * amp * lock * hx;
	VERTEX.y -= wb * (sy_b - y_bias) * belly_y * amp * lock;

	// 头颈：只垂直，不做横向（避免五官被左右拉扯）
	VERTEX.y += wh * (sy_h - y_bias) * head_y * amp * lock;

	// 头发：相位随高度连续滞后（UV.y 越大越靠下 = 越发梢）
	float hair_lag = radians(hair_lag_per_height) * UV.y;
	float sh_x = cos(phase - hair_lag - lag_x);
	float sh_y = sin(phase - hair_lag) * (1.0 - y_bias) + y_bias;
	// 横向飘：整片同向摆（头发是被气流带着走，不是左右对称扩张）
	VERTEX.x += wr * sh_x * hair_x * amp * lock * hx;
	VERTEX.y += wr * (sh_y - y_bias) * hair_y * amp * lock;

	// ── 翅膀：独立相位（2026-11-11）────────────────────────────────────
	// 相位公式 = phase - wing_lag_deg，跟胸/腹/头/发各走各的滞后角。
	// 横向用 sign(VERTEX.x) 做**对称外展**（左右翅膀朝相反方向张开，
	// 和胸腔同一个道理：翅膀展开不是整片往同一侧平移）。
	// 纵向用带 y_bias 的 sin，与胸腔同一条曲线，保证「吸/呼」的观感一致。
	// 注：wing 权重已从胸/腹通道里扣掉（见 portrait_breath_mesh 的 inv_wing），
	//     所以翅膀区域只受这一项驱动，不会和身体相位叠加出乱抖。
	float sx_w = cos(phase - lag_w - lag_x);
	float sy_w = sin(phase - lag_w) * (1.0 - y_bias) + y_bias;
	VERTEX.x += sign(VERTEX.x) * wg * sx_w * wing_x * amp * lock * hx;
	VERTEX.y += wg * (sy_w - y_bias) * wing_y * amp * lock;
}

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
