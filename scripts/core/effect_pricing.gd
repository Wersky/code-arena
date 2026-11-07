class_name EffectPricing
extends RefCounted
## 效果定价 v1（圆桌终裁口径落地）。
##
## 口径：
##   - **p50 定 cost、p95 只做封禁**，两者分开公示，绝不把 p95 折进 cost
##   - 对照是**同一张卡去掉 effects**，否则测出来的是"多一张牌"的价值
##   - 固定参考擂台 + 固定种子 + 逐样本配对，同卡两次定价必须一致
##   - 先丢非法 clause，再按最终 AST 定价（调用方传编译后的结果）
##
## 四道闸门（圆桌第 1/2 轮）：
##   1. 终止性：回合内状态哈希重复 → 判非终止，直接拒
##   2. 决策次数：每场决策点击数 p95 > 60 → 判交互过载，拒
##   3. 触发链：由 EffectRuntime 的 op 预算 64 + 深度 1 保证（不在定价层重复）
##   4. 版本：dsl_version 不匹配 → 拒
##
## 离线：`price_cached` 按 (程序 hash, dsl_version, 擂台, 定价版本) 缓存到
## `user://effect_price_cache.json`；查表 miss 时给保守上界，绝不阻塞在模拟上。

const SAMPLES := 200
const COST_MIN := 1
const COST_MAX := 3
const PRICING_VERSION := 2
const CACHE_PATH := "user://effect_price_cache.json"
const BAN_P95 := 40.0            ## p95 超过它 → 竞技封禁
const DECISION_EXTRA_MAX := 20   ## 相对基线的额外点击上限（绝对值随擂台长度漂移）
const MAX_TURNS := 40

## 参考擂台：2026-11-05 标定——起始卡组在此配置下胜率 ≈0.47（0.4–0.6 有效区间）。
const REF_HP := 200
const REF_ATK := 16
const REF_DEF := 5

static var _cache: Dictionary = {}
static var _cache_loaded := false


## 定价（完整四闸门 + p50/p95 双口径）
## 返回：
##   ok / cost / ev(p50) / p95 / banned / reason / non_terminating / decision_p95 /
##   base / with_card / samples / pricing_version / cache_key
static func price(card: StsCard, level_index: int = 1, samples: int = SAMPLES) -> Dictionary:
	## 闸门 4：版本
	if card.dsl_version != 0 and card.dsl_version != EffectSpec.VERSION:
		return _fail("版本不匹配：卡 %d / 本地 %d" % [card.dsl_version, EffectSpec.VERSION])

	## 定价一律按 cost 1 模拟：否则会出现「定价 → 费用 → 能量消耗 → ΔEV → 定价」的循环。
	## 费用是定价的**输出**，不能反过来当输入。
	var shell := StsCard.make(card.id + "_shell", card.kind, 1,
			card.damage, card.block, "")
	shell.draw = card.draw
	var fx_sim := StsCard.make(card.id + "_sim", card.kind, 1,
			card.damage, card.block, "")
	fx_sim.draw = card.draw
	fx_sim.effects = card.effects
	fx_sim.dsl_version = card.dsl_version
	var base_deck: Array[StsCard] = StsCardPool.starter_deck()
	base_deck.append(shell)
	var fx_deck: Array[StsCard] = StsCardPool.starter_deck()
	fx_deck.append(fx_sim)

	var base := _run_deck_verbose(base_deck, level_index, samples)
	var fx := _run_deck_verbose(fx_deck, level_index, samples)

	## 闸门 1：终止性
	var gt := check_termination_gate(int(fx["non_terminating"]), samples)
	if not bool(gt["ok"]):
		return _fail(String(gt["reason"]))

	## 闸门 2：决策次数（相对基线，避免绝对值随擂台长度漂移）
	var dec_p95 := _quantile(fx["decisions"], 0.95)
	var base_dec_p95 := _quantile(base["decisions"], 0.95)
	var gd := check_decision_gate(dec_p95 - base_dec_p95)
	if not bool(gd["ok"]):
		return _fail(String(gd["reason"]))

	## 逐样本配对差分（同一 seed 的 base vs fx）
	## 单场分数 = 胜率 + 推进效率（敌人掉血 / 回合），对中毒这类"不打伤害但推进"的效果
	## 与直伤一视同仁；纯用 damage_dealt 会把中毒算成负收益（实测踩过）。
	var diffs: Array = []
	for i in mini((base["rows"] as Array).size(), (fx["rows"] as Array).size()):
		var b: Dictionary = (base["rows"] as Array)[i]
		var f: Dictionary = (fx["rows"] as Array)[i]
		var sb := float(b["win"]) * 100.0 + float(b["hp_lost"]) / maxf(1.0, float(b["turns"])) * 2.0
		var sf := float(f["win"]) * 100.0 + float(f["hp_lost"]) / maxf(1.0, float(f["turns"])) * 2.0
		diffs.append(sf - sb)

	var ev_p50 := _bootstrap_quantile(diffs, 0.5)
	var ev_p95 := _bootstrap_quantile(diffs, 0.95)
	var cost := clampi(COST_MIN + int(round(ev_p50 / 8.0)), COST_MIN, COST_MAX)
	var banned := ev_p95 > BAN_P95

	var result := {
		"ok": true,
		"cost": cost,
		"ev": ev_p50,
		"p95": ev_p95,
		"banned": banned,
		"reason": "封禁：p95=%.1f > %.0f" % [ev_p95, BAN_P95] if banned else "",
		"non_terminating": 0,
		"decision_p95": dec_p95,
		"decision_extra": dec_p95 - base_dec_p95,
		"base": base["summary"],
		"with_card": fx["summary"],
		"samples": samples,
		"pricing_version": PRICING_VERSION,
	}
	return result


