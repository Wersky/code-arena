extends Control
class_name RewardScreen
## 过关奖励：三选一，每一张都是**往牌库里加一张扑克牌**。
## 牌库变大 = 更容易凑出高牌型。
##
## 视觉：卡面本身是主角——悬停时描边亮起、四角装饰点亮（§8.2 强调色边框）。
## 按钮统一用次级样式，页面只有一个"选择"动作，不摆三个主按钮（§2.8）。

signal chosen

var run: RunState = null
var _options: Array[Dictionary] = []
var _row: HBoxContainer = null
var _title: Label = null
var _subtitle: Label = null
var _taken: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(run_state: RunState) -> void:
	run = run_state


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = Art.tex("bg-arena")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var veil := ColorRect.new()
	veil.color = Color(0.043, 0.055, 0.086, 0.78)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 80
	v.offset_right = -80
	v.offset_top = 60
	v.offset_bottom = -60
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UiKit.SP_4)
	add_child(v)

	_title = UiKit.title("过关 · 往牌库里加一张牌", UiKit.FS_M)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)

	_subtitle = UiKit.dim("牌库变大，高牌型才凑得出来。", UiKit.FS_XS)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_subtitle)

	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", UiKit.SP_4)
	v.add_child(_row)

	_roll_options()


func _roll_options() -> void:
	_options = []
	# 三种随机牌：点数 1~10，花色随机
	var seen := {}
	var guard := 0
	while _options.size() < 3 and guard < 60:
		guard += 1
		var suit := run.rng.randi_range(0, 3)
		var rank := run.rng.randi_range(1, 10)
		var key := "%d-%d" % [suit, rank]
		if seen.has(key):
			continue
		seen[key] = true
		var red := PokerCard.is_red(suit)
		_options.append({
			"kind": "add_card",
			"suit": suit,
			"rank": rank,
			"title": "+1 张 %s" % PokerCard.suit_symbol(suit) + str(rank),
			"desc": "%s ｜ 点数 %d
%s" % [
				PokerCard.suit_name(suit), rank,
				"红牌：每张 +3 倍率" if red else "黑牌：每张 +25 筹码"],
			"color": PokerCard.suit_color(suit),
			"rarity_name": PokerCard.suit_name(suit),
		})
	for c in _row.get_children():
		c.queue_free()
	for opt in _options:
		_row.add_child(_make_option_card(opt))


func _make_option_card(opt: Dictionary) -> Control:
	var wrap := VBoxContainer.new()
	wrap.custom_minimum_size = Vector2(300, 0)
	wrap.add_theme_constant_override("separation", UiKit.SP_2)

	var base_color: Color = opt.get("color", UiKit.ACCENT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 400)
	panel.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, base_color, 2, UiKit.SP_3, UiKit.EL_2))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiKit.SP_2)
	panel.add_child(v)

	# 形象：加牌奖励直接显示**这张牌本身**（与战斗界面同一套 CardView，所见即所得）
	if opt.has("suit") and opt.has("rank"):
		var preview := CardView.new()
		preview.interactive = false
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.setup(PokerCard.make(int(opt["suit"]), int(opt["rank"])),
				str(run.ai.id) if run.ai != null else "deepdeek")
		preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(preview)
	else:
		var portrait := TextureRect.new()
		portrait.texture = Art.tex(str(opt.get("art", "")))
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(268, 172)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if portrait.texture == null:
			portrait.custom_minimum_size = Vector2(268, 60)
		else:
			v.add_child(portrait)

	# 稀有度色条（§8.2 强调色边框）
	var ribbon := ColorRect.new()
	ribbon.color = base_color
	ribbon.custom_minimum_size = Vector2(0, 3)
	v.add_child(ribbon)

	v.add_child(UiKit.dim(str(opt.get("rarity_name", "常见")), UiKit.FS_XS))
	v.add_child(UiKit.label(str(opt["title"]), UiKit.FS_S, base_color))
	v.add_child(UiKit.rule())
	var desc := UiKit.label(str(opt["desc"]), UiKit.FS_XS, UiKit.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(268, 0)
	v.add_child(desc)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)

	var btn := UiKit.button("▶  选择这个", UiKit.FS_XS)
	btn.custom_minimum_size = Vector2(0, 40)
	btn.pressed.connect(_on_pick.bind(opt))
	v.add_child(btn)

	# 四角装饰：默认熄灭，悬停点亮
	var frame := PixelFrame.new()
	frame.color = base_color
	frame.arm = 12
	frame.thick = 2
	frame.inset = 4
	frame.modulate = Color(1, 1, 1, 0.25)
	panel.add_child(frame)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 4
	frame.offset_top = 4
	frame.offset_right = -4
	frame.offset_bottom = -4

	# 悬停：描边亮起 + 角饰点亮 + 卡片微微抬起
	panel.mouse_entered.connect(func() -> void: _hover_on(panel, frame, base_color))
	panel.mouse_exited.connect(func() -> void: _hover_off(panel, frame))
	panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_on_pick(opt))

	return wrap


func _hover_on(panel: PanelContainer, frame: PixelFrame, color: Color) -> void:
	panel.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL_3, color, 2, UiKit.SP_3, UiKit.EL_2))
	frame.modulate = Color(1, 1, 1, 1.0)


func _hover_off(panel: PanelContainer, frame: PixelFrame) -> void:
	var color: Color = UiKit.LINE
	panel.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, color, 2, UiKit.SP_3, UiKit.EL_2))
	frame.modulate = Color(1, 1, 1, 0.25)


func _on_pick(opt: Dictionary) -> void:
	if _taken:
		return
	_taken = true
	if str(opt.get("kind", "")) == "add_card":
		run.add_poker_card(int(opt.get("suit", 0)), int(opt.get("rank", 1)))
	chosen.emit()
