class_name TutorialOverlay
extends Control
## 新手引导覆盖层（2026-11-18 主人要求）：
##   ① 全局半透明变暗，**只有被指的那个控件不暗**（在遮罩上挖一个洞）
##   ② 洞里/旁边弹一个提示框，写明这一步干什么
##   ③ 完成后调 next_step()；三步走完自毁
##
## 挖洞做法：不用 shader，直接画 4 块矩形围住目标区域（上下左右），
## 这样目标区域天然保持原亮度，且边框能精确贴合。比 shader 版好调、无兼容问题。
##
## 用法：
##   var t := TutorialOverlay.new()
##   add_child(t)
##   t.start([{rect=..., text="..."}...])

signal finished

const DIM := Color(0.02, 0.03, 0.06, 0.72)
const HOLE_PAD := 8.0          ## 挖洞比目标大一圈，留呼吸
const BORDER := Color(1.0, 0.85, 0.35, 0.95)
const TIP_BG := Color(0.06, 0.09, 0.15, 0.97)
const TIP_LINE := Color(0.55, 0.85, 1.0, 0.95)
const TIP_W := 520.0

var _steps: Array = []
var _idx := -1
var _hole := Rect2()
var _dims: Array[ColorRect] = []
var _tip: PanelContainer = null
var _tip_label: Label = null
var _hint: Label = null
var _border: Control = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     ## 吃掉点击，防止误触后面的界面
	z_index = 900
	# 四块遮罩：上 / 下 / 左 / 右（围绕洞）
	for i in 4:
		var r := ColorRect.new()
		r.color = DIM
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		_dims.append(r)
	# 洞的描边框
	_border = Control.new()
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border.draw.connect(_draw_border)
	add_child(_border)
	# 提示框
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = TIP_BG
	sb.border_color = TIP_LINE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_tip.add_theme_stylebox_override("panel", sb)
	_tip.custom_minimum_size = Vector2(TIP_W, 0)
	add_child(_tip)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_tip.add_child(v)
	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(TIP_W - 32, 0)
	_tip_label.add_theme_font_size_override("font_size", 19)
	_tip_label.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0))
	v.add_child(_tip_label)
	_hint = Label.new()
	_hint.text = "（点击任意处继续）"
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.7, 0.88))
	v.add_child(_hint)
	visible = false


## steps: [{rect: Rect2（屏幕坐标）, text: String}]
func start(steps: Array) -> void:
	_steps = steps
	_idx = -1
	visible = true
	next_step()


## 进入下一步；走完则 finish()
func next_step() -> void:
	_idx += 1
	if _idx >= _steps.size():
		finish()
		return
	var st: Dictionary = _steps[_idx]
	_hole = (st.get("rect", Rect2()) as Rect2).grow(HOLE_PAD)
	_tip_label.text = String(st.get("text", ""))
	_layout()


func finish() -> void:
	visible = false
	finished.emit()
	queue_free()


func _layout() -> void:
	var sz := size
	if sz.x <= 0.0 or sz.y <= 0.0:
		sz = get_viewport_rect().size
	var h := _hole
	# 四块：上（整宽）/下（整宽）/左（洞高）/右（洞高）
	_dims[0].position = Vector2.ZERO
	_dims[0].size = Vector2(sz.x, maxf(0.0, h.position.y))
	_dims[1].position = Vector2(0.0, h.end.y)
	_dims[1].size = Vector2(sz.x, maxf(0.0, sz.y - h.end.y))
	_dims[2].position = Vector2(0.0, h.position.y)
	_dims[2].size = Vector2(maxf(0.0, h.position.x), maxf(0.0, h.size.y))
	_dims[3].position = Vector2(h.end.x, h.position.y)
	_dims[3].size = Vector2(maxf(0.0, sz.x - h.end.x), maxf(0.0, h.size.y))
	_border.position = Vector2.ZERO
	_border.size = sz
	_border.queue_redraw()
	# 提示框定位：优先放在**离洞较远**的一侧，且必须完全避开洞（不遮挡目标）
	_tip.size = Vector2(TIP_W, 0)
	_tip.reset_size()
	var tw := TIP_W
	var th := _tip.get_combined_minimum_size().y
	var tx := clampf(h.get_center().x - tw * 0.5, 24.0, maxf(24.0, sz.x - tw - 24.0))
	# 洞下方的可用空间 vs 上方
	var below := sz.y - h.end.y - 24.0
	var above := h.position.y - 24.0
	var ty: float
	if below >= th + 12.0:
		ty = h.end.y + 20.0            # 放下面，不遮挡
	elif above >= th + 12.0:
		ty = h.position.y - 20.0 - th  # 放上面
	else:
		# 上下都放不下（洞很高）：放右侧或左侧
		var right := sz.x - h.end.x - 24.0
		if right >= tw + 12.0:
			tx = h.end.x + 20.0
			ty = clampf(h.get_center().y - th * 0.5, 20.0, sz.y - th - 20.0)
		else:
			tx = maxf(12.0, h.position.x - 20.0 - tw)
			ty = clampf(h.get_center().y - th * 0.5, 20.0, sz.y - th - 20.0)
	_tip.position = Vector2(tx, ty)
	_tip.size = Vector2(tw, th)


func _draw_border() -> void:
	_border.draw_rect(_hole, BORDER, false, 2.0)
	# 四角加粗，强调"就是这个"
	var L := 18.0
	var c: Color = BORDER
	var a := _hole.position
	var b := _hole.end
	_border.draw_line(a, a + Vector2(L, 0), c, 3.0)
	_border.draw_line(a, a + Vector2(0, L), c, 3.0)
	_border.draw_line(Vector2(b.x, a.y), Vector2(b.x - L, a.y), c, 3.0)
	_border.draw_line(Vector2(b.x, a.y), Vector2(b.x, a.y + L), c, 3.0)
	_border.draw_line(Vector2(a.x, b.y), Vector2(a.x + L, b.y), c, 3.0)
	_border.draw_line(Vector2(a.x, b.y), Vector2(a.x, b.y - L), c, 3.0)
	_border.draw_line(b, b - Vector2(L, 0), c, 3.0)
	_border.draw_line(b, b - Vector2(0, L), c, 3.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			accept_event()
			next_step()
