class_name BreathDebugPanel
extends Control
## 立绘「呼吸」调试面板（**常驻显示**在选角右上角，不绑热键）。
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
##       程序化显隐（无热键入口）。
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
## ── 为什么现在不绑热键（主人 2026-11-10 裁决）─────────────────────────
##   最初用 F1，被 UiTuner 无条件吞掉；改 F2 后发现面板本就默认可见，按一下
##   反而是「关掉」，主人以为调不出来；再改 F3 仍有同样的语义反转问题。
##   最终方案：**常驻显示在选角右上角，不响应任何热键**。
##   · F1 完整让给 UiTuner，本面板不参与任何按键竞争，两者可同屏共存；
##   · 需要临时隐掉时走程序化接口 set_visible_state(false) / toggle_breath_panel()；
##   · 除非主人另行要求，不要再给它绑热键。
signal params_changed(amp: float, period: float, phase: float, mode: int)
## 三层参数变化（2026-11-10）：每角色独立，CharacterSelectScreen 收到后转给呼吸层
signal layers_changed(layers: Dictionary)
## 呼吸引擎切换（2026-11-10）：0=UV(V3)  1=Mesh(V4 网格顶点形变)
signal engine_changed(engine: int)

## 呼吸方案。值直接进 params_changed 的 mode，不要另立编号。
enum Mode {
	UV = 0,        ## 上下起伏（纯纵向 UV 位移，默认）
	UV_HORZ = 1,   ## 左右起伏（纯横向 UV 位移）
	SCALE = 2,     ## 整图缩放（绕底边，最像真呼吸）
	OFF = 3,       ## 关闭
}

## 2026-11-10 主人要求提供「上下 / 左右」两种运动方向：
##   旧版 shader 里横向与纵向错相 1.2rad 合成椭圆轨迹，观感像画面在转 —— 已删除。
##   现在把方向做成显式二选一，各自都只有单一轴向，不会出现旋转感。
const MODE_NAMES := ["上下起伏", "左右起伏", "整图缩放", "关闭"]

# ── 布局常量（像素风刻度：宽度/间距按 4 的倍数，字号走 UiKit 的 12 档）──
const PANEL_W := 470.0       ## 面板宽（V3 扩到 8 层，两列布局）
const MARGIN := 18.0         ## 距屏幕上/右边缘
const PAD := 10              ## 面板内边距
const CORNER_R := 4          ## 圆角
const KEY_COL_W := 40.0      ## 滑杆行左侧标签列宽
const VAL_COL_W := 52.0      ## 滑杆行右侧数值列宽
const ROW_SEP := 5           ## 行距
const FS := 12               ## 字号（见文件头，与选角界面一致）
## 主人 2026-11-10 要求默认打开面板（方便直接拖滑杆调呼吸）
const PANEL_OPEN_BY_DEFAULT := true

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
var _engine_btns: Array[Button] = []
var _engine := GameSettings.BREATH_ENGINE_DEF

## ── 2026-11-10 主人要求：每个角色的每一层都能单独调 ──────────────────
## 面板只显示**当前角色**的参数，切角色时整体换成该角色的值（面板不会太大）。
var _cur_char := "deepdeek"
## 三层各自的 gain / phase 滑杆与数值 Label（键名同 GameSettings.BREATH_LAYER_KEYS）
var _layer_sliders := {}
var _layer_vals := {}
var _char_lbl: Label = null
## V4 引擎的 mesh 引用（面板直接改它的 uniform）
var _mesh_ref: PortraitBreathMesh = null
var _horiz_btn: Button = null


func _init() -> void:
	name = "BreathDebugPanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 根铺满全屏但**不吃鼠标**：只让面板本体接点击，后面的圆点/箭头/开始键照常可用
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 主人 2026-11-10 要求默认打开：进选角界面就能直接拖滑杆试呼吸
	visible = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_settings()
	_build()
	_sync_widgets()
	_refresh_readout()
	set_visible_state(PANEL_OPEN_BY_DEFAULT)


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


