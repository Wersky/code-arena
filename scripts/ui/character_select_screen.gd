class_name CharacterSelectScreen
extends Control
## 选角界面（2026-11-09 主人手绘稿 图2 + 三轮修订）：
##   · **背景**：当前角色的大立绘铺满全屏，**不加任何暗纱**（主人要求保持原图明度）
##   · 底部居中：← 圆点圆点圆点圆点 →（左右箭头 + 4 个位置点）
##   · 右下角：UI「开始游戏」
##   · 切换时用该角色专属转场播到它（一人一款，见 TRANSITION_STYLE）
##
## 修订记录：
##   一轮：框内小立绘用 RippleSwapPortrait 播一人一款转场
##   二轮：选框不用转场直接切；背景用大立绘
##   三轮（2026-11-09）：去掉左上角介绍文字（角色名/家族/一句话）、去掉左侧小立绘选框、
##                      去掉背景暗纱；圆点与箭头移到底部水平居中
##   四轮（2026-11-09）：**背景换图用一人一款转场**（水波/折扇/龙鳞/乱斩），
##                      素材已换成 1600x900 与画布同比，转场控件可直接 UV 采样
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
## 一人一款转场：下标与 AiPool.all_ais() 顺序一致
##   DeepDeek 水波 / Kweno 折扇 / ChatPPT 龙鳞 / Grock 乱斩
const TRANSITION_STYLE := [
	RippleSwapPortrait.Style.RIPPLE,
	RippleSwapPortrait.Style.FAN,
	RippleSwapPortrait.Style.HEX,
	RippleSwapPortrait.Style.SLASH,
]
## 转场时长从 GameSettings 按风格单独取（左下角调参器可调、跨启动记住）
const STYLE_KEYS := ["ripple", "fan", "hex", "slash"]   ## 与 TRANSITION_STYLE 一一对应

var _ais: Array[AiData] = []
var _big_texs: Array[Texture2D] = []         ## 铺满全屏的大立绘
var _idx := 0

var _bg_layer: RippleSwapPortrait = null     ## 背景大立绘（带一人一款转场）
var _swapping := false

## 左下角调参器（Notes：只在选角界面出现，调整即时生效并落盘）
var _tuner_panel: PanelContainer = null
var _tuner_labels: Dictionary = {}           ## style_key -> Label（显示秒数）


## 某位角色的转场时长（秒）：优先用主人调好的值
func _swap_time_for(idx: int) -> float:
	var key: String = String(STYLE_KEYS[idx % STYLE_KEYS.size()])
	return GameSettings.select_time_for(key)
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
	_build_tuner()
	_refresh()


# ── 背景：当前角色大立绘铺满全屏（无暗纱，带一人一款转场）──
func _build_background() -> void:
	_bg_layer = RippleSwapPortrait.new()
	_bg_layer.name = "BigPortraitBg"
	_bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_layer.swap_time = _swap_time_for(_idx)
	_bg_layer.style = int(TRANSITION_STYLE[_idx % TRANSITION_STYLE.size()])
	_bg_layer.swap_finished.connect(func() -> void: _swapping = false)
	add_child(_bg_layer)
	_bg_layer.set_portrait(_big_texs[_idx])


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


# ── 左下角：转场调速器（2026-11-09 主人要求，数值落盘跨启动记住）──
const TUNER_NAMES := ["水波", "折扇", "龙鳞", "乱斩"]

func _build_tuner() -> void:
	_tuner_panel = PanelContainer.new()
	_tuner_panel.name = "SwapTuner"
	var sb := StyleBoxFlat.new()
	# 半透明深色底：立绘再亮也读得清，但不会挡住画面
	sb.bg_color = Color(0.02, 0.03, 0.06, 0.80)
	sb.border_color = Color(0.28, 0.42, 0.62, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	_tuner_panel.add_theme_stylebox_override("panel", sb)
	_tuner_panel.position = Vector2(18.0, 690.0)
	_tuner_panel.custom_minimum_size = Vector2(300.0, 0.0)
	add_child(_tuner_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_tuner_panel.add_child(v)

	var title := UiKit.dim("转场速度（秒，拖动即存）", 12, Color(0.68, 0.80, 0.94))
	v.add_child(title)

	for i in STYLE_KEYS.size():
		var key := String(STYLE_KEYS[i])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		v.add_child(row)

		var nm := UiKit.dim(String(TUNER_NAMES[i]), 12, Color(0.85, 0.92, 1.0))
		nm.custom_minimum_size = Vector2(34.0, 0.0)
		row.add_child(nm)

		var slider := HSlider.new()
		slider.min_value = float(GameSettings.SELECT_SWAP_MIN)
		slider.max_value = float(GameSettings.SELECT_SWAP_MAX)
		slider.step = 0.01
		slider.value = float(GameSettings.select_time_for(key))
		slider.custom_minimum_size = Vector2(180.0, 14.0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)

		var val_lbl := UiKit.dim("%.2f" % GameSettings.select_time_for(key), 12,
				Color(0.60, 0.88, 1.0))
		val_lbl.custom_minimum_size = Vector2(34.0, 0.0)
		row.add_child(val_lbl)
		_tuner_labels[key] = val_lbl

		# 拖动：即时改数值 + 落盘（主人要求「以我填的数值为准」）
		slider.value_changed.connect(func(v2: float) -> void:
			GameSettings.set_select_time(key, v2)
			if _tuner_labels.has(key):
				(_tuner_labels[key] as Label).text = "%.2f" % v2)


# ── 右下角「开始游戏」──
func _build_start() -> void:
	_start_btn = UiKit.accent_button("开始游戏", 24)
	_start_btn.name = "StartButton"
	_start_btn.position = START_BTN_POS
	_start_btn.size = START_BTN_SIZE
	_start_btn.pressed.connect(func() -> void: started.emit(current_id()))
	add_child(_start_btn)


## 刷新指示器（背景换图由 _swap_to_character 负责）
func _refresh(animate_bg: bool = false) -> void:
	if _ais.is_empty():
		return
	_refresh_dots()
	if _bg_layer != null and not animate_bg:
		_bg_layer.set_portrait(_big_texs[_idx])


## 切到第 next 位：用**目标角色**的专属转场播过去
func _swap_to_character(next: int) -> void:
	if next < 0 or next >= _ais.size() or next == _idx or _swapping:
		return
	_idx = next
	_refresh_dots()          # 指示器立即跟随（转场是视觉层，状态不该滞后）
	if _bg_layer == null:
		return
	_swapping = true
	# 风格取**目标角色**的专属款：切过去时呈现的是它
	_bg_layer.style = int(TRANSITION_STYLE[next % TRANSITION_STYLE.size()])
	_bg_layer.swap_time = _swap_time_for(next)
	_bg_layer.swap_to(_big_texs[next])


## 左右切换
func _step(dir: int) -> void:
	if _ais.is_empty() or _swapping:
		return
	_swap_to_character(wrapi(_idx + dir, 0, _ais.size()))


## 供测试/调试：直接切到第 i 位（走转场）
func select_by_index(i: int) -> void:
	_swap_to_character(i)
