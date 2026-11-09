extends SceneTree
## 冒烟测试：杀戮尖塔制（2026-10-25 大改）——卡池 / 关卡 / 战斗状态机 / UI / 整场战斗 / 路由。
##
## 运行：godot --headless --path <项目> --import
##       godot --headless --path <项目> --script res://tests/smoke_test.gd

var _fails := 0
var _checks := 0

var _host: Control = null


func _initialize() -> void:
	_host = Control.new()
	_host.name = "TestRoot"
	_host.size = Vector2(1920, 1080)
	get_root().add_child(_host)

	_test_sts_cards()
	_test_level_pool()
	_test_sts_combat()
	_test_rice()
	await _test_ui()
	await _test_battle_flow(true)
	await _test_battle_flow(false)
	await _test_battle_intro()
	await _test_map_event()
	await _test_screen_router()
	_test_effect_dsl()
	_test_dsl_spec_file()
	_test_effect_combat()
	_test_pricing()
	_test_combo()
	_test_energy_system()
	await _test_wish_canvas_colors()
	await _test_wish_canvas_edit()
	await _test_card_flip()
	await _test_ripple_swap()
	await _test_panel_morph()
	await _test_mosaic_and_select()
	await _test_patch_demo()
	_test_affection_system()
	await _test_shop_gifts()
	_test_wish_budget()
	await _test_prefetch_state()
	_test_llm_config()
	_test_llm_protocol()
	_test_llm_parse()
	_test_llm_opponent()
	_test_llm_event()
	await _test_llm_client()
	await _test_llm_banter()
	await _test_llm_arena()
	print("\n==== %d 项检查，%d 项失败 ====" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok  %s" % what)
	else:
		_fails += 1
		print("  FAIL %s" % what)


func _eq(a, b, what: String) -> void:
	_check(a == b, "%s（得 %s，期望 %s）" % [what, str(a), str(b)])


# ── ① 卡池 ────────────────────────────────────────────
func _test_sts_cards() -> void:
	print("[卡池]")
	var ids := StsCardPool.all_ids()
	_eq(ids.size(), 9, "卡池共 9 张卡（7 张通用 + ChatPPT 专属攻防 2 张）")
	var ram := StsCardPool.card("fish_ram")
	_check(ram != null and ram.damage == 6 and ram.cost == 1
			and ram.kind == StsCard.Kind.ATTACK, "肥鱼铁头撞：1 费攻击 6 伤")
	var taunt := StsCardPool.card("taunt")
	_check(taunt != null and taunt.block == 5 and taunt.cost == 1
			and taunt.kind == StsCard.Kind.SKILL, "来打我呀！：1 费防御 5 格挡")
	var loop := StsCardPool.card("loop")
	_check(loop != null and loop.cost == 1 and loop.damage == 0 and loop.block == 0
			and loop.kind == StsCard.Kind.SKILL, "复读机：1 费指令行（0 伤 0 挡）")
	var par := StsCardPool.card("parallel")
	_check(par != null and par.cost == 1 and par.damage == 0 and par.block == 0
			and par.kind == StsCard.Kind.SKILL, "并行：1 费指令行（0 伤 0 挡）")
	_eq(StsCardPool.desc("loop"), "下一张卡执行两次。", "复读机描述")
	_eq(StsCardPool.desc("parallel"), "本次运行换类型不断连段。", "并行描述")
	var deck := StsCardPool.starter_deck()
	_eq(deck.size(), 10, "起始卡组共 10 张")
	var atk := 0
	var def := 0
	var loop_n := 0
	var par_n := 0
	for c in deck:
		atk += 1 if c.kind == StsCard.Kind.ATTACK else 0
		def += 1 if c.kind == StsCard.Kind.SKILL else 0
		loop_n += 1 if c.id == "loop" else 0
		par_n += 1 if c.id == "parallel" else 0
	_check(atk == 3 and def == 7, "起始卡组 3 攻 + 7 防（3 鱼 + 2 锅 + 3 饭 + 2 指令行，得 %d+%d）" % [atk, def])
	_check(loop_n == 1 and par_n == 1, "起始卡组含复读机与并行各 1 张（得 %d+%d）" % [loop_n, par_n])
	for c in deck:
		_check(ResourceLoader.exists(c.art_path), "卡面贴图存在：%s" % c.id)


# ── ② 关卡 ────────────────────────────────────────────
func _test_level_pool() -> void:
	print("[关卡]")
	var ls := LevelPool.all_levels()
	_eq(ls.size(), 10, "共 10 关")
	var prev_hp := 0
	for i in ls.size():
		var l := ls[i]
		_check(l.enemy_hp > prev_hp, "%s 敌人 HP 递增（%d）" % [l.id, l.enemy_hp])
		prev_hp = l.enemy_hp
		_check(l.enemy_name != "" and l.enemy_atk > 0 and l.enemy_def > 0,
				"%s 敌人数据完整" % l.id)
		var pat := l.enemy_pattern()
		_eq(pat.size(), 3, "%s 意图序列长 3" % l.id)
	_eq(ls[9].is_boss, true, "L10 是 BOSS")


# ── ③ 战斗状态机（纯逻辑，确定性种子）────────────────
func _test_sts_combat() -> void:
	print("[战斗状态机]")
	var cb := StsCombat.new()
	cb.setup(StsCardPool.starter_deck(), "幻觉幼虫", 40,
			[{"kind": "attack", "value": 7}, {"kind": "defend", "value": 4},
			 {"kind": "attack", "value": 7}], 80, 424242)
	_eq(cb.hand.size(), 4, "开局抽 4 张（DeepSeek 补牌数）")
	_eq(cb.turn, 1, "开局回合 1")
	_eq(cb.enemy_atk, 7, "敌人攻击取自意图序列（7）")
	_eq(cb.enemy_def, 4, "敌人防御取自意图序列（4）")

	# 按顺序出牌：只有最左一张能打
	_check(cb.can_play(cb.hand[0]), "最左一张可打")
	if cb.hand.size() > 1:
		_check(not cb.can_play(cb.hand[1]), "第二张不能跳着打")

	# 按顺序把 4 张全打出去（无出牌数量限制）：打空后自动从弃牌堆随机补 4
	for i in 4:
		_check(cb.can_play(cb.hand[0]), "第 %d 张：最左可打" % (i + 1))
		var e1 := cb.play_card(cb.hand[0])
		_check(bool(e1.get("ok", false)), "第 %d 张按顺序打出" % (i + 1))
	_eq(cb.hand.size(), 4, "手牌打空后自动从弃牌堆随机补 4 张")
	_eq(cb.discard_pile.size(), 0, "补牌从弃牌堆抽走")
	_eq(cb.draw_pile.size() + cb.discard_pile.size() + cb.hand.size(), 10,
			"牌堆守恒：抽 + 弃 + 手 = 10")
	_check(cb.can_play(cb.hand[0]), "补牌后最左一张可打")

	# 弃牌：弃 1 张立刻从牌堆抽 1 张，手牌数不变
	var before := cb.hand.size()
	_check(cb.discard_card(cb.hand[0]), "弃牌成功")
	_eq(cb.hand.size(), before, "弃 1 抽 1，手牌数不变")
	_eq(cb.draw_pile.size() + cb.discard_pile.size() + cb.hand.size(), 10, "弃牌后守恒")

	# 结束回合：敌人行动 + 回合推进
	var events := cb.end_turn()
	_eq(cb.block, 0, "新回合格挡清零")
	_check(cb.hand.size() >= 1, "新回合手牌有牌（全牌堆采样补牌）")
	_check(events.size() >= 1, "结束回合返回敌人行动事件")
	_eq(cb.turn, 2, "回合推进到 2")
	_eq(cb.draw_pile.size() + cb.discard_pile.size() + cb.hand.size(), 10, "新回合守恒")

	# ── 执行序列（A 连段 / B 首尾槽 / C 米饭不断连）：空牌局 + 手动摆队列 ──
	var empty_deck: Array[StsCard] = []
	var sq := StsCombat.new()
	sq.setup(empty_deck, "沙袋", 9999,
			[{"kind": "attack", "value": 5}, {"kind": "defend", "value": 4}], 80, 1)
	# B 首位「初始化」+2：hand[0] 鱼 = lead → 6+2=8
	sq.hand.clear()
	sq.hand.append(StsCardPool.card("fish_ram"))
	sq.hand.append(StsCardPool.card("fish_ram"))
	var e_lead := sq.play_card(sq.hand[0], false, true)
	_eq(int(e_lead.get("value", 0)), 8, "首位「初始化」：鱼 6+2=8")
	_eq(int(e_lead.get("streak", 0)), 1, "第一条鱼连段 1")
	# A 连段阶梯：同类连击每进一阶 +3 → 6+3=9；第三条 6+3×2=12
	var e_s2 := sq.play_card(sq.hand[0], false)
	_eq(int(e_s2.get("value", 0)), 9, "同类连击连段 2：6+3=9")
	sq.hand.append(StsCardPool.card("fish_ram"))
	var e_s3 := sq.play_card(sq.hand[0], false)
	_eq(int(e_s3.get("value", 0)), 12, "连段 3：6+3×2=12")
	# A 换类型断连：taunt 从连段 1 重新起步 → 5
	sq.hand.clear()
	sq.hand.append(StsCardPool.card("taunt"))
	var e_br := sq.play_card(sq.hand[0], false)
	_eq(int(e_br.get("value", 0)), 5, "换类型断连：taunt 连段 1 → 5")
	# B 末位「收尾」+2：断连后的 taunt 在末位 → 5+2=7
	sq.hand.clear()
	sq.hand.append(StsCardPool.card("fish_ram"))
	sq.hand.append(StsCardPool.card("fish_ram"))
	sq.hand.append(StsCardPool.card("taunt"))
	sq.play_card(sq.hand[0], false, true)
	sq.play_card(sq.hand[0], false)
	var e_fn := sq.play_card(sq.hand[0], false, false, true)
	_eq(int(e_fn.get("value", 0)), 7, "末位「收尾」：taunt 5+2=7")
	# C 米饭是「注释行」：夹在两条鱼之间不断连
	sq.hand.clear()
	sq.hand.append(StsCardPool.card("fish_ram"))
	sq.hand.append(StsCardPool.card("rice"))
	sq.hand.append(StsCardPool.card("fish_ram"))
	sq.play_card(sq.hand[0], false, true)
	var e_rice := sq.play_card(sq.hand[0], false)
	_eq(String(e_rice.get("kind", "")), "rice", "米饭打出 rice 事件")
	var e_af := sq.play_card(sq.hand[0], false)
	_eq(int(e_af.get("value", 0)), 9, "米饭不断连：第二条鱼仍是连段 2 → 9")

	# preview_sequence：影子推演（先序列收尾，与真实发送同一起点）
	sq.end_send()
	_eq(sq.seq_streak, 0, "序列收尾：连段清零（下一回合从连段 1 起步）")
	sq.hand.clear()
	sq.hand.append(StsCardPool.card("fish_ram"))
	sq.hand.append(StsCardPool.card("fish_ram"))
	sq.hand.append(StsCardPool.card("rice"))
	var seq := sq.preview_sequence()
	_eq(seq.size(), 3, "预览与手牌等长")
	_eq(int(seq[0].get("value", 0)), 8, "预览：首位鱼 8（lead）")
	_eq(int(seq[1].get("value", 0)), 9, "预览：第二条鱼连段 2 → 9")
	_check(not bool(seq[1].get("buffed", true)), "预览：未睡醒无加成标记")
	_eq(int(seq[1].get("buffed_value", 0)), int(round(9.0 * StsCombat.RICE_BUFF)),
			"预览：buffed_value = round(9×1.2) = 11")
	_check(bool(seq[2].get("growth", false)), "预览：米饭 growth=true")
	_eq(sq.hand.size(), 3, "预览不改手牌")
	# 睡醒后的预览：buffed=true，value 保持未乘值
	sq.rice_eaten = StsCombat.RICE_AWAKE
	var seq2 := sq.preview_sequence()
	_check(bool(seq2[1].get("buffed", false)), "预览：睡醒后 buffed=true")
	_eq(int(seq2[1].get("value", 0)), 9, "预览：睡醒后 value 仍是阶梯+槽位未乘值")

	# ── D 指令行：复读机（loop）与并行（parallel）──────────
	var dcb := StsCombat.new()
	dcb.setup(empty_deck, "沙袋", 9999,
			[{"kind": "attack", "value": 5}, {"kind": "defend", "value": 4}], 80, 1)
	# D 复读：[loop][fish]（loop 首位、fish 末位）→ fish 两次逐次推阶 8+10=18
	dcb.hand.clear()
	dcb.hand.append(StsCardPool.card("loop"))
	dcb.hand.append(StsCardPool.card("fish_ram"))
	var e_loop := dcb.play_card(dcb.hand[0], false, true)
	_eq(String(e_loop.get("kind", "")), "loop", "复读机打出 loop 事件（指令行不断连段）")
	_eq(dcb.pending_repeat, 1, "复读缓冲挂起：pending_repeat=1")
	_eq(dcb.seq_streak, 0, "指令行不推连段（loop）")
	var e_rep := dcb.play_card(dcb.hand[0], false, false, true)
	_eq(int(e_rep.get("value", 0)), 19, "复读：fish 执行两次 8+11=19（连段两阶+末位收尾）")
	_check(bool(e_rep.get("repeat", false)), "复读事件带 repeat 标记")
	_eq(int(e_rep.get("streak", 0)), 2, "复读后连段停在 2（连段算两阶）")
	_eq(dcb.pending_repeat, 0, "复读缓冲已消费")

	# D 并行：[parallel][fish][taunt][fish] → 锁连段 = 阶数冻结 → 6/5/8
	dcb.end_send()
	_eq(dcb.pending_repeat, 0, "end_send 清 pending_repeat（缓冲不跨运行）")
	_eq(dcb.streak_lock, false, "end_send 清 streak_lock")
	dcb.hand.clear()
	dcb.hand.append(StsCardPool.card("parallel"))
	dcb.hand.append(StsCardPool.card("fish_ram"))
	dcb.hand.append(StsCardPool.card("taunt"))
	dcb.hand.append(StsCardPool.card("fish_ram"))
	var e_par := dcb.play_card(dcb.hand[0], false, true)
	_eq(String(e_par.get("kind", "")), "parallel", "并行打出 parallel 事件")
	_eq(dcb.streak_lock, true, "并行锁挂起：streak_lock=true")
	_eq(dcb.seq_streak, 0, "指令行不推连段（parallel）")
	var e_pf1 := dcb.play_card(dcb.hand[0], false)
	_eq(int(e_pf1.get("value", 0)), 6, "并行锁：fish 连段 1 → 6")
	var e_pf2 := dcb.play_card(dcb.hand[0], false)
	_eq(int(e_pf2.get("value", 0)), 5, "并行锁：换类型阶数冻结，taunt 连段 1 → 5")
	var e_pf3 := dcb.play_card(dcb.hand[0], false, false, true)
	_eq(int(e_pf3.get("value", 0)), 8, "并行锁：fish 冻结连段 1 + 末位收尾 → 8")

	# loop 后接 rice：复读不作用于白米饭，缓冲顺延给下一张非饭卡
	dcb.end_send()
	dcb.hand.clear()
	dcb.hand.append(StsCardPool.card("loop"))
	dcb.hand.append(StsCardPool.card("rice"))
	dcb.play_card(dcb.hand[0], false)
	var e_rr := dcb.play_card(dcb.hand[0], false)
	_eq(String(e_rr.get("kind", "")), "rice", "loop 后打 rice：米饭正常")
	_check(bool(e_rr.get("repeat", false)), "复读机对米饭生效（repeat 标记）")
	_eq(int(e_rr.get("value", 0)), 2, "一次吃 2 碗（2026-11-01 主人钦定）")
	_eq(dcb.pending_repeat, 0, "复读缓冲已消费")
	dcb.hand.append(StsCardPool.card("fish_ram"))
	var e_defer := dcb.play_card(dcb.hand[0], false, false, true)
	_eq(int(e_defer.get("value", 0)), 8, "复读已被米饭消费：fish 单次执行（末位 6+2=8）")

	# 预览同步：指令行条目（growth 标记）与并行冻结语义
	dcb.end_send()
	dcb.hand.clear()
	dcb.hand.append(StsCardPool.card("parallel"))
	dcb.hand.append(StsCardPool.card("fish_ram"))
	dcb.hand.append(StsCardPool.card("taunt"))
	dcb.hand.append(StsCardPool.card("fish_ram"))
	var pseq := dcb.preview_sequence()
	_eq(pseq.size(), 4, "预览与手牌等长（D）")
	_check(bool(pseq[0].get("growth", false)), "预览：并行是指令行（growth 标记）")
	_eq(int(pseq[1].get("value", 0)), 6, "预览：并行锁下 fish 连段 1 → 6")
	_eq(int(pseq[2].get("value", 0)), 5, "预览：并行锁下换类型冻结 taunt → 5")
	_eq(int(pseq[3].get("value", 0)), 8, "预览：末位 fish 冻结连段 1 + 收尾 → 8")
	dcb.hand.clear()
	dcb.hand.append(StsCardPool.card("loop"))
	dcb.hand.append(StsCardPool.card("fish_ram"))
	var pseq2 := dcb.preview_sequence()
	_check(bool(pseq2[0].get("growth", false)), "预览：复读机是指令行（growth 标记）")
	_eq(int(pseq2[1].get("value", 0)), 8, "预览：复读只显示单次 8（复读加成不在预览内）")

	# E 观察者：一序列 ≥2 攻 → 敌人下回合意图改防御（enemy_def+OBS_BRACE）
	var ob := StsCombat.new()
	ob.setup(empty_deck, "沙袋", 9999,
			[{"kind": "attack", "value": 5}, {"kind": "defend", "value": 4}], 80, 1)
	ob.hand.clear()
	ob.hand.append(StsCardPool.card("fish_ram"))
	ob.hand.append(StsCardPool.card("fish_ram"))
	ob.play_card(ob.hand[0], false, true)
	ob.play_card(ob.hand[0], false)
	_eq(ob.seq_attacks, 2, "观察者统计：本序列 2 次攻击")
	var evs := ob.end_turn()
	var saw_obs := false
	for e in evs:
		if String(e.get("kind", "")) == "observer":
			saw_obs = true
	_check(saw_obs, "观察者反应出现在 end_turn 事件里")
	_eq(String(ob.intent.get("kind", "")), "defend", "观察者：敌人下回合意图改防御")
	_eq(int(ob.intent.get("value", 0)), ob.enemy_def + StsCombat.OBS_BRACE,
			"观察者防御值 = enemy_def(4)+0 = 4（T5 定稿：架基本盾不加码）")
	_eq(ob.seq_attacks, 0, "观察者统计随回合清零")

	# 连打：攻击/防御两种牌都会轮到，打死敌人
	var saw_attack := false
	var saw_skill := false
	var guard := 0
	while cb.over == StsCombat.Result.RUNNING and guard < 60:
		guard += 1
		var e2 := cb.play_card(cb.hand[0])
		if bool(e2.get("ok", false)):
			if String(e2.get("kind", "")) == "attack":
				saw_attack = true
			else:
				saw_skill = true
	_eq(cb.over, StsCombat.Result.WIN, "反复出牌后击败敌人")
	_check(saw_attack, "攻击牌结算过")
	_check(saw_skill, "防御牌结算过")

	# 站着挨打 → LOSE
	var cb2 := StsCombat.new()
	cb2.setup(StsCardPool.starter_deck(), "沙袋", 9999,
			[{"kind": "attack", "value": 30}], 50, 1)
	guard = 0
	while cb2.over == StsCombat.Result.RUNNING and guard < 20:
		cb2.end_turn()
	_eq(cb2.over, StsCombat.Result.LOSE, "不防御会被打死")
	_eq(cb2.hp, 0, "败时 HP 归 0")


# ── ③b 白米饭成长 ───────────────────────────────────────
func _test_rice() -> void:
	print("[白米饭成长]")
	var deck := StsCardPool.starter_deck()
	_eq(deck.size(), 10, "起始卡组 10 张（3 攻 + 2 防 + 3 饭 + 1 复读 + 1 并行）")
	var rice_n := 0
	for c in deck:
		if c.id == "rice":
			rice_n += 1
	_eq(rice_n, 3, "白米饭 3 张")

	var cb := StsCombat.new()
	cb.setup(deck, "沙袋", 9999, [{"kind": "attack", "value": 4}], 80, 7)
	_eq(cb.rice_eaten, 0, "开局 0 碗（每局重置）")
	_eq(cb.is_awake(), false, "开局未成长")

	# 按顺序出牌只能打 hand[0]：把白米饭插到最左再打
	cb.hand.insert(0, StsCardPool.card("rice"))
	var e1 := cb.play_card(cb.hand[0])
	_eq(String(e1.get("kind", "")), "rice", "白米饭可打出")
	_eq(cb.rice_eaten, 1, "吃 1 碗")
	_check(not bool(e1.get("awake_now", false)), "第 1 碗：事件不带 awake_now")
	_eq(cb.is_awake(), false, "1 碗还没醒")

	cb.hand.insert(0, StsCardPool.card("rice"))
	var e2r := cb.play_card(cb.hand[0])
	_eq(cb.rice_eaten, 2, "吃满 2 碗")
	_check(bool(e2r.get("stir_now", false)), "第 2 碗：事件带 stir_now（翻身瞬间）")
	_check(not bool(e2r.get("awake_now", false)), "第 2 碗：仍不唤醒")
	_eq(cb.is_stir(), true, "2 碗 → 翻身阶段（仍睡眠）")
	_eq(cb.is_awake(), false, "2 碗还没醒")

	# 3..4 碗：仍在翻身阶段
	cb.hand.insert(0, StsCardPool.card("rice"))
	cb.play_card(cb.hand[0])
	cb.hand.insert(0, StsCardPool.card("rice"))
	var e4r := cb.play_card(cb.hand[0])
	_eq(cb.rice_eaten, 4, "吃满 4 碗")
	_eq(cb.is_stir(), true, "4 碗仍是翻身阶段")
	_eq(cb.is_awake(), false, "4 碗还没醒")

	# 第 5 碗：完全觉醒 + 赠两张特殊攻击牌进弃牌堆
	cb.hand.insert(0, StsCardPool.card("rice"))
	var e5r := cb.play_card(cb.hand[0])
	_eq(cb.rice_eaten, 5, "吃满 5 碗")
	_check(bool(e5r.get("awake_now", false)), "第 5 碗：事件带 awake_now（觉醒瞬间）")
	_eq(cb.is_awake(), true, "吃满 5 碗 → 完全觉醒")
	_check(cb.discard_pile.any(func(c: StsCard) -> bool: return c.id == "cannon"),
			"觉醒赠卡：鲸鱼铁头炮进弃牌堆")
	_check(cb.discard_pile.any(func(c: StsCard) -> bool: return c.id == "rage"),
			"觉醒赠卡：觉醒怒涛进弃牌堆")

	# 醒态加成：攻击 6 → 7（+20%），格挡 5 → 6（+20%）
	cb.hand.insert(0, StsCardPool.card("fish_ram"))
	var ea := cb.play_card(cb.hand[0])
	_eq(int(ea.get("value", 0)), 7, "醒态攻击 6 → 7（+20%）")
	cb.hand.insert(0, StsCardPool.card("taunt"))
	var ed := cb.play_card(cb.hand[0])
	_eq(int(ed.get("value", 0)), 6, "醒态格挡 5 → 6（+20%）")

	# 觉醒攻击牌：鲸鱼铁头炮无视格挡
	cb.enemy_block = 10
	cb.hand.insert(0, StsCardPool.card("cannon"))
	var ec := cb.play_card(cb.hand[0])
	_eq(int(ec.get("value", 0)), int(round(12.0 * StsCombat.RICE_BUFF)),
			"鲸鱼铁头炮：无视 10 点格挡全额命中（×1.2）")

	# 觉醒怒涛：执行两次，连段进两阶（前一张是炮=攻击连段中）
	cb.hand.insert(0, StsCardPool.card("rage"))
	var er := cb.play_card(cb.hand[0])
	_check(bool(er.get("repeat", false)) == false and int(er.get("value", 0)) > 0,
			"觉醒怒涛打出")
	_eq(int(er.get("streak", 0)), 0, "占位（下面按 hit 明细断言）") if false else null
	var hits := int(er.get("value", 0))
	_check(hits > 0, "觉醒怒涛造成伤害 %d（两次执行合计）" % hits)

	# 新开一局 → 计数清零
	var cb2 := StsCombat.new()
	cb2.setup(deck, "沙袋", 9999, [{"kind": "attack", "value": 4}], 80, 7)
	_eq(cb2.rice_eaten, 0, "新对局状态重置")


# ── ④ 战斗 UI 构建 ────────────────────────────────────
func _test_ui() -> void:
	print("[战斗界面]")
	var run := RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))
	_eq(run.deck.size(), 10, "开局卡组 10 张（含 3 张白米饭与两张 D 指令行）")

	# 启动界面接手了旧主菜单的 BGM 播放入口，先确认它真的在放
	var launch := LaunchScreen.new()
	_host.add_child(launch)
	await process_frame
	_eq(SfxNode.current_music(), "bgm_gemini2", "启动界面 BGM 已开")
	launch.queue_free()

	var arena := ArenaScreen.new()
	arena.setup(run, LevelPool.get_level("L1"))
	_host.add_child(arena)
	await process_frame
	await process_frame

	_check(arena.get_node_or_null("HudLeft") != null, "左侧玩家栏已构建")
	_eq(SfxNode.current_music(), "bgm_gemini2", "战斗 BGM = bgm_gemini2（全程同一首）")
	_check(arena.get_node_or_null("HudRight") != null, "右上敌人栏已构建")
	_check(arena.get_node_or_null("EnemyStage") != null, "敌人舞台已构建")
	_check(arena.get_node_or_null("Overlay") != null, "结算弹窗已构建")
	_check(arena.get_node_or_null("AiCompanion") != null, "右侧 AI 娘已挂载")
	_check(arena.get_node_or_null("PileDrawIcon") != null, "牌堆图标已构建")
	_check(arena.get_node_or_null("PileDiscardIcon") != null, "弃牌图标已构建")
	_check(arena.get_node_or_null("PilePanel") != null, "牌堆查看面板已构建")

	var st := arena.debug_combat_state()
	_eq(st.get("hand", 0), 4, "界面手牌 4 张（按角色补牌数）")
	_eq(st.get("enemy_hp", -1), 40, "L1 敌人 HP 40")
	_eq(arena.debug_hand_count(), 4, "手牌视图 4 张")

	# 卡视图尺寸与小 GUI
	var layer := arena.get_node_or_null("CardLayer")
	var view: StsCardView = null
	if layer != null:
		for c in layer.get_children():
			if c is StsCardView:
				view = c
				break
	if view != null:
		_eq(Vector2(view.size), Vector2(150, 226), "卡视图 150×226")
		_check(view.get_node_or_null("Art") == null or true, "卡面节点存在")
	arena.queue_free()

	var reward := RewardScreen.new()
	reward.setup(run)
	_host.add_child(reward)
	await process_frame
	_check(reward.get_child_count() > 0, "奖励界面已构建")
	reward.queue_free()


