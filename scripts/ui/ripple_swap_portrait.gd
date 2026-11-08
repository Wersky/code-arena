class_name RippleSwapPortrait
extends Control
## 角色立绘转场控件（2026-11-08 起**一人一款**）：
##   - RIPPLE 水波扩散（DeepDeek 女仆·柔和向）：中心水花不规则扩散，波内显现新立绘
##   - FAN    折扇开屏（Kweno 千金·青花折扇）：扇面从左往右逐扇骨展开
##   - SLASH  X 双斩（Grock 毒舌小恶魔·扛 X 巨斧）：两道剑光交叉劈开，四片滑开坠落
##   - HEX    龙鳞剥落（ChatPPT 白龙千金）：六边形鳞片底部先剥、沿线翘金边
##
## 用法：
##   set_portrait(tex_a)          → 初始立绘
##   swap_to(tex_b)               → 按 style 播转场，结束后 tex_b 成为当前立绘
##   debug_prepare(a, b) + debug_set_progress(p) → 逐帧验收
## 约束：tex_prev/tex_next 用同宽高比贴图（内部按 UV 直采）。

signal swap_finished

enum Style { RIPPLE, FAN, SLASH, HEX }

const SHADERS := {
	Style.RIPPLE: preload("res://assets/shaders/ripple_reveal.gdshader"),
	Style.FAN: preload("res://assets/shaders/fan_sprite_reveal.gdshader"),
	Style.SLASH: preload("res://assets/shaders/x_slash.gdshader"),
	Style.HEX: preload("res://assets/shaders/hex_scale.gdshader"),
}
## 实物扇子素材（2026-11-08 主人定稿：不用透明遮罩，用真实生成的青花扇·动漫赛璐璐）
const FAN_TEX_CLOSED := preload("res://assets/art/fx/fan-closed.png")
const FAN_TEX_OPEN := preload("res://assets/art/fx/fan-open.png")
## 扇贴图实测参数（tools 侧 numpy 量的：扇钉位置 / 扇骨角跨 / 纸面半径）
const FAN_PIVOT_T := Vector2(0.068, 0.903)
const FAN_TEX_MID := -59.0
const FAN_TEX_HALF := 48.0
const FAN_R_SCALE := 0.975
## 画面侧扇轴（左下角内收一点）
const FAN_PIVOT_S := Vector2(0.06, 0.94)
## 一次 swap 的总时长（秒）。demo 页有调速滑杆，主人的数值存 GameSettings 跨启动记住。
var swap_time := 0.7
var style: int = Style.RIPPLE

var _mat: ShaderMaterial = null
var _swapping := false
var _current: Texture2D = null
## 实物扇子（FAN 风格专用）
var _fan_closed: TextureRect = null
var _fan_open: TextureRect = null
var _fan_swapped := false   ## 展开完全遮住后，背后已换成新立绘
var _fan_next: Texture2D = null


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
	_build_fan_sprites()


func _build_fan_sprites() -> void:
	_fan_closed = TextureRect.new()
	_fan_closed.name = "FanClosed"
	_fan_closed.texture = FAN_TEX_CLOSED
	_fan_closed.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fan_closed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fan_closed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fan_closed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fan_closed.visible = false
	add_child(_fan_closed)
	_fan_open = TextureRect.new()
	_fan_open.name = "FanOpen"
	_fan_open.texture = FAN_TEX_OPEN
	_fan_open.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fan_open.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fan_open.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_fan_open.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fan_open.visible = false
	add_child(_fan_open)