# ── 输入：不再绑定热键（主人 2026-11-10 裁决）────────────
# 原方案 F2/F3 切换有两处实测问题：
#   ① 面板本就默认可见，按一下反而是「关掉」，主人以为调不出来；
#   ② 面板挂载时机与 UiTuner 的 F1 广播顺序耦合，容易互相压。
# 现改为**常驻显示在选角右上角**，不再响应任何热键：
#   · 想临时隐藏用代码/测试调 set_visible_state(false) 或 toggle_breath_panel()
#   · F1 完整让给 UiTuner，本面板不参与任何按键竞争
# 保留空实现的 _input 只为了对齐父类签名，不做任何事。


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
	head.add_child(UiKit.dim("松手即存 · 常驻显示", FS, UiKit.TEXT_DIM))

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

	v.add_child(UiKit.rule())

	# —— 当前角色标题（切角色时刷新）——
	_char_lbl = UiKit.dim("角色：deepdeek", FS, Color(0.95, 0.85, 0.55))
	_char_lbl.name = "CharLabel"
	v.add_child(_char_lbl)

	# —— 呼吸引擎切换（V4 网格 / V3 UV）——
	# V4 能做胸腔横向外扩与头发随高度连续滞后；V3 只做整幅 UV 平移，留作对比降级。
	var eng_row := HBoxContainer.new()
	eng_row.name = "EngineRow"
	eng_row.add_theme_constant_override("separation", UiKit.SP_2)
	v.add_child(eng_row)
	var eng_lbl := UiKit.dim("引擎", FS, Color(0.85, 0.92, 1.0))
	eng_lbl.custom_minimum_size = Vector2(KEY_COL_W, 0)
	eng_row.add_child(eng_lbl)
	_engine_btns.clear()
	for i in ["V4 网格", "V3 UV"]:
		var eb := Button.new()
		eb.text = String(i)
		eb.toggle_mode = true
		eb.focus_mode = Control.FOCUS_NONE
		eb.add_theme_font_size_override("font_size", FS)
		eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eb.custom_minimum_size = Vector2(0, 22)
		var idx2 := _engine_btns.size()
		eb.pressed.connect(func() -> void: _on_engine_button(idx2))
		eng_row.add_child(eb)
		_engine_btns.append(eb)
	_sync_engine_buttons()

	# —— V4 引擎参数（2026-11-10 切到网格形变后的正确调参项）——
	# V3 那套 8 层 gain/phase 是 UV 位移模型的产物，V4 用的是
	# 「胸/腹/头/发的横竖像素幅度 + 滞后角」，两套参数模型不兼容。
	# 面板只显示**当前引擎**对应的参数，切引擎自动换。
	_layer_sliders.clear()
	_layer_vals.clear()
	var grid := HBoxContainer.new()
	grid.name = "LayerGrid"
	grid.add_theme_constant_override("separation", UiKit.SP_3)
	v.add_child(grid)
	var col_l := VBoxContainer.new()
	col_l.add_theme_constant_override("separation", 2)
	col_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(col_l)
	var col_r := VBoxContainer.new()
	col_r.add_theme_constant_override("separation", 2)
	col_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(col_r)

	# 左列：幅度（像素单位，1600x900 画布下 10px ≈ 画面高 1.1%）
	# 右列：相位滞后 / 其他
	var specs := [
		# 总倍率：一条滑杆同时缩放全部 7 个幅度（主人要「整体减弱」时不用逐条拖）
		["amp", "总倍率", 0.0, 3.0, 0.05, col_l],
		# 幅度步长一律 0.1：出厂默认里有 3.2 这类非 0.5 整倍数（商业基线反推出来的，
		# 不应为迁就滑杆而改数值）。旧存档存的是 0.5 网格值，全都落在 0.1 网格上，兼容。
		["chest_x", "胸横", 0.0, 30.0, 0.1, col_l],
		["chest_y", "胸纵", 0.0, 30.0, 0.1, col_l],
		["belly_x", "腹横", 0.0, 30.0, 0.1, col_l],
		["belly_y", "腹纵", 0.0, 30.0, 0.1, col_l],
		["head_y", "头纵", 0.0, 30.0, 0.1, col_l],
		["hair_x", "发横", 0.0, 40.0, 0.1, col_l],
		["hair_y", "发纵", 0.0, 40.0, 0.1, col_l],
		# 底锁下限给 0.01 而不是 0：0 在旧 shader 里会撞 smoothstep(0,0,x) 未定义行为，
		# shader 已加显式分支兜底，这里再从 UI 侧挡一道（拖到底也不至于完全没呼吸）。
		["lock_bottom", "底锁", 0.01, 0.5, 0.01, col_l],
		["belly_lag_deg", "腹滞°", 0.0, 180.0, 1.0, col_r],
		["head_lag_deg", "头滞°", 0.0, 180.0, 1.0, col_r],
		["hair_lag_per_height", "发高滞°", 0.0, 720.0, 5.0, col_r],
		["x_lag_deg", "横相滞°", 0.0, 180.0, 1.0, col_r],
		# 0.01 而不是 0.02：默认 0.35 在 0.02 网格上会被吸附成 0.36
		["y_bias", "纵偏移", 0.0, 1.0, 0.01, col_r],
		# 背景层：人物以外区域的轻微跟随。0 = 背景完全静止（觉得画面整体在晃就拖到 0）。
		# 它不改 uniform 而是烘进顶点色，改动会重建网格（一次几百毫秒，松手时才会触发）。
		["env_weight", "背景", 0.0, 0.5, 0.01, col_r],
	]
	var v4p := {}
	if _mesh_ref != null:
		v4p = _mesh_ref.get_v4_params()
	for sp in specs:
		var key := String(sp[0])
		var cur := float(v4p.get(key, 0.0))
		var row := _add_slider_row(sp[5] as VBoxContainer, String(sp[1]),
				float(sp[2]), float(sp[3]), float(sp[4]), cur)
		_layer_sliders[key] = row["slider"]
		_layer_vals[key] = row["value"]
		(row["slider"] as HSlider).value_changed.connect(
				func(_v: float) -> void: _on_v4_changed(key))

	# 横向总开关（关掉 = 纯上下呼吸，彻底没有旋转感）
	var hz_row := HBoxContainer.new()
	hz_row.add_theme_constant_override("separation", UiKit.SP_2)
	v.add_child(hz_row)
	var hz_lbl := UiKit.dim("横向", FS, Color(0.85, 0.92, 1.0))
	hz_lbl.custom_minimum_size = Vector2(KEY_COL_W, 0)
	hz_row.add_child(hz_lbl)
	_horiz_btn = Button.new()
	_horiz_btn.text = "开"
	_horiz_btn.toggle_mode = true
	_horiz_btn.focus_mode = Control.FOCUS_NONE
	_horiz_btn.add_theme_font_size_override("font_size", FS)
	_horiz_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hz_on := bool(v4p.get("use_horiz", true))
	_horiz_btn.set_pressed_no_signal(hz_on)
	_style_mode_btn(_horiz_btn, hz_on)
	_horiz_btn.pressed.connect(_on_horiz_toggle)
	hz_row.add_child(_horiz_btn)

	# —— 一行只读汇总（截图取证用）——
	_readout = UiKit.label("", FS, Color(0.60, 0.88, 1.0))
	_readout.name = "Readout"
	_readout.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	_readout.add_theme_constant_override("outline_size", 2)
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout.autowrap_mode = TextServer.AUTOWRAP_OFF
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


