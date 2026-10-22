class_name Scanlines
extends Control
## CRT 扫描线覆盖层。
##
## 提示词区是"给模型下指令"的地方，做成一台老终端的屏幕非常贴题：
## 扫描线 + 轻微的暗角，把这块区域和其他面板区分开。

@export var spacing: int = 3
@export var alpha: float = 0.20
@export var vignette: bool = true
@export var vignette_strength: float = 0.28


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if vignette:
		# 四边压暗，做出"玻璃管"的弧光感
		var edge := 48.0
		var steps := 12
		for i in steps:
			var f := float(i) / float(steps)
			var a := vignette_strength * (1.0 - f)
			var inset := f * edge
			draw_rect(Rect2(inset, inset, size.x - inset * 2.0, 2), Color(0, 0, 0, a))
			draw_rect(Rect2(inset, size.y - inset - 2, size.x - inset * 2.0, 2), Color(0, 0, 0, a))
			draw_rect(Rect2(inset, inset, 2, size.y - inset * 2.0), Color(0, 0, 0, a))
			draw_rect(Rect2(size.x - inset - 2, inset, 2, size.y - inset * 2.0), Color(0, 0, 0, a))
	for y in range(0, int(size.y), spacing):
		draw_rect(Rect2(0, y, size.x, 1), Color(0, 0, 0, alpha))
