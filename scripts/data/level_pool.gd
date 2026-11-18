class_name LevelPool
extends RefCounted
## 关卡表：10 场战斗，4 章（2026-10-25 大改：杀戮尖塔制）。
##
## 一关 = 一个 AI 世界里的捣蛋鬼。难度曲线靠 敌人HP/攻击/防御 三个数字抬：
## 起始卡组 3 攻 2 防（6 伤/5 挡，每回合 3 能量 → 理论上限 18 伤/回合），
## 曲线按「~4~8 回合解决战斗、被打 2~5 下」标定。

const TINTS := {
	"bug": Color(0.784, 0.298, 0.298),      # 幻觉虫 · 红
	"lizard": Color(0.839, 0.545, 0.239),   # 过拟合蜥 · 橙
	"ghost": Color(0.427, 0.553, 0.839),    # 上下文幽灵 · 蓝
	"golem": Color(0.443, 0.639, 0.486),    # Token 魔像 · 绿
	"core": Color(0.639, 0.388, 0.815),     # 天网核心 · 紫
}


static func _lv(id: String, chapter: int, chapter_name: String, idx: int,
		title: String, brief: String, e_name: String, e_hp: int, e_atk: int,
		e_def: int, tint_key: String, boss: bool = false) -> LevelData:
	var l := LevelData.new()
	l.id = id
	l.chapter = chapter
	l.chapter_name = chapter_name
	l.index_in_chapter = idx
	l.title = title
	l.brief = brief
	l.enemy_name = e_name
	l.enemy_hp = e_hp
	l.enemy_atk = e_atk
	l.enemy_def = e_def
	l.enemy_tint = TINTS.get(tint_key, TINTS["bug"])
	l.is_boss = boss
	return l


## 【特殊怪物】封号大王（2026-11-11 主人要求）：
## 不用程序化像素图，直接用主人给的立绘；带技能「封号」。
## 意图循环多一拍 skill：攻 → 防 → 封号 → 攻（见 ban_pattern）。
const BAN_ART := "res://assets/art/enemy-fenghao-dawang.png"
const SKILL_BAN := "ban"


static func _special_ban() -> LevelData:
	var l := _lv("L0", 1, "幻觉滋生", 0, "第一战 · 封号大王",
			"它抬手一指，你的输出就没了。",
			"封号大王", 55, 6, 4, "bug", false)
	l.enemy_art = BAN_ART
	l.is_special = true
	l.enemy_skill = SKILL_BAN
	return l


## 封号大王的意图循环：攻 → 防 → 封号 → 攻 …
## 封号那一拍 value=0（不造成伤害，纯粹开技能）
static func ban_pattern(atk: int, def: int) -> Array:
	return [
		{"kind": "attack", "value": atk},
		{"kind": "defend", "value": def},
		{"kind": "skill", "value": 0, "skill": SKILL_BAN},
		{"kind": "attack", "value": atk},
	]


static func all_levels() -> Array[LevelData]:
	return [
		# ── 第 1 章 · 幻觉滋生 ─────────────────────────────
		# 首战 = 特殊怪物封号大王（2026-11-11 主人要求）
		_special_ban(),
		_lv("L1", 1, "幻觉滋生", 1, "第一只幻觉",
			"它一本正经地胡说八道。撞它！",
			"幻觉幼虫", 40, 7, 4, "bug"),
		_lv("L2", 1, "幻觉滋生", 2, "引用编造",
			"论文链接全是编的，伤害却是真的。",
			"幻觉成虫", 60, 8, 5, "bug"),
		_lv("L3", 1, "幻觉滋生", 3, "置信满格",
			"它说自己 100% 确定。撞到它怀疑虫生。",
			"满格幻觉", 76, 9, 6, "bug"),

		# ── 第 2 章 · 过拟合 ───────────────────────────────
		_lv("L4", 2, "过拟合", 1, "背题怪物",
			"训练集倒背如流，新题一题不会。",
			"过拟合巨蜥", 92, 10, 6, "lizard"),
		_lv("L5", 2, "过拟合", 2, "验证集塌方",
			"它的防御来自死记硬背，撞开就好。",
			"过拟合巨蜥·改", 110, 11, 7, "lizard"),
		_lv("L6", 2, "过拟合", 3, "梯度消失",
			"越训越笨的庞然大物。",
			"梯度消失兽", 126, 12, 8, "lizard"),

		# ── 第 3 章 · 上下文崩坏 ───────────────────────────
		_lv("L7", 3, "上下文崩坏", 1, "断片",
			"话说到一半被掐断的怨灵。",
			"断片", 130, 13, 8, "ghost"),
		_lv("L8", 3, "上下文崩坏", 2, "Token 超限",
			"话说到一半被掐断的怨灵。",
			"Token 超限魔像", 138, 12, 8, "golem"),

		# ── 第 4 章 · 天网 ─────────────────────────────────
		_lv("L9", 4, "天网", 1, "哨兵",
			"天网的看门狗，先过它这关。",
			"天网哨兵", 140, 12, 8, "core"),
		_lv("L10", 4, "天网", 2, "天网核心",
			"一切捣蛋鬼的源头。把它撞下线！",
			"天网核心", 146, 13, 8, "core", true),
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
