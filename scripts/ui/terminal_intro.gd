class_name TerminalIntro
extends Control
## 终端式进场（2026-10-28 主人钦定，取代 3D 转场）。
##
## 节奏：
##   ① 全屏终端：开机行 + 逐字敲出角色专属代码（for / while / 生成函数）
##   ② 代码打完后**停留 1 秒**
##   ③ 代码**瞬间消失**，屏幕正中**直接闪现**角色字符画（无扫描动画）
##   ④ 停留一拍后整层淡出，交给 arena 弹出真手牌
##
## 字符画：**单色**（不带彩），只用 ░▒▓█ 的疏密勾勒轮廓；
## 素材用设定图正面视图（rig/<id>-front/front.png），一个字符 = 一个像素块。

signal finished

# ── 时间轴（秒）────────────────────────────────
const T_BOOT := 0.55        ## 开机行
const T_CPS := 230.0        ## 打字速度（字符/秒）
const T_CODE_HOLD := 1.0    ## 代码打完停留（主人指定 1 秒）
const T_ART_HOLD := 1.6     ## 字符画停留
const T_FADE := 0.26        ## 淡出

# ── 外观 ─────────────────────────────────────
const C_BG := Color("#05070a")
const C_TERM := Color("#8ff0c4")
const C_DIM := Color("#2e6b57")
const C_ACCENT := Color("#9fe6ff")
const C_ART := Color("#dfe9f2")        ## 字符画主色（白）
const C_ART_HI := Color("#6fd8e8")     ## 最亮一档的点缀青（参照主人给的图）
## ASCII 密度梯度：从空到最密（经典 jp2a 风格），疏密勾出形体
const RAMP := " .'`^\",:;Il!i~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$"
const ART_FONT := 9                    ## 字符画字号（格高 ≈ 字号的 1.35 倍）
const ART_WIDTH_RATIO := 0.86          ## 字符画占屏宽比例
const ART_HEIGHT_RATIO := 0.84         ## 字符画占屏高比例
const GLYPHS := [" ", "░", "▒", "▓", "█"]
const COLUMNS := 42

var _ai_name := ""
var _code: PackedStringArray = []
var _art_chars := PackedStringArray()
var _art_cols := 0
var _art_rows_count := 0
var _art_font_px := 9

var _t := 0.0
var _done := false
var _on_done := Callable()
var _font: Font = null
var _code_chars := 0


## ai_id / ai_name：角色标识与显示名；art_tex：该角色像素立绘（转字符画用）
func play(ai_id: String, ai_name: String, art_tex: Texture2D, on_done: Callable) -> void:
	_on_done = on_done
	_ai_name = ai_name
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modulate.a = 1.0
	_font = PixelTheme.font()
	_code = IntroScript.code_for(ai_id, ai_name)
	_code_chars = 0
	for line in _code:
		_code_chars += line.length() + 1
	if art_tex != null:
		_build_art(art_tex, Vector2(1600, 900))
	_t = 0.0
	_done = false
	gui_input.connect(_on_gui)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _code_done_time() -> float:
	return T_BOOT + float(_code_chars) / T_CPS


func _art_start() -> float:
	return _code_done_time() + T_CODE_HOLD


func _total_time() -> float:
	return _art_start() + T_ART_HOLD + T_FADE


func _on_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		skip()


func skip() -> void:
	if not _done:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	if _on_done.is_valid():
		_on_done.call()
	queue_free()


# ── 绘制 ─────────────────────────────────────
func _draw() -> void:
	if _font == null:
		_font = PixelTheme.font()
	if _font == null:
		return
	var vp := get_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), C_BG)
	_draw_scanlines(vp)
	if _t < _art_start():
		_draw_terminal_text()
	else:
		_draw_art(vp)
	_draw_hint(vp)
	var total := _total_time()
	if _t > total - T_FADE:
		modulate.a = clampf((total - _t) / T_FADE, 0.0, 1.0)
		if _t >= total:
			_finish()


func _draw_scanlines(vp: Vector2) -> void:
	var y := 0.0
	while y < vp.y:
		draw_rect(Rect2(0, y, vp.x, 1), Color(0, 0, 0, 0.18))
		y += 3.0


