class_name JuiceButton
extends Control
## 主菜单的**大按钮**：底板用生图的美术资产，文字仍用像素字现画（中文没法烘进图里）。
##
## 悬停时同时发生四件事（叠起来才有"正式游戏"的手感）：
##   ① 底板整体提亮并染金
##   ② 一道 28px 宽的硬边高光从左扫到右（0.5 秒，悬停期间循环）
##   ③ 左侧 ▶ 箭头往里滑，右侧出现 ◀（对称收拢）
##   ④ 文字由白转金
## 按下时整体下压 2px + 闪白；松开在按钮内则 emit pressed。
##
## 底板尺寸纪律：`custom_minimum_size` 必须等于 `UiArt.display_size("btn")`（= 原生 ×2），
## 否则图片会被非整数拉伸，像素格变得一宽一窄。太小就用别的按钮样式，别硬缩。

signal pressed

var text := ""
var accent := Color(0.31, 0.76, 0.97)
var font_size := 36
var primary := false              ## 主按钮：金边呼吸

## 底板资产名（"ui/btn" 之类）。留空则退回自绘直角底。
var plate := ""
## 裸字模式：不画底板，只有字 + 悬停金线。用于"退出游戏"这类次要入口，
## 免得多一个不同像素密度的底板把画面搞脏。
var bare := false

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
	var down_off := roundf(3.0 * _press)
	draw_set_transform(Vector2(0, down_off), 0.0, Vector2.ONE)

	var r := Rect2(Vector2.ZERO, size)
	var breath := 0.5 + 0.5 * sin(_breath * 1.6) if primary else 0.0
	var plate_tex := UiArt.tex(plate) if not plate.is_empty() else null

	if bare:
		_draw_bare(font, breath)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	if plate_tex != null:
		_draw_plate(plate_tex, breath)
	else:
		_draw_flat(breath)

	# 扫光：只在底板内侧打一条，别糊住金边
	if _sweep < 1.0 and _hover > 0.05:
		var inset := 26.0 if plate_tex != null else 2.0
		var sx := -28.0 + _sweep * (size.x + 56.0)
		draw_rect(Rect2(Vector2(roundf(sx), inset), Vector2(28, size.y - inset * 2.0)),
				Color(1, 1, 1, 0.13 * _hover))

	_draw_label(font)


## 生图底板：整块铺满，悬停染金提亮
func _draw_plate(t: Texture2D, breath: float) -> void:
	# 投影用「底板自己的剪影」画，别用矩形——底板是切角的，矩形投影会在四角露黑块
	var sh := roundf(6.0 - 4.0 * _press)
	draw_texture_rect(t, Rect2(Vector2(sh, sh + 3), size), false, Color(0, 0, 0, 0.55))

	var tint := Color(1, 1, 1)
	tint = tint.lerp(Color(1.10, 1.16, 1.22), _hover)      # 悬停偏冷白（霓虹感）
	if _press > 0.5:
		tint = tint.lerp(Color(1.5, 1.5, 1.5), 0.7)        # 按下闪白
	draw_texture_rect(t, Rect2(Vector2.ZERO, size), false, tint)
	# 悬停再叠一层金色剪影：只乘底板 alpha，等于给整块板打一层暖光
	if _hover > 0.01:
		draw_texture_rect(t, Rect2(Vector2.ZERO, size), false,
				Color(0.42, 0.88, 1.0, 0.22 * _hover))

	# 主按钮：内侧一圈金线呼吸，提示"这是主要入口"
	if breath > 0.0:
		var inset := 24.0
		draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0),
				Color(UiArt.NEON.r, UiArt.NEON.g, UiArt.NEON.b, 0.10 + 0.18 * breath),
				false, 2.0)


## 没资产时的退路（老样式，别删：headless / 缺图时不至于没按钮）
func _draw_flat(breath: float) -> void:
	var sh := roundf(5.0 - 3.0 * _press)
	draw_rect(Rect2(Vector2(sh, sh + 1), size), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(Vector2.ZERO, size),
			Color(0.055, 0.071, 0.106).lerp(Color(0.10, 0.13, 0.19), _hover))
	var border := accent.lerp(UiKit.GOLD, maxf(_hover, 0.35 if primary else 0.0))
	if primary:
		border = border.lerp(UiKit.GOLD, 0.35 + 0.35 * breath)
	if _press > 0.5:
		border = border.lerp(Color.WHITE, 0.8)
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 2.0 + roundf(_hover))
	var tick := Color(border.r, border.g, border.b, 0.55 + 0.45 * _hover)
	var t := 6.0
	for corner in [Vector2.ZERO, Vector2(size.x - t, 0.0),
			Vector2(0.0, size.y - t), Vector2(size.x - t, size.y - t)]:
		draw_rect(Rect2(corner, Vector2(t, t)), tick)


func _draw_label(font: Font) -> void:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var tx := roundf(size.x * 0.5 - ts.x * 0.5)
	var ty := roundf(size.y * 0.5 + font_size * 0.36)
	var txt_col := Color(0.92, 0.97, 1.0).lerp(UiArt.NEON, _hover)
	draw_string(font, Vector2(tx + 3, ty + 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, Color(0, 0, 0, 0.72))
	draw_string(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, txt_col)

	var arrow_a := 0.30 + 0.70 * _hover
	var push := roundf(8.0 * _hover)
	var acol := Color(UiArt.NEON.r, UiArt.NEON.g, UiArt.NEON.b, arrow_a)
	var asz := int(font_size * 0.72)
	draw_string(font, Vector2(tx - 44.0 + push, ty), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1,
			asz, acol)
	if _hover > 0.05:
		draw_string(font, Vector2(tx + ts.x + 22.0 - push, ty), "◀",
				HORIZONTAL_ALIGNMENT_LEFT, -1, asz, acol)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 裸字：只有字 + 悬停时长出来的金线 + 两侧小箭头
func _draw_bare(font: Font, _breath: float) -> void:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var tx := roundf(size.x * 0.5 - ts.x * 0.5)
	var ty := roundf(size.y * 0.5 + font_size * 0.36)
	var txt_col := Color(UiKit.TEXT_DIM).lerp(Color(0.95, 0.97, 1.0), _hover)
	draw_string(font, Vector2(tx + 2, ty + 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, txt_col)

	# 悬停时下方长出一条金线（从中间往两侧长）
	if _hover > 0.02:
		var half := roundf(ts.x * 0.5 * _hover)
		var y := ty + 8.0
		draw_rect(Rect2(Vector2(roundf(size.x * 0.5) - half, y),
				Vector2(half * 2.0, 2.0)),
				Color(UiArt.NEON.r, UiArt.NEON.g, UiArt.NEON.b, 0.9 * _hover))

	var asz := int(font_size * 0.8)
	var push := roundf(6.0 * _hover)
	var acol := Color(UiArt.NEON.r, UiArt.NEON.g, UiArt.NEON.b, _hover)
	if _hover > 0.05:
		draw_string(font, Vector2(tx - 24.0 + push, ty), "▶",
				HORIZONTAL_ALIGNMENT_LEFT, -1, asz, acol)
		draw_string(font, Vector2(tx + ts.x + 10.0 - push, ty), "◀",
				HORIZONTAL_ALIGNMENT_LEFT, -1, asz, acol)
