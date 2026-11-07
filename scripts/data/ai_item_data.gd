class_name AiItemData
extends Resource
## AI 道具（对应小丑牌的"小丑牌"）。每件改写一条永久规则。
##
## effect_id 由 scoring.gd 的效果表解释；power 是该效果的数值参数。

enum Rarity { COMMON, RARE, EPIC }

const RARITY_NAMES := {
	Rarity.COMMON: "常见",
	Rarity.RARE: "少见",
	Rarity.EPIC: "稀有",
}

const RARITY_COLORS := {
	Rarity.COMMON: Color(0.62, 0.66, 0.70),
	Rarity.RARE: Color(0.36, 0.62, 0.90),
	Rarity.EPIC: Color(0.72, 0.46, 0.90),
}

@export var id: String = ""
@export var display_name: String = ""
@export var family: String = ""
@export var description: String = ""
@export var effect_id: String = ""
## 分类（2026-11-04 主人钦定）：skill=AI 自身能力 / mcp=外挂工具服务
@export var category: String = "skill"
@export var power: int = 0
@export var rarity: Rarity = Rarity.COMMON
@export var min_chapter: int = 1
@export var art_path: String = ""
## 耐用型道具的剩余场次（-1 = 无限）；0 = 损坏
@export var charges := -1
## 是否已损坏（本局内不再生效）
@export var broken := false


static func rarity_name(r: int) -> String:
	return RARITY_NAMES.get(r, "?")


static func rarity_color(r: int) -> Color:
	return RARITY_COLORS.get(r, Color(0.6, 0.6, 0.6))
