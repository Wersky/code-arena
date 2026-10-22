extends SceneTree
## 冒烟测试：数据完整性 + 计分引擎数值 + UI 构建。
##
## 运行：godot --headless --path <项目> --import
##       godot --headless --path <项目> --script res://tests/smoke_test.gd

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_test_card_pool()
	_test_level_pool()
	_test_item_pool()
	_test_scoring_basics()
	_test_scoring_combos()
	_test_scoring_penalties()
	_test_scoring_items()
	_test_run_state()
	_test_poker_cards()
	_test_poker_hands()
	_test_poker_scoring()
	_test_poker_deck()
	await _test_ui()
	await _test_arena_flow()
	await _test_level_seeds_and_flip()
	await _test_screen_router()
	print("\n==== %d 项检查，%d 项失败 ====" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


## 递归按名字找节点（界面全是代码构建，节点名不保证是固定路径）
func _find_named(n: Node, name: String) -> Node:
	if n == null:
		return null
	if n.name == name:
		return n
	for c in n.get_children():
		var hit := _find_named(c, name)
		if hit != null:
			return hit
	return null


# ── 断言工具 ───────────────────────────────────────────
func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok  : " + msg)
	else:
		_fails += 1
		printerr("FAIL  : " + msg)


func _eq(actual, expected, msg: String) -> void:
	_check(actual == expected, "%s  期望=%s 实得=%s" % [msg, str(expected), str(actual)])


func _card(title: String) -> CardData:
	for c in CardPool.all_cards():
		if c.title == title:
			return c
	return null


func _item(effect_id: String) -> AiItemData:
	for it in AiItemPool.all_items():
		if it.effect_id == effect_id:
			return it
	return null


func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"token_budget": 9, "items": [] as Array[AiItemData], "turn_index": 0,
		"rule": LevelData.Rule.NONE, "shield": false, "preview": true,
	}
	for k in overrides:
		base[k] = overrides[k]
	return base


# ── 数据完整性 ─────────────────────────────────────────
func _test_card_pool() -> void:
	print("[卡池]")
	var all := CardPool.all_cards()
	_check(all.size() >= 40, "卡池总数 ≥ 40（实得 %d）" % all.size())

	var titles := {}
	var dup := ""
	for c in all:
		if titles.has(c.title):
			dup = c.title
		titles[c.title] = true
	_check(dup == "", "卡牌标题无重复" + ("" if dup == "" else "（重复：%s）" % dup))

	var risky := 0
	for c in all:
		if c.risky:
			risky += 1
	_check(risky >= 3, "风险卡 ≥ 3 张（实得 %d）" % risky)

	var kinds := {}
	for c in all:
		kinds[c.kind] = true
	_check(kinds.size() == 6, "6 种组件类型齐全（实得 %d）" % kinds.size())

	var deck := CardPool.starting_deck()
	_eq(deck.size(), 20, "起始牌组 20 张")


func _test_level_pool() -> void:
	print("[关卡表]")
	var levels := LevelPool.all_levels()
	_eq(levels.size(), 10, "共 10 关")
	var prev := 0
	var monotonic := true
	for l in levels:
		if l.target_score <= prev:
			monotonic = false
		prev = l.target_score
	_check(monotonic, "目标分逐关递增")
	_check(levels[9].is_boss, "最后一关是 BOSS")
	var prev_turns := 0
	var turns_monotonic := true
	for l in levels:
		_check(l.turns >= 3, "%s 回合数 ≥ 3" % l.id)
		if l.turns < prev_turns:
			turns_monotonic = false
		prev_turns = l.turns
		# 基础玩法没有关卡特殊规则与 Token 预算
		_eq(l.rule, LevelData.Rule.NONE, "%s 没有特殊规则" % l.id)
		_eq(l.token_budget, 0, "%s 没有 Token 预算" % l.id)
	_check(turns_monotonic, "回合数逐关不降（目标分才能单调递增）")
	for l in levels:
		# 扑克玩法单手 40~1000 分，整关目标分必须落在这个尺度里
		# 刻度随计分口径变（散牌不计分后整缩小约 6 倍），区间跟着换，防的是"手写大数字塞回来"
		_check(l.target_score >= 100 and l.target_score <= 1200,
			"%s 目标分落在扑克尺度区间 100~1200（实得 %d）" % [l.id, l.target_score])
		# 目标分 / 出牌次数 = 每手要求的分数，必须低于单手上限（约 1200）
		var per_hand := float(l.target_score) / float(l.turns)
		_check(per_hand <= 1200.0, "%s 每手要求 %.1f 分 ≤ 单手上限 1200" % [l.id, per_hand])


