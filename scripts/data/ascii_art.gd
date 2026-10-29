class_name AsciiArt
extends Object
## 像素图 → ASCII 字符画（纯文本）。
##
## 关键实现：**先把整幅图缩放到字符网格大小（面积平均）再逐格取色**。
## 早期版本每格只采一个像素（最近邻），对平涂插画等于纯噪声——这是「糊成一片」的真因。

const RAMP := " .:-=+*#%@"
const CELL_ASPECT := 2.0        ## 终端字符 高:宽
const STRETCH := 2.2            ## 横向拉伸：竖构图人物正常比例只占屏宽三成，撑宽才「大」
const CROP_W := 1.0             ## 横向取景比例（1.0 = 全宽）
const BUST := 1.0               ## 纵向取景比例（1.0 = 全身）


static func build(tex: Texture2D, rows: int, max_cols: int = 200,
		cell_aspect: float = CELL_ASPECT) -> PackedStringArray:
	var out := PackedStringArray()
	if tex == null:
		return out
	var img := tex.get_image()
	if img == null:
		return out
	img.convert(Image.FORMAT_RGBA8)
	_key_background(img)
	var bb := _alpha_bbox(img)
	if bb.size.x <= 0 or bb.size.y <= 0:
		return out

	# 取景框（居中横切 + 顶部起纵向切）
	var crop_w := maxi(8, int(float(bb.size.x) * CROP_W))
	var crop_h := maxi(8, int(float(bb.size.y) * BUST))
	var crop := Rect2i(
		Vector2i(bb.position.x + (bb.size.x - crop_w) / 2, bb.position.y),
		Vector2i(mini(crop_w, bb.size.x), mini(crop_h, bb.size.y)))
	img = img.get_region(crop)
	bb = _alpha_bbox(img)
	if bb.size.x <= 0 or bb.size.y <= 0:
		return out
	img = img.get_region(bb)

	var src_aspect := float(img.get_width()) / float(img.get_height())
	var cols := int(round(float(rows) * src_aspect * cell_aspect * STRETCH))
	if cols > max_cols:
		cols = max_cols
		rows = maxi(4, int(round(float(cols) / (src_aspect * cell_aspect * STRETCH))))
	cols = maxi(8, cols)
	rows = maxi(4, rows)

	# 面积平均缩放：一格 = 这块图案的平均色，不会出现采样噪点
	img.resize(cols, rows, Image.INTERPOLATE_BILINEAR)

	var lum := PackedFloat32Array()
	var cov := PackedFloat32Array()
	lum.resize(cols * rows)
	cov.resize(cols * rows)
	for r in rows:
		for c in cols:
			var px := img.get_pixel(c, r)
			var i := r * cols + c
			cov[i] = px.a
			lum[i] = (px.r * 0.299 + px.g * 0.587 + px.b * 0.114) if px.a > 0.0 else 0.0

	# 只在有内容的格子上归一化，深色头发才不会塌成空格
	var lo := 1.0
	var hi := 0.0
	for i in cov.size():
		if cov[i] < 0.35:
			continue
		lo = minf(lo, lum[i])
		hi = maxf(hi, lum[i])
	var span := maxf(0.05, hi - lo)

	for r in rows:
		var line := ""
		for c in cols:
			var i := r * cols + c
			if cov[i] < 0.35:
				line += " "
				continue
			var nv := (lum[i] - lo) / span
			nv = pow(clampf(nv, 0.0, 1.0), 1.15)      ## 略提亮中间调
			var gi := clampi(int(roundf(nv * float(RAMP.length() - 1))), 0, RAMP.length() - 1)
			line += RAMP[gi]
		out.append(line.rstrip(" "))
	return out


static func _key_background(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w < 2 or h < 2:
		return
	var corners: Array[Color] = [
		img.get_pixel(0, 0), img.get_pixel(w - 1, 0),
		img.get_pixel(0, h - 1), img.get_pixel(w - 1, h - 1)]
	var opaque := 0
	for c in corners:
		if c.a > 0.9:
			opaque += 1
	if opaque < 3:
		return
	var key := corners[0]
	for c in corners:
		if c.r + c.g + c.b < key.r + key.g + key.b:
			key = c
	for y in h:
		for x in w:
			var px := img.get_pixel(x, y)
			if absf(px.r - key.r) + absf(px.g - key.g) + absf(px.b - key.b) < 0.12:
				px.a = 0.0
				img.set_pixel(x, y, px)


static func _alpha_bbox(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.35:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
