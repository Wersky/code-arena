class_name EventScreen
extends Control
## 事件节点界面（选关地图的「事件」类型）：随机事件 + 两个选项，选完回地图。
## 效果走 RunState（回血 / 加卡），随机性用 run.rng（每局确定）。

signal finished

const EVENTS := [
	{
		"title": "午夜算力泉",
		"text": "地图边缘有一汪泛着蓝光的算力泉。泉水低语：喝下我，或者捞点什么。",
		"choices": [
			{"text": "深潜（回复 18 HP）", "hp": 18},
			{"text": "捞一张攻击牌", "card": "any_attack"},
		],
	},
	{
		"title": "迷路的调试精灵",
		"text": "一只 _debug 精灵卡在死循环里，抱着终端嘤嘤哭泣。",
		"choices": [
			{"text": "帮它修段代码（获得「来打我呀！」）", "card": "taunt"},
			{"text": "无视它走开（回复 10 HP）", "hp": 10},
		],
	},
	{
		"title": "褪色的记忆缓存",
		"text": "一段旧缓存里存着前代模型的食谱备份……看起来还能吃。",
		"choices": [
			{"text": "读旧日志（获得一张白米饭）", "card": "rice"},
			{"text": "一键清空（回复 14 HP）", "hp": 14},
		],
	},
]

var run: RunState = null
var _event_index := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(run_state: RunState, event_index: int) -> void:
	run = run_state
	_event_index = event_index


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = Art.tex("bg-arena")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.03, 0.05, 0.86)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var ev: Dictionary = EVENTS[_event_index % EVENTS.size()]
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 200
	v.offset_right = -200
	v.offset_top = 120
	v.offset_bottom = -120
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UiKit.SP_4)
	add_child(v)

	var head := UiKit.title("事件 · %s" % str(ev["title"]), UiKit.FS_M)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)

	var body := UiKit.label(str(ev["text"]), UiKit.FS_S, UiKit.TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(0, 60)
	v.add_child(body)

	v.add_child(Control.new())

	var idx := 0
	for ch in ev["choices"]:
		var btn := UiKit.button("%d.  %s" % [idx + 1, str(ch["text"])], UiKit.FS_S)
		btn.custom_minimum_size = Vector2(0, 56)
		btn.pressed.connect(_on_choice.bind(ch))
		v.add_child(btn)
		idx += 1


func _on_choice(ch: Dictionary) -> void:
	SfxNode.play("card_select")
	if ch.has("hp"):
		run.hp = mini(RunState.MAX_HP, run.hp + int(ch["hp"]))
	if ch.has("card"):
		var card_id := String(ch["card"])
		if card_id == "any_attack":
			card_id = "fish_ram"
		run.add_card(card_id)
	finished.emit()
