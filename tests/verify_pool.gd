extends SceneTree
## 牌池与「打出即失效」自检。
##
## 跑法：
##   godot --headless --path . --script res://tests/verify_pool.gd
## 期望：13 项检查，0 项失败。
##
## 守的是 2026-10-22 主人定的三条机制：
##   ① 起始牌池 = 扑克 52 张全牌（4 花色 × 13 点数）
##   ② 打出去的牌**本关内失效**，不再回到手牌（弃牌不算，弃掉的还会回来）
##   ③ A 是最大的牌（顺子那侧由 tests/verify_hands.gd 管）

var _checks := 0
var _fails := 0


func _init() -> void:
	print("[牌池与失效机制]")
	var run := RunState.new()
	run.reset_run()
	run.ensure_poker_deck()

	# ① 52 张 / 每花色 13 张 / 每点数 4 张 / id 不重复
	_eq(run.poker_deck.size(), RunState.POKER_DECK_SIZE, "牌池 52 张")
	var by_suit := {}
	var by_rank := {}
	var ids := {}
	for c in run.poker_deck:
		by_suit[c.suit] = int(by_suit.get(c.suit, 0)) + 1
		by_rank[c.rank] = int(by_rank.get(c.rank, 0)) + 1
		ids[c.id()] = true
	var suit_ok := by_suit.size() == 4
	for s in by_suit:
		if int(by_suit[s]) != RunState.POKER_RANKS:
			suit_ok = false
	_check(suit_ok, "每花色 13 张（四种花色都在）")
	var rank_ok := by_rank.size() == RunState.POKER_RANKS
	for r in by_rank:
		if int(by_rank[r]) != 4:
			rank_ok = false
	_check(rank_ok, "每点数 4 张（A~K 齐全）")
	_eq(ids.size(), RunState.POKER_DECK_SIZE, "52 张牌的 id 互不相同")

	# ② 打出即失效
	run.set_ai(AiPool.get_ai("deepdeek"))
	var level := LevelPool.get_level("L1")
	run.start_poker_level(level)
	_eq(run.poker_hand.size(), RunState.POKER_HAND_SIZE, "开局手牌 5 张")
	_eq(run.poker_void.size(), 0, "开局失效堆为空")

	var played_ids: Array[String] = []
	for i in 3:
		var hand_snapshot: Array[PokerCard] = run.poker_hand.duplicate()
		var play: Array[PokerCard] = [hand_snapshot[0], hand_snapshot[1]]
		for c in play:
			played_ids.append(c.id())
		run.play_poker_hand(play)
	_eq(run.poker_void.size(), 6, "打了 3 手 × 2 张 → 失效堆 6 张")
	_check(_absent(run, played_ids), "打出去的 6 张不再出现在手牌或抽牌堆里")

	# 弃牌不算失效：弃掉的进弃牌堆，仍有回来的机会
	var discard_pick: Array[PokerCard] = [run.poker_hand[0]]
	var discard_id: String = discard_pick[0].id()
	_check(run.discard_poker(discard_pick), "弃牌成功")
	_eq(run.poker_discard.size(), 1, "弃掉的牌进弃牌堆（不进退废堆）")
	_check(not _in_void(run, discard_id), "弃掉的牌没被打进失效堆")

	# ③ 每关重置：新开一关，失效堆清空、牌池重新发满
	run.start_poker_level(LevelPool.get_level("L2"))
	_eq(run.poker_void.size(), 0, "新开一关失效堆清空")
	_eq(run.poker_hand.size(), RunState.POKER_HAND_SIZE, "新开一关手牌仍是 5 张")

	print("\n==== %d 项检查，%d 项失败 ====" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)


## 这些 id 是否已经完全不在「手牌 + 抽牌堆」里
func _absent(run: RunState, ids: Array[String]) -> bool:
	for i in ids:
		for c in run.poker_hand:
			if c.id() == i:
				return false
		for c in run.poker_draw:
			if c.id() == i:
				return false
	return true


func _in_void(run: RunState, id: String) -> bool:
	for c in run.poker_void:
		if c.id() == id:
			return true
	return false


func _eq(got: Variant, want: Variant, msg: String) -> void:
	_check(got == want, "%s  期望=%s 实得=%s" % [msg, str(want), str(got)])


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("  ok  : %s" % msg)
	else:
		_fails += 1
		print("  FAIL: %s" % msg)
