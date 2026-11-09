class_name CharacterSelectScreen
extends Control
## 选角界面（2026-11-09 主人手绘稿 图2 + 同日二次修订）：
##   · **背景**：当前角色的大立绘铺满全屏（暗化处理，避免抢前景）
##   · 左侧一个竖长选框，显示该角色小立绘——**切换时直接换图，不播转场**
##   · 框下方：← 圆点圆点圆点圆点 →（左右切换箭头 + 4 个位置点）
##   · 右下角：UI「开始游戏」
##
## 修订记录：
##   2026-11-09 一轮：框内用 RippleSwapPortrait 播一人一款转场
##   2026-11-09 二轮：主人明确「选框不用转场，直接切换；后面的背景立绘用大立绘」
##                    → 选框换回 TextureRect 即时切换，转场只保留给背景换图（淡入淡出）
##
## 布局基准 1600×900。

signal started(ai_id: String)
signal back_requested

# ── 布局常量（按主人图 2 的比例落到 1600×900）──
const FRAME_POS := Vector2(78.0, 128.0)      ## 选框左上角
const FRAME_W := 262.0
const FRAME_H := 566.0
const DOTS_Y := 726.0                        ## 圆点行 y
const ARROW_GAP := 34.0                      ## 箭头与圆点群的水平间距
const DOT_R := 5.0
const DOT_GAP := 26.0
const START_BTN_POS := Vector2(1318.0, 806.0)
const START_BTN_SIZE := Vector2(228.0, 62.0)

## 背景大立绘的暗化量：0=原图，越高越暗。让前景文字/选框清晰可读
const BG_DIM := 0.52
## 背景换图的淡入淡出时长（不是角色转场，只是避免生硬跳变）
const BG_FADE := 0.22

var _ais: Array[AiData] = []
var _small_texs: Array[Texture2D] = []       ## 选框用的小立绘
var _big_texs: Array[Texture2D] = []         ## 铺满全屏的大立绘
var _idx := 0
var _busy := false

var _bg_layer: TextureRect = null            ## 背景大立绘（底层）
var _bg_dim: ColorRect = null                ## 背景暗化层
var _frame: PanelContainer = null
var _thumb: TextureRect = null               ## 选框内小立绘（直接切图）
var _name_lbl: Label = null
var _family_lbl: Label = null
var _intro_lbl: Label = null
var _dots: Array[Panel] = []
var _left_btn: Button = null
var _right_btn: Button = null
var _start_btn: Button = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _ais.is_empty():
		setup(AiPool.all_ais())
	_build()


## 注入角色（locked 标记已由 AiPool 设好）
func setup(ais: Array[AiData]) -> void:
	_ais = ais
	_small_texs.clear()
	_big_texs.clear()
	for a in _ais:
		_small_texs.append(_load_tex(a.portrait_path))
		# 大立绘优先用 bust_path（主人后续提供的全屏大图），没有就退回小立绘放大
		var big := _load_tex(a.bust_path)
		if big == null:
			big = _small_texs[_small_texs.size() - 1]
		_big_texs.append(big)
	if is_inside_tree():
		_build()


func _load_tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func current_id() -> String:
	if _ais.is_empty():
		return "deepdeek"
	return _ais[_idx].id


func current_index() -> int:
	return _idx


func _build() -> void:
	if _ais.is_empty():
		return
	_build_background()
	_build_frame()
	_build_dots()
	_build_start()
	_refresh()


# ── 背景：当前角色大立绘铺满全屏 ──
func _build_background() -> void:
	_bg_layer = TextureRect.new()
	_bg_layer.name = "BigPortraitBg"
	_bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# 铺满全屏且不变形：等比放大到覆盖整个画布，超出部分裁掉
	_bg_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_layer)

	# 暗化 + 左侧渐深：保证选框和文字在上面读得清
	_bg_dim = ColorRect.new()
	_bg_dim.name = "BgDim"
	_bg_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_dim.color = Color(0.01, 0.015, 0.03, BG_DIM)
	_bg_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_dim)


