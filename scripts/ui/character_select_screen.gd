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
##
## 五轮（2026-11-09 integrate）：**大立绘加呼吸**。做法与理由见 PortraitBreathLayer 文件头：
##   RippleSwapPortrait 内部是独占材质的全屏不透明 ColorRect，所以呼吸只能做成它的**子节点**
##   （后入树 = 画在上面），转场期间整体隐藏，转场结束换图后 0.15s 淡入接管。
##   四人各自错相（第 i 位 = i/4 周期），切角色不重置相位；参数来自 F2 呼吸面板。

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

## 呼吸遮罩（生图灰度图，白区 = 位移大）：按**角色 id** 索引，与上面的大立绘一一对应。
## 注意 id 与美术原型名不是同名映射（AiPool.BIG_PORTRAITS 里 deepdeek→deepseek、
## kweno→qwen、chatppt→gpt、grock→grok），遮罩跟着原型名走。
## 缺文件时该角色自动降级纯 shader（use_region=false），不报错。
## 2026-11-10 主人要求拆成**三层**（hair / face / body）各自独立呼吸：
##   旧版单遮罩让眼睛跟着头发一起被推、脸被拉扯，三层拆分后脸严格只跟脸层曲线。
## 每层都是独立灰度图；某层缺文件则该层不参与（shader 侧 sum 归一化自动退让），
## 三层全缺时 use_layers=false，退化为「全身统一底边锚定」。
const BREATH_LAYERS := {
	"deepdeek": {
		"hair": "res://assets/art/select/layer-deepseek-hair.png",
		"face": "res://assets/art/select/layer-deepseek-face.png",
		"body": "res://assets/art/select/layer-deepseek-body.png",
		"wing": "",
		"h5": ["res://assets/art/select/hair5c-deepseek-seg1.png",
				"res://assets/art/select/hair5c-deepseek-seg2.png",
				"res://assets/art/select/hair5c-deepseek-seg3.png",
				"res://assets/art/select/hair5c-deepseek-seg4.png",
				"res://assets/art/select/hair5c-deepseek-seg5.png"],
	},
	"kweno": {
		"hair": "res://assets/art/select/layer-qwen-hair.png",
		"face": "res://assets/art/select/layer-qwen-face.png",
		"body": "res://assets/art/select/layer-qwen-body.png",
		"wing": "",
		"h5": ["res://assets/art/select/hair5c-qwen-seg1.png",
				"res://assets/art/select/hair5c-qwen-seg2.png",
				"res://assets/art/select/hair5c-qwen-seg3.png",
				"res://assets/art/select/hair5c-qwen-seg4.png",
				"res://assets/art/select/hair5c-qwen-seg5.png"],
	},
	"chatppt": {
		"hair": "res://assets/art/select/layer-gpt-hair.png",
		"face": "res://assets/art/select/layer-gpt-face.png",
		"body": "res://assets/art/select/layer-gpt-body2.png",
		"wing": "res://assets/art/select/layer-gpt-wing.png",
		"h5": ["res://assets/art/select/hair5c-gpt-seg1.png",
				"res://assets/art/select/hair5c-gpt-seg2.png",
				"res://assets/art/select/hair5c-gpt-seg3.png",
				"res://assets/art/select/hair5c-gpt-seg4.png",
				"res://assets/art/select/hair5c-gpt-seg5.png"],
	},
	"grock": {
		"hair": "res://assets/art/select/layer-grok-hair.png",
		"face": "res://assets/art/select/layer-grok-face.png",
		"body": "res://assets/art/select/layer-grok-body.png",
		"wing": "",
		"h5": ["res://assets/art/select/hair5c-grok-seg1.png",
				"res://assets/art/select/hair5c-grok-seg2.png",
				"res://assets/art/select/hair5c-grok-seg3.png",
				"res://assets/art/select/hair5c-grok-seg4.png",
				"res://assets/art/select/hair5c-grok-seg5.png"],
	},
}

