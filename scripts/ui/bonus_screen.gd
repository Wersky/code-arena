class_name BonusScreen
extends Control
## 奖励关卡（10% 掷中）：宝箱点开 → 随机道具入包 → 回选关。

signal finished

var run: RunState = null
var _opened := false


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
	veil.color = Color(0.02, 0.03, 0.05, 0.7)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UiKit.SP_4)
	add_child(v)

	var head := UiKit.title("奖励关卡 · 宝箱", UiKit.FS_M)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)

	var chest := TextureRect.new()
	chest.texture = load("res://assets/art/chest.png")
	chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chest.custom_minimum_size = Vector2(280, 280)
	chest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chest.pivot_offset = Vector2(140, 140)
	chest.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_child(chest)

	var result := UiKit.label("", UiKit.FS_S, Color(1.0, 0.82, 0.4))
	result.name = "Result"
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.custom_minimum_size = Vector2(0, 60)
	v.add_child(result)

	var open_btn := UiKit.accent_button("开箱 ▶", UiKit.FS_S)
	open_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	open_btn.pressed.connect(_on_open.bind(chest, result))
	v.add_child(open_btn)

	var back := UiKit.button("继续旅程", UiKit.FS_XS)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.visible = false
	back.pressed.connect(func() -> void: finished.emit())
	back.name = "BackBtn"
	v.add_child(back)


func _on_open(chest: TextureRect, result: Label) -> void:
	if _opened:
		return
	_opened = true
	SfxNode.play("win")
	var it := run.grant_elite_chest()
	if it != null:
		result.text = "获得【%s】！
%s" % [it.display_name, it.description]
	else:
		result.text = "空箱子……"
	chest.pivot_offset = chest.size * 0.5
	var tw := chest.create_tween()
	tw.tween_property(chest, "scale", Vector2(1.15, 1.15), 0.2)
	tw.parallel().tween_property(chest, "rotation", 0.06, 0.2)
	tw.tween_property(chest, "scale", Vector2.ONE, 0.2)
	tw.parallel().tween_property(chest, "rotation", 0.0, 0.2)
	(get_node_or_null("BackBtn") as Control).visible = true