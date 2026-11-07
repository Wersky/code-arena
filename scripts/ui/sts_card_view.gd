class_name StsCardView
extends Control
## 杀戮尖塔制的卡面视图：150×226。
##
## 2026-11-07 再改版（主人要求，卡框贴图回归）：
##   - **正面 = 卡框贴图**（sts-frame-attack/defend，按类型取）：
##     左上角小圈圈（费用球）填费用数字；顶部名牌（输入框样式）填「名字 + 等级」；
##     立绘从画窗一直铺到底——原底部描述面板废弃（描述挪到背面），用深色底板盖住刻线。
##   - **等级** = 定价档位 price_tier（1–3；未定价显示 Lv.1）。
##   - **右键翻面**：横向翻转动画（压缩→换面→回弹），背面 = 名字 + 描述。
##   - 数值预览（set_seq_value / set_multiplier）写到背面，翻过来才看。

signal clicked(view: StsCardView)
## 翻面完成时发出（back=true 表示已翻到背面）
signal flipped(view: StsCardView, back: bool)

const W := 150.0
const H := 226.0

## 卡框贴图（按类型取；750×1130 像素画 ÷5 = 150×226）
const FRAME_PATHS := {
	StsCard.Kind.ATTACK: "res://assets/art/sts-frame-attack.png",
	StsCard.Kind.SKILL: "res://assets/art/sts-frame-defend.png",
}

## 实测分区（卡面坐标，贴图 ÷5；截图校准：圆环心 (17.5,16.6)、名牌内区 y5..21.9、
## 名牌底框是红色（金线只有顶线 y4.4）。像素字体的 CJK 墨迹在行盒里偏沉，
## 文字 rect 比「内区几何中心」抬高 5px 才能让墨迹居中——11-07 实测校准。）
const COST_RECT := Rect2(8, 6, 20, 21)        ## 费用数字：居中在左上角小圈圈里
const NAME_RECT := Rect2(37, 2, 66, 15)       ## 名字：名牌（输入框）左段，左对齐
const LV_RECT := Rect2(104, 2, 30, 15)        ## 等级：名牌右段，右对齐「Lv.N」
## 立绘：画窗顶铺到底（盖住废弃的底部描述面板），四周不压外圈金线
const ART_RECT := Rect2(9, 30, 132, 188)
## 立绘底板色（与卡框画窗的深海军蓝一致，透出立绘的透明背景）
const C_ART_BG := Color(0.043, 0.055, 0.102)

## 费用数字的颜色（能量青）
const C_COST := Color(0.310, 0.757, 0.965)
## 等级数字的颜色（淡金）
const C_LV := Color(1.0, 0.84, 0.5)

var card: StsCard = null
var playable := true
var _slot_frame_first: Panel = null
var _slot_frame_last: Panel = null
var _mult := 1.0   ## 成长倍率（白米饭吃满后 1.2；1.0 = 无加成）

