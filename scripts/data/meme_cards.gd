class_name MemeCard
extends Resource
## 梗卡数据表：新卡牌机制的唯一数据源（20 张牌 + 4 位 AI 娘主题加成表）。
##
## 与旧机制（CardData / CardPool / 命令行片段）**完全平行、互不影响**：
## 梗卡没有命令行片段，只有"梗注解"（flavor），任何一张卡都能一眼看懂。
##
## 术语：
##   kind          卡类型：饭 / 代码 / 玄学 / 杂项 / 专属
##   unique_owner  专属归属的 AI 娘主题 id（"" = 谁都能用）；专属卡只在该主题下可用
##   flavor        梗注解（tooltip 文案），一行说清这张卡为什么好笑
##
## 静态 API（下游界面层只用这几个）：
##   MemeCard.all_cards()            -> Array[MemeCard]   全量 20 张
##   MemeCard.get_card(id)           -> MemeCard          按 id 取卡，取不到返回 null
##   MemeCard.themes()               -> Array[Dictionary] 4 位 AI 娘主题表
##   MemeCard.get_theme(id)          -> Dictionary        按 id 取主题，取不到返回 {}
##   MemeCard.theme_ids()            -> Array[String]
##   MemeCard.kind_name(kind)        -> String            中文类型名
##   MemeCard.kind_color(kind)       -> Color
##   MemeCard.card_allowed_in(theme_id, card) -> bool      专属卡的主题可用性判定

enum Kind { FOOD, CODE, MYSTIC, MISC, EXCLUSIVE }

const KIND_NAMES := {
	Kind.FOOD: "饭",
	Kind.CODE: "代码",
	Kind.MYSTIC: "玄学",
	Kind.MISC: "杂项",
	Kind.EXCLUSIVE: "专属",
}

## 英文 kind key，供连携表按类型做倍率（kind_mult）时使用
const KIND_KEYS := {
	Kind.FOOD: "food",
	Kind.CODE: "code",
	Kind.MYSTIC: "mystic",
	Kind.MISC: "misc",
	Kind.EXCLUSIVE: "exclusive",
}

const KIND_COLORS := {
	Kind.FOOD: Color(0.960, 0.760, 0.360),
	Kind.CODE: Color(0.360, 0.730, 0.950),
	Kind.MYSTIC: Color(0.760, 0.560, 0.960),
	Kind.MISC: Color(0.560, 0.820, 0.560),
	Kind.EXCLUSIVE: Color(0.960, 0.480, 0.520),
}

## ── 单张卡 ─────────────────────────────────────────────
@export var id: String = ""
@export var name: String = ""
@export var kind: int = Kind.MISC
@export var base_score: int = 10
@export var token_cost: int = 1
@export var flavor: String = ""
## 专属卡的归属主题 id（"" = 通用卡）
@export var unique_owner: String = ""


static func kind_name(k: int) -> String:
	return KIND_NAMES.get(k, "?")


static func kind_color(k: int) -> Color:
	return KIND_COLORS.get(k, Color(0.6, 0.6, 0.6))


static func kind_key(k: int) -> String:
	return KIND_KEYS.get(k, "misc")


# ── 静态池 ───────────────────────────────────────────────
static var _pool: Array[MemeCard] = []


## 全量 20 张（通用 16 + 专属 4），顺序即牌组表顺序
static func all_cards() -> Array[MemeCard]:
	if _pool.is_empty():
		_pool = _build_pool()
	return _pool


static func get_card(card_id: String) -> MemeCard:
	for c in all_cards():
		if c.id == card_id:
			return c
	return null


static func cards_of_kind(k: int) -> Array[MemeCard]:
	var out: Array[MemeCard] = []
	for c in all_cards():
		if c.kind == k:
			out.append(c)
	return out


