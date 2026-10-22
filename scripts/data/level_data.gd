class_name LevelData
extends Resource
## 一个关卡 = 一道 Benchmark 评测任务。
##
## rule_id 由 scoring.gd 解释（关卡特殊规则），rule_text 是给玩家看的说明。

enum Rule { NONE, HALF_PERSONA, NEED_FORMAT, NEED_KNOWLEDGE, DOUBLE_OVERFLOW, HALF_EXAMPLE, HALF_RISKY, NEED_TWO, BOSS }

@export var id: String = ""
@export var chapter: int = 1
@export var chapter_name: String = ""
@export var index_in_chapter: int = 0
@export var title: String = ""
@export var brief: String = ""
@export var target_score: int = 400
@export var turns: int = 3
@export var token_budget: int = 9
@export var rule: Rule = Rule.NONE
@export var rule_text: String = ""
@export var is_boss: bool = false