## 翻转容器：正面/背面都在里面，动画只动它的 scale（和悬停缩放互不干扰）
var _flip_root: Control = null
var _front: Control = null
var _back: Panel = null
var _frame: TextureRect = null
var _art: TextureRect = null
var _cost_lbl: Label = null
var _name_lbl: Label = null
var _lv_lbl: Label = null
var _back_name: Label = null
var _back_desc: Label = null
var _flipped := false
var _flipping := false
## 序列预览信息（翻面时用来显示"这一格将打出多少"）
var _seq_info: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(c: StsCard) -> void:
	card = c
	var kcolor: Color = StsCardPool.kind_color(c.kind)

	_flip_root = Control.new()
	_flip_root.name = "FlipRoot"
	_flip_root.size = Vector2(W, H)
	_flip_root.pivot_offset = Vector2(W, H) * 0.5
	_flip_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flip_root)

	# ── 正面：卡框贴图打底 + 左上费用球 + 名牌（名字+等级）+ 立绘铺到底 ──
	# （2026-11-07 卡框贴图回归：名牌/费用球填字复活；底部描述面板废弃，
	#   立绘铺过它——描述挪到背面）
	_front = Control.new()
	_front.name = "Front"
	_front.size = Vector2(W, H)
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flip_root.add_child(_front)

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
	_front.add_child(_frame)

	# 立绘底板：盖住卡框底部废弃的描述面板（刻线别透出来），兼当立绘透明背景的衬色
	var art_bg := Panel.new()
	art_bg.name = "ArtBg"
	art_bg.position = ART_RECT.position
	art_bg.size = ART_RECT.size
	art_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var absb := StyleBoxFlat.new()
	absb.bg_color = C_ART_BG
	art_bg.add_theme_stylebox_override("panel", absb)
	_front.add_child(art_bg)

	_art = TextureRect.new()
	_art.name = "Art"
	_art.position = ART_RECT.position
	_art.size = ART_RECT.size
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.clip_contents = true
	if c.art_path != "":
		var tex := _load_art(c.art_path)
		if tex != null:
			_art.texture = tex
	_front.add_child(_art)

	# 左上角小圈圈：费用数字（圆环心实测 (16,14.5)）
	_cost_lbl = UiKit.label(str(c.cost), 14, C_COST)
	_cost_lbl.name = "CostOrb"
	_cost_lbl.position = COST_RECT.position
	_cost_lbl.size = COST_RECT.size
	_cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.add_child(_cost_lbl)

	# 名牌（输入框样式）：名字左对齐 + 等级右对齐「Lv.N」
	_name_lbl = UiKit.label(StsCardPool.card_name(c.id), 12, Color(0.93, 0.96, 1.0))
	_name_lbl.name = "NamePlate"
	_name_lbl.position = NAME_RECT.position
	_name_lbl.size = NAME_RECT.size
	_name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.add_child(_name_lbl)

	_lv_lbl = UiKit.label("Lv.%d" % maxi(1, c.price_tier), 10, C_LV)
	_lv_lbl.name = "LevelTag"
	_lv_lbl.position = LV_RECT.position
	_lv_lbl.size = LV_RECT.size
	_lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lv_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.add_child(_lv_lbl)

	# ── 背面：名字 / 类型·费用 / 效果说明 ───────────────
	_back = Panel.new()
	_back.name = "Back"
	_back.position = Vector2.ZERO
	_back.size = Vector2(W, H)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.055, 0.105, 0.98)
	sb.border_color = kcolor
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(7)
	_back.add_theme_stylebox_override("panel", sb)
	_flip_root.add_child(_back)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)

	_back_name = UiKit.label(StsCardPool.card_name(c.id), 14, kcolor)
	_back_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_back_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_back_name)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sep)

	_back_desc = UiKit.label("", UiKit.FS_XS, UiKit.TEXT)
	_back_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_back_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_back_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_back_desc)

	_back.visible = false
	_refresh_back()

	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	gui_input.connect(_on_gui)


## 卡面加载：res:// 走 ResourceLoader；user://（许愿卡 AI 图）走 Image.load_from_file
static func _load_art(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t: Resource = load(path)
		if t is Texture2D:
			return t as Texture2D
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	return null


func _on_hover(entered: bool) -> void:
	set_hovered(entered)


func _on_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			clicked.emit(self)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			flip()
			accept_event()


## 右键翻面：先横向压扁 → 换面 → 回弹（带轻微过冲），中途提亮一下
func flip() -> void:
	if _flipping or _flip_root == null:
		return
	_flipping = true
	var tw := create_tween()
	tw.tween_property(_flip_root, "scale", Vector2(0.04, 0.94), 0.11) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_flip_root, "modulate", Color(1.45, 1.45, 1.55), 0.11)
	tw.tween_callback(func() -> void:
		_flipped = not _flipped
		_front.visible = not _flipped
		_back.visible = _flipped
		if _flipped:
			_refresh_back()
		flipped.emit(self, _flipped))
	tw.tween_property(_flip_root, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_flip_root, "modulate", Color.WHITE, 0.20)
	tw.tween_callback(func() -> void: _flipping = false)


