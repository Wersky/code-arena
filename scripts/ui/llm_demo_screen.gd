class_name LLMDemoScreen
extends Control
## 本次改动 Demo v2（2026-11-03）：真交互演示，不是文字说明。
## - 迷你对战：真实 StsCombat + 五动作规则层，玩家真出牌、AI 真决策
## - 事件引擎：真实 apply 到 RunState，预算/HP 真变化
## - 小鲸：真实气泡组件，四个钩子真弹
## - 解析器：可输入任意文本，实时看四层容错结果
## - 配置：一键从 ZCode 的 goat 分组导入（真读 provider_config.json 并写游戏配置）
## 入口：启动界面「本次改动 Demo」；返回：back_requested。

signal back_requested
## 一键直进（2026-11-04 主人钦定）：不看说明，直接像平常那样进 AI 战斗 / AI 事件
signal start_ai_battle
signal start_ai_event

const W := 1600.0
const H := 900.0

var _content: Control
var _tab_btns: Array[Button] = []
var _tab := 0
var _status: Label

# 战斗
var _combat: StsCombat
var _battle_info: Label
var _hand_row: HBoxContainer
var _battle_log: RichTextLabel
var _battle_lines: Array[String] = []

# 事件
var _event_run: RunState
var _event_cands: Array = []
var _event_info: Label
var _event_out: RichTextLabel
var _event_box: VBoxContainer

# 小鲸
var _banter: AIBanter

# 解析
var _parse_text := "ATTACK\n\n检测到非法连击，已加入回收队列。"
var _parse_mode := 0
var _parse_input: LineEdit
var _parse_out: RichTextLabel

# 配置
var _cfg_out: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	_build_header()
	_build_left()
	_build_right()
	_ensure_banter()
	_switch_tab(0)


func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.016, 0.032)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var line := ColorRect.new()
	line.color = Color(0.10, 0.22, 0.38, 0.35)
	line.size = Vector2(W, 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)


func _build_header() -> void:
	var title := UiKit.label("本次改动 Demo · LLM 接入全链路", 32, Color(0.92, 0.95, 1.0))
	title.position = Vector2(60, 42)
	title.size = Vector2(900, 42)
	add_child(title)
	var sub := UiKit.dim("真交互：迷你对战 / 事件应用 / 小鲸气泡 / 解析器 / ZCode goat 导入 ｜ smoke 323", 15, Color(0.55, 0.72, 0.9))
	sub.position = Vector2(62, 88)
	sub.size = Vector2(1100, 22)
	add_child(sub)
	var back := UiKit.accent_button("← 返回主界面", 16)
	back.position = Vector2(1330, 48)
	back.size = Vector2(210, 44)
	back.pressed.connect(func() -> void: back_requested.emit())
	add_child(back)


func _build_left() -> void:
	var panel := UiKit.panel_box(Color(0.045, 0.06, 0.10, 0.96), Color(0.16, 0.30, 0.48), 16)
	panel.position = Vector2(60, 132)
	panel.size = Vector2(440, 710)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	# 一键直进：主人钦定的入口，按钮大、文案直白，点进去就是平常的战斗/事件
	v.add_child(UiKit.label("直接体验（像平常战斗一样）", 19, Color(0.55, 0.85, 1.0)))
	var battle_btn := UiKit.button("⚔  直接进入 AI 对战", 24)
	battle_btn.custom_minimum_size = Vector2(0, 88)
	battle_btn.pressed.connect(func() -> void:
		SfxNode.play("ui_click")
		start_ai_battle.emit())
	v.add_child(battle_btn)
	var event_btn := UiKit.button("🎲  直接进入 AI 事件", 24)
	event_btn.custom_minimum_size = Vector2(0, 88)
	event_btn.pressed.connect(func() -> void:
		SfxNode.play("ui_click")
		start_ai_event.emit())
	v.add_child(event_btn)
	v.add_child(UiKit.dim("战斗中左下角鲸鱼脸满了可以放终结技\n按 F1 也能随时看终结技演出", 13, Color(0.58, 0.68, 0.82)))
	v.add_child(UiKit.rule())
	v.add_child(UiKit.label("技术细节（可展开看）", 16, Color(0.85, 0.92, 1.0)))
	var rows := [
		["AI 对手", "五动作 + 三标记 + 本地兜底\nATTACK / DEFEND / CHARGE / MARK / TAUNT"],
		["AI 事件", "8 机械槽位 + 本地预筛 + 预算钳\nLLM 只池内挑，数值全本地掷"],
		["AI 娘小鲸", "三份 prompt + 4 钩子 + 回怼\n0.5s 延迟 / 3s 丢弃 / 本地兜底"],
	]
	for r in rows:
		var d := UiKit.dim("%s：%s" % [String(r[0]), String(r[1]).replace("\n", " ")], 12, Color(0.52, 0.62, 0.76))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(400, 0)
		v.add_child(d)
		v.add_child(UiKit.spacer(2))


