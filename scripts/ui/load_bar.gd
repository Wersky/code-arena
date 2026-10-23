class_name LoadBar
extends Control
## 生图进度条：AI 生成的 track 框 + 引擎绘制的填充（渐变 + 亮边 + 顶部高光）。
##
## 资产管线：pictures/gen.py（pixel-art 风格，16:9）→ tools/make_loadbar_asset.py
## （抠棋盘格假透明 → 最大连通块 → ÷3 NEAREST → 内槽量测）。
## 资产 360x40，游戏内 ×2 整数放大 = 720x80（资产规矩：×2 显示不糊）。

const TRACK_PATH := "res://assets/art/ui/loadbar-track.png"
## 内槽在资产坐标系里的矩形（make_loadbar_asset.py 量测 + 目检校准）
const SLOT := Rect2(20, 13, 320, 14)
const C_FILL_L := Color("#1b64d8")   ## 填充左端：深蓝
const C_FILL_R := Color("#37d8f0")   ## 填充右端：青
const C_EDGE := Color("#d8fbff")     ## 填充前沿亮线：淡薄荷
const C_SHINE := Color(1, 1, 1, 0.22)

var value := 0.0:                    ## 0..1
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
var _tex: Texture2D = null


func _init() -> void:
	_tex = load(TRACK_PATH)
	var sz := Vector2(_tex.get_width(), _tex.get_height()) * 2.0
	custom_minimum_size = sz
	size = sz
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_value(v: float) -> void:
	value = v


func _draw() -> void:
	var s := 2.0
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(_tex.get_width(), _tex.get_height()) * s), false)
	var slot := Rect2(SLOT.position * s, SLOT.size * s)
	var fw := floorf(slot.size.x * value)
	if fw < 1.0:
		return
	var fill := Rect2(slot.position, Vector2(fw, slot.size.y))
	# 填充本体：左深蓝 → 右青 的四顶点渐变
	draw_polygon(
		PackedVector2Array([fill.position, fill.position + Vector2(fill.size.x, 0),
				fill.end, fill.position + Vector2(0, fill.size.y)]),
		PackedColorArray([C_FILL_L, C_FILL_R, C_FILL_R, C_FILL_L]))
	# 顶部高光条
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, 2)), C_SHINE)
	# 填充前沿：2px 亮线 + 出槽 1px 的光晕头
	draw_rect(Rect2(Vector2(fill.end.x - 2.0, slot.position.y), Vector2(2.0, slot.size.y)), C_EDGE)
	draw_rect(Rect2(Vector2(fill.end.x - 1.0, slot.position.y + 2.0), Vector2(1.0, slot.size.y - 4.0)),
			Color(C_EDGE.r, C_EDGE.g, C_EDGE.b, 0.45))
