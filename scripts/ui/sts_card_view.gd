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
## 框材质的实测分区（卡框 750x1130 ÷5 = 150x226；全部按框素材像素量出来的，
## 不是估的）：金线在 x4/x144、y4/y166/y219；画窗 y31..161；底部面板 y168..216，
## 其中 y≈183 有一条内部分隔线（上=能量/类型，下=效果描述）。
const ART_RECT := Rect2(9, 31, 132, 130)      ## 立绘：严格限制在画窗内
const COST_FONT := 18                          ## 费用数字字号（球内区 ~20px，24 会顶满环）
const COST_RECT := Rect2(9, 2, 26, 26)        ## 费用数字：居中在六边形球里（球心实测 (17,15.5)，见 docs/shots 校准图）
const NAME_RECT := Rect2(50, 6, 90, 16)       ## 卡名：居中在名牌内区（中心 95,14）
const META_RECT := Rect2(6, 168, 138, 14)     ## 「能量 N ｜ 类型」：分隔线以上
const DESC_RECT := Rect2(6, 184, 138, 31)     ## 效果描述：分隔线以下，不出底边 216

## 费用数字的颜色（能量青）
const C_COST := Color(0.310, 0.757, 0.965)

## 卡框材质（按类型取）
const FRAME_PATHS := {
	StsCard.Kind.ATTACK: "res://assets/art/sts-frame-attack.png",
	StsCard.Kind.SKILL: "res://assets/art/sts-frame-defend.png",
}

var card: StsCard = null
var playable := true
var _slot_frame_first: Panel = null
var _slot_frame_last: Panel = null
var _mult := 1.0   ## 成长倍率（白米饭吃满后 1.2；1.0 = 无加成）

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

	# ② 顶栏：费用数字（左）+ 卡名（中，给费用让出左侧）
	var cost_lbl := UiKit.label(str(c.cost), COST_FONT, C_COST)
	cost_lbl.name = "CostOrb"
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_constant_override("outline_size", 4)
	cost_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.95))
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cost_lbl)

	_name_lbl = UiKit.label(StsCardPool.card_name(c.id), UiKit.FS_XS, kcolor)
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_lbl.add_theme_constant_override("outline_size", 3)
	_name_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.92))
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_lbl)

	# ③ 立绘（严格落在框的画窗内；KEEP_ASPECT_COVERED 不拉伸变形）
	_art = TextureRect.new()
	_art.name = "Art"
	_art.position = ART_RECT.position
	_art.size = ART_RECT.size
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.clip_contents = true      ## 双保险：万一以后换宽幅立绘，也只会在窗内裁切
	if c.art_path != "" and ResourceLoader.exists(c.art_path):
		var t: Resource = load(c.art_path)
		if t is Texture2D:
			_art.texture = t as Texture2D
	add_child(_art)

	# ④ 小 GUI（图片下方）：能量+类型一行（能量色），效果描述一行（居中+描边）
	_meta_lbl = UiKit.label("能量 %d ｜ %s" % [c.cost, StsCardPool.kind_name(c.kind)],
			UiKit.FS_XS, C_COST)
	_meta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta_lbl.add_theme_constant_override("outline_size", 2)
	_meta_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
	_meta_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_meta_lbl)

	_desc_lbl = UiKit.label(StsCardPool.desc(c.id), UiKit.FS_XS, UiKit.TEXT)
	_desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.add_theme_constant_override("outline_size", 2)
	_desc_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
	_desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desc_lbl)

	# 排版最后一步：全部文字按目标 rect 居中。
	# 必须放在字号/描边都设好之后——Label 的最小尺寸含描边宽度，
	# 提前算会让位置偏（实测费用数字下偏 12px）。
	_fit_label(cost_lbl, COST_RECT)
	_fit_label(_name_lbl, NAME_RECT)
	_fit_label(_meta_lbl, META_RECT)
	_fit_label(_desc_lbl, DESC_RECT)

	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	gui_input.connect(_on_gui)


