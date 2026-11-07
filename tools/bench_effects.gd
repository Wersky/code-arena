extends SceneTree
## 效果层基准（圆桌第 3 轮验证顺序 #1）：解释器到底多慢。
##
## 运行：godot --headless --path <项目> --script res://tools/bench_effects.gd
##
## 输出三组数：
##   1. DSL 编译成本（us/次）
##   2. 单 op 求值成本（us/op）——性能官红线 ≤20µs
##   3. 一场战斗开销（纯逻辑 vs 带效果），以及 200 场定价模拟的墙钟

const BATTLES := 300
const COMPILES := 20000
const EVALS := 200000

const PROGRAM := [
	{"when": "on_play", "then": [
		{"do": "damage", "amount": 6},
		{"do": "damage_scaled", "per": "same_kind_streak", "step": 2},
		{"do": "apply_status", "status": "weak", "tier": 1, "target": "enemy"},
	]},
	{"when": "on_turn_end", "then": [
		{"do": "apply_status", "status": "poison", "tier": 1, "target": "enemy"},
	]},
]


func _init() -> void:
	var clauses: Array = EffectDSL.compile(PROGRAM)["clauses"]
	print("compiled clauses=%d ops=%d" % [clauses.size(), EffectDSL.compile(PROGRAM)["ops"]])

	# ① 编译
	var t0 := Time.get_ticks_usec()
	for i in COMPILES:
		EffectDSL.compile(PROGRAM)
	var dt_compile := float(Time.get_ticks_usec() - t0) / COMPILES
	print("compile: %.2f us/次" % dt_compile)

	# ② 求值（一次 eval 含 3 个 on_play op + 1 个 on_turn_end op）
	var ctx := {"hand_size": 3, "same_kind_streak": 2, "cards_played_this_turn": 3,
			"enemy_status_count": 1, "turn": 4}
	var ops_per_eval := 4
	t0 = Time.get_ticks_usec()
	for i in EVALS:
		EffectRuntime.eval(clauses, "on_play", ctx)
	var dt_eval := float(Time.get_ticks_usec() - t0) / EVALS
	print("eval: %.3f us/次（%.3f us/op）" % [dt_eval, dt_eval / ops_per_eval])

	# ③ 战斗：基线 vs 带效果
	var base := _run(BATTLES, false)
	var fx := _run(BATTLES, true)
	print("battle plain:   %.3f ms/场" % base)
	print("battle effects: %.3f ms/场（+%.2f%%）" % [fx, (fx / base - 1.0) * 100.0])
	print("200 场定价模拟（带效果）: %.2f s" % (fx * 200.0 / 1000.0))
	print("1000 场定价模拟（带效果）: %.2f s" % (fx * 1000.0 / 1000.0))
	quit()


## 跑 m 场完整战斗；with_fx 时给起始牌组前 3 张挂效果程序
func _run(m: int, with_fx: bool) -> float:
	var clauses: Array = EffectDSL.compile(PROGRAM)["clauses"]
	var t0 := Time.get_ticks_usec()
	for i in m:
		var deck: Array[StsCard] = StsCardPool.starter_deck()
		if with_fx:
			for k in mini(3, deck.size()):
				deck[k].effects = clauses
				deck[k].dsl_version = 1
		var cb := StsCombat.new()
		var pattern := [
			{"kind": "attack", "value": 8},
			{"kind": "defend", "value": 5},
			{"kind": "attack", "value": 8},
		]
		cb.setup(deck, "bench", 90, pattern, 80, i + 1, 4, 1)
		var guard := 0
		while cb.over == StsCombat.Result.RUNNING and cb.turn < 60 and guard < 300:
			guard += 1
			while not cb.hand.is_empty() and cb.over == StsCombat.Result.RUNNING \
					and cb.can_play(cb.hand[0]):
				cb.play_card(cb.hand[0], false, false, false)
			if cb.over == StsCombat.Result.RUNNING:
				cb.end_send()
				cb.end_turn()
	var dt := float(Time.get_ticks_usec() - t0) / m
	return dt / 1000.0