var _ais: Array[AiData] = []
var _big_texs: Array[Texture2D] = []         ## 铺满全屏的大立绘
## 与 _big_texs 一一对应的呼吸遮罩（每项都可为 null）
var _big_hair: Array[Texture2D] = []
var _big_face: Array[Texture2D] = []
var _big_body: Array[Texture2D] = []
var _big_wing: Array[Texture2D] = []
## 五段头发：每角色一个长度 5 的数组
var _big_h5: Array = []
## GPT 黑洞区域遮罩（由 Python 定位红线核得出，只有这一张）
var _bh_region: Texture2D = null
var _idx := 0

var _bg_layer: RippleSwapPortrait = null     ## 背景大立绘（带一人一款转场）
var _breath: PortraitBreathLayer = null      ## 呼吸层（_bg_layer 的子节点，画在它上面）
var _blackhole: BlackHoleSpinner = null      ## 黑洞旋转层（仅 GPT 有，画在呼吸层之上）
var _breath_panel: BreathDebugPanel = null   ## F2 呼吸调试面板
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
	_big_hair.clear()
	_big_face.clear()
	_big_body.clear()
	_big_wing.clear()
	_bh_region = _load_tex("res://assets/art/select/region-gpt-blackhole.png")
	_big_h5.clear()
	for a in _ais:
		# 大立绘优先用 bust_path（全屏大图），没有就退回小立绘
		var big := _load_tex(a.bust_path)
		if big == null:
			big = _load_tex(a.portrait_path)
		_big_texs.append(big)
		# 三层遮罩按 id 查表；缺文件返回 null，该层自动不参与
		var lay: Dictionary = BREATH_LAYERS.get(a.id, {})
		_big_hair.append(_load_tex(String(lay.get("hair", ""))))
		_big_face.append(_load_tex(String(lay.get("face", ""))))
		_big_body.append(_load_tex(String(lay.get("body", ""))))
		_big_wing.append(_load_tex(String(lay.get("wing", ""))))
		var seg_paths: Array = lay.get("h5", [])
		var seg_texs: Array = []
		for sp in seg_paths:
			seg_texs.append(_load_tex(String(sp)))
		_big_h5.append(seg_texs)
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
	_build_breath_panel()   # 最后挂：F2 面板永远在所有控件之上
	_refresh()


# ── 背景：当前角色大立绘铺满全屏（无暗纱，带一人一款转场）──
func _build_background() -> void:
	# _build 可能被跑两次（_ready 一次、之后 setup() 再一次）：背景层只建一次，
	# 否则会叠出两层转场、两层呼吸，既费资源又会看到鬼影。
	if _bg_layer == null or not is_instance_valid(_bg_layer):
		_bg_layer = RippleSwapPortrait.new()
		_bg_layer.name = "BigPortraitBg"
		_bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bg_layer.swap_finished.connect(_on_swap_finished)
		add_child(_bg_layer)
		_build_breath()
	_bg_layer.swap_time = _swap_time_for(_idx)
	_bg_layer.style = int(TRANSITION_STYLE[_idx % TRANSITION_STYLE.size()])
	_bg_layer.set_portrait(_big_texs[_idx])
	_sync_breath_char()


## 呼吸层：作为 _bg_layer 的**子节点**后挂 → 画在 RippleRect 之上。
## 为什么不做成兄弟节点：兄弟要靠 z_index 抢层序，而 _bg_layer 的 SLASH 风格还会在
## 转场时抖动自身 position，挂成子节点能自动跟着走，层序也天然正确。
func _build_breath() -> void:
	if is_instance_valid(_breath) and _breath.get_parent() == _bg_layer:
		return
	_breath = PortraitBreathLayer.new()
	_breath.name = "PortraitBreath"
	_breath.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_layer.add_child(_breath)
	# 黑洞旋转层：挂在呼吸层之后（后入树=画在上面），只对 GPT 生效
	_blackhole = BlackHoleSpinner.new()
	_bg_layer.add_child(_blackhole)
	_sync_breath_char()


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
		_sync_breath_char()