func _draw_terminal_text() -> void:
	var boot := IntroScript.boot_lines(_ai_name)
	var y := 56.0
	var shown := int(floorf(_t / maxf(0.01, T_BOOT / float(boot.size()))))
	for i in mini(shown, boot.size()):
		draw_string(_font, Vector2(56, y), boot[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_DIM)
		y += 29.0
	y += 14.0
	var budget := int(floorf((_t - T_BOOT) * T_CPS))
	if budget <= 0:
		return
	# 代码行变长后总高会超出屏幕：整体上移，让最新一行贴住可视区底部（终端式滚屏）。
	# 不这么做的话后半段全画到屏幕外面去，看起来像卡住了。
	var line_h := 29.0
	var code_bottom := get_viewport_rect().size.y - 44.0
	var total_h := float(_code.size()) * line_h
	if y + total_h > code_bottom:
		y = maxf(34.0, code_bottom - total_h)
	var consumed := 0
	for line in _code:
		if consumed >= budget:
			break
		var take := mini(line.length(), budget - consumed)
		var txt := line.substr(0, take)
		if take < line.length():
			txt += "\u258c"
		var col := C_TERM
		if line.begins_with("//") or line.begins_with("#") or line.begins_with("/*") or line.begins_with(" *"):
			col = C_DIM
		elif line.begins_with("int ") or line.begins_with("static ") or line.begins_with("float "):
			col = C_ACCENT
		draw_string(_font, Vector2(56, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
		y += 29.0
		consumed += line.length() + 1


## 字符画：ASCII 疏密梯度、单色（最亮一档点一点青）、整块闪现、居中
func _draw_art(vp: Vector2) -> void:
	if _art_chars.is_empty() or _art_cols <= 0:
		return
	var step_x := _font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, _art_font_px).x
	var step_y := _font.get_height(_art_font_px)
	var w := float(_art_cols) * step_x
	var h := float(_art_rows_count) * step_y
	var ox := floorf((vp.x - w) * 0.5)
	var oy := floorf((vp.y - h) * 0.5)
	var ascent := _font.get_ascent(_art_font_px)
	var hi_from := int(float(RAMP.length()) * 0.86)     ## 最亮 14% 走点缀青
	for r in _art_rows_count:
		var line := _art_chars[r]
		for c in _art_cols:
			var ch := line[c]
			if ch == " ":
				continue
			var gi := RAMP.find(ch)
			var col := C_ART_HI if gi >= hi_from else C_ART
			draw_char(_font, Vector2(ox + c * step_x, oy + r * step_y + ascent),
					ch, _art_font_px, col)


func _draw_hint(vp: Vector2) -> void:
	if fmod(_t, 1.0) < 0.55:
		draw_string(_font, Vector2(56, vp.y - 30), "arena@neural:~$ %s\u258c" % _ai_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_TERM)
	draw_string(_font, Vector2(vp.x - 250, vp.y - 30), "[点击任意处跳过]",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)


# ── 像素图 → 单色字符网格 ─────────────────────
func _build_art(tex: Texture2D, vp: Vector2) -> void:
	var img := tex.get_image()
	if img == null:
		return
	img.convert(Image.FORMAT_RGBA8)
	_key_background(img)
	var bb := _alpha_bbox(img)
	if bb.size.x <= 0 or bb.size.y <= 0 or _font == null:
		return

	# 网格：格宽=字宽、格高=行高 → 天然是 ASCII 的瘦高格子，密度拉满
	_art_font_px = ART_FONT
	var step_x := _font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, ART_FONT).x
	var step_y := _font.get_height(ART_FONT)
	var rows := int((vp.y * ART_HEIGHT_RATIO) / step_y)
	var cols := int(rows * (float(bb.size.x) / float(bb.size.y)) * (step_y / step_x))
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

	# 只看「有像素」的格子做亮度归一化 —— 深色头发才能落到中间档
	var lo := 1.0
	var hi := 0.0
	for idx in covers.size():
		if covers[idx] < 0.12:
			continue
		lo = minf(lo, lums[idx])
		hi = maxf(hi, lums[idx])
	var span := maxf(0.05, hi - lo)

	_art_cols = cols
	_art_rows_count = rows
	_art_chars.clear()
	for r in rows:
		var line := ""
		for c in cols:
			var idx := r * cols + c
			if covers[idx] < 0.12:
				line += " "
				continue
			var nv := clampf((lums[idx] - lo) / span, 0.0, 1.0)
			nv = clampf(nv * 0.55 + covers[idx] * 0.45, 0.0, 1.0)   ## 亮度为主、覆盖率为辅
			var gi := int(roundf(nv * float(RAMP.length() - 1)))
			line += RAMP[clampi(gi, 0, RAMP.length() - 1)]
		_art_chars.append(line)


func _key_background(img: Image) -> void:
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


func _alpha_bbox(img: Image) -> Rect2i:
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
