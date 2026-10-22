extends Control
class_name MainMenuScreen
## 主菜单（2026-10-22 重做）：**大标题居中靠上 + 按钮居中靠下**，走"正式游戏标题画面"的路子。
##
## 版面（1600×900 基准，全部按 size 摆，换分辨率不散）：
##   小字副题 → 大标题牌（中文大字 + 英文 + 金饰线）→ 内容信息一行
##   中间留白给背景与立绘
##   [ ▶ 开始游戏 ]（大按钮，悬停有扫光/箭头/角标）
##   [    退出    ]
##   操作提示一行
##   左下版本号 / 右下版权 / 右下角评审官立绘
##
## 外部只依赖两个信号：`start_run` / `quit_game`（main.gd 里接的）。

signal start_run
signal quit_game

## 环境动效层（漂浮尘埃 + 扫描线 + 视差）
var _bg_fx: BgFx = null

var _title_block: VBoxContainer = null
var _btn_block: VBoxContainer = null
var _hero: TextureRect = null
var _start_btn: JuiceButton = null
var _foot_left: Label = null
var _foot_right: Label = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build_bg()
	_build_hero()
	_build_title_block()
	_build_button_block()
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
	veil.color = Color(0.043, 0.055, 0.086, 0.72)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	_bg_fx = BgFx.new()
	_bg_fx.name = "BgFx"
	_bg_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg_fx)
	_bg_fx.setup(size)


## 右下角评审官立绘（径向渐隐版，边缘融进背景）
func _build_hero() -> void:
	_hero = Art.make_avatar("hero-reviewer-blend", Vector2(660, 660))
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero.size = Vector2(660, 660)
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.modulate = Color(1, 1, 1, 0.92)
	add_child(_hero)


# ── 标题 ──────────────────────────────────────────────
func _build_title_block() -> void:
	_title_block = VBoxContainer.new()
	_title_block.name = "TitleBlock"
	_title_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_block.add_theme_constant_override("separation", 2)
	add_child(_title_block)

	var kicker := UiKit.dim("AI 娘 · 德州扑克 · 肉鸽构筑", UiKit.FS_XS)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_block.add_child(kicker)

	var plate := TitlePlate.new()
	plate.name = "TitlePlate"
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_block.add_child(plate)

	var stats := UiKit.dim("10 关 ｜ 4 位 AI 娘 ｜ 52 张牌面", UiKit.FS_XS)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_block.add_child(stats)


# ── 按钮 ──────────────────────────────────────────────
func _build_button_block() -> void:
	_btn_block = VBoxContainer.new()
	_btn_block.name = "ButtonBlock"
	_btn_block.add_theme_constant_override("separation", 10)
	add_child(_btn_block)

	_start_btn = JuiceButton.new()
	_start_btn.name = "StartButton"
	_start_btn.text = "开始游戏"
	_start_btn.primary = true
	_start_btn.accent = UiKit.GOLD
	_start_btn.font_size = 36
	_start_btn.custom_minimum_size = Vector2(520, 78)
	_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_btn.pressed.connect(func() -> void: start_run.emit())
	_btn_block.add_child(_start_btn)

	var quit_btn := JuiceButton.new()
	quit_btn.name = "QuitButton"
	quit_btn.text = "退出"
	quit_btn.accent = UiKit.ACCENT
	quit_btn.font_size = 24
	quit_btn.custom_minimum_size = Vector2(380, 54)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.pressed.connect(func() -> void: quit_game.emit())
	_btn_block.add_child(quit_btn)

	var hint := UiKit.dim("纯鼠标操作：点手牌选牌 → 点「运行」出牌", UiKit.FS_XS)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn_block.add_child(hint)


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

	var tw := 960.0
	_title_block.position = Vector2(s.x * 0.5 - tw * 0.5, 44.0)
	_title_block.size = Vector2(tw, 300.0)

	var bw := 560.0
	_btn_block.position = Vector2(s.x * 0.5 - bw * 0.5, s.y - 336.0)
	_btn_block.size = Vector2(bw, 240.0)

	# 立绘靠右下，尽量不压住中间的按钮列
	_hero.position = Vector2(s.x - 700.0, s.y - 690.0)

	_foot_left.position = Vector2(28.0, s.y - 30.0)
	_foot_left.size = Vector2(320, 20)
	_foot_right.position = Vector2(s.x - 348.0, s.y - 30.0)
	_foot_right.size = Vector2(320, 20)

	if _bg_fx:
		_bg_fx.setup(s)
