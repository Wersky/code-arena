class_name TitlePlate
extends Control
## 主菜单的**大标题牌**：生图的金框牌匾 + 中文大字（逐字排版 + 硬阴影）+ 英文副题。
##
## 为什么要现画文字而不是把字烘进图里：中文标题是游戏名，会改；而且生图模型写中文
## 基本必错字。所以牌匾只出「空框」，字由像素字体绘制。
##
## 像素风纪律：硬边、无模糊、无渐变填充；高光用 2px 实心竖条扫过。
## 动效：整体亮度缓慢呼吸（0.92~1.0），每 4.2 秒有一道高光从左扫到右。

const CN := "代码擂台"
const EN := "CODE  ARENA"

## 牌匾资产名（"ui/plaque"）。留空则只画字，不画底。
var plate := ""

var cn_size := 90
var en_size := 30
var cn_gap := 10.0               ## 中文字间距
var en_gap := 10.0               ## 英文词间距
var shadow := Vector2(4, 5)

var _t := 0.0
var _sweep := -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(808, 294)


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# 每 4.2 秒扫一道高光，扫完 _sweep 置 -1（不画）
	var cycle := fmod(_t, 4.2)
	_sweep = cycle / 0.85 if cycle < 0.85 else -1.0
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var breath := 0.92 + 0.08 * (0.5 + 0.5 * sin(_t * 1.1))
	var w := size.x
	var has_plate := not plate.is_empty() and UiArt.has(plate)

	if has_plate:
		draw_texture_rect(UiArt.tex(plate), Rect2(Vector2.ZERO, size), false)

	# 牌匾的内腔范围（避开顶部徽饰与四周金边）。没有底就退回居中。
	# 牌匾内腔：上沿要给顶部六边形徽饰让位
	var body_top := size.y * 0.26 if has_plate else size.y * 0.30
	var body_bot := size.y * 0.90 if has_plate else size.y * 0.80
	var cn_base := roundf(lerpf(body_top, body_bot, 0.60))
	var en_base := roundf(cn_base + cn_size * 0.46)

	# ① 中英标题的逐字宽度（先算总宽才能居中）
	var cn_widths: Array[float] = []
	var cn_total := 0.0
	for i in CN.length():
		var cw := font.get_string_size(CN[i], HORIZONTAL_ALIGNMENT_LEFT, -1, cn_size).x
		cn_widths.append(cw)
		cn_total += cw + cn_gap
	cn_total -= cn_gap
	var en_widths: Array[float] = []
	var en_total := 0.0
	for i in EN.length():
		var ew := font.get_string_size(EN[i], HORIZONTAL_ALIGNMENT_LEFT, -1, en_size).x
		en_widths.append(ew)
		en_total += ew + en_gap
	en_total -= en_gap

	var cn_x := roundf(w * 0.5 - cn_total * 0.5)
	var en_x := roundf(w * 0.5 - en_total * 0.5)

	# ② 中文大字：先画硬阴影，再画本体（亮度呼吸）
	var x := cn_x
	for i in CN.length():
		draw_string(font, Vector2(x + shadow.x, cn_base + shadow.y), CN[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, cn_size, Color(0, 0, 0, 0.78))
		draw_string(font, Vector2(x, cn_base), CN[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
				cn_size, Color(0.97, 0.98, 1.0, breath))
		x += cn_widths[i] + cn_gap

	# ③ 英文副题（金色，字距拉开）
	x = en_x
	var neon := Color(UiArt.NEON.r, UiArt.NEON.g, UiArt.NEON.b, 0.92 * breath)
	for i in EN.length():
		draw_string(font, Vector2(x + 3, en_base + 3), EN[i], HORIZONTAL_ALIGNMENT_LEFT,
				-1, en_size, Color(0, 0, 0, 0.65))
		draw_string(font, Vector2(x, en_base), EN[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
				en_size, neon)
		x += en_widths[i] + en_gap

	# ④ 扫过标题的那道高光（只在标题带内，硬边 2px）
	if _sweep >= 0.0:
		var sx := roundf(cn_x - 40.0 + _sweep * (cn_total + 80.0))
		var a := 0.18 * (1.0 - absf(_sweep - 0.5) * 1.4)
		if a > 0.01:
			draw_rect(Rect2(Vector2(sx, cn_base - cn_size * 0.92),
					Vector2(2, cn_size * 1.1)), Color(1, 1, 1, a))

	# ⑤ 没牌匾时才补装饰线（有牌匾时金边本身就是装饰，再加就脏）
	if not has_plate:
		_deco_line(w, en_base + 26.0, breath)
		_deco_line(w, cn_base - cn_size * 1.3, breath * 0.7)


func _deco_line(w: float, y: float, a: float) -> void:
	var gap := 18.0
	var half := w * 0.5 - gap
	var col := Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, 0.55 * a)
	draw_rect(Rect2(Vector2(w * 0.5 - half, roundf(y)), Vector2(half - 4.0, 1)), col)
	draw_rect(Rect2(Vector2(w * 0.5 + 4.0, roundf(y)), Vector2(half - 4.0, 1)), col)
	var cx := roundf(w * 0.5)
	var g := Color(UiArt.NEON.r, UiArt.NEON.g, UiArt.NEON.b, 0.9 * a)
	draw_rect(Rect2(Vector2(cx - 1, y - 3), Vector2(2, 2)), g)
	draw_rect(Rect2(Vector2(cx - 3, y - 1), Vector2(6, 2)), g)
	draw_rect(Rect2(Vector2(cx - 1, y + 1), Vector2(2, 2)), g)
