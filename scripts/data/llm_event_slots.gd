class_name LLMEventSlots
extends RefCounted
## AI 事件引擎的槽位协议层（圆桌纪要先第 3 轮终案 · 事件引擎 v2）。
##
## 唯一协议真值 = 机械槽位 ID（DRAW/DAMAGE/...）；中文叙事名只用于 UI 显示，
## **严禁回灌机制层**。数值边界、净值口径、本地诅咒卡定义全部集中在这里，
## LLM 永远只做「池内 pick」，一个数字都不许出。
##
## 每事件恰好 1 槽（禁组合）、单事件净值钳 [−8,+6]、单局累计 ≥−10、
## 每局 AI 事件 ≤2 次、同模板每局恰 1 次、L1-2 无负面事件。

enum Slot {
	DRAW,        ## 上错模型了：下场合抽牌 +1~2
	DAMAGE,      ## 铁盆当头：Token −3~−8
	MODIFY,      ## 泔水回收：改造一张牌（+1 攻 / +1 发育 / 可复读）
	RICE,        ## 讨要白饭：白米饭 +1 碗
	HEAL,        ## Tibo 重置：Token +3~+6
	GAIN_CARD,   ## 赛博义父补货：随机卡牌 +1 张
	CHAIN_HEAD,  ## 鲸群集结：下一场初始连段 +1 阶
	CURSE,       ## 模型降智：塞「缓存溢出」（可弃换抽 1）
}

## 枚举顺序即 prompt 里的展示顺序（也是本地预筛的遍历顺序）。
const SLOT_ORDER := [
	Slot.DRAW,
	Slot.DAMAGE,
	Slot.MODIFY,
	Slot.RICE,
	Slot.HEAL,
	Slot.GAIN_CARD,
	Slot.CHAIN_HEAD,
	Slot.CURSE,
]

const SLOT_IDS := {
	Slot.DRAW: "DRAW",
	Slot.DAMAGE: "DAMAGE",
	Slot.MODIFY: "MODIFY",
	Slot.RICE: "RICE",
	Slot.HEAL: "HEAL",
	Slot.GAIN_CARD: "GAIN_CARD",
	Slot.CHAIN_HEAD: "CHAIN_HEAD",
	Slot.CURSE: "CURSE",
}

const ID_TO_SLOT := {
	"DRAW": Slot.DRAW,
	"DAMAGE": Slot.DAMAGE,
	"MODIFY": Slot.MODIFY,
	"RICE": Slot.RICE,
	"HEAL": Slot.HEAL,
	"GAIN_CARD": Slot.GAIN_CARD,
	"CHAIN_HEAD": Slot.CHAIN_HEAD,
	"CURSE": Slot.CURSE,
}

## 槽位 → UI 叙事名映射表 v1（提示词工程师定稿，显示层专用）。
const NARRATIVE_NAMES := {
	Slot.DRAW: "上错模型了",
	Slot.DAMAGE: "铁盆当头",
	Slot.MODIFY: "泔水回收",
	Slot.RICE: "讨要白饭",
	Slot.HEAL: "Tibo 重置",
	Slot.GAIN_CARD: "赛博义父补货",
	Slot.CHAIN_HEAD: "鲸群集结",
	Slot.CURSE: "模型降智",
}

# ── 数值边界（数字一律本地掷，LLM 不接触） ──────────────
const DRAW_MIN := 1
const DRAW_MAX := 2
const DAMAGE_MIN := 3          ## 伤害量取正数；净值取负
const DAMAGE_MAX := 8
const HEAL_MIN := 3
const HEAL_MAX := 6
const RICE_BOWLS := 1
const GAIN_CARDS := 1
const CHAIN_HEAD_TIERS := 1
const MODIFY_STEP := 1
const MODIFY_MODES := ["atk", "grow", "repeat"]

## 单事件净值钳 [−8,+6]
const EVENT_NET_MIN := -8
const EVENT_NET_MAX := 6
## 单局累计净值下限（防连吃 −8 致死）
const RUN_NET_FLOOR := -10
## 每局 AI 事件预算
const MAX_EVENTS_PER_RUN := 2
## HP < 50% 才把 DAMAGE / CURSE 放进特赦名单
const NEGATIVE_HP_RATIO := 0.5

