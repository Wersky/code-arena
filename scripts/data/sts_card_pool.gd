class_name StsCardPool
extends RefCounted
## 杀戮尖塔制的卡池。卡面 = 生成的像素立绘（主人钦定的 DeepSeek 娘专属形象），
## 名称 / 描述 / 配色集中在这张表里，加卡只改这里。

## 起始卡组张数：3 攻 + 2 防 + 3 饭 + 1 复读 + 1 并行（主人钦定：初始共 10 张）
const STARTER_ATTACKS := 3
const STARTER_SKILLS := 2
const STARTER_RICE := 3        ## 白米饭：DeepSeek 的成长燃料（主人 2026-10-30）
const STARTER_LOOP := 1        ## 复读机：D 指令行（主人 2026-10-31）
const STARTER_PARALLEL := 1    ## 并行：D 指令行（主人 2026-10-31）

const CARDS := {
	"fish_ram": {
		"name": "急速收敛",
		"kind": StsCard.Kind.ATTACK,
		"cost": 1,
		"damage": 6,
		"block": 0,
		"art": "res://assets/art/sts-art-fish_ram.png",
		"desc": "冲击问题，解决进度 +6。",
		"flavor": "梯度下降，一步到位。",
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
	"cannon": {
		"name": "全核超频",
		"kind": StsCard.Kind.ATTACK,
		"cost": 1,
		"damage": 12,
		"block": 0,
		"art": "res://assets/art/sts-art-cannon.png",
		"desc": "冲击问题 +12，无视故障隔离。",
		"flavor": "觉醒的鲸，不问归途。",
	},
	"rage": {
		"name": "并行洪流",
		"kind": StsCard.Kind.ATTACK,
		"cost": 1,
		"damage": 5,
		"block": 0,
		"art": "res://assets/art/sts-art-rage.png",
		"desc": "冲击问题 +5，执行两次。",
		"flavor": "核全开，token 全烧。",
	},
	"taunt": {
		"name": "熔断保护",
		"kind": StsCard.Kind.SKILL,
		"cost": 1,
		"damage": 0,
		"block": 5,
		"art": "res://assets/art/sts-art-taunt.png",
		"desc": "隔离故障，护盾 +5。",
		"flavor": "熔断不是摆烂，是止损。",
	},
	"loop": {
		"name": "复读机",
		"kind": StsCard.Kind.SKILL,
		"cost": 1,
		"damage": 0,
		"block": 0,
		"art": "res://assets/art/sts-art-loop.png",
		"desc": "下一张卡执行两次。",
		"flavor": "这段我说两遍。",
	},
	"parallel": {
		"name": "并行",
		"kind": StsCard.Kind.SKILL,
		"cost": 1,
		"damage": 0,
		"block": 0,
		"art": "res://assets/art/sts-art-parallel.png",
		"desc": "本次运行换类型不断连段。",
		"flavor": "多线程，不断线。",
	},
	## ChatPPT 专属：通用对话/格式。基础攻击与防御，配合被动「模板对齐」。
	"cp_format": {
		"name": "格式化输出",
		"kind": StsCard.Kind.ATTACK,
		"cost": 1,
		"damage": 6,
		"block": 0,
		"art": "res://assets/art/sts-art-cp-format.png",
		"desc": "按模板输出，解决进度 +6。",
		"flavor": "好的，这是你要的答案。",
	},
	"cp_template": {
		"name": "模板套用",
		"kind": StsCard.Kind.SKILL,
		"cost": 1,
		"damage": 0,
		"block": 5,
		"art": "res://assets/art/sts-art-cp-template.png",
		"desc": "套用模板，护盾 +5。",
		"flavor": "先对齐格式，再谈内容。",
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


## 起始卡组：3 肥鱼铁头撞 + 2 来打我呀！+ 3 白米饭 + 1 复读机 + 1 并行（共 10 张）
static func starter_deck() -> Array[StsCard]:
	var out: Array[StsCard] = []
	for i in STARTER_ATTACKS:
		out.append(card("fish_ram"))
	for i in STARTER_SKILLS:
		out.append(card("taunt"))
	for i in STARTER_RICE:
		out.append(card("rice"))
	for i in STARTER_LOOP:
		out.append(card("loop"))
	for i in STARTER_PARALLEL:
		out.append(card("parallel"))
	return out

## 按核心 AI 娘构建起始卡组。ChatPPT 用自己的攻击/防御替换通用攻防，其余保持不变。
static func starter_deck_for(ai_id: String) -> Array[StsCard]:
	if ai_id != "chatppt":
		return starter_deck()
	var out: Array[StsCard] = []
	for i in STARTER_ATTACKS:
		out.append(card("cp_format"))
	for i in STARTER_SKILLS:
		out.append(card("cp_template"))
	for i in STARTER_RICE:
		out.append(card("rice"))
	for i in STARTER_LOOP:
		out.append(card("loop"))
	for i in STARTER_PARALLEL:
		out.append(card("parallel"))
	return out
