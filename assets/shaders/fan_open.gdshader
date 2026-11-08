shader_type canvas_item;
render_mode unshaded;

// 折扇开屏转场（2026-11-08，Kweno 专属）：一把大折扇从左下扇轴展开，
// 扇面过处显现新立绘——扇骨金线 + 展开前缘微光。配青花瓷千金的手折扇。
// 扇轴画在画面左下外侧，扇面角度从左(A1)往右(A0)逐扇骨扫开。

uniform sampler2D tex_prev : source_color, filter_linear;
uniform sampler2D tex_next : source_color, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;

const float A0 = -0.10;    // 收拢侧终止角（右，弧度，画面上方为负）
const float A1 = -1.95;    // 展开侧起始角（左）
const float RIBS = 10.0;   // 扇骨数
const float R_FAR = 1.6;   // 扇面半径（覆盖全画布）

void fragment() {
	vec2 pivot = vec2(0.05, 1.15);
	vec2 rel = UV - pivot;
	float r = length(rel);
	float ang = atan(rel.y, rel.x);

	// 前缘角：按扇骨逐格推进，格内再平滑（像有人手腕一抖一抖地开扇）
	float k = clamp(progress, 0.0, 1.0) * RIBS;
	float lead = A1 + (floor(k) + smoothstep(0.0, 1.0, fract(k))) * ((A0 - A1) / RIBS);

	// 扇面：角度落在 [A1, lead] 且在半径内 → 新立绘
	float opened = step(A1, ang) * step(ang, lead) * step(r, R_FAR);

	// 扇骨金线：只点在「已展开、且离开前缘一段距离」的扇面上，低调
	float w = (A0 - A1) / RIBS;
	float rib_ang = A1 + floor((ang - A1) / w) * w;
	float rib = exp(-abs(ang - rib_ang) * 110.0) * opened * step(0.5, floor((ang - A1) / w));

	// 展开前缘亮线（扇面的「边」——这圈才是主角）
	float lead_line = exp(-abs(ang - lead) * 45.0) * step(r, R_FAR)
			* step(0.0001, progress) * step(progress, 0.9999);

	vec4 prev_c = texture(tex_prev, UV);
	vec4 next_c = texture(tex_next, UV);
	vec4 col = mix(prev_c, next_c, opened);

	// 刚展开的扇面有一短段高光再沉降
	float fresh = exp(-abs(ang - lead) * 10.0) * opened;
	col.rgb += vec3(1.0, 0.88, 0.55) * (rib * 0.13 + lead_line * 0.85 + fresh * 0.14);

	COLOR = col;
}
