class_name AiData
extends Resource
## 一位 AI 娘的核心人格数据。纯数据，无逻辑。

@export var id: String = ""
@export var display_name: String = ""
@export var family: String = ""
@export var tint_color: Color = Color.WHITE
@export var portrait_path: String = ""
@export var locked: bool = false
@export var taste_rules: PackedStringArray = PackedStringArray()
@export var intro_line: String = ""

# ── 可选扩展字段（不影响上述必填字段，UI 用）────────────
@export var bust_path: String = ""
@export var unlock_hint: String = ""
@export var prototype_note: String = ""
