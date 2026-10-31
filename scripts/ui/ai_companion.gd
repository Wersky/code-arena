class_name AiCompanion
extends Control
## 屏幕右侧的 AI 娘吉祥物（纯装饰，不参与计分，不挡鼠标）。
##
## deepdeek → Q 版睡觉小人：程序化像素画（与 ChibiRig 占位件同一套深蓝调色板），
##            底边中心为轴做呼吸起伏，头顶飘 Zzz。
## 其余 AI  → 立绘 PNG（192×256）轻轻漂浮。
##
## 动画纪律：只 tween scale / rotation / modulate / position（绝对坐标，不走锚点），
## 全部 resize 后由 _place_children() 重排，窗口缩放不会散架。

## 睡觉小人的画布（美术像素）与放大倍率
const SLEEP_W := 64
const SLEEP_H := 46
const SLEEP_SCALE := 4

## Zzz 气泡参数：三个 Z 错相漂浮
const Z_DURS := [2.4, 3.0, 3.6]
const Z_RISE := 22.0

## 生成的睡觉立绘（2026-10-25 主人钦定的 DeepSeek 专属形象，
## 由「蓝白鲸纹女仆像素角色设定图」图生图而来；画里已自带 ZZZ）
const SLEEP_ASSET := "res://assets/art/ai-deepdeek-sleep.png"
## 成长到「有点睡醒」用的立绘（快跑 1K 生图，2026-10-30）
const AWAKE_ASSET := "res://assets/art/ai-deepdeek-awake.png"
## 完全觉醒站立立绘（2026-10-31 主人钦定：调皮自信「来打我呀」神态）
const STAND_ASSET := "res://assets/art/ai-deepdeek-awake-stand.png"

## 深蓝调色板（与 chibi_rig 占位件一致，保持一套 DeepSeek 系颜色）
const C_OUT := Color("#1B2246")
const C_BLUE := Color("#4D6BFE")
const C_BLUE_DK := Color("#3C55D8")
const C_NAVY := Color("#2E3A8C")
const C_NAVY_DK := Color("#232C6B")
const C_SKIN := Color("#E9EEFF")
const C_BLUE_LT := Color("#7FA0FF")
const C_BLUE_HL := Color("#6D87FF")
const C_BLUSH := Color("#FF9FB0")
const C_MOUTH := Color("#C46A7A")
const C_Z := Color("#9FB8FF")

var _ai: AiData = null
var _art: TextureRect = null
var _zs: Array[Label] = []
var _mode := ""   ## "sleep" / "portrait"
var _stage := "sleep"   ## 睡觉造型成长阶段：sleep / stir / stand
var _art_generated := false   ## 睡觉图用的是生成立绘（true）还是程序化回退（false）


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_place_children)


## 展示哪位 AI 娘。ai == null 时隐藏。
## 成长状态切换：吃满白米饭后从「沉睡」换成「有点睡醒」。
## 只对 deepdeek 的睡觉造型生效（其它 AI 是立绘模式，没有这个阶段）。
## 展示哪位 AI 娘。ai == null 时隐藏。
## 成长三段（2026-10-31 主人钦定）：sleep 躺睡 → stir 翻身坐起 → stand 觉醒站立。
## 只对 deepdeek 的睡觉造型生效（其它 AI 是立绘模式，没有这个阶段）。
func set_stage(stage: String) -> void:
	if _mode != "sleep" or _art == null or _stage == stage:
		return
	_stage = stage
	var path := SLEEP_ASSET
	if stage == "stir":
		path = AWAKE_ASSET
	elif stage == "stand":
		path = STAND_ASSET
	var t := load(path) as Texture2D
	if t == null:
		return
	_art.texture = t
	_art_generated = true
	_place_children()
	# 换形态弹一下，肉眼能看出「变了」
	_art.pivot_offset = Vector2(_art.size.x * 0.5, _art.size.y)
	_art.scale = Vector2(0.84, 0.84)
	var tw := _art.create_tween()
	tw.tween_property(_art, "scale", Vector2.ONE, 0.42) 			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
