class_name RiftTransition
extends Control
## 胜利裂隙转场（2026-11-01 主人钦定）：全屏黑暗 → 中央裂开裂缝（向上下张开）
## → 黑幕沿裂缝分成左右两半向两侧滑开，露出后面的新界面。
##
## 用法：父界面 add_child(rift)（全屏锚点）→ 一帧后自动播放 → finished 后自毁。

signal finished

var _left: RiftHalf = null
var _right: RiftHalf = null
var _crack: Line2D = null
var _crack_glow: Line2D = null
var _w := 0.0
var _h := 0.0
var _jag := PackedVector2Array()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	await get_tree().process_frame      ## 等锚点布局算出真实尺寸
	_w = size.x
	_h = size.y
	if _w <= 1.0:
		_w = 1920.0
		_h = 1080.0
	_build_jagged_line()
	_left = RiftHalf.new()
	_left.is_left = true
	_left.jag = _jag
	_left.set_anchors_preset(Control.PRESET_FULL_RECT)
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left)
	_right = RiftHalf.new()
	_right.is_left = false
	_right.jag = _jag
	_right.set_anchors_preset(Control.PRESET_FULL_RECT)
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right)
	_build_crack()
	_play()


## 中轴锯齿线：从画布上缘经中心到下缘（中部摆幅最大，越靠边越收窄）
func _build_jagged_line() -> void:
	var cx := _w * 0.5
	var steps := 14
	for i in steps:
		var t := float(i) / float(steps - 1)
		var y := -10.0 + t * (_h + 20.0)
		_jag.append(Vector2(cx + randf_range(-24.0, 24.0) * (1.0 - absf(t - 0.5) * 0.7), y))


func _build_crack() -> void:
	_crack_glow = Line2D.new()
	_crack_glow.points = _jag
	_crack_glow.width = 10.0
	_crack_glow.default_color = Color(0.31, 0.76, 0.97, 0.4)
	_crack_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crack_glow)
	_crack = Line2D.new()
	_crack.points = _jag
	_crack.width = 2.5
	_crack.default_color = Color(0.78, 0.93, 1.0)
	_crack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crack)


func _play() -> void:
	# ① 细缝先张开（裂纹可见）→ ② 黑幕沿裂缝左右大幅分开（向上下张满）
	var tw := create_tween()
	tw.tween_property(_left, "position:x", -7.0, 0.18) 			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_right, "position:x", 7.0, 0.18) 			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.14)
	tw.tween_property(_left, "position:x", -_w, 0.55) 			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_right, "position:x", _w, 0.55) 			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())