## 切到第 next 位：用**目标角色**的专属转场播过去
func _swap_to_character(next: int) -> void:
	if next < 0 or next >= _ais.size() or next == _idx or _swapping:
		return
	_idx = next
	_refresh_dots()          # 指示器立即跟随（转场是视觉层，状态不该滞后）
	if _bg_layer == null:
		return
	_swapping = true
	# 转场期间呼吸层让位：两个动画同时改同一张画面会打架（呼吸的采样 UV 与转场的
	# tex_prev/tex_next 双图语义不兼容），等转场播完再淡入接管新图。
	if _breath != null:
		_breath.visible = false
	# 风格取**目标角色**的专属款：切过去时呈现的是它
	_bg_layer.style = int(TRANSITION_STYLE[next % TRANSITION_STYLE.size()])
	_bg_layer.swap_time = _swap_time_for(next)
	_bg_layer.swap_to(_big_texs[next])


## 转场结束：解锁连点 + 呼吸层接管新立绘
func _on_swap_finished() -> void:
	_swapping = false
	_sync_breath_char()
	if _breath == null or not _breath.has_portrait():
		return
	# 淡入而不是硬切：转场末帧与新图相同，但相位可能正在半周期，直接显会看到一下跳变
	_breath.visible = true
	_breath.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_breath, "modulate:a", 1.0, 0.15)


## 把当前角色的立绘/遮罩/错相下标推给呼吸层
func _sync_breath_char() -> void:
	if _breath == null or _big_texs.is_empty():
		return
	var i := clampi(_idx, 0, _big_texs.size() - 1)
	var hair: Texture2D = null
	var face: Texture2D = null
	var body: Texture2D = null
	if i < _big_hair.size():
		hair = _big_hair[i]
	if i < _big_face.size():
		face = _big_face[i]
	if i < _big_body.size():
		body = _big_body[i]
	var wing: Texture2D = null
	if i < _big_wing.size():
		wing = _big_wing[i]
	var h5: Array = []
	if i < _big_h5.size():
		h5 = _big_h5[i]
	_breath.set_character(i, _big_texs[i], hair, face, body, h5, wing)
	# 黑洞只有 GPT（chatppt）有，其余角色传 null 让该层隐藏
	if _blackhole != null:
		if current_id() == "chatppt":
			_blackhole.set_region(_big_texs[i], _bh_region)
		else:
			_blackhole.set_region(null, null)
	# 2026-11-10 主人要求：每个角色的呼吸参数都不一样 → 切角色时把该角色那套下发
	var cid := current_id()
	_apply_layers(cid)
	if _breath_panel != null:
		_breath_panel.set_character(cid)      # 面板整组换成该角色的值（静默，不回流）


## 把某角色的 8 层参数从 GameSettings 读出来、推给呼吸层
func _apply_layers(cid: String) -> void:
	if _breath == null:
		return
	_breath.set_layer_params(GameSettings.breath_layers_of(cid))


## 左右切换
func _step(dir: int) -> void:
	if _ais.is_empty() or _swapping:
		return
	_swap_to_character(wrapi(_idx + dir, 0, _ais.size()))


## 供测试/调试：直接切到第 i 位（走转场）
func select_by_index(i: int) -> void:
	_swap_to_character(i)