## 分层滑杆变化：写进当前角色的那一层，并立即下发（不存盘，松手时存）
func _on_layer_changed(key: String) -> void:
	if not _layer_sliders.has(key):
		return
	var sl: HSlider = _layer_sliders[key]
	GameSettings.set_breath_layer(_cur_char, key, float(sl.value))
	var lv: Label = _layer_vals.get(key)
	if lv != null:
		lv.text = "%.3f" % float(sl.value)
	_emit_layers()


## 注入 V4 mesh 引用（CharacterSelectScreen 在切角色时调）。
## **bind 完立刻自同步**：面板滑杆可能是在 _mesh_ref 还是 null 时建的，
## 那时读不到初始值。把「绑定」和「同步」绑成一次原子操作，调用方就不必
## 记得「bind 之后还要再刷一遍」（2026-11-10 踩过：漏了这步 → 滑杆全 0 画面照动）。
func bind_mesh(m: PortraitBreathMesh) -> void:
	_mesh_ref = m
	sync_from_mesh()


## 从 mesh 读真值刷新 V4 滑杆（不发 value_changed，不会反过来改 mesh）
func sync_from_mesh() -> void:
	if _mesh_ref == null:
		return
	var v4 := _mesh_ref.get_v4_params()
	for k in _layer_sliders.keys():
		if not v4.has(k):
			continue
		var sl: HSlider = _layer_sliders[k]
		sl.set_value_no_signal(float(v4[k]))
		var lv: Label = _layer_vals.get(k)
		if lv != null:
			lv.text = "%.2f" % float(v4[k])
	# 横向开关也跟 mesh 走（它是独立按钮，不在 _layer_sliders 里）
	if _horiz_btn != null and v4.has("use_horiz"):
		var on := bool(v4["use_horiz"])
		_horiz_btn.set_pressed_no_signal(on)
		_style_mode_btn(_horiz_btn, on)
		_horiz_btn.text = "开" if on else "关"
	_refresh_readout()


