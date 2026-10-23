class_name PromptLine
extends Control
## 一条"AI 终端输入行"：`>` 提示符 + 正文 + 末尾闪烁的方块光标。
##
## 为什么不用 Label：光标是要跟着正文走的，还要能单独上色/闪烁。
## 自绘一屏 3 个 draw_string 的成本远低于拆成三个控件去对齐。

var text := ""
var font_size := 20
var prefix := ">"
var prefix_color := UiArt.NEON
var text_color := Color(0.62, 0.70, 0.82)
var caret_color := UiArt.NEON

## 光标闪烁周期（秒）。设为 0 则不画光标。
var blink_period := 0.9
## 在自身宽度内水平居中
var centered := true

var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if blink_period > 0.0:
		set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var y := roundf(size.y * 0.5 + font_size * 0.36)
	var pw := font.get_string_size(prefix + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var cursor_w := roundf(font_size * 0.55) + 4.0 if blink_period > 0.0 else 0.0
	var x := 0.0
	if centered:
		x = roundf((size.x - (pw + tw + cursor_w)) * 0.5)

	draw_string(font, Vector2(x, y), prefix, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, prefix_color)
	x += pw

	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, text_color)

	if blink_period > 0.0 and fmod(_t, blink_period) < blink_period * 0.5:
		var cw := roundf(font_size * 0.55)
		draw_rect(Rect2(Vector2(roundf(x + tw + 4.0), roundf(y - font_size * 0.72)),
				Vector2(cw, roundf(font_size * 0.9))), caret_color)
