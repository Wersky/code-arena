extends Control
class_name ShopScreen
## 商店：用算力点买卡牌 / AI 道具。

signal closed

const CARD_PRICE := 40
const ITEM_PRICE := 90
const REFRESH_PRICE := 12

## 好感度礼物（2026-11-07）：金币结算，买来直接喂 Deep Sick
const AFFECTION_GOODS := [
	{"id": "cake", "name": "小蛋糕", "price": 20, "points": 6.0,
		"desc": "Deep Sick 最爱的奶油甜点，一口一个幸福。"},
	{"id": "ribbon", "name": "鲸纹蝴蝶结", "price": 45, "points": 15.0,
		"desc": "系上它，她今天格外开心。"},
	{"id": "date", "name": "深夜约会券", "desc": "两个人的后台进程，独占一晚。", "points": 40.0, "price": 110},
]

var run: RunState = null
var _card_offers: Array[CardData] = []
var _item_offers: Array[AiItemData] = []
var _cards_row: HBoxContainer = null
var _items_row: HBoxContainer = null
var _money: Label = null
var _gold: Label = null
var _affection: Label = null
var _gifts_row: HBoxContainer = null
var _gift_offers: Array = []
var _refresh_btn: Button = null
var _hint: Label = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(run_state: RunState) -> void:
	run = run_state


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = Art.tex("bg-arena")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var veil := ColorRect.new()
	veil.color = Color(0.055, 0.063, 0.09, 0.88)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 60
	root.offset_right = -60
	root.offset_top = 40
	root.offset_bottom = -40
	root.add_theme_constant_override("separation", 20)
	add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	root.add_child(head)
	head.add_child(UiKit.title("商店", UiKit.FS_M))
	_money = UiKit.label("", UiKit.FS_S, UiKit.DANGER)
	head.add_child(_money)
	_gold = UiKit.label("", UiKit.FS_S, Color(1.0, 0.82, 0.4))
	head.add_child(_gold)
	_affection = UiKit.label("", UiKit.FS_S, Color(0.95, 0.6, 0.75))
	head.add_child(_affection)

	root.add_child(UiKit.dim("卡牌 —— 扩充你的牌库，让更多牌型成为可能", UiKit.FS_XS))
	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 16)
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_cards_row)

	root.add_child(UiKit.dim("AI 道具 —— 永久改写一条规则", UiKit.FS_XS))
	_items_row = HBoxContainer.new()
	_items_row.add_theme_constant_override("separation", 16)
	_items_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_items_row)

	root.add_child(UiKit.dim("好感度礼物 —— 用金币买，喂给 Deep Sick（影响许愿卡品质）", UiKit.FS_XS))
	_gifts_row = HBoxContainer.new()
	_gifts_row.add_theme_constant_override("separation", 16)
	_gifts_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_gifts_row)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 16)
	root.add_child(foot)

	_refresh_btn = UiKit.button("↺  刷新货架（%d）" % REFRESH_PRICE, 17)
	_refresh_btn.pressed.connect(_on_refresh)
	foot.add_child(_refresh_btn)

	var close_btn := UiKit.accent_button("离开商店", 20)
	close_btn.pressed.connect(func() -> void: closed.emit())
	foot.add_child(close_btn)

	_hint = UiKit.dim("", UiKit.FS_XS)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_hint)

	_roll_offers()
	_refresh()


func _roll_offers() -> void:
	_card_offers = CardPool.random_cards(run.rng, 4)
	_item_offers = []
	for it in AiItemPool.roll_rewards(run.rng, run.chapter, run.items, 2):
		_item_offers.append(it)
	_gift_offers = []
	for g in AFFECTION_GOODS:
		_gift_offers.append(g.duplicate())


func _refresh() -> void:
	_money.text = "算力 %d" % run.compute
	if _gold != null:
		_gold.text = "💰 金币 %d" % run.gold
	if _affection != null:
		_affection.text = "好感 Lv.%d" % Affection.level()

	# 买得起才让点。买不起时按钮置灰并说明原因，避免"点了没反应"
	_refresh_btn.disabled = run.compute < REFRESH_PRICE
	_refresh_btn.tooltip_text = "需要 %d 算力（当前 %d）" % [REFRESH_PRICE, run.compute]
	if run.compute < REFRESH_PRICE:
		_hint.text = "算力不足（%d / %d）——先通过评测赚算力：剩余回合 × 20 ＋ 超出目标分 ÷ 10" % [
			run.compute, REFRESH_PRICE
		]
		_hint.add_theme_color_override("font_color", UiKit.DANGER)
	else:
		_hint.text = "算力 %d ｜ 卡牌 %d 算力一张 ｜ 道具 %d 算力一件" % [
			run.compute, CARD_PRICE, ITEM_PRICE
		]
		_hint.add_theme_color_override("font_color", UiKit.TEXT_DIM)

	for c in _cards_row.get_children():
		c.queue_free()
	for card in _card_offers:
		_cards_row.add_child(_make_card_offer(card))

	for c in _items_row.get_children():
		c.queue_free()
	for it in _item_offers:
		_items_row.add_child(_make_item_offer(it))

	for c in _gifts_row.get_children():
		c.queue_free()
	for g in _gift_offers:
		_gifts_row.add_child(_make_gift_offer(g))