func _test_item_pool() -> void:
	print("[道具池]")
	var items := AiItemPool.all_items()
	_check(items.size() >= 12, "道具 ≥ 12 件（实得 %d）" % items.size())
	var ids := {}
	var dup := ""
	for it in items:
		if ids.has(it.id):
			dup = it.id
		ids[it.id] = true
	_check(dup == "", "道具 id 无重复")
	# 虚构命名检查：不得出现真实品牌名
	var forbidden := ["deepseek", "chatgpt", "gemini", "llama", "grok", "ollama", "qwen", "mistral", "claude"]
	var leaked := ""
	for it in items:
		var low := it.display_name.to_lower()
		for f in forbidden:
			if low.contains(f):
				leaked = it.display_name
	_check(leaked == "", "道具名均为虚构名" + ("" if leaked == "" else "（泄漏：%s）" % leaked))


# ── 计分引擎 ───────────────────────────────────────────
func _test_scoring_basics() -> void:
	print("[计分 · 基础]")
	var empty := Scoring.evaluate([], _ctx())
	_eq(int(empty["score"]), 0, "空牌得分 0")

	var c3: Array[CardData] = [_card("写个函数"), _card("资深工程师"), _card("输出一段 JSON")]
	var r3 := Scoring.evaluate(c3, _ctx())
	_eq(int(r3["base"]), 40, "3 张基础分 40")
	_eq(int(r3["flat"]), 50, "3 张加分 50（委托明确30 + 结构化20）")
	_eq(int(r3["score"]), 109, "3 张得分 109")
	_eq(int(r3["token_cost"]), 4, "3 张 Token 花费 4")


func _test_scoring_combos() -> void:
	print("[计分 · 牌型]")
	var perfect: Array[CardData] = [
		_card("资深工程师"), _card("写个函数"), _card("贴上代码仓库"),
		_card("输出一段 JSON"), _card("给一个正例"),
	]
	var rp := Scoring.evaluate(perfect, _ctx())
	var names: Array[String] = []
	for combo in rp["combos"]:
		names.append(str(combo["name"]))
	_check(names.has("完美配方"), "5 张不同类型命中完美配方")
	_eq(int(rp["score"]), 570, "完美配方得分 570")

	var deep: Array[CardData] = [
		_card("资深工程师"), _card("写个函数"), _card("输出一段 JSON"),
		_card("给一个正例"), _card("不得编造事实"),
	]
	var rd := Scoring.evaluate(deep, _ctx())
	names.clear()
	for combo in rd["combos"]:
		names.append(str(combo["name"]))
	_check(names.has("深度推理"), "任务+范例+约束 命中深度推理")
	_check(names.has("受控"), "含约束 命中受控")
	_eq(int(rd["score"]), 802, "深度推理 5 张得分 802")

	# 同类型 3 张 → 堆叠
	var stack: Array[CardData] = [_card("资深工程师"), _card("毒舌评论家"), _card("小学老师")]
	var rs := Scoring.evaluate(stack, _ctx())
	names.clear()
	for combo in rs["combos"]:
		names.append(str(combo["name"]))
	_check(names.has("堆叠 · 角色"), "3 张同类型命中堆叠")