func _build_right() -> void:
	var panel := UiKit.panel_box(Color(0.03, 0.045, 0.08, 0.97), Color(0.16, 0.30, 0.48), 14)
	panel.position = Vector2(530, 132)
	panel.size = Vector2(1010, 710)
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	outer.add_child(tabs)
	var names := ["总览", "⚔ 真对战", "事件", "小鲸", "解析器", "goat 导入", "平衡"]
	for i in names.size():
		var b := UiKit.button(String(names[i]), 13)
		b.custom_minimum_size = Vector2(0, 32)
		b.pressed.connect(func() -> void: _switch_tab(i))
		tabs.add_child(b)
		_tab_btns.append(b)
	outer.add_child(UiKit.rule())

	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.custom_minimum_size = Vector2(970, 610)
	outer.add_child(_content)


func _switch_tab(idx: int) -> void:
	_tab = idx
	for i in _tab_btns.size():
		_tab_btns[i].modulate = Color(1, 1, 1) if i == idx else Color(0.62, 0.68, 0.78)
	for c in _content.get_children():
		c.queue_free()
	match idx:
		0: _build_overview()
		1: _build_battle()
		2: _build_event()
		3: _build_banter()
		4: _build_parse()
		5: _build_config()
		6: _build_balance()


# ══ 总览 ═════════════════════════════════════════════

func _build_overview() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.add_theme_constant_override("separation", 8)
	_content.add_child(v)
	var lines := [
		["[b]这次不是文字说明，下面每个页签都能真操作。[/b]", "#7ec8f0"],
		["⚔ 真对战：真实 StsCombat，玩家点手牌、发送，AI 观察者按五动作规则层做决策（本地兜底）。", "#dcebf5"],
		["事件：真实生成候选池并 apply 到 RunState，HP / 预算 / 槽位会真的变化。", "#dcebf5"],
		["小鲸：真实 AIBanter 气泡，四个钩子点一下真的弹。", "#dcebf5"],
		["解析器：随便输入文本，实时看四层容错 / 事件三关的结果。", "#dcebf5"],
		["goat 导入：真读 ZCode 的 goat-claude 配置（base/key/模型），一键写进游戏 LLM 配置。", "#dcebf5"],
		["", "#dcebf5"],
		["真实使用：主界面「AI 接入」或 F2 → 开总开关；AI 对手仅在普通战斗生效，精英/Boss 走规则。", "#8b9bb4"],
	]
	for l in lines:
		var lbl := UiKit.label(String(l[0]), 16, Color(0.82, 0.88, 0.98))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(930, 0)
		v.add_child(lbl)


# ══ 战斗（真交互）════════════════════════════════════

func _build_battle() -> void:
	if _combat == null:
		_reset_battle()
	_battle_info = UiKit.label("", 15, Color(0.85, 0.92, 1.0))
	_battle_info.position = Vector2(8, 8)
	_battle_info.size = Vector2(940, 24)
	_content.add_child(_battle_info)

	_hand_row = HBoxContainer.new()
	_hand_row.position = Vector2(8, 42)
	_hand_row.size = Vector2(940, 46)
	_hand_row.add_theme_constant_override("separation", 8)
	_content.add_child(_hand_row)

	var send := UiKit.accent_button("发送执行 ▶", 15)
	send.position = Vector2(8, 96)
	send.size = Vector2(160, 40)
	send.pressed.connect(_on_send)
	_content.add_child(send)
	var reset := UiKit.button("重置战斗", 14)
	reset.position = Vector2(180, 96)
	reset.size = Vector2(120, 40)
	reset.pressed.connect(func() -> void:
		_reset_battle()
		_switch_tab(1))
	_content.add_child(reset)

	_battle_log = RichTextLabel.new()
	_battle_log.bbcode_enabled = true
	_battle_log.scroll_active = true
	_battle_log.position = Vector2(8, 146)
	_battle_log.size = Vector2(940, 440)
	_battle_log.add_theme_font_override("normal_font", PixelTheme.font())
	_battle_log.add_theme_font_size_override("normal_font_size", 15)
	_content.add_child(_battle_log)
	_refresh_battle()