## 离线查表：命中直接返回；未命中时按 need_compute 决定是现算还是给保守上界
static func price_cached(card: StsCard, level_index: int = 1, samples: int = SAMPLES,
		compute_on_miss: bool = true) -> Dictionary:
	_load_cache()
	var key := cache_key(card, level_index)
	if _cache.has(key):
		var hit: Dictionary = (_cache[key] as Dictionary).duplicate()
		hit["cached"] = true
		return hit
	if not compute_on_miss:
		## 保守上界：宁可偏贵，绝不阻塞在模拟上
		return {
			"ok": true, "cost": COST_MAX, "ev": 0.0, "p95": 0.0, "banned": false,
			"reason": "临时价（未计算）", "non_terminating": 0, "decision_p95": 0.0,
			"samples": 0, "pricing_version": PRICING_VERSION, "cached": false,
			"cache_key": key,
		}
	var r := price(card, level_index, samples)
	_cache[key] = r.duplicate()
	_save_cache()
	r["cached"] = false
	r["cache_key"] = key
	return r


## 缓存键：(定价版本, DSL 版本, 关卡, 擂台, 程序 AST)
static func cache_key(card: StsCard, level_index: int) -> String:
	var payload := {
		"v": PRICING_VERSION,
		"dsl": EffectSpec.VERSION,
		"lv": level_index,
		"ref": [REF_HP, REF_ATK, REF_DEF],
		"p": card.effects,
	}
	return JSON.stringify(payload).sha256_text()


## 批量定价（离线批次入口）：返回 [{id, cost, banned, cached, reason}]
static func price_batch(cards: Array, level_index: int = 1, samples: int = SAMPLES) -> Array:
	var out: Array = []
	for c in cards:
		var r := price_cached(c, level_index, samples)
		out.append({"id": String(c.id), "cost": int(r["cost"]), "banned": bool(r["banned"]),
				"cached": bool(r.get("cached", false)), "reason": String(r["reason"])})
	return out


static func clear_cache() -> void:
	_cache.clear()
	_cache_loaded = true
	_save_cache()


static func _load_cache() -> void:
	if _cache_loaded:
		return
	_cache_loaded = true
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_cache = parsed


static func _save_cache() -> void:
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_cache))


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "cost": COST_MAX, "ev": 0.0, "p95": 0.0, "banned": true,
			"reason": reason, "non_terminating": 0, "decision_p95": 0.0,
			"samples": 0, "pricing_version": PRICING_VERSION}


## 闸门 1（纯函数，便于单测）：出现状态重复即判非终止
static func check_termination_gate(non_term: int, total: int) -> Dictionary:
	if non_term > 0:
		return {"ok": false, "reason": "非终止：%d/%d 场出现状态重复" % [non_term, total]}
	return {"ok": true, "reason": ""}


