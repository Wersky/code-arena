class_name RiftHalf
extends Control
## 裂隙转场的半边黑幕：绘制带锯齿内缘的黑色多边形（RiftTransition 配套）。
## is_left=true：锯齿是右缘（覆盖左半屏）；false：锯齿是左缘（覆盖右半屏）。

var jag: PackedVector2Array = []
var is_left := true
var col := Color(0.012, 0.02, 0.04)


func _draw() -> void:
	if jag.size() < 2:
		return
	var filled := PackedVector2Array()
	if is_left:
		filled.append(Vector2(-6.0, jag[0].y))
		for p in jag:
			filled.append(p)
		filled.append(Vector2(-6.0, jag[jag.size() - 1].y))
	else:
		filled.append(Vector2(size.x + 6.0, jag[0].y))
		for p in jag:
			filled.append(p)
		filled.append(Vector2(size.x + 6.0, jag[jag.size() - 1].y))
	draw_colored_polygon(filled, col)
