class_name EventScreen
extends Control
## 事件节点界面（选关地图的「事件」类型）：随机事件 + 两个选项，选完回地图。
## 效果走 RunState（回血 / 加卡），随机性用 run.rng（每局确定）。
##
## 2026-11-03 LLM 接入：AI 启用时由 main.gd 先走 LLMEventEngine 预筛 + LLM pick，
## 本界面负责「叙事 + 槽位效果」展示；AI 关闭/超时/解析失败时仍走原 5 则事件，
## 原路径的节点、文案、按钮与结算逻辑零差异。

signal finished

const EVENTS := [
	{
		"id": "fire",
		"title": "服务器着火了",
		"art": "res://assets/art/event-0.png",
		"text": "机房浓烟滚滚，墙上贴着「机房重地 · 禁止泼水」。你手边恰好有一桶水，水桶在反光。",
		"choices": [
			{"text": "抄灭火器，规范操作（恢复 15K Token）", "hp": 15},
			{"text": "泼水！经典错误（敌人下一战短路 -20K，你损失 5K Token）",
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
			{"text": "「不会，我们是搭档。」（观众感动：+18K Token）", "hp": 18},
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
			{"text": "应战！灵魂对线（气势如虹：敌人下一战 -15K）", "enemy_pre_hp": -15},
			{"text": "拉黑删除，眼不见心不烦（+12K Token）", "hp": 12},
		],
	},
]

var run: RunState = null
var _event_index := 0

## AI 事件路径：先挂「正在挑槽位」的等待态，回调到了再换成结果页。
var _ai_loading := false
var _ai_result: Dictionary = {}
var _ai_reason := ""
var _content: VBoxContainer = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(run_state: RunState, event_index: int) -> void:
	run = run_state
	_event_index = event_index
	_ai_loading = false
	_ai_result = {}
	_ai_reason = ""


## AI 启用且候选池非空：先显示等待态，main.gd 拿到 LLM pick 后调 apply_ai_event()。
func setup_ai_loading(run_state: RunState) -> void:
	run = run_state
	_event_index = 0
	_ai_loading = true
	_ai_result = {}
	_ai_reason = ""


## 应用并展示 AI 事件结果（效果已在 main.gd 本地掷骰并写入 run）。
func apply_ai_event(result: Dictionary, reason: String) -> void:
	_ai_loading = false
	_ai_result = result
	_ai_reason = String(reason)
	if _content != null and is_instance_valid(_content):
		_content.visible = false
		_content.queue_free()
		_content = null
	_build_ai_result()


func _ready() -> void:
	_build_shell()
	if _ai_loading:
		_build_ai_loading()
	else:
		_build_event_ui(EVENTS[_event_index % EVENTS.size()])


func _build_shell() -> void:
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


func _make_content_box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 200
	v.offset_right = -200
	v.offset_top = 120
	v.offset_bottom = -120
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UiKit.SP_4)
	_content = v
	add_child(v)
	return v


# ── 原 5 则事件（AI 关闭时的零差异路径） ──────────────
func _build_event_ui(ev: Dictionary) -> void:
	var v := _make_content_box()

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


# ── AI 事件：等待态 / 结果态 ──────────────────────────
func _build_ai_loading() -> void:
	var v := _make_content_box()

	var head := UiKit.title("事件 · AI 正在挑槽位", UiKit.FS_M)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)

	var body := UiKit.label(
			"模型正在本地预筛的候选池里挑一个槽位。\n数值由本地掷骰，AI 只写一句自嘲。",
			UiKit.FS_S, UiKit.TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(0, 90)
	v.add_child(body)

	var wait := UiKit.dim("…… 3 秒没回来就自动回退热梗事件池", UiKit.FS_S, UiKit.TEXT_DIM)
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wait)


func _build_ai_result() -> void:
	var v := _make_content_box()
	var slot := LLMEventSlots.slot_of(_ai_result.get("slot", -1))
	var slot_name := LLMEventSlots.narrative_name(slot)
	if slot_name == "未知事件":
		slot_name = String(_ai_result.get("name", "未知事件"))
	var slot_id := LLMEventSlots.id_of(slot)
	if slot_id == "NONE":
		slot_id = String(_ai_result.get("id", "?"))

	var head := UiKit.title("事件 · %s" % slot_name, UiKit.FS_M)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)

	# AI 叙事（≤20 字自嘲）；解析失败走本地默认候选时给一句兜底叙事。
	var narrative := _ai_reason.strip_edges()
	if narrative.is_empty():
		narrative = "AI 吃白饭不干活，本地替它挑了一个槽位。"
	var body := UiKit.label(narrative, UiKit.FS_S, UiKit.TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(0, 70)
	v.add_child(body)

	# 槽位效果（UI 叙事名来自 LLMEventSlots 映射表，机械 ID 同时展示便于核对）
	var slot_line := UiKit.label("槽位：%s · %s" % [slot_id, slot_name],
			UiKit.FS_S, UiKit.ACCENT)
	slot_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(slot_line)

	var detail := UiKit.label("效果：%s" % String(_ai_result.get("detail", "")),
			UiKit.FS_S, UiKit.TEXT)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(0, 60)
	v.add_child(detail)

	var net := int(_ai_result.get("net", 0))
	var count := int(_ai_result.get("count", 0))
	var foot := UiKit.dim("净值 %+d ｜ 本局 AI 事件 %d/%d ｜ 数字全部本地掷出"
			% [net, count, LLMEventSlots.MAX_EVENTS_PER_RUN],
			UiKit.FS_XS, UiKit.TEXT_DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(foot)

	v.add_child(Control.new())

	var ok := UiKit.button("收下结果", UiKit.FS_S)
	ok.custom_minimum_size = Vector2(0, 56)
	ok.pressed.connect(func() -> void:
		SfxNode.play("card_select")
		finished.emit())
	v.add_child(ok)


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
