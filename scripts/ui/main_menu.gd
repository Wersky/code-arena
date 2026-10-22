extends Control
class_name MainMenuScreen
## 主菜单。

signal start_run
signal quit_game

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
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

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 60
	root.offset_right = -40
	root.offset_top = 40
	root.offset_bottom = -40
	root.add_theme_constant_override("separation", 40)
	add_child(root)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", UiKit.SP_3)
	root.add_child(v)

	# 标题：终端前缀 + 大字
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", UiKit.SP_2)
	v.add_child(title_row)
	title_row.add_child(UiKit.label(">", UiKit.FS_M, UiKit.ACCENT))
	var title := UiKit.title("提示词擂台", UiKit.FS_L)
	title_row.add_child(title)

	var sub := UiKit.label("PROMPT  ARENA", UiKit.FS_S, UiKit.ACCENT)
	v.add_child(sub)

	v.add_child(UiKit.rule())

	var desc := UiKit.dim("拼装提示词组件，让模型输出通过评测线。\n每一关是一道 Benchmark，每一件 AI 道具都改写一条规则。", UiKit.FS_XS)
	v.add_child(desc)

	v.add_child(UiKit.spacer(UiKit.SP_3))

	var start_btn := UiKit.accent_button("▶  开始新的一局", UiKit.FS_S)
	start_btn.custom_minimum_size = Vector2(320, 52)
	start_btn.pressed.connect(func() -> void: start_run.emit())
	v.add_child(start_btn)

	var quit_btn := UiKit.button("退出", UiKit.FS_XS)
	quit_btn.custom_minimum_size = Vector2(320, 40)
	quit_btn.pressed.connect(func() -> void: quit_game.emit())
	v.add_child(quit_btn)

	v.add_child(UiKit.spacer(UiKit.SP_2))
	var hint := UiKit.dim("全程鼠标操作：点手牌 → 落进槽位 → 点运行。右键卡牌可翻到背面看配图。", UiKit.FS_XS)
	v.add_child(hint)

	# 主角（评审官）立绘——径向渐隐版本，边缘融进背景。
	# 源图 384×384，按 2 倍整数放大到 768，像素块不会不匀。
	var hero := Art.make_avatar("hero-reviewer-blend", Vector2(768, 768))
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.custom_minimum_size = Vector2(768, 768)
	root.add_child(hero)

	# 扫描线覆盖全屏，给整台"机器"一点 CRT 味
	var scan := Scanlines.new()
	scan.spacing = 4
	scan.alpha = 0.10
	add_child(scan)
	scan.set_anchors_preset(Control.PRESET_FULL_RECT)
