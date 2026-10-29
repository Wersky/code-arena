class_name AsciiArt
extends Object
## 像素图 → ASCII 字符画（纯文本，供游戏内终端 / 真实系统终端共用）。
##
## 用「疏密梯度」表现明暗：空格 → . : - = + * # % @ $，越亮字符越密。
## 终端字符天生窄高一倍，所以按 cell 宽 1 : 高 2 的假设换算列数。

const RAMP := " .:-=+*#%@"
const CELL_ASPECT := 2.0        ## 终端字符宽:高 ≈ 1:2
const STRETCH := 1.0            ## 横向拉伸系数
const CROP_W := 0.86            ## 横向只取中间 55%：头发太抢画面，裁窄点让身体/手势占比更大
const BUST := 0.78              ## 取「头 + 手势 + 上半身」高度比例（0.40 只到脸，太小）
                                ## 全身缩进去必然糊，胸像才够精细（参考图也是胸像）


## 返回字符画文本行；rows 为目标行数（字体/窗口能放多少行就传多少）
static func build(tex: Texture2D, rows: int, max_cols: int = 110,
		cell_aspect: float = CELL_ASPECT) -> PackedStringArray:
	var out := PackedStringArray()
	if tex == null:
		return out
	var img := tex.get_image()
	if img == null:
		return out
	img.convert(Image.FORMAT_RGBA8)
	_key_background(img)
	# 像素图色块太硬，直接采样会变噪点汤；先双线性放大当"柔化"，阶梯色调才会平滑
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_BILINEAR)
	var bb := _alpha_bbox(img)
	if bb.size.x <= 0 or bb.size.y <= 0:
		return out
	# 只取上半身（胸像）：从内容顶部裁剪 BUST 比例的高度
	# 先按比例裁出「头 + 肩」的取景框（横向居中），否则长发会把构图撑成扁的
	var crop_h := maxi(8, int(float(bb.size.y) * BUST))
	var crop_w := maxi(8, int(float(bb.size.x) * CROP_W))
	var crop_rect := Rect2i(Vector2i(bb.position.x + (bb.size.x - crop_w) / 2, bb.position.y),
			Vector2i(crop_w, mini(crop_h, bb.size.y)))
	# 裁完再算一次内容包围盒：裁切框比角色宽时，网格里会有一半空列、角色被挤到一边
	img = img.get_region(crop_rect)
	bb = _alpha_bbox(img)
	if bb.size.x <= 0 or bb.size.y <= 0:
		return out
	var src_aspect := float(bb.size.x) / float(bb.size.y)
	var cols := int(round(float(rows) * src_aspect * cell_aspect * STRETCH))
	if cols > max_cols:
		cols = max_cols
		rows = maxi(4, int(round(float(cols) / (src_aspect * cell_aspect * STRETCH))))
	cols = maxi(8, cols)
	rows = maxi(4, rows)
	var lums := PackedFloat32Array()
	var covers := PackedFloat32Array()
	lums.resize(cols * rows)
	covers.resize(cols * rows)
	for r in rows:
		for c in cols:
			var sx0 := bb.position.x + int(float(c) / cols * bb.size.x)
			var sx1 := maxi(sx0 + 1, bb.position.x + int(float(c + 1) / cols * bb.size.x))
			var sy0 := bb.position.y + int(float(r) / rows * bb.size.y)
			var sy1 := maxi(sy0 + 1, bb.position.y + int(float(r + 1) / rows * bb.size.y))
			var lum := 0.0
			var n := 0
			for y in range(sy0, mini(sy1, img.get_height())):
				for x in range(sx0, mini(sx1, img.get_width())):
					var px := img.get_pixel(x, y)
					if px.a < 0.35:
						continue
					lum += px.r * 0.299 + px.g * 0.587 + px.b * 0.114
					n += 1
			var idx := r * cols + c
			covers[idx] = float(n) / float(maxi(1, (sy1 - sy0) * (sx1 - sx0)))
			lums[idx] = lum / float(maxi(1, n))
	# 亮度归一化（只看有像素的格子），否则深色头发会掉到最暗档
	var lo := 1.0
	var hi := 0.0
	for idx in covers.size():
		if covers[idx] < 0.12:
			continue
		lo = minf(lo, lums[idx])
		hi = maxf(hi, lums[idx])
	var span := maxf(0.05, hi - lo)
	for r in rows:
		var line := ""
		for c in cols:
			var idx := r * cols + c
			if covers[idx] < 0.12:
				line += " "
				continue
			# 直接用亮度（不要覆盖率混合，否则像素图的平涂色块会变成噪点汤）；
			# gamma 提亮中间调，白围裙才会亮起来、深色头发才落到低档
			var nv := 0.22 + 0.78 * clampf(pow(clampf(lums[idx], 0.0, 1.0), 1.15), 0.0, 1.0)   ## 抬暗部：剪影可见、亮部仍最密
			# 边缘检测：轮廓用最密的字符描出来，内部才按明暗填 —— 字符画能不能看清，全看这步
			var e := 0.0
			var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			for d: Vector2i in dirs:
				var nr: int = r + d.y
				var nc: int = c + d.x
				if nr < 0 or nr >= rows or nc < 0 or nc >= cols:
					continue
				var nidx: int = nr * cols + nc
				if covers[nidx] < 0.12:
					e = maxf(e, covers[idx])              ## 挨着背景的格子必然算轮廓
				else:
					e = maxf(e, absf(lums[idx] - lums[nidx]))
			var gi := int(roundf(nv * float(RAMP.length() - 1)))
			if e > 0.99:
				gi = RAMP.length() - 1                    ## 轮廓：最密字符
			elif e > 0.98:
				gi = maxi(gi, RAMP.length() - 3)
			line += RAMP[clampi(gi, 0, RAMP.length() - 1)]
		out.append(line.rstrip(" "))
	return out


static func _key_background(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
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