func setup(ai: AiData) -> void:
	_ai = ai
	_teardown()
	if ai == null:
		return
	if ai.id == "deepdeek":
		_mode = "sleep"
		_art = _make_sleep_sprite()
	else:
		_mode = "portrait"
		_art = _make_portrait(ai)
	add_child(_art)
	_place_children()
	_start_anim()


func _teardown() -> void:
	for c in get_children():
		c.queue_free()
	_art = null
	_zs.clear()
	_mode = ""
	_art_generated = false


# ─────────────────────────────────────────────────────────
#  造型
# ─────────────────────────────────────────────────────────
## Q 版睡觉小人：优先用生成的立绘（主人钦定的专属形象）；资产缺失时回退程序化像素画
func _make_sleep_sprite() -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "Art"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(SLEEP_ASSET):
		var t: Resource = load(SLEEP_ASSET)
		if t is Texture2D:
			rect.texture = t as Texture2D
			# 生成图是高密度像素画、显示时大幅缩小——线性过滤更稳，NEAREST 会丢细描边
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_SCALE
			_art_generated = true
			return rect
	_art_generated = false
	var img := Image.create_empty(SLEEP_W, SLEEP_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 小枕头（头下面那只：中蓝 + 顶上一条亮边，和深蓝坐垫拉开层次）
	_blob(img, Rect2i(2, 26, 24, 8), C_BLUE_DK, C_OUT)
	_blob(img, Rect2i(4, 26, 20, 2), C_BLUE_LT, Color(0, 0, 0, 0), false)
	# 大坐垫（整幅画的底座）
	_blob(img, Rect2i(4, 33, 56, 9), C_NAVY_DK, C_OUT)
	_blob(img, Rect2i(6, 34, 52, 2), C_NAVY, Color(0, 0, 0, 0), false)
	# 毯子拱起的身体（从枕边一直盖到画面右端）
	for y in range(20, 34):
		var w := 6 + (y - 20) * 2
		if y > 30:
			w = 18 - (y - 30) * 3
		_blob(img, Rect2i(22, y, 36, 1), C_BLUE, Color(0, 0, 0, 0), false)
	_blob(img, Rect2i(22, 33, 36, 1), C_OUT, Color(0, 0, 0, 0), false)
	# 毯子上沿的高光与褶皱
	for x in range(24, 56):
		var top := 20 + (8 - absi(x - 40) / 2)
		if x % 2 == 0:
			_px(img, x, top, C_BLUE_HL)
	_blob(img, Rect2i(30, 26, 1, 6), C_BLUE_DK, Color(0, 0, 0, 0), false)
	_blob(img, Rect2i(38, 24, 1, 8), C_BLUE_DK, Color(0, 0, 0, 0), false)
	_blob(img, Rect2i(46, 27, 1, 5), C_BLUE_DK, Color(0, 0, 0, 0), false)
	# 脚从毯子右端露出来：两只加大、上下错开、中间留缝的小脚
	_blob(img, Rect2i(52, 26, 5, 6), C_SKIN, C_OUT)
	_blob(img, Rect2i(58, 28, 5, 6), C_SKIN, C_OUT)
	# 头（大圆脸枕在枕头上）：先画整张脸，再用头发只盖「发顶 + 后脑」，
	# 脸窗要够大（正面看过去大半张脸是肤色，才认得出是女孩）。
	_disc(img, Vector2i(14, 15), 10, C_SKIN, C_OUT)
	for y in range(4, 26):
		for x in range(3, 25):
			var dd := Vector2(float(x - 14), float(y - 15)).length()
			if dd <= 10.0 and (y <= 9 or x >= 20):
				_px(img, x, y, C_BLUE)
	# 发顶 / 后脑的外缘补一圈深色描边（头发盖掉了脸的描边）
	for y in range(3, 27):
		for x in range(2, 26):
			var dd := Vector2(float(x - 14), float(y - 15)).length()
			if dd > 10.0 and dd <= 12.0 and (y <= 10 or x >= 19):
				_px(img, x, y, C_OUT)
	# 后脑勺一小撮头发垂到枕头上
	_blob(img, Rect2i(20, 24, 5, 4), C_BLUE, C_OUT)
	_blob(img, Rect2i(18, 26, 4, 3), C_BLUE, C_OUT)
	# 刘海：额前一排浅锯齿压在发际线上（别吃掉脸窗）
	for i in 4:
		_blob(img, Rect2i(6 + i * 3, 10 + (i % 2), 3, 2), C_BLUE, C_OUT)
	_blob(img, Rect2i(5, 11, 2, 3), C_BLUE, C_OUT)
	# 发顶高光 + 浅蓝发夹
	_blob(img, Rect2i(9, 5, 5, 2), C_BLUE_HL, Color(0, 0, 0, 0), false)
	_blob(img, Rect2i(21, 7, 3, 2), C_BLUE_LT, C_OUT)
	# 睡脸：闭眼（︶×2）+ 腮红 + 小嘴（都落在露出的脸窗里）
	_px(img, 10, 18, C_OUT)
	_px(img, 11, 19, C_OUT)
	_px(img, 12, 19, C_OUT)
	_px(img, 13, 18, C_OUT)
	_px(img, 15, 18, C_OUT)
	_px(img, 16, 19, C_OUT)
	_px(img, 17, 19, C_OUT)
	_px(img, 18, 18, C_OUT)
	_blob(img, Rect2i(8, 21, 2, 1), C_BLUSH, Color(0, 0, 0, 0), false)
	_blob(img, Rect2i(17, 21, 2, 1), C_BLUSH, Color(0, 0, 0, 0), false)
	_blob(img, Rect2i(13, 22, 3, 1), C_MOUTH, Color(0, 0, 0, 0), false)

	var fallback := TextureRect.new()
	fallback.name = "Art"
	fallback.texture = ImageTexture.create_from_image(img)
	fallback.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return fallback


## 其他 AI：直接用立绘，轻轻漂
func _make_portrait(ai: AiData) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "Art"
	if ai.portrait_path != "" and ResourceLoader.exists(ai.portrait_path):
		var t: Resource = load(ai.portrait_path)
		if t is Texture2D:
			rect.texture = t as Texture2D
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.custom_minimum_size = Vector2(160, 214)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# ─────────────────────────────────────────────────────────
#  摆位（resize 跟着重排）
# ─────────────────────────────────────────────────────────
func _place_children() -> void:
	if _art == null:
		return
	var art_size := _art_display_size()
	# 底部留 8px 呼吸空间；睡觉小人偏左一点点，Zzz 从头顶飘
	var cx := size.x * (0.44 if _mode == "sleep" else 0.5)
	_art.size = art_size
	_art.pivot_offset = Vector2(art_size.x * 0.5, art_size.y if _mode == "sleep" else art_size.y * 0.5)
	_art.position = Vector2(cx - art_size.x * 0.5, size.y - art_size.y - 8.0)

	for i in _zs.size():
		var z := _zs[i]
		z.pivot_offset = z.get_minimum_size() * 0.5
		z.position = Vector2(cx - art_size.x * 0.35 + i * 14.0,
				size.y - art_size.y - 18.0 - i * 12.0)


## 当前造型在盒子里的显示尺寸
func _art_display_size() -> Vector2:
	if _mode == "portrait":
		return _art.custom_minimum_size
	if not _art_generated or _art.texture == null:
		return Vector2(SLEEP_W, SLEEP_H) * SLEEP_SCALE
	# 生成立绘：按原始宽高比缩进盒子（高不超过 300）
	var aspect := float(_art.texture.get_width()) / float(_art.texture.get_height())
	var max_h := minf(size.y - 16.0, 300.0)
	var w := minf(size.x - 8.0, max_h * aspect)
	return Vector2(w, w / aspect)


# ─────────────────────────────────────────────────────────
#  动画
# ─────────────────────────────────────────────────────────
func _start_anim() -> void:
	if _mode == "sleep":
		# 呼吸：底边为轴，纵向轻轻起伏
		var tw := _art.create_tween().set_loops()
		tw.tween_property(_art, "scale:y", 1.035, 1.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_art, "scale:y", 1.0, 1.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		# Zzz：三个 Z 错相上飘、渐隐（生成立绘画里已自带 ZZZ，就不叠加了）
		if not _art_generated:
			for i in Z_DURS.size():
				var z := Label.new()
				z.text = "Z"
				z.add_theme_font_size_override("font_size", [18, 14, 11][i])
				z.add_theme_color_override("font_color", C_Z)
				z.add_theme_constant_override("outline_size", 4)
				z.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
				z.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(z)
				_zs.append(z)
			_place_children()
			for i in _zs.size():
				_loop_z(_zs[i], Z_DURS[i])
	else:
		# 立绘漂浮：缩放 + 微转（pivot 在中心，位置不会被锚点拉回去）
		var tw := _art.create_tween().set_loops()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_art, "scale", Vector2(1.02, 1.02), 1.1)
		tw.tween_property(_art, "scale", Vector2.ONE, 1.1)
		var sway := _art.create_tween().set_loops()
		sway.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sway.tween_property(_art, "rotation", 0.018, 1.6)
		sway.tween_property(_art, "rotation", -0.018, 1.6)


## 一个 Z 的循环：先归位，再上飘 + 渐隐，留一小段间隔
func _loop_z(z: Label, dur: float) -> void:
	var base := z.position
	z.modulate.a = 0.0
	var tw := z.create_tween().set_loops()
	tw.tween_callback(func() -> void:
		z.position = base
		z.modulate.a = 0.0)
	tw.tween_property(z, "modulate:a", 0.95, dur * 0.2)
	tw.tween_property(z, "position:y", base.y - Z_RISE, dur * 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(z, "modulate:a", 0.0, dur * 0.4).set_delay(dur * 0.25)
	tw.tween_interval(dur * 0.2)


# ─────────────────────────────────────────────────────────
#  像素绘制小工具（同 chibi_rig 的画法，硬边、无抗锯齿）
# ─────────────────────────────────────────────────────────
func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, col)


func _blob(img: Image, r: Rect2i, col: Color, outline: Color, do_outline: bool = true) -> void:
	img.fill_rect(r, col)
	if not do_outline or outline.a <= 0.0:
		return
	if r.size.x > 2:
		img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 1), outline)
		img.fill_rect(Rect2i(r.position.x, r.position.y + r.size.y - 1, r.size.x, 1), outline)
	if r.size.y > 2:
		img.fill_rect(Rect2i(r.position.x, r.position.y, 1, r.size.y), outline)
		img.fill_rect(Rect2i(r.position.x + r.size.x - 1, r.position.y, 1, r.size.y), outline)


func _disc(img: Image, c: Vector2i, rad: int, col: Color, outline: Color) -> void:
	for y in range(c.y - rad, c.y + rad + 1):
		if y < 0 or y >= img.get_height():
			continue
		for x in range(c.x - rad, c.x + rad + 1):
			if x < 0 or x >= img.get_width():
				continue
			var d := Vector2(float(x - c.x), float(y - c.y)).length()
			if d <= float(rad):
				img.set_pixel(x, y, outline if d > float(rad) - 2.0 else col)


# ─────────────────────────────────────────────────────────
#  测试钩子
# ─────────────────────────────────────────────────────────
func debug_mode() -> String:
	return _mode
