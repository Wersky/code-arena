class_name StsCard
extends Resource
## 杀戮尖塔制的一张卡（2026-10-25 大改：取代德州扑克机制）。
##
## 只存数值与资源路径；名字/描述/配色在 StsCardPool 的表里查，
## 这样以后加卡只改一处数据表。

enum Kind { ATTACK, SKILL }


@export var id := ""
@export var kind: int = Kind.ATTACK
@export var cost := 1
@export var damage := 0
@export var block := 0
@export var art_path := ""


static func make(card_id: String, card_kind: int, card_cost: int,
		dmg: int, blk: int, art: String) -> StsCard:
	var c := StsCard.new()
	c.id = card_id
	c.kind = card_kind
	c.cost = card_cost
	c.damage = dmg
	c.block = blk
	c.art_path = art
	return c
