shader_type canvas_item;
render_mode unshaded, blend_mix;

// GPT 角色「血色黑洞」全效（2026-11-10 起做旋转，2026-11-11 扩成四层特效）。
//
// ── 为什么独立一层、不并进呼吸 shader ──────────────────────────────────
//   呼吸是**往复**的纵向位移（sin 来回），黑洞是**持续单向**旋转（累加不回头）。
//   两者节奏、语义、时间模型都不同：塞进同一个 shader 会互相牵制。
//
// ⚠ 血泪坑（V4 呼吸引入后实测）：本层**绝不能重绘整个画面**。
//   早期版本在遮罩外直接 `COLOR = base`（基图原样），等于把整张不动的立绘
//   重新画了一遍盖在呼吸层上 —— GPT 的呼吸因此完全消失（位移像素仅 133）。
//   **遮罩外一律 `COLOR = vec4(0.0)`**，一个像素都不许碰。
//
// ⚠ 另一条：本文件严禁出现 maxf / minf / clampf —— 那是 GDScript 的函数名，
//   Godot shader 里只有 max / min / clamp，写错会静默白屏。
//   gl_compatibility 下同样禁用 hint_screen_texture。
//
// ── 四层特效（全部只在遮罩内生效）─────────────────────────────────────
//   ① 旋涡扭转    极坐标下按半径衰减地把像素沿 θ 扭转（内圈快、外圈近乎不动）
//   ② 引力扭曲    极轻的径向内拉（内圈明显、外圈无感），强化「被吸进去」的读感
//   ③ 吸积盘流光  核外一圈**倾斜的椭圆盘**，三瓣亮度 + 细密纹理 + 冷暖分侧，
//                 随 spin 单向旋转；盘面用椭圆归一（因为遮罩本身是 1.82:1 扁盘，
//                 拿圆去算会被遮罩裁出「翅膀」形，非常假）
//   ④ 事件视界辉光 紧贴圆形核心的青白亮环，亮度随 beat 搏动
//   ⑤ 核心压黑    半径小于核心阈值处强制近全黑，并把半径做细微呼吸
//
// ── 三条时间轴（各自独立、都单调递增）─────────────────────────────────
//   spin  6.00s / 圈 —— 旋涡 + 吸积盘旋转
//   pulse 2.83s / 次 —— 快速搏动（beat 主成分）
//   surge 7.10s / 次 —— 慢速涌动（beat 次成分，与 pulse 叠加出非整数拍）
//   三个周期两两都不成整数比，且都**避开角色呼吸默认的 4.0s**
//   （4.0/2.83=1.41、4.0/7.10=0.56），保证黑洞永远不和身体同频。

uniform sampler2D tex_src : source_color, filter_linear;
uniform sampler2D tex_region : hint_default_black, filter_linear;

uniform float spin : hint_range(0.0, 1.0) = 0.0;    // 旋转相位（0..1 循环）
uniform float pulse : hint_range(0.0, 1.0) = 0.0;   // 快搏动相位
uniform float surge : hint_range(0.0, 1.0) = 0.0;   // 慢涌动相位

uniform vec2 center = vec2(0.3581, 0.1218);         // 黑洞中心 UV
uniform float aspect = 1.7777778;                   // 宽/高，做极坐标圆化
uniform float core : hint_range(0.004, 0.20) = 0.0235; // 核心半径（height 单位）

// 吸积盘椭圆的半轴（height 单位）。由 Python 量遮罩得到：51px / 28px @900 高
uniform vec2 disk_half = vec2(0.0567, 0.0311);

uniform float twist : hint_range(0.0, 8.0) = 2.9;    // 扭转强度（弧度，内圈最大）
uniform float falloff : hint_range(0.5, 8.0) = 1.85; // 扭转随半径衰减的指数
uniform float distort : hint_range(0.0, 0.30) = 0.055; // 引力内拉强度
uniform float disk_gain : hint_range(0.0, 1.5) = 0.20; // 吸积盘亮度
uniform float rim_gain : hint_range(0.0, 1.5) = 0.20;  // 辉光亮度
uniform float pulse_amt : hint_range(0.0, 0.4) = 0.13; // 核心半径搏动幅度

const vec3 HOLE_COL = vec3(0.010, 0.005, 0.012);  // 洞里的近黑色（不是纯黑，留一点紫）

