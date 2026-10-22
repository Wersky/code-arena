extends SceneTree
## 平衡模拟（**扑克玩法**：9 张牌库 + 德州牌型 + 红黑花色效果）
##
## 运行：
##   godot --headless --path <项目> --script res://tools/balance_sim2.gd -- --sims=120
##   godot --headless --path <项目> --script res://tools/balance_sim2.gd -- --sims=480 --dump=res://docs/poker_424242.json
##
## 贪心策略：手牌 5 张，枚举全部 31 个子集（1~5 张），取 PokerHand.score 最高的一手。
## 子集只有 31 个，直接穷举，不需要束搜索。
##
## ⚠️ 样本量：q05（保过关判定）需要 ≥400 局才稳；只做趋势判断时 120 局够用。

const DEFAULT_SIMS := 60
const SEED_BASE := 424242
const SEED_STEP := 7919
const TARGET_QUANTILE := 0.10


static func _quantile(sorted_vals: Array, q: float) -> int:
	if sorted_vals.is_empty():
		return 0
	if sorted_vals.size() == 1:
		return int(sorted_vals[0])
	var pos := q * float(sorted_vals.size() - 1)
	var lo := int(pos)
	var hi := mini(lo + 1, sorted_vals.size() - 1)
	var frac := pos - float(lo)
	return int(round(float(sorted_vals[lo]) * (1.0 - frac) + float(sorted_vals[hi]) * frac))


func _initialize() -> void:
	var sims := DEFAULT_SIMS
	var seed_base := SEED_BASE
	var dump_path := ""
	var ai_id := "deepdeek"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sims="):
			sims = maxi(1, int(a.substr(7)))
		elif a.begins_with("--seed="):
			seed_base = int(a.substr(7))
		elif a.begins_with("--ai="):
			ai_id = a.substr(5)
		elif a.begins_with("--dump="):
			dump_path = a.substr(7)

	var levels := LevelPool.all_levels()
	print("扑克玩平衡模拟（每局 %d 次 · AI娘 %s）" % [sims, ai_id])
	if sims < 240:
		print("⚠ 样本量 %d 局：q05 噪声大，「保过关」判定仅供参考。" % sims)

	var rows: Array = []
	for s in sims:
		var run := RunState.new()
		run.reset_run()
		run.set_ai(AiPool.get_ai(ai_id))
		run.run_seed = seed_base + s * SEED_STEP
		var row: Array = []
		for level in levels:
			row.append(_play_level(run, level))
		rows.append(row)

	var stat: Array = []
	var reach := 1.0
	for li in levels.size():
		var level: LevelData = levels[li]
		var scores: Array = []
		var passed := 0
		for row in rows:
			var sc := int(row[li])
			scores.append(sc)
			if sc >= level.target_score:
				passed += 1
		scores.sort()
		var total := 0
		for v in scores:
			total += int(v)
		var pr := float(passed) / float(maxi(1, sims))
		stat.append({
			"level": level, "scores": scores,
			"avg": float(total) / float(maxi(1, sims)),
			"pass_rate": pr, "reach": reach,
			"suggest": _quantile(scores, TARGET_QUANTILE),
			"q05": _quantile(scores, 0.05),
		})
		reach *= pr

	var wins := 0
	for row in rows:
		var alive := true
		for li in levels.size():
			if int(row[li]) < (levels[li] as LevelData).target_score:
				alive = false
				break
		if alive:
			wins += 1

	print("")
	print("关卡   目标分  出牌  贪心均分  通过率  到达率  建议目标分    q05  判定")
	print("─".repeat(76))
	for r in stat:
		var level: LevelData = r["level"]
		var verdict := "OK"
		var pr := float(r["pass_rate"])
		if pr < 0.82:
			verdict = "难"
		elif pr > 0.98:
			verdict = "易"
		if level.target_score <= int(r["q05"]):
			verdict = "保过"
		print("%-6s %6d %5d %9.0f %6.0f%% %6.0f%% %8d %5d  %s" % [
			level.id, level.target_score, level.turns,
			float(r["avg"]), pr * 100.0, float(r["reach"]) * 100.0,
			int(r["suggest"]), int(r["q05"]), verdict,
		])
	print("")
	print("整局通关率：%.0f%%" % (float(wins) / float(maxi(1, sims)) * 100.0))
	print("")
	for r in stat:
		var sc: Array = r["scores"]
		print("  %-4s q05=%5d q08=%5d q10=%5d 中位=%5d 均值=%5d" % [
			(r["level"] as LevelData).id,
			_quantile(sc, 0.05), _quantile(sc, 0.08), _quantile(sc, 0.10),
			_quantile(sc, 0.50), int(r["avg"]),
		])

	if dump_path != "":
		var f := FileAccess.open(dump_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"sims": sims, "seed": seed_base, "ai": ai_id, "rows": rows}))
			f.close()
			print("\n得分矩阵已落盘：%s" % dump_path)

	quit()


func _play_level(run: RunState, level: LevelData) -> int:
	run.start_poker_level(level)
	var guard := 0
	while run.hands_left > 0 and guard < 20:
		guard += 1
		var best := _best_hand(run.poker_hand)
		run.score += int(best["score"])
		run.play_poker_hand(best["cards"])
	return run.score


## 枚举 1~5 张的全部子集，取最高分
func _best_hand(hand: Array[PokerCard]) -> Dictionary:
	var n := hand.size()
	var best: Dictionary = {"score": 0, "cards": [] as Array[PokerCard]}
	if n == 0:
		return best
	var total := 1 << n
	for mask in range(1, total):
		var sel: Array[PokerCard] = []
		for i in n:
			if mask & (1 << i) != 0:
				sel.append(hand[i])
		if sel.size() > 5:
			continue
		var r := PokerHand.score(sel)
		if int(r["score"]) > int(best["score"]):
			best = {"score": int(r["score"]), "cards": sel}
	return best