func is_flipped() -> bool:
	return _flipped


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


## 成长倍率变化 → 背面数值行改显「基础值 (×倍率)」
func set_multiplier(m: float) -> void:
	if absf(m - _mult) < 0.001:
		return
	_mult = m
	_refresh_back()


func _desc_text() -> String:
	var base := StsCardPool.desc(card.id)
	if absf(_mult - 1.0) < 0.001:
		return base
	if card.kind == StsCard.Kind.ATTACK and card.damage > 0:
		return "造成 %d (×%.1f) 点伤害。" % [card.damage, _mult]
	if card.kind == StsCard.Kind.SKILL and card.block > 0:
		return "获得 %d (×%.1f) 点格挡。" % [card.block, _mult]
	return base


## 背面刷新：名字 / 描述（类型与费用已在正面名牌与费用球上）
func _refresh_back() -> void:
	if _back == null or card == null:
		return
	if _name_lbl != null:
		_name_lbl.text = StsCardPool.card_name(card.id)
	if _cost_lbl != null:
		_cost_lbl.text = str(card.cost)
	if _lv_lbl != null:
		_lv_lbl.text = "Lv.%d" % maxi(1, card.price_tier)
	if _back_name != null:
		_back_name.text = StsCardPool.card_name(card.id)
	if _back_desc != null:
		_back_desc.text = _seq_or_desc()


func _seq_or_desc() -> String:
	if _seq_info.is_empty() or bool(_seq_info.get("growth", false)):
		return _desc_text()
	var v := int(_seq_info.get("value", 0))
	var buffed := bool(_seq_info.get("buffed", false))
	var mult_txt := "%.1f" % StsCombat.RICE_BUFF
	if card.kind == StsCard.Kind.ATTACK:
		return "本序列：造成 %d (×%s) 点伤害。" % [v, mult_txt] if buffed \
				else "本序列：造成 %d 点伤害。" % v
	if card.kind == StsCard.Kind.SKILL:
		return "本序列：获得 %d (×%s) 点格挡。" % [v, mult_txt] if buffed \
				else "本序列：获得 %d 点格挡。" % v
	return _desc_text()


## 队列槽位徽标：金/紫描边（左端费用球、右端槽位徽标在背面，不占正面）
const SLOT_BADGE_RECT := Rect2(124, 3, 18, 20)
const C_SLOT_LEAD := Color(1.0, 0.82, 0.40)     ## 「首」金 #ffd166
const C_SLOT_FINISH := Color(0.639, 0.388, 0.815)  ## 「尾」紫 #a363d0


func set_slot(lead: bool, finish: bool) -> void:
	if _slot_frame_first == null:
		_slot_frame_first = _make_slot_frame(Color(1.0, 0.82, 0.4))
		_slot_frame_last = _make_slot_frame(Color(0.639, 0.388, 0.815))
	_slot_frame_first.visible = lead
	_slot_frame_last.visible = finish and not lead


func _make_slot_frame(col: Color) -> Panel:
	var pn := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = col
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.anti_aliasing = false
	pn.add_theme_stylebox_override("panel", sb)
	pn.position = Vector2(1, 1)
	pn.size = Vector2(W - 2, H - 2)
	pn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pn)
	return pn


## 序列预览数值：记下来，翻到背面时显示
func set_seq_value(info: Dictionary) -> void:
	_seq_info = info
	_refresh_back()


## 能量不够 → 整卡压暗（arena 每次能量变化后刷新）
func set_playable(ok: bool) -> void:
	playable = ok
	modulate = Color.WHITE if ok else Color(0.55, 0.55, 0.58, 0.85)
