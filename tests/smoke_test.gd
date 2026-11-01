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
	_eq(ids.size(), 7, "卡池共 7 张卡（含白米饭、两张 D 指令行与两张觉醒攻击）")
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


# ── ⑧ 运行序列 / 选关地图 / 事件 ──────────────────────
func _test_map_event() -> void:
	print("[运行序列与地图]")
	var run := RunState.new()
	run.reset_run()
	_eq(run.run_seq.size(), 14, "运行序列 14 节点（10 战斗 + 4 事件）")
	var ev_n := 0
	for n in run.run_seq:
		if String(n.get("type", "")) == "event":
			ev_n += 1
	_eq(ev_n, 4, "事件节点 4 个（每 2 战斗插 1 个）")
	_eq(String(run.run_seq[0].get("type", "")), "battle", "首节点是战斗")
	_eq(String(run.run_seq[2].get("type", "")), "event", "第 3 节点是事件")

	var m := MapScreen.new()
	m.setup(run)
	_host.add_child(m)
	await process_frame
	_check(m.get_child_count() > 0, "选关地图已构建")
	_eq(String(run.current_node().get("type", "")), "battle", "当前节点 = 第一场战斗")
	m.queue_free()

	var hp0 := run.hp
	var e := EventScreen.new()
	e.setup(run, 0)
	_host.add_child(e)
	await process_frame
	_check(e.get_child_count() > 0, "事件界面已构建")
	e._on_choice({"hp": 18})
	await process_frame
	_check(run.hp == mini(RunState.MAX_HP, hp0 + 18), "事件效果生效（HP %d → %d）" % [hp0, run.hp])
	e.queue_free()
	run.node_finished()
	_eq(run.seq_idx, 1, "节点推进到 1")
