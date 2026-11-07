class_name TerminalRain
extends Control
## 终端代码雨背景（2026-11-07 主人要求）：一串串终端符号（@ # / \ 等），
## 像雨滴一样从天上落下来——跟终端画一个味。当面板/屏幕的背景层用。
##
## 用法：塞进任意 Control 里即可（PanelContainer 会自动铺满）；
## 自身 mouse_filter = IGNORE，不吃输入；隐藏时不跑动画不重绘。
## 注意：ult_cinematic.gd 里另有一个内部类 CodeRain（Label 列雨，终结技演出用），
## 两者的字形/画法不同，别混用同名。

const GLYPHS := "@#/\\|+-*=<>[]{}()!;:^~%&$_"
const HEAD_COLOR := Color(0.72, 0.98, 1.0, 0.95)  ## 雨头：亮青
const TRAIL_COLOR := Color(0.42, 0.82, 0.98)      ## 雨尾：暗青（按距离渐隐）
const COLUMN_W := 14.0                            ## 列宽 ≈ 一个字符宽
const LINE_H := 18.0                              ## 字符行高
const FONT_SIZE := 13
## 雨尾透明度上限（压低保证前景文字可读）
const TRAIL_ALPHA := 0.5

var _cols: Array = []            ## 每列：{x, head, speed, len, glyphs}
var _font: Font = null
var _acc := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_rng.randomize()
	_font = PixelTheme.font()
	resized.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	_cols.clear()
	var n := int(size.x / COLUMN_W) + 1
	for i in n:
		# 初始雨头撒满全高（含屏内），开场就是「正在下雨」而不是等雨来
		_cols.append(_make_col(i * COLUMN_W,
				_rng.randf_range(-size.y * 0.5, size.y * 0.6)))


func _make_col(x: float, head: float) -> Dictionary:
	var len_v := _rng.randi_range(8, 24)
	return {
		"x": x,
		"head": head,
		"speed": _rng.randf_range(90.0, 230.0),
		"len": len_v,
		"glyphs": _rand_glyphs(len_v),
	}


func _rand_glyphs(n: int) -> Array:
	var out := []
	for i in n:
		out.append(GLYPHS[_rng.randi() % GLYPHS.length()])
	return out


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_acc += delta
	if _acc < 1.0 / 30.0:      ## 30fps 足够雨的感觉，省电
		return
	var dt := _acc
	_acc = 0.0
	for c in _cols:
		c["head"] += float(c["speed"]) * dt
		## 下落途中随机变几个字符，保持「活的终端」感
		if _rng.randf() < 0.3:
			var g: Array = c["glyphs"]
			g[_rng.randi() % g.size()] = GLYPHS[_rng.randi() % GLYPHS.length()]
		if float(c["head"]) - float(c["len"]) * LINE_H > size.y:
			var nc := _make_col(float(c["x"]), -_rng.randf_range(0.0, 240.0))
			c["speed"] = nc["speed"]
			c["len"] = nc["len"]
			c["glyphs"] = nc["glyphs"]
			c["head"] = nc["head"]
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	for c in _cols:
		var x := float(c["x"])
		var head := float(c["head"])
		var n := int(c["len"])
		var glyphs: Array = c["glyphs"]
		for i in n:
			var gy := head - float(i) * LINE_H
			if gy < -LINE_H or gy > size.y + LINE_H:
				continue
			var g := String(glyphs[i % glyphs.size()])
			if i == 0:
				draw_string(_font, Vector2(x, gy), g,
						HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, HEAD_COLOR)
			else:
				var col := TRAIL_COLOR
				col.a = TRAIL_ALPHA * (1.0 - float(i) / float(n))
				draw_string(_font, Vector2(x, gy), g,
						HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
