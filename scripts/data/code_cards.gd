class_name CodeCard
extends Resource
## 代码卡数据表：**基础玩法的唯一数据源**（8 张纯代码卡）。
##
## 设计原则（2026-10-22 主人要求「简洁」后重做）：
##   · **只有代码卡**。没有饭卡/玄学/杂项/专属卡，没有 AI 娘主题加成。
##   · 每张卡就是一个**语句**，卡面写清它在程序里干什么。
##   · 8 种卡各 3 份 = 24 张牌库，凑对子的概率够高。
##
## 四种类型只用来给卡面上色、让玩家一眼分清"这是管循环的还是管出错的"：
##   循环 LOOP / 分支 BRANCH / 异常 EXCEPT / 语句 FLOW
##
## 静态 API（界面层只用这几个）：
##   CodeCard.all_cards()      -> Array[CodeCard]  全量 8 张
##   CodeCard.get_card(id)     -> CodeCard         按 id 取卡，取不到返回 null
##   CodeCard.kind_name(kind)  -> String           中文类型名
##   CodeCard.kind_color(kind) -> Color            卡面/片段配色

enum Kind { LOOP, BRANCH, EXCEPT, FLOW }

const KIND_NAMES := {
	Kind.LOOP: "循环",
	Kind.BRANCH: "分支",
	Kind.EXCEPT: "异常",
	Kind.FLOW: "语句",
}

const KIND_COLORS := {
	Kind.LOOP: Color(0.360, 0.730, 0.950),    # 蓝
	Kind.BRANCH: Color(0.960, 0.720, 0.300),  # 金
	Kind.EXCEPT: Color(0.960, 0.480, 0.520),  # 红
	Kind.FLOW: Color(0.560, 0.840, 0.620),    # 绿
}

## ── 单张卡 ─────────────────────────────────────────────
## 卡在程序里的唯一标识。**顺序语法规则按 id 判定**，不要随便改。
@export var id: String = ""
## 卡面显示名（也是命令行里打出来的片段文本）
@export var name: String = ""
@export var kind: int = Kind.FLOW
## 语法合法时的基础分
@export var base_score: int = 10
## 一句话注解：这张卡在程序里干什么
@export var flavor: String = ""


static func kind_name(k: int) -> String:
	return KIND_NAMES.get(k, "?")


static func kind_color(k: int) -> Color:
	return KIND_COLORS.get(k, Color(0.6, 0.6, 0.6))


# ── 静态池 ───────────────────────────────────────────────
static var _pool: Array[CodeCard] = []


static func all_cards() -> Array[CodeCard]:
	if _pool.is_empty():
		_pool = _build_pool()
	return _pool


static func get_card(card_id: String) -> CodeCard:
	for c in all_cards():
		if c.id == card_id:
			return c
	return null


static func cards_of_kind(k: int) -> Array[CodeCard]:
	var out: Array[CodeCard] = []
	for c in all_cards():
		if c.kind == k:
			out.append(c)
	return out


static func _c(id: String, name: String, kind: int, base: int, flavor: String) -> CodeCard:
	var c := CodeCard.new()
	c.id = id
	c.name = name
	c.kind = kind
	c.base_score = base
	c.flavor = flavor
	return c


## 8 张卡的唯一真值。
## 分值梯度：能独立成立的语句便宜（printf 9），需要配对的贵（try 14、while 12）。
static func _build_pool() -> Array[CodeCard]:
	return [
		# ── 循环 ──────────────────────────────────
		_c("while_kw", "while", Kind.LOOP, 12,
				"条件成立就一直转。必须接 if 当护栏。"),
		_c("for_kw", "for", Kind.LOOP, 10,
				"数着圈数转。跑够次数自己停。"),
		# ── 分支 ──────────────────────────────────
		_c("if_kw", "if", Kind.BRANCH, 10,
				"岔路口，走一条。while 的护栏就是它。"),
		_c("else_kw", "else", Kind.BRANCH, 8,
				"另一条路。前面必须先有 if。"),
		# ── 异常 ──────────────────────────────────
		_c("try_kw", "try", Kind.EXCEPT, 14,
				"先试着跑一遍。必须接 catch。"),
		_c("catch_kw", "catch", Kind.EXCEPT, 12,
				"炸了也有兜底。前面必须先有 try。"),
		# ── 语句 ──────────────────────────────────
		_c("printf", "printf", Kind.FLOW, 9,
				"打出来看看。哪都能放，不参与语法。"),
		_c("cache", "cache", Kind.FLOW, 10,
				"存一份，下次快。哪都能放，不参与语法。"),
	]
