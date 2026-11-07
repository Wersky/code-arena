extends SceneTree
## 算力系统验证（2026-11-06）：
##   1. cost 1 全免费 → 起始牌组的行为必须与"无算力"版本一致
##   2. cost 3 的许愿卡必须真的挤占出牌（每回合出牌数下降）
##
## 运行：godot --headless --path . --script res://tools/energy_check.gd

const N := 300


func _init() -> void:
	# ① 基线：起始牌组（全 cost 1）
	var base := _run(StsCardPool.starter_deck(), N)
	print("基线（全 cost1）      win=%.2f turns=%.2f 出牌/回合=%.2f" % [
		base.win, base.turns, base.plays])

	# ② 加一张 cost3 的强效果卡：应显著挤占出牌
	var big := StsCard.make("en_big", StsCard.Kind.ATTACK, 3, 6, 0, "")
	big.effects = EffectDSL.compile([
		{"when": "on_play", "then": [
			{"do": "damage", "amount": 20},
			{"do": "damage_scaled", "per": "same_kind_streak", "step": 3},
		]},
	])["clauses"]
	big.dsl_version = EffectSpec.VERSION
	var deck2: Array[StsCard] = StsCardPool.starter_deck()
	deck2.append(big)
	var with3 := _run(deck2, N)
	print("加 cost3 强卡         win=%.2f turns=%.2f 出牌/回合=%.2f" % [
		with3.win, with3.turns, with3.plays])
	print("→ 每回合出牌数变化 %+.2f（负值 = 算力真的在约束）" % (with3.plays - base.plays))

	# ③ 同一张卡若 cost=1（对照组）：不应挤占
	var cheap := StsCard.make("en_cheap", StsCard.Kind.ATTACK, 1, 6, 0, "")
	cheap.effects = big.effects
	cheap.dsl_version = EffectSpec.VERSION
	var deck3: Array[StsCard] = StsCardPool.starter_deck()
	deck3.append(cheap)
	var with1 := _run(deck3, N)
	print("同卡 cost1（对照）    win=%.2f turns=%.2f 出牌/回合=%.2f" % [
		with1.win, with1.turns, with1.plays])
	quit()


func _run(deck: Array[StsCard], n: int) -> Dictionary:
	var wins := 0
	var turns := 0
	var plays := 0
	var pattern := [
		{"kind": "attack", "value": EffectPricing.REF_ATK},
		{"kind": "defend", "value": EffectPricing.REF_DEF},
		{"kind": "attack", "value": EffectPricing.REF_ATK},
	]
	for i in n:
		var cb := StsCombat.new()
		cb.setup(deck, "ref", EffectPricing.REF_HP, pattern, 80, i + 1, 4, 1)
		var guard := 0
		var plays_i := 0
		while cb.over == StsCombat.Result.RUNNING and cb.turn < EffectPricing.MAX_TURNS \
				and guard < 400:
			guard += 1
			while not cb.hand.is_empty() and cb.over == StsCombat.Result.RUNNING \
					and cb.can_play(cb.hand[0]):
				cb.play_card(cb.hand[0], false, false, false)
				plays_i += 1
			if cb.over == StsCombat.Result.RUNNING:
				cb.end_send()
				cb.end_turn()
		wins += 1 if cb.over == StsCombat.Result.WIN else 0
		turns += cb.turn
		plays += plays_i
	return {
		"win": float(wins) / n,
		"turns": float(turns) / n,
		"plays": float(plays) / float(maxi(1, turns)),
	}