func _make_card_offer(card: CardData) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(190, 250)
	var color := CardData.kind_color(card.kind)
	panel.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL_2, color, 2, 12, 3))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var icon := Art.make_rect("card-" + CardData.kind_slug(card.kind), true)
	icon.custom_minimum_size = Vector2(0, 84)
	v.add_child(icon)
	v.add_child(UiKit.label(card.title, UiKit.FS_S, color))
	v.add_child(UiKit.dim("%s ｜ %d 分 ｜ %d Token" % [CardData.kind_name(card.kind), card.base_score, card.token_cost], UiKit.FS_XS))
	var desc := UiKit.dim(card.body, UiKit.FS_XS)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(165, 0)
	v.add_child(desc)
	if card.risky:
		v.add_child(UiKit.label("⚠ 风险卡", UiKit.FS_XS, UiKit.DANGER))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var btn := UiKit.button("购买 %d" % CARD_PRICE, 16)
	btn.disabled = run.compute < CARD_PRICE
	btn.pressed.connect(_on_buy_card.bind(card))
	v.add_child(btn)
	return panel


func _make_item_offer(it: AiItemData) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 250)
	var color := AiItemData.rarity_color(it.rarity)
	panel.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL_2, color, 2, 12, 3))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var portrait := TextureRect.new()
	portrait.texture = Art.tex(Art.item_bust_name(it.id))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(0, 100)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if portrait.texture != null:
		v.add_child(portrait)
	v.add_child(UiKit.dim(AiItemData.rarity_name(it.rarity), UiKit.FS_XS))
	v.add_child(UiKit.label(it.display_name, UiKit.FS_S, color))
	var desc := UiKit.label(it.description, UiKit.FS_XS, UiKit.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(255, 0)
	v.add_child(desc)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var btn := UiKit.button("购买 %d" % ITEM_PRICE, 16)
	btn.disabled = run.compute < ITEM_PRICE
	btn.pressed.connect(_on_buy_item.bind(it))
	v.add_child(btn)
	return panel


func _make_gift_offer(g: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(230, 200)
	panel.add_theme_stylebox_override("panel", UiKit.flat(
			UiKit.PANEL_2, Color(0.95, 0.6, 0.75), 2, 12, 3))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var heart := UiKit.label("♥ %d" % int(g["points"]), UiKit.FS_S, Color(0.95, 0.6, 0.75))
	heart.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(heart)
	v.add_child(UiKit.label(String(g["name"]), UiKit.FS_S, Color(0.95, 0.75, 0.85)))
	var desc := UiKit.label(String(g["desc"]), UiKit.FS_XS, UiKit.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(205, 0)
	v.add_child(desc)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var btn := UiKit.button("购买 %d 金币" % int(g["price"]), 16)
	btn.disabled = run.gold < int(g["price"])
	btn.pressed.connect(_on_buy_gift.bind(g))
	v.add_child(btn)
	return panel


func _on_buy_gift(g: Dictionary) -> void:
	var price := int(g["price"])
	if run.gold < price:
		return
	run.gold -= price
	var lv := Affection.add(float(g["points"]))
	_gift_offers.erase(g)
	_refresh()
	_hint.text = "Deep Sick 开心收下了【%s】｜ 好感 Lv.%d" % [String(g["name"]), lv]
	_hint.add_theme_color_override("font_color", Color(0.95, 0.75, 0.85))


func _on_buy_card(card: CardData) -> void:
	if run.compute < CARD_PRICE:
		return
	run.compute -= CARD_PRICE
	run.deck.append(card.duplicate())
	## 组合审计预热：200ms 限时，不卡商店界面（2026-11-10）
	run.prewarm_combo_audit()
	_card_offers.erase(card)
	_refresh()


func _on_buy_item(it: AiItemData) -> void:
	if run.compute < ITEM_PRICE:
		return
	run.compute -= ITEM_PRICE
	run.add_item(it)
	_item_offers.erase(it)
	_refresh()


func _on_refresh() -> void:
	if run.compute < REFRESH_PRICE:
		return
	run.compute -= REFRESH_PRICE
	_roll_offers()
	_refresh()