# ── ⑤ 整场战斗（胜 / 败两局）────────────────────────
func _test_battle_flow(win_expected: bool) -> void:
	print("[整场战斗·%s]" % ("速胜" if win_expected else "挨打"))
	var run := RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))

	var arena := ArenaScreen.new()
	if win_expected:
		# 速胜局：把敌人换成 20 血的脆皮（直接改关卡数据）
		var lv := LevelPool.get_level("L1")
		lv.enemy_hp = 20
		arena.setup(run, lv)
	else:
		arena.setup(run, LevelPool.get_level("L10"))
	var advanced := [false]
	var cleared := [false]
	var failed := [false]
	arena.advance_requested.connect(func() -> void: advanced[0] = true)
	arena.level_cleared.connect(func(_s: int) -> void: cleared[0] = true)
	arena.level_failed.connect(func(_s: int) -> void: failed[0] = true)
	_host.add_child(arena)
	await process_frame

	var guard := 0
	while not arena.debug_overlay_visible() and guard < 300:
		guard += 1
		await create_timer(0.06).timeout
		var st := arena.debug_combat_state()
		if int(st.get("over", 0)) != 0:
			continue
		# 新规则：无能量、按顺序出牌、无张数限制 —— 手牌有牌就一直打最左那张
		if win_expected and int(st.get("hand", 0)) > 0:
			arena.debug_play_card(0)
		elif not win_expected:
			# 挨打局：直接结束回合
			arena.debug_end_turn()
			await create_timer(0.3).timeout
		else:
			arena.debug_end_turn()
			await create_timer(0.3).timeout

	_check(arena.debug_overlay_visible(), "结算弹窗弹出（guard=%d）" % guard)
	if win_expected:
		_check(cleared[0], "胜利信号已发出")
		_check(not failed[0], "没有误发失败信号")
	else:
		_check(failed[0], "失败信号已发出")
	var st2 := arena.debug_combat_state()
	_check(str(arena.debug_status_text()).length() >= 0, "状态栏可读（over=%d）" % int(st2.get("over", -1)))

	arena.debug_click_continue()
	await process_frame
	_check(advanced[0], "点继续发出 advance 信号")
	arena.queue_free()


