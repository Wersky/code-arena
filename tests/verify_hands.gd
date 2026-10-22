extends SceneTree
## 德州牌型规则自检：把 9 种标准牌型 + 本作额外的「五条」逐个钉死。
##
## 跑法：
##   godot --headless --path . --script res://tests/verify_hands.gd
## 期望：14 项检查，0 失败。
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

	# 牌型优先级：同花顺 > 四条 > 葫芦 > 同花 > 顺子 > 三条 > 两对 > 一对 > 高牌
	_check(PokerHand.Type.STRAIGHT_FLUSH > PokerHand.Type.FOUR_KIND
			and PokerHand.Type.FOUR_KIND > PokerHand.Type.FULL_HOUSE
			and PokerHand.Type.FULL_HOUSE > PokerHand.Type.FLUSH
			and PokerHand.Type.FLUSH > PokerHand.Type.STRAIGHT
			and PokerHand.Type.STRAIGHT > PokerHand.Type.THREE_KIND
			and PokerHand.Type.THREE_KIND > PokerHand.Type.TWO_PAIR
			and PokerHand.Type.TWO_PAIR > PokerHand.Type.PAIR
			and PokerHand.Type.PAIR > PokerHand.Type.HIGH_CARD,
			"牌型强弱顺序与德州一致（同花顺最高）")

	# A 当最小：A-2-3-4-5 认作顺子（德州 A 可低）
	_expect("A 当最小的顺子 A2345", PokerHand.Type.STRAIGHT,
			[[0, 1], [1, 2], [2, 3], [3, 4], [0, 5]])

	# ⚠ 已知缺口：A 当最大（10-J-Q-K-A）目前**不认**。
	# 现状断言，防止"以为它已经支持"。修法见 docs/进度交接.md §2.3。
	var high_ace: Array[PokerCard] = [
		PokerCard.make(0, 10), PokerCard.make(1, 11), PokerCard.make(2, 12),
		PokerCard.make(3, 13), PokerCard.make(0, 1)]
	_check(PokerHand.evaluate_type(high_ace) != PokerHand.Type.STRAIGHT,
			"已知缺口：10-J-Q-K-A 目前不算顺子（A 只当 1）")

	# 计分公式：♥3 + ♦3（一对，两张红牌，DeepDeek）→ 16 筹码 × 10 倍率 = 160
	# 与 docs/04-基础玩法.md §4 的手算示例一致
	var t: String = "一对"
	var cards: Array[PokerCard] = [PokerCard.make(0, 3), PokerCard.make(1, 3)]
	var r := PokerHand.score(cards, {"ai_id": "deepdeek"})
	_check(r["type_name"] == t and int(r["chips"]) == 16 and int(r["mult"]) == 10
			and int(r["score"]) == 160,
			"♥3+♦3 手算示例 = 16×10=160（实得 %d×%d=%d）"
			% [int(r["chips"]), int(r["mult"]), int(r["score"])])

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
