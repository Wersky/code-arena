class_name PixelBar
extends Control
## 分段式像素能量条。
##
## 比 ProgressBar 有"游戏味"：一格一格的能量槽，
## 填满的格子亮、没填的暗，读起来像血条/经验条而不是网页进度条。

@export var value: float = 0.0       ## 0..1
@export var track_color: Color = UiKit.PANEL_2
@export var fill_color: Color = UiKit.ACCENT
@export var segment_w: int = 8
@export var gap: int = 2
@export var bar_h: int = 10
@export var border: bool = true
@export var border_color: Color = UiKit.LINE

var _flash: float = 0.0             ## 刚变化时的闪动


func set_value(v: float) -> void:
	var nv := clampf(v, 0.0, 1.0)
	if absf(nv - value) > 0.0001:
		_flash = 1.0
		value = nv
		queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := bar_h
	var y := (size.y - h) * 0.5
	var total := segment_w + gap
	var count := maxi(1, int((w + gap) / total))
	var used := w - (count - 1) * gap
	var seg_w := used / count
	if seg_w < 1:
		seg_w = 1
		used = count

	for i in count:
		var x := i * (seg_w + gap)
		var frac := float(i) / float(count)
		var rect := Rect2(x, y, seg_w, h)
		draw_rect(rect, track_color)
		if frac < value:
			var c := fill_color
			if _flash > 0.0:
				c = c.lerp(Color.WHITE, _flash * 0.7)
			draw_rect(rect, c)
		if border:
			draw_rect(rect, border_color, false, 1.0)
