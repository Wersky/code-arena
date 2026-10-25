extends Control
class_name RewardScreen
## 过关奖励：三选一（2026-10-25 大改：杀戮尖塔制）。
##
## 当前卡池只有两张卡，所以固定三档：+1 攻击牌 / +1 防御牌 / 治疗。
## 卡类选项直接展示 StsCardView（所见即所得）；治疗显示回复量。

signal chosen

const HEAL := 14

var run: RunState = null
var _row: HBoxContainer = null
var _taken := false


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
	v.offset_top = 50
	v.offset_bottom = -50
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UiKit.SP_4)
	add_child(v)

	var title := UiKit.title("过关 · 挑一个奖励", UiKit.FS_M)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var subtitle := UiKit.dim("卡组 %d 张 ｜ HP %d/%d" % [
		run.deck.size(), run.hp, RunState.MAX_HP], UiKit.FS_XS)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(subtitle)

	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", UiKit.SP_4)
	v.add_child(_row)

	_make_option("fish_ram", StsCardPool.kind_color(StsCard.Kind.ATTACK))
	_make_option("taunt", StsCardPool.kind_color(StsCard.Kind.SKILL))
	_make_option("heal", Color(0.443, 0.839, 0.557))


func _make_option(kind: String, base_color: Color) -> void:
	var wrap := VBoxContainer.new()
	wrap.custom_minimum_size = Vector2(280, 0)
	wrap.add_theme_constant_override("separation", UiKit.SP_2)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 380)
	panel.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, base_color, 2, UiKit.SP_3, UiKit.EL_2))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiKit.SP_2)
	panel.add_child(v)

	var title_text := ""
	if kind == "heal":
		title_text = "系统重启（+%d HP）" % HEAL
		var big := UiKit.label("＋%d" % HEAL, UiKit.FS_XL, base_color)
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(big)
		var note := UiKit.dim("小睡一觉，回点血。\n当前 %d/%d → 上限 %d。" % [
			run.hp, RunState.MAX_HP, RunState.MAX_HP], UiKit.FS_XS)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(note)
	else:
		title_text = "+1 张 %s" % StsCardPool.card_name(kind)
		var preview := StsCardView.new()
		preview.setup(StsCardPool.card(kind))
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(preview)

	var ribbon := ColorRect.new()
	ribbon.color = base_color
	ribbon.custom_minimum_size = Vector2(0, 3)
	v.add_child(ribbon)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)

	var btn := UiKit.button("▶  选择这个", UiKit.FS_XS)
	btn.custom_minimum_size = Vector2(0, 40)
	btn.pressed.connect(_on_pick.bind(kind))
	v.add_child(btn)

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

	panel.mouse_entered.connect(func() -> void:
		panel.add_theme_stylebox_override("panel",
			UiKit.flat(UiKit.PANEL_3, base_color, 2, UiKit.SP_3, UiKit.EL_2))
		frame.modulate = Color(1, 1, 1, 1.0))
	panel.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel",
			UiKit.flat(UiKit.PANEL, base_color, 2, UiKit.SP_3, UiKit.EL_2))
		frame.modulate = Color(1, 1, 1, 0.25))

	_row.add_child(wrap)


func _on_pick(kind: String) -> void:
	if _taken:
		return
	_taken = true
	SfxNode.play("card_select")
	match kind:
		"heal":
			run.hp = mini(RunState.MAX_HP, run.hp + HEAL)
		_:
			run.add_card(kind)
	chosen.emit()
