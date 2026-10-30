class_name SymbolFrame
extends Control
## 把终端里那一屏字符画 **1:1** 复刻到游戏窗口。
##
## 为什么不用 Label / RichTextLabel：它们是按字体的自然步进排字的，而终端是**固定字符格**。
## 字体步进和格宽只要差 1%，几十列之后就会整体偏出去，复刻就对不上了。
## 所以这里逐格定位、逐字绘制：每个字都画在 (列 * 格宽, 行 * 格高) 上。
##
## 字号怎么定：终端里一个字符正好占一个格子宽，所以**按格宽反推字号**（em = 格宽 / 步进比）。
## 这才是终端的真实比例。之前用「字号 = 格高 × 系数」再按格宽夹，结果把字夹小了 13%，
## 画出来比终端细一圈。格高只用来兜一个上限，防止字太高串到上一行。
## 前三个是终端的等宽字体；后面两个是**带中文字形**的系统字体。
## 字幕「正在生成 AI 娘中」里有中文，而 draw_char 不做缺字回退——列表里没有中文字体时
## 中文整行画不出来（实测只画出了 "AI"）。等宽在前保证 ASCII 走终端同款。
const FONT_NAMES := ["Cascadia Mono", "Consolas", "Courier New", "Microsoft YaHei", "SimSun"]
const HEIGHT_LIMIT := 1.08      ## 行高最多允许超出格高的比例（超一点没关系，字墨在行内）

var _lines: PackedStringArray = PackedStringArray()
var _cell: Vector2 = Vector2.ONE
var _origin: Vector2 = Vector2.ZERO
var _font: Font = null
var _size_px: int = 16
var _advance: float = 0.0


## [param cell] 一个字符格的画布尺寸；[param origin] 字符画左上角（画布坐标）。
func setup(lines: PackedStringArray, cell: Vector2, origin: Vector2) -> void:
	_lines = lines
	_cell = cell
	_origin = origin
	_font = _make_font()
	_fit_font()
	queue_redraw()


func _make_font() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(FONT_NAMES)
	sf.allow_system_fallback = true
	return sf


## 字号 = 格宽 / 步进比；再用行高兜上限（防止字比格子还高，串到相邻行）
func _fit_font() -> void:
	if _font == null or _cell.x <= 0.0 or _cell.y <= 0.0:
		return
	var ref := 64
	var adv_ratio := _font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, ref).x / float(ref)
	var h_ratio := float(_font.get_height(ref)) / float(ref)
	_size_px = maxi(4, int(roundf(_cell.x / maxf(0.01, adv_ratio))))
	var by_h := maxi(4, int(floorf(_cell.y * HEIGHT_LIMIT / maxf(0.01, h_ratio))))
	_size_px = mini(_size_px, by_h)
	_advance = _font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, _size_px).x


func _draw() -> void:
	if _font == null or _lines.is_empty():
		return
	# 行内垂直居中：终端把字形摆在格子的垂直中线上，这里照做
	var line_h := float(_font.get_height(_size_px))
	var dy := maxf(0.0, (_cell.y - line_h) * 0.5) + float(_font.get_ascent(_size_px))
	# 列内水平居中：步进未必正好等于格宽，差的那点均分到左右
	var dx := (_cell.x - _advance) * 0.5
	for r in _lines.size():
		var line := _lines[r]
		var y := _origin.y + float(r) * _cell.y + dy
		# 用「笔」推进而不是「列号」：中文占两格，按列号算整行会越走越偏
		var pen := 0
		for c in line.length():
			var ch := line[c]
			if ch == " ":
				pen += 1
				continue
			# 必须用 draw_string：draw_char 不做缺字回退，中文字形不在等宽字体里就整行画不出来
			# （实测字幕只画出了 "AI"）。单字调用仍然保持逐格定位。
			draw_string(_font, Vector2(_origin.x + float(pen) * _cell.x + dx, y),
					ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _size_px, Color.WHITE)
			# 中文在终端里占两格，这里必须同样按两格推进，否则整行会越来越偏
			pen += 2 if _is_wide(ch) else 1


## 全角判定（与 IntroScript._is_wide 同一套区间，两处必须一致）
static func _is_wide(ch: String) -> bool:
	var cp := ch.unicode_at(0)
	return (cp >= 0x2E80 and cp <= 0xA4CF) \
		or (cp >= 0xAC00 and cp <= 0xD7A3) \
		or (cp >= 0xF900 and cp <= 0xFAFF) \
		or (cp >= 0xFE30 and cp <= 0xFE6F) \
		or (cp >= 0xFF00 and cp <= 0xFF60) \
		or (cp >= 0xFFE0 and cp <= 0xFFE6)