func _reset_battle() -> void:
	_combat = StsCombat.new()
	_combat.setup(StsCardPool.starter_deck(), "幻觉幼虫", 40,
			[{"kind": "attack", "value": 7}, {"kind": "defend", "value": 4},
			{"kind": "attack", "value": 7}], 80, 12345)
	_combat.set_ai_id("deepdeek")
	_battle_lines.clear()
	_battle_line("战斗开始：你 80K Token vs 幻觉幼虫 40 故障强度。")


func _battle_line(s: String) -> void:
	_battle_lines.append(s)
	if _battle_lines.size() > 12:
		_battle_lines.pop_front()


func _refresh_battle() -> void:
	if _combat == null or _battle_info == null:
		return
	var intent := String(_combat.intent.get("kind", "?"))
	var intent_v := int(_combat.intent.get("value", 0))
	var intent_txt := ("攻击 %d" % intent_v) if intent == "attack" else ("防御 %d" % intent_v)
	_battle_info.text = "回合 %d ｜ 你 %dK/80K ｜ 敌 %d/40 ｜ 敌格挡 %d ｜ 意图：%s" % [
		_combat.turn, _combat.hp, _combat.enemy_hp, _combat.enemy_block, intent_txt]

	for c in _hand_row.get_children():
		c.queue_free()
	if _combat.over != StsCombat.Result.RUNNING:
		var done := UiKit.label(
			"战斗结束：%s" % ("胜利" if _combat.over == StsCombat.Result.WIN else "失败"),
			16, Color(0.7, 0.9, 0.7))
		_hand_row.add_child(done)
	else:
		for i in _combat.hand.size():
			var card: StsCard = _combat.hand[i]
			var label := StsCardPool.card_name(card.id)
			if card.kind == StsCard.Kind.ATTACK:
				label += " ⚔%d" % card.damage
			elif card.kind == StsCard.Kind.SKILL and card.block > 0:
				label += " 🛡%d" % card.block
			var b := UiKit.button(label, 13)
			b.custom_minimum_size = Vector2(150, 40)
			b.disabled = i != 0 or _combat.over != StsCombat.Result.RUNNING
			b.pressed.connect(_on_hand_card.bind(i))
			_hand_row.add_child(b)

	var text := ""
	for s in _battle_lines:
		text += s + "\n"
	_battle_log.text = text
	_battle_log.scroll_to_line(_battle_log.get_line_count())


func _on_hand_card(idx: int) -> void:
	if _combat == null or idx != 0:
		return
	var c: StsCard = _combat.hand[0]
	var ev := _combat.play_card(c, false, true, _combat.hand.size() == 1)
	if bool(ev.get("ok", false)):
		match String(ev.get("kind", "")):
			"attack":
				_battle_line("你出「%s」→ 造成 %d 伤害。" % [StsCardPool.card_name(c.id), int(ev.get("value", 0))])
			"defend":
				_battle_line("你出「%s」→ 护盾 +%d。" % [StsCardPool.card_name(c.id), int(ev.get("value", 0))])
			"rice":
				_battle_line("你吃「%s」→ 累计 %d 碗。" % [StsCardPool.card_name(c.id), int(ev.get("value", 0))])
			_:
				_battle_line("你出「%s」。" % StsCardPool.card_name(c.id))
	_refresh_battle()