func _test_scoring_penalties() -> void:
	print("[计分 · 惩罚与规则]")
	var c3: Array[CardData] = [_card("写个函数"), _card("资深工程师"), _card("输出一段 JSON")]
	var over := Scoring.evaluate(c3, _ctx({"token_budget": 2}))
	_eq(int(over["overflow"]), 2, "超预算 2 Token")
	_eq(int(over["score"]), 109 - 30, "超预算罚 30（2×15）")

	var risky: Array[CardData] = [_card("写个函数"), _card("资深工程师"), _card("先斩后奏")]
	var rr := Scoring.evaluate(risky, _ctx())
	_eq(int(rr["has_risk"]), 1, "识别出风险卡")
	_eq(int(rr["score"]), 62, "风险卡结算 62（132 − 70）")
	var olamo := _item("shield")
	var shield_items: Array[AiItemData] = [olamo]
	var rs2 := Scoring.evaluate(risky, _ctx({"shield": true, "items": shield_items}))
	_eq(int(rs2["score"]), 132, "OlaMo 护盾抵消幻觉惩罚 → 132")
	var rs3 := Scoring.evaluate(risky, _ctx({"shield": true}))
	_eq(int(rs3["score"]), 62, "无护盾道具时护盾不生效 → 62")

	var need_fmt := Scoring.evaluate(c3, _ctx({"rule": LevelData.Rule.NEED_FORMAT}))
	_check(int(need_fmt["score"]) == 109, "含格式卡时不受 NEED_FORMAT 规则影响")
	var no_fmt: Array[CardData] = [_card("写个函数"), _card("资深工程师"), _card("不得编造事实")]
	var rnf := Scoring.evaluate(no_fmt, _ctx({"rule": LevelData.Rule.NEED_FORMAT}))
	_check(int(rnf["score"]) < 109, "缺格式卡时分数减半（实得 %d）" % int(rnf["score"]))


func _test_scoring_items() -> void:
	print("[计分 · 道具]")
	var c3: Array[CardData] = [_card("写个函数"), _card("资深工程师"), _card("输出一段 JSON")]

	var sft := _item("flat_all")
	var items: Array[AiItemData] = [sft]
	var r := Scoring.evaluate(c3, _ctx({"items": items}))
	_eq(int(r["score"]), 116, "SFT 微调：所有卡 +2 → 116")

	var deepdeek := _item("first_core_x2")
	var items2: Array[AiItemData] = [deepdeek]
	var r2 := Scoring.evaluate(c3, _ctx({"items": items2}))
	_eq(int(r2["score"]), 131, "DeepDeek：首张任务卡 ×2 → 131")

	var small: Array[CardData] = [_card("资深工程师"), _card("输出一段 JSON")]
	var llamo := _item("minimal_x2")
	var items3: Array[AiItemData] = [llamo]
	var r3 := Scoring.evaluate(small, _ctx({"items": items3}))
	_eq(int(r3["score"]), 92, "LLaMo：≤2 张卡得分 ×2 → 92")

	var mistral := _item("budget")
	var items4: Array[AiItemData] = [mistral]
	_eq(Scoring.effective_budget(_ctx({"items": items4})), 12, "Mistraline：预算 +3 → 12")


func _test_run_state() -> void:
	print("[局内状态]")
	var run := RunState.new()
	run.reset_run()
	_eq(run.deck.size(), 20, "开局 20 张")
	_eq(run.compute, 0, "开局算力 0")

	var level := LevelPool.get_level("L1")
	run.start_level(level)
	_eq(run.hand.size(), 8, "开局抽 8 张手牌")
	_eq(run.turn, 0, "回合数 0")

	var played: Array[CardData] = [run.hand[0]]
	run.end_turn(played)
	_eq(run.turn, 1, "结算后回合 +1")
	_eq(run.hand.size(), 8, "结算后补满 8 张手牌")
	_eq(run.discard_pile.size(), 8, "弃牌堆 8 张（原手牌全部进弃牌堆）")

	# 弃牌堆回收：连续抽空牌库应能自动洗回
	for _i in 40:
		run.end_turn([])
	_eq(run.hand.size(), 8, "牌库耗尽后自动洗回，手牌仍有 8 张")


