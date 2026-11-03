class_name LaunchScreen
extends Control
## 新版启动流程（主人 2026-10-30 手绘稿）：
##   状态A  全屏黑，中间只有一个白框像素按钮「初始化」
##   状态B  点初始化 → 底部居中展开 Agent 对话框 + 左侧滑入侧边栏（技能 / MCP）
##          对话框右下角是纯图标发送键，旁边是模型下拉（DeepSeek/Grok/GPT/千问）
##   发送   → launched(ai_id)，由 main.gd 接管进终端进场与战斗
##
## 布局基准：画布 1600x900。像素风走 PixelTheme 的字体。

signal launched(ai_id: String)

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
var _model_btn: OptionButton
var _send_btn: Button
var _portrait: TextureRect
var _hint: Label
var _skill_list: Label
var _model_idx := 0
var _expanded := false


func _ready() -> void:
	# BGM：旧主菜单是唯一的播放入口，换成启动界面后这里必须接上，否则全局静音
	SfxNode.music("bgm_gemini2")
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

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
	_build_portrait()
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
	_dialog.custom_minimum_size = Vector2(1080, 230)
	_dialog.position = Vector2(306, 640)
	_dialog.size = Vector2(1080, 230)
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

	_model_btn = OptionButton.new()
	_model_btn.add_theme_font_override("font", PixelTheme.font())
	_model_btn.add_theme_font_size_override("font_size", 18)
	_model_btn.custom_minimum_size = Vector2(150, 0)
	for m in MODELS:
		_model_btn.add_item(String(m[1]))
	_model_btn.item_selected.connect(func(i: int) -> void:
		_model_idx = i
		_apply_model())
	row.add_child(_model_btn)

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
	_sidebar.custom_minimum_size = Vector2(230, 0)
	_sidebar.position = Vector2(56, 0)
	_sidebar.size = Vector2(232, 900)
	add_child(_sidebar)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_sidebar.add_child(v)
	var t1 := Label.new()
	t1.text = "▸ 技能"
	t1.add_theme_font_override("font", PixelTheme.font())
	t1.add_theme_font_size_override("font_size", 20)
	t1.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	v.add_child(t1)
	_skill_list = Label.new()
	_skill_list.add_theme_font_override("font", PixelTheme.font())
	_skill_list.add_theme_font_size_override("font_size", 16)
	_skill_list.add_theme_color_override("font_color", Color(0.72, 0.8, 0.92))
	v.add_child(_skill_list)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	v.add_child(sp)
	var t2 := Label.new()
	t2.text = "▸ MCP"
	t2.add_theme_font_override("font", PixelTheme.font())
	t2.add_theme_font_size_override("font_size", 20)
	t2.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	v.add_child(t2)
	for item in MCP_ITEMS:
		var l := Label.new()
		l.text = "  · " + item
		l.add_theme_font_override("font", PixelTheme.font())
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(0.72, 0.8, 0.92))
		v.add_child(l)


func _build_portrait() -> void:
	_portrait = TextureRect.new()
	_portrait.name = "ModelPortrait"
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.position = Vector2(1210, 210)
	_portrait.size = Vector2(240, 420)
	add_child(_portrait)


## 模型切换：换立绘 + 换侧边栏技能列表 + 未解锁提示
func _apply_model() -> void:
	var id := String(MODELS[_model_idx][0])
	var need := int(MODELS[_model_idx][2])
	var ai := AiPool.get_ai(id)
	var tex := load("res://assets/art/select/%s.png" % id) as Texture2D
	if tex == null:
		tex = load("res://assets/art/ai-%s.png" % id) as Texture2D
	_portrait.texture = tex
	_skill_list.text = ""
	if ai != null:
		for sk in ai.taste_rules:
			_skill_list.text += "  · " + sk + "\n"
	var locked := run_level() < need
	if locked:
		_hint.text = "「%s」未解锁：通过第 %d 关后加入" % [String(MODELS[_model_idx][1]), need + 1]
	else:
		_hint.text = ""
	_model_btn.set_item_disabled(_model_idx, false)


func run_level() -> int:
	return 0        ## 启动阶段还没开Run；解锁判定在 main.gd 里按实际进度复核


func _send() -> void:
	var id := String(MODELS[_model_idx][0])
	var need := int(MODELS[_model_idx][2])
	if run_level() < need:
		_hint.text = "「%s」还没解锁，先通关 %d 关。" % [String(MODELS[_model_idx][1]), need]
		return
	if _input.text.strip_edges().is_empty():
		_hint.text = "先写一句指令再发送。"
		return
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