# ── 左侧选框 ──
func _build_frame() -> void:
	_frame = PanelContainer.new()
	_frame.name = "PortraitFrame"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.045, 0.08, 0.72)
	sb.border_color = Color(0.42, 0.56, 0.78)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	_frame.add_theme_stylebox_override("panel", sb)
	_frame.position = FRAME_POS
	_frame.size = Vector2(FRAME_W, FRAME_H)
	_frame.clip_contents = true
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	# 选框内：普通 TextureRect，切换时**直接换 texture**（不播转场）
	_thumb = TextureRect.new()
	_thumb.name = "Thumb"
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_thumb)

	# 角色名 / 家族 / 一句话（框右侧）
	_name_lbl = UiKit.label("", 40, Color(0.95, 0.98, 1.0))
	_name_lbl.position = Vector2(FRAME_POS.x + FRAME_W + 54.0, FRAME_POS.y + 24.0)
	add_child(_name_lbl)

	_family_lbl = UiKit.dim("", 20, Color(0.62, 0.84, 1.0))
	_family_lbl.position = Vector2(FRAME_POS.x + FRAME_W + 56.0, FRAME_POS.y + 80.0)
	add_child(_family_lbl)

	_intro_lbl = UiKit.dim("", 18, Color(0.68, 0.78, 0.9))
	_intro_lbl.position = Vector2(FRAME_POS.x + FRAME_W + 56.0, FRAME_POS.y + 118.0)
	_intro_lbl.size = Vector2(560, 60)
	_intro_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_intro_lbl)


# ── 圆点 + 左右箭头 ──
func _build_dots() -> void:
	var n := _ais.size()
	var total_w := ARROW_GAP * 2.0 + DOT_GAP * float(n - 1)
	var x0 := FRAME_POS.x + (FRAME_W - total_w) * 0.5

	var row := Control.new()
	row.name = "DotRow"
	row.position = Vector2(x0, DOTS_Y)
	row.size = Vector2(total_w, 26.0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_left_btn = _make_arrow("←")
	_left_btn.position = Vector2.ZERO
	_left_btn.pressed.connect(func() -> void: _step(-1))
	row.add_child(_left_btn)

	for i in n:
		var d := Panel.new()
		d.name = "Dot%d" % i
		d.position = Vector2(ARROW_GAP + DOT_GAP * float(i) - DOT_R, 13.0 - DOT_R)
		d.size = Vector2(DOT_R * 2.0, DOT_R * 2.0)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dots.append(d)
		row.add_child(d)

	_right_btn = _make_arrow("→")
	_right_btn.position = Vector2(total_w - 18.0, 0.0)
	_right_btn.pressed.connect(func() -> void: _step(1))
	row.add_child(_right_btn)


func _make_arrow(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(18.0, 26.0)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(0.78, 0.88, 0.98))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.45, 0.72, 1.0))
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	return b


func _refresh_dots() -> void:
	for i in _dots.size():
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.88, 0.96, 1.0) if i == _idx else Color(0.34, 0.44, 0.60)
		sb.set_corner_radius_all(int(DOT_R))
		_dots[i].add_theme_stylebox_override("panel", sb)


# ── 右下角「开始游戏」──
func _build_start() -> void:
	_start_btn = UiKit.accent_button("开始游戏", 24)
	_start_btn.name = "StartButton"
	_start_btn.position = START_BTN_POS
	_start_btn.size = START_BTN_SIZE
	_start_btn.pressed.connect(func() -> void: started.emit(current_id()))
	add_child(_start_btn)


## 刷新当前角色：选框**直接换图**，背景做一次短淡入（避免生硬跳变）
func _refresh(animate_bg: bool = false) -> void:
	if _ais.is_empty():
		return
	var ai := _ais[_idx]
	_name_lbl.text = ai.display_name
	_family_lbl.text = ai.family
	_intro_lbl.text = ai.intro_line
	_refresh_dots()
	if _thumb != null:
		_thumb.texture = _small_texs[_idx]
	if _bg_layer != null:
		_bg_layer.texture = _big_texs[_idx]
		if animate_bg:
			_bg_layer.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(_bg_layer, "modulate:a", 1.0, BG_FADE) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 左右切换：选框直接换，背景淡入新图
func _step(dir: int) -> void:
	if _busy or _ais.is_empty():
		return
	var next := wrapi(_idx + dir, 0, _ais.size())
	if next == _idx:
		return
	_idx = next
	_refresh(true)


## 供测试/调试：直接切到第 i 位（不播转场）
func select_by_index(i: int) -> void:
	if i < 0 or i >= _ais.size() or i == _idx:
		return
	_idx = i
	_refresh(true)
