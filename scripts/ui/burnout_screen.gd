class_name BurnoutScreen
extends Control
## 燃尽画面（2026-11-01 主人钦定）：额度耗尽 → 全屏黑 → AI 娘跪居中（45°俯视
## 双手撑地失落姿，生图）→ 「燃尽了」烧焦大字浮现 → 余烬飘落 → 按钮浮现
## （重试 / 回到主界面）。

signal retry_requested
signal menu_requested

var _maid: TextureRect = null
var _title: TextureRect = null
var _btns: VBoxContainer = null
var _ember_timer: Timer = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	# 全屏黑（主人的设定：额度耗尽 → 全屏黑）
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)

	# AI 娘跪姿（居中，45°俯视失落姿）——缓慢下沉，像力竭
	_maid = TextureRect.new()
	_maid.texture = load("res://assets/art/deepseek-kneel.png")
	_maid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_maid.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_maid.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_maid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_maid.modulate = Color(0.82, 0.82, 0.88)
	add_child(_maid)

	# 「燃尽了」烧焦大字（AI 生图）——浮现 + 轻微漂浮
	_title = TextureRect.new()
	_title.texture = load("res://assets/art/title-burnout.png")
	_title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.modulate = Color(1, 1, 1, 0)
	add_child(_title)

	_layout()

	# 女仆缓慢下沉（力竭感）
	var sink := _maid.create_tween()
	sink.tween_property(_maid, "position:y", _maid.position.y + 14.0, 4.0) 			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 大字延迟浮现 + 永久轻漂浮
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(_title, "modulate:a", 1.0, 0.9) 			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		var float_tw := _title.create_tween().set_loops()
		float_tw.tween_property(_title, "position:y", _title.position.y - 10.0, 1.6) 				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		float_tw.tween_property(_title, "position:y", _title.position.y + 10.0, 1.6) 				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))

	# 余烬飘落
	_ember_timer = Timer.new()
	_ember_timer.wait_time = 0.14
	_ember_timer.timeout.connect(_spawn_ember)
	add_child(_ember_timer)
	_ember_timer.start()

	SfxNode.play("fx_burnout")

	# 按钮延迟浮现
	var btn_tw := create_tween()
	btn_tw.tween_interval(2.4)
	btn_tw.tween_callback(_show_buttons)


func _layout() -> void:
	var W := size.x
	var H := size.y
	if _maid != null:
		_maid.size = Vector2(minf(520.0, H * 0.52), minf(520.0, H * 0.52))
		_maid.position = Vector2(W * 0.5 - _maid.size.x * 0.5, H * 0.52 - _maid.size.y * 0.35)
	if _title != null:
		_title.size = Vector2(minf(680.0, W * 0.6), minf(680.0, W * 0.6) * 0.98)
		_title.position = Vector2(W * 0.5 - _title.size.x * 0.5, H * 0.1)
	if _btns != null:
		_btns.position = Vector2(W * 0.5 - 150.0, H * 0.86)


func _show_buttons() -> void:
	_btns = VBoxContainer.new()
	_btns.add_theme_constant_override("separation", UiKit.SP_3)
	add_child(_btns)
	_layout()

	var retry := UiKit.button("重整旗鼓 · 重试本关", UiKit.FS_XS, false)
	retry.custom_minimum_size = Vector2(300, 42)
	retry.modulate.a = 0.0
	retry.pressed.connect(func() -> void:
		SfxNode.play("ui_click")
		retry_requested.emit())
	_btns.add_child(retry)

	var menu := UiKit.accent_button("回到主界面", UiKit.FS_S)
	menu.custom_minimum_size = Vector2(300, 48)
	menu.modulate.a = 0.0
	menu.pressed.connect(func() -> void:
		SfxNode.play("ui_click")
		menu_requested.emit())
	_btns.add_child(menu)

	var bt := create_tween()
	bt.set_parallel(true)
	bt.tween_property(retry, "modulate:a", 0.85, 0.5)
	bt.tween_property(menu, "modulate:a", 1.0, 0.5)


## 余烬：小橙粒从画面上方飘落（随机漂移 + 渐隐）
func _spawn_ember() -> void:
	if not is_inside_tree():
		return
	var e := ColorRect.new()
	var s := randf_range(3.0, 7.0)
	e.size = Vector2(s, s)
	e.color = Color(1.0, randf_range(0.42, 0.62), 0.2, randf_range(0.5, 0.9))
	e.position = Vector2(randf_range(0, size.x), -10.0)
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(e)
	move_child(e, get_child_count() - 2)   ## 余烬垫在按钮下
	var drift := randf_range(-40.0, 40.0)
	var tw := e.create_tween()
	tw.set_parallel(true)
	tw.tween_property(e, "position:y", size.y + 12.0, randf_range(2.4, 4.2))
	tw.tween_property(e, "position:x", e.position.x + drift, randf_range(2.4, 4.2)) 			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(e, "modulate:a", 0.0, randf_range(2.0, 3.0)).set_delay(1.2)
	tw.chain().tween_callback(func() -> void: e.queue_free())
