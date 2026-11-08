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
	Style.FAN: preload("res://assets/shaders/ripple_reveal.gdshader"),  ## FAN 只用底层（progress 恒 0），动画全靠布料精灵
	Style.SLASH: preload("res://assets/shaders/x_slash.gdshader"),
	Style.HEX: preload("res://assets/shaders/hex_scale.gdshader"),
}
## 扇面布素材（2026-11-08 主人定稿：只要扇面的布、不要支架；一开始就很大直接盖满立绘）
const FAN_TEX_CLOTH := preload("res://assets/art/fx/fan-cloth.png")
## 一次 swap 的总时长（秒）。demo 页有调速滑杆，主人的数值存 GameSettings 跨启动记住。
var swap_time := 0.7
var style: int = Style.RIPPLE

var _mat: ShaderMaterial = null
var _swapping := false
var _current: Texture2D = null
## 扇面布（FAN 风格专用）
var _fan_cloth: TextureRect = null
var _fan_swapped := false   ## 布盖满后，背后已换成新立绘
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
	_fan_cloth = TextureRect.new()
	_fan_cloth.name = "FanCloth"
	_fan_cloth.texture = FAN_TEX_CLOTH
	_fan_cloth.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fan_cloth.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fan_cloth.stretch_mode = TextureRect.STRETCH_SCALE   ## 布铺满画框，边缘到边缘
	_fan_cloth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fan_cloth.visible = false
	add_child(_fan_cloth)


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
		# 扇面布：啪一下盖满立绘 → 延展开 → 背后换图 → 逆向撤走（纯精灵动画）
		_fan_swapped = false
		_fan_next = tex
		_fan_cloth.visible = false
		_fan_cloth.position = Vector2.ZERO
		var tw := create_tween()
		tw.tween_method(_apply_fan, 0.0, 1.0, maxf(0.05, swap_time))
		tw.tween_callback(func() -> void:
			_fan_cloth.visible = false
			_fan_cloth.position = Vector2.ZERO
			_mat.set_shader_parameter("tex_prev", tex)
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
func _apply_fan(p: float) -> void:
	if _fan_cloth == null:
		return
	var W := size.x
	var H := size.y
	_fan_cloth.pivot_offset = Vector2(W, H) * 0.5
	var vis := false
	var sc := 1.0
	var alpha := 0.0
	var rot := 0.0
	var slide := Vector2.ZERO
	if p < 0.13:
		# 啪：布整体放大落下，直接盖满整个立绘
		var k: float = p / 0.13
		vis = true
		alpha = clampf(k * 2.2, 0.0, 1.0)
		sc = 1.18 - 0.18 * smoothstep(0.0, 1.0, k)
		rot = -2.5 * (1.0 - smoothstep(0.0, 1.0, k))
	elif p < 0.5:
		# 延展开：布往四周缓缓延展铺平
		var k: float = (p - 0.13) / 0.37
		vis = true
		alpha = 1.0
		sc = 1.0 + 0.045 * sin(k * PI)
		rot = 0.8 * sin(k * PI)
	else:
		var k: float = (p - 0.5) / 0.5
		if k < 0.7:
			# 逆向撤走：布沿对角线掀起滑走，露出新立绘
			var kk: float = k / 0.7
			vis = true
			alpha = 1.0 - smoothstep(0.25, 1.0, kk)
			sc = 1.04 + 0.10 * kk
			rot = 2.0 * kk
			slide = Vector2(90.0, -120.0) * smoothstep(0.0, 1.0, kk)
	_fan_cloth.visible = vis
	_fan_cloth.scale = Vector2.ONE * maxf(sc, 0.02)
	_fan_cloth.modulate = Color(1, 1, 1, alpha)
	_fan_cloth.rotation_degrees = rot
	_fan_cloth.position = slide
	# 盖满之后背后换新立绘
	if p >= 0.2 and not _fan_swapped and _fan_next != null:
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
		_fan_cloth.visible = false
		_fan_cloth.position = Vector2.ZERO


func debug_set_progress(p: float) -> void:
	if style == Style.FAN:
		_apply_fan(clampf(p, 0.0, 1.0))
	elif _mat != null:
		_mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))