## 该主题下可用的牌（通用牌 + 该主题专属牌）
static func cards_for_theme(theme_id: String) -> Array[MemeCard]:
	var out: Array[MemeCard] = []
	for c in all_cards():
		if card_allowed_in(theme_id, c):
			out.append(c)
	return out


## 专属卡只在对应主题下可用
static func card_allowed_in(theme_id: String, card: MemeCard) -> bool:
	if card == null:
		return false
	if card.unique_owner == "":
		return true
	return card.unique_owner == theme_id


static func _c(id: String, name: String, kind: int, base: int, token: int,
		flavor: String, owner: String = "") -> MemeCard:
	var c := MemeCard.new()
	c.id = id
	c.name = name
	c.kind = kind
	c.base_score = base
	c.token_cost = token
	c.flavor = flavor
	c.unique_owner = owner
	return c


static func _build_pool() -> Array[MemeCard]:
	var out: Array[MemeCard] = []
	# ── 通用 16 张 ───────────────────────────────
	out.append(_c("rice", "白米饭", Kind.FOOD, 12, 1, "大肥鱼的主食，热量与快乐同在"))
	out.append(_c("mantou", "馒头", Kind.FOOD, 10, 1, "比米饭顶饱，就是没什么味道"))
	out.append(_c("hotpot", "火锅", Kind.FOOD, 16, 2, "干饭人的梦想，涮什么都行"))
	out.append(_c("foodie", "干饭人", Kind.FOOD, 14, 1, "干饭界的精神图腾，看到锅就想坐"))
	out.append(_c("while_kw", "while", Kind.CODE, 12, 1, "循环体的爹，能转到你怀疑人生"))
	out.append(_c("for_kw", "for", Kind.CODE, 11, 1, "定量循环，个数说得清"))
	out.append(_c("if_kw", "if", Kind.CODE, 10, 1, "分支的一半"))
	out.append(_c("else_kw", "else", Kind.CODE, 10, 1, "分支的另一半"))
	out.append(_c("recursion", "递归", Kind.CODE, 15, 2, "自己调自己，套娃永动机"))
	out.append(_c("try_kw", "try", Kind.CODE, 10, 1, "试一下，大不了再说"))
	out.append(_c("catch_kw", "catch", Kind.CODE, 12, 1, "兜住异常的老好人"))
	out.append(_c("printf", "printf", Kind.CODE, 9, 1, "打印，屏幕上全是它"))
	out.append(_c("deadlock", "死锁", Kind.CODE, 13, 2, "两个 while 互相等，谁也不动"))
	out.append(_c("illusion", "幻觉", Kind.MYSTIC, 14, 2, "一本正经胡说八道，还特别自信"))
	out.append(_c("temp", "温度", Kind.MYSTIC, 11, 1, "调高就放飞，调低就保守"))
	out.append(_c("emerge", "涌现", Kind.MYSTIC, 15, 2, "玄学中的玄学，说不清但确实发生"))
	out.append(_c("context", "上下文", Kind.MISC, 12, 2, "越长越贵，还容易忘"))
	out.append(_c("cache", "缓存", Kind.MISC, 11, 1, "命中就省钱"))
	out.append(_c("token", "token", Kind.MISC, 10, 1, "你的钱在燃烧"))
	# ── DeepSeek（大肥鱼）专属 4 张 ───────────────
	out.append(_c("bigfish", "大肥鱼", Kind.EXCLUSIVE, 20, 2, "蓝色的大肥鱼，爱吃白米饭，能吃", "deepdeek"))
	out.append(_c("rice_freedom", "白米饭自由", Kind.EXCLUSIVE, 18, 2, "想吃多少吃多少，代价是长胖", "deepdeek"))
	out.append(_c("binge", "暴食", Kind.EXCLUSIVE, 17, 2, "吃到扶墙出，扶着墙也还要吃", "deepdeek"))
	out.append(_c("deepfish", "深海鱼", Kind.EXCLUSIVE, 15, 2, "大肥鱼的远亲，同样不爱运动", "deepdeek"))
	return out


