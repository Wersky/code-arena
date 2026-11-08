class_name RippleSwapPortrait
extends Control
## 角色立绘的水波扩散转场（2026-11-08 试验版，主人钦定）：
## 初始显示一张大立绘；swap_to() 换角色时，从立绘**中心**长出一圈水波形状的
## 不规则圆快速扩散到整图，波内逐渐显现新立绘（shader 见 assets/shaders/ripple_reveal.gdshader）。
##
## 用法：
##   set_portrait(tex_a)          → 初始立绘
##   swap_to(tex_b)               → 播水波转场，波前结束后 tex_b 成为当前立绘
##   debug_set_progress(p)        → 逐帧验收用：直接停在某个进度
## 约束：tex_prev/tex_next 用同宽高比的贴图（内部按 UV 直采，不做适配）。

signal swap_finished

const SHADER := preload("res://assets/shaders/ripple_reveal.gdshader")
const SWAP_TIME := 0.7

var _mat: ShaderMaterial = null
var _swapping := false
var _current: Texture2D = null


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := ColorRect.new()
	rect.name = "RippleRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
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
	_mat.set_shader_parameter("tex_next", tex)
	_mat.set_shader_parameter("progress", 0.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_mat.set_shader_parameter("progress", v), 0.0, 1.0, SWAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		_mat.set_shader_parameter("tex_prev", tex)
		_mat.set_shader_parameter("progress", 0.0)
		_current = tex
		_swapping = false
		swap_finished.emit())


func is_swapping() -> bool:
	return _swapping


## 逐帧验收：把两张图摆好、直接停在某个进度（不播动画）
func debug_prepare(prev: Texture2D, next: Texture2D) -> void:
	_swapping = false
	_mat.set_shader_parameter("tex_prev", prev)
	_mat.set_shader_parameter("tex_next", next)
	_mat.set_shader_parameter("progress", 0.0)
	_current = prev


func debug_set_progress(p: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))
