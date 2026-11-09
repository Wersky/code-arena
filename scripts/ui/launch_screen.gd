class_name LaunchScreen
extends Control
## 新版启动流程（主人 2026-10-30 手绘稿）：
##   状态A  全屏黑，中间只有一个白框像素按钮「初始化」
##   状态B  点初始化 → 底部居中展开 Agent 对话框 + 左侧滑入侧边栏（技能 / MCP）
##          对话框右下角是纯图标发送键，旁边是模型下拉（DeepSeek/Grok/GPT/千问）
##   发送   → launched(ai_id)（2026-11-09 起：选角已移到独立界面，输入框可空着直接发）
##            main.gd 收到后播全屏马赛克 → 切 CharacterSelectScreen 选角 → 开始游戏才进战斗
##
## 布局基准：画布 1600x900。像素风走 PixelTheme 的字体。

signal launched(ai_id: String)
## 对话框展开完成（main.gd 用它决定 AI 接入 / Demo 入口何时出现）
signal dialog_expanded
## 左下角图标入口
signal ai_settings_requested
signal demo_requested
signal patch_demo_requested

## 下拉项顺序按主人给的：DeepSeek、Grok、GPT、千问
const MODELS := [
	["deepdeek", "DeepSeek", 0],
	["grock", "Grok", 0],
	["chatppt", "GPT", 0],
	["kweno", "千问", 0],
]
const MCP_ITEMS := ["文件系统", "浏览器", "终端", "联网搜索"]

var _boot_btn: Button
var _dialog: Control
var _sidebar: Control
var _input: LineEdit
var _send_btn: Button
var _hint: Label
var _skill_list: Label
var _skill_title: Button
var _mcp_title: Button
var _mcp_box: VBoxContainer
var _model_idx := 0
var _expanded := false


func _ready() -> void:
	# BGM：旧主菜单是唯一的播放入口，换成启动界面后这里必须接上，否则全局静音
	SfxNode.music("bgm_gemini2")
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 终端代码雨背景（2026-11-07 主人要求）：主界面全程下雨，
	# 初始化态 → Agent 对话框 → 侧边栏各态都铺在黑底之上
	var rain := TerminalRain.new()
	rain.name = "TerminalRainBg"
	rain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rain)

	_boot_btn = Button.new()
	_boot_btn.text = "初始化"
	_boot_btn.flat = true
	_boot_btn.add_theme_font_override("font", PixelTheme.font())
	_boot_btn.add_theme_font_size_override("font_size", 44)
	_boot_btn.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	_boot_btn.add_theme_color_override("font_hover_color", Color(0.55, 0.85, 1.0))
	_boot_btn.add_theme_color_override("font_pressed_color", Color(0.35, 0.65, 0.9))
	_boot_btn.add_theme_stylebox_override("normal", _frame(Color(1, 1, 1, 0.92)))
	_boot_btn.add_theme_stylebox_override("hover", _frame(Color(0.55, 0.85, 1.0)))
	_boot_btn.add_theme_stylebox_override("pressed", _frame(Color(0.35, 0.65, 0.9)))
	_boot_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_boot_btn.custom_minimum_size = Vector2(260, 96)
	# 只用绝对坐标，**不走锚点预设**：PRESET_CENTER 的 offset 在全屏模式首次布局前
	# 会按 0 尺寸计算，等父区域变成 1600x900 后按钮被推到右下角（实测踩坑）。
	# 本项目画布固定 1600x900 + canvas_items 缩放，绝对坐标天然与分辨率无关。
	_boot_btn.position = Vector2(670.0, 402.0)
	_boot_btn.size = Vector2(260.0, 96.0)
	_boot_btn.pressed.connect(expand)
	add_child(_boot_btn)


