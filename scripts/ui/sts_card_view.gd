class_name StsCardView
extends Control
## 杀戮尖塔制的卡面视图：150×226。
##
## 底子是**生成的像素风卡框材质**（sts-frame-attack/defend，三段布局与本视图
## 的分割线对齐），引擎只往上面叠三样：立绘、文字、费用球——
## 生图不写文字（会乱码），排版全在这里管。
##
## 布局：
##   顶栏 0..26    卡名（类型色 + 黑描边，居中）
##   画区 26..166  生成的像素立绘
##   小GUI 166..226「能量 N ｜ 类型」+ 效果描述（居中 + 描边）
##   左上角能量费用球（引擎画），能量不够时整卡变灰

signal clicked(view: StsCardView)

const W := 150.0
const H := 226.0
const NAME_H := 26.0
const ART_H := 140.0

const ORB_R := 13.0
const ORB_C := Vector2(20, 20)
const C_ORB_BG := Color(0.055, 0.078, 0.125)
const C_ORB_RING := Color(0.310, 0.757, 0.965)

## 卡框材质（按类型取）
const FRAME_PATHS := {
	StsCard.Kind.ATTACK: "res://assets/art/sts-frame-attack.png",
	StsCard.Kind.SKILL: "res://assets/art/sts-frame-defend.png",
}

var card: StsCard = null
var playable := true

var _frame: TextureRect = null
var _art: TextureRect = null
var _name_lbl: Label = null
var _meta_lbl: Label = null
var _desc_lbl: Label = null


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(c: StsCard) -> void:
	card = c
	var kcolor: Color = StsCardPool.kind_color(c.kind)

	# ① 卡框材质打底（高密度像素画缩小显示，线性过滤）
	_frame = TextureRect.new()
	_frame.name = "Frame"
	_frame.position = Vector2.ZERO
	_frame.size = Vector2(W, H)
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fp := String(FRAME_PATHS.get(c.kind, FRAME_PATHS[StsCard.Kind.ATTACK]))
	if ResourceLoader.exists(fp):
		var ft: Resource = load(fp)
		if ft is Texture2D:
			_frame.texture = ft as Texture2D
	add_child(_frame)

	# ② 顶栏卡名：类型色 + 黑描边（描边让像素字在花纹上读得清）
	_name_lbl = UiKit.label(StsCardPool.card_name(c.id), UiKit.FS_XS, kcolor)
	_name_lbl.position = Vector2(4, 4)
	_name_lbl.size = Vector2(W - 8, NAME_H)
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_lbl.add_theme_constant_override("outline_size", 3)
	_name_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.92))
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_lbl)

	# ③ 立绘（框的画窗正中）
	_art = TextureRect.new()
	_art.name = "Art"
	_art.position = Vector2(0, NAME_H)
	_art.size = Vector2(W, ART_H)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if c.art_path != "" and ResourceLoader.exists(c.art_path):
		var t: Resource = load(c.art_path)
		if t is Texture2D:
			_art.texture = t as Texture2D
	add_child(_art)

	# ④ 小 GUI（图片下方）：能量+类型一行（能量色），效果描述一行（居中+描边）
	_meta_lbl = UiKit.label("能量 %d ｜ %s" % [c.cost, StsCardPool.kind_name(c.kind)],
			UiKit.FS_XS, C_ORB_RING)
	_meta_lbl.position = Vector2(4, NAME_H + ART_H + 5)
	_meta_lbl.size = Vector2(W - 8, 16)
	_meta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta_lbl.add_theme_constant_override("outline_size", 2)
	_meta_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
	_meta_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_meta_lbl)

	_desc_lbl = UiKit.label(StsCardPool.desc(c.id), UiKit.FS_XS, UiKit.TEXT)
	_desc_lbl.position = Vector2(6, NAME_H + ART_H + 24)
	_desc_lbl.size = Vector2(W - 12, 32)
	_desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.add_theme_constant_override("outline_size", 2)
	_desc_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
	_desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desc_lbl)

	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	gui_input.connect(_on_gui)


func _on_hover(entered: bool) -> void:
	set_hovered(entered)


func _on_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			clicked.emit(self)
			accept_event()


## 悬停：绕底边中心放大（pivot 由 arena 布局时设置）
func set_hovered(on: bool) -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale",
			Vector2(1.16, 1.16) if on else Vector2.ONE, 0.10) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 打出时的白闪
func flash() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate",
			Color(1.6, 1.6, 1.6), 0.06)
	tw.tween_property(self, "modulate", Color.WHITE, 0.14)


## 能量不够 → 整卡压暗（arena 每次能量变化后刷新）
func set_playable(ok: bool) -> void:
	playable = ok
	modulate = Color.WHITE if ok else Color(0.55, 0.55, 0.58, 0.85)


func _draw() -> void:
	if card == null:
		return
	# 能量费用球（左上角；框图的底座不明显，球由引擎画）
	draw_circle(ORB_C, ORB_R, C_ORB_BG)
	draw_arc(ORB_C, ORB_R - 1.0, 0, TAU, 24, C_ORB_RING, 2.0)
	var f := ThemeDB.fallback_font
	var num := str(card.cost)
	var num_w := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(f, ORB_C + Vector2(-num_w * 0.5, 5.0), num,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.95, 0.98))
