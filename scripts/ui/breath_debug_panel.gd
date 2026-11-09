class_name BreathDebugPanel
extends Control
## 立绘「呼吸」调试面板（F2 显隐，右上角浮层）。
##
## 用途：选角界面实测呼吸效果时，实时调 幅度 / 周期 / 相位 / 方案，拖动即生效并落盘，
## 关掉游戏再开还是主人调好的值。纯 UI + 信号，不自己改任何立绘——接线由
## CharacterSelectScreen 负责（本组件**不**知道 shader 的存在，保持可复用）。
##
## ── 对外契约（integrate 任务照这个用，改签名必须先回来改注释）──────────────
##   signal params_changed(amp: float, period: float, phase: float, mode: int)
##       任何参数变化都会发一次（滑杆拖动、方案按钮、set_params()）。
##
##   func set_visible_state(v: bool) -> void
##       程序化显隐。F2 走的也是这个函数，两个入口行为完全一致。
##
##   func get_params() -> Dictionary
##       键 "amp" / "period" / "phase" / "mode"，值都是当前生效值（已 clamp）。
##
##   func set_params(amp, period, phase, mode, emit_changed := true) -> void
##       程序化设值（不碰滑杆焦点）。emit_changed=false 时只同步 UI 不发信号，
##       适合「读存档回填但不触发重播」的场景。
##
##   enum Mode { UV = 0, SCALE = 1, OFF = 2 }
##       params_changed 的 mode 参数就是这三个值。
##
## ── 参数范围（唯一真相在 GameSettings.BREATH_*，这里只是引用）──────────────
##   amp    0.0 ~ 0.030   默认 0.008（= 0.8%，主人定的默认）
##   period 1.0 ~ 8.0 秒  默认 4.0
##   phase  0.0 ~ 1.0     默认 0.0（1.0 等于一个整周期，与 0 等价）
##
## ── 为什么是 F2（主人裁决，别改）──────────────────────────────────────────
##   主人 2026-11-09 裁决：呼吸面板用 F2，把 F1 留给 UiTuner（UI 调参器），
##   两边互不干扰。
##
##   背景（实测记录）：main.gd 在 _ready 里挂 UiTuner，它无条件吞 F1；而 Godot 4.7
##   的 _input 广播顺序是「后入树者先收到」+ accept_event 有效，本面板由
##   CharacterSelectScreen 挂载（更晚入树），若也用 F1 就会在选角界面上把 UiTuner
##   的 F1 抢走。改 F2 后两个调试工具可以同时在同一个界面上开着用，谁也压不住谁。
##   除非主人另行裁决，**不要**改回 F1，也不要顺手去动 UiTuner。
##
## ── 字号为什么是 12 而不是 spec 写的 13~15 ──────────────────────────────
##   项目用 Ark Pixel 12px 像素字体（PixelTheme 设了 fixed_size=12 +
##   INTEGER_ONLY 缩放），UiKit 明确约定「字号只能是 12 的整数倍，否则塌成同一档」，
##   选角界面全部文字都是 12。实测 13/14/15 只会把行高撑到 19/20/21，字形并未真正
##   变大（还带非整数缩放的字距抖动）。所以取 12 与选角界面严格一致。

## 参数变化（滑杆 / 方案按钮 / set_params 都会发）
signal params_changed(amp: float, period: float, phase: float, mode: int)

## 呼吸方案。值直接进 params_changed 的 mode，不要另立编号。
enum Mode {
	UV = 0,      ## UV 微起伏（shader，默认）
	SCALE = 1,   ## 仅整图缩放
	OFF = 2,     ## 关闭
}

const MODE_NAMES := ["UV微起伏", "仅整图缩放", "关闭"]

