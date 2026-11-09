class_name PatchDemoScreen
extends Control
## 本次更新交互演示（2026-11-07）：效果程序 / 翻面卡牌 / 算力 / 定价 / 组合审计 / 好感度。
## 全部接真实系统（EffectDSL / EffectRuntime / StsCombat / EffectPricing / EffectCombo /
## Affection），真跑逻辑，不是文字说明。入口：启动界面「更新演示」；返回 back_requested。

signal back_requested

const W := 1600.0
const H := 900.0

var _content: Control
var _tab_btns: Array[Button] = []
var _tab := 0
var _status: Label

# ── Tab0 效果工坊 ──
var _fx_trigger: OptionButton = null
var _fx_op: OptionButton = null
var _fx_amount: HSlider = null
var _fx_amount_lbl: Label = null
var _fx_desc: Label = null
var _fx_ws: Label = null
var _fx_run_out: RichTextLabel = null
var _fx_combat: StsCombat = null

# ── Tab1 翻面 ──
var _flip_view: StsCardView = null
var _flip_view2: StsCardView = null
var _flip_state: Label = null

# ── Tab2 算力 ──
var _en_combat: StsCombat = null
var _en_lbl: Label = null
var _en_log: RichTextLabel = null
var _en_cards := []

# ── Tab3 定价 ──
var _price_pick: OptionButton = null
var _price_samples: HSlider = null
var _price_out: RichTextLabel = null
var _price_cards := []

# ── Tab4 组合 ──
var _combo_checks: Array[Button] = []
var _combo_cards := []
var _combo_out: RichTextLabel = null

# ── Tab5 好感度 ──
var _aff_out: RichTextLabel = null
var _aff_pts: HSlider = null
var _gold_slider: HSlider = null
var _saved_affection := 0.0
## 视觉验收：命令行 --tab=N 直开指定标签页
var initial_tab := 0

# ── Tab6 角色转场（水波试验版）──
var _rp_view: RippleSwapPortrait = null
var _rp_btns: Array[Button] = []
var _rp_state: Label = null
var _rp_cur := 0
var _rp_texs: Array[Texture2D] = []
## 转场风格覆盖：-1=按角色（一人一款），其余 = RippleSwapPortrait.Style.*
var _rp_style_override := -1


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	_build_header()
	_build_left()
	_build_tabs()
	_switch_tab(initial_tab)


func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.016, 0.032)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_header() -> void:
	var title := UiKit.label("更新演示 · 效果程序 / 翻面 / 算力 / 定价 / 组合 / 好感度 / 转场", 30, Color(0.92, 0.95, 1.0))
	title.position = Vector2(60, 42)
	title.size = Vector2(1100, 40)
	add_child(title)
	var sub := UiKit.dim("全部接真实系统：EffectDSL / StsCombat / EffectPricing / EffectCombo / Affection", 15, Color(0.55, 0.72, 0.9))
	sub.position = Vector2(62, 86)
	sub.size = Vector2(1000, 22)
	add_child(sub)
	var back := UiKit.accent_button("← 返回主界面", 16)
	back.position = Vector2(1330, 48)
	back.size = Vector2(210, 44)
	back.pressed.connect(func() -> void: back_requested.emit())
	add_child(back)


func _build_left() -> void:
	var panel := UiKit.panel_box(Color(0.045, 0.06, 0.10, 0.96), Color(0.16, 0.30, 0.48), 16)
	panel.position = Vector2(60, 132)
	panel.size = Vector2(430, 710)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UiKit.label("这次更新了什么", 19, Color(0.55, 0.85, 1.0)))
	var rows := [
		["效果程序", "AI 写程序定效果：8 触发器 × 10 操作，本地校验 + 人话描述"],
		["卡牌翻面", "卡框回归：费用球+名牌（名字+等级）+立绘铺满，右键翻面看描述"],
		["算力", "每回合 3 点，cost≥2 才消耗，cost3 吃掉整回合"],
		["定价", "模拟跑分：p50 定费用、p95 封禁，超模卡当场判禁用"],
		["组合审计", "2–6 张组容斥差分，抓「单卡无害合起来超模」"],
		["好感度", "金币（伤害对数结算）+ 商店礼物 + 喂饭；好感抬许愿卡品质"],
		["角色转场", "一人一款：水波 / 折扇单边展开 / 龙鳞剥落 / 乱斩火烧——第 7 页可玩"],
		["面板伸缩", "两框同时收缩，左框先停，下框上冲顶着左框一起弹出画面——第 8 页可玩"],
	]
	for r in rows:
		var d := UiKit.dim("%s：%s" % [String(r[0]), String(r[1]).replace("\n", " ")], 13, Color(0.55, 0.68, 0.85))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(395, 0)
		v.add_child(d)
	v.add_child(UiKit.rule())
	v.add_child(UiKit.dim("右边每个标签页都能亲手操作，\n背后跑的就是游戏里的真系统。", 13, Color(0.6, 0.85, 0.7)))
	v.add_child(UiKit.spacer(2))


