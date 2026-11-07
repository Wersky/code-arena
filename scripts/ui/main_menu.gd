extends Control
class_name MainMenuScreen
## 主菜单（2026-10-23 重做 v2）：商业游戏标题画面的构图。
##
## 版面（1600×900 基准，全部按 size 摆，换分辨率不散）：
##
##        ┌──────── 牌匾（生图金框 + 像素大字）────────┐   ← 压在主面板上沿
##     ┌──┴────────────────────────────────────────────┴──┐
##     │  一句副题                                        │
##     │  [图标] 52 张牌   [图标] 10 关   ...             │   ← 生图图标 + 说明
##     │  ───────────── 金分隔线 ─────────────            │
##     │        ┌──── 开始游戏（生图底板 ×2）────┐        │
##     │                  退出游戏                        │
##     └──────────────────────────────────────────────────┘
##   v0.9 …                                        © 2026 …
##
## 尺寸纪律（主人原话："不要太小，不然背景显得太大"）：
##   面板宽 ≥ 屏宽 65%，牌匾宽 ≥ 面板宽 75%，主按钮宽 ≥ 面板宽 55%。
##   所有生图资产按整数倍放大（×2），非整数会把像素格拉得一宽一窄。
##
## 外部只依赖两个信号：`start_run` / `quit_game`（main.gd 里接的）。

signal start_run
signal quit_game
## AI 接入面板（main.gd 接路由；面板本体见文件末尾的 LLMSettingsPanel）
signal open_ai_settings

## 环境动效层（漂浮尘埃 + 扫描线 + 视差）
var _bg_fx: BgFx = null

var _shadow: NinePatchRect = null
var _panel: NinePatchRect = null
var _plaque: TitlePlate = null
var _kicker: PromptLine = null
var _feat_row: HBoxContainer = null
var _divider: TextureRect = null
var _start_btn: JuiceButton = null
var _quit_btn: JuiceButton = null
var _speed_btn: JuiceButton = null
var _win_btn: JuiceButton = null
var _ai_btn: JuiceButton = null
var _hint: Label = null
var _foot_left: Label = null
var _foot_right: Label = null

## 版面尺寸（在 _layout 里算，_build 时先用默认值也能正常显示）
var _rect_panel := Rect2(280, 300, 1040, 520)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	SfxNode.music("bgm_gemini2")
	_build_bg()
	_build_panel()
	_build_plaque()
	_build_content()
	_build_footer()

	# CRT 扫描线盖全屏，压在最上面但鼠标透传
	var scan := Scanlines.new()
	scan.spacing = 4
	scan.alpha = 0.08
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scan)
	scan.set_anchors_preset(Control.PRESET_FULL_RECT)

	resized.connect(_layout)
	_layout()


# ── 背景 ──────────────────────────────────────────────
func _build_bg() -> void:
	var bg := TextureRect.new()
	bg.texture = Art.tex("bg-arena")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var veil := ColorRect.new()
	veil.color = Color(0.043, 0.055, 0.086, 0.66)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	# 终端代码雨（2026-11-07 主人要求）：压暗层之上、尘埃层之下
	var rain := TerminalRain.new()
	rain.name = "TerminalRainBg"
	rain.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rain)

	_bg_fx = BgFx.new()
	_bg_fx.name = "BgFx"
	_bg_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg_fx)
	_bg_fx.setup(size)


# ── 面板 ──────────────────────────────────────────────
func _build_panel() -> void:
	# 阴影：把同一张九宫格调成黑色当剪影，比矩形阴影更贴合异形边角
	_shadow = UiArt.panel(_rect_panel.size)
	if _shadow != null:
		_shadow.self_modulate = Color(0, 0, 0, 0.55)
		add_child(_shadow)

	_panel = UiArt.panel(_rect_panel.size)
	if _panel != null:
		add_child(_panel)