func _on_send() -> void:
	if _combat == null or _combat.over != StsCombat.Result.RUNNING:
		return
	# 把剩余手牌按顺序执行（首位标记给第一张）
	var first := true
	while not _combat.hand.is_empty() and _combat.can_play(_combat.hand[0]):
		var c: StsCard = _combat.hand[0]
		var ev := _combat.play_card(c, false, first, _combat.hand.size() == 1)
		first = false
		if bool(ev.get("ok", false)):
			_battle_line("执行「%s」：%s +%d" % [StsCardPool.card_name(c.id), String(ev.get("kind", "")), int(ev.get("value", 0))])
	_combat.end_send()
	if _combat.over != StsCombat.Result.RUNNING:
		_refresh_battle()
		return
	# AI 观察者：真实走五动作规则层（本地兜底；AI 开启时会换成 LLM）
	var act := LLMOpponentPool.local_choose(_combat)
	var events := _combat.apply_ai_action(act, "观察者")
	_battle_line("AI 观察者决策：%s（%s）" % [act, LLMOpponentPool.action_ui_name(act)])
	for e in events:
		var k := String(e.get("kind", ""))
		if k == "enemy_attack":
			_battle_line("  → 敌攻击 %d，你实际掉 %d。" % [int(e.get("value", 0)), int(e.get("dealt", 0))])
		elif k == "enemy_defend":
			_battle_line("  → 敌防御 +%d。" % int(e.get("value", 0)))
		elif k == "enemy_mark":
			_battle_line("  → 敌标记：%s。" % String(e.get("mode", "")))
		elif k == "enemy_taunt":
			_battle_line("  → 敌嘲讽：吞掉你的首位加成。")
		elif k == "new_turn":
			_battle_line("  → 新回合 %d，手牌已补。" % int(e.get("turn", 0)))
	_refresh_battle()


# ══ 事件（真应用）════════════════════════════════════

func _build_event() -> void:
	if _event_run == null:
		_event_run = RunState.new()
		_event_run.reset_run()
	_event_info = UiKit.label("", 15, Color(0.85, 0.92, 1.0))
	_event_info.position = Vector2(8, 8)
	_event_info.size = Vector2(940, 24)
	_content.add_child(_event_info)
	var gen := UiKit.accent_button("生成候选池", 15)
	gen.position = Vector2(8, 40)
	gen.size = Vector2(150, 38)
	gen.pressed.connect(_gen_event_candidates)
	_content.add_child(gen)
	_event_box = VBoxContainer.new()
	_event_box.position = Vector2(8, 88)
	_event_box.size = Vector2(940, 150)
	_event_box.add_theme_constant_override("separation", 6)
	_content.add_child(_event_box)
	_event_out = RichTextLabel.new()
	_event_out.bbcode_enabled = true
	_event_out.scroll_active = true
	_event_out.position = Vector2(8, 250)
	_event_out.size = Vector2(940, 330)
	_event_out.add_theme_font_override("normal_font", PixelTheme.font())
	_event_out.add_theme_font_size_override("normal_font_size", 15)
	_content.add_child(_event_out)
	_refresh_event_info()
	_event_out.text = "点「生成候选池」→ 再点一个候选 → 效果会真的写进本局 RunState。"


func _refresh_event_info() -> void:
	if _event_info == null or _event_run == null:
		return
	_event_info.text = "本局 AI 事件：已用 %d 次 ｜ 剩余预算 %d ｜ 当前 HP %d/80 ｜ 累计净值 %+d" % [
		LLMEventEngine.event_count(_event_run), LLMEventEngine.budget_left(_event_run),
		_event_run.hp, LLMEventEngine.total_net(_event_run)]


func _gen_event_candidates() -> void:
	if _event_run == null:
		return
	for c in _event_box.get_children():
		c.queue_free()
	_event_cands = LLMEventEngine.build_candidates(_event_run, _event_run.rng)
	if _event_cands.is_empty():
		_event_out.text = "当前没有合法候选（预算用尽 / 负面槽门槛未满足）。"
		return
	for c in _event_cands:
		var tag := "负面" if bool(c.get("negative", false)) else "正面"
		var b := UiKit.button("#%d %s（%s）%+d~%+d" % [
			int(c.get("index", 0)), String(c.get("name", "")), tag,
			int(c.get("net_min", 0)), int(c.get("net_max", 0))], 14)
		b.custom_minimum_size = Vector2(0, 38)
		b.pressed.connect(_apply_event.bind(int(c.get("index", 1))))
		_event_box.add_child(b)
	_event_out.text = "候选已生成，点上面任意一项真实应用。"
	_refresh_event_info()


func _apply_event(pick: int) -> void:
	if _event_run == null or _event_cands.is_empty():
		return
	var res := LLMEventEngine.apply_pick(_event_run, _event_cands, pick)
	if res is Dictionary and bool(res.get("ok", false)):
		_event_out.text = "[color=#7ee787]已应用[/color] %s（%s）\n净值 %+d ｜ %s\n\n本局已用 %d 次，剩余预算 %d，HP %d/80。" % [
			String(res.get("id", "")), String(res.get("name", "")),
			int(res.get("net", 0)), String(res.get("detail", res.get("text", ""))),
			LLMEventEngine.event_count(_event_run), LLMEventEngine.budget_left(_event_run), _event_run.hp]
	else:
		_event_out.text = "[color=#ff8f8f]应用失败：%s[/color]" % String(res.get("error", "未知"))
	for c in _event_box.get_children():
		c.queue_free()
	_event_cands = []
	_refresh_event_info()


