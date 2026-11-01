class_name StsItemPool
extends RefCounted
## 道具池（2026-11-01 主人钦定）：三件被动道具，战斗内由 StsCombat 消费效果。

const ITEMS := {
	"prompt_opt": {
		"name": "提示词优化器",
		"desc": "所有攻击牌伤害 +2。措辞更精准，打得更痛。",
		"effect_id": "prompt_opt",
		"power": 2,
		"art": "res://assets/art/item-prompt-opt.png",
		"rarity": 1,
	},
	"subagent": {
		"name": "子代理零件",
		"desc": "弃牌模式不限次数。小代理们帮你无限整理队列。",
		"effect_id": "subagent",
		"power": 1,
		"art": "res://assets/art/item-subagent.png",
		"rarity": 1,
	},
	"compress": {
		"name": "上下文压缩",
		"desc": "手牌上限 +1。压缩上下文，腾出更多空间。",
		"effect_id": "compress",
		"power": 1,
		"art": "res://assets/art/item-compress.png",
		"rarity": 1,
	},
}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in ITEMS.keys():
		out.append(String(k))
	return out


static func make(item_id: String) -> AiItemData:
	var d: Dictionary = ITEMS.get(item_id, {})
	if d.is_empty():
		return null
	var it := AiItemData.new()
	it.id = item_id
	it.display_name = String(d["name"])
	it.description = String(d["desc"])
	it.effect_id = String(d["effect_id"])
	it.power = int(d["power"])
	it.rarity = int(d["rarity"])
	it.art_path = String(d["art"])
	return it


static func random_id(rng: RandomNumberGenerator) -> String:
	var ids := ids()
	return ids[rng.randi_range(0, ids.size() - 1)]