# ── 代码卡机制（当前主玩法）───────────────────────────
func _test_poker_cards() -> void:
	print("[扑克 · 牌数据]")
	# 起始牌池 = 完整一副扑克（2026-10-22 起由 9 张改为 52 张）
	var run := RunState.new()
	run.reset_run()
	run.ensure_poker_deck()
	_eq(run.poker_deck.size(), RunState.POKER_DECK_SIZE, "起始牌池 52 张（完整一副）")
	var ranks := {}
	for c in run.poker_deck:
		ranks[c.rank] = int(ranks.get(c.rank, 0)) + 1
	# 13 个点数各 4 张（A~K 齐全），一对/三条/四条才凑得出来
	var full := ranks.size() == RunState.POKER_RANKS
	for r in ranks:
		if int(ranks[r]) != 4:
			full = false
	_check(full, "13 个点数各 4 张（A~K 齐全）")
	var suits := {}
	for c in run.poker_deck:
		suits[c.suit] = true
	_eq(suits.size(), 4, "四种花色都有")
	# id / 显示名
	var h3 := PokerCard.make(PokerCard.Suit.HEART, 3)
	_eq(h3.id(), "H3", "红心 3 的 id = H3")
	_eq(h3.display_name(), "♥3", "红心 3 的显示名 = ♥3")
	_check(PokerCard.is_red(PokerCard.Suit.HEART), "红心是红色")
	_check(PokerCard.is_red(PokerCard.Suit.DIAMOND), "方块是红色")
	_check(not PokerCard.is_red(PokerCard.Suit.SPADE), "黑桃不是红色")
	_check(not PokerCard.is_red(PokerCard.Suit.CLUB), "梅花不是红色")


func _test_poker_hands() -> void:
	print("[扑克 · 牌型判定]")
	_eq(PokerHand.evaluate_type(_pk(["H1"])), PokerHand.Type.HIGH_CARD, "单张 = 高牌")
	_eq(PokerHand.evaluate_type(_pk(["H1", "S1"])), PokerHand.Type.PAIR, "两张同点 = 一对")
	_eq(PokerHand.evaluate_type(_pk(["H1", "S1", "H2", "S2"])), PokerHand.Type.TWO_PAIR, "两对")
	_eq(PokerHand.evaluate_type(_pk(["H3", "S3", "C3"])), PokerHand.Type.THREE_KIND, "三条")
	_eq(PokerHand.evaluate_type(_pk(["H1", "S2", "C3", "D4", "H5"])), PokerHand.Type.STRAIGHT, "1-5 = 顺子")
	_eq(PokerHand.evaluate_type(_pk(["H1", "H2", "H3", "H4", "H6"])), PokerHand.Type.FLUSH, "同花不连 = 同花")
	_eq(PokerHand.evaluate_type(_pk(["H3", "S3", "C3", "H4", "S4"])), PokerHand.Type.FULL_HOUSE, "3+2 = 葫芦")
	_eq(PokerHand.evaluate_type(_pk(["H3", "S3", "C3", "D3"])), PokerHand.Type.FOUR_KIND, "四张同点 = 四条")
	_eq(PokerHand.evaluate_type(_pk(["H1", "H2", "H3", "H4", "H5"])), PokerHand.Type.STRAIGHT_FLUSH, "同花顺")
	# 断号不是顺子
	_check(PokerHand.evaluate_type(_pk(["H1", "S2", "C3", "D4", "H6"])) != PokerHand.Type.STRAIGHT,
			"1-2-3-4-6 不是顺子")
	# 花色不同不是同花
	_check(PokerHand.evaluate_type(_pk(["H1", "H2", "H3", "H4", "S6"])) != PokerHand.Type.FLUSH,
			"四张红心 + 一张黑桃 不是同花")


