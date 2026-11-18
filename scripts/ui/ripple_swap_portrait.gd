class_name RippleSwapPortrait
extends Control
## 角色立绘转场控件（2026-11-08 起**一人一款**）：
##   - RIPPLE 水波扩散（DeepDeek 女仆·柔和向）：中心水花不规则扩散，波内显现新立绘
##   - FAN    折扇开屏（Kweno 千金·青花折扇）：扇面从左往右逐扇骨展开
##   - SLASH  X 双斩（Grock 毒舌小恶魔·扛 X 巨斧）：两道剑光交叉劈开，四片滑开坠落
##   - HEX    龙鳞剥落（ChatPPT 白龙千金）：六边形鳞片底部先剥、沿线翘金边
##   - PETAL  白花瓣遮幕（Kweno 千问·2026-11-11 主人指定）：花瓣自左下涌向右上，
##            密到遮满全屏后散开。遮幕期间换图，所以终态绝对干净。
##
## 用法：
##   set_portrait(tex_a)          → 初始立绘
##   swap_to(tex_b)               → 按 style 播转场，结束后 tex_b 成为当前立绘
##   debug_prepare(a, b) + debug_set_progress(p) → 逐帧验收
## 约束：tex_prev/tex_next 用同宽高比贴图（内部按 UV 直采）。

signal swap_finished

enum Style { RIPPLE, FAN, SLASH, HEX, PETAL }

const SHADERS := {
	Style.RIPPLE: preload("res://assets/shaders/ripple_reveal.gdshader"),
	Style.FAN: preload("res://assets/shaders/fan_sprite_reveal.gdshader"),
	Style.SLASH: preload("res://assets/shaders/x_slash.gdshader"),
	Style.HEX: preload("res://assets/shaders/hex_scale.gdshader"),
	Style.PETAL: preload("res://assets/shaders/petal_veil_reveal.gdshader"),
}
## 白花瓣图集（4×4，透明底；2026-11-11 程序化生成，生图通道 503 时的替代）
const PETAL_TEX_SHEET := preload("res://assets/art/fx/petals-sheet.png")
## 花瓣风格换图的进度点：白幕在这个位置最厚，前一张图已被完全遮住。
## 为什么不是 0.5：白幕从 0.30 渐入、0.58 起渐出，0.56 处仍在峰值内侧，
## 留一点缓冲吸收 tween 的帧量化误差（4.7 的 tween 一帧可能跳 2~3%）。
const PETAL_SWAP_AT := 0.56
## 实物扇子素材（2026-11-08 主人定稿：像素风扇布——合拢竖在左缘，展开扫满全画框，无支架）
const FAN_TEX_CLOTH_PX := preload("res://assets/art/fx/fan-cloth-pixel.png")
## 画面侧扇轴（左下角内收一点）
const FAN_PIVOT_S := Vector2(0.06, 0.94)
## 一次 swap 的总时长（秒）。demo 页有调速滑杆，主人的数值存 GameSettings 跨启动记住。
var swap_time := 0.7
var style: int = Style.RIPPLE

var _mat: ShaderMaterial = null
var _swapping := false
var _current: Texture2D = null
## FAN 风格专用状态
var _fan_swapped := false   ## 盖满后，背后已换成新立绘
var _fan_next: Texture2D = null
## PETAL 风格专用状态
var _petal_swapped := false
var _petal_next: Texture2D = null


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := ColorRect.new()
	rect.name = "RippleRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADERS[style]
	_mat.set_shader_parameter("progress", 0.0)
	rect.material = _mat
	add_child(rect)
	resized.connect(_update_geo)
	_update_geo()


func _update_geo() -> void:
	if _mat == null or size.y <= 0.0:
		return
	var asp := size.x / size.y
	_mat.set_shader_parameter("aspect", asp)
	# max_dist：水波用（中心到最远角，aspect 校正 + 少量余量）；其余风格忽略它
	_mat.set_shader_parameter("max_dist", Vector2(0.5 * asp, 0.5).length() + 0.02)
	# PETAL 用 aspect 做极坐标圆化（它有自己的 _update_petal_geo）
	if style == Style.PETAL:
		_update_petal_geo()


func set_portrait(tex: Texture2D) -> void:
	_current = tex
	if _mat != null:
		_mat.set_shader_parameter("tex_prev", tex)
		_mat.set_shader_parameter("progress", 0.0)


