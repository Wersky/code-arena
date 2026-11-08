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
## 实物扇子素材（2026-11-08 主人定稿：单边舒展；展开面只用青花布——不要金扇骨）
const FAN_TEX_CLOSED := preload("res://assets/art/fx/fan-closed.png")
const FAN_TEX_CLOTH := preload("res://assets/art/fx/fan-cloth.png")
## 扇贴图实测参数（numpy 量的：扇钉位置 / 扇骨角中位与半跨）
const FAN_PIVOT_T := Vector2(0.068, 0.903)
const FAN_TEX_MID := -59.0
const FAN_TEX_HALF := 48.0
## 画面侧扇轴（左下角内收一点）
const FAN_PIVOT_S := Vector2(0.06, 0.94)
## 一次 swap 的总时长（秒）。demo 页有调速滑杆，主人的数值存 GameSettings 跨启动记住。
var swap_time := 0.7
var style: int = Style.RIPPLE

var _mat: ShaderMaterial = null
var _swapping := false
var _current: Texture2D = null
## 实物扇子（FAN 风格专用）：合拢扇精灵 + 角度揭示 shader
var _fan_closed: TextureRect = null
var _fan_swapped := false   ## 盖满后，背后已换成新立绘
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
		# 实物扇子：合拢扇啪上对角线 → 扇骨从对角线向两侧开花盖满 → 背后换图 → 逆向收拢
		_fan_swapped = false
		_fan_next = tex
		_mat.shader = SHADERS[style]
		_mat.set_shader_parameter("tex_fan", FAN_TEX_CLOTH)
		_mat.set_shader_parameter("tex_next", tex)
		_mat.set_shader_parameter("sweep", 0.0)
		_mat.set_shader_parameter("dim", 0.0)
		_update_fan_geo()
		_fan_closed.visible = false
		var tw := create_tween()
		tw.tween_method(_apply_fan, 0.0, 1.0, maxf(0.05, swap_time))
		tw.tween_callback(func() -> void:
			_fan_closed.visible = false
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
	if style == Style.SLASH:
		# 斩击张力：双剑交叉的瞬间画面震一下
		var base_pos := position
		var sh := create_tween()
		sh.tween_interval(maxf(0.05, swap_time) * 0.30)
		for i in 5:
			sh.tween_property(self, "position",
					base_pos + Vector2(randf_range(-10.0, 10.0), randf_range(-8.0, 8.0)), 0.028)
		sh.tween_property(self, "position", base_pos, 0.05)


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
	# 画面角度带（相对左下扇轴，aspect 校正后）：画框可见四角的 atan 范围
	var a_ur := rad_to_deg(atan2(-(FAN_PIVOT_S.y * size.y), (1.0 - FAN_PIVOT_S.x) * size.x * asp))
	var a_ul := rad_to_deg(atan2(-(FAN_PIVOT_S.y * size.y), -(FAN_PIVOT_S.x * size.x) * asp))
	var a_lr := rad_to_deg(atan2((1.0 - FAN_PIVOT_S.y) * size.y, (1.0 - FAN_PIVOT_S.x) * size.x * asp))
	var a_start := a_lr + 3.0                      ## 起始边：底边侧再往外 3° 兜住底角
	var a_end := a_ul - 2.0                        ## 终止边：左边侧再收 2° 兜住左上角
	_mat.set_shader_parameter("pivot_s", FAN_PIVOT_S)
	_mat.set_shader_parameter("pivot_t", FAN_PIVOT_T)
	_mat.set_shader_parameter("a_start", a_start)
	_mat.set_shader_parameter("a_end", a_end)
	## 角度映射基准 = 扫掠带 [a_start, a_end] 的中位 对齐 贴图扇骨中位
	_mat.set_shader_parameter("t_off", FAN_TEX_MID - (a_start + a_end) * 0.5)
	_mat.set_shader_parameter("r_scale", 0.95)
	_mat.set_shader_parameter("aspect", asp)


func _apply_fan(p: float) -> void:
	if _fan_closed == null or _mat == null:
		return
	# 合拢扇精灵当「第一片扇骨」：绕扇柄（左下）旋转，领着前缘走
	_fan_closed.pivot_offset = Vector2(size.x * 0.07, size.y * 0.9)
	var sweep := 0.0
	var dim := 0.0
	var rot := 0.0
	if p < 0.14:
		# 啪：合拢扇在起始边拍上（回弹缩小）
		var k: float = p / 0.14
		rot = 50.0 - 12.0 * smoothstep(0.0, 1.0, k)
		_fan_closed.visible = true
		_fan_closed.modulate = Color(1, 1, 1, clampf(k * 2.0, 0.0, 1.0))
		_fan_closed.scale = Vector2.ONE * (1.25 - 0.25 * smoothstep(0.0, 1.0, k))
		_fan_closed.rotation_degrees = rot
	elif p < 0.55:
		# 单边舒展：扇骨从起始边一路扫到另一边，合拢扇领着前缘转
		var k: float = (p - 0.14) / 0.41
		sweep = smoothstep(0.0, 1.0, k)
		dim = 0.95 * sweep
		rot = 50.0 - 100.0 * k
		_fan_closed.visible = true
		_fan_closed.modulate = Color(1, 1, 1, clampf(1.0 - k * 1.4, 0.0, 1.0))
		_fan_closed.rotation_degrees = rot
	elif p < 0.62:
		# 盖满：定住（背后已换成新立绘）
		sweep = 1.0
		dim = 0.95
		_fan_closed.visible = false
		_fan_closed.rotation_degrees = 0.0
	elif p < 0.9:
		# 逆向收拢：扇骨合回起始边，露出新立绘
		var k: float = (p - 0.62) / 0.28
		sweep = 1.0 - smoothstep(0.0, 1.0, k)
		dim = 0.95 * sweep
		_fan_closed.visible = false
		_fan_closed.rotation_degrees = 0.0
	else:
		# 收拢扇淡出
		var k: float = (p - 0.9) / 0.1
		_fan_closed.visible = true
		_fan_closed.modulate = Color(1, 1, 1, 1.0 - k)
		_fan_closed.rotation_degrees = 0.0
	_mat.set_shader_parameter("sweep", sweep)
	_mat.set_shader_parameter("dim", dim)
	# 完全盖住的瞬间，背后换成新立绘
	if p >= 0.55 and not _fan_swapped and _fan_next != null:
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
		_mat.set_shader_parameter("tex_fan", FAN_TEX_CLOTH)
		_update_fan_geo()
		_fan_closed.visible = false


func debug_set_progress(p: float) -> void:
	if style == Style.FAN:
		_apply_fan(clampf(p, 0.0, 1.0))
	elif _mat != null:
		_mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))
