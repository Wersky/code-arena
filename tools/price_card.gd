extends SceneTree
## 效果卡定价器（圆桌第 3 轮交付物 #3 的可跑版本）。
##
## 运行：godot --headless --path <项目> --script res://tools/price_card.gd
##
## 输出：每张样例卡的 cost / EV / 胜率差 / 回合差，以及牌组组合审计结果。
## 口径：p50 定 cost（本 v0 用 200 场均值近似），固定参考擂台 + 固定种子，可复跑。

const LEVEL := 1
const SAMPLES := 200

const SAMPLES_PROGRAMS := {
	"纯数值（对照）": [],
	"回响：连击成长": [
		{"when": "on_play", "then": [
			{"do": "damage", "amount": 6},
			{"do": "damage_scaled", "per": "same_kind_streak", "step": 2},
		]},
	],
	"污染：上易伤": [
		{"when": "on_play", "then": [
			{"do": "apply_status", "status": "vulnerable", "tier": 1, "target": "enemy"},
		]},
	],
	"泄漏：回合末中毒": [
		{"when": "on_turn_end", "then": [
			{"do": "apply_status", "status": "poison", "tier": 2, "target": "enemy"},
		]},
	],
	"手牌越多越重": [
		{"when": "on_play", "if": {"counter": "hand_size", "gte": 3}, "then": [
			{"do": "damage", "amount": 4},
			{"do": "damage_scaled", "per": "hand_size", "step": 2},
		]},
	],
	"超模（应被封禁）": [
		{"when": "on_play", "then": [
			{"do": "damage", "amount": 20},
			{"do": "damage_scaled", "per": "hand_size", "step": 5},
			{"do": "damage_scaled", "per": "same_kind_streak", "step": 5},
			{"do": "apply_status", "status": "vulnerable", "tier": 3, "target": "enemy"},
		]},
	],
}


func _init() -> void:
	var cards: Array[StsCard] = []
	print("=== 单卡定价（level=%d, samples=%d）===" % [LEVEL, SAMPLES])
	for name in SAMPLES_PROGRAMS:
		var program: Array = SAMPLES_PROGRAMS[name]
		var c := StsCard.make("price_" + str(name.hash()), StsCard.Kind.ATTACK, 1, 6, 0, "")
		if not program.is_empty():
			var compiled := EffectDSL.compile(program)
			c.effects = compiled["clauses"]
			c.dsl_version = EffectSpec.VERSION
		var t0 := Time.get_ticks_msec()
		var r := EffectPricing.price(c, LEVEL, SAMPLES)
		var ms := Time.get_ticks_msec() - t0
		print("%-18s cost=%d  p50=%+6.1f  p95=%+6.1f  banned=%s  胜率%+5.1f%%  回合%+.2f  (%d ms)" % [
			name, int(r["cost"]), float(r["ev"]), float(r["p95"]),
			"Y" if bool(r["banned"]) else "N",
			float(r["win_delta"]) * 100.0 if r.has("win_delta") else 0.0,
			float(r["turn_delta"]) if r.has("turn_delta") else 0.0, ms])
		cards.append(c)

	print("\n=== 牌组级组合审计（把上面 6 张塞进同一牌组）===")
	var t_audit := Time.get_ticks_msec()
	var audit := EffectCombo.audit(cards, LEVEL, 30)
	print("tag=%s  pairs=%d  triples=%d  quads=%d  block=%d  verify=%d  (%d ms)" % [
		audit["tag"], (audit["pairs"] as Array).size(),
		(audit["triples"] as Array).size(),
		(audit["quads"] as Array).size(),
		audit["blocked"], audit["verified"], Time.get_ticks_msec() - t_audit])
	for row in audit["pairs"]:
		print("  对 %-12s × %-12s excess=%+7.2f  → %s" % [
			String(row["a"]), String(row["b"]),
			float(row["excess"]), String(row["tag"])])
	for row in audit["triples"]:
		var ids: Array = row["cards"]
		print("  三 %-12s × %-12s × %-12s excess=%+7.2f  → %s" % [
			String(ids[0]), String(ids[1]), String(ids[2]),
			float(row["excess"]), String(row["tag"])])
	for row in audit["quads"]:
		var q: Array = row["cards"]
		print("  %d张 %s excess=%+7.2f  → %s" % [
			int(row["size"]), " × ".join(q), float(row["excess"]), String(row["tag"])])
	quit()
