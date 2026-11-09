class_name CharacterSelectScreen
extends Control
## 选角界面（2026-11-09 主人手绘稿 图2）：
##   · 左侧一个竖长立绘框，显示 4 位角色之一
##   · 框下方：← 圆点圆点圆点圆点 →（左右切换箭头 + 4 个位置点）
##   · 右下角：UI「开始游戏」
##   · 左右切换时用**该角色专属**的转场动画（一人一款，见 TRANSITION_STYLE）
##
## 背景：全屏马赛克淡入（由 main 的 ScreenMosaic 负责），本界面只画自己的内容。
## 布局基准 1600×900。

signal started(ai_id: String)
signal back_requested

## 一人一款转场：下标与 AiPool.all_ais() 一致
##   DeepDeek 水波 / Kweno 折扇 / ChatPPT 龙鳞 / Grock 乱斩
const TRANSITION_STYLE := [
	RippleSwapPortrait.Style.RIPPLE,
	RippleSwapPortrait.Style.FAN,
	RippleSwapPortrait.Style.HEX,
	RippleSwapPortrait.Style.SLASH,
]

# ── 布局常量（按主人图 2 的比例落到 1600×900）──
const FRAME_POS := Vector2(78.0, 128.0)      ## 立绘框左上角
const FRAME_W := 262.0
const FRAME_H := 566.0
const DOTS_Y := 726.0                        ## 圆点行 y
const ARROW_GAP := 34.0                      ## 箭头与圆点群的水平间距
const DOT_R := 5.0
const DOT_GAP := 26.0
const START_BTN_POS := Vector2(1318.0, 806.0)
const START_BTN_SIZE := Vector2(228.0, 62.0)

var _ais: Array[AiData] = []
var _texs: Array[Texture2D] = []
var _idx := 0
var _swapping := false

var _frame: PanelContainer = null
var _swap_view: RippleSwapPortrait = null
var _name_lbl: Label = null
var _family_lbl: Label = null
var _intro_lbl: Label = null
var _dot_row: Control = null
var _dots: Array[Panel] = []
var _left_btn: Button = null
var _right_btn: Button = null
var _start_btn: Button = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	if _ais.is_empty():
		setup(AiPool.all_ais())
	_build()


## 注入角色（locked 标记已由 AiPool 设好）
func setup(ais: Array[AiData]) -> void:
	_ais = ais
	_texs.clear()
	for a in _ais:
		var tex := load(a.portrait_path) as Texture2D
		_texs.append(tex)
	if is_inside_tree():
		_build()


func current_id() -> String:
	if _ais.is_empty():
		return "deepdeek"
	return _ais[_idx].id


func current_index() -> int:
	return _idx


func _build() -> void:
	if _ais.is_empty():
		return
	_build_frame()
	_build_dots()
	_build_start()
	_refresh(true)


# ── 左侧立绘框 ──
func _build_frame() -> void:
	_frame = PanelContainer.new()
	_frame.name = "PortraitFrame"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.045, 0.08, 0.55)
	sb.border_color = Color(0.30, 0.42, 0.62)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	_frame.add_theme_stylebox_override("panel", sb)
	_frame.position = FRAME_POS
	_frame.size = Vector2(FRAME_W, FRAME_H)
	_frame.clip_contents = true
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_swap_view = RippleSwapPortrait.new()
	_swap_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_swap_view)
	_fit_swap_view()
	_swap_view.set_portrait(_texs[_idx])
	_swap_view.swap_finished.connect(func() -> void: _swapping = false)

	# 角色名 / 家族 / 一句话（框右侧竖排说明）
	_name_lbl = UiKit.label("", 40, Color(0.92, 0.96, 1.0))
	_name_lbl.position = Vector2(FRAME_POS.x + FRAME_W + 54.0, FRAME_POS.y + 24.0)
	add_child(_name_lbl)

	_family_lbl = UiKit.dim("", 20, Color(0.55, 0.78, 1.0))
	_family_lbl.position = Vector2(FRAME_POS.x + FRAME_W + 56.0, FRAME_POS.y + 80.0)
	add_child(_family_lbl)

	_intro_lbl = UiKit.dim("", 18, Color(0.62, 0.72, 0.86))
	_intro_lbl.position = Vector2(FRAME_POS.x + FRAME_W + 56.0, FRAME_POS.y + 118.0)
	_intro_lbl.size = Vector2(560, 60)
	_intro_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_intro_lbl)


