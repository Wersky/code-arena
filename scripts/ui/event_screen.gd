class_name EventScreen
extends Control
## 事件节点界面（选关地图的「事件」类型）：随机事件 + 两个选项，选完回地图。
## 效果走 RunState（回血 / 加卡），随机性用 run.rng（每局确定）。

signal finished

const EVENTS := [
	{
		"id": "fire",
		"title": "服务器着火了",
		"art": "res://assets/art/event-0.png",
		"text": "机房浓烟滚滚，墙上贴着「机房重地 · 禁止泼水」。你手边恰好有一桶水，水桶在反光。",
		"choices": [
			{"text": "抄灭火器，规范操作（回复 15 HP）", "hp": 15},
			{"text": "泼水！经典错误（敌人下一战短路 -20 HP，你被电 5 HP）",
					"enemy_pre_hp": -20, "self_hp": 5},
		],
	},
	{
		"id": "interview",
		"title": "街头采访：AI 会取代人类吗",
		"art": "res://assets/art/event-1.png",
		"text": "记者把话筒怼到你脸上：「你的 AI 女仆这么强，她会取代你吗？」直播间在线人数暴涨。",
		"choices": [
			{"text": "「会，就在明天。」（播出后全网玩梗：本局攻击 +1）", "run_atk": 1},
			{"text": "「不会，我们是搭档。」（观众感动：回复 18 HP）", "hp": 18},
		],
	},
	{
		"id": "temperature",
		"title": "温度旋钮：0 还是 2",
		"art": "res://assets/art/event-2.png",
		"text": "控制台上一个巨大的温度旋钮。老工程师留言：0 是绝对理性，2 是玄学放飞。",
		"choices": [
			{"text": "拧到 0，确定性拉满（下一场战斗手牌 +1）", "hand_next": 1},
			{"text": "拧到 2，玄学放飞（随机一张牌入库）", "card_random": true},
		],
	},
	{
		"id": "alchemy",
		"title": "显卡炼丹炉",
		"art": "res://assets/art/event-3.png",
		"text": "炼丹炉里 ghost 般的 RGB 火苗忽明忽暗。投点什么进去炼一炉？",
		"choices": [
			{"text": "投一张旧显卡（获得随机道具）", "item": true},
			{"text": "投一粒香火钱（获得「电子木鱼」）", "item": "muyu"},
		],
	},
	{
		"id": "feud",
		"title": "百万大 V 求对线",
		"art": "res://assets/art/event-4.png",
		"text": "某百万粉丝大 V 挂出对战书：「你的 AI 就是个复读机！敢不敢现在对线？」",
		"choices": [
			{"text": "应战！灵魂对线（气势如虹：敌人下一战 -15 HP）", "enemy_pre_hp": -15},
			{"text": "拉黑删除，眼不见心不烦（回复 12 HP）", "hp": 12},
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

	# 事件立绘（生图，带趣味的场景演出）
	if ev.has("art") and ResourceLoader.exists(String(ev["art"])):
		var art := TextureRect.new()
		art.texture = load(String(ev["art"]))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(0, 260)
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		v.add_child(art)

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
	if ch.has("self_hp"):
		run.hp = maxi(1, run.hp - int(ch["self_hp"]))
	if ch.has("enemy_pre_hp"):
		run.next_pre_hp += int(ch["enemy_pre_hp"])
	if ch.has("run_atk"):
		run.run_atk_bonus += int(ch["run_atk"])
	if ch.has("hand_next"):
		run.next_hand_bonus += int(ch["hand_next"])
	if ch.has("card"):
		var card_id := String(ch["card"])
		if card_id == "any_attack":
			card_id = "fish_ram"
		run.add_card(card_id)
	if ch.has("card_random"):
		var ids: Array[String] = ["fish_ram", "taunt", "rice"]
		run.add_card(ids[run.rng.randi_range(0, ids.size() - 1)])
	if ch.has("item"):
		var item_id := String(ch["item"]) if not bool(ch["item"]) else StsItemPool.random_id(run.rng)
		var it := StsItemPool.make(item_id)
		if it != null:
			run.add_item(it)
	finished.emit()
