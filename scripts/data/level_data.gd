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


## 敌人意图序列（循环）：攻 → 防 → 攻（BOSS 同节奏但数值更高）
func enemy_pattern() -> Array:
	var a := {"kind": "attack", "value": enemy_atk}
	var d := {"kind": "defend", "value": enemy_def}
	return [a, d, a.duplicate()]
