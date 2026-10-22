class_name LevelPool
extends RefCounted
## 关卡表：10 关，4 章。
##
## 一关只有 **目标分 + 出牌次数** 两个数字。没有特殊规则、没有 Token。
##
## ★ 目标分刻度（扑克玩法 · chips × mult）
##   单手的量级：高牌 ~40、一对 ~130、三条 ~470、同花 ~950。
##   一关 3~7 手 → 目标分落在 **2000~5300**。
##   校准口径：120 局快速模拟（seedstep=7919），目标分取 q08~q10 之间。
##   验收线：每关通过率 82%~98%、整局通关率 35%~55%。
##   复算：
##     godot --headless --path . --script res://tools/balance_sim2.gd -- --sims=120

const R := LevelData.Rule


static func _lv(id: String, chapter: int, chapter_name: String, idx: int, title: String,
		brief: String, target: int, hands: int, boss: bool = false) -> LevelData:
	var l := LevelData.new()
	l.id = id
	l.chapter = chapter
	l.chapter_name = chapter_name
	l.index_in_chapter = idx
	l.title = title
	l.brief = brief
	l.target_score = target
	l.turns = hands
	l.token_budget = 0
	l.rule = R.NONE
	l.is_boss = boss
	return l


static func all_levels() -> Array[LevelData]:
	return [
		# ── 第 1 章 · 摸牌 ────────────────────────────────
		_lv("L1", 1, "摸牌", 1, "起手",
			"先随便打一手。红牌加倍率，黑牌加筹码。",
			2050, 3),
		_lv("L2", 1, "摸牌", 2, "凑一对",
			"两张同点数的牌就是一对，比单张强得多。",
			2100, 3),
		_lv("L3", 1, "摸牌", 3, "凑两对",
			"两对分开算，比一对多一倍基础筹码。",
			2850, 4),

		# ── 第 2 章 · 成型 ────────────────────────────────
		_lv("L4", 2, "成型", 1, "三条",
			"三张同点数：基础 30×3。",
			2950, 4),
		_lv("L5", 2, "成型", 2, "顺子",
			"五张连号的牌。点数越高越值钱。",
			3650, 5),
		_lv("L6", 2, "成型", 3, "同花",
			"五张同花色。全红 = 倍率爆炸，全黑 = 筹码爆炸。",
			3700, 5),

		# ── 第 3 章 · 高压 ────────────────────────────────
		_lv("L7", 3, "高压", 1, "葫芦",
			"三条 + 一对：40×4，稳定产分。",
			4450, 6),
		_lv("L8", 3, "高压", 2, "四条",
			"四张同点数：60×7。牌库不够厚就凑不出来。",
			4550, 6),
		_lv("L9", 3, "高压", 3, "同花顺",
			"五张连号又同花：100×8。看到了就别放过。",
			5200, 7),

		# ── 第 4 章 · 终局 ────────────────────────────────
		_lv("L10", 4, "终局", 1, "终局",
			"最后一关。每一手都要打出成型牌型。",
			5220, 7, true),
	]


static func get_level(id: String) -> LevelData:
	for l in all_levels():
		if l.id == id:
			return l
	return null


static func levels_of_chapter(chapter: int) -> Array[LevelData]:
	var out: Array[LevelData] = []
	for l in all_levels():
		if l.chapter == chapter:
			out.append(l)
	return out