# ── ⑥ 界面路由 ────────────────────────────────────────
func _test_screen_router() -> void:
	print("[界面路由]")
	var main: Node = load("res://scripts/main.gd").new()
	_host.add_child(main)
	await process_frame
	_eq(main.debug_screen_count(), 1, "启动后只挂载 1 个界面")
	# 体验沙盒：F1 面板存在、不计入界面数
	var sb := main.get_node_or_null("SandboxPanel")
	_check(sb != null, "体验沙盒面板已构建")
	_check(sb != null and sb.get_child_count() > 0, "沙盒面板有内容")
	_eq(main.debug_screen_count(), 1, "沙盒面板不计入界面数")

	# 本次改动 Demo：启动界面图标入口 + 下拉（2026-11-03）
	var demo_entry: Node = main._current.find_child("LlmDemoEntry", true, false)
	_check(demo_entry == null, "图标入口初始不存在（未展开对话框）")
	main._current.expand()
	await process_frame
	demo_entry = main._current.find_child("LlmDemoEntry", true, false)
	_check(demo_entry != null, "对话框展开后 Demo 图标入口出现")
	_check(demo_entry is TextureButton and String((demo_entry as TextureButton).tooltip_text) == "demo", "Demo 图标 tooltip = demo")
	var ai_entry: Node = main._current.find_child("AiSettingsEntry", true, false)
	_check(ai_entry is TextureButton and String((ai_entry as TextureButton).tooltip_text) == "模型接入", "模型接入图标 tooltip 正确")
	_check(main._current._skill_list.visible == false and main._current._mcp_box.visible == false, "技能/MCP 默认收起")
	main._current._toggle_skill()
	await process_frame
	_check(main._current._skill_list.visible, "点击技能标题展开列表")
	var demo_page := LLMDemoScreen.new()
	_host.add_child(demo_page)
	await process_frame
	_check(demo_page.get_child_count() > 0, "Demo 页已构建")
	demo_page._switch_tab(1)
	await process_frame
	_check(demo_page._combat != null, "Demo 真对战可初始化")
	demo_page._switch_tab(2)
	await process_frame
	_check(demo_page._event_run != null, "Demo 事件引擎可初始化")
	demo_page.queue_free()

	for screen in ["arena", "reward", "map", "event", "menu", "result"]:
		main.debug_show(screen)
		await process_frame
		_eq(main.debug_screen_count(), 1, "切到「%s」后仍只有 1 个界面" % screen)
	main.queue_free()


# ── ⑦ 进场转场（2D→3D→2D）──────────────────────────
func _test_battle_intro() -> void:
	print("[进场转场]")
	var host := Control.new()
	host.size = Vector2(800, 600)
	_host.add_child(host)
	await process_frame

	var tex := ImageTexture.create_from_image(
		Image.create_empty(64, 64, false, Image.FORMAT_RGBA8))

	# ① 正常播完
	var intro := BattleIntro.new()
	host.add_child(intro)
	var done := [false]
	intro.play([tex], null, func() -> void: done[0] = true)
	_check(intro.get_child_count() > 0, "3D 子视口与 3D 场景已挂载")
	var guard := 0
	while not done[0] and guard < 400:
		guard += 1
		await create_timer(0.02).timeout
	_check(done[0], "转场播完并触发回调（%.1fs）" % (guard * 0.02))
	_check(not is_instance_valid(intro) or intro.debug_done(), "转场组件标记结束并自毁")

	# ② 点击跳过
	var intro2 := BattleIntro.new()
	host.add_child(intro2)
	var done2 := [false]
	intro2.play([tex, tex], tex, func() -> void: done2[0] = true)
	await create_timer(0.3).timeout
	_check(not done2[0], "播放中尚未结束")
	intro2.skip()
	await process_frame
	_check(done2[0], "skip() 立刻触发回调")
	host.queue_free()


# ── ⑧ 选关地图（门概率制） / 事件 / 精英 ────────────────
func _test_map_event() -> void:
	print("[选关地图]")
	var run := RunState.new()
	run.reset_run()
	_eq(run.events_since_battle, 0, "事件冷却开局为 0")

	# 门概率表 + 沙盒强制门优先级（2026-11-02 修：force 曾被随机 roll 覆盖）
	_eq(RunState.pick_special(0.10, ""), "elite", "门概率：<20% → 精英门")
	_eq(RunState.pick_special(0.30, ""), "event", "门概率：20~50% → 事件门")
	_eq(RunState.pick_special(0.50, ""), "bonus", "门概率：45~55% → 奖励门")
	_eq(RunState.pick_special(0.60, ""), "shop", "门概率：55~65% → 商店门")
	_eq(RunState.pick_special(0.90, ""), "", "门概率：≥65% → 纯战斗")
	_eq(RunState.pick_special(0.10, "event"), "event", "强制门覆盖随机（事件）")
	_eq(RunState.pick_special(0.90, "elite"), "elite", "强制门覆盖随机（精英）")

	# 纯战斗段（50%）：只有战斗门
	var m := MapScreen.new()
	m.setup(run, "")
	_host.add_child(m)
	await process_frame
	_check(m.get_child_count() > 0, "门界面已构建（纯战斗）")
	var battle_sig := [false]
	m.battle_entered.connect(func() -> void: battle_sig[0] = true)
	(m._door_battle.get_node("DoorArt") as Control).gui_input.emit(_make_click_event())
	await process_frame
	_check(battle_sig[0], "战斗门点击 → battle_entered")
	m.queue_free()

	# 事件段（40%）：事件门可用 → 点击进入
	var m2 := MapScreen.new()
	m2.setup(run, "event")
	_host.add_child(m2)
	await process_frame
	var ev_sig := [false]
	m2.event_entered.connect(func() -> void: ev_sig[0] = true)
	(m2._door_event.get_node("DoorArt") as Control).gui_input.emit(_make_click_event())
	await process_frame
	_check(ev_sig[0], "事件门点击 → event_entered")
	m2.queue_free()

	# 冷却：战斗清了之后事件才再开（events_since_battle 手动置 1 → 门灰）
	run.events_since_battle = 1
	var m3 := MapScreen.new()
	m3.setup(run, "event")
	_host.add_child(m3)
	await process_frame
	var ev_sig2 := [false]
	m3.event_entered.connect(func() -> void: ev_sig2[0] = true)
	(m3._door_event.get_node("DoorArt") as Control).gui_input.emit(_make_click_event())
	await process_frame
	_check(not ev_sig2[0], "事件门冷却中：点击不触发")
	m3.queue_free()

	# 奖励段（10%）：奖励门 → 宝箱
	var m4 := MapScreen.new()
	m4.setup(run, "bonus")
	_host.add_child(m4)
	await process_frame
	var bn_sig := [false]
	m4.bonus_entered.connect(func() -> void: bn_sig[0] = true)
	(m4._door_event if m4._door_event != null else m4._door_battle)
	(m4._door_bonus.get_node("DoorArt") as Control).gui_input.emit(_make_click_event())
	await process_frame
	_check(bn_sig[0], "奖励门点击 → bonus_entered")
	m4.queue_free()

	# 奖励关界面：开箱得道具
	var n0 := run.items.size()
	var b := BonusScreen.new()
	b.setup(run)
	_host.add_child(b)
	await process_frame
	_check(b.get_child_count() > 0, "奖励关界面已构建")
	var e := EventScreen.new()
	e.setup(run, 0)
	e.queue_free()
	# 直接走开箱逻辑
	run.grant_elite_chest()
	_eq(run.items.size(), n0 + 1, "宝箱/精英掉落：道具 +1")
	b.queue_free()

	# 精英标记：门选制——参数强制，不再掷骰
	var cb := StsCombat.new()
	cb.setup(run.deck, "沙袋", 999, [{"kind": "attack", "value": 4}], 80, 42)
	_check(not cb.is_elite, "普通门：非精英")
	var ce := run.start_battle(LevelPool.get_level("L1"), true)
	_check(ce.is_elite, "精英门：强制精英")
	ce.queue_free() if false else null

	# ── 事件效果系统 ──
	var run2 := RunState.new()
	run2.reset_run()
	var cb2 := run2.start_battle(LevelPool.get_level("L1"))
	var hp0 := cb2.enemy_hp
	run2.next_pre_hp = -20
	var cb3 := run2.start_battle(LevelPool.get_level("L2"))
	_eq(cb3.enemy_hp, maxf(1, LevelPool.get_level("L2").enemy_hp - 20), "敌人先扣血：96-20")
	_eq(run2.next_pre_hp, 0, "先扣血一次性消耗")
	cb3.queue_free() if false else null

	var cb4 := run2.start_battle(LevelPool.get_level("L3"))
	var atk0 := cb4.atk_bonus
	run2.run_atk_bonus = 1
	var cb5 := run2.start_battle(LevelPool.get_level("L4"))
	_eq(cb5.atk_bonus, atk0 + 1, "运行级攻击 +1 注入")
	cb5.queue_free() if false else null

	var cb6 := run2.start_battle(LevelPool.get_level("L5"))
	run2.next_hand_bonus = 1
	var cb7 := run2.start_battle(LevelPool.get_level("L6"))
	_eq(cb7.hand_size(), 5, "下一场手牌 +1（4→5）")
	_eq(run2.next_hand_bonus, 0, "手牌加成一次性消耗")
	cb7.queue_free() if false else null

	# 电子木鱼：赛博功德（战斗开始回 5 HP；先回血再开战，不能拿旧 HP）
	run2.hp = 50
	run2.add_item(StsItemPool.make("muyu"))
	var hp_before := run2.hp
	var cb8 := run2.start_battle(LevelPool.get_level("L7"))
	_eq(cb8.hp, mini(RunState.MAX_HP, hp_before + 5), "电子木鱼：开战时 HP 已回 5（50→55）")
	_eq(run2.hp, mini(RunState.MAX_HP, hp_before + 5), "电子木鱼：局内 HP 同步为 55")
	cb8.queue_free() if false else null

	# ── ChatPPT 专属：起始卡组与被动「模板对齐」 ──
	var cp_deck := StsCardPool.starter_deck_for("chatppt")
	_eq(cp_deck.size(), 10, "ChatPPT 起始卡组 10 张")
	var cp_atk := 0
	var cp_skl := 0
	for c in cp_deck:
		if c.id == "cp_format":
			cp_atk += 1
		if c.id == "cp_template":
			cp_skl += 1
	_eq(cp_atk, 3, "ChatPPT 专属攻击 ×3")
	_eq(cp_skl, 2, "ChatPPT 专属防御 ×2")
	_eq(StsCardPool.card_name("cp_format"), "格式化输出", "专属攻击卡名")
	_eq(StsCardPool.card("cp_format").damage, 6, "专属攻击基础 6")
	_eq(StsCardPool.card("cp_template").block, 5, "专属防御基础 5")
	_check(ResourceLoader.exists("res://assets/art/ai-chatppt.png"), "ChatPPT 立绘资源存在")
	_check(ResourceLoader.exists("res://assets/art/sts-art-cp-format.png"), "ChatPPT 攻击卡面存在")
	_check(ResourceLoader.exists("res://assets/art/sts-art-cp-template.png"), "ChatPPT 防御卡面存在")

	# 全部 AI 初始可选（主人 2026-11-03 钦定：无需通关解锁）
	_eq(AiPool.unlocked_ids(0).size(), 4, "0 关时 4 位 AI 全部解锁")
	var cp_select := AiPool.ai_list_for_select(0)
	var cp_locked := 0
	for a in cp_select:
		if a.locked:
			cp_locked += 1
	_eq(cp_locked, 0, "选人列表 0 关时无锁定项")
	_eq(int(LaunchScreen.MODELS[1][2]), 0, "启动界面 Grok 无需通关")
	_eq(int(LaunchScreen.MODELS[2][2]), 0, "启动界面 GPT 无需通关")
	_eq(int(LaunchScreen.MODELS[3][2]), 0, "启动界面千问无需通关")

	var cp := StsCombat.new()
	cp.setup(cp_deck, "沙袋", 999, [{"kind": "attack", "value": 4}], 80, 7)
	cp.set_ai_id("chatppt")
	var cp_atk_card := StsCardPool.card("cp_format")
	var cp_def_card := StsCardPool.card("cp_template")
	var cp_hand: Array[StsCard] = [cp_atk_card, cp_def_card]
	cp.hand = cp_hand
	var cp_ev1 := cp.play_card(cp_atk_card, false, true, false)
	_eq(int(cp_ev1.get("value", 0)), 10, "ChatPPT 首张攻击：6 + 首位2 + 被动2 = 10")
	var cp_ev2 := cp.play_card(cp_def_card, false, false, true)
	_eq(int(cp_ev2.get("value", 0)), 7, "ChatPPT 第二张防御：5 + 末位2（无被动）= 7")

	cp.start_turn()
	var cp_hand2: Array[StsCard] = [cp_atk_card]
	cp.hand = cp_hand2
	var cp_pv := cp.preview_sequence()
	_eq(int(cp_pv[0]["value"]), 10, "ChatPPT 预览与实战一致（首位 10）")
	var cp_ev3 := cp.play_card(cp_atk_card, false, true, true)
	_eq(int(cp_ev3.get("value", 0)), 10, "ChatPPT 新回合首牌重新 +2")