# ── 布局常量（像素风刻度：宽度/间距按 4 的倍数，字号走 UiKit 的 12 档）──
const PANEL_W := 336.0       ## 面板宽（右上角浮层，不挡画面主体）
const MARGIN := 18.0         ## 距屏幕上/右边缘
const PAD := 10              ## 面板内边距
const CORNER_R := 4          ## 圆角
const KEY_COL_W := 40.0      ## 滑杆行左侧标签列宽
const VAL_COL_W := 52.0      ## 滑杆行右侧数值列宽
const ROW_SEP := 5           ## 行距
const FS := 12               ## 字号（见文件头，与选角界面一致）

# ── 当前生效值（唯一真相；滑杆 / 信号 / get_params 都读它）──
var _amp := 0.008
var _period := 4.0
var _phase := 0.0
var _mode := int(Mode.UV)

# ── 节点 ──
var _panel: PanelContainer = null
var _amp_slider: HSlider = null
var _period_slider: HSlider = null
var _phase_slider: HSlider = null
var _amp_val: Label = null
var _period_val: Label = null
var _phase_val: Label = null
var _readout: Label = null
var _mode_btns: Array[Button] = []


func _init() -> void:
	name = "BreathDebugPanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 根铺满全屏但**不吃鼠标**：只让面板本体接点击，后面的圆点/箭头/开始键照常可用
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_settings()
	_build()
	_sync_widgets()
	_refresh_readout()
	set_visible_state(false)


# ── 持久化 ───────────────────────────────────────────
## 从 GameSettings 读基线（main.gd 已在 _ready 里 load_from_disk，这里只取快照）
func _load_settings() -> void:
	var p := GameSettings.breath_params()
	_amp = clampf(float(p.get("amp", 0.008)), GameSettings.BREATH_AMP_MIN, GameSettings.BREATH_AMP_MAX)
	_period = clampf(float(p.get("period", 4.0)),
			GameSettings.BREATH_PERIOD_MIN, GameSettings.BREATH_PERIOD_MAX)
	_phase = clampf(float(p.get("phase", 0.0)),
			GameSettings.BREATH_PHASE_MIN, GameSettings.BREATH_PHASE_MAX)
	_mode = clampi(int(p.get("mode", 0)), 0, GameSettings.BREATH_MODE_MAX)


## 写回 GameSettings。**不存盘**——存盘时机由调用方定（滑杆松手 / 按方案键），
## 拖动过程中每像素都存盘会把磁盘打爆。
func _push_settings() -> void:
	GameSettings.set_breath(_amp, _period, _phase, _mode)


# ── 对外 API ─────────────────────────────────────────
func set_visible_state(v: bool) -> void:
	visible = v
	if v:
		_refresh_readout()


func get_params() -> Dictionary:
	return {
		"amp": _amp,
		"period": _period,
		"phase": _phase,
		"mode": _mode,
	}


## 程序化设值。emit_changed=false 时只同步 UI（存档回填用，不触发重播）。
func set_params(new_amp: float, new_period: float, new_phase: float, new_mode: int,
		emit_changed: bool = true) -> void:
	_amp = clampf(new_amp, GameSettings.BREATH_AMP_MIN, GameSettings.BREATH_AMP_MAX)
	_period = clampf(new_period, GameSettings.BREATH_PERIOD_MIN, GameSettings.BREATH_PERIOD_MAX)
	_phase = clampf(new_phase, GameSettings.BREATH_PHASE_MIN, GameSettings.BREATH_PHASE_MAX)
	_mode = clampi(new_mode, 0, GameSettings.BREATH_MODE_MAX)
	_sync_widgets()
	if emit_changed:
		_emit_changed()
	else:
		_push_settings()
		_refresh_readout()


# ── 输入：只吃 F2（F1 留给 UiTuner）──────────────────
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	# keycode 与 physical_keycode 都查：非 US 布局下 keycode 可能是别的字符
	if k.keycode == KEY_F2 or k.physical_keycode == KEY_F2:
		set_visible_state(not visible)
		accept_event()      # 只有命中 F2 才吞；其它输入（含 F1）一律放行