# ── 牌匾 ──────────────────────────────────────────────
func _build_plaque() -> void:
	_plaque = TitlePlate.new()
	_plaque.name = "TitlePlate"
	_plaque.plate = UiArt.NAME_PLAQUE if UiArt.has("plaque") else ""
	_plaque.cn_size = 88
	_plaque.en_size = 30
	_plaque.custom_minimum_size = Vector2(808, 294)
	_plaque.size = Vector2(808, 294)
	add_child(_plaque)


# ── 面板内容 ──────────────────────────────────────────
func _build_content() -> void:
	# 一条"提示词输入行"：> 正文 ▮ ← 这是全屏最"AI"的细节，别删
	_kicker = PromptLine.new()
	_kicker.name = "PromptLine"
	_kicker.text = "选一位 AI 娘，把牌凑成德州牌型打出去"
	_kicker.font_size = 22
	_kicker.prefix_color = UiArt.NEON
	_kicker.text_color = Color(0.66, 0.74, 0.86)
	_kicker.caret_color = UiArt.NEON
	add_child(_kicker)

	_feat_row = HBoxContainer.new()
	_feat_row.add_theme_constant_override("separation", 56)
	_feat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_feat_row)
	for item in [["tokens", "52 张牌"], ["server", "10 关爬塔"],
			["reticle", "目标分"], ["chip", "4 位 AI 娘"]]:
		_feat_row.add_child(_feature(item[0], item[1]))


	_start_btn = JuiceButton.new()
	_start_btn.name = "StartButton"
	_start_btn.text = "开始游戏"
	_start_btn.primary = true
	_start_btn.accent = UiArt.NEON
	_start_btn.font_size = 56
	_start_btn.plate = UiArt.NAME_BTN if UiArt.has("btn") else ""
	var bs := UiArt.display_size("btn")
	_start_btn.custom_minimum_size = bs
	_start_btn.size = bs
	_start_btn.pressed.connect(func() -> void:
		SfxNode.play("ui_click")
		start_run.emit())
	add_child(_start_btn)

	_quit_btn = JuiceButton.new()
	_quit_btn.name = "QuitButton"
	_quit_btn.text = "退出游戏"
	_quit_btn.bare = true
	_quit_btn.font_size = 24
	_quit_btn.custom_minimum_size = Vector2(360, 44)
	_quit_btn.size = Vector2(360, 44)
	_quit_btn.pressed.connect(func() -> void:
		SfxNode.play("ui_click")
		quit_game.emit())
	add_child(_quit_btn)

	# 终端进场打字速度（慢 / 中 / 快）——开始界面就能改
	_speed_btn = JuiceButton.new()
	_speed_btn.name = "SpeedButton"
	_speed_btn.bare = true
	_speed_btn.font_size = 18
	_speed_btn.custom_minimum_size = Vector2(178, 40)
	_speed_btn.size = Vector2(178, 40)
	_speed_btn.text = _speed_text()
	_speed_btn.pressed.connect(func() -> void:
		SfxNode.play("ui_click")
		GameSettings.cycle_speed()
		_speed_btn.text = _speed_text())
	add_child(_speed_btn)

	# 终端窗口模式：铺满屏幕（最大化） / 全屏
	_win_btn = JuiceButton.new()
	_win_btn.name = "WindowModeButton"
	_win_btn.bare = true
	_win_btn.font_size = 18
	_win_btn.custom_minimum_size = Vector2(178, 40)
	_win_btn.size = Vector2(178, 40)
	_win_btn.text = _win_text()
	_win_btn.pressed.connect(func() -> void:
		SfxNode.play("ui_click")
		GameSettings.toggle_window_mode()
		_win_btn.text = _win_text())
	add_child(_win_btn)

	# AI 接入：玩家自填 Base URL / Key / 协议 / 模型（2026-11-03 LLM 接入）
	_ai_btn = JuiceButton.new()
	_ai_btn.name = "AiSettingsButton"
	_ai_btn.bare = true
	_ai_btn.font_size = 18
	_ai_btn.custom_minimum_size = Vector2(178, 40)
	_ai_btn.size = Vector2(178, 40)
	_ai_btn.text = "AI 接入"
	_ai_btn.pressed.connect(func() -> void:
		SfxNode.play("ui_click")
		open_ai_settings.emit())
	add_child(_ai_btn)

	# 面板底部一行操作提示（不抢戏，但新手看得见）
	_hint = UiKit.dim("纯鼠标操作 ｜ 点手牌选牌 → 点「运行」出牌", 15, Color(0.45, 0.55, 0.68))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)