## V4 参数改动 → 写进当前角色的存档 + mesh 的 uniform
## 每角色一套：切角色时各自恢复，互不干扰。
## env_weight 例外：它烘在顶点色里，每改一点就重建网格会卡，推迟到松手重建。
var _env_dirty := false
## 落盘节流：**点击滑杆跳值不发 drag_ended**（只有真拖动才发），
## 只靠 drag_ended 存盘会漏掉点击这条路径（实测：点完之后磁盘还是旧值）。
## 所以这里自己带一个延迟存盘，每来一次改动就重置计时，停手 0.4s 落盘。
const SAVE_DEBOUNCE := 0.4
var _save_timer: Timer = null

func _on_v4_changed(key: String) -> void:
	if not _layer_sliders.has(key):
		return
	var sl: HSlider = _layer_sliders[key]
	var lv: Label = _layer_vals.get(key)
	if lv != null:
		lv.text = "%.2f" % float(sl.value)
	GameSettings.set_breath_v4(_cur_char, key, float(sl.value))
	if _mesh_ref != null:
		if String(key) == "env_weight":
			_env_dirty = true          # 松手时再重建网格
		else:
			_mesh_ref.set_v4_param(key, float(sl.value))
	_refresh_readout()
	_queue_save()


## 延迟存盘（防抖）：连续拖动的每一下都会重置计时，停手才写盘，
## 不会把磁盘打爆，也能兜住「点击跳值」这条不发 drag_ended 的路径。
func _queue_save() -> void:
	if _save_timer == null:
		_save_timer = Timer.new()
		_save_timer.one_shot = true
		_save_timer.wait_time = SAVE_DEBOUNCE
		_save_timer.timeout.connect(_flush_save)
		add_child(_save_timer)
	_save_timer.start()


## 立刻落盘（防抖到点 / 面板被销毁前调用）
func _flush_save() -> void:
	if _env_dirty and _mesh_ref != null:
		_env_dirty = false
		_mesh_ref.set_env_weight(GameSettings.breath_v4_get(_cur_char, "env_weight"))
	GameSettings.save_to_disk()


## 面板离开场景树时兜底存一次：防止「改完立刻退出/切场景」丢改动
func _exit_tree() -> void:
	if _save_timer != null and not _save_timer.is_stopped():
		_flush_save()


## 横向总开关
func _on_horiz_toggle() -> void:
	var on := not _horiz_btn.button_pressed
	_horiz_btn.set_pressed_no_signal(on)
	_style_mode_btn(_horiz_btn, on)
	_horiz_btn.text = "开" if on else "关"
	if _mesh_ref != null:
		_mesh_ref.set_horiz(on)
	GameSettings.breath_use_horiz = on
	GameSettings.save_to_disk()
	_refresh_readout()


