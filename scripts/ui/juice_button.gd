class_name JuiceButton
extends Control
## 主菜单的**大按钮**：自绘边框 + 四角标记 + 悬停演示。
##
## 悬停时同时发生四件事（叠起来才有"正式游戏"的手感）：
##   ① 边框从强调色渐变到金色，并加粗 1px
##   ② 一道 28px 宽的硬边高光从左扫到右（0.5 秒，悬停期间循环）
##   ③ 左侧 ▶ 箭头往里滑一点，右侧出现 ◀（对称收拢）
##   ④ 底色提亮 + 文字由白转金
## 按下时整体下压 2px + 边框闪白；松开在按钮内则 emit pressed。
##
## 为什么不用 Button + 主题：Button 的 _draw 被主题接管，想在边框上做扫光/角标
## 得再叠一层，反而更绕。这里一个 Control 全自绘，逻辑更直白。

signal pressed

var text := ""
var accent := Color(0.31, 0.76, 0.97)
var font_size := 36
var primary := false              ## 主按钮：金框 + 呼吸

var _hover := 0.0
var _press := 0.0
var _sweep := 1.0                 ## 0~1 扫光进度，>=1 表示不画
var _breath := 0.0
var _hovered := false
var _down := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(480, 70)


func _ready() -> void:
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	set_process(true)


func _process(delta: float) -> void:
	_breath += delta
	var dirty := false
	if _press > 0.0:
		_press = maxf(0.0, _press - delta * 4.5)
		dirty = true
	if _sweep < 1.0:
		_sweep += delta / 0.5
		dirty = true
	if _hovered or dirty or primary:
		queue_redraw()


## 目检用：直接进/出悬停态（`Input.warp_mouse` 不会产生 mouse_entered，拍不到悬停帧）
func debug_set_hover(v: bool) -> void:
	if v:
		_on_enter()
	else:
		_on_exit()


func _on_enter() -> void:
	_hovered = true
	_tween_to(1.0)
	_sweep = 0.0


func _on_exit() -> void:
	_hovered = false
	_tween_to(0.0)


func _tween_to(target: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "_hover", target, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_down = true
			_press = 1.0
			queue_redraw()
		else:
			var was_down := _down
			_down = false
			queue_redraw()
			if was_down and Rect2(Vector2.ZERO, size).has_point(mb.position):
				pressed.emit()


func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var down_off := roundf(2.0 * _press)
	draw_set_transform(Vector2(0, down_off), 0.0, Vector2.ONE)

	var r := Rect2(Vector2.ZERO, size)
	var breath := 0.0
	if primary:
		breath = 0.5 + 0.5 * sin(_breath * 1.6)

	# ① 硬投影（按下时收一点，像真的压进去）
	var sh := roundf(5.0 - 3.0 * _press)
	draw_rect(Rect2(Vector2(sh, sh + 1), size), Color(0, 0, 0, 0.55))

	# ② 底色：悬停提亮
	var base := Color(0.055, 0.071, 0.106).lerp(Color(0.10, 0.13, 0.19), _hover)
	draw_rect(r, base)

	# ③ 扫光：28px 硬边竖条，悬停期间循环
	if _sweep < 1.0 and _hover > 0.05:
		var sx := -28.0 + _sweep * (size.x + 56.0)
		draw_rect(Rect2(Vector2(roundf(sx), 2), Vector2(28, size.y - 4)),
				Color(accent.r, accent.g, accent.b, 0.14 * _hover))

	# ④ 边框：强调色 → 金色；主按钮额外呼吸
	var border := accent.lerp(UiKit.GOLD, maxf(_hover, 0.35 if primary else 0.0))
	if primary:
		border = border.lerp(UiKit.GOLD, 0.35 + 0.35 * breath)
	if _press > 0.5:
		border = border.lerp(Color.WHITE, 0.8)
	draw_rect(r, border, false, 2.0 + roundf(_hover))

	# ⑤ 四角标记（正式游戏面板的"角标"感，颜色跟随边框，别和主色打架）
	var tick := Color(border.r, border.g, border.b, 0.55 + 0.45 * _hover)
	var t := 6.0
	for corner in [Vector2.ZERO, Vector2(size.x - t, 0.0),
			Vector2(0.0, size.y - t), Vector2(size.x - t, size.y - t)]:
		draw_rect(Rect2(corner, Vector2(t, t)), tick)

	# ⑥ 文字 + 两侧箭头（箭头随悬停往里收）
	var label := text
	var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var tx := size.x * 0.5 - ts.x * 0.5
	var ty := size.y * 0.5 + font_size * 0.36
	var txt_col := Color(0.90, 0.93, 0.97).lerp(UiKit.GOLD, _hover)
	draw_string(font, Vector2(tx + 2, ty + 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, txt_col)

	var arrow_a := 0.35 + 0.65 * _hover
	var push := roundf(6.0 * _hover)
	var acol := Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, arrow_a)
	draw_string(font, Vector2(tx - 34.0 + push, ty), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1,
			24, acol)
	if _hover > 0.05:
		draw_string(font, Vector2(tx + ts.x + 18.0 - push, ty), "◀",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 24, acol)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