# ── F2 呼吸调试面板（2026-11-09）：挂在本界面右上角，与 UiTuner 的 F1 互不冲突 ──
func _build_breath_panel() -> void:
	if _breath_panel != null:
		return
	_breath_panel = BreathDebugPanel.new()
	_breath_panel.name = "BreathDebugPanel"
	add_child(_breath_panel)
	_breath_panel.params_changed.connect(_on_breath_params_changed)
	# 三层参数变化（每层 gain/phase）：面板改哪条就即时下发哪条
	_breath_panel.layers_changed.connect(_on_breath_layers_changed)
	_breath_panel.engine_changed.connect(_on_breath_engine_changed)
	# 启动回填：用存档值显式 set_params(..., emit_changed=false) —— 只同步面板 UI，
	# **不发信号**，所以开局不会因为回填把呼吸重播/重置相位。回填完再手动推一次
	# 给呼吸层（这条路径不发信号，必须显式调）。
	var sp := GameSettings.breath_params()
	var sp_amp := float(sp.get("amp", GameSettings.BREATH_AMP_DEF))
	var sp_per := float(sp.get("period", GameSettings.BREATH_PERIOD_DEF))
	var sp_ph := float(sp.get("phase", GameSettings.BREATH_PHASE_DEF))
	var sp_md := int(sp.get("mode", GameSettings.BREATH_MODE_DEF))
	_breath_panel.set_params(sp_amp, sp_per, sp_ph, sp_md, false)
	_on_breath_params_changed(sp_amp, sp_per, sp_ph, sp_md)
	# 面板按当前角色刷新三层滑杆（静默，避免开局重播）
	_breath_panel.set_character(current_id())
	# 呼吸引擎按配置生效（默认 V4 网格；V3 UV 留作降级对比）
	if _breath != null:
		_breath.set_engine(GameSettings.breath_engine == GameSettings.BREATH_ENGINE_MESH)
	# 面板直接改 V4 的 mesh uniform
	# 注意顺序：面板滑杆是在 _build() 里建的，那时 _mesh_ref 还是 null，
	# 初始值读不到、回调也写不进去。bind 之后必须**重新同步一次滑杆值**，
	# 否则主人会遇到「滑杆拖到 0，画面照样大幅动」（2026-11-10 实测踩到）。
	if _breath_panel != null:
		var mesh_now := _breath.get_mesh_layer()
		_breath_panel.bind_mesh(mesh_now)
		if mesh_now != null:
			var v4 := mesh_now.get_v4_params()
			for k in _breath_panel._layer_sliders.keys():
				if v4.has(k):
					var sl: HSlider = _breath_panel._layer_sliders[k]
					sl.set_value_no_signal(float(v4[k]))
					var lv: Label = _breath_panel._layer_vals.get(k)
					if lv != null:
						lv.text = "%.2f" % float(v4[k])
	# 横向开关按配置（主人要「上下、左右」分开，默认只做上下）
	var ml := _breath.get_mesh_layer()
	if ml != null:
		ml.set_horiz(GameSettings.breath_use_horiz)


## 面板参数变化 → 呼吸层即时生效（周期变了 Tween 会重建，但相位连续，见呼吸层注释）
func _on_breath_params_changed(a: float, per: float, ph: float, m: int) -> void:
	if _breath == null:
		return
	_breath.set_params(a, per, ph, m)


## 引擎切换 → 立即换实现（V4 网格 / V3 UV）
func _on_breath_engine_changed(engine: int) -> void:
	if _breath != null:
		_breath.set_engine(engine == GameSettings.BREATH_ENGINE_MESH)


## 八层参数变化 → 即时下发到呼吸层（面板已把值写进 GameSettings 对应角色分节）
func _on_breath_layers_changed(layers: Dictionary) -> void:
	if _breath == null:
		return
	_breath.set_layer_params(layers)


## 供测试/调试：开关呼吸面板（等同按一下 F2）
func toggle_breath_panel(force: Variant = null) -> bool:
	if _breath_panel == null:
		return false
	var v := (not _breath_panel.visible) if force == null else bool(force)
	_breath_panel.set_visible_state(v)
	return _breath_panel.visible


# ── 截图验收接口（verify 任务用）──────────────────────────────────────────
## 定格呼吸到某个进度（0..1）。p < 0 表示恢复自动呼吸。
## 定格期间 Tween 的写入被忽略，画面停在该相位，适合截图逐帧比对。
func debug_set_breath(p: float, amp_override: float = -1.0) -> void:
	if _breath == null:
		return
	if amp_override >= 0.0:
		_breath.set_params(amp_override, _breath.period, _breath.base_phase, _breath.mode)
	if p < 0.0:
		_breath.debug_resume_breath()
	else:
		_breath.debug_set_breath(p)


## 呼吸层当前状态快照（smoke / verify 断言都读它，避免直接摸私有字段）
func breath_state() -> Dictionary:
	if _breath == null:
		return {}
	return _breath.breath_state()


## 呼吸面板当前参数（没挂面板时返回 GameSettings 里的值）
func breath_panel_params() -> Dictionary:
	if _breath_panel == null:
		return GameSettings.breath_params()
	return _breath_panel.get_params()
