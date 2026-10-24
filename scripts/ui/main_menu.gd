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

	# 面板底部一行操作提示（不抢戏，但新手看得见）
	_hint = UiKit.dim("纯鼠标操作 ｜ 点手牌选牌 → 点「运行」出牌", 15, Color(0.45, 0.55, 0.68))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)


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
		_quit_btn.position = Vector2(roundf(cx - 180.0), py + 404.0)

	if _hint != null:
		_hint.position = Vector2(px, py + 464.0)
		_hint.size = Vector2(pw, 22)

	_foot_left.position = Vector2(px, s.y - 34.0)
	_foot_left.size = Vector2(320, 20)
	_foot_right.position = Vector2(px + pw - 320.0, s.y - 34.0)
	_foot_right.size = Vector2(320, 20)

	if _bg_fx:
		_bg_fx.setup(s)