func _update_geo() -> void:
	if _mat == null or size.y <= 0.0:
		return
	var asp := size.x / size.y
	_mat.set_shader_parameter("aspect", asp)
	# max_dist：水波用（中心到最远角，aspect 校正 + 少量余量）；其余风格忽略它
	_mat.set_shader_parameter("max_dist", Vector2(0.5 * asp, 0.5).length() + 0.02)


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
		# 实物扇子：啪→绕左下扇轴绽放盖满→背后换图→逆向收走（sweep/dim 驱动）
		_fan_swapped = false
		_fan_next = tex
		_mat.shader = SHADERS[style]
		_mat.set_shader_parameter("tex_fan", FAN_TEX_OPEN)
		_mat.set_shader_parameter("tex_next", tex)
		_mat.set_shader_parameter("sweep", 0.0)
		_mat.set_shader_parameter("dim", 0.0)
		_update_fan_geo()
		_fan_closed.visible = false
		_fan_open.visible = false
		var tw := create_tween()
		tw.tween_method(_apply_fan, 0.0, 1.0, maxf(0.05, swap_time))
		tw.tween_callback(func() -> void:
			_fan_closed.visible = false
			_fan_open.visible = false
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


## 实物扇子分镜（p 0→1，由 tween/逐帧验收推进）：
##   0~0.16  啪：合拢扇拍上立绘（回弹缩小）
##   0.16~0.46 从中间向左右展开（scale.x 中心为轴 0→1），完全遮住立绘
##   0.46~0.56 扇面定住——p≥0.5 时背后已换成新立绘
##   0.56~0.88 逆向收扇（scale.x 1→0），露出新立绘
##   0.88~1  合拢扇滑走淡出
func _update_fan_geo() -> void:
	if _mat == null or size.y <= 0.0:
		return
	var asp := size.x / size.y
	# 画面角度带（相对左下扇轴，aspect 校正后，度）：画框四角的 atan 范围
	var ur := Vector2((size.x - FAN_PIVOT_S.x * size.x) * asp,
			-(FAN_PIVOT_S.y * size.y))
	var ul := Vector2(-(FAN_PIVOT_S.x * size.x) * asp, -(FAN_PIVOT_S.y * size.y))
	var lr := Vector2((size.x - FAN_PIVOT_S.x * size.x) * asp,
			(1.0 - FAN_PIVOT_S.y) * size.y)
	var a_ur := rad_to_deg(atan2(ur.y, ur.x))
	var a_ul := rad_to_deg(atan2(ul.y, ul.x))
	var a_lr := rad_to_deg(atan2(lr.y, lr.x))
	var mid := (a_ul + a_lr) * 0.5
	var half := maxf(a_lr - a_ul, a_ur - a_ul) * 0.5 + 2.0
	_mat.set_shader_parameter("pivot_s", FAN_PIVOT_S)
	_mat.set_shader_parameter("pivot_t", FAN_PIVOT_T)
	_mat.set_shader_parameter("a_mid_s", mid)
	_mat.set_shader_parameter("a_half_s", half)
	_mat.set_shader_parameter("a_mid_t", FAN_TEX_MID)
	_mat.set_shader_parameter("a_half_t", FAN_TEX_HALF)
	_mat.set_shader_parameter("r_scale", FAN_R_SCALE)
	_mat.set_shader_parameter("aspect", asp)


func _apply_fan(p: float) -> void:
	if _fan_closed == null or _fan_open == null or _mat == null:
		return
	var W := size.x
	var H := size.y
	_fan_closed.pivot_offset = Vector2(W, H) * 0.5
	var sweep := 0.0
	var dim := 0.0
	if p < 0.15:
		# 啪：合拢扇沿对角线拍上（回弹缩小）
		var k: float = p / 0.15
		_fan_closed.visible = true
		_fan_closed.modulate = Color(1, 1, 1, clampf(k * 2.0, 0.0, 1.0))
		_fan_closed.scale = Vector2.ONE * (1.35 - 0.35 * smoothstep(0.0, 1.0, k))
	elif p < 0.5:
		# 绕左下扇轴绽放：扇骨从对角线向两侧铺开（shader 角度揭示）
		var k: float = (p - 0.15) / 0.35
		sweep = smoothstep(0.0, 1.0, k)
		dim = 0.95 * sweep
		_fan_closed.visible = k < 0.22
		_fan_closed.modulate = Color(1, 1, 1, clampf(1.0 - k / 0.22, 0.0, 1.0))
	elif p < 0.56:
		# 盖满：定住（背后已换成新立绘）
		sweep = 1.0
		dim = 0.95
		_fan_closed.visible = false
	elif p < 0.88:
		# 逆向收扇：扇骨合回对角线，露出新立绘
		var k: float = (p - 0.56) / 0.32
		sweep = 1.0 - smoothstep(0.0, 1.0, k)
		dim = 0.95 * sweep
		_fan_closed.visible = false
	else:
		# 合拢扇沿对角线滑走淡出
		var k: float = (p - 0.88) / 0.12
		_fan_closed.visible = true
		_fan_closed.modulate = Color(1, 1, 1, 1.0 - k)
		_fan_closed.scale = Vector2.ONE
		_fan_closed.position = Vector2(-90.0, 130.0) * smoothstep(0.0, 1.0, k)
	_fan_open.visible = false
	_mat.set_shader_parameter("sweep", sweep)
	_mat.set_shader_parameter("dim", dim)
	# 完全盖住的瞬间，背后换成新立绘
	if p >= 0.5 and not _fan_swapped and _fan_next != null:
		_mat.set_shader_parameter("tex_prev", _fan_next)
		_current = _fan_next
		_fan_swapped = true


func is_swapping() -> bool:
	return _swapping


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
		_mat.set_shader_parameter("tex_fan", FAN_TEX_OPEN)
		_update_fan_geo()
		_fan_closed.visible = false
		_fan_open.visible = false


func debug_set_progress(p: float) -> void:
	if style == Style.FAN:
		_apply_fan(clampf(p, 0.0, 1.0))
	elif _mat != null:
		_mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))
