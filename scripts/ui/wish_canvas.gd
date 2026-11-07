class_name WishCanvas
extends Control
## 许愿涂鸦板（2026-11-04 主人钦定）：白色正方形区域，鼠标拖拽画线。
## 导出为 data URI 给多模态模型做视觉解析。
##
## 2026-11-06 修 bug：每笔落笔时**快照画笔设置**（大小/形状/颜色），
## 之后切换画笔只影响新笔迹，已画的不会整体变色。

signal stroke_finished
## 吸管取到颜色时发出（UI 拿它更新画笔颜色）
signal color_picked(color: Color)

const PAD_SIZE := 320.0
const LINE_W := 12.0
const INK := Color(0.12, 0.13, 0.16)
## 纸张色（橡皮 = 用纸色覆盖，导出给模型时也是白的）
const PAPER := Color(0.98, 0.98, 0.96)
## 尺寸范围：画笔走滑杆 1–100，橡皮走 S/M/L 三档
const SIZE_MIN := 1.0
const SIZE_MAX := 100.0

## 画笔设置（2026-11-06 改：尺寸走 1–100 滑杆）
var brush_size := 24.0
var brush_style := "round"          ## round / square
var brush_color := Color(0.12, 0.13, 0.16)
## 橡皮：独立尺寸（S/M/L），新笔迹用纸色覆盖（撤销仍然按笔回退）
var eraser_size := 24.0
## 当前工具：brush / eraser / picker（吸管）
var tool := "brush"
## 滑杆拖动时的尺寸预览直径（>0 时在画布中心画一个黑点）
var preview_size := 0.0
## 每笔：{pts: PackedVector2Array, size: float, style: String, color: Color, eraser: bool}
var _strokes: Array = []
var _cur := PackedVector2Array()
var _cur_size := 12.0
var _cur_style := "round"
var _cur_color := Color(0.12, 0.13, 0.16)
var _drawing := false


func _ready() -> void:
	custom_minimum_size = Vector2(PAD_SIZE, PAD_SIZE)
	size = Vector2(PAD_SIZE, PAD_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			## 吸管：点一下取色，不落笔
			if tool == "picker":
				color_picked.emit(color_at(mb.position))
				accept_event()
				return
			_drawing = true
			_cur = PackedVector2Array([mb.position])
			## 落笔瞬间快照：之后再换画笔不影响这一笔
			_cur_size = eraser_size if tool == "eraser" else brush_size
			_cur_style = brush_style
			_cur_color = PAPER if tool == "eraser" else brush_color
			queue_redraw()
		elif _drawing:
			_drawing = false
			if _cur.size() > 0:
				_strokes.append({
					"pts": _cur,
					"size": _cur_size,
					"style": _cur_style,
					"color": _cur_color,
					"eraser": tool == "eraser",
				})
			_cur = PackedVector2Array()
			queue_redraw()
			stroke_finished.emit()
		accept_event()
	elif event is InputEventMouseMotion and _drawing:
		var mm := event as InputEventMouseMotion
		_cur.append(mm.position)
		queue_redraw()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.98, 0.98, 0.96), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.60, 0.68), false, 2.0)
	for s in _strokes:
		_draw_stroke(s)
	if _cur.size() > 0:
		_draw_stroke({
			"pts": _cur, "size": _cur_size, "style": _cur_style, "color": _cur_color,
		})
	## 滑杆拖动预览：画布正中的黑点 = 当前画笔粗细
	if preview_size > 0.0:
		var center := size * 0.5
		var rad := minf(preview_size, minf(size.x, size.y)) * 0.5
		draw_circle(center, rad, Color(0, 0, 0, 0.88))
		draw_arc(center, rad, 0.0, TAU, 48, Color(1, 1, 1, 0.85), 1.5, true)


func _draw_stroke(stroke: Dictionary) -> void:
	var pts: PackedVector2Array = stroke.get("pts", PackedVector2Array())
	var sz := float(stroke.get("size", LINE_W))
	var style := String(stroke.get("style", "round"))
	var col: Color = stroke.get("color", INK)
	if pts.size() < 2:
		if pts.size() == 1:
			if style == "square":
				var h := sz * 0.5
				draw_rect(Rect2(pts[0] - Vector2(h, h), Vector2(sz, sz)), col)
			else:
				draw_circle(pts[0], sz * 0.5, col)
		return
	if style == "square":
		var half := sz * 0.5
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var steps := maxi(1, int(a.distance_to(b) / 2.0))
			for k in steps + 1:
				var p := a.lerp(b, float(k) / steps)
				draw_rect(Rect2(p - Vector2(half, half), Vector2(sz, sz)), col)
	else:
		for i in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], col, sz, true)


