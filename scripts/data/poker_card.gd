class_name PokerCard
extends Resource
## 一张扑克牌：花色 + 点数。**当前玩法的唯一数据单位。**
##
## 花色分两种颜色（决定了这张牌给什么）：
##   红（红心 ♥ / 方块 ♦）→ 加**倍率**
##   黑（黑桃 ♠ / 梅花 ♣）→ 加**筹码**
##
## 牌面：中间是**该花色对应的角色**（形象由花色决定，与选了哪位 AI 娘无关），
##       四角是花色符号 + 点数，由 CardView 叠 `pips-<suit>-<rank>` 层画。
##
## 卡图资源：assets/art/card-<suit>-<rank>.png（角色层）+ pips-<suit>-<rank>.png（角标层），
##           4 花色 × 13 点数 = 52 张牌，见 tools/make_card_assets.py。
##           旧版 poker-<ai_id>-<suit>.png（16 张满幅插画）已退出主流程，仅存档。

enum Suit { HEART, DIAMOND, SPADE, CLUB }

const SUIT_NAMES := {
	Suit.HEART: "红心",
	Suit.DIAMOND: "方块",
	Suit.SPADE: "黑桃",
	Suit.CLUB: "梅花",
}

## 花色符号（用系统字体绘制，不依赖卡图）
const SUIT_SYMBOLS := {
	Suit.HEART: "♥",
	Suit.DIAMOND: "♦",
	Suit.SPADE: "♠",
	Suit.CLUB: "♣",
}

## 花色 slug（卡图文件名用）
const SUIT_SLUGS := {
	Suit.HEART: "heart",
	Suit.DIAMOND: "diamond",
	Suit.SPADE: "spade",
	Suit.CLUB: "club",
}

const SUIT_COLORS := {
	Suit.HEART: Color(0.960, 0.360, 0.400),
	Suit.DIAMOND: Color(0.980, 0.580, 0.300),
	Suit.SPADE: Color(0.640, 0.720, 0.880),
	Suit.CLUB: Color(0.480, 0.800, 0.560),
}

@export var suit: int = Suit.HEART
@export var rank: int = 1


static func suit_name(s: int) -> String:
	return SUIT_NAMES.get(s, "?")


static func suit_symbol(s: int) -> String:
	return SUIT_SYMBOLS.get(s, "?")


static func suit_slug(s: int) -> String:
	return SUIT_SLUGS.get(s, "?")


static func suit_color(s: int) -> Color:
	return SUIT_COLORS.get(s, Color(0.7, 0.7, 0.7))


## 红色 = 加倍率，黑色 = 加筹码。这是整个玩法的颜色规则。
static func is_red(s: int) -> bool:
	return s == Suit.HEART or s == Suit.DIAMOND


static func make(s: int, r: int) -> PokerCard:
	var c := PokerCard.new()
	c.suit = s
	c.rank = r
	return c


## 唯一 id，形如 "H3" / "S9"
func id() -> String:
	var k := "H"
	match suit:
		Suit.DIAMOND: k = "D"
		Suit.SPADE: k = "S"
		Suit.CLUB: k = "C"
	return "%s%d" % [k, rank]


func display_name() -> String:
	return "%s%s" % [suit_symbol(suit), str(rank)]


## 卡图资源名（旧版满幅插画，4 位 AI娘 × 4 花色 = 16 张）。
## **已退出主流程**，只留作存档与降级参考；新卡面用 face_name() / pips_name()。
func art_name(ai_id: String) -> String:
	return "poker-%s-%s" % [ai_id, suit_slug(suit)]


## 角色层：`card-<suit>-<rank>`，只有角色，150×226 透明底。
## 由 tools/make_card_assets.py 从 docs/shots/ 样张抠出来（形象由**花色**决定）。
func face_name() -> String:
	return "card-%s-%d" % [suit_slug(suit), rank]


## 角标层：`pips-<suit>-<rank>`，四角花色+点数，150×226 透明底，位置与样张一致。
func pips_name() -> String:
	return "pips-%s-%d" % [suit_slug(suit), rank]