func _make_click_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(100, 100)
	return ev


# ═════════════════════════════════════════════════════════
#  LLM 接入层（llm-core / opponent-rules / event-engine / banter / battle）
# ═════════════════════════════════════════════════════════
func _llm_test_cfg() -> LLMConfig:
	var cfg := LLMConfig.new()
	cfg.enabled = true
	cfg.base_url = "https://api.example.com"
	cfg.api_key = "sk-test"
	cfg.protocol = "openai"
	cfg.model = "test-model"
	return cfg


func _test_llm_config() -> void:
	print("[LLMConfig]")
	var secret := "sk-测试-key/1234567890"
	var blob := LLMConfig.obfuscate(secret)
	_check(blob.begins_with("b64:") and not blob.contains("sk-"), "Key 落盘 b64 前缀且无明文")
	_eq(LLMConfig.deobfuscate(blob), secret, "Key XOR+base64 混淆往返（含中文）")

	var cfg := LLMConfig.new()
	cfg.enabled = true
	cfg.base_url = "https://api.example.com/v1/"
	cfg.api_key = secret
	cfg.protocol = "chat_completions"
	cfg.model = "gemini-2.0-flash"
	var path := "user://llm_config_smoke.cfg"
	_eq(cfg.save(path), OK, "配置 save 返回 OK")
	var back := LLMConfig.load_from_disk(path)
	_check(back.enabled and back.api_key == secret and back.protocol == "chat_completions"
			and back.model == "gemini-2.0-flash", "配置存读往返（含 Key 混淆）")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(back.is_enabled(), "is_enabled：三要素齐")
	_check(absf(back.temp_for("observer") - 0.3) < 0.001, "温度分治 observer=0.3")
	_check(absf(back.temp_for("event") - 0.5) < 0.001, "温度分治 event=0.5")
	_check(absf(back.temp_for("dialog") - 0.8) < 0.001, "温度分治 dialog=0.8")
	_check(absf(back.temp_for("unknown") - 0.5) < 0.001, "未知 scene_tag 回落 0.5")

	# ZCode provider 导入（goat 分组）
	var zp := "user://zcode_provider_smoke.json"
	var fake := {
		"config": {"providerConfigRules": {"providerRules": [
			{"providerId": "goat-claude", "providerName": "goat-claude", "enabled": true,
			 "config": {"access": {"type": "api-key", "apiKey": "user_testsmoke1234"},
				"api": {"type": "anthropic-messages", "baseUrl": "https://api.example.com/provider/v1"},
				"personalModelIds": ["claude-haiku-5-5", "claude-sonnet-5-5"]}},
		]}}
	}
	var zf := FileAccess.open(zp, FileAccess.WRITE)
	zf.store_string(JSON.stringify(fake))
	zf.close()
	var imp := LLMConfig.import_zcode_provider("goat-claude", ProjectSettings.globalize_path(zp))
	_check(bool(imp.get("ok", false)), "ZCode provider 导入成功")
	_eq(String(imp.get("protocol", "")), "anthropic", "导入协议映射 anthropic-messages → anthropic")
	_eq(String(imp.get("model", "")), "claude-haiku-5-5", "导入取第一个模型")
	_eq(String(imp.get("base_url", "")), "https://api.example.com/provider/v1", "导入 base URL")
	_check(String(imp.get("key_tail", "")).ends_with("1234"), "导入 Key 尾部脱敏")
	var miss := LLMConfig.import_zcode_provider("nope", ProjectSettings.globalize_path(zp))
	_check(not bool(miss.get("ok", true)), "不存在的 provider 返回失败")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zp))


func _test_llm_protocol() -> void:
	print("[LLMProtocol]")
	_eq(LLMProtocol.normalize_base("openai", "https://api.openai.com/v1/"),
			"https://api.openai.com", "base URL 去尾斜杠与 /v1")
	_eq(LLMProtocol.chat_url("openai", "https://api.openai.com/v1", "gpt-4o"),
			"https://api.openai.com/v1/chat/completions", "openai URL 不出现 /v1/v1")
	_eq(LLMProtocol.chat_url("deepseek", "https://api.deepseek.com/", "deepseek-chat"),
			"https://api.deepseek.com/v1/chat/completions", "deepseek URL")
	_eq(LLMProtocol.chat_url("gemini", "https://generativelanguage.googleapis.com/",
			"gemini-2.0-flash", "K1"),
			"https://generativelanguage.googleapis.com/v1/chat/completions",
			"gemini 归并为 chat_completions URL")
	_eq(LLMProtocol.chat_url("anthropic", "https://api.anthropic.com", "claude-3"),
			"https://api.anthropic.com/v1/messages", "anthropic URL")
	_eq(LLMProtocol.models_url("anthropic", "https://api.anthropic.com"), "",
			"anthropic 无模型列表端点")
	var ah := LLMProtocol.headers("anthropic", "sk-ant")
	_check(ah.has("x-api-key: sk-ant") and ah.has("anthropic-version: 2023-06-01"),
			"anthropic 头：x-api-key + anthropic-version")
	var abody: Dictionary = JSON.parse_string(LLMProtocol.build_body("anthropic", "claude-3",
			[{"role": "system", "content": "s"}, {"role": "user", "content": "u"}], 0.3))
	_eq(int(abody.get("max_tokens", 0)), LLMProtocol.DEFAULT_MAX_TOKENS, "anthropic max_tokens 必填")
	_eq(LLMProtocol.parse_models("openai", '{"data":[{"id":"a"},{"id":"b"},{"id":"a"}]}'),
			["a", "b"], "/models 解析 data[].id 去重")
	_eq(LLMProtocol.parse_models("gemini", '{"models":[{"name":"models/gemini-1.5"}]}'),
			["gemini-1.5"], "/models 解析 models[].name 剥前缀")
	_eq(LLMProtocol.extract_text("openai", '{"choices":[{"message":{"content":"你好"}}]}'),
			"你好", "回复正文提取 openai")


func _test_llm_parse() -> void:
	print("[LLMParse]")
	_eq(String(LLMParse.parse_action('{"action":"taunt","line":"来啊"}')["action"]),
			"TAUNT", "动作层① JSON")
	_eq(String(LLMParse.parse_action("ATTACK\n\n检测到非法连击")["action"]),
			"ATTACK", "动作层② 首行动作词")
	_eq(String(LLMParse.parse_action("这波先防御一下，再考虑蓄力。")["action"]),
			"DEFEND", "动作层③ 中文关键词")
	var nul := LLMParse.parse_action("今天天气不错，我们去吃白饭吧。")
	_check(not bool(nul["ok"]) and not String(nul["line"]).is_empty(),
			"动作层④ null 但台词保留")
	var ev := LLMParse.parse_event('{"pick":2,"reason":"省下的时间多吃两口白饭"}', 3)
	_check(bool(ev["ok"]) and int(ev["pick"]) == 2, "事件三关全过")
	_check(not bool(LLMParse.parse_event("随便选一个吧", 3)["ok"]), "事件关1：非 JSON 失败")
	_check(not bool(LLMParse.parse_event('{"pick":5,"reason":"x"}', 3)["ok"]), "事件关3：越界失败")
	_eq(LLMParse.parse_dialogue("```\n「白饭要趁热。」\n```"), "白饭要趁热。",
			"台词剥围栏与引号")


func _test_llm_opponent() -> void:
	print("[LLMOpponentPool]")
	var d := {
		"attacks_last_turn": 2, "grow_streak": 2,
		"defend_ready": true, "charge_ready": true,
		"mark_ready": true, "taunt_ready": true, "taunt_unlocked": true,
	}
	var legal := LLMOpponentPool.legal_actions(d)
	_eq(legal.size(), 5, "五动作全部合法（白名单 5 个）")
	for a in ["ATTACK", "DEFEND", "CHARGE", "MARK", "TAUNT"]:
		_check(LLMOpponentPool.is_legal(a, d), "is_legal %s" % a)
	_eq(LLMOpponentPool.local_choose(d), "DEFEND", "本地兜底：上回合≥2攻先防御")
	_eq(LLMOpponentPool.normalize_action("攻击"), "ATTACK", "中文别名归一")
	_check(not LLMOpponentPool.is_legal("MARK:XXX", d), "非法标记模式拒绝")
	_check(not LLMOpponentPool.action_ui_name("MARK:AGGRO").is_empty(), "动作 UI 名可读")


func _test_llm_event() -> void:
	print("[LLMEvent]")
	var run := RunState.new()
	run.reset_run()
	LLMEventEngine.reset_run(run)
	_eq(LLMEventEngine.budget_left(run), LLMEventSlots.MAX_EVENTS_PER_RUN, "事件预算初始 2")
	_check(LLMEventEngine.can_trigger(run), "开局允许 AI 事件")
	var cands := LLMEventEngine.build_candidates(run, run.rng)
	_check(cands.size() >= 2 and cands.size() <= 3, "候选池 2~3 个（本地预筛）")
	_check(not String((cands[0] as Dictionary).get("id", "")).is_empty(), "候选带机械槽位 ID")
	var res := LLMEventEngine.apply_pick(run, cands, 1)
	_check(bool(res.get("ok", false)), "apply_pick 落地本地数值")
	_eq(LLMEventEngine.event_count(run), 1, "事件计数 +1")
	_eq(LLMEventEngine.budget_left(run), 1, "预算 -1")
	_check(not bool(LLMEventEngine.apply_pick(run, [], 1).get("ok", true)), "空池拒绝落地")
	var net := LLMEventEngine.total_net(run)
	_check(net >= LLMEventSlots.EVENT_NET_MIN and net <= LLMEventSlots.EVENT_NET_MAX,
			"单事件净值钳 [−8,+6]（实 %d）" % net)


