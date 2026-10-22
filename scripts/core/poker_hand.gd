class_name PokerHand
extends RefCounted
## 德州牌型判定与结算（Balatro 式 chips × mult）。
##
## 玩家选 1~5 张牌 → 判定牌型 → 给该牌型的基础筹码与基础倍率 →
## 每张牌再按「点数」加筹码、按「颜色」加倍率/筹码 → 相乘得分。
##
## 颜色规则（整个玩法最简单的一条）：
##   红（♥ ♦）每张 **+3 倍率**
##   黑（♠ ♣）每张 **+25 筹码**
##
## 结算公式（唯一一条）：
##   chips = 牌型筹码 + Σ 点数 + Σ 黑色筹码 + AI娘筹码加成
##   mult  = 牌型倍率 + Σ 红色倍率 + AI娘倍率加成
##   score = chips × mult

enum Type {
	HIGH_CARD, PAIR, TWO_PAIR, THREE_KIND, STRAIGHT,
	FLUSH, FULL_HOUSE, FOUR_KIND, STRAIGHT_FLUSH, FIVE_KIND,
}

const TYPE_NAMES := {
	Type.HIGH_CARD: "高牌",
	Type.PAIR: "一对",
	Type.TWO_PAIR: "两对",
	Type.THREE_KIND: "三条",
	Type.STRAIGHT: "顺子",
	Type.FLUSH: "同花",
	Type.FULL_HOUSE: "葫芦",
	Type.FOUR_KIND: "四条",
	Type.STRAIGHT_FLUSH: "同花顺",
	Type.FIVE_KIND: "五条",
}

## 牌型基础值：{chips, mult}
const TYPE_BASE := {
	Type.HIGH_CARD: {"chips": 5, "mult": 1},
	Type.PAIR: {"chips": 10, "mult": 2},
	Type.TWO_PAIR: {"chips": 20, "mult": 2},
	Type.THREE_KIND: {"chips": 30, "mult": 3},
	Type.STRAIGHT: {"chips": 30, "mult": 4},
	Type.FLUSH: {"chips": 35, "mult": 4},
	Type.FULL_HOUSE: {"chips": 40, "mult": 4},
	Type.FOUR_KIND: {"chips": 60, "mult": 7},
	Type.STRAIGHT_FLUSH: {"chips": 100, "mult": 8},
	Type.FIVE_KIND: {"chips": 120, "mult": 12},
}

## 颜色效果
const RED_MULT := 3       # 红牌每张加倍率
const BLACK_CHIPS := 25   # 黑牌每张加筹码


static func type_name(t: int) -> String:
	return TYPE_NAMES.get(t, "?")


static func type_base(t: int) -> Dictionary:
	return TYPE_BASE.get(t, {"chips": 0, "mult": 0})


## 判定牌型。cards 为空返回 HIGH_CARD。同一组牌取**能组成的最高牌型**。
static func evaluate_type(cards: Array[PokerCard]) -> int:
	var n := cards.size()
	if n == 0:
		return Type.HIGH_CARD
	if n == 1:
		return Type.HIGH_CARD

	# 点数计数（按出现次数从多到少排）
	var counts := {}
	for c in cards:
		counts[c.rank] = int(counts.get(c.rank, 0)) + 1
	var groups: Array = counts.values()
	groups.sort()
	groups.reverse()          # [最多, 次多, ...]

	var flush := n == 5
	if flush:
		var s := cards[0].suit
		for c in cards:
			if c.suit != s:
				flush = false
				break

	var straight := _is_straight(cards)

	if straight and flush:
		return Type.STRAIGHT_FLUSH
	if int(groups[0]) == 5:
		return Type.FIVE_KIND
	if int(groups[0]) == 4:
		return Type.FOUR_KIND
	if int(groups[0]) == 3 and groups.size() > 1 and int(groups[1]) == 2:
		return Type.FULL_HOUSE
	if flush:
		return Type.FLUSH
	if straight:
		return Type.STRAIGHT
	if int(groups[0]) == 3:
		return Type.THREE_KIND
	# 两对：至少两组各 2 张
	var pairs := 0
	for g in groups:
		if int(g) == 2:
			pairs += 1
	if pairs >= 2:
		return Type.TWO_PAIR
	if pairs == 1:
		return Type.PAIR
	return Type.HIGH_CARD


