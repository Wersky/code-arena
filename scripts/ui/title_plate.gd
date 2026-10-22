class_name TitlePlate
extends Control
## 主菜单的**大标题牌**：中文大字（逐字排版 + 硬阴影）+ 英文副题 + 连字符装饰线。
##
## 像素风纪律：硬边、无模糊、无渐变填充；高光用 1~2px 实心竖条扫过。
## 动效：整体亮度缓慢呼吸（0.92~1.0），每 4.2 秒有一道高光从左扫到右。

const CN := "代码擂台"
const EN := "CODE  ARENA"

const CN_SIZE := 60
const EN_SIZE := 24
const CN_GAP := 6.0          ## 中文字间距
const EN_GAP := 8.0          ## 英文词间距（已含在 EN 字符串里，这里再补）
const SHADOW := Vector2(3, 4)

var _t := 0.0
var _sweep := -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(760, 196)


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
	var cy := size.y * 0.5

	# ① 中英标题的逐字宽度（先算总宽才能居中）
	var cn_widths: Array[float] = []
	var cn_total := 0.0
	for i in CN.length():
		var cw := font.get_string_size(CN[i], HORIZONTAL_ALIGNMENT_LEFT, -1, CN_SIZE).x
		cn_widths.append(cw)
		cn_total += cw + CN_GAP
	cn_total -= CN_GAP
	var en_widths: Array[float] = []
	var en_total := 0.0
	for i in EN.length():
		var ew := font.get_string_size(EN[i], HORIZONTAL_ALIGNMENT_LEFT, -1, EN_SIZE).x
		en_widths.append(ew)
		en_total += ew + EN_GAP
	en_total -= EN_GAP

	var cn_x := w * 0.5 - cn_total * 0.5
	var cn_base := cy - 6.0
	var en_x := w * 0.5 - en_total * 0.5
	var en_base := cn_base + 44.0

	# ② 中文大字：先画硬阴影，再画本体（亮度呼吸）
	var x := cn_x
	for i in CN.length():
		draw_string(font, Vector2(x + SHADOW.x, cn_base + SHADOW.y), CN[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, CN_SIZE, Color(0, 0, 0, 0.75))
		draw_string(font, Vector2(x, cn_base), CN[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
				CN_SIZE, Color(0.97, 0.98, 1.0, breath))
		x += cn_widths[i] + CN_GAP

	# ③ 英文副题（金色，字距拉开）
	x = en_x
	var gold := Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, 0.86 * breath)
	for i in EN.length():
		draw_string(font, Vector2(x + 2, en_base + 2), EN[i], HORIZONTAL_ALIGNMENT_LEFT,
				-1, EN_SIZE, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(x, en_base), EN[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
				EN_SIZE, gold)
		x += en_widths[i] + EN_GAP

	# ④ 扫过标题的那道高光（只在标题带内，硬边 2px）
	if _sweep >= 0.0:
		var sx := roundf(cn_x - 40.0 + _sweep * (cn_total + 80.0))
		var a := 0.16 * (1.0 - absf(_sweep - 0.5) * 1.4)
		if a > 0.01:
			draw_rect(Rect2(Vector2(sx, cn_base - 56.0), Vector2(2, 66)),
					Color(1, 1, 1, a))

	# ⑤ 上下装饰线：两侧细线 + 中央小金块（"正式游戏"的分隔感）
	_deco_line(font, w, en_base + 26.0, breath)
	_deco_line(font, w, cn_base - 78.0, breath * 0.7)


func _deco_line(_font: Font, w: float, y: float, a: float) -> void:
	var gap := 18.0
	var half := w * 0.5 - gap
	var col := Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, 0.55 * a)
	draw_rect(Rect2(Vector2(w * 0.5 - half, roundf(y)), Vector2(half - 4.0, 1)), col)
	draw_rect(Rect2(Vector2(w * 0.5 + 4.0, roundf(y)), Vector2(half - 4.0, 1)), col)
	# 中央 5×5 菱形（用两行方块拼，避免旋转模糊）
	var cx := roundf(w * 0.5)
	var g := Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, 0.9 * a)
	draw_rect(Rect2(Vector2(cx - 1, y - 3), Vector2(2, 2)), g)
	draw_rect(Rect2(Vector2(cx - 3, y - 1), Vector2(6, 2)), g)
	draw_rect(Rect2(Vector2(cx - 1, y + 1), Vector2(2, 2)), g)
