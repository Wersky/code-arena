class_name StsCardPool
extends RefCounted
## 杀戮尖塔制的卡池。卡面 = 生成的像素立绘（主人钦定的 DeepSeek 娘专属形象），
## 名称 / 描述 / 配色集中在这张表里，加卡只改这里。

## 起始卡组张数：3 攻 + 2 防（主人钦定：初始共 5 张）
const STARTER_ATTACKS := 3
const STARTER_SKILLS := 2
const STARTER_RICE := 3        ## 白米饭：DeepSeek 的成长燃料（主人 2026-10-30）

const CARDS := {
	"fish_ram": {
		"name": "肥鱼铁头撞",
		"kind": StsCard.Kind.ATTACK,
		"cost": 1,
		"damage": 6,
		"block": 0,
		"art": "res://assets/art/sts-art-fish_ram.png",
		"desc": "造成 6 点伤害。",
		"flavor": "全速前进！",
	},
	"rice": {
		"name": "白米饭",
		"kind": StsCard.Kind.SKILL,
		"cost": 0,
		"damage": 0,
		"block": 0,
		"art": "res://assets/art/sts-art-rice.png",
		"desc": "神奇的白米饭。",
		"flavor": "碳水才是本体。",
	},
	"taunt": {
		"name": "来打我呀！",
		"kind": StsCard.Kind.SKILL,
		"cost": 1,
		"damage": 0,
		"block": 5,
		"art": "res://assets/art/sts-art-taunt.png",
		"desc": "获得 5 点格挡。",
		"flavor": "锅在头，不慌。",
	},
}

const KIND_NAMES := {
	StsCard.Kind.ATTACK: "攻击",
	StsCard.Kind.SKILL: "防御",
}

const KIND_COLORS := {
	StsCard.Kind.ATTACK: Color(0.784, 0.298, 0.298),   # #c84c4c 红
	StsCard.Kind.SKILL: Color(0.310, 0.639, 0.878),    # #4fa3e0 蓝
}


static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for k in CARDS.keys():
		out.append(String(k))
	return out


static func card(card_id: String) -> StsCard:
	var d: Dictionary = CARDS.get(card_id, {})
	if d.is_empty():
		return null
	return StsCard.make(card_id, int(d["kind"]), int(d["cost"]),
			int(d["damage"]), int(d["block"]), String(d["art"]))


static func card_name(card_id: String) -> String:
	var d: Dictionary = CARDS.get(card_id, {})
	return String(d.get("name", card_id))


static func desc(card_id: String) -> String:
	var d: Dictionary = CARDS.get(card_id, {})
	return String(d.get("desc", ""))


static func kind_name(k: int) -> String:
	return String(KIND_NAMES.get(k, "?"))


static func kind_color(k: int) -> Color:
	return KIND_COLORS.get(k, Color.WHITE)


## 起始卡组：3 张肥鱼铁头撞 + 2 张来打我呀！+ 3 张白米饭
static func starter_deck() -> Array[StsCard]:
	var out: Array[StsCard] = []
	for i in STARTER_ATTACKS:
		out.append(card("fish_ram"))
	for i in STARTER_SKILLS:
		out.append(card("taunt"))
	for i in STARTER_RICE:
		out.append(card("rice"))
	return out