func swap_to(tex: Texture2D) -> void:
	if _swapping or tex == null or _mat == null or tex == _current:
		return
	_swapping = true
	if style == Style.FAN:
		# 像素扇布透明转场：对角线起手 → 向两边展开盖满 → 背后换图 → 逆向收回
		_fan_swapped = false
		_fan_next = tex
		_mat.shader = SHADERS[style]
		_mat.set_shader_parameter("tex_fan", FAN_TEX_CLOTH_PX)
		_mat.set_shader_parameter("tex_next", tex)
		_mat.set_shader_parameter("sweep", 0.0)
		_mat.set_shader_parameter("dim", 0.0)
		_update_fan_geo()
		var tw := create_tween()
		tw.tween_method(_apply_fan, 0.0, 1.0, maxf(0.05, swap_time))
		tw.tween_callback(func() -> void:
			_mat.set_shader_parameter("tex_prev", tex)
			_mat.set_shader_parameter("sweep", 0.0)
			_mat.set_shader_parameter("dim", 0.0)
			_current = tex
			_swapping = false
			swap_finished.emit())
		return
	_mat.shader = SHADERS[style]          # 转场风格在开跑瞬间切换
	_mat.set_shader_parameter("tex_next", tex)
	_mat.set_shader_parameter("progress", 0.0)
	_update_geo()
	if style == Style.SLASH:
		_apply_slash_params(true)
	elif style == Style.PETAL:
		# 遮幕式：白幕最厚处（PETAL_SWAP_AT）把背后换成新图，
		# 之后的散开段露出的就已经是新立绘了。
		_mat.set_shader_parameter("tex_petal", PETAL_TEX_SHEET)
		_petal_swapped = false
		_petal_next = tex
		_update_petal_geo()
	if style == Style.PETAL:
		var tp := create_tween()
		tp.tween_method(func(v: float) -> void:
			_set_progress_petal(v), 0.0, 1.0, maxf(0.05, swap_time)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tp.tween_callback(func() -> void:
			_mat.set_shader_parameter("tex_prev", tex)
			_mat.set_shader_parameter("progress", 0.0)
			_current = tex
			_swapping = false
			swap_finished.emit())
		return
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_mat.set_shader_parameter("progress", v), 0.0, 1.0, maxf(0.05, swap_time)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		_mat.set_shader_parameter("tex_prev", tex)
		_mat.set_shader_parameter("progress", 0.0)
		_current = tex
		_swapping = false
		swap_finished.emit())


