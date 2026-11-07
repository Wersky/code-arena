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
## 出牌额外抽牌数（许愿卡超限档用；普通卡恒 0）
@export var draw := 0
## 效果程序（EffectDSL 编译后的 AST）。空数组 = 旧行为，零开销。
@export var effects: Array = []
## 程序规格版本：0 = 无程序。老卡按旧版本解释器跑，不静默迁移。
@export var dsl_version := 0
## 定价档位（1–3；0 = 未定价）。许愿卡出卡时先给保守上界，离线批次跑完查表校正。
@export var price_tier := 0


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