# ══ 小鲸（真气泡）════════════════════════════════════

func _ensure_banter() -> void:
	if _banter != null:
		return
	_banter = AIBanter.new()
	_banter.name = "DemoBanter"
	_banter.position = Vector2(1180, 560)
	_banter.size = Vector2(340, 200)
	add_child(_banter)
	_banter.setup(null, Callable())


func _build_banter() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(8, 8)
	v.size = Vector2(700, 560)
	v.add_theme_constant_override("separation", 10)
	_content.add_child(v)
	v.add_child(UiKit.label("点按钮，右下角会真的弹出小鲸气泡（本地兜底台词）", 15, Color(0.7, 0.85, 1.0)))
	var btns := [
		["开场问候", func() -> void: _banter.battle_started()],
		["连段喝彩（3 阶）", func() -> void: _banter.on_streak(3, 1)],
		["濒危关心（HP 10/80）", func() -> void: _banter.on_hp_changed(10, 80)],
		["回怼敌人「你已急哭。」", func() -> void: _banter.notify_enemy_line("你已急哭。")],
	]
	for b in btns:
		var btn := UiKit.button(String(b[0]), 14)
		btn.custom_minimum_size = Vector2(260, 40)
		btn.pressed.connect(b[1])
		v.add_child(btn)
	var tip := UiKit.dim("规则：同帧多钩只播 1 条其余顺延；回怼延迟 0.5s；LLM 超 3s 丢弃先播兜底；每场限次。", 13, Color(0.55, 0.68, 0.82))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(620, 0)
	v.add_child(tip)


# ══ 解析器（真输入）══════════════════════════════════

func _build_parse() -> void:
	var mode := OptionButton.new()
	mode.add_item("动作（首行动作词+台词）")
	mode.add_item("事件（JSON pick+reason）")
	mode.add_item("台词（自由文本清洗）")
	mode.selected = _parse_mode
	mode.position = Vector2(8, 8)
	mode.size = Vector2(260, 36)
	mode.item_selected.connect(func(i: int) -> void:
		_parse_mode = i
		_run_parse())
	_content.add_child(mode)

	_parse_input = LineEdit.new()
	_parse_input.text = _parse_text
	_parse_input.position = Vector2(280, 8)
	_parse_input.size = Vector2(560, 36)
	_parse_input.add_theme_font_override("font", PixelTheme.font())
	_parse_input.add_theme_font_size_override("font_size", 14)
	_parse_input.text_changed.connect(func(t: String) -> void: _parse_text = t)
	_content.add_child(_parse_input)

	var go := UiKit.accent_button("解析", 14)
	go.position = Vector2(850, 8)
	go.size = Vector2(90, 36)
	go.pressed.connect(_run_parse)
	_content.add_child(go)

	_parse_out = RichTextLabel.new()
	_parse_out.bbcode_enabled = true
	_parse_out.position = Vector2(8, 56)
	_parse_out.size = Vector2(940, 520)
	_parse_out.add_theme_font_override("normal_font", PixelTheme.font())
	_parse_out.add_theme_font_size_override("normal_font_size", 15)
	_content.add_child(_parse_out)
	_run_parse()


func _run_parse() -> void:
	if _parse_out == null:
		return
	var raw := _parse_text
	match _parse_mode:
		0:
			var r := LLMParse.parse_action(raw)
			_parse_out.text = "[color=#7ec8f0]动作解析结果[/color]\nok = %s\naction = %s\nline = %s" % [
				str(r.get("ok", false)), String(r.get("action", "")), String(r.get("line", ""))]
		1:
			var r := LLMParse.parse_event(raw, 3)
			_parse_out.text = "[color=#7ec8f0]事件解析结果（池大小 3）[/color]\nok = %s\npick = %d\nreason = %s" % [
				str(r.get("ok", false)), int(r.get("pick", 0)), String(r.get("reason", ""))]
		_:
			var r := LLMParse.parse_dialogue(raw, 50)
			_parse_out.text = "[color=#7ec8f0]台词清洗结果[/color]\n「%s」" % r