## 顺子：5 张、点数连续、无重复
static func _is_straight(cards: Array[PokerCard]) -> bool:
	if cards.size() != 5:
		return false
	var rs: Array[int] = []
	for c in cards:
		rs.append(c.rank)
	rs.sort()
	for i in range(1, rs.size()):
		if rs[i] != rs[i - 1] + 1:
			return false
	return true


## 结算。ctx 可带：
##   ai_id      —— 决定 AI 娘被动
##   bonus_chips / bonus_mult —— 本局累积的永久加成（奖励用）
static func score(cards: Array[PokerCard], ctx: Dictionary = {}) -> Dictionary:
	var t := evaluate_type(cards)
	var out := {
		"type": t,
		"type_name": type_name(t),
		"chips": 0,
		"mult": 0,
		"score": 0,
		"red_count": 0,
		"black_count": 0,
		"ai_id": str(ctx.get("ai_id", "")),
		"notes": [] as Array[String],
	}

	var base := type_base(t)
	var chips := int(base["chips"])
	var mult := int(base["mult"])

	var rank_sum := 0
	var red := 0
	var black := 0
	for c in cards:
		rank_sum += c.rank
		if PokerCard.is_red(c.suit):
			red += 1
		else:
			black += 1

	chips += rank_sum
	chips += black * BLACK_CHIPS
	mult += red * RED_MULT

	# AI 娘被动
	var ai_id := str(out["ai_id"])
	var ai_bonus := _ai_bonus(ai_id, cards, t)
	chips += int(ai_bonus["chips"])
	mult += int(ai_bonus["mult"])
	if str(ai_bonus["desc"]) != "":
		out["notes"].append(str(ai_bonus["desc"]))

	# 奖励累积的永久加成
	chips += int(ctx.get("bonus_chips", 0))
	mult += int(ctx.get("bonus_mult", 0))

	out["chips"] = chips
	out["mult"] = maxi(1, mult)
	out["score"] = chips * int(out["mult"])
	out["red_count"] = red
	out["black_count"] = black
	return out


## 4 位 AI 娘的被动：各自奖励一种出牌习惯
static func _ai_bonus(ai_id: String, cards: Array[PokerCard], t: int) -> Dictionary:
	var chips := 0
	var mult := 0
	var desc := ""
	match ai_id:
		"deepdeek":
			# 深度思考：红心牌额外 +2 倍率
			var hearts := 0
			for c in cards:
				if c.suit == PokerCard.Suit.HEART:
					hearts += 1
			mult += hearts * 2
			if hearts > 0:
				desc = "DeepDeek：红心牌额外 +%d 倍率" % (hearts * 2)
		"kweno":
			# 中文优化：所有牌 +10 筹码
			chips += cards.size() * 10
			desc = "Kweno：每张牌 +10 筹码（+%d）" % (cards.size() * 10)
		"chatppt":
			# 通用对话：高牌 / 一对 额外 +3 倍率（弱牌流）
			if t == Type.HIGH_CARD or t == Type.PAIR:
				mult += 3
				desc = "ChatPPT：高牌/一对 额外 +3 倍率"
		"grock":
			# 实时联网：黑桃牌额外 +20 筹码
			var spades := 0
			for c in cards:
				if c.suit == PokerCard.Suit.SPADE:
					spades += 1
			chips += spades * 20
			if spades > 0:
				desc = "Grock：黑桃牌额外 +%d 筹码" % (spades * 20)
	return {"chips": chips, "mult": mult, "desc": desc}


## 每位 AI 娘被动的一句话说明（选人界面用）
const AI_PASSIVE := {
	"deepdeek": "每张 ♥ 额外 +2 倍率",
	"kweno": "每张牌 +10 筹码",
	"chatppt": "高牌 / 一对 额外 +3 倍率",
	"grock": "每张 ♠ 额外 +20 筹码",
}


static func ai_passive_text(ai_id: String) -> String:
	return str(AI_PASSIVE.get(ai_id, ""))


## 牌型小抄（界面左栏常驻）
static func cheat_sheet() -> Array:
	return [
		[Type.HIGH_CARD, "高牌"],
		[Type.PAIR, "一对"],
		[Type.TWO_PAIR, "两对"],
		[Type.THREE_KIND, "三条"],
		[Type.STRAIGHT, "顺子"],
		[Type.FLUSH, "同花"],
		[Type.FULL_HOUSE, "葫芦"],
		[Type.FOUR_KIND, "四条"],
		[Type.STRAIGHT_FLUSH, "同花顺"],
	]