## 闸门 2（纯函数，便于单测）：相对基线的额外点击超限即判交互过载
static func check_decision_gate(extra: float) -> Dictionary:
	if extra > float(DECISION_EXTRA_MAX):
		return {"ok": false, "reason": "交互过载：比基线多 %.0f 次点击 > %d"
				% [extra, DECISION_EXTRA_MAX]}
	return {"ok": true, "reason": ""}


## 分位数（线性插值取最近秩）
static func _quantile(arr: Array, q: float) -> float:
	if arr.is_empty():
		return 0.0
	var a: Array = arr.duplicate()
	a.sort()
	var idx := clampi(int(round(q * float(a.size() - 1))), 0, a.size() - 1)
	return float(a[idx])


## 自助法分位：对逐场差分做有放回重采样，取「均值」的 p50 / p95。
## 直接对逐场差分取分位没有意义——单场是胜/负的二元跳变，p95 会变成 ±100。
## 固定种子保证同卡两次定价完全一致。
static func _bootstrap_quantile(diffs: Array, q: float, resamples := 200) -> float:
	if diffs.is_empty():
		return 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	var n := diffs.size()
	var means: Array = []
	for r in resamples:
		var acc := 0.0
		for i in n:
			acc += float(diffs[rng.randi_range(0, n - 1)])
		means.append(acc / float(n))
	return _quantile(means, q)


## 带逐场明细的跑批；同时做终止性检测（状态哈希重复）
## ref_hp > 0 时覆盖擂台血量（组合审计用更大的牌组，需要更高的血量才不饱和）
static func _run_deck_verbose(deck: Array[StsCard], level_index: int, n: int,
		ref_hp: int = -1) -> Dictionary:
	var rows: Array = []
	var wins := 0
	var turns_total := 0
	var dmg_total := 0
	var decisions: Array = []
	var non_term := 0
	var enemy_hp := (ref_hp if ref_hp > 0 else REF_HP) + maxi(0, level_index - 1) * 30
	var atk := REF_ATK + maxi(0, level_index - 1)
	var dfn := REF_DEF + maxi(0, level_index - 1)
	var pattern := [
		{"kind": "attack", "value": atk},
		{"kind": "defend", "value": dfn},
		{"kind": "attack", "value": atk},
	]
	for i in n:
		var cb := StsCombat.new()
		cb.setup(deck, "ref", enemy_hp, pattern, 80, i + 1, 4, level_index)
		var seen := {}
		var guard := 0
		var decisions_i := 0
		var repeated := false
		while cb.over == StsCombat.Result.RUNNING and cb.turn < MAX_TURNS and guard < 400:
			guard += 1
			var ids: Array[String] = []
			for c in cb.hand:
				ids.append(String(c.id))
			var h := "%d|%d|%d|%d|%d|%s" % [cb.hp, cb.enemy_hp, cb.block,
					cb.enemy_block, cb.rice_eaten, ",".join(ids)]
			if seen.has(h):
				repeated = true
				break
			seen[h] = true
			while not cb.hand.is_empty() and cb.over == StsCombat.Result.RUNNING \
					and cb.can_play(cb.hand[0]):
				cb.play_card(cb.hand[0], false, false, false)
				decisions_i += 1
			if cb.over == StsCombat.Result.RUNNING:
				cb.end_send()
				cb.end_turn()
		if repeated:
			non_term += 1
		decisions.append(decisions_i)
		turns_total += cb.turn
		dmg_total += cb.damage_dealt
		if cb.over == StsCombat.Result.WIN:
			wins += 1
		rows.append({
			"win": 1.0 if cb.over == StsCombat.Result.WIN else 0.0,
			"turns": float(cb.turn),
			"damage": float(cb.damage_dealt),
			## 敌人总掉血（含中毒等无视护盾的部分）——比 damage_dealt 更能代表"推进"
			"hp_lost": float(enemy_hp - cb.enemy_hp),
		})
	return {
		"rows": rows,
		"non_terminating": non_term,
		"decisions": decisions,
		"summary": {
			"win_rate": float(wins) / float(n),
			"avg_turns": float(turns_total) / float(n),
			"avg_damage": float(dmg_total) / float(n),
		},
	}


## 兼容旧调用（EffectCombo 用）：只返回聚合
static func _run_deck(deck: Array[StsCard], level_index: int, n: int,
		ref_hp: int = -1) -> Dictionary:
	return _run_deck_verbose(deck, level_index, n, ref_hp)["summary"]
