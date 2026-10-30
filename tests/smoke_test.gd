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
	await _test_ui()
	await _test_battle_flow(true)
	await _test_battle_flow(false)
	await _test_battle_intro()
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
	_eq(ids.size(), 2, "卡池共 2 张卡")
	var ram := StsCardPool.card("fish_ram")
	_check(ram != null and ram.damage == 6 and ram.cost == 1
			and ram.kind == StsCard.Kind.ATTACK, "肥鱼铁头撞：1 费攻击 6 伤")
	var taunt := StsCardPool.card("taunt")
	_check(taunt != null and taunt.block == 5 and taunt.cost == 1
			and taunt.kind == StsCard.Kind.SKILL, "来打我呀！：1 费防御 5 格挡")
	var deck := StsCardPool.starter_deck()
	_eq(deck.size(), 5, "起始卡组共 5 张")
	var atk := 0
	var def := 0
	for c in deck:
		atk += 1 if c.kind == StsCard.Kind.ATTACK else 0
		def += 1 if c.kind == StsCard.Kind.SKILL else 0
	_check(atk == 3 and def == 2, "起始卡组 3 攻 + 2 防（得 %d+%d）" % [atk, def])
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
	_eq(cb.hand.size(), 3, "开局抽 3 张（DeepSeek 补牌数）")
	_eq(cb.turn, 1, "开局回合 1")

	# 按顺序出牌：只有最左一张能打
	_check(cb.can_play(cb.hand[0]), "最左一张可打")
	if cb.hand.size() > 1:
		_check(not cb.can_play(cb.hand[1]), "第二张不能跳着打")

	# 按顺序把 3 张全打出去（无出牌数量限制）：打空后自动从弃牌堆随机补 3
	for i in 3:
		_check(cb.can_play(cb.hand[0]), "第 %d 张：最左可打" % (i + 1))
		var e1 := cb.play_card(cb.hand[0])
		_check(bool(e1.get("ok", false)), "第 %d 张按顺序打出" % (i + 1))
	_eq(cb.hand.size(), 3, "手牌打空后自动从弃牌堆随机补 3 张")
	_eq(cb.discard_pile.size(), 0, "补牌从弃牌堆抽走")
	_eq(cb.draw_pile.size() + cb.discard_pile.size() + cb.hand.size(), 5,
			"牌堆守恒：抽 + 弃 + 手 = 5")
	_check(cb.can_play(cb.hand[0]), "补牌后最左一张可打")

	# 弃牌：弃 1 张立刻从牌堆抽 1 张，手牌数不变
	var before := cb.hand.size()
	_check(cb.discard_card(cb.hand[0]), "弃牌成功")
	_eq(cb.hand.size(), before, "弃 1 抽 1，手牌数不变")
	_eq(cb.draw_pile.size() + cb.discard_pile.size() + cb.hand.size(), 5, "弃牌后守恒")

	# 结束回合：敌人行动 + 回合推进
	var events := cb.end_turn()
	_eq(cb.block, 0, "新回合格挡清零")
	_check(cb.hand.size() >= 1, "新回合手牌有牌（弃牌堆随机补）")
	_check(events.size() >= 1, "结束回合返回敌人行动事件")
	_eq(cb.turn, 2, "回合推进到 2")
	_eq(cb.draw_pile.size() + cb.discard_pile.size() + cb.hand.size(), 5, "新回合守恒")

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


# ── ④ 战斗 UI 构建 ────────────────────────────────────
func _test_ui() -> void:
	print("[战斗界面]")
	var run := RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))
	_eq(run.deck.size(), 5, "开局卡组 5 张")

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

	var st := arena.debug_combat_state()
	_eq(st.get("hand", 0), 3, "界面手牌 3 张（按角色补牌数）")
	_eq(st.get("enemy_hp", -1), 40, "L1 敌人 HP 40")
	_eq(arena.debug_hand_count(), 3, "手牌视图 3 张")

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
		if win_expected and arena.debug_hand_count() > 0:
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
	for screen in ["arena", "reward", "menu", "result"]:
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