## 乱斩参数（随机种子）：6 刀，角度/截距/起刀时刻全随机；第一刀偏中保证切得大。
## shake=true 时每刀落下画面小震一下。
func _apply_slash_params(shake: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var asp: float = (size.x / size.y) if size.y > 0.0 else 0.75
	var arr := PackedVector4Array()
	for k in 5:
		# 方向：180° 内分槽 + 大抖动（法线反向等价，180° 已覆盖所有直线方向；
		# 分槽只避免两条线几乎重合，抖动给足随机感）
		var ang := deg_to_rad(k * 36.0 + rng.randf_range(-28.0, 28.0))
		var nx := cos(ang)
		var ny := sin(ang)
		# 截距：线段到原点的有符号距离。有效范围 = 该方向画面半投影，
		# 在范围内**随机撒**（而不是都穿过中心附近）→ 均匀随机分布，不会绕中心切蛋糕
		var proj: float = absf(nx) * asp * 0.5 + absf(ny) * 0.5
		var c: float = rng.randf_range(-proj * 0.82, proj * 0.82)
		var delay: float = 0.04 + k * 0.05 + rng.randf_range(-0.008, 0.008)
		arr.append(Vector4(nx, ny, c, delay))
	_mat.set_shader_parameter("slashes", arr)
	_mat.set_shader_parameter("seed_n", rng.randf_range(0.0, 10.0))
	if not shake:
		return
	var base_pos := position
	var dur := maxf(0.05, swap_time)
	for k in 5:
		var sh := create_tween()
		sh.tween_interval(arr[k].w * dur)
		for i in 3:
			sh.tween_property(self, "position",
					base_pos + Vector2(randf_range(-7.0, 7.0), randf_range(-6.0, 6.0)), 0.025)
		sh.tween_property(self, "position", base_pos, 0.04)


## 像素扇布分镜（p 0→1，由 tween/逐帧验收推进）：
##   0~0.06   起手：扇布收在起始边（底边侧）
##   0.06~0.52 单边展开：前缘从起始边一路扫到另一边，扇面渐盖满全框
##   0.52~0.60 盖满定住——背后已换成新立绘
##   0.60~0.92 逆向收拢回起始边，露出新立绘
##   0.92~1   收尾淡出
func _update_fan_geo() -> void:
	if _mat == null or size.y <= 0.0:
		return
	var asp := size.x / size.y
	_mat.set_shader_parameter("pivot_s", FAN_PIVOT_S)
	_mat.set_shader_parameter("aspect", asp)

	# ── 角度带 ──
	# 扇轴在左下角，画面在它的右上方。可见角跨度接近 360°（左边中段能到 -174°，
	# 右下能到 +150°）—— **用整段做扇形是错的**：跨度 >360° 会让归一化退化，
	# 画面被切成两块（实测出现过左右两个分离色块）。
	# 正确做法：扇形只覆盖「轴 → 画面中心」方向的一个自然扇面（约 130°），
	# 视觉上是真扇子；剩余区域由 shader 在 sweep 末段线性补满，保证终态全覆盖。
	var px: float = FAN_PIVOT_S.x
	var py: float = FAN_PIVOT_S.y
	var to_center: float = rad_to_deg(atan2(0.5 - py, (0.5 - px) * asp))
	var half_span := 65.0
	_mat.set_shader_parameter("a_start", to_center + half_span)
	_mat.set_shader_parameter("a_end", to_center - half_span)
	# 半径取到最远角（右上 ≈1.92）留余量
	_mat.set_shader_parameter("fan_r", 2.1)
	_mat.set_shader_parameter("r_scale", 0.6)


func _apply_fan(p: float) -> void:
	if _mat == null:
		return
	var sweep := 0.0
	var dim := 0.0
	if p < 0.06:
		# 啪：对角线出现（合拢的扇就是这条线）
		sweep = 0.03
		dim = 0.0
	elif p < 0.5:
		# 向两边展开：扇布绕对角线对称开花，扇骨从对角线向两侧长出
		var k: float = (p - 0.06) / 0.44
		sweep = 0.03 + 0.97 * smoothstep(0.0, 1.0, k)
		dim = 0.92 * sweep
	elif p < 0.58:
		# 盖满：定住（背后已换成新立绘）
		sweep = 1.0
		dim = 0.92
	elif p < 0.92:
		# 逆向收拢回对角线，露出新立绘
		var k: float = (p - 0.58) / 0.34
		sweep = 1.0 - 0.97 * smoothstep(0.0, 1.0, k)
		dim = 0.92 * sweep
	else:
		# 收尾：对角线也淡出归零
		sweep = 0.03 * (1.0 - (p - 0.92) / 0.08)
		dim = 0.0
	_mat.set_shader_parameter("sweep", sweep)
	_mat.set_shader_parameter("dim", dim)
	# 完全盖住的瞬间，背后换成新立绘
	if p >= 0.5 and not _fan_swapped and _fan_next != null:
		_mat.set_shader_parameter("tex_prev", _fan_next)
		_current = _fan_next
		_fan_swapped = true


func is_swapping() -> bool:
	return _swapping


## 花瓣风格的几何：只需 aspect（花瓣按画面比例圆化，避免横向拉扁）
func _update_petal_geo() -> void:
	if _mat == null or size.y <= 0.0:
		return
	var asp := size.x / size.y
	_mat.set_shader_parameter("aspect", asp)
	_mat.set_shader_parameter("tex_petal", PETAL_TEX_SHEET)


## 花瓣风格的进度推进：到遮幕最厚处换图（幂等，重复调用无副作用）
func _set_progress_petal(p: float) -> void:
	_mat.set_shader_parameter("progress", p)
	if p >= PETAL_SWAP_AT and not _petal_swapped and _petal_next != null:
		_mat.set_shader_parameter("tex_prev", _petal_next)
		_current = _petal_next
		_petal_swapped = true


## 逐帧验收：把两张图摆好、直接停在某个进度（不播动画）
func debug_prepare(prev: Texture2D, next: Texture2D) -> void:
	_swapping = false
	_mat.shader = SHADERS[style]
	_mat.set_shader_parameter("tex_prev", prev)
	_mat.set_shader_parameter("tex_next", next)
	_mat.set_shader_parameter("progress", 0.0)
	_update_geo()
	_current = prev
	if style == Style.FAN:
		_fan_swapped = false
		_fan_next = next
		_mat.set_shader_parameter("tex_fan", FAN_TEX_CLOTH_PX)
		_update_fan_geo()
	elif style == Style.SLASH:
		_apply_slash_params(false)
	elif style == Style.PETAL:
		_petal_swapped = false
		_petal_next = next
		_update_petal_geo()


func debug_set_progress(p: float) -> void:
	if style == Style.FAN:
		_apply_fan(clampf(p, 0.0, 1.0))
	elif style == Style.PETAL:
		_set_progress_petal(clampf(p, 0.0, 1.0))
	elif _mat != null:
		_mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))