## 速度按钮文案
func _speed_text() -> String:
	return "打字速度：%s" % GameSettings.speed_name()


## 终端窗口模式文案
func _win_text() -> String:
	return "窗口：%s" % GameSettings.window_mode_name()


## 一个「图标 + 说明」的小单元
func _feature(icon_name: String, caption: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var ic := UiArt.icon(icon_name, 88.0)
	if ic != null:
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ic)
	else:
		var ph := Control.new()
		ph.custom_minimum_size = Vector2(88, 88)
		col.add_child(ph)

	var lb := UiKit.dim(caption, 16, UiKit.TEXT_DIM)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(lb)
	return col


# ── 页脚 ──────────────────────────────────────────────
func _build_footer() -> void:
	_foot_left = UiKit.dim("v0.9 ｜ Godot 4.7.2", UiKit.FS_XS)
	_foot_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_foot_left)

	_foot_right = UiKit.dim("© 2026 代码擂台 CODE ARENA", UiKit.FS_XS)
	_foot_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_foot_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_foot_right)


## 测试/目检用：主按钮的屏幕中心
func debug_start_button_center() -> Vector2:
	if _start_btn == null:
		return Vector2.ZERO
	return _start_btn.global_position + _start_btn.size * 0.5


## 测试/目检用：把主按钮切到悬停态（--shot=menuhover 用）
func debug_hover_start() -> void:
	if _start_btn != null:
		_start_btn.debug_set_hover(true)


# ── 布局 ──────────────────────────────────────────────
func _layout() -> void:
	var s := size
	if s.x < 1.0 or s.y < 1.0:
		return

	# 面板：宽度吃掉屏宽的 65%，高度按 2:1 走
	var pw := roundf(minf(1040.0, s.x * 0.65))
	var ph := roundf(minf(520.0, s.y * 0.58))
	var px := roundf((s.x - pw) * 0.5)
	var py := roundf(s.y * 0.335)
	_rect_panel = Rect2(px, py, pw, ph)

	if _panel != null:
		_panel.position = _rect_panel.position
		_panel.size = _rect_panel.size
	if _shadow != null:
		_shadow.position = _rect_panel.position + Vector2(10, 14)
		_shadow.size = _rect_panel.size

	# 牌匾：用资产的整数倍尺寸（非整数会拉出粗细不一的像素格），压在面板上沿
	var plaque_sz := UiArt.display_size("plaque")
	var plaque_w := plaque_sz.x
	var plaque_h := plaque_sz.y
	if _plaque != null:
		# 必须同时改 custom_minimum_size：Control 的 size 会被它顶住，不改就一直是旧尺寸
		_plaque.custom_minimum_size = Vector2(plaque_w, plaque_h)
		_plaque.size = Vector2(plaque_w, plaque_h)
		_plaque.position = Vector2(roundf((s.x - plaque_w) * 0.5),
				roundf(py - plaque_h + 22.0))
		# 牌匾大字随牌匾一起缩放（保证字始终撑满内腔）
		_plaque.cn_size = int(roundf(plaque_w * 0.115))
		_plaque.en_size = int(roundf(plaque_w * 0.042))

	# 面板内腔的纵向节拍（相对面板顶 py；面板 520 高）
	var cx := roundf(s.x * 0.5)
	if _kicker != null:
		_kicker.position = Vector2(px, py + 46.0)
		_kicker.size = Vector2(pw, 32)

	var feat_w := 760.0
	if _feat_row != null:
		_feat_row.position = Vector2(roundf(cx - feat_w * 0.5), py + 82.0)
		_feat_row.size = Vector2(feat_w, 124)

	if _start_btn != null:
		var bs := UiArt.display_size("btn")
		_start_btn.position = Vector2(roundf(cx - bs.x * 0.5), py + 220.0)
		_start_btn.size = bs

	if _quit_btn != null:
		_speed_btn.position = Vector2(roundf(cx - 273.0), py + 452.0)
	_win_btn.position = Vector2(roundf(cx - 89.0), py + 452.0)
	_ai_btn.position = Vector2(roundf(cx + 95.0), py + 452.0)
	_quit_btn.position = Vector2(roundf(cx - 180.0), py + 404.0)

	if _hint != null:
		_hint.position = Vector2(px, py + 506.0)
		_hint.size = Vector2(pw, 22)

	_foot_left.position = Vector2(px, s.y - 34.0)
	_foot_left.size = Vector2(320, 20)
	_foot_right.position = Vector2(px + pw - 320.0, s.y - 34.0)
	_foot_right.size = Vector2(320, 20)

	if _bg_fx:
		_bg_fx.setup(s)


