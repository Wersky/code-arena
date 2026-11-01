class_name MapScreen
extends Control
## 选关界面（2026-11-01 主人钦定）：运行序列的节点路径——
## 战斗 / 事件两种类型；已通关打勾、当前节点高亮可进、后续节点灰。
## 点当前节点（或底部按钮）进入。

signal node_entered(node: Dictionary)
signal run_completed

var run: RunState = null
var _list: VBoxContainer = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(run_state: RunState) -> void:
	run = run_state


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = Art.tex("bg-map")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.03, 0.05, 0.72)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 120
	v.offset_right = -120
	v.offset_top = 50
	v.offset_bottom = -50
	v.add_theme_constant_override("separation", UiKit.SP_3)
	add_child(v)

	var head := UiKit.title("作战路线", UiKit.FS_M)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)

	var stat := UiKit.dim("HP %d/%d ｜ 卡组 %d 张 ｜ 算力 %d" % [
		run.hp, RunState.MAX_HP, run.deck.size(), run.compute], UiKit.FS_XS)
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stat)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", UiKit.SP_1)
	scroll.add_child(_list)

	_build_nodes()


func _build_nodes() -> void:
	var all_done: bool = run.seq_idx >= run.run_seq.size()
	for i in run.run_seq.size():
		var node: Dictionary = run.run_seq[i]
		var done := i < run.seq_idx
		var current := i == run.seq_idx
		var is_battle := String(node.get("type", "")) == "battle"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiKit.SP_3)

		# 节点圆章：战（红）/ 事（金）
		var badge := UiKit.label("战" if is_battle else "事", UiKit.FS_S,
				Color(0.784, 0.298, 0.298) if is_battle else Color(1.0, 0.82, 0.4))
		badge.custom_minimum_size = Vector2(40, 40)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var bs := StyleBoxFlat.new()
		bs.bg_color = UiKit.PANEL_2
		bs.border_color = Color(0.4, 0.45, 0.55) if not (done or current) 				else (StsCardPool.kind_color(StsCard.Kind.ATTACK) if is_battle 						else Color(1.0, 0.82, 0.4))
		bs.set_border_width_all(2)
		bs.set_corner_radius_all(20)
		badge.add_theme_stylebox_override("normal", bs)
		row.add_child(badge)

		var label_text := ""
		if is_battle:
			var lv: LevelData = node["level"]
			label_text = "%s · %s（敌人 %s）" % [lv.id, lv.title, lv.enemy_name]
		else:
			label_text = "事件 · 未知的遭遇"
		if done:
			label_text += "  ✔"
		var lbl := UiKit.label(label_text, UiKit.FS_S,
				UiKit.TEXT if (done or current) else Color(0.45, 0.5, 0.6))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lbl)

		if current and not all_done:
			var go := UiKit.accent_button("进入 ▶", UiKit.FS_XS)
			go.custom_minimum_size = Vector2(120, 40)
			go.pressed.connect(func() -> void: node_entered.emit(run.current_node()))
			row.add_child(go)
		if current and all_done:
			var fin := UiKit.accent_button("查看结算 ▶", UiKit.FS_XS)
			fin.custom_minimum_size = Vector2(140, 40)
			fin.pressed.connect(func() -> void: run_completed.emit())
			row.add_child(fin)
		_list.add_child(row)

	if all_done:
		var t := UiKit.title("全部节点已通关 —— 前往结算！", UiKit.FS_S)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(t)
	else:
		var hint := UiKit.dim("点击高亮节点进入。战斗 = 与捣蛋鬼开战；事件 = 未知遭遇。", UiKit.FS_XS)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(hint)