## 切到另一个角色：面板**整组换成该角色存着的值**（主人要求每个角色的调参器都不一样）
## silent=true 时不发信号（选角流程里用，避免和 CharacterSelectScreen 自己的下发打架）
## 2026-11-10 修：这里必须按「滑杆装的是哪套键」分流。V4 的键（chest_x 等）在
## GameSettings.breath_layer() 里查不到 → 回落 0.0，曾把所有 V4 滑杆刷成 0。
func set_character(cid: String, silent: bool = true) -> void:
	if not GameSettings.BREATH_CHARS.has(cid):
		return
	_cur_char = cid
	if _char_lbl != null:
		_char_lbl.text = "角色：%s" % cid
	var v4_of := GameSettings.breath_v4_of(_cur_char)
	for key in _layer_sliders.keys():
		var k := String(key)
		# V4 键走 V4 存档；V3 键走 V3 存档。两套键空间不重叠，这里只是防御性分流。
		var v := float(v4_of[k]) if v4_of.has(k) else GameSettings.breath_layer(_cur_char, k)
		(_layer_sliders[key] as HSlider).set_value_no_signal(v)
		var lv2: Label = _layer_vals.get(key)
		if lv2 != null:
			lv2.text = ("%.2f" % v) if v4_of.has(k) else ("%.3f" % v)
	# 该角色的 V4 参数灌进 mesh（切角色后画面立刻是它自己的那套）
	if _mesh_ref != null:
		_mesh_ref.apply_v4_params(v4_of)
	_refresh_readout()
	if not silent:
		_emit_layers()


## 当前角色
func current_character() -> String:
	return _cur_char


## 取当前角色三层参数快照
func layer_params() -> Dictionary:
	var out := {}
	for key in _layer_sliders.keys():
		out[key] = float((_layer_sliders[key] as HSlider).value)
	return out



func _emit_layers() -> void:
	layers_changed.emit(layer_params())


## 松手才存盘：拖动中每帧都写会打爆磁盘
func _on_drag_ended(_value_changed: bool) -> void:
	# 拖动结束立刻落盘（不等防抖），并补一次背景权重网格重建
	if _save_timer != null:
		_save_timer.stop()
	_flush_save()


## 引擎切换：1=V4 网格, 0=V3 UV（按钮顺序是 V4 在前，所以取反）
func _on_engine_button(btn_idx: int) -> void:
	_engine = GameSettings.BREATH_ENGINE_MESH if btn_idx == 0 else GameSettings.BREATH_ENGINE_UV
	GameSettings.breath_engine = _engine
	_sync_engine_buttons()
	engine_changed.emit(_engine)
	GameSettings.save_to_disk()


func _sync_engine_buttons() -> void:
	for i in _engine_btns.size():
		var on := (i == 0 and _engine == GameSettings.BREATH_ENGINE_MESH) 				or (i == 1 and _engine == GameSettings.BREATH_ENGINE_UV)
		(_engine_btns[i] as Button).set_pressed_no_signal(on)
		_style_mode_btn(_engine_btns[i] as Button, on)


func current_engine() -> int:
	return _engine


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
		_readout.text = "amp %.4f  周期 %.2fs  %s" % [
			_amp, _period, String(MODE_NAMES[clampi(_mode, 0, MODE_NAMES.size() - 1)])]
		# 第二行读当前生效的引擎：V4 读像素幅度/滞后角，V3 才读那 8 个 gain
		if GameSettings.breath_engine == GameSettings.BREATH_ENGINE_MESH:
			_readout.text += "
%s 胸%.1f/%.1f 腹%.1f/%.1f 头%.1f 发%.1f/%.1f 滞%d/%d/%d" % [
				_cur_char,
				_slider_val("chest_x"), _slider_val("chest_y"),
				_slider_val("belly_x"), _slider_val("belly_y"),
				_slider_val("head_y"),
				_slider_val("hair_x"), _slider_val("hair_y"),
				int(_slider_val("belly_lag_deg")), int(_slider_val("head_lag_deg")),
				int(_slider_val("hair_lag_per_height"))]
		else:
			_readout.text += "
%s 顶%.2f 左%.2f 右%.2f 长%.2f 梢%.2f 脸%.2f 身%.2f 翅%.2f" % [
				_cur_char,
				float(_slider_val("h1_gain")), float(_slider_val("h2_gain")),
				float(_slider_val("h3_gain")), float(_slider_val("h4_gain")),
				float(_slider_val("h5_gain")), float(_slider_val("face_gain")),
				float(_slider_val("body_gain")), float(_slider_val("wing_gain"))]


## 读某条分层滑杆的当前值（滑杆还没建时返回 0）
func _slider_val(key: String) -> float:
	if _layer_sliders.has(key):
		return float((_layer_sliders[key] as HSlider).value)
	return 0.0


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