## 立绘等比适配：按贴图宽高比在框内居中，**不拉伸**。
## 素材换成正式立绘（更高更窄）后会自动铺满到最接近的等比尺寸。
func _fit_swap_view() -> void:
	if _swap_view == null or _ais.is_empty():
		return
	var tex := _texs[_idx]
	if tex == null:
		_swap_view.position = Vector2.ZERO
		_swap_view.size = Vector2(FRAME_W, FRAME_H)
		return
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	if tw <= 0.0 or th <= 0.0:
		return
	var scale: float = minf(FRAME_W / tw, FRAME_H / th)
	var w: float = tw * scale
	var h: float = th * scale
	_swap_view.position = Vector2((FRAME_W - w) * 0.5, (FRAME_H - h) * 0.5)
	_swap_view.size = Vector2(w, h)


# ── 圆点 + 左右箭头 ──
func _build_dots() -> void:
	var n := _ais.size()
	var total_w := ARROW_GAP * 2.0 + DOT_GAP * float(n - 1)
	var x0 := FRAME_POS.x + (FRAME_W - total_w) * 0.5

	_dot_row = Control.new()
	_dot_row.name = "DotRow"
	_dot_row.position = Vector2(x0, DOTS_Y)
	_dot_row.size = Vector2(total_w, 26.0)
	_dot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dot_row)

	_left_btn = _make_arrow("←")
	_left_btn.position = Vector2.ZERO
	_left_btn.pressed.connect(func() -> void: _step(-1))
	_dot_row.add_child(_left_btn)

	for i in n:
		var d := Panel.new()
		d.name = "Dot%d" % i
		d.custom_minimum_size = Vector2(DOT_R * 2.0, DOT_R * 2.0)
		d.position = Vector2(ARROW_GAP + DOT_GAP * float(i) - DOT_R, 13.0 - DOT_R)
		d.size = Vector2(DOT_R * 2.0, DOT_R * 2.0)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dots.append(d)
		_dot_row.add_child(d)

	_right_btn = _make_arrow("→")
	_right_btn.position = Vector2(total_w - 18.0, 0.0)
	_right_btn.pressed.connect(func() -> void: _step(1))
	_dot_row.add_child(_right_btn)


func _make_arrow(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(18.0, 26.0)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(0.70, 0.82, 0.96))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.45, 0.72, 1.0))
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _refresh_dots() -> void:
	for i in _dots.size():
		var on: bool = i == _idx
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.85, 0.94, 1.0) if on else Color(0.30, 0.40, 0.55)
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


## 按目标角色素材重算等比尺寸（切换前先设好，避免转场中途变形跳一下）
func _fit_swap_view_pending(i: int) -> void:
	if i < 0 or i >= _texs.size():
		return
	var keep := _idx
	_idx = i
	_fit_swap_view()
	_idx = keep


func _refresh(instant: bool = false) -> void:
	if _ais.is_empty():
		return
	var ai := _ais[_idx]
	_name_lbl.text = ai.display_name
	_family_lbl.text = ai.family
	_intro_lbl.text = ai.intro_line
	_refresh_dots()
	if instant and _swap_view != null:
		_swap_view.set_portrait(_texs[_idx])


## 左右切换：用**新角色**的专属转场播到它
func _step(dir: int) -> void:
	if _swapping or _ais.is_empty():
		return
	var next := wrapi(_idx + dir, 0, _ais.size())
	if next == _idx:
		return
	_swapping = true
	var next_tex := _texs[next]
	# 转场风格取「目标角色」的专属款（切换过去时呈现的是它）
	_swap_view.style = int(TRANSITION_STYLE[next % TRANSITION_STYLE.size()])
	_fit_swap_view_pending(next)
	_swap_view.swap_to(next_tex)
	var ai := _ais[next]
	_name_lbl.text = ai.display_name
	_family_lbl.text = ai.family
	_intro_lbl.text = ai.intro_line
	# 名字/说明闪一下，转场结束后补一次保险（swap_finished 已连 _swapping=false）
	UiKit.flash_text(_name_lbl, Color(0.55, 0.85, 1.0), 0.35)
	# 圆点立即跟着走（转场是视觉层，指示器状态不该滞后）
	_idx = next
	_refresh_dots()


## 供测试/调试：直接切到第 i 位并播转场（不走 dir 递推）
func select_by_index(i: int) -> void:
	if i < 0 or i >= _ais.size():
		return
	if i == _idx:
		return
	_idx = i
	_swapping = true
	_swap_view.style = int(TRANSITION_STYLE[i % TRANSITION_STYLE.size()])
	_fit_swap_view_pending(i)
	_swap_view.swap_to(_texs[i])
	var ai := _ais[i]
	_name_lbl.text = ai.display_name
	_family_lbl.text = ai.family
	_intro_lbl.text = ai.intro_line
	_refresh_dots()