## 点「初始化」：展开对话框 + 侧边栏（public，截图自检也要调）
func expand() -> void:
	if _expanded:
		return
	_expanded = true
	_boot_btn.queue_free()
	_build_dialog()
	_build_sidebar()
	_apply_model()
	_dialog.modulate.a = 0.0
	_dialog.position.y += 190.0
	_sidebar.modulate.a = 0.0
	_sidebar.position.x -= 250.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_dialog, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_dialog, "position:y", _dialog.position.y - 190.0, 0.55) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sidebar, "modulate:a", 1.0, 0.5)
	tw.tween_property(_sidebar, "position:x", _sidebar.position.x + 250.0, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_build_icon_entries()
	dialog_expanded.emit()


func _frame(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.0)
	sb.border_color = c
	sb.set_border_width_all(3)
	return sb


func _panel(c: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb


func _build_dialog() -> void:
	_dialog = PanelContainer.new()
	_dialog.name = "AgentDialog"
	_dialog.add_theme_stylebox_override("panel",
			_panel(Color(0.055, 0.075, 0.12), Color(0.22, 0.32, 0.5)))
	_dialog.custom_minimum_size = Vector2(880, 230)
	_dialog.position = Vector2(280, 670)
	_dialog.size = Vector2(880, 230)
	add_child(_dialog)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_dialog.add_child(v)

	var log := Label.new()
	log.text = "会话已建立。选择模型并下达指令。"
	log.add_theme_font_override("font", PixelTheme.font())
	log.add_theme_font_size_override("font_size", 16)
	log.add_theme_color_override("font_color", Color(0.55, 0.68, 0.85))
	v.add_child(log)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)

	_input = LineEdit.new()
	_input.placeholder_text = "向 AI 娘下达指令…"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_override("font", PixelTheme.font())
	_input.add_theme_font_size_override("font_size", 20)
	_input.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_input.add_theme_stylebox_override("normal",
			_panel(Color(0.03, 0.045, 0.08), Color(0.18, 0.26, 0.42)))
	_input.add_theme_stylebox_override("focus",
			_panel(Color(0.03, 0.045, 0.08), Color(0.4, 0.7, 1.0)))
	_input.text_submitted.connect(func(_t: String) -> void: _send())
	row.add_child(_input)

	_send_btn = Button.new()
	_send_btn.custom_minimum_size = Vector2(52, 44)
	_send_btn.icon = _send_icon()
	_send_btn.add_theme_stylebox_override("normal", _frame(Color(0.55, 0.85, 1.0)))
	_send_btn.add_theme_stylebox_override("hover", _frame(Color(0.8, 0.95, 1.0)))
	_send_btn.add_theme_stylebox_override("pressed", _frame(Color(0.3, 0.6, 0.9)))
	_send_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_send_btn.pressed.connect(_send)
	row.add_child(_send_btn)

	_hint = Label.new()
	_hint.add_theme_font_override("font", PixelTheme.font())
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	v.add_child(_hint)


func _build_sidebar() -> void:
	_sidebar = PanelContainer.new()
	_sidebar.name = "SidePanel"
	_sidebar.add_theme_stylebox_override("panel",
			_panel(Color(0.045, 0.06, 0.10), Color(0.20, 0.28, 0.45)))
	_sidebar.custom_minimum_size = Vector2(232, 0)
	_sidebar.position = Vector2(24, 0)
	_sidebar.size = Vector2(232, 900)
	add_child(_sidebar)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_sidebar.add_child(v)
	# 左上角模型铭牌已移除（2026-11-09 主人要求：选角不在主界面，模型名没意义了）
	# ── 技能（下拉）──
	_skill_title = Button.new()
	_skill_title.text = "▸ 技能"
	_skill_title.flat = true
	_skill_title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_skill_title.add_theme_font_override("font", PixelTheme.font())
	_skill_title.add_theme_font_size_override("font_size", 20)
	_skill_title.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	_skill_title.add_theme_color_override("font_hover_color", Color(0.85, 0.95, 1.0))
	_skill_title.pressed.connect(_toggle_skill)
	v.add_child(_skill_title)
	_skill_list = Label.new()
	_skill_list.add_theme_font_override("font", PixelTheme.font())
	_skill_list.add_theme_font_size_override("font_size", 16)
	_skill_list.add_theme_color_override("font_color", Color(0.72, 0.8, 0.92))
	_skill_list.visible = false
	v.add_child(_skill_list)
	v.add_child(UiKit.rule())

	# ── MCP（下拉）──
	_mcp_title = Button.new()
	_mcp_title.text = "▸ MCP"
	_mcp_title.flat = true
	_mcp_title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_mcp_title.add_theme_font_override("font", PixelTheme.font())
	_mcp_title.add_theme_font_size_override("font_size", 20)
	_mcp_title.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	_mcp_title.add_theme_color_override("font_hover_color", Color(0.85, 0.95, 1.0))
	_mcp_title.pressed.connect(_toggle_mcp)
	v.add_child(_mcp_title)
	_mcp_box = VBoxContainer.new()
	_mcp_box.add_theme_constant_override("separation", 4)
	_mcp_box.visible = false
	v.add_child(_mcp_box)
	for item in MCP_ITEMS:
		var l := Label.new()
		l.text = "  · " + item
		l.add_theme_font_override("font", PixelTheme.font())
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(0.72, 0.8, 0.92))
		_mcp_box.add_child(l)


