class_name CharacterSelectScreen
extends Control
## 选角界面（2026-11-09 主人手绘稿 图2 + 三轮修订）：
##   · **背景**：当前角色的大立绘铺满全屏，**不加任何暗纱**（主人要求保持原图明度）
##   · 底部居中：← 圆点圆点圆点圆点 →（左右箭头 + 4 个位置点）
##   · 右下角：UI「开始游戏」
##   · 切换时背景直接换图（短淡入），无转场
##
## 修订记录：
##   一轮：框内小立绘用 RippleSwapPortrait 播一人一款转场
##   二轮：选框不用转场直接切；背景用大立绘
##   三轮（2026-11-09）：去掉左上角介绍文字（角色名/家族/一句话）、去掉左侧小立绘选框、
##                      去掉背景暗纱；圆点与箭头移到底部水平居中
##
## 布局基准 1600×900。

signal started(ai_id: String)
signal back_requested

# ── 布局常量 ──
const DOTS_Y := 800.0                        ## 圆点行 y（底部居中，留出下边距）
const ARROW_GAP := 58.0                      ## 箭头与圆点群的水平间距
const DOT_R := 5.0
const DOT_GAP := 30.0
const START_BTN_POS := Vector2(1330.0, 800.0)
const START_BTN_SIZE := Vector2(228.0, 62.0)
## 背景换图的淡入淡出时长（不是角色转场，只是避免生硬跳变）
const BG_FADE := 0.22

var _ais: Array[AiData] = []
var _big_texs: Array[Texture2D] = []         ## 铺满全屏的大立绘
var _idx := 0

var _bg_layer: TextureRect = null            ## 背景大立绘（唯一视觉主体）
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
	_big_texs.clear()
	for a in _ais:
		# 大立绘优先用 bust_path（全屏大图），没有就退回小立绘
		var big := _load_tex(a.bust_path)
		if big == null:
			big = _load_tex(a.portrait_path)
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
	_build_dots()
	_build_start()
	_refresh()


# ── 背景：当前角色大立绘铺满全屏（无暗纱）──
func _build_background() -> void:
	_bg_layer = TextureRect.new()
	_bg_layer.name = "BigPortraitBg"
	_bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# 铺满全屏且不变形：等比放大到覆盖整个画布，超出部分裁掉
	_bg_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_layer)


# ── 底部居中：箭头 + 圆点 ──
func _build_dots() -> void:
	var n := _ais.size()
	var total_w := ARROW_GAP * 2.0 + DOT_GAP * float(maxi(n - 1, 0))
	# 水平居中：整组的中点放在屏幕中心
	var x0 := (1600.0 - total_w) * 0.5

	var row := Control.new()
	row.name = "DotRow"
	row.position = Vector2(x0, DOTS_Y)
	row.size = Vector2(total_w, 30.0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	# 箭头对齐到「圆点群两侧的空隙中心」，不是贴着行边缘（否则左右不对称）
	_left_btn = _make_arrow("←")
	_left_btn.position = Vector2((ARROW_GAP - _left_btn.size.x) * 0.5, 0.0)
	_left_btn.pressed.connect(func() -> void: _step(-1))
	row.add_child(_left_btn)

	for i in n:
		var d := Panel.new()
		d.name = "Dot%d" % i
		d.position = Vector2(ARROW_GAP + DOT_GAP * float(i) - DOT_R, 15.0 - DOT_R)
		d.size = Vector2(DOT_R * 2.0, DOT_R * 2.0)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dots.append(d)
		row.add_child(d)

	_right_btn = _make_arrow("→")
	_right_btn.position = Vector2(
			total_w - ARROW_GAP + (ARROW_GAP - _right_btn.size.x) * 0.5, 0.0)
	_right_btn.pressed.connect(func() -> void: _step(1))
	row.add_child(_right_btn)


func _make_arrow(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(20.0, 30.0)
	b.add_theme_font_size_override("font_size", 24)
	# 大立绘很亮，箭头加一层深色描边式投影保证可读
	b.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.55, 0.78, 1.0))
	b.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	b.add_theme_constant_override("outline_size", 6)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	return b


func _refresh_dots() -> void:
	for i in _dots.size():
		var sb := StyleBoxFlat.new()
		if i == _idx:
			sb.bg_color = Color(0.92, 0.97, 1.0)
			sb.set_corner_radius_all(int(DOT_R))
			# 选中点加一圈软描边，在亮背景上也分得清
			sb.border_color = Color(0.0, 0.0, 0.0, 0.45)
			sb.set_border_width_all(2)
		else:
			sb.bg_color = Color(0.42, 0.50, 0.62, 0.85)
			sb.set_corner_radius_all(int(DOT_R))
			sb.border_color = Color(0.0, 0.0, 0.0, 0.35)
			sb.set_border_width_all(1)
		_dots[i].add_theme_stylebox_override("panel", sb)


# ── 右下角「开始游戏」──
func _build_start() -> void:
	_start_btn = UiKit.accent_button("开始游戏", 24)
	_start_btn.name = "StartButton"
	_start_btn.position = START_BTN_POS
	_start_btn.size = START_BTN_SIZE
	_start_btn.pressed.connect(func() -> void: started.emit(current_id()))
	add_child(_start_btn)


## 刷新当前角色：背景直接换图（短淡入避免生硬跳变）
func _refresh(animate_bg: bool = false) -> void:
	if _ais.is_empty():
		return
	_refresh_dots()
	if _bg_layer != null:
		_bg_layer.texture = _big_texs[_idx]
		if animate_bg:
			_bg_layer.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(_bg_layer, "modulate:a", 1.0, BG_FADE) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 左右切换：背景直接换，指示器立即跟随
func _step(dir: int) -> void:
	if _ais.is_empty():
		return
	var next := wrapi(_idx + dir, 0, _ais.size())
	if next == _idx:
		return
	_idx = next
	_refresh(true)


## 供测试/调试：直接切到第 i 位
func select_by_index(i: int) -> void:
	if i < 0 or i >= _ais.size() or i == _idx:
		return
	_idx = i
	_refresh(true)
