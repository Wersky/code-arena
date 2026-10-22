extends SceneTree
## 平衡模拟（**新机制链路**：命令行片段 + 顺序层 + AI娘口味 + 道具层）
##
## 运行：godot --headless --path <项目> --script res://tools/balance_sim.gd
##
## 与旧版的区别（契约 G.5）：
##   ① 贪心枚举的手牌组合上限 5 → 6（对应命令行 6 段上限）；
##   ② 每个组合要试 **2 种排列**（规范序 / 规范序+范例紧邻任务）；
##   ③ 评分 ctx 必须带 `ai` 与 `command_parts`（按该排列拼出的片段数组），
##      否则顺序层不生效，模拟出来的均分与真实对局不是一个东西。
##
## 输出：
##   每关 贪心均分 / 通过率 / 到达率 / **建议目标分**（10 分位 → 约 90% 通过率）
##   整局通关率
##
## 验收线（契约 I-10）：每关贪心通过率 ≥ 85%，整局通关率 45%~60%。

const SIMS := 120
## 试算用的局数覆盖（--sims=N）；正式测量请用默认值
var _sims := SIMS
## 本局使用的核心 AI 娘（开局只有 DeepDeek 可选，见 AiPool.UNLOCK_AT）
const AI_ID := "deepdeek"
## 命令行片段上限（与 RunState.MAX_COMMAND_PARTS 一致）
const MAX_PARTS := 6
## 建议目标分取均分的这一分位数（0.10 → 约 90% 的局能过）
const TARGET_QUANTILE := 0.10

## 关卡表（整轮模拟共用同一批实例，目标分覆盖才能生效）
var _levels: Array[LevelData] = []


func _initialize() -> void:
	_levels = LevelPool.all_levels()
	_apply_target_override()
	print("完整 Run 模拟（每局 %d 次 · 贪心打牌 · AI娘=%s）" % [_sims, AI_ID])
	print("贪心 = 穷举手牌 ≤%d 张的组合 × %d 种排列，按新链路（顺序层 + 口味层）取最高分" % [MAX_PARTS, 2])
	print("")
	print("关卡   目标分  回合  贪心均分  贪心通过率  到达率  道具数  牌库   建议目标分    q05  判定")
	print("─".repeat(100))
	print("分位数参考（得分分布）：q05 / q08 / q10 / q15 / q20 / 中位")

	var full := _full_run()
	var stats: Array = full["levels"]
	for i in stats.size():
		var r: Dictionary = stats[i]
		var level: LevelData = r["level"]
		var verdict := "OK"
		if r["pass_rate"] < 0.85:
			verdict = "难"
		elif r["pass_rate"] > 0.98:
			verdict = "易"
		# 目标分 ≤ q05 ⇒ 连最差的一局都能过 ⇒ 这一关没有失败风险
		var q05 := _quantile(r["scores"], 0.05)
		if level.target_score <= q05:
			verdict = "保过"
		print("%-6s %6d %5d %9.0f %10.0f%% %7.0f%% %6.1f %6d  %6d  %5d  %s" % [
			level.id, level.target_score, level.turns, r["avg"], r["pass_rate"] * 100.0,
			r["reach_rate"] * 100.0, r["items"], r["deck"], r["suggest"], q05, verdict
		])
	print("")
	print("整局通关率：%.0f%%" % (float(full["clear_rate"]) * 100.0))
	print("")
	print("建议目标分 = 该关贪心得分分布的 %d%% 分位数（→ 约 %d%% 通过率）" % [
		int(TARGET_QUANTILE * 100.0), int((1.0 - TARGET_QUANTILE) * 100.0)])
	print("分位数参考：")
	for i in stats.size():
		var r: Dictionary = stats[i]
		var level: LevelData = r["level"]
		var sc: Array = r["scores"]
		print("  %-4s q05=%5d q08=%5d q10=%5d q15=%5d q20=%5d 中位=%5d 均值=%5d" % [
			level.id,
			_quantile(sc, 0.05), _quantile(sc, 0.08), _quantile(sc, 0.10),
			_quantile(sc, 0.15), _quantile(sc, 0.20), _quantile(sc, 0.50),
			int(r["avg"]),
		])
	quit()


## 校准辅助：命令行可传 `--targets=1210,1650,...`（10 个数）临时覆盖目标分，
## 用来在不动 level_pool.gd 的前提下试算不同目标分的结果。
## 正式目标分仍以 scripts/data/level_pool.gd 为准。
func _apply_target_override() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--targets="):
			var raw := a.substr(10)
			var nums := raw.split(",")
			if nums.size() != _levels.size():
				printerr("目标分覆盖失败：需要 %d 个数字，收到 %d 个" % [_levels.size(), nums.size()])
				return
			for i in _levels.size():
				_levels[i].target_score = int(nums[i].strip_edges())
			print("（本次用命令行覆盖目标分：%s）" % raw)
		elif a.begins_with("--sims="):
			_sims = maxi(1, int(a.substr(7)))
			print("（本次用命令行覆盖局数：%d）" % _sims)