## Label 的最小尺寸由「字号 + 描边」决定，常常比目标 rect 还高；
## 直接给 rect 会让 Godot 把框撑大、文字随之整体下移（实测下偏 12px）。
## 这里改成：尺寸取 max(rect, 最小尺寸)，再按 rect 中心对齐——文字永远居中。
func _fit_label(lbl: Label, rect: Rect2) -> void:
	lbl.set_meta("fit_rect", rect)
	_apply_fit(lbl)
	# 描边/字体生效会把最小尺寸抬高一档（实测 +6），只在 setup 里算一次会偏；
	# 绑住 minimum_size_changed 自动重排，永远居中。
	if not lbl.minimum_size_changed.is_connected(_on_fit_min_size):
		lbl.minimum_size_changed.connect(_on_fit_min_size.bind(lbl))


func _on_fit_min_size(lbl: Label) -> void:
	_apply_fit(lbl)


func _apply_fit(lbl: Label) -> void:
	var rect: Rect2 = lbl.get_meta("fit_rect", Rect2())
	var min_sz := lbl.get_combined_minimum_size()
	lbl.size = Vector2(maxf(rect.size.x, min_sz.x), maxf(rect.size.y, min_sz.y))
	lbl.position = rect.get_center() - lbl.size * 0.5


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


## 成长倍率变化 → 数值行改显「基础值 (×倍率)」（2026-10-31 主人钦定：
## 说明里不写加成，数值直接读在卡面上）
func set_multiplier(m: float) -> void:
	if absf(m - _mult) < 0.001:
		return
	_mult = m
	if _desc_lbl != null and card != null:
		_desc_lbl.text = _desc_text()


func _desc_text() -> String:
	var base := StsCardPool.desc(card.id)
	if absf(_mult - 1.0) < 0.001:
		return base
	if card.kind == StsCard.Kind.ATTACK and card.damage > 0:
		return "造成 %d (×%.1f) 点伤害。" % [card.damage, _mult]
	if card.kind == StsCard.Kind.SKILL and card.block > 0:
		return "获得 %d (×%.1f) 点格挡。" % [card.block, _mult]
	return base


## 队列槽位徽标：放卡名条右端（左端是费用球，互不遮挡）
const SLOT_BADGE_RECT := Rect2(124, 3, 18, 20)
const C_SLOT_LEAD := Color(1.0, 0.82, 0.40)     ## 「首」金 #ffd166
const C_SLOT_FINISH := Color(0.639, 0.388, 0.815)  ## 「尾」紫 #a363d0（2026-11-01 主人钦定：与防御卡蓝框区分）

var _slot_lead_lbl: Label = null
var _slot_finish_lbl: Label = null


## 序列槽位徽标（arena._update_seq_preview 每次刷新调用）：
## 队列首位 →「首」（初始化 +1）、末位 →「尾」（收尾 +2）；互斥显示，都没有就藏。
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


func _make_slot_badge(txt: String, col: Color) -> Label:
	var l := UiKit.label(txt, UiKit.FS_XS, col)
	l.name = "SlotBadge_" + txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = SLOT_BADGE_RECT.size
	l.position = SLOT_BADGE_RECT.position
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## 序列预览数值行（arena._update_seq_preview 每次刷新调用）：
## 该卡在队列这一格「将打出的数值」= 阶梯 + 槽位（info.value，未乘睡醒加成）；
## 睡醒加成照 set_multiplier 的惯例标成 (×1.2)。空 info / 米饭 → 回落卡池描述。
func set_seq_value(info: Dictionary) -> void:
	if _desc_lbl == null or card == null:
		return
	if info.is_empty() or bool(info.get("growth", false)):
		_desc_lbl.text = StsCardPool.desc(card.id)
		return
	var v := int(info.get("value", 0))
	var buffed := bool(info.get("buffed", false))
	var mult_txt := "%.1f" % StsCombat.RICE_BUFF
	if card.kind == StsCard.Kind.ATTACK:
		if buffed:
			_desc_lbl.text = "造成 %d (×%s) 点伤害。" % [v, mult_txt]
		else:
			_desc_lbl.text = "造成 %d 点伤害。" % v
	elif card.kind == StsCard.Kind.SKILL:
		if buffed:
			_desc_lbl.text = "获得 %d (×%s) 点格挡。" % [v, mult_txt]
		else:
			_desc_lbl.text = "获得 %d 点格挡。" % v
	else:
		_desc_lbl.text = StsCardPool.desc(card.id)


## 能量不够 → 整卡压暗（arena 每次能量变化后刷新）
func set_playable(ok: bool) -> void:
	playable = ok
	modulate = Color.WHITE if ok else Color(0.55, 0.55, 0.58, 0.85)