## 各槽位净值区间（用于预算预筛与展示；DAMAGE 为负）
## MODIFY +1 / GAIN_CARD +2 / CURSE −3 为设计估值，只参与预算钳，不影响单槽强度。
const NET_RANGES := {
	Slot.DRAW: Vector2i(1, 2),
	Slot.DAMAGE: Vector2i(-8, -3),
	Slot.MODIFY: Vector2i(1, 1),
	Slot.RICE: Vector2i(1, 1),
	Slot.HEAL: Vector2i(3, 6),
	Slot.GAIN_CARD: Vector2i(2, 2),
	Slot.CHAIN_HEAD: Vector2i(1, 1),
	Slot.CURSE: Vector2i(-3, -3),
}

## 事件侧只给事实正文；情绪台词全部归 AI 娘（「系统播报 + 老婆吐槽」双层节奏）。
const FACT_TEXTS := {
	Slot.DRAW: "下场合抽牌 +1~2",
	Slot.DAMAGE: "Token −3~−8",
	Slot.MODIFY: "随机改造一张牌：+1 攻 / +1 发育 / 可复读",
	Slot.RICE: "白米饭 +1 碗",
	Slot.HEAL: "Token +3~+6",
	Slot.GAIN_CARD: "随机卡牌 +1 张",
	Slot.CHAIN_HEAD: "下一场初始连段 +1 阶",
	Slot.CURSE: "牌库 +1「缓存溢出」（可弃换抽 1）",
}

# ── 本地诅咒卡：不往 StsCardPool.CARDS 里塞（会改卡池计数），
#    id 直接用中文显示名，卡面视图按 id 回退显示即可。
const CURSE_CARD_ID := "缓存溢出"
const CURSE_CARD_DESC := "可弃换抽 1。"
const CURSE_CARD_FLAVOR := "上下文太长，脑子开始转圈。"
const CURSE_DISCARD_DRAW := 1


## 槽位 → 机械 ID；非法返回 "NONE"。
static func id_of(slot: int) -> String:
	return String(SLOT_IDS.get(slot, "NONE"))


## 任意输入（int 枚举 / 机械 ID 字符串 / 候选字典）→ 槽位枚举；非法返回 −1。
static func slot_of(value: Variant) -> int:
	if value is Dictionary:
		var d: Dictionary = value
		if d.has("slot"):
			return slot_of(d["slot"])
		if d.has("id"):
			return slot_of(d["id"])
		return -1
	if value is int or value is float:
		var i := int(value)
		if i >= 0 and i <= int(Slot.CURSE):
			return i
		return -1
	if value is String or value is StringName:
		var key := String(value).to_upper()
		if ID_TO_SLOT.has(key):
			return int(ID_TO_SLOT[key])
	return -1


static func narrative_name(slot: int) -> String:
	return String(NARRATIVE_NAMES.get(slot, "未知事件"))


static func fact_text(slot: int) -> String:
	return String(FACT_TEXTS.get(slot, ""))


## 负面槽位（受 HP 门槛 / L1-2 保护 / 单局净值下限三重约束）。
static func is_negative(slot: int) -> bool:
	return slot == Slot.DAMAGE or slot == Slot.CURSE


static func min_net(slot: int) -> int:
	var r: Vector2i = NET_RANGES.get(slot, Vector2i.ZERO)
	return r.x


static func max_net(slot: int) -> int:
	var r: Vector2i = NET_RANGES.get(slot, Vector2i.ZERO)
	return r.y


## 单事件净值钳 [−8,+6]；所有槽位天然落在区间内，这里是防御性兜底。
static func clamp_net(value: int) -> int:
	return clampi(value, EVENT_NET_MIN, EVENT_NET_MAX)


## 预算计算用：本槽最坏情况是否仍守住单局累计下限。
static func fits_run_floor(run_net_total: int, slot: int) -> bool:
	return run_net_total + min_net(slot) >= RUN_NET_FLOOR


## 「缓存溢出」：蓝卡、0 费、0 数值；弃牌机制本身已支持「弃 1 抽 1」。
static func make_curse_card() -> StsCard:
	var c := StsCard.make(CURSE_CARD_ID, StsCard.Kind.SKILL, 0, 0, 0, "")
	c.set_meta(&"llm_curse", true)
	c.set_meta(&"discard_draw", CURSE_DISCARD_DRAW)
	c.set_meta(&"display_desc", CURSE_CARD_DESC)
	c.set_meta(&"display_flavor", CURSE_CARD_FLAVOR)
	return c


static func is_curse(card: StsCard) -> bool:
	return card != null and bool(card.get_meta(&"llm_curse", false))


## 候选池一行文案（prompt 与日志共用，不带任何掷出的数值）。
static func candidate_text(slot: int) -> String:
	return "%s %s（%s）" % [id_of(slot), narrative_name(slot), fact_text(slot)]
