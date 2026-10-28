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
const C_ART := Color("#dfe9f2")
const GLYPHS := [" ", "░", "▒", "▓", "█"]
const COLUMNS := 42

var _ai_name := ""
var _code: PackedStringArray = []
var _art_rows: Array[PackedInt32Array] = []
var _art_cols := 0

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
		_build_art(art_tex, COLUMNS)
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


## 字符画：单色、整块闪现、居中
func _draw_art(vp: Vector2) -> void:
	if _art_rows.is_empty() or _art_cols <= 0:
		return
	var cell := _cell_size(vp)
	var step := cell + Vector2(1, 1)
	var w := float(_art_cols) * step.x
	var h := float(_art_rows.size()) * step.y
	var ox := floorf((vp.x - w) * 0.5)
	var oy := floorf((vp.y - h) * 0.5)
	var size := int(cell.y)
	var ascent := _font.get_ascent(size)
	for r in _art_rows.size():
		var row := _art_rows[r]
		for c in _art_cols:
			var gi := row[c]
			if gi <= 0:
				continue
			var col := C_ART
			if gi == 2:
				col = Color(C_ART, 0.66)
			elif gi == 1:
				col = Color(C_ART, 0.42)
			draw_char(_font, Vector2(ox + c * step.x, oy + r * step.y + ascent),
					GLYPHS[gi], size, col)


func _cell_size(vp: Vector2) -> Vector2:
	var cols := float(maxi(1, _art_cols))
	var rows := float(maxi(1, _art_rows.size()))
	var s := minf((vp.x * 0.46) / cols, (vp.y * 0.74) / rows)
	s = maxf(4.0, floorf(s))
	return Vector2(s, s)


func _draw_hint(vp: Vector2) -> void:
	if fmod(_t, 1.0) < 0.55:
		draw_string(_font, Vector2(56, vp.y - 30), "arena@neural:~$ %s\u258c" % _ai_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_TERM)
	draw_string(_font, Vector2(vp.x - 250, vp.y - 30), "[点击任意处跳过]",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_DIM)


# ── 像素图 → 单色字符网格 ─────────────────────
func _build_art(tex: Texture2D, cols: int) -> void:
	var img := tex.get_image()
	if img == null:
		return
	img.convert(Image.FORMAT_RGBA8)
	_key_background(img)
	var bb := _alpha_bbox(img)
	if bb.size.x <= 0 or bb.size.y <= 0:
		return
	var cw := float(bb.size.x) / float(cols)
	var rows := maxi(1, int(round(float(bb.size.y) / cw)))

	# 第一遍：采样每个格子的覆盖率与平均亮度
	var cover := PackedFloat32Array()
	var lums := PackedFloat32Array()
	cover.resize(cols * rows)
	lums.resize(cols * rows)
	for r in rows:
		for c in cols:
			var sx0 := bb.position.x + int(c * cw)
			var sx1 := maxi(sx0 + 1, bb.position.x + int((c + 1) * cw))
			var sy0 := bb.position.y + int(r * cw)
			var sy1 := maxi(sy0 + 1, bb.position.y + int((r + 1) * cw))
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
			cover[idx] = float(n) / float(maxi(1, (sy1 - sy0) * (sx1 - sx0)))
			lums[idx] = lum / float(maxi(1, n))

	# 亮度归一化：这张图里最深（深蓝头发）和最亮（白围裙）拉到 0..1，
	# 否则深色区域全落在最低档、整块看起来只剩白团。
	var lo := 1.0
	var hi := 0.0
	for idx in cover.size():
		if cover[idx] < 0.16:
			continue
		lo = minf(lo, lums[idx])
		hi = maxf(hi, lums[idx])
	var span := maxf(0.05, hi - lo)

	_art_cols = cols
	_art_rows.clear()
	for r in rows:
		var glyphs := PackedInt32Array()
		glyphs.resize(cols)
		for c in cols:
			var idx := r * cols + c
			if cover[idx] < 0.16:
				glyphs[c] = 0
				continue
			var nv := clampf((lums[idx] - lo) / span, 0.0, 1.0)
			# 归一化亮度 → 4 级方块；覆盖率很低的边缘格降一档，轮廓才不糊
			var level := 1 + int(roundf(nv * 3.0))
			if cover[idx] < 0.5:
				level = maxi(1, level - 1)
			glyphs[c] = clampi(level, 1, 4)
		_art_rows.append(glyphs)


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
