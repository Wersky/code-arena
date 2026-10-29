class_name AsciiArt
extends Object
## 像素图 → ASCII 字符画（纯文本）。
##
## 关键实现（三条，都是踩坑换来的）：
##  ① **先把整幅图缩放到字符网格（面积平均）再逐格取字**。
##     早期每格只采一个像素（最近邻），对插画等于纯噪声——这是「糊成一片」的真因。
##  ② **横向比例必须按真实字符格算**（CELL_ASPECT = 格高/格宽）。
##     以前用 STRETCH 2.2 额外拉伸，人物被横着撑成 1.8 倍宽，看起来像鸡蛋。
##  ③ **叠加超采样梯度**，强边缘提亮，线条稿才不会被格子平均抹平。
##     只靠亮度梯度画出来是一团雾，加了边缘才看得出轮廓和结构。
##
## 已知上限：179x54 格的终端里，全身像的脸只占十几格，五官是画不出来的。
## 终端负责「符号印象」，清晰立绘交给游戏窗口（见 arena._show_hero_portrait）。

const RAMP := " .:-=+*#%@"
const CELL_ASPECT := 1.965      ## 终端字符 格高/格宽（实测 14.3 x 28.1 px）
const EDGE_TH := 0.55           ## 梯度阈值：超过就当作线条
const EDGE_BOOST := 3           ## 线条提亮档数
const SS_X := 4                 ## 超采样倍数（横向）
const SS_Y := 8                 ## 超采样倍数（纵向）


## [param rows] 目标行数；[param max_cols] 宽度上限；返回每行一条字符串（右侧已去尾空格）。
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
	img = img.get_region(bb)

	var src_aspect := float(img.get_width()) / float(img.get_height())
	var cols := int(round(float(rows) * src_aspect * cell_aspect))
	if cols > max_cols:
		cols = max_cols
		rows = maxi(4, int(round(float(cols) / (src_aspect * cell_aspect))))
	cols = maxi(8, cols)
	rows = maxi(4, rows)

	var lum := _luma_grid(img, cols, rows)
	if lum.size() != cols * rows:
		return out
	var cov := _coverage_grid(img, cols, rows)
	var edges := _edge_grid(img, cols, rows)

	# 只在有内容的格子上做 1%~99% 分位拉伸，深色头发才不会塌成空格
	var samples: Array[float] = []
	for i in cols * rows:
		if cov[i] >= 0.35:
			samples.append(lum[i])
	if samples.is_empty():
		return out
	samples.sort()
	var lo := samples[int(float(samples.size() - 1) * 0.01)]
	var hi := samples[int(float(samples.size() - 1) * 0.99)]
	var span := maxf(0.05, hi - lo)

	for r in rows:
		var line := ""
		for c in cols:
			var i := r * cols + c
			if cov[i] < 0.35:
				line += " "
				continue
			var nv := clampf((lum[i] - lo) / span, 0.0, 1.0)
			nv = pow(nv, 1.2)
			var lv := int(roundf(nv * float(RAMP.length() - 1)))
			if edges[i] > EDGE_TH:
				lv = mini(RAMP.length() - 1, lv + EDGE_BOOST)
			line += RAMP[lv]
		out.append(line.rstrip(" "))
	return out


## 面积平均后的亮度网格（BILINEAR 缩小 = 一格取整块的平均色）
static func _luma_grid(img: Image, cols: int, rows: int) -> PackedFloat32Array:
	var small := img.duplicate() as Image
	small.resize(cols, rows, Image.INTERPOLATE_BILINEAR)
	var d := small.get_data()
	var out := PackedFloat32Array()
	out.resize(cols * rows)
	for i in cols * rows:
		var o := i * 4
		out[i] = (float(d[o]) * 0.299 + float(d[o + 1]) * 0.587 + float(d[o + 2]) * 0.114) / 255.0
	return out


static func _coverage_grid(img: Image, cols: int, rows: int) -> PackedFloat32Array:
	var small := img.duplicate() as Image
	small.resize(cols, rows, Image.INTERPOLATE_BILINEAR)
	var d := small.get_data()
	var out := PackedFloat32Array()
	out.resize(cols * rows)
	for i in cols * rows:
		out[i] = float(d[i * 4 + 3]) / 255.0
	return out


## 超采样算梯度，每格取最大幅值 —— 细线条（头发丝、褶边）不会被面积平均吃掉
static func _edge_grid(img: Image, cols: int, rows: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(cols * rows)
	var sw := cols * SS_X
	var sh := rows * SS_Y
	var big := img.duplicate() as Image
	big.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	var d := big.get_data()
	var l := PackedFloat32Array()
	l.resize(sw * sh)
	for i in sw * sh:
		var o := i * 4
		l[i] = (float(d[o]) * 0.299 + float(d[o + 1]) * 0.587 + float(d[o + 2]) * 0.114) / 255.0
	for r in rows:
		for c in cols:
			var best := 0.0
			for yy in SS_Y:
				var y := r * SS_Y + yy
				if y <= 0 or y >= sh - 1:
					continue
				var row := y * sw
				var up := (y - 1) * sw
				var dn := (y + 1) * sw
				for xx in SS_X:
					var x := c * SS_X + xx
					if x <= 0 or x >= sw - 1:
						continue
					var gx := l[row + x + 1] - l[row + x - 1]
					var gy := l[dn + x] - l[up + x]
					var m := sqrt(gx * gx + gy * gy)
					if m > best:
						best = m
			out[r * cols + c] = best
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