# ══ goat / 配置（真导入）══════════════════════════════

func _build_config() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(8, 8)
	v.size = Vector2(940, 560)
	v.add_theme_constant_override("separation", 10)
	_content.add_child(v)
	v.add_child(UiKit.label("ZCode goat 分组 → 游戏 LLM 配置", 17, Color(0.55, 0.85, 1.0)))
	var imp := UiKit.accent_button("从 ZCode 导入 goat-claude", 15)
	imp.custom_minimum_size = Vector2(300, 42)
	imp.pressed.connect(_import_goat)
	v.add_child(imp)
	var refresh := UiKit.button("重新读取当前配置", 14)
	refresh.custom_minimum_size = Vector2(200, 36)
	refresh.pressed.connect(_refresh_cfg)
	v.add_child(refresh)
	_cfg_out = RichTextLabel.new()
	_cfg_out.bbcode_enabled = true
	_cfg_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cfg_out.custom_minimum_size = Vector2(900, 380)
	_cfg_out.add_theme_font_override("normal_font", PixelTheme.font())
	_cfg_out.add_theme_font_size_override("normal_font_size", 15)
	v.add_child(_cfg_out)
	_refresh_cfg()


func _refresh_cfg() -> void:
	if _cfg_out == null:
		return
	var cfg := LLMConfig.load_from_disk()
	_cfg_out.text = """[color=#7ec8f0]当前游戏 LLM 配置[/color]
总开关：%s
协议：%s
Base URL：%s
模型：%s
Key：%s
温度：observer %.1f ｜ event %.1f ｜ dialog %.1f

[color=#8b9bb4]导入后回主界面打开总开关即可；未导入/未开启时游戏完全按原规则运行。[/color]""" % [
		"开" if cfg.enabled else "关", cfg.protocol, cfg.effective_base(),
		cfg.model if not cfg.model.is_empty() else "（空）",
		("…" + cfg.api_key.substr(maxi(0, cfg.api_key.length() - 4))) if cfg.api_key.length() > 4 else "（空）",
		cfg.temp_for("observer"), cfg.temp_for("event"), cfg.temp_for("dialog")]


func _import_goat() -> void:
	var r := LLMConfig.import_zcode_provider()
	if not bool(r.get("ok", false)):
		_cfg_out.text = "[color=#ff8f8f]导入失败：%s[/color]" % String(r.get("error", "未知"))
		return
	var cfg := LLMConfig.load_from_disk()
	cfg.base_url = String(r.get("base_url", ""))
	cfg.protocol = String(r.get("protocol", "anthropic"))
	cfg.api_key = String(r.get("api_key", ""))
	cfg.model = String(r.get("model", ""))
	cfg.save()
	_refresh_cfg()
	_cfg_out.text += "\n[color=#7ee787]已导入 goat-claude[/color]：%s ｜ %s ｜ key %s（已写入 user://llm_config.cfg）" % [
		String(r.get("model", "")), String(r.get("base_url", "")), String(r.get("key_tail", ""))]


# ══ 平衡（静态报告）══════════════════════════════════

func _build_balance() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(8, 8)
	v.size = Vector2(940, 560)
	v.add_theme_constant_override("separation", 8)
	_content.add_child(v)
	var lines := [
		["[b]AGGRO 1.6 万场（择优 bot）[/b]", "#7ec8f0"],
		["总胜率            61.2%    PASS（40~65）", "#7ee787"],
		["L10 胜率          34.0%    PASS（≥25）", "#7ee787"],
		["带 MARK − 不带    −3.3pp   FAIL（目标 ≥+5pp）", "#ff8f8f"],
		["AGGRO 槽占比      13.5% → 1.2%（−90.8%）  PASS（≥30%）", "#7ee787"],
		["", "#dcebf5"],
		["结论：3/4 PASS。建议 AGGRO 权重 0.5→0.7~0.8；平滑 L7→L8 攻击断崖；MARK 指标符号口径待圆桌定稿。", "#ffd166"],
		["报告全文：docs/balance-aggro.md ｜ 模拟器：tools/sts_sim.gd", "#8b9bb4"],
	]
	for l in lines:
		var lbl := UiKit.label(String(l[0]), 15, Color(0.82, 0.88, 0.98))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(900, 0)
		v.add_child(lbl)