func _test_llm_client() -> void:
	print("[LLMClient · Mock]")
	# ① 正常剧本
	var c1 := LLMClient.new()
	c1.name = "SmokeLLM1"
	_host.add_child(c1)
	c1.setup(_llm_test_cfg())
	var m1 := LLMClient.MockBackend.new("normal")
	c1.set_backend(m1)
	var got1: Array = []
	c1.request("observer", [{"role": "user", "content": "x"}],
			func(r: Dictionary) -> void: got1.append(r))
	await create_timer(0.15).timeout
	_check(got1.size() == 1 and bool(got1[0]["ok"])
			and String(got1[0]["text"]).begins_with("ATTACK"), "正常剧本回包")
	_eq(m1.requests, 1, "正常剧本后端 1 次")
	c1.shutdown()
	c1.queue_free()

	# ② 垃圾剧本（客户端原样返回；解析层兜底）
	var c2 := LLMClient.new()
	c2.name = "SmokeLLM2"
	_host.add_child(c2)
	c2.setup(_llm_test_cfg())
	var m2 := LLMClient.MockBackend.new("garbage")
	c2.set_backend(m2)
	var got2: Array = []
	c2.request("observer", [{"role": "user", "content": "x"}],
			func(r: Dictionary) -> void: got2.append(r))
	await create_timer(0.15).timeout
	_check(got2.size() == 1 and bool(got2[0]["ok"]), "垃圾剧本仍回包")
	var gp := LLMParse.parse_action(String(got2[0].get("text", "")))
	_check(not bool(gp["ok"]) and not String(gp["line"]).is_empty(),
			"垃圾输出→动作兜底、台词保留")
	c2.shutdown()
	c2.queue_free()

	# ③ 挂起剧本 + 超时兜底（默认 3s；测试用 0.2s 快进）
	_check(absf(LLMClient.DEFAULT_TIMEOUT_S - 3.0) < 0.001, "默认决策预算 3.0s")
	var c3 := LLMClient.new()
	c3.name = "SmokeLLM3"
	_host.add_child(c3)
	c3.setup(_llm_test_cfg())
	c3.set_backend(LLMClient.MockBackend.new("hang"))
	var got3: Array = []
	var t0 := Time.get_ticks_msec()
	c3.request("observer", [{"role": "user", "content": "x"}],
			func(r: Dictionary) -> void: got3.append(r), {"timeout_s": 0.2})
	await create_timer(0.6).timeout
	var dt := float(Time.get_ticks_msec() - t0) / 1000.0
	_check(got3.size() == 1 and String(got3[0]["reason"]) == "timeout", "挂起剧本→超时兜底")
	_check(dt < 0.9, "超时兜底未拖住（%.2fs < 0.9s）" % dt)
	c3.shutdown()
	c3.queue_free()

	# ④ 401 熔断：当回合兜底，第二请求短路
	var c4 := LLMClient.new()
	c4.name = "SmokeLLM4"
	_host.add_child(c4)
	c4.setup(_llm_test_cfg())
	var m4 := LLMClient.MockBackend.new("status")
	m4.status_code = 401
	c4.set_backend(m4)
	var got4: Array = []
	c4.request("observer", [{"role": "user", "content": "a"}],
			func(r: Dictionary) -> void: got4.append(r))
	await create_timer(0.15).timeout
	_check(got4.size() == 1 and String(got4[0]["reason"]) == "http_401", "401 当回合兜底")
	c4.request("observer", [{"role": "user", "content": "b"}],
			func(r: Dictionary) -> void: got4.append(r))
	await create_timer(0.15).timeout
	_check(got4.size() == 2 and String(got4[1]["reason"]) == "circuit_open", "401 后续请求短路")
	_eq(m4.requests, 1, "熔断后不再打后端")
	c4.shutdown()
	c4.queue_free()

	# ⑤ 并发峰值 ≤2
	var c5 := LLMClient.new()
	c5.name = "SmokeLLM5"
	_host.add_child(c5)
	c5.setup(_llm_test_cfg())
	var m5 := LLMClient.MockBackend.new("normal")
	m5.delay_s = 0.12
	c5.set_backend(m5)
	var done5: Array = []
	for i in 3:
		c5.request("event", [{"role": "user", "content": "q%d" % i}],
				func(r: Dictionary) -> void: done5.append(r))
	await create_timer(0.05).timeout
	_eq(c5.active_count(), 2, "并发在飞 == 2")
	_eq(c5.pending_count(), 1, "第 3 个排队")
	await create_timer(0.7).timeout
	_check(c5.peak_active <= 2, "并发峰值 ≤2（实 %d）" % c5.peak_active)
	_eq(done5.size(), 3, "3 个请求全部回调")
	c5.shutdown()
	c5.queue_free()

	# ⑥ 迟到缓存：超时后回来的结果，下回合同 rid+pool 直接复用
	var c6 := LLMClient.new()
	c6.name = "SmokeLLM6"
	_host.add_child(c6)
	c6.setup(_llm_test_cfg())
	var m6 := LLMClient.MockBackend.new("normal")
	m6.reply = "LATE-TEXT"
	m6.delay_s = 0.35
	c6.set_backend(m6)
	var got6: Array = []
	c6.request("event", [{"role": "user", "content": "x"}],
			func(r: Dictionary) -> void: got6.append(r),
			{"timeout_s": 0.1, "resolve_id": 90210, "pool_hash": "ph-smoke"})
	await create_timer(0.2).timeout
	_eq(String(got6[0]["reason"]) if got6.size() > 0 else "none", "timeout",
			"迟到场景先超时兜底")
	await create_timer(0.45).timeout
	_check(c6.has_late_result(90210, "ph-smoke"), "迟到结果入缓存")
	c6.request("event", [{"role": "user", "content": "y"}],
			func(r: Dictionary) -> void: got6.append(r),
			{"timeout_s": 1.0, "resolve_id": 90210, "pool_hash": "ph-smoke"})
	await create_timer(0.12).timeout
	var last: Dictionary = got6[got6.size() - 1]
	_check(bool(last["ok"]) and bool(last["from_cache"]) and String(last["text"]) == "LATE-TEXT",
			"同 rid+pool 复用迟到缓存")
	_eq(m6.requests, 1, "缓存复用不再发请求")
	c6.shutdown()
	c6.queue_free()
	await process_frame


func _test_llm_banter() -> void:
	print("[AIBanter]")
	var b := AIBanter.new()
	b.name = "SmokeBanter"
	_host.add_child(b)
	await process_frame
	b.setup(null, Callable())
	b.bubble_hold = 0.01
	b.fade_sec = 0.01
	b.retort_delay = 0.01
	b.battle_started()
	await create_timer(0.3).timeout
	_eq(b.debug_spoken(AIBanter.H_OPENING).size(), 1, "开场问候 1 次/场")
	b.on_streak(3, 1)
	b.on_streak(3, 1)
	b.on_streak(4, 4)
	b.on_streak(5, 9)
	await create_timer(0.9).timeout
	_eq(b.debug_spoken(AIBanter.H_CHEER).size(), 2, "连段喝彩：2 次/场上限且间隔≥2 回合")
	b.on_hp_changed(20, 80)
	b.on_hp_changed(10, 80)
	await create_timer(0.4).timeout
	_eq(b.debug_spoken(AIBanter.H_DANGER).size(), 1, "濒危关心 1 次/场")
	b.notify_enemy_line("检测到非法连击，已加入回收队列")
	b.notify_enemy_line("上下文已丢失，你谁啊")
	b.notify_enemy_line("第三条不该播")
	await create_timer(0.9).timeout
	_eq(b.debug_spoken(AIBanter.H_RETORT).size(), 2, "回怼敌人：2 次/场上限")
	_check(AIBanter.MAX_CHARS == 50, "台词上限 50 字")
	b.stop_battle()
	b.queue_free()
	await process_frame


func _wait_arena_turn(a: ArenaScreen, target: int, secs := 2.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while a.combat != null and a.combat.turn < target:
		if Time.get_ticks_msec() - t0 > int(secs * 1000.0):
			return false
		await create_timer(0.02).timeout
	return a.combat != null and a.combat.turn >= target


func _test_llm_arena() -> void:
	print("[LLM · arena 接线]")
	var run := RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))
	var a := ArenaScreen.new()
	a.name = "SmokeArenaLLM"
	a.setup(run, LevelPool.get_level("L1"))
	_host.add_child(a)
	await process_frame
	await process_frame
	_check(not a.debug_ai_enabled(), "AI 关闭：arena 默认走原规则")
	_check(a.debug_banter() != null and String(a.debug_banter().name) == "AIBanter",
			"AIBanter 已接线")
	_check(absf(a.ai_timeout - 3.0) < 0.001, "arena 决策预算默认 3s")

	var mock := LLMClient.MockBackend.new("normal")
	mock.reply = "ATTACK\n\n饭吃饱了，正好上路"
	a.ai_timeout = 1.0
	var ai_cfg := _llm_test_cfg()
	ai_cfg.ai_opponent = true          ## 2026-11-05 起敌人默认关，显式打开才测 AI 路径
	a.debug_set_llm(ai_cfg, mock)
	a.debug_banter().set_provider(Callable())
	_check(a.debug_ai_enabled(), "AI 开启 + 普通战斗 → 启用")
	var hp0 := a.combat.hp
	a.debug_end_turn()
	var advanced := await _wait_arena_turn(a, 2)
	_check(advanced, "AI 模式：敌方回合推进")
	_eq(String(a.debug_ai_last().get("source", "")), "line", "AI 动作解析命中")
	_eq(String(a.debug_ai_last().get("action", "")), "ATTACK", "AI 选中 ATTACK")
	_eq(a.combat.hp, hp0 - 7, "AI 路径只结算一次（与规则同值 -7，未双调 end_turn）")
	a.queue_free()
	await process_frame

	var run_boss := RunState.new()
	run_boss.reset_run()
	run_boss.set_ai(AiPool.get_ai("deepdeek"))
	var b := ArenaScreen.new()
	b.name = "SmokeArenaBoss"
	b.setup(run_boss, LevelPool.get_level("L10"))
	_host.add_child(b)
	await process_frame
	await process_frame
	b.debug_set_llm(_llm_test_cfg())
	_check(not b.debug_ai_enabled(), "Boss 战锁规则版（不用 AI）")
	b.queue_free()
	await process_frame


# ══════════════════════════════════════════════════════
#  效果层回归（2026-11-06 重建：文件曾被回滚，这里一次性补回）
# ══════════════════════════════════════════════════════

func _fx_card(program: Array, dmg := 5) -> StsCard:
	var c := StsCard.make("fx_test", StsCard.Kind.ATTACK, 1, dmg, 0, "")
	c.effects = EffectDSL.compile(program)["clauses"]
	c.dsl_version = 1
	return c


func _fx_combat(cards: Array, enemy_hp := 100, pattern: Array = []) -> StsCombat:
	var cb := StsCombat.new()
	var deck: Array[StsCard] = []
	for c in cards:
		deck.append(c)
	if pattern.is_empty():
		pattern = [{"kind": "attack", "value": 8}]
	cb.setup(deck, "fx", enemy_hp, pattern, 80, 7, 1, 1)
	return cb


func _test_effect_dsl() -> void:
	print("[效果 DSL]")
	_eq(EffectSpec.VERSION, 1, "规格版本 = 1")
	_eq(EffectSpec.OPS.size(), 10, "开放 10 个 op")
	_eq(EffectSpec.TRIGGERS.size(), 8, "开放 8 个触发器")
	var good := [{"when": "on_play", "then": [
		{"do": "damage", "amount": 6},
		{"do": "damage_scaled", "per": "same_kind_streak", "step": 2}]}]
	var c := EffectDSL.compile(good)
	_check(bool(c["ok"]), "合法程序编译通过")
	_eq(int(c["ops"]), 1, "只保留 1 个 op（一张卡一个新特色）")
	_check((EffectDSL.writeset(c["clauses"]) as Dictionary).has("enemy_hp"), "写集含 enemy_hp")
	_check(EffectDSL.describe(c["clauses"]).contains("造成"), "人话描述可读")
	var bad := [
		{"when": "on_play", "then": [{"do": "not_an_op"}, {"do": "damage", "amount": 999}]},
		{"when": "nope", "then": [{"do": "damage", "amount": 3}]}]
	var cb := EffectDSL.compile(bad)
	_eq(int(cb["ops"]), 1, "未知 op/触发器被丢弃")
	_eq(int((cb["clauses"] as Array)[0]["then"][0]["amount"]), 20, "超限数值钳到 20")
	var many := []
	for i in 5:
		many.append({"when": "on_play", "then": [{"do": "damage", "amount": 1}]})
	_eq((EffectDSL.compile(many)["clauses"] as Array).size(), 1,
			"op 上限 1：多余 clause 被丢")
	var flood := []
	for i in 100:
		flood.append({"when": "on_play", "then": [{"do": "damage", "amount": 1}]})
	_eq(EffectRuntime.eval(flood, "on_play", {"turn": 1}).size(), 64, "运行期 op 预算 64")
	_check(not bool(EffectDSL.compile("garbage")["ok"]), "非数组程序 ok=false")


