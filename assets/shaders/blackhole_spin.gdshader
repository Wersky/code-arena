shader_type canvas_item;
render_mode unshaded, blend_mix;

// GPT 角色「血色黑洞」旋转特效（2026-11-10 主人要求）。
//
// 为什么单独一个 shader：
//   黑洞不是「呼吸」——它要的是**持续旋转扭曲**，而呼吸是往复的纵向位移。
//   两者语义不同、周期不同、不该混在一个 shader 里互相牵制。
//   本 shader 只作用于黑洞那一小块区域（由 tex_region 限定），
//   呼吸层继续管头发/脸/身体/翅膀，互不干扰。
//
// 视觉构成（分三层叠加）：
//   ① 旋涡扭曲：极坐标下把 UV 沿 θ 方向按半径衰减地扭转 → 内圈转得飞快、外圈几乎不动
//   ② 吸积盘亮环：扭曲后的采样再按半径加权提亮一圈，形成「事件视界边缘发亮」的观感
//   ③ 内圈纯黑：半径小于核心阈值的地方强制压到接近全黑，保证中心是「洞」不是「漩涡图」
//
// 注意：本文件严禁出现 maxf —— Godot shader 只有 max，maxf 会静默白屏。

uniform sampler2D tex_src : source_color, filter_linear;
// 黑洞区域遮罩：白=黑洞所在，黑=不处理（用 alpha 混合回原图，区域外完全不生效）
uniform sampler2D tex_region : hint_default_black, filter_linear;

uniform float spin : hint_range(0.0, 1.0) = 0.0;   // 旋转进度，由 GDScript 每帧累加
uniform float twist : hint_range(0.0, 6.0) = 2.2;  // 扭转强度（弧度，内圈最大）
uniform float falloff : hint_range(0.5, 8.0) = 2.6; // 扭转随半径衰减的指数
uniform float core : hint_range(0.0, 0.5) = 0.16;   // 核心黑洞半径（UV 单位）
uniform float rim_boost : hint_range(0.0, 2.0) = 0.75; // 事件视界亮环强度
uniform vec2 center = vec2(0.5, 0.5);               // 黑洞中心的 UV 坐标（GDScript 传入）
uniform float aspect = 1.0;                          // 宽/高，把极坐标修成圆

void fragment() {
	vec4 base = texture(tex_src, UV);
	float m = texture(tex_region, UV).r;
	if (m < 0.01) {
		COLOR = base;          // 区域外直接放行，一点不改
	} else {
		// ---- 1. 转到以黑洞中心为原点的、aspect 校正过的极坐标 ----
		vec2 p = UV - center;
		p.x *= aspect;
		float r = length(p);
		float a = atan(p.y, p.x);

		// ---- 2. 旋涡扭转：半径越小转得越多（falloff 控制衰减陡峭度）----
		float rr = max(r, 1e-4);
		float swirl = twist * spin * pow(clamp(core / rr, 0.0, 1.0), falloff);
		float na = a + swirl;

		// ---- 3. 用扭转后的角度重采样（半径不变，只转不缩）----
		vec2 sp = vec2(cos(na), sin(na)) * r;
		sp.x /= aspect;
		vec2 suv = clamp(center + sp, vec2(0.0), vec2(1.0));
		vec3 swirled = texture(tex_src, suv).rgb;

		// ---- 4. 事件视界亮环：核心外侧一圈提亮，模拟吸积盘边缘 ----
		float ring = smoothstep(core * 2.4, core * 1.05, r) * smoothstep(core * 0.85, core * 1.15, r);
		vec3 rim_col = vec3(1.0, 0.28, 0.20);           // 血红
		vec3 col = swirled + rim_col * ring * rim_boost;

		// ---- 5. 核心压黑：半径 < core 处强制接近全黑 ----
		float hole = smoothstep(core, core * 0.72, r);
		col = mix(col, vec3(0.015, 0.0, 0.005), hole);

		// ---- 6. 按遮罩强度混回原图（边缘软过渡，不会出现硬边）----
		COLOR = vec4(mix(base.rgb, col, clamp(m, 0.0, 1.0)), base.a);
	}
}