# ── 构建 ─────────────────────────────────────────────
func _build() -> void:
	if _panel != null:
		return                      # 已建过（重复 _ready 防御）

	_panel = PanelContainer.new()
	_panel.name = "Box"
	_panel.add_theme_stylebox_override("panel", _style_box(
			Color(0.02, 0.03, 0.06, 0.82), Color(UiKit.ACCENT, 0.85), 1, PAD))
	# 右上角：锚右边缘，靠 offset 定宽，高度由内容撑开并向下延伸
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -(PANEL_W + MARGIN)
	_panel.offset_right = -MARGIN
	_panel.offset_top = MARGIN
	_panel.offset_bottom = MARGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 面板本体接住点击，不漏到背后
	add_child(_panel)

	var v := VBoxContainer.new()
	v.name = "Rows"
	v.add_theme_constant_override("separation", ROW_SEP)
	_panel.add_child(v)

	# —— 标题行 ——
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiKit.COL_GAP)
	v.add_child(head)
	var ttl := UiKit.label("呼吸调试", FS, UiKit.ACCENT)
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ttl)
	head.add_child(UiKit.dim("F2 开关 · 松手即存", FS, UiKit.TEXT_DIM))

	v.add_child(UiKit.rule())

	# —— 三个滑杆 ——
	var amp_row := _add_slider_row(v, "幅度", GameSettings.BREATH_AMP_MIN,
			GameSettings.BREATH_AMP_MAX, 0.0001, _amp)
	_amp_slider = amp_row["slider"]
	_amp_val = amp_row["value"]
	var period_row := _add_slider_row(v, "周期", GameSettings.BREATH_PERIOD_MIN,
			GameSettings.BREATH_PERIOD_MAX, 0.05, _period)
	_period_slider = period_row["slider"]
	_period_val = period_row["value"]
	var phase_row := _add_slider_row(v, "相位", GameSettings.BREATH_PHASE_MIN,
			GameSettings.BREATH_PHASE_MAX, 0.01, _phase)
	_phase_slider = phase_row["slider"]
	_phase_val = phase_row["value"]

	v.add_child(UiKit.rule())

	# —— 方案切换 ——
	var mode_row := HBoxContainer.new()
	mode_row.name = "ModeRow"
	mode_row.add_theme_constant_override("separation", UiKit.SP_2)
	v.add_child(mode_row)
	_mode_btns.clear()
	for i in MODE_NAMES.size():
		var b := Button.new()
		b.name = "Mode%d" % i
		b.text = String(MODE_NAMES[i])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", FS)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 24)
		b.pressed.connect(_on_mode_button.bind(i))
		mode_row.add_child(b)
		_mode_btns.append(b)

	# —— 一行只读汇总（截图取证用）——
	_readout = UiKit.label("", FS, Color(0.60, 0.88, 1.0))
	_readout.name = "Readout"
	_readout.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	_readout.add_theme_constant_override("outline_size", 2)
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_readout)


## 上一次 _add_slider_row 生成的数值 Label（省一个返回元组）
## 加一行「标签 + 滑杆 + 数值」。返回 {slider: HSlider, value: Label}。
## 用 Dictionary 而不是靠成员变量传值：调用点一眼看得出谁拿到哪个控件。
func _add_slider_row(parent: VBoxContainer, key: String, mn: float, mx: float,
		step: float, val: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = key + "Row"
	row.add_theme_constant_override("separation", UiKit.SP_2)
	parent.add_child(row)

	var k := UiKit.dim(key, FS, Color(0.85, 0.92, 1.0))
	k.custom_minimum_size = Vector2(KEY_COL_W, 0)
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(k)

	var s := HSlider.new()
	s.name = key + "Slider"
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(0, 16)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)

	var vl := UiKit.dim("", FS, Color(0.60, 0.88, 1.0))
	vl.name = key + "Value"
	vl.custom_minimum_size = Vector2(VAL_COL_W, 0)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(vl)

	s.value_changed.connect(_on_slider_changed)
	s.drag_ended.connect(_on_drag_ended)
	return {"slider": s, "value": vl}


