extends SceneTree
## 德州牌型规则自检：把 9 种标准牌型 + 本作额外的「五条」逐个钉死。
##
## 跑法：
##   godot --headless --path . --script res://tests/verify_hands.gd
## 期望：15 项检查，0 失败。
##
## 这个文件替代 `docs/04-基础玩法.md` §3 的牌型表做**可执行断言**：
## 表里改了数值/新增牌型，这里必须同步——否则文档又会变成"看着对、跑起来不是"。

var _checks := 0
var _fails := 0


func _init() -> void:
	print("[德州牌型规则]")
	# 9 种标准牌型（与 docs/04-基础玩法.md §3 / 主人给的牌型表一致）
	_expect("高牌", PokerHand.Type.HIGH_CARD, [[3, 2]])
	_expect("一对", PokerHand.Type.PAIR, [[0, 3], [1, 3]])
	_expect("两对", PokerHand.Type.TWO_PAIR, [[0, 3], [1, 3], [3, 5], [2, 5]])
	_expect("三条", PokerHand.Type.THREE_KIND, [[0, 3], [1, 3], [2, 3]])
	_expect("顺子", PokerHand.Type.STRAIGHT, [[0, 1], [1, 2], [2, 3], [3, 4], [0, 5]])
	_expect("同花", PokerHand.Type.FLUSH, [[0, 1], [0, 3], [0, 5], [0, 7], [0, 9]])
	_expect("葫芦", PokerHand.Type.FULL_HOUSE, [[0, 3], [1, 3], [2, 3], [3, 5], [0, 5]])
	_expect("四条", PokerHand.Type.FOUR_KIND, [[0, 3], [1, 3], [2, 3], [3, 3], [0, 9]])
	_expect("同花顺", PokerHand.Type.STRAIGHT_FLUSH,
			[[0, 1], [0, 2], [0, 3], [0, 4], [0, 5]])
	# 本作额外牌型：奖励能加同点数牌，5 张同点可凑出（德州 52 张牌里不可能）
	_expect("五条（本作额外）", PokerHand.Type.FIVE_KIND,
			[[0, 3], [1, 3], [2, 3], [3, 3], [0, 3]])
	# 同花五条：五张同花色同点数（只有奖励叠出完全相同的牌才可能）
	_expect("同花五条", PokerHand.Type.FLUSH_FIVE,
			[[0, 3], [0, 3], [0, 3], [0, 3], [0, 3]])

	# 牌型优先级：同花顺 > 四条 > 葫芦 > 同花 > 顺子 > 三条 > 两对 > 一对 > 高牌
	_check(PokerHand.Type.ROYAL_FLUSH > PokerHand.Type.FLUSH_FIVE
			and PokerHand.Type.FLUSH_FIVE > PokerHand.Type.FIVE_KIND
			and PokerHand.Type.FIVE_KIND > PokerHand.Type.STRAIGHT_FLUSH,
			"新加的顶阶顺序：皇家同花顺 > 同花五条 > 五条 > 同花顺")
	_check(PokerHand.Type.STRAIGHT_FLUSH > PokerHand.Type.FOUR_KIND
			and PokerHand.Type.FOUR_KIND > PokerHand.Type.FULL_HOUSE
			and PokerHand.Type.FULL_HOUSE > PokerHand.Type.FLUSH
			and PokerHand.Type.FLUSH > PokerHand.Type.STRAIGHT
			and PokerHand.Type.STRAIGHT > PokerHand.Type.THREE_KIND
			and PokerHand.Type.THREE_KIND > PokerHand.Type.TWO_PAIR
			and PokerHand.Type.TWO_PAIR > PokerHand.Type.PAIR
			and PokerHand.Type.PAIR > PokerHand.Type.HIGH_CARD,
			"9 条标准牌型的强弱顺序与德州一致（同花顺是标准牌里的最高档）")

	# A 当最小：A-2-3-4-5 认作顺子（德州 A 可低）
	_expect("A 当最小的顺子 A2345", PokerHand.Type.STRAIGHT,
			[[0, 1], [1, 2], [2, 3], [3, 4], [0, 5]])

	# A 当最大：10-J-Q-K-A 也算顺子（2026-10-22 起，A 既当 1 也当 14）
	var high_ace: Array[PokerCard] = [
		PokerCard.make(0, 10), PokerCard.make(1, 11), PokerCard.make(2, 12),
		PokerCard.make(3, 13), PokerCard.make(0, 1)]
	_check(PokerHand.evaluate_type(high_ace) == PokerHand.Type.STRAIGHT,
			"A 当最大的顺子 10-J-Q-K-A → 顺子（实得 %s）"
			% PokerHand.type_name(PokerHand.evaluate_type(high_ace)))

	# 皇家同花顺：同花的 10-J-Q-K-A，2026-10-22 起**单列一档**（比同花顺高）
	var royal: Array[PokerCard] = [
		PokerCard.make(0, 10), PokerCard.make(0, 11), PokerCard.make(0, 12),
		PokerCard.make(0, 13), PokerCard.make(0, 1)]
	_check(PokerHand.evaluate_type(royal) == PokerHand.Type.ROYAL_FLUSH,
			"皇家同花顺 10-J-Q-K-A 同花 → 皇家同花顺（实得 %s）"
			% PokerHand.type_name(PokerHand.evaluate_type(royal)))

	# 计分公式：♥3 + ♦3（一对，两张红牌，DeepDeek）→ 16 筹码 × 10 倍率 = 160
	# 与 docs/04-基础玩法.md §4 的手算示例一致
	var t: String = "一对"
	var cards: Array[PokerCard] = [PokerCard.make(0, 3), PokerCard.make(1, 3)]
	var r := PokerHand.score(cards, {"ai_id": "deepdeek"})
	_check(r["type_name"] == t and int(r["chips"]) == 16 and int(r["mult"]) == 10
			and int(r["score"]) == 160,
			"♥3+♦3 手算示例 = 16×10=160（实得 %d×%d=%d）"
			% [int(r["chips"]), int(r["mult"]), int(r["score"])])

	# 点数价值（2026-10-22 定）：A=14、J/Q/K=10、其余按面值
	_check(PokerCard.chip_value(1) == 14 and PokerCard.chip_value(13) == 10
			and PokerCard.chip_value(11) == 10 and PokerCard.chip_value(7) == 7,
			"A=14 / JQK=10 / 其余按面值")

	# 只算牌型内：三条 3 + 两张散牌（K、Q）→ 只按 3 张 3 算
	#   chips = 30（三条）+ 3+3+3 + 2 张黑牌×25 = 89；mult = 3 + 1 张红牌×3 = 6
	var trio: Array[PokerCard] = [
		PokerCard.make(2, 3), PokerCard.make(3, 3), PokerCard.make(1, 3),
		PokerCard.make(3, 13), PokerCard.make(0, 12)]
	var trio_res := PokerHand.score(trio)
	_check(int(trio_res["scoring_count"]) == 3 and int(trio_res["chips"]) == 89
			and int(trio_res["mult"]) == 6,
			"三条+散牌：只算 3 张（chips=%d mult=%d 张数=%d）"
			% [int(trio_res["chips"]), int(trio_res["mult"]), int(trio_res["scoring_count"])])

	# 高牌取最大一张：♠A + ♣2 两张散牌 → 只算 A（14），chips = 5+14+25 = 44
	var two_scatter: Array[PokerCard] = [PokerCard.make(3, 1), PokerCard.make(2, 2)]
	var scatter_res := PokerHand.score(two_scatter)
	_check(int(scatter_res["scoring_count"]) == 1 and int(scatter_res["chips"]) == 44,
			"高牌只算最大一张：♠A+♣2 → 44 筹码（实得 %d）" % int(scatter_res["chips"]))

	print("\n==== %d 项检查，%d 项失败 ====" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)


## 按 [[花色, 点数], ...] 造牌并断言牌型
func _expect(label: String, want: int, spec: Array) -> void:
	var cards: Array[PokerCard] = []
	for p in spec:
		cards.append(PokerCard.make(int(p[0]), int(p[1])))
	var got := PokerHand.evaluate_type(cards)
	_check(got == want, "%s → %s（实得 %s）"
			% [label, PokerHand.type_name(want), PokerHand.type_name(got)])


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("  ok  : %s" % msg)
	else:
		_fails += 1
		print("  FAIL: %s" % msg)