func _test_poker_scoring() -> void:
	print("[扑克 · 结算]")
	# 一对黑桃3（两张黑牌）：chips = 10 + (3+3) + 2×25 = 66，mult = 2 → 132
	var blk := PokerHand.score(_pk(["S3", "C3"]))
	_eq(int(blk["chips"]), 66, "两张黑牌一对：筹码 66（10+6+50）")
	_eq(int(blk["mult"]), 2, "两张黑牌一对：倍率 2")
	_eq(int(blk["score"]), 132, "两张黑牌一对 = 132")

	# 一对红心3（两张红牌）：chips = 10 + 6 = 16，mult = 2 + 2×3 = 8 → 128
	var red := PokerHand.score(_pk(["H3", "D3"]))
	_eq(int(red["chips"]), 16, "两张红牌一对：筹码 16（10+6）")
	_eq(int(red["mult"]), 8, "两张红牌一对：倍率 8（2+6）")
	_eq(int(red["score"]), 128, "两张红牌一对 = 128")

	# 高牌单张黑6：chips = 5 + 6 + 25 = 36，mult = 1 → 36
	var hi := PokerHand.evaluate_type(_pk(["S6"]))
	_eq(hi, PokerHand.Type.HIGH_CARD, "单张黑6 = 高牌")
	var hi_res := PokerHand.score(_pk(["S6"]))
	_eq(int(hi_res["score"]), 36, "单张黑6 = 36（5+6+25）")

	# AI娘被动：Kweno 每张 +10 筹码
	var kw := PokerHand.score(_pk(["S3", "C3"]), {"ai_id": "kweno"})
	_eq(int(kw["chips"]), 66 + 20, "Kweno：每张 +10 筹码（66 → 86）")
	# ChatPPT：一对 +3 倍率
	var cp := PokerHand.score(_pk(["S3", "C3"]), {"ai_id": "chatppt"})
	_eq(int(cp["mult"]), 2 + 3, "ChatPPT：一对额外 +3 倍率（2 → 5）")
	# Grock：黑桃 +20 筹码
	var gr := PokerHand.score(_pk(["S3", "C3"]), {"ai_id": "grock"})
	_eq(int(gr["chips"]), 66 + 20, "Grock：每张黑桃 +20 筹码（66 → 86）")
	# DeepDeek：红心 +2 倍率
	var dd := PokerHand.score(_pk(["H3", "D3"]), {"ai_id": "deepdeek"})
	_eq(int(dd["mult"]), 8 + 2, "DeepDeek：每张红心 +2 倍率（8 → 10）")

	# 永久加成
	var bonus := PokerHand.score(_pk(["S6"]), {"bonus_chips": 100, "bonus_mult": 1})
	_eq(int(bonus["chips"]), 136, "永久筹码 +100 生效")
	_eq(int(bonus["mult"]), 2, "永久倍率 +1 生效")
	_eq(int(bonus["score"]), 272, "加成后的总分 = 136×2")