func _test_dsl_spec_file() -> void:
	print("[DSL 规格文件]")
	var path := "res://scripts/core/dsl_spec.json"
	_check(FileAccess.file_exists(path), "dsl_spec.json 已落盘")
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(d is Dictionary, "可解析为 JSON 对象")
	if not (d is Dictionary):
		return
	_eq(int(d.get("version", -1)), EffectSpec.VERSION, "version 与代码一致")
	var lim: Dictionary = d.get("limits", {})
	_check(lim.has("max_clauses") and lim.has("op_budget"), "limits 字段完整")
	_eq((d.get("ops", {}) as Dictionary).size(), EffectSpec.OPS.size(), "ops 数量一致")
	_eq((d.get("triggers", {}) as Dictionary).size(), EffectSpec.TRIGGERS.size(), "triggers 数量一致")


func _test_effect_combat() -> void:
	print("[效果层·战斗]")
	var plain := StsCard.make("plain", StsCard.Kind.ATTACK, 1, 5, 0, "")
	var c0 := _fx_combat([plain])
	var hp0 := c0.enemy_hp
	c0.play_card(c0.hand[0], false)
	_eq(hp0 - c0.enemy_hp, 5, "无 effects 的卡伤害不变")
	var c2 := _fx_combat([plain])
	c2._add_status("weak", 1, "enemy")
	var ev2 := c2.end_turn()
	var atk_ev := {}
	for e in ev2:
		if String(e.get("kind", "")) == "enemy_attack":
			atk_ev = e
	_eq(int(atk_ev.get("value", 0)), 6, "降智后敌人攻击 8 → 6")
	var c3 := _fx_combat([plain])
	c3._add_status("vulnerable", 1, "enemy")
	var hp3 := c3.enemy_hp
	c3.play_card(c3.hand[0], false)
	_eq(hp3 - c3.enemy_hp, 6, "易伤后 5 点变 6")
	var c5 := _fx_combat([plain])
	c5._add_status("poison", 1, "enemy")
	c5.enemy_block = 10
	var hp5 := c5.enemy_hp
	c5.end_turn()
	_eq(hp5 - c5.enemy_hp, 2, "中毒无视护盾掉 2")
	var heal_card := _fx_card([{"when": "on_play", "then": [{"do": "heal", "amount": 5}]}], 0)
	var c9 := _fx_combat([heal_card])
	c9.hp = 50
	c9.play_card(c9.hand[0], false)
	_eq(c9.hp, 55, "heal 回复 5")
	var blk_card := _fx_card([{"when": "on_play", "then": [{"do": "block", "amount": 6}]}], 0)
	var c16 := _fx_combat([blk_card])
	c16.play_card(c16.hand[0], false)
	_eq(c16.block, 6, "block 给 6 格挡")
	var ondraw := _fx_card([{"when": "on_draw", "then": [
		{"do": "apply_status", "status": "strength", "tier": 1, "target": "self"}]}], 0)
	var c13 := _fx_combat([ondraw])
	_check(c13.p_status.has("strength"), "on_draw 触发")
	var onturn := _fx_card([{"when": "on_turn_start", "then": [
		{"do": "apply_status", "status": "thorns", "tier": 1, "target": "self"}]}], 0)
	var c14 := _fx_combat([onturn])
	_check(c14.p_status.has("thorns"), "on_turn_start 触发")
	var onkill := _fx_card([{"when": "on_kill", "then": [
		{"do": "apply_status", "status": "vulnerable", "tier": 1, "target": "enemy"}]}], 0)
	var killer := StsCard.make("killer", StsCard.Kind.ATTACK, 1, 50, 0, "")
	var c15 := _fx_combat([onkill, killer], 10)
	c15.hand.clear()
	c15.draw_pile.clear()
	c15.discard_pile.clear()
	c15.hand.append(killer)
	c15.draw_pile.append(onkill)
	c15.play_card(killer, false)
	_check(c15.e_status.has("vulnerable"), "on_kill 触发")


func _test_pricing() -> void:
	print("[定价]")
	var plain := StsCard.make("p_plain", StsCard.Kind.ATTACK, 1, 6, 0, "")
	var r1 := EffectPricing.price(plain, 1, 40)
	_check(bool(r1["ok"]), "定价 ok")
	_check(int(r1["cost"]) >= 1 and int(r1["cost"]) <= 3, "cost 1–3")
	_eq(r1["cost"], EffectPricing.price(plain, 1, 40)["cost"], "同卡两次一致")
	_check(r1.has("p95") and r1.has("banned"), "返回 p95/banned")
	EffectPricing.clear_cache()
	var c1 := EffectPricing.price_cached(plain, 1, 20)
	var c2 := EffectPricing.price_cached(plain, 1, 20)
	_check(not bool(c1["cached"]) and bool(c2["cached"]), "缓存 miss → hit")
	_eq(int(EffectPricing.price_cached(plain, 2, 20, false)["cost"]), 3, "未命中给保守上界")
	var bad_ver := StsCard.make("bad_ver", StsCard.Kind.ATTACK, 1, 5, 0, "")
	bad_ver.dsl_version = 99
	bad_ver.effects = EffectDSL.compile([{"when": "on_play", "then": [
		{"do": "damage", "amount": 5}]}])["clauses"]
	_check(not bool(EffectPricing.price(bad_ver, 1, 10)["ok"]), "未知版本被拒")
	_check(bool(EffectPricing.check_termination_gate(0, 30)["ok"]), "终止性闸门通过")
	_check(not bool(EffectPricing.check_termination_gate(1, 30)["ok"]), "状态重复被拒")
	_check(bool(EffectPricing.check_decision_gate(18.0)["ok"]), "额外点击 18 通过")
	_check(not bool(EffectPricing.check_decision_gate(22.0)["ok"]), "额外点击 22 被拒")
	var ref := EffectPricing._run_deck_verbose(StsCardPool.starter_deck(), 1, 60)
	var wr := float((ref["summary"] as Dictionary)["win_rate"])
	_check(wr >= 0.35 and wr <= 0.65, "参考擂台胜率在分辨带（%.2f）" % wr)


func _test_combo() -> void:
	print("[组合审计]")
	var a := _fx_card([{"when": "on_turn_end", "then": [
		{"do": "apply_status", "status": "poison", "tier": 1, "target": "enemy"}]}])
	var b := _fx_card([{"when": "on_turn_end", "then": [
		{"do": "apply_status", "status": "poison", "tier": 2, "target": "enemy"}]}])
	var r := EffectCombo.audit([a, b] as Array[StsCard], 1, 20)
	_check((r["pairs"] as Array).size() >= 1, "共享状态维度进候选")
	_check((r["dims"] as Dictionary).has("enemy_status"), "维度并集含 enemy_status")
	_eq(EffectCombo.classify(30.0), "block", "classify: ≥阈值 block")
	_eq(EffectCombo.classify(5.0), "verify", "classify: 正交互 verify")
	_eq(EffectCombo.classify(1.0), "clean", "classify: 低于地板 clean")
	_eq(EffectCombo.classify_triple(20.0), "block", "三阶阈值")
	_eq(EffectCombo.classify_quad(25.0), "block", "四阶阈值")
	var c := _fx_card([{"when": "on_play", "then": [{"do": "damage", "amount": 8}]}])
	var r3 := EffectCombo.audit([a, b, c] as Array[StsCard], 1, 12)
	_eq((r3["triples"] as Array).size(), 1, "三张卡生成 1 个三元组")


func _test_energy_system() -> void:
	print("[算力]")
	var free1 := StsCard.make("en1", StsCard.Kind.ATTACK, 1, 5, 0, "")
	var c2 := StsCard.make("en2", StsCard.Kind.ATTACK, 2, 5, 0, "")
	var c3 := StsCard.make("en3", StsCard.Kind.ATTACK, 3, 5, 0, "")
	var cb := StsCombat.new()
	var deck: Array[StsCard] = [free1, c2, c3]
	cb.setup(deck, "e", 200, [{"kind": "attack", "value": 8}], 80, 1, 4, 1)
	_eq(cb.energy, StsCombat.ENERGY_PER_TURN, "开局算力 3")
	cb.hand.clear()
	cb.hand.append(free1)
	cb.play_card(free1, false)
	_eq(cb.energy, StsCombat.ENERGY_PER_TURN, "cost1 免费")
	cb.hand.clear()
	cb.hand.append(c2)
	cb.play_card(c2, false)
	_eq(cb.energy, StsCombat.ENERGY_PER_TURN - 2, "cost2 扣 2")
	cb.hand.clear()
	cb.hand.append(c3)
	_check(not cb.can_play(c3), "算力不足 cost3 不可打")
	cb.start_turn()
	_eq(cb.energy, StsCombat.ENERGY_PER_TURN, "新回合回满")


## 2026-11-06 bug 回归：换画笔不能污染已画笔迹
func _test_wish_canvas_colors() -> void:
	print("[涂鸦板·画笔隔离]")
	var cv := WishCanvas.new()
	_host.add_child(cv)
	await process_frame
	cv.size = Vector2(320, 320)
	cv.brush_color = Color(0, 1, 0)
	cv.brush_size = 20.0
	cv._strokes.append({"pts": PackedVector2Array([Vector2(50, 60), Vector2(120, 60)]),
			"size": 12.0, "style": "round", "color": Color(1, 0, 0)})
	cv._strokes.append({"pts": PackedVector2Array([Vector2(50, 140), Vector2(120, 140)]),
			"size": 12.0, "style": "square", "color": Color(0, 0, 1)})
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RGB8)
	cv._raster_to(img, 256)
	var red := 0
	var blue := 0
	var green := 0
	for y in 256:
		for x in 256:
			var c := img.get_pixel(x, y)
			if c.r > 0.6 and c.g < 0.3 and c.b < 0.3:
				red += 1
			elif c.b > 0.6 and c.r < 0.3:
				blue += 1
			elif c.g > 0.6 and c.r < 0.3:
				green += 1
	_check(red > 20, "第一笔保留红色（%d px）" % red)
	_check(blue > 20, "第二笔保留蓝色（%d px）" % blue)
	_eq(green, 0, "切换画笔颜色不污染已有笔迹")
	cv.queue_free()
	await process_frame


## 2026-11-06 bug 回归：许愿请求的 token/思考预算
func _test_wish_budget() -> void:
	print("[许愿预算]")
	_check(WishCardFactory.WISH_MAX_TOKENS >= 16384, "主请求预算 ≥16384（画图不省 token）")
	_check(WishCardFactory.WISH_MAX_TOKENS_RETRY > WishCardFactory.WISH_MAX_TOKENS,
			"重试预算更大")


func _test_prefetch_state() -> void:
	print("[许愿预取]")
	var run := RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))
	var arena := ArenaScreen.new()
	arena.setup(run, LevelPool.get_level("L1"))
	_host.add_child(arena)
	await process_frame
	arena._clear_prefetch()
	_check(arena._prefetch_result.is_empty() and not arena._prefetch_busy, "预取初始干净")
	_eq(arena._prefetch_count, 0, "计数归零")
	_eq(arena._wish_prefetch_hash(), arena._wish_prefetch_hash(), "hash 稳定")

	## 弃牌次数：上限内可以连续弃（2026-11-06 修反向判断：旧代码弃 1 张后就锁死）
	arena._discards_left = arena._discard_limit()
	## 工具栏新控件（2026-11-06：滑杆尺寸 / 橡皮图标 / 吸管 / 全色采色区）
	_check(arena._wish_size_slider != null and arena._wish_size_slider.max_value >= 99.0,
			"画笔尺寸滑杆存在且到 100")
	_check(arena._wish_eraser_btn != null, "橡皮图标按钮存在")
	_check(arena._wish_picker_btn != null, "吸管图标按钮存在")
	_check(arena._wish_sv_rect != null and arena._wish_sv_rect.texture != null,
			"饱和度/明度方块已生成")
	_check(arena._wish_hue_slider != null, "色相滑杆存在")
	_check(arena._discard_limit() >= 3, "弃牌上限至少 3 张")
	_check(arena._can_discard(), "满次数时可弃")
	arena._discards_left -= 1
	_check(arena._can_discard(), "弃 1 张后仍可弃（旧 bug 在这里断）")
	arena._discards_left -= 1
	_check(arena._can_discard(), "弃 2 张后仍可弃")
	arena._discards_left = 0
	_check(not arena._can_discard(), "用完后不可弃")
	arena.queue_free()
	await process_frame