## 深色底 + 描边 + 圆角。复用 UiKit.flat 的颜色/阴影刻度，只补圆角
## （UiKit.flat 是硬边面板工厂，corner_radius 恒为 0）。
func _style_box(bg: Color, border: Color, border_w: int, pad: int) -> StyleBoxFlat:
	var sb := UiKit.flat(bg, border, border_w, pad)
	sb.set_corner_radius_all(CORNER_R)
	return sb


# ── 交互 ─────────────────────────────────────────────
## 滑杆动 → 立刻生效（不存盘，存盘在 drag_ended）
func _on_slider_changed(_v: float) -> void:
	if _amp_slider == null:
		return
	_amp = float(_amp_slider.value)
	_period = float(_period_slider.value)
	_phase = float(_phase_slider.value)
	_emit_changed()


## 松手才存盘：拖动中每帧都写会打爆磁盘
func _on_drag_ended(_value_changed: bool) -> void:
	GameSettings.save_to_disk()


func _on_mode_button(idx: int) -> void:
	_mode = clampi(idx, 0, GameSettings.BREATH_MODE_MAX)
	# toggle_mode 的按钮点下去会自己翻转 button_pressed，但「点已选中的那个」会把它翻成
	# false；这里统一按 _mode 重刷三个键的按下态，保证永远只有一个亮着。
	_sync_mode_buttons()
	_emit_changed()
	GameSettings.save_to_disk()


## 只刷方案按钮的按下态与配色（不碰滑杆）
func _sync_mode_buttons() -> void:
	for i in _mode_btns.size():
		var b := _mode_btns[i]
		var on := i == _mode
		b.set_pressed_no_signal(on)
		_style_mode_btn(b, on)


func _emit_changed() -> void:
	_push_settings()
	_refresh_readout()
	params_changed.emit(_amp, _period, _phase, _mode)


# ── 刷新 ─────────────────────────────────────────────
## 把当前值推给控件（不触发 value_changed）
func _sync_widgets() -> void:
	if _amp_slider == null:
		return
	_amp_slider.set_value_no_signal(_amp)
	_period_slider.set_value_no_signal(_period)
	_phase_slider.set_value_no_signal(_phase)
	_sync_mode_buttons()


func _refresh_readout() -> void:
	if _amp_val == null:
		return
	_amp_val.text = "%.4f" % _amp
	_period_val.text = "%.2fs" % _period
	_phase_val.text = "%.2f" % _phase
	if _readout != null:
		_readout.text = "amp %.4f   周期 %.2fs   相位 %.2f   %s" % [
			_amp, _period, _phase, String(MODE_NAMES[clampi(_mode, 0, MODE_NAMES.size() - 1)])]


## 选中态：青色描边 + 亮字；未选：暗描边 + 灰字。与选角界面的调参器同色系。
func _style_mode_btn(b: Button, selected: bool) -> void:
	var border := Color(UiKit.ACCENT, 1.0) if selected else Color(0.28, 0.34, 0.46, 0.9)
	var bg := Color(0.09, 0.16, 0.22, 0.95) if selected else Color(0.06, 0.08, 0.12, 0.9)
	b.add_theme_stylebox_override("normal", _style_box(bg, border, 1, 4))
	b.add_theme_stylebox_override("hover",
			_style_box(bg.lightened(0.10), border.lightened(0.22), 1, 4))
	b.add_theme_stylebox_override("pressed", _style_box(bg.darkened(0.18), border, 1, 4))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color",
			Color(0.93, 0.98, 1.0) if selected else UiKit.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", UiKit.TEXT_DIM)


# ── 测试/调试辅助（供 integrate 与 headless 自测用，玩法不调）──
## 当前面板框的全局矩形（没建出来就返回空 Rect2）
func panel_rect() -> Rect2:
	if _panel == null or not _panel.is_inside_tree():
		return Rect2()
	return Rect2(_panel.global_position, _panel.size)