# ── UI 构建 ────────────────────────────────────────────
func _test_ui() -> void:
	print("[UI 构建]")
	var run := RunState.new()
	run.reset_run()
	var level := LevelPool.get_level("L1")

	var arena := ArenaScreen.new()
	arena.setup(run, level)
	root.add_child(arena)
	await process_frame
	_check(arena.get_node_or_null("HudLeft") != null, "Arena 左上 HUD 已构建")
	_check(arena.get_node_or_null("HudRight") != null, "Arena 右上 HUD 已构建")
	_check(arena.get_node_or_null("PromptArea") != null, "Arena 提示词区已构建")
	_check(arena.get_node_or_null("Sidebar") == null, "Arena 左侧信息栏已移除")
	_check(arena.get_node_or_null("Terminal") == null, "Arena 终端面板壳已移除")
	_check(arena.get_node_or_null("Overlay") != null, "Arena 结算弹窗已构建")
	await process_frame
	_check(run.poker_hand.size() == RunState.POKER_HAND_SIZE, "Arena 启动后抽 %d 张手牌" % RunState.POKER_HAND_SIZE)
	arena.queue_free()

	var reward := RewardScreen.new()
	reward.setup(run)
	root.add_child(reward)
	await process_frame
	_check(reward.get_child_count() > 0, "Reward 界面已构建")
	reward.queue_free()

	var menu := MainMenuScreen.new()
	root.add_child(menu)
	await process_frame
	_check(menu.get_child_count() > 0, "主菜单已构建")
	menu.queue_free()


# ── 完整战斗流程（程序化驱动真实 UI）──────────────────
func _test_arena_flow() -> void:
	print("[战斗流程]")
	var run := RunState.new()
	run.reset_run()
	var level := LevelPool.get_level("L1")

	var arena := ArenaScreen.new()
	arena.setup(run, level)
	var cleared := [false]
	var failed := [false]
	arena.level_cleared.connect(func(_s: int) -> void: cleared[0] = true)
	arena.level_failed.connect(func(_s: int) -> void: failed[0] = true)
	root.add_child(arena)
	await process_frame

	# 把手牌里前 3 张放进槽位
	for i in range(3):
		_check(arena.debug_place_card(i), "第 %d 张手牌落入槽位" % i)
	_check(arena.debug_played_count() == 3, "已打出 3 张卡")

	var before := run.score
	arena.debug_run()
	await process_frame
	await process_frame
	_check(run.score > before, "结算后得分增加（%d → %d）" % [before, run.score])
	_check(run.turn == 1, "回合数推进到 1")
	_check(arena.debug_played_count() == 0, "结算后槽位清空")
	_check(run.poker_hand.size() == RunState.POKER_HAND_SIZE, "结算后手牌补满 %d 张" % RunState.POKER_HAND_SIZE)

	# 打完剩余回合，验证关卡必然结束（通过或未通过都要走到结算界面）
	var guard := 0
	while run.turn < level.turns and guard < 10:
		guard += 1
		for i in range(4):
			arena.debug_place_card(i)
		arena.debug_run()
		for _i in 4:
			await process_frame
	# _on_run_pressed 内部有 0.6 秒的结算停顿再弹结果窗，等它过去
	await create_timer(1.0).timeout
	_check(cleared[0] or failed[0], "回合用尽后关卡正常结束（通过=%s 未通过=%s，得分 %d/%d）" % [
		str(cleared[0]), str(failed[0]), run.score, level.target_score
	])
	_check(run.score > 0, "整关累计得分 > 0（%d）" % run.score)
	arena.queue_free()


# ── 每关独立种子 & 卡牌翻转 ──────────────────────────
func _test_level_seeds_and_flip() -> void:
	print("[每关种子 & 卡牌翻转]")
	var run := RunState.new()
	run.reset_run()

	# 每一关的牌序都应该不同
	var orders := {}
	var dup := ""
	for lv in LevelPool.all_levels():
		run.start_poker_level(lv)
		var key := ""
		for c in run.poker_hand:
			key += c.id() + "|"
		if orders.has(key):
			dup = lv.id
		orders[key] = lv.id
	_check(dup == "", "10 关的牌序互不相同" + ("" if dup == "" else "（%s 与 %s 重复）" % [
		dup, str(orders.get(dup, "?"))]))

	# 同一关重打应可复现
	run.start_poker_level(LevelPool.get_level("L1"))
	var first := ""
	for c in run.poker_hand:
		first += c.id() + "|"
	run.start_poker_level(LevelPool.get_level("L1"))
	var again := ""
	for c in run.poker_hand:
		again += c.id() + "|"
	_check(first == again, "同一关重打时牌序可复现")

	# 结算弹窗：关卡结束后弹窗应可见，点「继续」才推进
	var run2 := RunState.new()
	run2.reset_run()
	var arena := ArenaScreen.new()
	arena.setup(run2, LevelPool.get_level("L1"))
	var advanced := [false]
	arena.advance_requested.connect(func() -> void: advanced[0] = true)
	root.add_child(arena)
	await process_frame
	# 先打两张牌，把回合数推到最后一回合并把分数顶到目标线，触发过关
	var lv := LevelPool.get_level("L1")
	arena.debug_place_card(0)
	arena.debug_place_card(1)
	run2.hands_left = 1
	run2.score = lv.target_score
	arena.debug_run()
	await create_timer(1.0).timeout
	_check(arena.debug_overlay_visible(), "回合用尽后弹出结算结果窗")
	_check(not advanced[0], "结果窗显示时不自动跳屏")
	arena.debug_click_continue()
	_check(advanced[0], "点「继续」后触发推进信号")

	arena.queue_free()