func _toggle_skill() -> void:
	if _skill_list == null:
		return
	_skill_list.visible = not _skill_list.visible
	_skill_title.text = ("▾ 技能" if _skill_list.visible else "▸ 技能")


func _toggle_mcp() -> void:
	if _mcp_box == null:
		return
	_mcp_box.visible = not _mcp_box.visible
	_mcp_title.text = ("▾ MCP" if _mcp_box.visible else "▸ MCP")


## 左下角图标入口：绑定在 GUI 层（侧栏之后创建、置顶），跟随对话框展开出现。
## 位置对齐战斗界面牌堆图标右侧（牌堆 x=36..92, y=750）。
func _build_icon_entries() -> void:
	_make_icon_entry("AiSettingsEntry", "res://assets/art/ui-ai-access.png",
			"模型接入", Vector2(100, 750), ai_settings_requested)
	_make_icon_entry("LlmDemoEntry", "res://assets/art/ui-demo.png",
			"demo", Vector2(164, 750), demo_requested)
	_make_icon_entry("PatchDemoEntry", "res://assets/art/ui-patch-demo.png",
			"更新演示", Vector2(292, 750), patch_demo_requested)


func _make_icon_entry(node_name: String, tex_path: String, tip: String,
		pos: Vector2, sig: Signal) -> void:
	var btn := TextureButton.new()
	btn.name = node_name
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(tex_path):
		btn.texture_normal = load(tex_path)
	btn.position = pos
	btn.size = Vector2(56, 56)
	btn.tooltip_text = tip
	btn.pressed.connect(func() -> void: sig.emit())
	add_child(btn)
	btn.move_to_front()


## 侧边栏技能列表（模型选择已移到选角界面，这里只按默认角色填技能示例）
func _apply_model() -> void:
	if _skill_list == null:
		return
	var ai := AiPool.get_ai(String(MODELS[_model_idx][0]))
	_skill_list.text = ""
	if ai != null:
		for sk in ai.taste_rules:
			_skill_list.text += "  · " + sk + "\n"


func run_level() -> int:
	return 0        ## 启动阶段还没开Run；解锁判定在 main.gd 里按实际进度复核


func _send() -> void:
	var id := String(MODELS[_model_idx][0])
	var need := int(MODELS[_model_idx][2])
	if run_level() < need:
		_hint.text = "「%s」还没解锁，先通关 %d 关。" % [String(MODELS[_model_idx][1]), need]
		return
	# 2026-11-09 主人要求：输入框空着也能直接发送 → 进选角
	launched.emit(id)


## 像素风「发送」图标：程序化画一枚右向箭头，不依赖外部素材
func _send_icon() -> ImageTexture:
	var sz := 22
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in range(2, 20):
		var t := float(y - 2) / 17.0
		var x_end := int(round(3.0 + t * 16.0))
		for x in range(3, maxi(4, x_end)):
			img.set_pixel(x, y, Color(0.62, 0.88, 1.0, 1.0))
	return ImageTexture.create_from_image(img)
