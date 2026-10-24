extends Control
class_name ResultScreen
## 通用结算画面：过关 / 通关整局 / 失败。
##
## 按钮由外部传入：[{"text": "重打本关", "id": "retry"}, ...]
## 被点击时发出对应 id 的信号。

signal retry
signal to_menu
signal proceed

var _title: Label = null
var _body: Label = null
var _btn_box: VBoxContainer = null
var _ids: Array[String] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(title: String, body: String, buttons: Array) -> void:
	var bg := TextureRect.new()
	bg.texture = Art.tex("bg-arena")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var veil := ColorRect.new()
	veil.color = Color(0.055, 0.063, 0.09, 0.86)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	add_child(v)

	_title = UiKit.title(title, UiKit.FS_M)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)

	_body = UiKit.label(body, UiKit.FS_XS)
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(700, 0)
	v.add_child(_body)

	v.add_child(UiKit.spacer(10))

	_btn_box = VBoxContainer.new()
	_btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_box.add_theme_constant_override("separation", 10)
	v.add_child(_btn_box)

	_ids.clear()
	for b in buttons:
		var text := str(b.get("text", "确定"))
		var id := str(b.get("id", "proceed"))
		var accent := bool(b.get("accent", false))
		var btn := UiKit.accent_button(text, UiKit.FS_S) if accent else UiKit.button(text, UiKit.FS_S)
		btn.custom_minimum_size = Vector2(320, 50)
		btn.pressed.connect(func() -> void:
			SfxNode.play("ui_click")
			_on_button(id))
		_btn_box.add_child(btn)
		_ids.append(id)


func _on_button(id: String) -> void:
	match id:
		"retry":
			retry.emit()
		"menu":
			to_menu.emit()
		_:
			proceed.emit()
