class_name LevelData
extends Resource
## 一个关卡 = 一场杀戮尖塔式战斗（2026-10-25 大改，取代旧 Benchmark 评测）。
##
## 敌人是 AI 世界的捣蛋鬼：幻觉、过拟合、上下文丢失、Token 超限……
## 敌人意图 = 攻击/防御的循环模式（见 enemy_pattern()）。

@export var id: String = ""
@export var chapter: int = 1
@export var chapter_name: String = ""
@export var index_in_chapter: int = 0
@export var title: String = ""
@export var brief: String = ""
@export var enemy_name: String = ""
@export var enemy_hp: int = 40
@export var enemy_atk: int = 7
@export var enemy_def: int = 5
@export var enemy_tint: Color = Color(0.784, 0.298, 0.298)
@export var is_boss: bool = false
## 【特殊怪物】(2026-11-11 主人要求)：不走程序化像素贴图，直接用一张真实立绘。
## 空串 = 原有程序化像素图（其余关卡都是空串，零改动）。
@export var enemy_art: String = ""
## 特殊怪物标签（UI 上显示「【特殊怪物】」）
@export var is_special: bool = false
## 敌人技能 id（空 = 无技能）。目前只有 "ban" = 封号大王。
@export var enemy_skill: String = ""


## 敌人意图序列（循环）：攻 → 防 → 攻（BOSS 同节奏但数值更高）
## 带技能的敌人（封号大王）走另一套循环：攻 → 防 → 封号 → 攻（见 LevelPool.ban_pattern）
func enemy_pattern() -> Array:
	if enemy_skill == "ban":
		return LevelPool.ban_pattern(enemy_atk, enemy_def)
	var a := {"kind": "attack", "value": enemy_atk}
	var d := {"kind": "defend", "value": enemy_def}
	return [a, d, a.duplicate()]
