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
@export var power: int = 0
@export var rarity: Rarity = Rarity.COMMON
@export var min_chapter: int = 1


static func rarity_name(r: int) -> String:
	return RARITY_NAMES.get(r, "?")


static func rarity_color(r: int) -> Color:
	return RARITY_COLORS.get(r, Color(0.6, 0.6, 0.6))
