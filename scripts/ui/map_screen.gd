class_name MapScreen
extends Control
## 选关界面（2026-11-01 主人钦定改版）：战斗/事件各一道大门，点门进入。
## 事件门冷却：每打完一场战斗可用 1 次（防无限刷事件）。

signal battle_entered
signal event_entered
signal bonus_entered
signal elite_entered
signal shop_entered

var run: RunState = null
var special := ""   ## "" 纯战斗 ｜ "event" 事件门 ｜ "bonus" 奖励门
var _door_battle: Control = null
var _door_event: Control = null
var _door_bonus: Control = null
var _chosen := false   ## 每次回到门界面只能选一个（2026-11-01 主人钦定）


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(run_state: RunState, special_kind: String = "") -> void:
	run = run_state
	special = special_kind


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = Art.tex("bg-map")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.03, 0.05, 0.6)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 120
	v.offset_right = -120
	v.offset_top = 40
	v.offset_bottom = -40
	v.add_theme_constant_override("separation", UiKit.SP_3)
	add_child(v)

	var head := UiKit.title("选择你的道路", UiKit.FS_M)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)

	var stat := UiKit.dim("Token %dK/%dK ｜ 卡组 %d 张 ｜ 已通关 %d/10" % [
		run.hp, RunState.MAX_HP, run.deck.size(), run.level_index], UiKit.FS_XS)
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stat)

	var doors := HBoxContainer.new()
	doors.size_flags_vertical = Control.SIZE_EXPAND_FILL
	doors.alignment = BoxContainer.ALIGNMENT_CENTER
	doors.add_theme_constant_override("separation", 90)
	v.add_child(doors)

	var all_done: bool = run.level_index >= 10

	# ── 事件之门（40% 掷中才出现）──
	if special == "event":
		var event_locked: bool = run.events_since_battle >= 1 and not all_done
		var ewrap := _make_door("res://assets/art/door-event.png",
				Color(1.0, 0.82, 0.4), not event_locked and not all_done,
				func() -> void: event_entered.emit())
		_door_event = ewrap
		doors.add_child(ewrap)
		var ecap := ewrap.get_meta("cap") as Label
		ecap.text = "神秘遭遇" if not event_locked else "冷却中 · 先打一场战斗"
		if event_locked:
			ewrap.modulate = Color(0.5, 0.5, 0.55, 0.85)

	# ── 精英之门（20% 掷中才出现）：强制精英战，必掉宝箱 ──
	if special == "elite":
		var elite_wrap := _make_door("res://assets/art/door-elite.png",
				Color(1.0, 0.23, 0.23), not all_done,
				func() -> void: elite_entered.emit())
		doors.add_child(elite_wrap)
		var elite_cap := elite_wrap.get_meta("cap") as Label
		elite_cap.text = "精英怪 · 必掉宝箱"

	# ── 商店之门（10% 掷中才出现）：金币买好感礼物 ──
	if special == "shop":
		var shop_wrap := _make_door("res://assets/art/door-shop.png",
				Color(0.95, 0.75, 0.4), not all_done,
				func() -> void: shop_entered.emit())
		doors.add_child(shop_wrap)
		var shop_cap := shop_wrap.get_meta("cap") as Label
		shop_cap.text = "Deep Sick 的商店 · 金币买好感礼物"

	# ── 奖励之门（10% 掷中才出现）：宝箱直接开道具 ──
	if special == "bonus":
		var chest_wrap := _make_door("res://assets/art/chest.png",
				Color(1.0, 0.82, 0.4), not all_done,
				func() -> void: bonus_entered.emit())
		_door_bonus = chest_wrap
		doors.add_child(chest_wrap)
		var chest_cap := chest_wrap.get_meta("cap") as Label
		chest_cap.text = "奖励关卡 · 开宝箱得道具"

	# ── 战斗之门 ──
	var bwrap := _make_door("res://assets/art/door-battle.png",
			Color(0.784, 0.298, 0.298), not all_done,
			func() -> void: battle_entered.emit())
	_door_battle = bwrap
	doors.add_child(bwrap)
	var bnext := bwrap.get_meta("cap") as Label
	if all_done:
		bnext.text = "已全部通关"
	else:
		var lv: LevelData = LevelPool.all_levels()[run.level_index]
		bnext.text = "第 %d 战 · 敌人：%s" % [run.level_index + 1, lv.enemy_name]

	# （事件门 / 奖励门按掷骰出现，见上方 special 分支）

	var hint := UiKit.dim("点门进入。战斗推进路线；每次抵达掷遭遇：50% 战斗 ｜ 40% 事件 ｜ 10% 奖励关。", UiKit.FS_XS)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func _make_door(tex_path: String, col: Color, clickable: bool,
		on_click: Callable) -> Control:
	var chosen_guard := func() -> bool:
		if _chosen:
			return false
		_chosen = true
		if _door_battle != null:
			_door_battle.modulate = Color(0.6, 0.6, 0.65)
		if _door_event != null:
			_door_event.modulate = Color(0.6, 0.6, 0.65)
		return true
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", UiKit.SP_2)

	var door := TextureRect.new()
	door.name = "DoorArt"
	door.texture = load(tex_path)
	door.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	door.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	door.custom_minimum_size = Vector2(430, 560)
	door.size_flags_vertical = Control.SIZE_EXPAND_FILL
	door.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	door.mouse_filter = Control.MOUSE_FILTER_STOP
	door.pivot_offset = Vector2(215, 280)
	wrap.add_child(door)

	var glow := UiKit.label("", UiKit.FS_S, col)
	glow.name = "DoorGlow"
	glow.custom_minimum_size = Vector2(0, 26)
	glow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(glow)

	var cap := UiKit.label("", UiKit.FS_XS, UiKit.TEXT_DIM)
	cap.name = "DoorCap"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.custom_minimum_size = Vector2(0, 20)
	wrap.add_child(cap)
	wrap.set_meta("cap", cap)

	if clickable:
		door.mouse_entered.connect(func() -> void:
			door.modulate = Color(1.12, 1.12, 1.15)
			door.scale = Vector2(1.03, 1.03)
			glow.text = "▶ 进入")
		door.mouse_exited.connect(func() -> void:
			door.modulate = Color.WHITE
			door.scale = Vector2.ONE
			glow.text = "")
		door.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
					and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				if not chosen_guard.call():
					return
				SfxNode.play("ui_click")
				on_click.call())
	return wrap