func _build_tabs() -> void:
	var tab_row := HBoxContainer.new()
	tab_row.position = Vector2(520, 138)
	tab_row.size = Vector2(1020, 36)
	tab_row.add_theme_constant_override("separation", 5)
	add_child(tab_row)
	var names := ["效果工坊", "翻面卡牌", "算力", "定价", "组合审计", "好感度", "角色转场", "面板伸缩"]
	for i in names.size():
		var b := UiKit.button(String(names[i]), 15)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(120, 34)
		b.button_pressed = i == 0
		var idx := i
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_switch_tab(idx))
		tab_row.add_child(b)
		_tab_btns.append(b)

	var panel := UiKit.panel_box(Color(0.03, 0.045, 0.08, 0.97), Color(0.16, 0.30, 0.48), 14)
	panel.position = Vector2(520, 182)
	panel.size = Vector2(1020, 660)
	add_child(panel)

	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_content)

	_build_fx_tab()
	_build_flip_tab()
	_build_energy_tab()
	_build_price_tab()
	_build_combo_tab()
	_build_affection_tab()
	_build_ripple_tab()
	_build_morph_tab()


func _switch_tab(idx: int) -> void:
	_tab = idx
	for k in _tab_btns.size():
		_tab_btns[k].button_pressed = k == idx
	for c in _content.get_children():
		c.visible = c.get_index() == idx
	if idx == 3:
		_price_out.text = "选一张样例卡，点「开始定价」——后台真跑 %d 场模拟。" % int(_price_samples.value)


# ═══ Tab0 效果工坊 ═══════════════════════════════════

func _build_fx_tab() -> void:
	var root := Control.new()
	root.name = "TabFX"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(root)

	var v := VBoxContainer.new()
	v.position = Vector2(24, 20)
	v.size = Vector2(960, 600)
	v.add_theme_constant_override("separation", 8)
	root.add_child(v)

	v.add_child(UiKit.label("自己拼一个效果程序（触发器 × 操作 × 数值），实时看编译结果", 17, Color(0.55, 0.85, 1.0)))

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	v.add_child(row1)
	row1.add_child(UiKit.dim("触发器", 15, UiKit.TEXT_DIM))
	_fx_trigger = OptionButton.new()
	for t in EffectSpec.TRIGGERS.keys():
		_fx_trigger.add_item("%s（%s）" % [String(t), String(EffectSpec.TRIGGERS[t])])
	_fx_trigger.custom_minimum_size = Vector2(300, 30)
	_fx_trigger.selected = 0
	_fx_trigger.item_selected.connect(func(_i: int) -> void: _fx_refresh())
	row1.add_child(_fx_trigger)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	v.add_child(row2)
	row2.add_child(UiKit.dim("操作", 15, UiKit.TEXT_DIM))
	_fx_op = OptionButton.new()
	for op_key in EffectSpec.OPS.keys():
		_fx_op.add_item("%s（%s）" % [String(op_key), String(EffectSpec.OPS[op_key]["label"])])
	_fx_op.custom_minimum_size = Vector2(300, 30)
	_fx_op.selected = 0
	_fx_op.item_selected.connect(func(_i: int) -> void: _fx_refresh())
	row2.add_child(_fx_op)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 10)
	v.add_child(row3)
	row3.add_child(UiKit.dim("数值", 15, UiKit.TEXT_DIM))
	_fx_amount = HSlider.new()
	_fx_amount.min_value = 1
	_fx_amount.max_value = 20
	_fx_amount.value = 8
	_fx_amount.custom_minimum_size = Vector2(260, 20)
	_fx_amount.value_changed.connect(func(_v: float) -> void: _fx_refresh())
	row3.add_child(_fx_amount)
	_fx_amount_lbl = UiKit.label("8", 15, UiKit.TEXT)
	row3.add_child(_fx_amount_lbl)

	_fx_desc = UiKit.label("", 16, Color(0.85, 0.95, 1.0))
	_fx_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fx_desc.custom_minimum_size = Vector2(920, 30)
	v.add_child(_fx_desc)
	_fx_ws = UiKit.dim("", 13, Color(0.5, 0.65, 0.8))
	v.add_child(_fx_ws)

	var run_btn := UiKit.accent_button("▶ 上机试打（真 StsCombat + 真 EffectRuntime）", 17)
	run_btn.custom_minimum_size = Vector2(0, 46)
	run_btn.pressed.connect(_fx_run)
	v.add_child(run_btn)

	_fx_run_out = RichTextLabel.new()
	_fx_run_out.custom_minimum_size = Vector2(0, 300)
	_fx_run_out.add_theme_font_size_override("normal_font_size", 15)
	_fx_run_out.text = "拼好之后点上面，真打一次给你看。"
	v.add_child(_fx_run_out)
	_fx_refresh()