## 撤销最后一笔；返回是否真的有笔迹被撤销
func undo() -> bool:
	if not _cur.is_empty():
		_cur = PackedVector2Array()
		queue_redraw()
		stroke_finished.emit()
		return true
	if _strokes.is_empty():
		return false
	_strokes.pop_back()
	queue_redraw()
	stroke_finished.emit()
	return true


func stroke_count() -> int:
	return _strokes.size()


## 吸管：返回该点最上层笔迹的颜色（没画到就返回纸色）
func color_at(pos: Vector2) -> Color:
	for i in range(_strokes.size() - 1, -1, -1):
		var st: Dictionary = _strokes[i]
		var pts: PackedVector2Array = st.get("pts", PackedVector2Array())
		var sz := float(st.get("size", LINE_W))
		if _point_near(pos, pts, sz * 0.5 + 2.0):
			return st.get("color", INK)
	return PAPER


func _point_near(p: Vector2, pts: PackedVector2Array, radius: float) -> bool:
	if pts.is_empty():
		return false
	var r2 := radius * radius
	if pts.size() == 1:
		return p.distance_squared_to(pts[0]) <= r2
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var denom := ab.length_squared()
		var t := 0.0
		if denom > 0.0001:
			t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
		if p.distance_squared_to(a + ab * t) <= r2:
			return true
	return false


func clear() -> void:
	_strokes.clear()
	_cur = PackedVector2Array()
	_drawing = false
	queue_redraw()


func is_empty() -> bool:
	return _strokes.is_empty() and _cur.is_empty()


## 导出 PNG 的 data URI（白底，缩到 512×512 送模型）
func export_data_uri(out_size := 512) -> String:
	var img := Image.create_empty(out_size, out_size, false, Image.FORMAT_RGB8)
	_raster_to(img, out_size)
	var png := img.save_png_to_buffer()
	return "data:image/png;base64," + Marshalls.raw_to_base64(png)


## 直接落盘（手绘涂鸦当卡面用）
func save_png(path: String, out_size := 512) -> bool:
	var img := Image.create_empty(out_size, out_size, false, Image.FORMAT_RGB8)
	_raster_to(img, out_size)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
			path.get_base_dir()))
	return img.save_png(path) == OK


func _raster_to(img: Image, out_size: int) -> void:
	img.fill(Color(0.98, 0.98, 0.96))
	var scale := float(out_size) / maxf(size.x, 1.0)
	for s in _strokes:
		_raster_stroke(img, s, scale)
	if _cur.size() > 1:
		_raster_stroke(img, {
			"pts": _cur, "size": _cur_size, "style": _cur_style, "color": _cur_color,
		}, scale)


func _raster_stroke(img: Image, stroke: Dictionary, scale: float) -> void:
	## 线段按包围盒扫描填充「胶囊」，**不是**沿线段撒圆盘——
	## 撒圆盘在半径边缘会漏采样，橡皮擦不干净（2026-11-06 实测残留 54 个红像素）。
	## 导出图里方头笔也按圆头画：512px 下差异可忽略，UI 里仍按方头显示。
	var pts: PackedVector2Array = stroke.get("pts", PackedVector2Array())
	var sz := float(stroke.get("size", LINE_W))
	var col: Color = stroke.get("color", INK)
	var r := maxi(2, int(round(sz * 0.5 * scale)))
	if pts.is_empty():
		return
	if pts.size() == 1:
		_fill_capsule(img, pts[0] * scale, pts[0] * scale, r, col)
		return
	for i in range(pts.size() - 1):
		_fill_capsule(img, pts[i] * scale, pts[i + 1] * scale, r, col)


## 填充「线段 + 半径 r」的胶囊：扫描线段 AABB，逐像素算点到线段距离
func _fill_capsule(img: Image, a: Vector2, b: Vector2, r: int, col: Color) -> void:
	var minx := maxi(0, int(floor(minf(a.x, b.x))) - r)
	var maxx := mini(img.get_width() - 1, int(ceil(maxf(a.x, b.x))) + r)
	var miny := maxi(0, int(floor(minf(a.y, b.y))) - r)
	var maxy := mini(img.get_height() - 1, int(ceil(maxf(a.y, b.y))) + r)
	var ab := b - a
	var denom := ab.length_squared()
	var rr := float(r * r)
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var p := Vector2(x, y)
			var t := 0.0
			if denom > 0.0001:
				t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
			var closest := a + ab * t
			if p.distance_squared_to(closest) <= rr:
				img.set_pixel(x, y, col)