# ══════════════════════════════════════════════════════
#  AI 接入设置面板（模态；main.gd 也可以直接实例化打开）
#  · 字段失焦 / 切换即存：走 LLMConfig.save（Key 自动 XOR+base64）
#  · 刷新：LLMProtocol.models_url + parse_models（anthropic 无列表端点 → 手填）
#  · 测试：1-token ping（LLMClient，8s 超时），红绿字反馈
# ══════════════════════════════════════════════════════
class LLMSettingsPanel extends Control:
	signal closed
	signal saved

	var cfg: LLMConfig = null
	## 测试可注入临时路径；游戏内用 LLMConfig.CONFIG_PATH
	var save_path := LLMConfig.CONFIG_PATH

	var _base_edit: LineEdit
	var _key_edit: LineEdit
	var _eye_btn: TextureButton
	var _ai_opp_btn: CheckButton
	var _img_enabled_btn: CheckButton
	var _img_model_edit: LineEdit
	var _img_base_edit: LineEdit
	var _img_key_edit: LineEdit
	var _protocol_btn: OptionButton
	var _model_edit: LineEdit
	var _model_menu: MenuButton
	var _refresh_btn: Button
	var _temp_slider: HSlider
	var _temp_val: Label
	var _enabled_btn: CheckButton
	var _test_btn: Button
	var _feedback: Label
	var _models: Array[String] = []
	var _closed := false
	var _loading := false


	func setup(config: LLMConfig, path: String = "") -> void:
		cfg = config
		if path != "":
			save_path = path


	func _ready() -> void:
		if cfg == null:
			cfg = LLMConfig.load_from_disk(save_path)
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_preset(Control.PRESET_FULL_RECT)
		_build()
		_load_fields()


	func _build() -> void:
		var veil := ColorRect.new()
		veil.color = Color(0.02, 0.03, 0.05, 0.84)
		veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		veil.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(veil)

		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)

		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(880, 0)
		box.add_theme_stylebox_override("panel",
				UiKit.flat(UiKit.PANEL, UiKit.LINE, 2, UiKit.SP_5))
		center.add_child(box)

		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", UiKit.SP_3)
		box.add_child(v)

		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", UiKit.SP_3)
		v.add_child(head)
		var title := UiKit.title("AI 接入 · 模型配置", UiKit.FS_M)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var close_btn := UiKit.button("关闭", UiKit.FS_XS)
		close_btn.custom_minimum_size = Vector2(96, 40)
		close_btn.pressed.connect(_close)
		head.add_child(close_btn)

		var sub := UiKit.dim("填入自己的 API。字段失焦或切换即保存；Key 只做防围观混淆。",
				UiKit.FS_XS)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sub)

		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", UiKit.SP_3)
		grid.add_theme_constant_override("v_separation", UiKit.SP_2)
		v.add_child(grid)

		_base_edit = _line_edit("https://api.deepseek.com")
		_base_edit.focus_exited.connect(_save)
		_row(grid, "Base URL", _base_edit)

		_key_edit = _line_edit("sk-...（本地模型可留空）")
		_key_edit.secret = true
		_key_edit.focus_exited.connect(_save)
		# Key 尾巴上的眼睛：点一下切换 明文/圆点（2026-11-04 主人钦定）
		var key_row := HBoxContainer.new()
		key_row.add_theme_constant_override("separation", UiKit.SP_2)
		key_row.add_child(_key_edit)
		_eye_btn = TextureButton.new()
		_eye_btn.texture_normal = _eye_texture(false)      # 初始闭眼（key 隐藏）
		_eye_btn.custom_minimum_size = Vector2(46, 40)
		_eye_btn.toggle_mode = true
		_eye_btn.tooltip_text = "显示 / 隐藏 Key"
		_eye_btn.toggled.connect(func(on: bool) -> void:
			_key_edit.secret = not on
			_eye_btn.texture_normal = _eye_texture(on))
		key_row.add_child(_eye_btn)
		_row(grid, "API Key", key_row)

		_protocol_btn = OptionButton.new()
		_protocol_btn.custom_minimum_size = Vector2(0, 40)
		_protocol_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for p in LLMConfig.PROTOCOLS:
			_protocol_btn.add_item(String(LLMConfig.PROTOCOL_LABELS.get(p, p)))
		_protocol_btn.item_selected.connect(_on_protocol_selected)
		_row(grid, "协议", _protocol_btn)

		var model_row := HBoxContainer.new()
		model_row.add_theme_constant_override("separation", UiKit.SP_2)
		_model_edit = _line_edit("模型名，可手填")
		_model_edit.focus_exited.connect(_save)
		model_row.add_child(_model_edit)
		_model_menu = MenuButton.new()
		_model_menu.text = "模型 ▾"
		_model_menu.custom_minimum_size = Vector2(104, 40)
		_model_menu.get_popup().id_pressed.connect(_on_model_pick)
		model_row.add_child(_model_menu)
		_refresh_btn = UiKit.button("刷新", UiKit.FS_XS)
		_refresh_btn.custom_minimum_size = Vector2(96, 40)
		_refresh_btn.pressed.connect(_refresh_models)
		model_row.add_child(_refresh_btn)
		_row(grid, "模型", model_row)

		var temp_row := HBoxContainer.new()
		temp_row.add_theme_constant_override("separation", UiKit.SP_2)
		_temp_slider = HSlider.new()
		_temp_slider.min_value = LLMConfig.TEMP_MIN
		_temp_slider.max_value = LLMConfig.TEMP_MAX
		_temp_slider.step = 0.1
		_temp_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_temp_slider.custom_minimum_size = Vector2(0, 40)
		_temp_slider.value_changed.connect(_on_temp_changed)
		_temp_slider.drag_ended.connect(_on_temp_drag_ended)
		temp_row.add_child(_temp_slider)
		_temp_val = UiKit.label("0.5", UiKit.FS_XS, UiKit.ACCENT)
		_temp_val.custom_minimum_size = Vector2(48, 0)
		temp_row.add_child(_temp_val)
		_row(grid, "事件温度", temp_row)

		_enabled_btn = CheckButton.new()
		_enabled_btn.text = "启用 AI 接入（事件 / 对手 / 小鲸）"
		_enabled_btn.toggled.connect(func(_on: bool) -> void: _save())
		v.add_child(_enabled_btn)

		_ai_opp_btn = CheckButton.new()
		_ai_opp_btn.text = "敌人使用 AI 决策（消耗 token，默认关走本地规则）"
		_ai_opp_btn.toggled.connect(func(_on: bool) -> void: _save())
		v.add_child(_ai_opp_btn)

		## ── AI 作画（许愿卡）配置（2026-11-04）──
		v.add_child(UiKit.label("AI 作画（许愿卡）", UiKit.FS_S, Color(0.55, 0.85, 1.0)))
		_img_enabled_btn = CheckButton.new()
		_img_enabled_btn.text = "启用 AI 作画（战斗左下角「愿」按钮）"
		_img_enabled_btn.toggled.connect(func(_on: bool) -> void: _save())
		v.add_child(_img_enabled_btn)
		_img_model_edit = _line_edit("生图模型（例：gpt-image-2.5-1k）")
		_img_model_edit.focus_exited.connect(_save)
		_row(grid, "作画模型", _img_model_edit)
		_img_base_edit = _line_edit("留空 = 用上面的 Base URL")
		_img_base_edit.focus_exited.connect(_save)
		_row(grid, "作画端点", _img_base_edit)
		_img_key_edit = _line_edit("生图 Key（留空 = 用上面的 API Key）")
		_img_key_edit.secret = true
		_img_key_edit.focus_exited.connect(_save)
		_row(grid, "作画 Key", _img_key_edit)

		var test_row := HBoxContainer.new()
		test_row.add_theme_constant_override("separation", UiKit.SP_3)
		v.add_child(test_row)
		_test_btn = UiKit.button("测试连接", UiKit.FS_XS, true)
		_test_btn.custom_minimum_size = Vector2(148, 44)
		_test_btn.pressed.connect(_test_connection)
		test_row.add_child(_test_btn)
		_feedback = UiKit.dim("", UiKit.FS_XS)
		_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		test_row.add_child(_feedback)

		## 从 ZCode 的 goat 分组一键导入（2026-11-03）
		var import_row := HBoxContainer.new()
		import_row.add_theme_constant_override("separation", UiKit.SP_3)
		v.add_child(import_row)
		var import_btn := UiKit.button("从 ZCode 导入 goat", UiKit.FS_XS)
		import_btn.custom_minimum_size = Vector2(180, 40)
		import_btn.pressed.connect(_import_zcode)
		import_row.add_child(import_btn)

		var foot := UiKit.dim("保存到 %s ｜ 关闭后立即生效" % save_path, UiKit.FS_XS,
				UiKit.TEXT_DIM)
		foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(foot)


	func _line_edit(placeholder: String) -> LineEdit:
		var e := LineEdit.new()
		e.placeholder_text = placeholder
		e.custom_minimum_size = Vector2(0, 40)
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return e


	## 程序化像素眼睛（睁/闭两态）：Key 显隐按钮图标
	func _eye_texture(open_eye: bool) -> ImageTexture:
		var img := Image.create_empty(24, 24, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var col := Color(0.75, 0.88, 1.0)
		if open_eye:
			for x in range(3, 21):
				var dx := float(x - 12) / 9.0
				var h := int(round(5.0 * sqrt(maxf(0.0, 1.0 - dx * dx))))
				img.set_pixel(x, 12 - h, col)
				img.set_pixel(x, 12 + h, col)
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					img.set_pixel(12 + dx, 12 + dy, col)
		else:
			for x in range(4, 20):
				var dx2 := float(x - 12) / 8.0
				var y := 10 + int(round(3.0 * (1.0 - dx2 * dx2)))
				img.set_pixel(x, y, col)
		return ImageTexture.create_from_image(img)


	func _row(grid: GridContainer, label_text: String, control: Control) -> void:
		var l := UiKit.label(label_text, UiKit.FS_XS, UiKit.TEXT_DIM)
		l.custom_minimum_size = Vector2(132, 0)
		grid.add_child(l)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(control)


	## 从 ZCode 的 goat 分组一键导入（2026-11-03）
	func _import_zcode() -> void:
		var r := LLMConfig.import_zcode_provider()
		if not bool(r.get("ok", false)):
			_feedback.text = "导入失败：%s" % String(r.get("error", "未知"))
			return
		cfg.base_url = String(r.get("base_url", ""))
		cfg.protocol = String(r.get("protocol", "anthropic"))
		cfg.api_key = String(r.get("api_key", ""))
		cfg.model = String(r.get("model", ""))
		cfg.save(save_path)
		_load_fields()
		_feedback.text = "已导入 goat-claude：%s ｜ key %s" % [
			String(r.get("model", "")), String(r.get("key_tail", ""))]
		saved.emit()


	func _load_fields() -> void:
		_loading = true
		_base_edit.text = cfg.base_url if not cfg.base_url.strip_edges().is_empty() \
				else cfg.default_base_for(cfg.protocol)
		_key_edit.text = cfg.api_key
		_model_edit.text = cfg.model
		var pidx := LLMConfig.PROTOCOLS.find(cfg.protocol)
		_protocol_btn.selected = maxi(0, pidx)
		_temp_slider.value = cfg.temp_for("event")
		_temp_val.text = "%.1f" % _temp_slider.value
		_enabled_btn.button_pressed = cfg.enabled
		_ai_opp_btn.button_pressed = cfg.ai_opponent
		_img_enabled_btn.button_pressed = cfg.image_enabled
		_img_model_edit.text = cfg.image_model
		_img_base_edit.text = cfg.image_base
		_img_key_edit.text = cfg.image_key
		_loading = false


	func _collect() -> void:
		cfg.base_url = _base_edit.text.strip_edges()
		cfg.api_key = _key_edit.text
		cfg.model = _model_edit.text.strip_edges()
		cfg.ai_opponent = _ai_opp_btn.button_pressed
		cfg.image_enabled = _img_enabled_btn.button_pressed
		cfg.image_model = _img_model_edit.text.strip_edges()
		cfg.image_base = _img_base_edit.text.strip_edges()
		cfg.image_key = _img_key_edit.text
		var pidx := _protocol_btn.selected
		if pidx >= 0 and pidx < LLMConfig.PROTOCOLS.size():
			cfg.protocol = String(LLMConfig.PROTOCOLS[pidx])
		cfg.temperatures["event"] = clampf(
				snappedf(_temp_slider.value, 0.1), LLMConfig.TEMP_MIN, LLMConfig.TEMP_MAX)
		cfg.enabled = _enabled_btn.button_pressed


	func _save() -> void:
		if cfg == null or _loading:
			return
		_collect()
		cfg.save(save_path)
		_temp_val.text = "%.1f" % float(cfg.temperatures.get("event", 0.5))
		saved.emit()


	func _on_protocol_selected(idx: int) -> void:
		var old_default := cfg.default_base_for(cfg.protocol)
		var cur := _base_edit.text.strip_edges()
		if idx >= 0 and idx < LLMConfig.PROTOCOLS.size():
			cfg.protocol = String(LLMConfig.PROTOCOLS[idx])
		if cur.is_empty() or cur == old_default:
			_base_edit.text = cfg.default_base_for(cfg.protocol)
		_populate_models([])
		_save()


	func _on_temp_changed(v: float) -> void:
		_temp_val.text = "%.1f" % v


	func _on_temp_drag_ended(_changed: bool) -> void:
		_save()


	func _on_model_pick(id: int) -> void:
		if id >= 0 and id < _models.size():
			_model_edit.text = _models[id]
			_save()


	func _populate_models(models: Array) -> void:
		_models.clear()
		var pop := _model_menu.get_popup()
		pop.clear()
		for m in models:
			_models.append(String(m))
		for i in _models.size():
			pop.add_item(_models[i], i)


	## 拉取模型列表；as_test=true 时反馈按「测试」口径。
	func _refresh_models(as_test: bool = false) -> void:
		_collect()
		if not LLMProtocol.supports_model_list(cfg.protocol):
			_set_feedback("该协议没有模型列表端点，请手填模型名。", UiKit.GOLD)
			return
		var url := LLMProtocol.models_url(cfg.protocol, cfg.effective_base(), cfg.api_key)
		if url.is_empty():
			_set_feedback("Base URL 为空，先填地址。", UiKit.DANGER)
			return
		var http := HTTPRequest.new()
		http.timeout = 8.0
		add_child(http)
		http.request_completed.connect(_on_models_done.bind(http, as_test))
		_refresh_btn.disabled = true
		_test_btn.disabled = true
		_set_feedback("正在拉取模型列表…", UiKit.TEXT_DIM)
		var err := http.request(url, LLMProtocol.headers(cfg.protocol, cfg.api_key),
				HTTPClient.METHOD_GET)
		if err != OK:
			_refresh_btn.disabled = false
			_test_btn.disabled = false
			http.queue_free()
			_set_feedback("请求发不出去（%s）。" % error_string(err), UiKit.DANGER)


	func _on_models_done(result: int, code: int, _headers: PackedStringArray,
			body: PackedByteArray, http: HTTPRequest, as_test: bool) -> void:
		http.queue_free()
		_refresh_btn.disabled = false
		_test_btn.disabled = false
		if result != HTTPRequest.RESULT_SUCCESS:
			_set_feedback("网络失败（%s）。" % error_string(result), UiKit.DANGER)
			return
		if code < 200 or code >= 300:
			_set_feedback("HTTP %d：%s" % [code, _short(body.get_string_from_utf8())],
					UiKit.DANGER)
			return
		var models := LLMProtocol.parse_models(cfg.protocol, body.get_string_from_utf8())
		if models.is_empty():
			_set_feedback("连上了，但没解析到模型列表。", UiKit.GOLD)
			return
		_populate_models(models)
		if _model_edit.text.strip_edges().is_empty():
			_model_edit.text = _models[0]
			_save()
		if as_test:
			_set_feedback("连接成功：%d 个模型可用。" % _models.size(), UiKit.GOOD)
		else:
			_set_feedback("已拉取 %d 个模型，点「模型 ▾」选。" % _models.size(), UiKit.GOOD)


	## 测试：优先 1-token ping；没填模型且协议支持列表时退回拉列表。
	func _test_connection() -> void:
		_collect()
		_set_feedback("测试中…", UiKit.TEXT_DIM)
		if cfg.model.strip_edges().is_empty():
			if LLMProtocol.supports_model_list(cfg.protocol):
				_refresh_models(true)
				return
			_set_feedback("先填模型名再测试。", UiKit.DANGER)
			return
		var probe := LLMConfig.new()
		probe.apply_dict(cfg.to_dict())
		probe.enabled = true
		if probe.base_url.strip_edges().is_empty():
			probe.base_url = probe.default_base_for(probe.protocol)
		var cli := LLMClient.new()
		add_child(cli)
		cli.setup(probe)
		_test_btn.disabled = true
		## max_tokens 不能给 1：推理模型（如 deepseek-v4.1-flash）会把 token 全花在
		## 思维链上、content 为空 → 客户端判 "empty" 假阴性（2026-11-04 实测踩坑）。
		cli.request("event", [{"role": "user", "content": "ping"}],
				_on_test_done.bind(cli), {"max_tokens": 512, "timeout_s": 25.0})


	func _on_test_done(r: Dictionary, cli: LLMClient) -> void:
		cli.queue_free()
		_test_btn.disabled = false
		if bool(r.get("ok", false)):
			_set_feedback("连接成功：%s" % _short(String(r.get("text", ""))), UiKit.GOOD)
		else:
			var reason := String(r.get("reason", "unknown"))
			if reason == "empty":
				_set_feedback("连接失败：网关通了但正文为空——推理模型思考吃 token，再点一次或换非推理模型", UiKit.DANGER)
			else:
				_set_feedback("连接失败：%s" % reason, UiKit.DANGER)


	func _short(text: String) -> String:
		var t := text.strip_edges().replace("\n", " ")
		return t.substr(0, 80)


	func _set_feedback(text: String, color: Color) -> void:
		_feedback.text = text
		_feedback.add_theme_color_override("font_color", color)


	func _close() -> void:
		if _closed:
			return
		_closed = true
		closed.emit()
		queue_free()


	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close()