# ── 主题（AI 娘）加成表 ──────────────────────────────────
## bonus_kinds：享受该主题加成的卡类型（-1 = 所有类型）
## bonus_mult：该类型卡的**基础分**倍率
## bonus_flat：该类型卡额外加的固定分
static var _themes: Array[Dictionary] = []


static func themes() -> Array[Dictionary]:
	if _themes.is_empty():
		_themes = _build_themes()
	return _themes


static func get_theme(theme_id: String) -> Dictionary:
	for t in themes():
		if str(t.get("id", "")) == theme_id:
			return t
	return {}


static func theme_ids() -> Array[String]:
	var out: Array[String] = []
	for t in themes():
		out.append(str(t.get("id", "")))
	return out


## 该主题给这张卡的基础分倍率与固定加分
static func theme_bonus(theme_id: String, card: MemeCard) -> Dictionary:
	var t := get_theme(theme_id)
	if t.is_empty() or card == null:
		return {"mult": 1.0, "flat": 0}
	var kinds: Array = t.get("bonus_kinds", [])
	var hit := kinds.has(-1) or kinds.has(card.kind)
	if not hit:
		return {"mult": 1.0, "flat": 0}
	return {
		"mult": float(t.get("bonus_mult", 1.0)),
		"flat": int(t.get("bonus_flat", 0)),
	}


static func _build_themes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({
		"id": "deepdeek",
		"display_name": "DeepDeek",
		"prototype": "deepseek",
		"theme": "大肥鱼·吃白饭",
		"bonus_kinds": [Kind.FOOD],
		"bonus_mult": 1.3,
		"bonus_flat": 0,
		"unlock_exclusive": true,
		"desc": "饭类卡基础分 ×1.3（且解锁 4 张专属卡）",
		"tint": Color(0.310, 0.757, 0.965),
		"lines": [
			"先吃两口白米饭，再谈推理。",
			"我的肚子比我的上下文还长。",
			"饭可以晚点吃，bug 不能。",
		],
	})
	out.append({
		"id": "gemigo",
		"display_name": "Gemigo",
		"prototype": "gemini",
		"theme": "故障机器猫",
		"bonus_kinds": [Kind.MYSTIC],
		"bonus_mult": 1.3,
		"bonus_flat": 0,
		"unlock_exclusive": false,
		"desc": "玄学类卡基础分 ×1.3",
		"tint": Color(0.780, 0.470, 0.960),
		"lines": [
			"我也不知道为什么对，但就是对。",
			"概率上不存在的答案，正在向你走来。",
			"喵——不对，喵是别人。我只是偶尔抖一下。",
		],
	})
	out.append({
		"id": "grock",
		"display_name": "Grock",
		"prototype": "grok",
		"theme": "毒舌千金",
		"bonus_kinds": [Kind.CODE],
		"bonus_mult": 1.3,
		"bonus_flat": 0,
		"unlock_exclusive": false,
		"desc": "代码类卡基础分 ×1.3",
		"tint": Color(0.478, 0.792, 0.443),
		"lines": [
			"就这？连个 while 都不会写。",
			"你的代码能跑，说明运气还行。",
			"我夸你一句，你会截图发朋友圈吧。",
		],
	})
	out.append({
		"id": "kweno",
		"display_name": "Kweno",
		"prototype": "qwen",
		"theme": "元气大小姐",
		"bonus_kinds": [-1],
		"bonus_mult": 1.0,
		"bonus_flat": 8,
		"unlock_exclusive": false,
		"desc": "所有卡基础分 +8",
		"tint": Color(1.000, 0.820, 0.400),
		"lines": [
			"一起吃饭呀！分数我帮你加满！",
			"这张卡看起来就很厉害的样子！",
			"哎呀，token 不够啦？都怪你点太快！",
		],
	})
	return out