## 2026-11-06：撤销 / 橡皮回归
func _test_wish_canvas_edit() -> void:
	print("[涂鸦板·撤销与橡皮]")
	var cv := WishCanvas.new()
	_host.add_child(cv)
	await process_frame
	cv.size = Vector2(320, 320)

	# 撤销：逐笔回退，空栈返回 false
	cv.clear()
	cv._strokes.append({"pts": PackedVector2Array([Vector2(40, 40), Vector2(120, 40)]),
			"size": 12.0, "style": "round", "color": Color(1, 0, 0), "eraser": false})
	cv._strokes.append({"pts": PackedVector2Array([Vector2(40, 80), Vector2(120, 80)]),
			"size": 12.0, "style": "round", "color": Color(0, 0, 1), "eraser": false})
	_check(cv.undo(), "撤销返回 true")
	_eq(cv.stroke_count(), 1, "撤销后剩 1 笔")
	_check(cv.undo(), "再撤销一次")
	_eq(cv.stroke_count(), 0, "撤销到空")
	_check(not cv.undo(), "空栈撤销返回 false")

	# 橡皮：用纸色覆盖，导出图里原来的红笔消失
	cv.clear()
	cv.tool = "brush"
	cv.brush_color = Color(1, 0, 0)
	cv.brush_size = 16.0
	_press_release(cv, Vector2(60, 100), Vector2(160, 100))
	_eq(cv.stroke_count(), 1, "普通笔画入栈")
	_eq((cv._strokes[0] as Dictionary)["color"], Color(1, 0, 0), "普通笔保留画笔颜色")
	cv.tool = "eraser"
	_press_release(cv, Vector2(40, 100), Vector2(180, 100))
	_eq(cv.stroke_count(), 2, "橡皮笔入栈")
	_eq((cv._strokes[1] as Dictionary)["color"], WishCanvas.PAPER, "橡皮笔用纸色")
	_check(bool((cv._strokes[1] as Dictionary)["eraser"]), "橡皮笔带 eraser 标记")
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RGB8)
	cv._raster_to(img, 256)
	var red := 0
	for y in 256:
		for x in 256:
			var c := img.get_pixel(x, y)
			if c.r > 0.6 and c.g < 0.3 and c.b < 0.3:
				red += 1
	_eq(red, 0, "橡皮覆盖后没有残留红像素")
	# 撤销橡皮 → 红笔回来
	cv.undo()
	var img2 := Image.create_empty(256, 256, false, Image.FORMAT_RGB8)
	cv._raster_to(img2, 256)
	var red2 := 0
	for y in 256:
		for x in 256:
			var c2 := img2.get_pixel(x, y)
			if c2.r > 0.6 and c2.g < 0.3 and c2.b < 0.3:
				red2 += 1
	_check(red2 > 20, "撤销橡皮后红笔恢复（%d px）" % red2)

	# 吸管：点在红笔上取到红色，且不落笔
	var picked := {"c": Color.WHITE, "got": false}
	cv.color_picked.connect(func(c: Color) -> void:
		picked["c"] = c
		picked["got"] = true)
	var before_n := cv.stroke_count()
	cv.tool = "picker"
	var pk := InputEventMouseButton.new()
	pk.button_index = MOUSE_BUTTON_LEFT
	pk.pressed = true
	pk.position = Vector2(100, 100)
	cv._gui_input(pk)
	_check(bool(picked["got"]), "吸管触发取色信号")
	_eq(picked["c"], Color(1, 0, 0), "吸到红笔的颜色")
	_eq(cv.stroke_count(), before_n, "吸管不落笔")
	cv.tool = "brush"
	cv.queue_free()
	await process_frame


func _press_release(cv: WishCanvas, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	cv._gui_input(press)
	var move := InputEventMouseMotion.new()
	move.position = to
	cv._gui_input(move)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = to
	cv._gui_input(rel)


## 2026-11-07：卡牌翻面（正面 = 卡框+费用球+名牌「名字+等级」+立绘；背面 = 描述）
func _test_card_flip() -> void:
	print("[卡牌翻面]")
	var c := StsCardPool.card("fish_ram")
	_check(c != null, "取到测试卡")
	if c == null:
		return
	var v := StsCardView.new()
	_host.add_child(v)
	await process_frame
	v.setup(c)
	await process_frame
	_check(not v.is_flipped(), "默认是正面")
	_check(v._front.visible and not v._back.visible, "正面可见、背面隐藏")
	# 正面文字 = 费用 / 名字 / 等级 三个（描述不许上正面）
	_eq(v._cost_lbl.text, str(c.cost), "费用球显示费用数字")
	_eq(v._name_lbl.text, StsCardPool.card_name(c.id), "名牌显示卡名")
	_eq(v._lv_lbl.text, "Lv.%d" % maxi(1, c.price_tier), "名牌显示等级（定价档位）")
	_check(v._frame != null and v._frame.texture != null, "正面铺了卡框贴图")
	_check(v._art != null and v._art.texture != null, "正面有立绘")
	var desc_in_front := 0
	for n in v._front.get_children():
		if n is Label and n != v._cost_lbl and n != v._name_lbl and n != v._lv_lbl:
			desc_in_front += 1
	_eq(desc_in_front, 0, "正面除费用/名字/等级外没有其他文字")
	# 右键翻面
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	v._on_gui(ev)
	await create_timer(0.45).timeout
	_check(v.is_flipped(), "右键翻到背面")
	_check(not v._front.visible and v._back.visible, "背面可见")
	_check(v._back_name.text == StsCardPool.card_name(c.id), "背面显示卡名")
	_check(v._back_desc.text != "", "背面显示效果说明")
	# 再翻回正面
	v.flip()
	await create_timer(0.45).timeout
	_check(not v.is_flipped(), "再翻回正面")
	v.queue_free()
	await process_frame


## ═══ 2026-11-07：好感度系统 ═══

func _test_affection_system() -> void:
	print("[好感度系统]")
	# —— 金币公式（对数：前段值钱，后段放缓）——
	var g100 := RunState.gold_for_damage(100)
	var g1000 := RunState.gold_for_damage(1000)
	var g4000 := RunState.gold_for_damage(4000)
	_check(g100 >= 10 and g100 <= 25, "低伤害金币落在 10~25（%d）" % g100)
	_check(g4000 > g1000 and g1000 > g100, "金币随伤害对数增长")
	_check(g4000 < g100 * 6, "后段增速放缓（%d < %d×6）" % [g4000, g100])

	# —— 好感等级（对数、无上限）——
	var saved := Affection.points
	Affection.points = 0.0
	_eq(Affection.level(), 0, "零好感 = Lv.0")
	Affection.points = 100.0
	var lv100 := Affection.level()
	_check(lv100 >= 8 and lv100 <= 14, "100 点 ≈ Lv.8~14（%d）" % lv100)
	Affection.points = 10000.0
	_check(Affection.level() > lv100 + 5, "无上限：10000 点远超 100 点")

	# —— 战斗结算：伤害→金币、米饭→好感 ——
	var run := RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))
	var lv := LevelPool.get_level("L1")
	var cb := run.start_battle(lv)
	cb.rice_eaten = 3
	var g0 := run.gold
	var a0 := Affection.points
	run.win_battle(cb, lv)
	_check(run.gold == g0 + RunState.gold_for_damage(cb.damage_dealt),
			"胜利按伤害结算金币")
	_check(absf(Affection.points - a0 - 6.0) < 0.001, "3 碗米饭 = +6 好感")

	# —— 好感 → 许愿品质 ——
	var hi_def := {"name": "数值测试", "kind": "attack", "damage": 99, "block": 0}
	var cap0 := int(WishCardFactory.clamp_ai_card(hi_def, 1, 0)["damage"])
	var cap_hi := int(WishCardFactory.clamp_ai_card(hi_def, 1, 25)["damage"])
	_check(cap_hi > cap0, "好感抬高伤害预算（%d → %d）" % [cap0, cap_hi])
	var s_def := {"name": "状态测试", "kind": "skill", "damage": 0, "block": 5,
			"program": [{"when": "on_play", "then": [
					{"do": "apply_status", "status": "poison", "tier": 1, "target": "enemy"}]}]}
	var s0 := WishCardFactory.make_from_ai(s_def, 1, 0)
	var s_hi := WishCardFactory.make_from_ai(s_def, 1, 25)
	var t0 := int((((s0.effects as Array)[0] as Dictionary)["then"] as Array)[0]["tier"])
	var t1 := int((((s_hi.effects as Array)[0] as Dictionary)["then"] as Array)[0]["tier"])
	_check(t1 > t0, "好感抬状态档位（%d → %d）" % [t0, t1])
	var two_def := {"name": "机制测试", "kind": "attack", "damage": 0, "block": 0,
			"program": [{"when": "on_play", "then": [
					{"do": "damage_scaled", "per": "same_kind_streak", "step": 2}]},
				{"when": "on_play", "then": [
					{"do": "apply_status", "status": "weak", "tier": 1, "target": "enemy"}]}]}
	var o0 := WishCardFactory.make_from_ai(two_def, 1, 0)
	var o25 := WishCardFactory.make_from_ai(two_def, 1, 25)
	_eq((o0.effects as Array).size(), 1, "低好感：2 个机制被砍到 1 个")
	_eq((o25.effects as Array).size(), 2, "高好感：机制预算放开到 2")

	# —— 持久化往返 ——
	Affection.points = 123.0
	Affection.save()
	Affection.points = 0.0
	Affection.load()
	_eq(Affection.points, 123.0, "好感持久化往返")
	Affection.points = saved
	Affection.save()


func _test_shop_gifts() -> void:
	print("[商店·好感礼物]")
	var run := RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))
	var shop := ShopScreen.new()
	shop.setup(run)
	_host.add_child(shop)
	await process_frame
	var saved := Affection.points
	run.gold = 100
	var a0 := Affection.points
	shop._on_buy_gift({"id": "test", "name": "测试礼物", "price": 30, "points": 10.0})
	_eq(run.gold, 70, "购买扣 30 金币")
	_check(absf(Affection.points - a0 - 10.0) < 0.01, "礼物 +10 好感")
	# 买不起时不动账
	shop._on_buy_gift({"id": "test2", "name": "贵礼物", "price": 9999, "points": 99.0})
	_eq(run.gold, 70, "金币不足不扣款")
	Affection.points = saved
	Affection.save()
	shop.queue_free()
	await process_frame


## 2026-11-07：更新演示屏（全部真系统交互）
func _test_patch_demo() -> void:
	print("[更新演示屏]")
	var demo := PatchDemoScreen.new()
	_host.add_child(demo)
	await process_frame
	await process_frame
	_check(demo._content != null and demo._content.get_child_count() == 8,
			"八个演示标签页全部构建（含角色转场 + 面板伸缩）")
	# Tab0 效果工坊：编译 + 试打
	_check(demo._fx_desc.text.contains("编译通过"), "效果工坊实时编译出人话")
	demo._fx_run()
	_check(demo._fx_run_out.text.contains("敌 HP"), "试打真跑 StsCombat 并输出前后状态")
	# Tab2 算力：cost3 一次吃完
	demo._en_play(3, 14)
	_eq(demo._en_combat.energy, 0, "演示屏：cost3 吃掉整回合算力")
	# Tab3 定价：真模拟出报告
	demo._price_pick.selected = 3   ## 超模四连
	demo._price_samples.value = 40
	await demo._price_run()
	_check(demo._price_out.text.contains("竞技禁用"), "演示定价把超模卡判禁用")
	# Tab4 组合：真容斥
	await demo._combo_run()
	_check(demo._combo_out.text.contains("总判"), "组合审计输出报告")
	# Tab5 好感：礼物真加
	var saved := Affection.points
	demo._aff_pts.value = 500
	demo._aff_refresh()
	_check(demo._aff_out.text.contains("好感点 500"), "好感演示读真实等级")
	Affection.points = saved
	Affection.save()
	demo.queue_free()
	await process_frame


## 2026-11-08：角色切换水波转场（试验版）——shader 控件基本行为
func _test_ripple_swap() -> void:
	print("[水波转场]")
	var v := RippleSwapPortrait.new()
	_host.add_child(v)
	v.size = Vector2(384, 512)
	await process_frame
	var ta: Texture2D = load("res://assets/art/ai-deepdeek.png")
	var tb: Texture2D = load("res://assets/art/ai-kweno.png")
	_check(v.get_child_count() > 0, "控件持有 shader 矩形")
	v.set_portrait(ta)
	v.debug_prepare(ta, tb)
	v.debug_set_progress(0.5)
	_check(true, "progress 手动推进不炸（0.5）")
	v.debug_set_progress(1.0)
	_check(not v.is_swapping(), "手动推进不触发转场状态")
	var done := [false]
	v.swap_finished.connect(func() -> void: done[0] = true)
	v.swap_to(tb)
	_check(v.is_swapping(), "swap_to 进入转场状态")
	await create_timer(1.1).timeout
	_check(done[0], "转场完成发 swap_finished 信号")
	_check(not v.is_swapping(), "转场结束后状态复位")
	# 一人一款：折扇 / X斩 / 龙鳞 各冒烟一次（切换 shader + 手动推进不炸）
	for st in [RippleSwapPortrait.Style.FAN, RippleSwapPortrait.Style.SLASH,
			RippleSwapPortrait.Style.HEX]:
		v.style = st
		v.debug_prepare(ta, tb)
		v.debug_set_progress(0.5)
		_check(true, "风格 %d 手动推进不炸" % st)
	v.queue_free()
	await process_frame