void fragment() {
	float m = texture(tex_region, UV).r;
	// ── 硬边界：遮罩外**必须透明**，绝不能输出基图（否则盖掉下面的呼吸层）──
	if (m < 0.01) {
		COLOR = vec4(0.0);
	} else {
		vec4 base = texture(tex_src, UV);
		float cov = smoothstep(0.01, 0.22, m);   // 遮罩软过渡，避免硬边

		// ── 三条时间轴合成一个 beat（0..1），只用来驱动亮度/半径，绝不驱动方向 ──
		float pw = 0.5 - 0.5 * cos(pulse * 6.28318530718);
		float sg = 0.5 - 0.5 * cos(surge * 6.28318530718);
		float beat = clamp(pw * 0.74 + sg * 0.26, 0.0, 1.0);

		// 核心半径随 beat 小幅呼吸（±6.5%）
		float cr = core * (1.0 + pulse_amt * (beat - 0.5));

		// ── 以中心为原点的、aspect 校正过的极坐标（height 单位 → 圆不变形）──
		vec2 p = vec2((UV.x - center.x) * aspect, UV.y - center.y);
		float r = length(p);
		float ang = atan(p.y, p.x);
		float rn = r / max(cr, 1e-4);              // 圆形归一（核心/辉光用）
		float safe_r = max(r, 1e-4);

		// ── ① 旋涡扭转 + ② 引力内拉 ──
		// 扭转：半径越小转得越多，pow 衰减；r < cr 时被 clamp 封顶，不会无限转
		float swirl = twist * spin * pow(clamp(cr / safe_r, 0.0, 1.0), falloff);
		float na = ang + swirl;
		// 内拉：只在内圈生效，2.6 个核心半径外完全无感（重了会糊）
		float pull = distort * (1.0 - smoothstep(0.9, 2.6, rn));
		float sr = r * (1.0 - pull);

		vec2 suv = clamp(center + vec2(cos(na) * sr / aspect, sin(na) * sr), vec2(0.0), vec2(1.0));
		vec3 swirled = texture(tex_src, suv).rgb;

		// ── ③ 吸积盘：椭圆归一半径 ──
		// 为什么单独一套半径：遮罩本身是 1.82:1 的扁椭圆。若用圆半径算盘面，
		// 盘在上下方向会先撞到遮罩边缘、左右方向却被 cutoff 掐掉 → 变成「翅膀」。
		// 用椭圆半径算，盘面天然是斜看的盘，边缘由遮罩统一收口。
		float ren = length(vec2(p.x / disk_half.x, p.y / disk_half.y));

		// 冷暖分侧：用**扭转后**的方位角，让色相跟着旋涡一起转
		float side = 0.5 + 0.5 * cos(na + 2.1);
		// side=1 → 暖侧(偏金白)，side=0 → 冷侧(青蓝)，呼应 GPT 的白金龙鳞
		vec3 tint = vec3(0.50 + 0.50 * side, 0.82 - 0.16 * side, 1.00 - 0.68 * side);

		// 盘带：内 0.42~0.66 起亮、0.90~1.06 收口（都是 ren 归一，1.0 = 遮罩外缘）
		float band = smoothstep(0.42, 0.66, ren) * (1.0 - smoothstep(0.90, 1.06, ren));
		float lobes = 0.22 + 0.78 * (0.5 + 0.5 * cos(3.0 * na + 0.5));       // 三瓣
		float grain = 0.66 + 0.54 * (0.5 + 0.5 * cos(11.0 * na - ren * 12.0)); // 细纹
		float disk_i = band * lobes * grain * (0.80 + 0.44 * beat);

		// ── ④ 事件视界辉光：紧贴圆形核心 ──
		float rim = smoothstep(0.94, 1.06, rn) * (1.0 - smoothstep(1.06, 1.62, rn));
		vec3 rim_col = vec3(0.62 + 0.38 * side, 0.92 - 0.06 * side, 1.00 - 0.24 * side);
		float rim_i = rim * (0.40 + 0.95 * beat);

		// 叠加光（软压缩：1-exp 把高光压住，避免盘面糊成纯白丢掉细节）
		vec3 glow = tint * (disk_i * disk_gain) + rim_col * (rim_i * rim_gain);
		glow = vec3(1.0) - exp(-glow * 1.25);
		vec3 col = swirled + glow;

		// ── ⑤ 核心压黑：rn < 1.02 处强制近全黑，保证中心是「洞」不是「漩涡图」──
		float hole = 1.0 - smoothstep(0.74, 1.02, rn);
		col = mix(col, HOLE_COL, hole);

		// 按遮罩强度合成：区域内显示特效，区域外透明（交还给呼吸层）
		COLOR = vec4(mix(base.rgb, col, cov), cov * base.a);
	}
}
