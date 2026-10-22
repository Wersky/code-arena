class_name PixelFrame
extends Control
## 像素角饰框：在面板四角画 L 形装饰角。
##
## 经典像素 UI 的灵魂细节——不占空间、不抢内容，
## 但一眼就"是游戏"而不是"网页表单"。

@export var color: Color = UiKit.LINE_HI
@export var arm: int = 12        ## 每个角的臂长（像素）
@export var thick: int = 2       ## 线粗
@export var inset: int = 2       ## 离边框的距离
@export var corners: int = 0b1111  ## 位掩码：左上/右上/左下/右下


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var i := inset
	var r := Rect2(Vector2(i, i), size - Vector2(i, i) * 2.0)
	var a := float(arm)
	var t := float(thick)

	# 左上
	if corners & 0b1000:
		draw_rect(Rect2(r.position, Vector2(a, t)), color)
		draw_rect(Rect2(r.position, Vector2(t, a)), color)
	# 右上
	if corners & 0b0100:
		draw_rect(Rect2(Vector2(r.end.x - a, r.position.y), Vector2(a, t)), color)
		draw_rect(Rect2(Vector2(r.end.x - t, r.position.y), Vector2(t, a)), color)
	# 左下
	if corners & 0b0010:
		draw_rect(Rect2(Vector2(r.position.x, r.end.y - t), Vector2(a, t)), color)
		draw_rect(Rect2(Vector2(r.position.x, r.end.y - a), Vector2(t, a)), color)
	# 右下
	if corners & 0b0001:
		draw_rect(Rect2(Vector2(r.end.x - a, r.end.y - t), Vector2(a, t)), color)
		draw_rect(Rect2(Vector2(r.end.x - t, r.end.y - a), Vector2(t, a)), color)
