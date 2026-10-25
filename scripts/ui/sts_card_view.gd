class_name StsCardView
extends Control
## 杀戮尖塔制的卡面视图：150×226。
##
## 布局（主人钦定 2026-10-25）：
##   顶栏 26px  卡名（类型色）
##   画区 140px 生成的像素立绘（StsCardPool 表里的 art）
##   小GUI 60px 「能量 N ｜ 攻击/防御」+ 一句效果描述
##   左上角能量费用球，能量不够时整卡变灰（由 arena 调 set_playable）
##
## 悬停放大 / 点击闪光是自带的；抬起位移由 arena 的横排布局管。

signal clicked(view: StsCardView)

const W := 150.0
const H := 226.0
const NAME_H := 26.0
const ART_H := 140.0

const ORB_R := 13.0
const ORB_C := Vector2(20, 20)
const C_ORB_BG := Color(0.055, 0.078, 0.125)
const C_ORB_RING := Color(0.310, 0.757, 0.965)

var card: StsCard = null
var playable := true

var _art: TextureRect = null
var _name_lbl: Label = null
var _meta_lbl: Label = null
var _desc_lbl: Label = null
var _hover := false


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(c: StsCard) -> void:
	card = c
	var kcolor: Color = StsCardPool.kind_color(c.kind)

	_name_lbl = UiKit.label(StsCardPool.card_name(c.id), UiKit.FS_XS, kcolor)
	_name_lbl.position = Vector2(0, 5)
	_name_lbl.size = Vector2(W, NAME_H)
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_lbl)

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

	# 小 GUI（图片下方）：能量 + 类型 一行，效果描述一行
	_meta_lbl = UiKit.label("能量 %d ｜ %s" % [c.cost, StsCardPool.kind_name(c.kind)],
			UiKit.FS_XS, C_ORB_RING)
	_meta_lbl.position = Vector2(6, NAME_H + ART_H + 4)
	_meta_lbl.size = Vector2(W - 12, 16)
	_meta_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_meta_lbl)

	_desc_lbl = UiKit.label(StsCardPool.desc(c.id), UiKit.FS_XS, UiKit.TEXT)
	_desc_lbl.position = Vector2(8, NAME_H + ART_H + 22)
	_desc_lbl.size = Vector2(W - 16, 34)
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desc_lbl)

	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	gui_input.connect(_on_gui)


func _on_hover(entered: bool) -> void:
	_hover = entered
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
	var kcolor: Color = StsCardPool.kind_color(card.kind)
	# 卡底 + 类型色描边
	draw_rect(Rect2(0, 0, W, H), UiKit.PANEL)
	draw_rect(Rect2(0, 0, W, H), kcolor, false, 2.0)
	# 顶栏底色
	draw_rect(Rect2(2, 2, W - 4, NAME_H), UiKit.PANEL_2)
	# 小 GUI 面板底（图片下方那条）
	draw_rect(Rect2(2, H - 58, W - 4, 56), UiKit.PANEL_2)
	draw_rect(Rect2(2, H - 58, W - 4, 56), kcolor * Color(1, 1, 1, 0.55), false, 1.0)
	draw_line(Vector2(2, H - 58), Vector2(W - 2, H - 58), kcolor, 1.0)
	# 能量费用球（左上角）
	draw_circle(ORB_C, ORB_R, C_ORB_BG)
	draw_arc(ORB_C, ORB_R - 1.0, 0, TAU, 24, C_ORB_RING, 2.0)
	var f := ThemeDB.fallback_font
	var num := str(card.cost)
	var num_w := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(f, ORB_C + Vector2(-num_w * 0.5, 5.0), num,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.95, 0.98))