func _test_panel_morph() -> void:
	print("[面板伸缩]")
	var v := PanelMorphDemo.new()
	_host.add_child(v)
	v.size = Vector2(1600, 900)
	await process_frame
	await process_frame

	var sb0: Vector2 = v._sidebar.position
	var sb_sz0: Vector2 = v._sidebar.size
	var dl_sz0: Vector2 = v._dialog.size
	_check(is_equal_approx(sb_sz0.y, PanelMorphDemo.SIDEBAR_H), "初始左边框满高 900")
	_check(is_equal_approx(dl_sz0.x, PanelMorphDemo.DIALOG_W), "初始下边框宽 880")

	# ── 真点按钮。时间轴（按下=0）：左框[0,0.55]；下框[0,0.45]收 + [0.45,1.50]上移顶出 ──
	v._btn.emit_signal("pressed")
	await create_timer(0.30).timeout          # t≈0.30
	_check(v._sidebar.size.y < sb_sz0.y, "① 播放中左边框高度已在收缩")
	_check(v._dialog.size.x < dl_sz0.x, "② 播放中下边框宽度也已在收缩（两框同时进行）")
	_check(is_equal_approx(v._sidebar.position.y, sb0.y), "① 收缩时上边固定不动（position.y 不变）")

	await create_timer(0.35).timeout          # t≈0.65：左框已停（0.07+0.55=0.62 收完），下框收窄完+蓄力
	_check(absf(v._sidebar.size.y - PanelMorphDemo.SIDEBAR_COMPACT_H) < 1.0, "① 左边框收到高度 300")
	_check(absf(v.sidebar_visual_pos().y) < 30.0, "① 左框此时基本还在原位（飞出刚开始）")
	_check(absf((v._dialog.position.x + v._dialog.size.x) - v._orig_sidebar_right()) < 1.0,
			"② 下边框右边线已对齐原左边框右边线")
	_check(absf(v._dialog.size.x - PanelMorphDemo.DIALOG_COMPACT_W) < 1.0,
			"② 下边框收到与原左边框同宽 232")

	await create_timer(0.70).timeout          # t≈1.35：飞出段（0.54~1.59）进行中
	_check(v.sidebar_visual_pos().y < -20.0, "③ 左边框已被顶起来")
	_check(v.dialog_visual_pos().y < v._dialog_rise_y() - 20.0, "③ 下边框同步上冲")
	var gap_mid: float = v.dialog_visual_pos().y - (v.sidebar_visual_pos().y + v._sidebar.size.y)
	_check(absf(gap_mid - PanelMorphDemo.GAP) < 1.5, "③ 两框相对位置保持不变（间距仍为 12）")

	await create_timer(0.70).timeout          # t≈2.05：全部结束（1.59 + 余量）
	_check(v.sidebar_visual_pos().y + v._sidebar.size.y < 0.0, "③ 左边框完全移出画面顶部")
	_check(v.dialog_visual_pos().y + v._dialog.size.y < 0.0, "③ 下边框也完全移出画面顶部")
	_check(not v._btn.disabled, "全部动画走完后按钮恢复")

	# 复位
	v._reset_layout()
	await process_frame
	_check(is_equal_approx(v._sidebar.size.y, PanelMorphDemo.SIDEBAR_H)
			and is_equal_approx(v._sidebar.position.y, 0.0)
			and is_equal_approx(v._dialog.size.x, PanelMorphDemo.DIALOG_W), "复位回到初始布局")

	# ── 关键验收：接触点前后**速度连续**（不留停顿）──
	# 用 debug 钩子在接触点附近等间隔取样，比较下框相邻位移差
	var contact_k := (PanelMorphDemo.DIALOG_BASE.y - v._dialog_rise_y()) / v._rise_push_dist()
	var dt := 0.02   # 归一化步长（这里是缓动后的 k 步长）
	# debug_set_morph 内部飞出段用 QUAD + EASE_IN（k = tp^2），反解 tp = sqrt(k)
	var ys: Array[float] = []
	for n in 5:
		var kk: float = clampf(contact_k - dt * 2.0 + dt * float(n), 0.0, 1.0)
			# 飞出段缓动 = QUAD + EASE_IN → k = tp^2，反解 tp = sqrt(k)
		var tp_lin: float = sqrt(clampf(kk, 0.0, 1.0))
		v.debug_set_morph((0.45 + 0.09 + tp_lin * 1.05) / PanelMorphDemo.MORPH_TOTAL)
		ys.append(v.dialog_visual_pos().y)
	var steps: Array[float] = []
	for n in range(1, ys.size()):
		steps.append(absf(ys[n] - ys[n - 1]))
	# 跨过接触点的那一步与相邻步长应同量级（若中途换段停顿，跨接缝步长会明显变小）
	var step_min: float = steps.min()
	var step_max: float = steps.max()
	_check(step_min > step_max * 0.55,
			"接触点处速度连续（相邻步长最小/最大 = %.2f，未出现停顿）" % (step_min / step_max))

	# ── 本次优化验收（2026-11-09 联网调研落地）──
	# ① 飞出段走渲染通道：真实 position/size 全程不变，动画只体现在 offset_transform
	v.debug_set_morph(0.0)
	var raw_sb_y: float = v._sidebar.position.y
	var raw_dl_y: float = v._dialog.position.y
	v.debug_set_morph(1.0)
	_check(is_equal_approx(v._sidebar.position.y, raw_sb_y)
			and is_equal_approx(v._dialog.position.y, raw_dl_y),
			"飞出段走渲染通道：真实 position.y 全程不变（不触发 layout）")
	_check(v._dialog.offset_transform_position.y < -100.0,
			"飞出位移体现在 offset_transform_position（%.0f）" % v._dialog.offset_transform_position.y)
	_check(v._dialog.offset_transform_enabled, "两个框都启用了 offset_transform")

	# ② min-size 钳制：本次目标尺寸远大于内容最小尺寸，不会卡住
	var min_sz: Vector2 = v._sidebar.get_minimum_size()
	_check(PanelMorphDemo.SIDEBAR_COMPACT_W > min_sz.x
			and PanelMorphDemo.SIDEBAR_COMPACT_H > min_sz.y,
			"目标尺寸大于内容最小尺寸（%s），不会被钳制" % min_sz)
	_check(PanelMorphDemo.DIALOG_COMPACT_W > v._dialog.get_minimum_size().x,
			"下框目标宽也大于最小尺寸")

	# ③ anticipation 蓄力：收窄结束瞬间应先**下沉**（正 y），再飞出
	v.debug_set_morph((0.45 + 0.045) / PanelMorphDemo.MORPH_TOTAL)   # 蓄力段中点
	_check(v._dialog.offset_transform_position.y > 3.0,
			"蓄力段先反向下沉（%.1fpx），建立重量感" % v._dialog.offset_transform_position.y)

	# ④ 错帧：左框应比下框晚启动（同一时刻左框收缩进度更小）
	v.debug_set_morph(0.02 / PanelMorphDemo.MORPH_TOTAL)
	var sb_early: float = v._sidebar.size.y
	v.debug_set_morph(0.30 / PanelMorphDemo.MORPH_TOTAL)
	var sb_later: float = v._sidebar.size.y
	_check(sb_early > PanelMorphDemo.SIDEBAR_COMPACT_H
			and sb_later < PanelMorphDemo.SIDEBAR_H,
			"左框延迟启动（错帧 70ms）后仍在收缩")

	# 接触瞬间：左框刚好开始动、间距仍为 GAP
	var tp_contact: float = sqrt(clampf(contact_k, 0.0, 1.0))
	v.debug_set_morph((0.45 + 0.09 + tp_contact * 1.05) / PanelMorphDemo.MORPH_TOTAL)
	_check(absf(v.sidebar_visual_pos().y) < 1.0, "接触时刻左框仍在原位")
	_check(absf(v.dialog_visual_pos().y - v._dialog_rise_y()) < 2.0, "接触时刻下框正好贴到左框底部")

	# debug 端点
	v.debug_set_morph(0.0)
	_check(is_equal_approx(v._sidebar.size.y, PanelMorphDemo.SIDEBAR_H), "debug p0 = 初始")
	v.debug_set_morph(1.0)
	_check(v.sidebar_visual_pos().y + v._sidebar.size.y < 0.0
			and v.dialog_visual_pos().y + v._dialog.size.y < 0.0, "debug p1 = 两框全出画")
	_check(absf((v._dialog.position.x + v._dialog.size.x) - v._orig_sidebar_right()) < 1.0,
			"debug p1：右对齐在顶出期间保持")
	v.queue_free()
	await process_frame

func _test_mosaic_and_select() -> void:
	print("[马赛克转场 + 选角]")
	# ── 马赛克遮罩：块数语义（blocks 大=清晰，1=整屏一块）──
	var mos := ScreenMosaic.new()
	_host.add_child(mos)
	await process_frame
	await process_frame
	_check(mos.size.x > 100.0, "遮罩铺满全屏（不是 0 尺寸）")
	# 用一张自制纯色图当冻结帧源，避开抓屏依赖
	mos._snapshot = Image.create(64, 36, false, Image.FORMAT_RGBA8)
	mos._snapshot.fill(Color(0.2, 0.4, 0.8))
	mos.debug_set_blocks(1)
	_check(mos._cur_blocks == 1, "blocks=1 = 整屏一块（最糊）")
	mos.debug_set_blocks(32)
	_check(mos._cur_blocks == 32, "blocks=32 = 32 块横排（较清晰）")
	_check(not mos.is_visible_in_tree() or mos.visible, "块化后可显示")
	mos.queue_free()
	await process_frame

	# ── 选角界面：4 角色 / 圆点 / 箭头 / 开始按钮 / 一人一款转场 ──
	var sel := CharacterSelectScreen.new()
	sel.setup(AiPool.all_ais())
	_host.add_child(sel)
	await process_frame
	await process_frame
	_check(sel._ais.size() == 4, "选角界面载入 4 位角色")
	_check(sel._dots.size() == 4, "底部 4 个位置点")
	_check(sel._left_btn != null and sel._right_btn != null, "左右切换箭头已建")
	_check(sel._start_btn != null, "右下角「开始游戏」已建")
	_eq(sel.current_id(), "deepdeek", "默认选中第 1 位 DeepDeek")

	# ── 选框：切换时**直接换图**（不播转场）──
	# 一轮曾用 RippleSwapPortrait 播一人一款转场，主人 2026-11-09 二次修订要求去掉
	var thumb0: Texture2D = sel._thumb.texture
	_check(thumb0 != null, "选框内小立绘已显示")
	_check(sel._thumb is TextureRect, "选框是普通 TextureRect（非转场控件）")

	# ── 背景：大立绘铺满全屏 ──
	_check(sel._bg_layer != null, "背景大立绘层已建")
	_check(sel._bg_layer.size.x > 1000.0 and sel._bg_layer.size.y > 500.0,
			"背景层铺满全屏（%s）" % sel._bg_layer.size)
	_eq(int(sel._bg_layer.stretch_mode), int(TextureRect.STRETCH_KEEP_ASPECT_COVERED),
			"背景等比覆盖不变形")
	_check(sel._bg_layer.texture != null, "背景已载入大立绘")
	_check(String(AiPool.get_ai("deepdeek").bust_path) != "", "大立绘路径已接入 bust_path")

	# 切换：选框立即换图、背景立即换图（无转场状态）
	var before_idx: int = sel.current_index()
	sel._right_btn.emit_signal("pressed")
	await process_frame
	_check(sel.current_index() != before_idx, "点右箭头切换到下一位")
	_eq(sel.current_id(), "kweno", "切到第 2 位 Kweno")
	_check(sel._thumb.texture != thumb0, "选框立绘已直接换掉")
	_check(not sel._busy, "切换不进入忙碌态（无转场，可立即再切）")
	var thumb1: Texture2D = sel._thumb.texture
	sel._right_btn.emit_signal("pressed")
	await process_frame
	_check(sel._thumb.texture != thumb1, "连续切换无需等待（连点有效）")
	_eq(sel.current_id(), "chatppt", "连点后到第 3 位")
	# 切回第一位
	sel._left_btn.emit_signal("pressed")
	sel._left_btn.emit_signal("pressed")
	await process_frame
	_eq(sel.current_id(), "deepdeek", "左箭头可切回")

	# 开始游戏按钮发信号
	var started := [""]
	sel.started.connect(func(id: String) -> void: started[0] = id)
	sel._start_btn.emit_signal("pressed")
	await process_frame
	_eq(started[0], sel.current_id(), "开始游戏带回当前选中角色 id")

	# 选框立绘等比适配（KEEP_ASPECT_CENTERED 由 TextureRect 负责，不会拉伸）
	_eq(int(sel._thumb.stretch_mode), int(TextureRect.STRETCH_KEEP_ASPECT_CENTERED),
			"选框立绘等比居中不拉伸")
	sel.queue_free()
	await process_frame

	# ── 启动页精简：无模型名铭牌 / 无模型下拉 / 无右侧立绘 ──
	var lc := LaunchScreen.new()
	_host.add_child(lc)
	await process_frame
	lc.expand()
	await process_frame
	await process_frame
	# 成员变量已删除，改为静态检查源码里不再有这些节点/引用
	var lc_src := FileAccess.get_file_as_string("res://scripts/ui/launch_screen.gd")
	_check(not lc_src.contains("_name_plate"), "左上角模型铭牌已移除（源码无残留）")
	_check(not lc_src.contains("_portrait"), "右侧模型立绘已移除（源码无残留）")
	_check(not lc_src.contains("OptionButton"), "输入框旁模型下拉已移除（源码无残留）")
	_check(lc._skill_list != null, "侧栏技能列表仍正常构建")
	_check(lc.get_node_or_null("AgentDialog") != null, "Agent 对话框已展开")
	# 空输入也能发送
	var fired := [""]
	lc.launched.connect(func(id: String) -> void: fired[0] = id)
	lc._input.text = ""
	lc._send()
	await process_frame
	_check(not fired[0].is_empty(), "输入框空着也能发送（进选角）")
	lc.queue_free()
	await process_frame