func _fx_program() -> Array:
	var trg := String(EffectSpec.TRIGGERS.keys()[_fx_trigger.selected])
	var op_key := String(EffectSpec.OPS.keys()[_fx_op.selected])
	var amt := int(_fx_amount.value)
	var op := {"do": op_key}
	for arg_name in EffectSpec.OPS[op_key]["args"].keys():
		var aspec: Dictionary = EffectSpec.OPS[op_key]["args"][arg_name]
		if String(aspec.get("type", "")) == "enum":
			op[arg_name] = String(aspec["values"][0])
			if op_key == "apply_status" and arg_name == "target":
				op["target"] = "enemy"
		elif arg_name == "amount":
			op[arg_name] = amt
	return [{"when": trg, "then": [op]}]


func _fx_refresh() -> void:
	if _fx_amount_lbl != null:
		_fx_amount_lbl.text = "%d" % int(_fx_amount.value)
	var c := EffectDSL.compile(_fx_program())
	if bool(c["ok"]):
		_fx_desc.text = "编译通过：%s" % EffectDSL.describe(c["clauses"])
		var ws := EffectDSL.writeset(c["clauses"]).keys()
		_fx_ws.text = "写集：%s ｜ op 数：%d（本作上限 1：一卡一个新特色）" % [
				", ".join(ws), int(c["ops"])]
	else:
		_fx_desc.text = "编译失败（不该发生）"
		_fx_ws.text = ""


func _fx_run() -> void:
	var c := EffectDSL.compile(_fx_program())
	if not bool(c["ok"]):
		return
	if _fx_combat == null:
		_fx_combat = StsCombat.new()
		var deck: Array[StsCard] = StsCardPool.starter_deck()
		_fx_combat.setup(deck, "演示幽灵", 200,
				[{"kind": "attack", "value": 8}, {"kind": "defend", "value": 5}], 80, 42, 4, 1)
	var cb := _fx_combat
	var before := "敌 HP %d ｜ 敌格挡 %d ｜ 我方格挡 %d ｜ 我方 HP %d ｜ 状态 %d 项" % [
		cb.enemy_hp, cb.enemy_block, cb.block, cb.hp, cb.e_status.size() + cb.p_status.size()]
	var trg := String(EffectSpec.TRIGGERS.keys()[_fx_trigger.selected])
	var outs := EffectRuntime.eval(c["clauses"], trg, cb._effect_ctx())
	var ev := {}
	cb._apply_effects(outs, ev)
	var after := "敌 HP %d ｜ 敌格挡 %d ｜ 我方格挡 %d ｜ 我方 HP %d ｜ 状态 %d 项" % [
		cb.enemy_hp, cb.enemy_block, cb.block, cb.hp, cb.e_status.size() + cb.p_status.size()]
	var lines := "[触发 %s] ｜ 前：%s\n" % [trg, before]
	if ev.has("fx"):
		for fx in ev["fx"]:
			lines += "  · %s %+d\n" % [String((fx as Dictionary)["kind"]).replace("effect_", ""),
					int((fx as Dictionary).get("value", 0))]
	else:
		lines += "  · （这个触发器下没有可结算的效果）\n"
	lines += "后：%s" % after
	_fx_run_out.text = lines
	SfxNode.play("ui_click")


# ═══ Tab1 翻面卡牌 ═══════════════════════════════════

func _build_flip_tab() -> void:
	var root := Control.new()
	root.name = "TabFlip"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(root)

	var flip_title := UiKit.label("右键点卡牌翻面（正面：费用球+名牌+立绘；背面：描述）", 17, Color(0.55, 0.85, 1.0))
	flip_title.position = Vector2(24, 20)
	root.add_child(flip_title)

	# 攻击框（红）+ 技能框（蓝）各来一张，两种卡框都能看
	_flip_view = StsCardView.new()
	_flip_view.position = Vector2(120, 80)
	_flip_view.scale = Vector2(1.3, 1.3)
	_flip_view.pivot_offset = Vector2(75, 113)
	root.add_child(_flip_view)
	_flip_view.flipped.connect(func(_v: StsCardView, _b: bool) -> void: _poll_flip())
	var c := StsCardPool.card("fish_ram")
	if c != null:
		_flip_view.setup(c)

	_flip_view2 = StsCardView.new()
	_flip_view2.position = Vector2(340, 80)
	_flip_view2.scale = Vector2(1.3, 1.3)
	_flip_view2.pivot_offset = Vector2(75, 113)
	root.add_child(_flip_view2)
	_flip_view2.flipped.connect(func(_v: StsCardView, _b: bool) -> void: _poll_flip())
	var c2 := StsCardPool.card("rice")
	if c2 == null:
		c2 = StsCardPool.card("taunt")
	if c2 != null:
		_flip_view2.setup(c2)

	_flip_state = UiKit.label("当前：正面", 16, Color(0.85, 0.95, 1.0))
	_flip_state.position = Vector2(600, 120)
	_flip_state.size = Vector2(320, 26)
	root.add_child(_flip_state)

	var flip_btn := UiKit.button("翻转左卡（等效右键）", 16)
	flip_btn.position = Vector2(600, 160)
	flip_btn.custom_minimum_size = Vector2(230, 40)
	flip_btn.pressed.connect(func() -> void:
		if _flip_view != null:
			_flip_view.flip())
	root.add_child(flip_btn)

	var flip_btn2 := UiKit.button("翻转右卡（等效右键）", 16)
	flip_btn2.position = Vector2(600, 210)
	flip_btn2.custom_minimum_size = Vector2(230, 40)
	flip_btn2.pressed.connect(func() -> void:
		if _flip_view2 != null:
			_flip_view2.flip())
	root.add_child(flip_btn2)

	var info := UiKit.dim("正面 = 卡框贴图：左上角小圈圈是费用，顶部名牌是「名字 + 等级」（等级=定价档位 1–3），立绘从画窗一直铺到底——原底部描述面板废弃。\n背面 = 名字 + 描述（序列预览数值也写在背面，翻过来就能看到「这一格会打多少」）。\n翻面动画：横向压扁 → 换面 → 回弹（过冲）+ 中途提亮。", 14, Color(0.55, 0.68, 0.85))
	info.position = Vector2(600, 270)
	info.size = Vector2(560, 200)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info)