# ── 界面路由：切换界面时旧界面必须被销毁（回归缩进 bug）──
func _test_screen_router() -> void:
	print("[界面路由]")
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	_eq(main.debug_screen_count(), 1, "启动后只挂载 1 个界面（主菜单）")

	for screen in ["arena", "reward", "shop", "menu", "arena"]:
		main.debug_show(screen)
		await process_frame
		_eq(main.debug_screen_count(), 1, "切到「%s」后仍只有 1 个界面" % screen)

	# 连续快速切换也不能堆积
	for i in 5:
		main.debug_show("reward")
		main.debug_show("arena")
		await process_frame
	_eq(main.debug_screen_count(), 1, "连续快速切换 10 次后仍只有 1 个界面")
	main.queue_free()

func _test_poker_deck() -> void:
	print("[扑克 · 牌库与回合]")
	var run := RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))
	var level := LevelPool.get_level("L1")
	run.start_poker_level(level)
	_eq(run.poker_hand.size(), RunState.POKER_HAND_SIZE, "开局手牌 %d 张" % RunState.POKER_HAND_SIZE)
	_eq(run.hands_left, level.turns, "出牌次数 = 关卡回合数")
	_eq(run.discards_left, 2, "每关 2 次弃牌")
	_eq(run.score, 0, "开局 0 分")

	# 打一手：手牌补满、出牌次数 −1
	var before_hand := run.poker_hand.size()
	run.play_poker_hand([run.poker_hand[0]])
	_eq(run.poker_hand.size(), RunState.POKER_HAND_SIZE, "打完后手牌补满")
	_eq(run.hands_left, level.turns - 1, "出牌次数 −1")

	# 弃牌：手牌补满、弃牌次数 −1
	var disc_before := run.discards_left
	_check(run.discard_poker([run.poker_hand[0]]), "弃牌成功")
	_eq(run.discards_left, disc_before - 1, "弃牌次数 −1")
	_eq(run.poker_hand.size(), RunState.POKER_HAND_SIZE, "弃牌后手牌补满")

	# 加牌
	var deck_before := run.poker_deck.size()
	run.add_poker_card(PokerCard.Suit.SPADE, 10)
	_eq(run.poker_deck.size(), deck_before + 1, "奖励加牌后牌库 +1")


## 按 id 造一组卡
## 按 "H3" 形式造一组牌
func _pk(ids: Array) -> Array[PokerCard]:
	var out: Array[PokerCard] = []
	for i in ids:
		var cid := str(i)
		var s := -1
		match cid.substr(0, 1):
			"H": s = PokerCard.Suit.HEART
			"D": s = PokerCard.Suit.DIAMOND
			"S": s = PokerCard.Suit.SPADE
			"C": s = PokerCard.Suit.CLUB
		if s >= 0:
			out.append(PokerCard.make(s, int(cid.substr(1))))
	return out


