class_name PixelSlot
extends Control
## 像素插槽框：虚线边框 + 角标序号。
##
## 空槽不该是五个抢戏的大方框——它应该是"等待放入"的提示，
## 所以用比正文更暗的虚线，角标小字，视觉权重压到最低（§2.4 强调靠去强调别人）。

@export var index: int = 1
@export var occupied: bool = false
@export var line_color: Color = UiKit.LINE
@export var fill_color: Color = UiKit.PANEL
@export var dash: int = 6
@export var gap: int = 4
@export var thick: int = 2


func set_occupied(v: bool) -> void:
	if occupied != v:
		occupied = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), fill_color)
	if occupied:
		# 有卡时框线退到背景里，只留一点点存在感
		draw_rect(Rect2(Vector2.ZERO, size), line_color, false, 1.0)
	else:
		_dashed_rect(Rect2(Vector2(thick, thick), size - Vector2(thick, thick) * 2.0))
		# 角标序号
		var tag := "%02d" % index
		draw_string(font, Vector2(thick + 4, thick + 14), tag,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.LINE_HI)


func _dashed_rect(r: Rect2) -> void:
	_dashed_line(r.position, Vector2(r.end.x - r.position.x, 0))
	_dashed_line(Vector2(r.end.x, r.position.y), Vector2(0, r.end.y - r.position.y))
	_dashed_line(r.end, Vector2(-(r.end.x - r.position.x), 0))
	_dashed_line(Vector2(r.position.x, r.end.y), Vector2(0, -(r.end.y - r.position.y)))


func _dashed_line(from: Vector2, delta: Vector2) -> void:
	var len := delta.length()
	if len <= 0.0:
		return
	var dir := delta / len
	var d := 0.0
	while d < len:
		var a := from + dir * d
		var b := from + dir * minf(d + float(dash), len)
		draw_line(a, b, line_color, thick)
		d += float(dash + gap)