func _poll_flip() -> void:
	if _flip_state == null:
		return
	var st := func(v: StsCardView) -> String:
		if v == null:
			return "无"
		return "背面（描述）" if v.is_flipped() else "正面（卡框+立绘）"
	_flip_state.text = "左卡：%s ｜ 右卡：%s" % [st.call(_flip_view), st.call(_flip_view2)]


# ═══ Tab2 算力 ═══════════════════════════════════════

func _build_energy_tab() -> void:
	var root := Control.new()
	root.name = "TabEnergy"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(root)

	var v := VBoxContainer.new()
	v.position = Vector2(24, 20)
	v.size = Vector2(960, 600)
	v.add_theme_constant_override("separation", 10)
	root.add_child(v)

	v.add_child(UiKit.label("每回合 3 点算力：cost 1 的基础指令免费，cost ≥2 的复杂指令要花算力", 17, Color(0.55, 0.85, 1.0)))
	_en_lbl = UiKit.label("", 20, Color(1.0, 0.82, 0.4))
	v.add_child(_en_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var specs := [
		["免费平A ×2", 1, 5, false],
		["cost2 重击", 2, 9, false],
		["cost3 大招", 3, 14, false],
	]
	for sp in specs:
		var cost := int(sp[1])
		var b := UiKit.button("%s\n（cost %d ｜ %d 伤）" % [String(sp[0]), cost, int(sp[2])], 14)
		b.custom_minimum_size = Vector2(170, 64)
		b.disabled = true
		b.pressed.connect(_en_play.bind(cost, int(sp[2])))
		row.add_child(b)
		_en_cards.append({"btn": b, "cost": cost, "dmg": int(sp[2])})

	var reset := UiKit.button("↺ 新回合（算力回满）", 15)
	reset.custom_minimum_size = Vector2(200, 36)
	reset.pressed.connect(func() -> void:
		if _en_combat != null:
			_en_combat.start_turn()
			_en_refresh())
	v.add_child(reset)

	_en_log = RichTextLabel.new()
	_en_log.custom_minimum_size = Vector2(0, 280)
	_en_log.add_theme_font_size_override("normal_font_size", 15)
	_en_log.text = "点上面的卡牌出招——cost 3 的大招会吃掉整回合算力。"
	v.add_child(_en_log)

	_en_combat = StsCombat.new()
	var deck: Array[StsCard] = StsCardPool.starter_deck()
	_en_combat.setup(deck, "演示靶子", 300,
			[{"kind": "attack", "value": 0}], 80, 77, 4, 1)
	_en_combat.intent = {"kind": "defend", "value": 0}
	_en_refresh()


func _en_refresh() -> void:
	if _en_combat == null or _en_lbl == null:
		return
	_en_lbl.text = "⚡ 算力 %d / %d ｜ 敌 HP %d" % [
		_en_combat.energy, StsCombat.ENERGY_PER_TURN, _en_combat.enemy_hp]
	for i in _en_cards.size():
		var e: Dictionary = _en_cards[i]
		var b: Button = e["btn"]
		b.disabled = _en_combat.energy < int(e["cost"]) or _en_combat.over != StsCombat.Result.RUNNING


func _en_play(cost: int, dmg: int) -> void:
	if _en_combat == null:
		return
	var c := StsCard.make("demo_c%d" % cost, StsCard.Kind.ATTACK, cost, dmg, 0, "")
	_en_combat.hand.clear()
	_en_combat.hand.append(c)
	if not _en_combat.can_play(c):
		return
	var ev := _en_combat.play_card(c, false)
	if bool(ev.get("ok", false)):
		_en_log.text += "▸ 打出 cost%d（%d 伤）→ 剩余算力 %d\n" % [cost, dmg, _en_combat.energy]
	_en_refresh()
	SfxNode.play("card_select")


# ═══ Tab3 定价 ═══════════════════════════════════════

const PRICE_PRESETS := [
	{"name": "平A卡（对照）", "def": {"name": "平A", "kind": "attack", "damage": 6, "block": 0}},
	{"name": "连击成长", "def": {"name": "连击", "kind": "attack", "damage": 5,
		"program": [{"when": "on_play", "then": [
			{"do": "damage_scaled", "per": "same_kind_streak", "step": 2}]}]}},
	{"name": "首杀成长", "def": {"name": "连击", "kind": "attack", "damage": 5,
		"program": [{"when": "on_play", "then": [
			{"do": "damage", "amount": 5},
			{"do": "damage_scaled", "per": "same_kind_streak", "step": 2}]}]}},
	{"name": "超模直伤50", "def": {"name": "超模", "kind": "attack", "damage": 0,
		"program": [{"when": "on_play", "then": [
			{"do": "damage", "amount": 50}]}]}},
]


func _build_price_tab() -> void:
	var root := Control.new()
	root.name = "TabPrice"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(root)

	var v := VBoxContainer.new()
	v.position = Vector2(24, 20)
	v.size = Vector2(960, 600)
	v.add_theme_constant_override("separation", 10)
	root.add_child(v)

	v.add_child(UiKit.label("定价器：把效果程序丢进模拟器跑分——p50 定费用、p95 封禁（竞技禁用）", 17, Color(0.55, 0.85, 1.0)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(UiKit.dim("样例卡", 15, UiKit.TEXT_DIM))
	_price_pick = OptionButton.new()
	for p in PRICE_PRESETS:
		_price_pick.add_item(String(p["name"]))
	_price_pick.custom_minimum_size = Vector2(240, 30)
	row.add_child(_price_pick)
	row.add_child(UiKit.dim("样本", 15, UiKit.TEXT_DIM))
	_price_samples = HSlider.new()
	_price_samples.min_value = 20
	_price_samples.max_value = 200
	_price_samples.step = 20
	_price_samples.value = 60
	_price_samples.custom_minimum_size = Vector2(220, 20)
	row.add_child(_price_samples)

	var btn := UiKit.accent_button("开始定价（真模拟）", 16)
	btn.custom_minimum_size = Vector2(220, 40)
	btn.pressed.connect(_price_run)
	v.add_child(btn)

	_price_out = RichTextLabel.new()
	_price_out.custom_minimum_size = Vector2(0, 380)
	_price_out.add_theme_font_size_override("normal_font_size", 15)
	v.add_child(_price_out)

	for p in PRICE_PRESETS:
		var d: Dictionary = p["def"]
		var card_id := "price_demo_%d" % int(String(p["name"]).hash())
		var card := StsCard.make(card_id, StsCard.Kind.ATTACK, 1,
				int(d.get("damage", 6)), 0, "")
		var prog = d.get("program", [])
		if prog is Array and not (prog as Array).is_empty():
			card.effects = EffectDSL.compile(prog)["clauses"]
			card.dsl_version = EffectSpec.VERSION
		_price_cards.append(card)


func _price_run() -> void:
	var idx := _price_pick.selected
	if idx < 0 or idx >= _price_cards.size():
		return
	var card: StsCard = _price_cards[idx]
	var n := int(_price_samples.value)
	_price_out.text = "模拟中…（%d 场 × 2 组对照）" % n
	await get_tree().create_timer(0.05).timeout
	var r := EffectPricing.price(card, 1, n)
	var verdict := "✔ 正常" if not bool(r["banned"]) else "✖ 竞技禁用"
	_price_out.text = ("【%s】\n费用档 = %d（p50 = %+.1f）\np95 = %+.1f ｜ %s\n决策增量 = %+.0f 次\n"
			+ "基线胜率 %.0f%% → 加卡 %.0f%%\n（%d 场真模拟，约 %.1f 秒）") % [
			String(PRICE_PRESETS[idx]["name"]), int(r["cost"]), float(r["ev"]), float(r["p95"]),
			verdict, float(r.get("decision_extra", 0.0)),
			float((r["base"] as Dictionary)["win_rate"]) * 100.0,
			float((r["with_card"] as Dictionary)["win_rate"]) * 100.0, n, float(n) * 0.004]
	SfxNode.play("ui_click")


# ═══ Tab4 组合审计 ═══════════════════════════════════

func _build_combo_tab() -> void:
	var root := Control.new()
	root.name = "TabCombo"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(root)

	var v := VBoxContainer.new()
	v.position = Vector2(24, 20)
	v.size = Vector2(960, 600)
	v.add_theme_constant_override("separation", 10)
	root.add_child(v)

	v.add_child(UiKit.label("组合审计：勾选卡牌组成牌组，容斥差分找「单卡无害、合起来超模」", 17, Color(0.55, 0.85, 1.0)))

	_combo_cards = [
		{"name": "持续中毒", "card": _fx_card_of([{"when": "on_turn_end", "then": [
			{"do": "apply_status", "status": "poison", "tier": 2, "target": "enemy"}]}])},
		{"name": "持续易伤", "card": _fx_card_of([{"when": "on_turn_end", "then": [
			{"do": "apply_status", "status": "vulnerable", "tier": 2, "target": "enemy"}]}])},
		{"name": "连击成长", "card": _fx_card_of([{"when": "on_play", "then": [
			{"do": "damage", "amount": 6},
			{"do": "damage_scaled", "per": "same_kind_streak", "step": 2}]}])},
		{"name": "大额直伤", "card": _fx_card_of([{"when": "on_play", "then": [
			{"do": "damage", "amount": 20}]}])},
	]
	for cc in _combo_cards:
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = true
		b.text = "☑ " + String(cc["name"])
		b.custom_minimum_size = Vector2(200, 34)
		var cc_ref: Dictionary = cc
		b.toggled.connect(func(on: bool) -> void:
			b.text = ("☑ " if on else "☐ ") + String(cc_ref["name"]))
		v.add_child(b)
		_combo_checks.append(b)

	var btn := UiKit.accent_button("审计牌组（真容斥差分）", 16)
	btn.custom_minimum_size = Vector2(240, 40)
	btn.pressed.connect(_combo_run)
	v.add_child(btn)

	_combo_out = RichTextLabel.new()
	_combo_out.custom_minimum_size = Vector2(0, 320)
	_combo_out.add_theme_font_size_override("normal_font_size", 15)
	_combo_out.text = "勾好后点上面。"
	v.add_child(_combo_out)


func _fx_card_of(program: Array) -> StsCard:
	var c := StsCard.make("combo_demo", StsCard.Kind.ATTACK, 1, 5, 0, "")
	c.effects = EffectDSL.compile(program)["clauses"]
	c.dsl_version = EffectSpec.VERSION
	return c


func _combo_run() -> void:
	var deck: Array[StsCard] = []
	for i in _combo_cards.size():
		if _combo_checks[i].button_pressed:
			deck.append(_combo_cards[i]["card"])
	if deck.size() < 2:
		_combo_out.text = "至少勾 2 张（组合是 ≥2 张卡之间的事）。"
		return
	var r := EffectCombo.audit(deck, 1, 20)
	var lines := "总判：%s ｜ 候选对 %d ｜ 三元组 %d\n" % [
		String(r["tag"]), (r["pairs"] as Array).size(), (r["triples"] as Array).size()]
	for row in r["pairs"]:
		lines += "  对：%s × %s → 交互 %+.1f → %s\n" % [
			String(row["a"]).substr(0, 6), String(row["b"]).substr(0, 6),
			float(row["excess"]), String(row["tag"])]
	for row in r["triples"]:
		lines += "  三：%s… → 交互 %+.1f → %s\n" % [
			",".join(row["cards"]).substr(0, 20), float(row["excess"]), String(row["tag"])]
	_combo_out.text = lines
	SfxNode.play("ui_click")


# ═══ Tab5 好感度 ═════════════════════════════════════

func _build_affection_tab() -> void:
	var root := Control.new()
	root.name = "TabAff"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(root)

	var v := VBoxContainer.new()
	v.position = Vector2(24, 20)
	v.size = Vector2(960, 600)
	v.add_theme_constant_override("separation", 10)
	root.add_child(v)

	_saved_affection = Affection.points

	v.add_child(UiKit.label("好感度：无上限，等级按对数涨；喂饭和商店礼物都加好感，好感抬许愿卡品质", 17, Color(0.55, 0.85, 1.0)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(UiKit.dim("好感点", 15, UiKit.TEXT_DIM))
	_aff_pts = HSlider.new()
	_aff_pts.min_value = 0
	_aff_pts.max_value = 2000
	_aff_pts.step = 10
	_aff_pts.value = clampf(Affection.points, 0, 2000)
	_aff_pts.custom_minimum_size = Vector2(320, 20)
	_aff_pts.value_changed.connect(func(v: float) -> void:
		Affection.points = v
		_aff_refresh())
	row.add_child(_aff_pts)

	var gift_row := HBoxContainer.new()
	gift_row.add_theme_constant_override("separation", 8)
	v.add_child(gift_row)
	for g in [["小蛋糕 +6", 6.0], ["蝴蝶结 +15", 15.0], ["约会券 +40", 40.0]]:
		var pts: float = g[1]
		var b := UiKit.button(String(g[0]), 14)
		b.custom_minimum_size = Vector2(150, 34)
		b.pressed.connect(func() -> void:
			Affection.add(pts)
			_aff_pts.value = Affection.points
			_aff_refresh()
			SfxNode.play("ui_click"))
		gift_row.add_child(b)

	var reset := UiKit.button("↺ 还原本机真实好感", 14)
	reset.custom_minimum_size = Vector2(220, 34)
	reset.pressed.connect(func() -> void:
		Affection.points = _saved_affection
		Affection.save()
		_aff_pts.set_value_no_signal(clampf(Affection.points, 0, 2000))
		_aff_refresh())
	v.add_child(reset)

	_aff_out = RichTextLabel.new()
	_aff_out.custom_minimum_size = Vector2(0, 260)
	_aff_out.add_theme_font_size_override("normal_font_size", 15)
	v.add_child(_aff_out)

	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 10)
	v.add_child(gold_row)
	gold_row.add_child(UiKit.dim("战斗伤害", 15, UiKit.TEXT_DIM))
	_gold_slider = HSlider.new()
	_gold_slider.min_value = 0
	_gold_slider.max_value = 5000
	_gold_slider.step = 50
	_gold_slider.value = 500
	_gold_slider.custom_minimum_size = Vector2(320, 20)
	_gold_slider.value_changed.connect(func(_v: float) -> void: _aff_refresh())
	gold_row.add_child(_gold_slider)

	_aff_refresh()


func _aff_refresh() -> void:
	if _aff_out == null:
		return
	var lv := Affection.level()
	var dmg := int(_gold_slider.value)
	var gold := RunState.gold_for_damage(dmg)
	var caps := "伤害预算 +%d ｜ 状态档 +%d ｜ 机制 op %d 个 ｜ 画质 T%d ｜ 输出 %d token" % [
		Affection.damage_bonus(), Affection.tier_boost(), Affection.feature_ops(),
		Affection.quality_tier(), WishCardFactory.max_tokens_for(lv)]
	_aff_out.text = ("好感点 %.0f ｜ 等级 Lv.%d（进度 %.0f%%）\n%s\n\n许愿卡连动：画出来的卡 [伤害上限][状态档位][机制数量] 全部抬升。\n商店礼物：小蛋糕 20 金 / 蝴蝶结 45 金 / 约会券 110 金。\n\n金币预览：本战伤害 %d → 金币 +%d（对数：100 伤≈18 金，4000 伤≈65 金）" % [
		Affection.points, lv, Affection.level_progress() * 100.0, caps, dmg, gold])


# ═══ Tab6 角色转场（水波试验版）══════════════════════════════════════════════

const RIPPLE_IDS := ["deepdeek", "kweno", "chatppt", "grock"]
const RIPPLE_NAMES := ["DeepDeek｜水波", "Kweno｜折扇", "ChatPPT｜龙鳞", "Grock｜X斩"]
## 每人一款：女仆=水波（柔和）、青花千金=折扇、白龙千金=龙鳞、X斧小恶魔=X斩
const RIPPLE_STYLES := [RippleSwapPortrait.Style.RIPPLE, RippleSwapPortrait.Style.FAN,
		RippleSwapPortrait.Style.HEX, RippleSwapPortrait.Style.SLASH]
const RIPPLE_TINTS := [Color(0.310, 0.757, 0.965), Color(1.000, 0.820, 0.400),
		Color(0.937, 0.545, 0.706), Color(0.478, 0.792, 0.443)]


func _build_ripple_tab() -> void:
	var root := Control.new()
	root.name = "TabRipple"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(root)

	var title := UiKit.label("一人一款转场：水波（女仆）/ 折扇（青花千金）/ 龙鳞（白龙）/ X斩（小恶魔）——点角色试试", 17, Color(0.55, 0.85, 1.0))
	title.position = Vector2(24, 16)
	root.add_child(title)

	for id in RIPPLE_IDS:
		var t: Texture2D = load("res://assets/art/ai-%s.png" % id)
		_rp_texs.append(t)

	# 大立绘（192×256 立绘整数 ×2 = 384×512，像素画 crisp）
	var frame := UiKit.panel_box(Color(0.03, 0.045, 0.08, 0.97), Color(0.16, 0.30, 0.48), 10)
	frame.position = Vector2(80, 58)
	frame.size = Vector2(408, 560)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)

	_rp_view = RippleSwapPortrait.new()
	_rp_view.name = "RipplePortrait"
	_rp_view.position = Vector2(100, 82)
	_rp_view.size = Vector2(384, 512)
	root.add_child(_rp_view)
	_rp_view.set_portrait(_rp_texs[0])
	_rp_view.swap_finished.connect(func() -> void:
		if _rp_state != null:
			_rp_state.text = "转场完成 ✓ 当前：%s" % RIPPLE_NAMES[_rp_cur])

	# 右侧：4 个角色切换按钮（竖排）
	for i in RIPPLE_NAMES.size():
		var b := UiKit.button(RIPPLE_NAMES[i], 18)
		b.toggle_mode = true
		b.button_pressed = i == 0
		b.custom_minimum_size = Vector2(280, 52)
		b.position = Vector2(560, 82 + i * 66)
		var idx := i
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_rp_swap(idx))
		root.add_child(b)
		_rp_btns.append(b)

	var replay := UiKit.button("↻ 重播上一转（A/B 交替）", 15)
	replay.custom_minimum_size = Vector2(280, 40)
	replay.position = Vector2(560, 82 + RIPPLE_NAMES.size() * 66 + 6)
	replay.pressed.connect(func() -> void:
		var other := (_rp_cur + 1) % _rp_texs.size()
		_rp_swap(other))
	root.add_child(replay)

	# 调速器（2026-11-08 主人要求）：水波扩散速度，拖完即存盘——主人的数值跨启动记住
	_rp_view.swap_time = GameSettings.ripple_swap_time
	var speed_lbl := UiKit.label("速度", 15, Color(0.85, 0.95, 1.0))
	speed_lbl.position = Vector2(560, 82 + RIPPLE_NAMES.size() * 66 + 58)
	speed_lbl.size = Vector2(48, 24)
	root.add_child(speed_lbl)
	var speed_val := UiKit.label("%.2fs" % GameSettings.ripple_swap_time, 15, Color(0.6, 0.85, 1.0))
	speed_val.position = Vector2(770, 82 + RIPPLE_NAMES.size() * 66 + 58)
	speed_val.size = Vector2(80, 24)
	root.add_child(speed_val)
	var speed_slider := HSlider.new()
	speed_slider.min_value = 0.15
	speed_slider.max_value = 10.0
	speed_slider.step = 0.05
	speed_slider.value = GameSettings.ripple_swap_time
	speed_slider.position = Vector2(612, 82 + RIPPLE_NAMES.size() * 66 + 62)
	speed_slider.size = Vector2(150, 18)
	speed_slider.value_changed.connect(func(v: float) -> void:
		if _rp_view != null:
			_rp_view.swap_time = v
		GameSettings.ripple_swap_time = v
		GameSettings.save_to_disk()
		speed_val.text = "%.2fs" % v)
	root.add_child(speed_slider)

	_rp_state = UiKit.label("当前：DeepDeek", 16, Color(0.85, 0.95, 1.0))
	_rp_state.position = Vector2(560, 82 + RIPPLE_NAMES.size() * 66 + 92)
	_rp_state.size = Vector2(360, 26)
	root.add_child(_rp_state)

	# 风格覆盖：默认一人一款，也可以强行指定某款来看对比
	var style_lbl := UiKit.label("风格", 15, Color(0.85, 0.95, 1.0))
	style_lbl.position = Vector2(560, 82 + RIPPLE_NAMES.size() * 66 + 124)
	style_lbl.size = Vector2(48, 24)
	root.add_child(style_lbl)
	var style_pick := OptionButton.new()
	for s in ["按角色（一人一款）", "水波（柔和）", "折扇（千金）", "X斩（小恶魔）", "龙鳞（白龙）"]:
		style_pick.add_item(s)
	style_pick.position = Vector2(612, 82 + RIPPLE_NAMES.size() * 66 + 120)
	style_pick.size = Vector2(230, 30)
	style_pick.item_selected.connect(func(idx: int) -> void:
		_rp_style_override = -1 if idx == 0 else idx - 1)
	root.add_child(style_pick)

	var info := UiKit.dim("水波=柔和漫开（女仆）；折扇=先勾金色扇沿再铺像素布、逆向收回（千金）；\nX斩=剑光交叉劈开、四片火烧留黑痕渐消（小恶魔）；龙鳞=鳞片底部先剥翘金边（白龙）。\n速度滑杆拖完自动存档（0.15s ~ 2.5s），下次启动还是主人调的值。", 13, Color(0.55, 0.68, 0.85))
	info.position = Vector2(560, 82 + RIPPLE_NAMES.size() * 66 + 158)
	info.size = Vector2(430, 120)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info)


func _rp_swap(i: int) -> void:
	if i == _rp_cur or _rp_view == null:
		return
	_rp_cur = i
	_rp_view.style = _rp_style_override if _rp_style_override >= 0 \
			else int(RIPPLE_STYLES[i])
	_rp_view.swap_to(_rp_texs[i])
	if _rp_state != null:
		_rp_state.text = "转场中… → %s" % RIPPLE_NAMES[i]
	for k in _rp_btns.size():
		_rp_btns[k].button_pressed = k == i


# ═══ Tab7 面板伸缩 ═══════════════════════════════════

var _morph_view: PanelMorphDemo = null


func _build_morph_tab() -> void:
	var root := Control.new()
	root.name = "TabMorph"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(root)

	var title := UiKit.label("面板动态伸缩：两框同时收缩（左框上边不动）｜左框先停｜下框上冲顶左框一起弹出画面", 17,
			Color(0.55, 0.85, 1.0))
	title.position = Vector2(24, 16)
	root.add_child(title)

	var info := UiKit.dim("三段：① 两框同时收缩（左框上边固定 900→300、下框收到左下角右边线对齐 x=256）；② 左框先收完停住；③ 下框上冲顶着左框一起弹出画面。全部 Tween 驱动，可重复播放。", 13,
			Color(0.55, 0.68, 0.85))
	info.position = Vector2(24, 42)
	info.size = Vector2(966, 40)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info)

	var holder := Control.new()
	holder.position = Vector2(24, 92)
	holder.size = Vector2(960, 540)
	holder.clip_contents = true
	root.add_child(holder)

	_morph_view = PanelMorphDemo.new()
	_morph_view.position = Vector2.ZERO
	_morph_view.size = Vector2(1600, 900)
	_morph_view.scale = Vector2(0.6, 0.6)   ## 1600×900 缩到 960×540 内
	_morph_view.back_requested.connect(func() -> void: pass)
	holder.add_child(_morph_view)