## 跑完整局：一次模拟同时得到每关分数分布 / 通过率 / 到达率 / 整局通关率。
func _full_run() -> Dictionary:
	var per_level := {}
	for l in _levels:
		per_level[l.id] = {"scores": [], "passed": 0, "reached": 0, "items": 0.0, "deck": 0}
	var wins := 0
	for s in _sims:
		var run := RunState.new()
		run.reset_run()
		run.run_seed = 424242 + s * 17
		run.set_ai(AiPool.get_ai(AI_ID))
		var alive := true
		for level in _levels:
			var sc := _play_level(run, level)
			var rec: Dictionary = per_level[level.id]
			rec["scores"].append(sc)
			rec["reached"] = int(rec["reached"]) + 1
			rec["items"] = float(rec["items"]) + float(run.items.size())
			rec["deck"] = int(rec["deck"]) + run.deck.size()
			if sc >= level.target_score:
				rec["passed"] = int(rec["passed"]) + 1
				_grant_rewards(run, level)
			else:
				alive = false
				break
		if alive:
			wins += 1

	var out := []
	for level in _levels:
		var rec: Dictionary = per_level[level.id]
		var scores: Array = rec["scores"]
		var reached := int(rec["reached"])
		var passed := int(rec["passed"])
		out.append({
			"level": level,
			"avg": float(scores.reduce(func(a, b): return a + b, 0)) / float(maxi(1, scores.size())),
			"pass_rate": float(passed) / float(maxi(1, reached)),
			"reach_rate": float(reached) / float(_sims),
			"items": float(rec["items"]) / float(maxi(1, reached)),
			"deck": int(rec["deck"]) / float(maxi(1, reached)),
			"suggest": _quantile(scores, TARGET_QUANTILE),
			"scores": scores,
		})
	return {"levels": out, "clear_rate": float(wins) / float(_sims)}


## 打一整关，返回最终得分
func _play_level(run: RunState, level: LevelData) -> int:
	run.start_level(level)
	while run.turn < level.turns:
		var best := _pick(run, level)
		var res := Scoring.evaluate(best["cards"], _ctx(run, level, best["parts"]))
		run.score += int(res["score"])
		run.end_turn(best["cards"])
	return run.score


## 过关奖励：1 件 AI 道具 + 算力够就买 1 张卡
func _grant_rewards(run: RunState, level: LevelData) -> void:
	run.level_index += 1
	run.award_compute(level)
	var offers := AiItemPool.roll_rewards(run.rng, level.chapter, run.items, 3)
	if not offers.is_empty():
		run.add_item(offers[run.rng.randi_range(0, offers.size() - 1)])
	if run.compute >= 40:
		run.compute -= 40
		var cards := CardPool.random_cards(run.rng, 1)
		if not cards.is_empty():
			run.deck.append(cards[0])


func _ctx(run: RunState, level: LevelData, parts: Array[String]) -> Dictionary:
	return {
		"token_budget": level.token_budget, "items": run.items,
		"turn_index": run.turn, "rule": level.rule,
		"shield": run.shield_ready > 0,
		# preview=false：与真实对局一致（arena 结算走的就是 preview=false，
		# gamble 类道具的随机结算才生效）。
		"preview": false,
		"rng": run.rng,
		# ── 新机制：顺序层 / 口味层需要这两项 ──
		"ai": run.ai,
		"command_parts": parts,
	}


## 贪心：穷举手牌所有 ≤6 张的组合，每种组合试 2 种排列，取新链路的最高分。
## 返回 {"cards": Array[CardData]（按最终顺序）, "parts": Array[String]}
func _pick(run: RunState, level: LevelData) -> Dictionary:
	var hand := run.hand.duplicate()
	var best_cards: Array[CardData] = []
	var best_parts: Array[String] = []
	var best_score := -1
	var n := hand.size()
	# ctx 只建一次，每次只换 command_parts（Scoring.evaluate 不持有 ctx）
	var ctx := _ctx(run, level, [] as Array[String])
	for mask in range(1 << n):
		var chosen: Array[CardData] = []
		for i in n:
			if mask & (1 << i):
				chosen.append(hand[i])
		if chosen.is_empty() or chosen.size() > MAX_PARTS:
			continue
		for ordering in _orderings(chosen):
			var parts: Array[String] = []
			for c in ordering:
				parts.append(c.cli_fragment())
			ctx["command_parts"] = parts
			var sc := int(Scoring.evaluate(ordering, ctx)["score"])
			if sc > best_score:
				best_score = sc
				best_cards = ordering
				best_parts = parts
	return {"cards": best_cards, "parts": best_parts}


## 每个组合试 2 种排列（契约 G.5）：
##   1) 规范序（按 CardData.KIND_ORDER）——本规则表下基本就是最优序
##   2) 规范序 + 把 --example 挪到 --task 紧后（覆盖「范例紧邻任务」这类口味）
func _orderings(cards: Array[CardData]) -> Array:
	var out := []
	var canon := _canonical(cards)
	out.append(canon)
	out.append(_example_next_to_task(canon))
	return out


## 按 kind 的规范顺序排序（同类卡保持原相对次序）
func _canonical(cards: Array[CardData]) -> Array[CardData]:
	var out: Array[CardData] = cards.duplicate()
	out.sort_custom(func(a: CardData, b: CardData) -> bool:
		return _kind_index(a.kind) < _kind_index(b.kind))
	return out


## 把第一张范例卡挪到第一张任务卡紧后
func _example_next_to_task(cards: Array[CardData]) -> Array[CardData]:
	var out: Array[CardData] = cards.duplicate()
	var ti := -1
	var ei := -1
	for i in out.size():
		if ti < 0 and out[i].kind == CardData.Kind.TASK:
			ti = i
		elif ei < 0 and out[i].kind == CardData.Kind.EXAMPLE:
			ei = i
	if ti < 0 or ei < 0 or ei <= ti:
		return out
	var ex: CardData = out[ei]
	out.remove_at(ei)
	if ei < ti:
		ti -= 1
	out.insert(ti + 1, ex)
	return out


func _kind_index(kind: int) -> int:
	return CardData.KIND_ORDER.find(kind)


## 分位数（0 = 最小值，1 = 最大值）
func _quantile(values: Array, q: float) -> int:
	if values.is_empty():
		return 0
	var arr := values.duplicate()
	arr.sort()
	var idx := int(floor(clampf(q, 0.0, 1.0) * float(arr.size() - 1)))
	return int(arr[idx])
