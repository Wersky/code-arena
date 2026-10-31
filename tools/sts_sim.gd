extends SceneTree
## T5 定稿战斗模拟器（蜂群任务 t5）：乱序基线 vs 择优排序 —— 定稿验证与调参数据。
##
## 运行：
##   godot --headless --path . --script res://tools/sts_sim.gd
##
## 输出：stdout + res://.godot/sim_report.txt（T2 基线另存 sim_report_t2_baseline.txt）
##
## 【独立实现声明】不加载 StsCombat / StsCard 运行时，机制公式按
## scripts/core/sts_combat.gd 快照复刻（2026-10-31，T5 定稿态）：
##   A 连段阶梯：同类连击第 n 阶 step = STREAK_STEP*(n-1)；换类型断连；白米饭不断连不进阶
##   B 槽位：首位 +LEAD_BONUS、末位 +FINISH_BONUS（按发送时队列位置）
##   C 成长：吃满 RICE_AWAKE 碗 → 后续数值 round(v * RICE_BUFF)
##   D 指令行：loop 复读机（下一张非饭卡执行两次，连段逐次推阶）；parallel 并行
##             （本序列换类型阶数冻结）；收尾清 streak_lock / 未消费 pending_repeat
##   E 观察者：end_turn 时本序列 ≥2 攻 → 敌下回合 defend(def+OBS_BRACE)；
##             ≥2 发育 → attack(atk+OBS_CHARGE)；覆写 pattern 下一槽位
##   敌人 pattern = [攻 atk, 防 def, 攻 atk] 循环；敌格挡累积不清零；玩家格挡每回合清零
##   手牌 3 张队列：发送整手 → end_send → 敌方回合 → start_turn 补 3
##   补牌语义（T5 修循环锁定）：**全牌堆采样**——弃牌堆全部并回抽牌堆、洗混、抽 3。
##   每回合手牌是全卡组的随机样本，跨回合组合真正变化（开局组合不再锁死命运）。

# ── 机制常量快照（读自 scripts/core/sts_combat.gd @ T5 定稿态）──────────
const STREAK_STEP := 3
const LEAD_BONUS := 2
const FINISH_BONUS := 2
const RICE_AWAKE := 5
const RICE_BUFF := 1.2
const OBS_BRACE := 0
const OBS_CHARGE := 3
const PLAYER_HP := 80
const HAND_REFILL := 3
const MAX_TURNS := 60

# ── 评估器权重（本模拟器自定，不是游戏常量）───────────────────────────
const W_HP := 1.0        ## 攻击打到敌方 hp 的权重
const W_EBLK := 0.5      ## 削掉敌方格挡的权重
const W_RICE := 0.5      ## 每碗米饭的成长价值
const W_AWAKE := 10.0    ## 本序列内点火「有点睡醒」的跨回合粗略加权

const KIND_ATTACK := 0   ## StsCard.Kind.ATTACK 快照
const KIND_SKILL := 1    ## StsCard.Kind.SKILL 快照

const RUNS_PER_LEVEL := 200
const BASE_SEED := 424242
const SEED_STEP := 7919

## 关卡表快照（读自 scripts/data/level_pool.gd）：敌 hp / atk / def
const LEVELS := [
	{"id": "L1", "hp": 40, "atk": 7, "def": 4},
	{"id": "L2", "hp": 60, "atk": 8, "def": 5},
	{"id": "L3", "hp": 76, "atk": 9, "def": 6},
	{"id": "L4", "hp": 92, "atk": 10, "def": 6},
	{"id": "L5", "hp": 110, "atk": 11, "def": 7},
	{"id": "L6", "hp": 126, "atk": 12, "def": 8},
	{"id": "L7", "hp": 130, "atk": 13, "def": 8},
	{"id": "L8", "hp": 138, "atk": 12, "def": 8},
	{"id": "L9", "hp": 140, "atk": 12, "def": 8},
	{"id": "L10", "hp": 146, "atk": 13, "def": 8},
]

## 起始卡组快照（读自 sts_card_pool.gd starter_deck @T4 完成态）：
## 3 fish_ram(攻6) + 2 taunt(防5) + 3 rice + 1 loop(复读机) + 1 parallel(并行)
## = 3 攻 + 7 防，共 10 张
func _make_deck() -> Array:
	var deck: Array = []
	for i in 3:
		deck.append({"id": "fish", "kind": KIND_ATTACK, "dmg": 6, "blk": 0})
	for i in 2:
		deck.append({"id": "taunt", "kind": KIND_SKILL, "dmg": 0, "blk": 5})
	for i in 3:
		deck.append({"id": "rice", "kind": KIND_SKILL, "dmg": 0, "blk": 0})
	deck.append({"id": "loop", "kind": KIND_SKILL, "dmg": 0, "blk": 0})
	deck.append({"id": "parallel", "kind": KIND_SKILL, "dmg": 0, "blk": 0})
	return deck


class SimState:
	var rng := RandomNumberGenerator.new()
	var hp := 0
	var block := 0
	var rice := 0
	var e_hp := 0
	var e_blk := 0
	var e_atk := 0
	var e_def := 0
	var draw_pile: Array = []
	var discard: Array = []
	var hand: Array = []
	var pattern: Array = []
	var pat_idx := 0
	var intent := {}
	var turn := 0
	var seq_streak := 0
	var seq_kind := -1
	var seq_attacks := 0
	var seq_grows := 0
	var pending_repeat := 0   ## D 复读机：下一张非饭卡执行两次
	var streak_lock := false  ## D 并行：本序列换类型阶数冻结
	var observer_ever := false   ## 本局是否触发过观察者（统计用）


# ── 牌堆机制（复刻 _shuffle/_draw/_refill，rng 流与运行时同构）──────────

func _shuffle(st: SimState, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := st.rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _draw(st: SimState, n: int) -> void:
	for i in n:
		if st.draw_pile.is_empty():
			if st.discard.is_empty():
				return
			st.draw_pile.append_array(st.discard)
			st.discard.clear()
			_shuffle(st, st.draw_pile)
		st.hand.append(st.draw_pile.pop_back())


func _refill_from_deck(st: SimState) -> void:
	st.draw_pile.append_array(st.discard)
	st.discard.clear()
	_shuffle(st, st.draw_pile)
	_draw(st, HAND_REFILL)


func _setup(st: SimState, deck: Array, lv: Dictionary, seed_i: int) -> void:
	st.rng.seed = seed_i
	st.hp = PLAYER_HP
	st.block = 0
	st.rice = 0
	st.e_hp = int(lv["hp"])
	st.e_blk = 0
	st.e_atk = int(lv["atk"])
	st.e_def = int(lv["def"])
	st.pattern = [
		{"kind": "attack", "value": st.e_atk},
		{"kind": "defend", "value": st.e_def},
		{"kind": "attack", "value": st.e_atk},
	]
	st.pat_idx = 0
	st.draw_pile = deck.duplicate()
	st.discard = []
	st.hand = []
	st.turn = 0
	st.seq_streak = 0
	st.seq_kind = -1
	st.seq_attacks = 0
	st.seq_grows = 0
	st.pending_repeat = 0
	st.streak_lock = false
	st.observer_ever = false
	_shuffle(st, st.draw_pile)
	_draw(st, HAND_REFILL)          ## 初始手牌从牌堆抽（随后 start_turn 会经弃牌堆洗回）
	st.intent = st.pattern[0].duplicate()
	st.pat_idx = 1
	_start_turn(st)


func _start_turn(st: SimState) -> void:
	st.turn += 1
	st.block = 0
	for c in st.hand:
		st.discard.append(c)
	st.hand.clear()
	_refill_from_deck(st)      ## T5：全牌堆采样（修循环锁定）
	if st.hand.is_empty():
		_draw(st, HAND_REFILL)


# ── 出牌（复刻 play_card 核心数值链，无 rng；含 D 指令行）─────────────

func _play_one(st: SimState, c: Dictionary, lead: bool, finish: bool) -> void:
	var cid := String(c["id"])
	# 注释行：米饭（成长）
	if cid == "rice":
		st.rice += 1
		st.seq_grows += 1
		return
	# D 指令行：复读机（不连段不结算，给下一张非饭卡挂两次执行）
	if cid == "loop":
		st.pending_repeat = 1
		return
	# D 指令行：并行（阶数冻结）
	if cid == "parallel":
		st.streak_lock = true
		return
	# 连段推进（与运行时同构：0→1；同类进阶；异类断连，除非并行锁冻结）
	if st.seq_streak == 0:
		st.seq_streak = 1
	elif st.seq_kind == int(c["kind"]):
		st.seq_streak += 1
	elif not st.streak_lock:
		st.seq_streak = 1
	st.seq_kind = int(c["kind"])
	# D 复读消费：本卡执行两次，连段逐次推阶
	var times := 1
	if st.pending_repeat > 0:
		times = 2
		st.pending_repeat = 0
	var slot := LEAD_BONUS if lead else (FINISH_BONUS if finish else 0)
	for i in times:
		var step := STREAK_STEP * (st.seq_streak - 1)
		if int(c["kind"]) == KIND_ATTACK:
			var v := int(c["dmg"]) + step + slot
			if st.rice == RICE_AWAKE:
				## 觉醒赠卡（与游戏 sts_combat._grant_awake_cards 一致）
				st.discard.append({"id": "cannon", "kind": KIND_ATTACK, "dmg": 12, "blk": 0})
				st.discard.append({"id": "rage", "kind": KIND_ATTACK, "dmg": 5, "blk": 0})
			if st.rice >= RICE_AWAKE:
				v = int(round(float(v) * RICE_BUFF))
			st.seq_attacks += 1
			_hit_enemy(st, v)
		else:
			var v2 := int(c["blk"]) + step + slot
			if st.rice >= RICE_AWAKE:
				v2 = int(round(float(v2) * RICE_BUFF))
			st.seq_grows += 1
			st.block += v2
		if i < times - 1:
			st.seq_streak += 1


func _hit_enemy(st: SimState, dmg: int) -> void:
	var d := dmg
	if st.e_blk > 0:
		var cut := mini(st.e_blk, d)
		st.e_blk -= cut
		d -= cut
	st.e_hp = maxi(0, st.e_hp - d)


func _hit_player(st: SimState, dmg: int) -> void:
	var d := dmg
	if st.block > 0:
		var cut := mini(st.block, d)
		st.block -= cut
		d -= cut
	st.hp = maxi(0, st.hp - d)


func _end_send(st: SimState) -> void:
	st.seq_streak = 0
	st.seq_kind = -1
	st.streak_lock = false
	st.pending_repeat = 0


## 敌方回合（复刻 end_turn：敌行动 → refresh_intent → 观察者覆写 → start_turn）。
## 返回 false = 玩家死亡（LOSE）。
func _end_turn(st: SimState) -> bool:
	var it: Dictionary = st.intent
	if String(it.get("kind", "")) == "attack":
		_hit_player(st, int(it.get("value", 0)))
	else:
		st.e_blk += int(it.get("value", 0))
	if st.hp <= 0:
		return false
	st.intent = st.pattern[st.pat_idx % st.pattern.size()].duplicate()
	st.pat_idx += 1
	# E 观察者：看完这段程序，调整下回合意图（覆写 pattern 槽位）
	if st.seq_attacks >= 2:
		st.intent = {"kind": "defend", "value": st.e_def + OBS_BRACE}
		st.observer_ever = true
	elif st.seq_grows >= 2:
		st.intent = {"kind": "attack", "value": st.e_atk + OBS_CHARGE}
		st.observer_ever = true
	st.seq_attacks = 0
	st.seq_grows = 0
	_start_turn(st)
	return true


# ── 序列评估器（择优用，影子推演，不改真实状态；含 D 指令行影子）─────
## 收益 = Σ攻击有效伤害（hp×1.0 + 削敌盾×0.5，溢出不计）
##      + Σ格挡抵消价值（敌意图=attack 时 min(总格挡, 意图值)×1.0；defend 时 0）
##      + 米饭每碗 +0.5
##      + 本序列内点火「有点睡醒」+10.0（跨回合粗略加权）
## D 影子推演：loop 给后续非饭卡挂两次执行（伤害/格挡两次都计分）；
##             parallel 冻结连段（换类型不清链不进阶）——排序决策理解指令行价值。

func _evaluate(st: SimState, perm: Array) -> float:
	var streak := 0
	var kind := -1
	var lock := st.streak_lock
	var rep := st.pending_repeat
	var rice_shadow := st.rice
	var e_blk := st.e_blk
	var e_hp := st.e_hp
	var total_blk := 0
	var score := 0.0
	var n := perm.size()
	for i in n:
		var c: Dictionary = st.hand[int(perm[i])]
		var lead := i == 0
		var finish := i == n - 1
		var cid := String(c["id"])
		if cid == "rice":
			rice_shadow += 1
			score += W_RICE
			continue
		if cid == "loop":
			rep = 1
			continue
		if cid == "parallel":
			lock = true
			continue
		if streak == 0:
			streak = 1
		elif kind == int(c["kind"]):
			streak += 1
		elif not lock:
			streak = 1
		kind = int(c["kind"])
		var times := 1
		if rep > 0:
			times = 2
			rep = 0
		var slot := LEAD_BONUS if lead else (FINISH_BONUS if finish else 0)
		for t in times:
			var step := STREAK_STEP * (streak - 1)
			var awake := rice_shadow >= RICE_AWAKE
			if int(c["kind"]) == KIND_ATTACK:
				var v := int(c["dmg"]) + step + slot
				if awake:
					v = int(round(float(v) * RICE_BUFF))
				var cut := mini(e_blk, v)
				e_blk -= cut
				var to_hp := mini(v - cut, e_hp)
				e_hp -= to_hp
				score += W_EBLK * float(cut) + W_HP * float(to_hp)
			else:
				var v2 := int(c["blk"]) + step + slot
				if awake:
					v2 = int(round(float(v2) * RICE_BUFF))
				total_blk += v2
			if t < times - 1:
				streak += 1
	if String(st.intent.get("kind", "")) == "attack":
		score += float(mini(total_blk, int(st.intent.get("value", 0))))
	if st.rice < RICE_AWAKE and rice_shadow >= RICE_AWAKE:
		score += W_AWAKE
	return score


# ── 两种策略 ─────────────────────────────────────────────────────────

func _range_arr(n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append(i)
	return a


## 乱序基线：手牌按抽到顺序直接执行
func _order_random(st: SimState) -> Array:
	return _range_arr(st.hand.size())


## 择优排序：枚举全排列（3 张 = 6 种），评估器取最高（平手取字典序首个 = 原顺序）
func _order_best(st: SimState) -> Array:
	var best: Array = _range_arr(st.hand.size())
	var best_v := -INF
	for p in _perms(st.hand.size()):
		var v := _evaluate(st, p)
		if v > best_v:
			best_v = v
			best = p
	return best


func _perms(n: int) -> Array:
	var out: Array = []
	var cur: Array = []
	var used := {}
	_perm_rec(n, cur, used, out)
	return out


func _perm_rec(n: int, cur: Array, used: Dictionary, out: Array) -> void:
	if cur.size() == n:
		out.append(cur.duplicate())
		return
	for i in n:
		if used.get(i, false):
			continue
		used[i] = true
		cur.append(i)
		_perm_rec(n, cur, used, out)
		cur.pop_back()
		used.erase(i)


# ── 单局战斗 ─────────────────────────────────────────────────────────

func _run_battle(deck: Array, lv: Dictionary, seed_i: int, smart: bool) -> Dictionary:
	var st := SimState.new()
	_setup(st, deck, lv, seed_i)
	var combo_ids: Array = []
	for c in st.hand:
		combo_ids.append(String(c["id"]))
	var combo := ",".join(combo_ids)
	while st.turn <= MAX_TURNS:
		var order: Array = _order_best(st) if smart else _order_random(st)
		var seq: Array = []
		for idx in order:
			seq.append(st.hand[int(idx)])
		var win := false
		var played := 0
		for c in seq:
			if st.hand.is_empty():
				break
			var k := st.hand.find(c)   ## 同 id 卡深度相等，删哪个实例数值等价
			st.hand.remove_at(k)
			st.discard.append(c)
			_play_one(st, c, played == 0, played == seq.size() - 1)
			played += 1
			if st.e_hp <= 0:
				win = true
				break
		_end_send(st)
		if win:
			return {"win": true, "turns": st.turn, "observer": st.observer_ever, "combo": combo}
		if not _end_turn(st):
			return {"win": false, "turns": st.turn, "observer": st.observer_ever, "combo": combo}
	return {"win": false, "turns": st.turn, "observer": st.observer_ever, "combo": combo, "timeout": true}


# ── 统计与报告 ───────────────────────────────────────────────────────

func _fmt_pct(v: float) -> String:
	return "%.1f%%" % (v * 100.0)


func _initialize() -> void:
	var deck := _make_deck()
	var lines: Array[String] = []
	lines.append("════════════════════════════════════════════════════════════════")
	lines.append("T5 定稿战斗模拟报告：乱序基线 vs 择优排序（T2 基线见 sim_report_t2_baseline.txt）")
	lines.append("════════════════════════════════════════════════════════════════")
	lines.append("机制常量快照（2026-10-31 读自 scripts/core/sts_combat.gd @T5 定稿态）：")
	lines.append("  STREAK_STEP=%d  LEAD_BONUS=%d  FINISH_BONUS=%d" % [STREAK_STEP, LEAD_BONUS, FINISH_BONUS])
	lines.append("  RICE_AWAKE=%d  RICE_BUFF=%.1f  OBS_BRACE=%d  OBS_CHARGE=%d" % [RICE_AWAKE, RICE_BUFF, OBS_BRACE, OBS_CHARGE])
	lines.append("模拟配置：")
	lines.append("  卡组=起始卡组 10 张（3 fish_ram 攻6 + 2 taunt 防5 + 3 rice + loop + parallel）")
	lines.append("  补牌=全牌堆采样（T5 修循环锁定：弃牌堆并回抽牌堆洗混再抽 3）")
	lines.append("  玩家 HP=%d，手牌 %d 张/回合整手发送，每关 %d 局，seed=%d+level_index*%d" % [PLAYER_HP, HAND_REFILL, RUNS_PER_LEVEL, BASE_SEED, SEED_STEP])
	lines.append("  敌人 pattern=攻防攻循环；敌格挡累积不清零；观察者在 end_turn 生效")
	lines.append("  D 指令行：loop 复读两次（逐次推阶）、parallel 阶数冻结、收尾清缓冲")
	lines.append("  上限 %d 回合（超时记负局）；均回合 = 胜局平均" % MAX_TURNS)
	lines.append("择优评估器（独立实现，权重为模拟器自定）：")
	lines.append("  收益 = Σ攻击有效伤害(hp×%.1f + 削敌盾×%.1f) + Σ格挡抵消(敌意图=attack时 min(格挡,意图值)×1.0)" % [W_HP, W_EBLK])
	lines.append("       + 米饭每碗+%.1f + 本序列点火睡醒+%.1f（跨回合粗略加权）" % [W_RICE, W_AWAKE])
	lines.append("")
	lines.append("关卡 ｜ 乱序胜率 ｜ 乱序均回合 ｜ 择优胜率 ｜ 择优均回合 ｜ 胜率差(pp) ｜ 相对收益 ｜ 择优观察者触发局")
	lines.append("─────┼──────────┼────────────┼──────────┼────────────┼───────────┼──────────┼────────────────")

	var sum_a_win := 0
	var sum_b_win := 0
	var rel_gains: Array[float] = []
	var level_b_rates: Array[float] = []
	var combo_stats := {}   ## 开局组合 → {n, a, b}（10 关合计）
	for li in LEVELS.size():
		var lv: Dictionary = LEVELS[li]
		## seed 基底 = 424242 + level_index*7919（任务公式）；每局 +r 偏移，
		## 保证 200 局是 200 场独立随机对局（基底单独用会 200 局同一对局）
		var seed_base := BASE_SEED + li * SEED_STEP
		var a_win := 0
		var a_turn_sum := 0
		var b_win := 0
		var b_turn_sum := 0
		var b_observer := 0
		for r in RUNS_PER_LEVEL:
			var seed_i := seed_base + r
			# 同局同 seed 下两策略 rng 流同步（打整手 → 抽牌次数恒同），纯对照顺序差异
			var ra := _run_battle(deck, lv, seed_i, false)
			if bool(ra["win"]):
				a_win += 1
				a_turn_sum += int(ra["turns"])
			var rb := _run_battle(deck, lv, seed_i, true)
			if bool(rb["win"]):
				b_win += 1
				b_turn_sum += int(rb["turns"])
			if bool(rb["observer"]):
				b_observer += 1
			## 组合分桶（乱序/择优同局同 seed，共用一个桶）
			var combo_key := String(ra["combo"])
			if not combo_stats.has(combo_key):
				combo_stats[combo_key] = {"n": 0, "a": 0, "b": 0}
			var cs: Dictionary = combo_stats[combo_key]
			cs["n"] = int(cs["n"]) + 1
			if bool(ra["win"]):
				cs["a"] = int(cs["a"]) + 1
			if bool(rb["win"]):
				cs["b"] = int(cs["b"]) + 1
		var a_rate := float(a_win) / RUNS_PER_LEVEL
		var b_rate := float(b_win) / RUNS_PER_LEVEL
		var a_avg := float(a_turn_sum) / a_win if a_win > 0 else 0.0
		var b_avg := float(b_turn_sum) / b_win if b_win > 0 else 0.0
		var diff_pp := (b_rate - a_rate) * 100.0
		var rel := 0.0
		if a_rate > 0.0:
			rel = (b_rate - a_rate) / a_rate
		elif b_rate > 0.0:
			rel = INF
		rel_gains.append(rel if rel != INF else 9.99)
		level_b_rates.append(b_rate)
		sum_a_win += a_win
		sum_b_win += b_win
		var rel_str := "∞" if rel == INF else "%.1f%%" % (rel * 100.0)
		var line := "%-4s ｜ %7s ｜ %9.1f ｜ %7s ｜ %9.1f ｜ %8.1f ｜ %8s ｜ %d/%d" % [
			lv["id"], _fmt_pct(a_rate), a_avg, _fmt_pct(b_rate), b_avg,
			diff_pp, rel_str, b_observer, RUNS_PER_LEVEL,
		]
		lines.append(line)
		print(line)

	lines.append("─────┴──────────┴────────────┴──────────┴────────────┴───────────┴──────────┴────────────────")
	var tot_a := float(sum_a_win) / (RUNS_PER_LEVEL * LEVELS.size())
	var tot_b := float(sum_b_win) / (RUNS_PER_LEVEL * LEVELS.size())
	lines.append("合计 ｜ %7s ｜           ｜ %7s ｜            ｜ %8.1f ｜           ｜" % [_fmt_pct(tot_a), _fmt_pct(tot_b), (tot_b - tot_a) * 100.0])
	print("合计  乱序 %s  择优 %s" % [_fmt_pct(tot_a), _fmt_pct(tot_b)])

	# ── 开局组合统计（T5 全牌堆采样后：开局组合只影响首回合，不再锁死命运）──
	lines.append("")
	lines.append("──── 开局手牌组合统计（10 关 × 200 局合计；仅反映首回合组合的影响）────")
	lines.append("开局组合              ｜ 局数 ｜ 乱序胜率 ｜ 择优胜率 ｜ 排序增益(pp)")
	var combo_keys: Array = combo_stats.keys()
	combo_keys.sort_custom(func(a, b):
		var da: Dictionary = combo_stats[a]
		var db: Dictionary = combo_stats[b]
		return int(db["b"]) * int(da["n"]) > int(da["b"]) * int(db["n"]))
	for ck in combo_keys:
		var cs: Dictionary = combo_stats[ck]
		var n := int(cs["n"])
		var ar := float(int(cs["a"])) / n
		var br := float(int(cs["b"])) / n
		lines.append("%-20s ｜ %4d ｜ %7s ｜ %7s ｜ %+.1f" % [ck, n, _fmt_pct(ar), _fmt_pct(br), (br - ar) * 100.0])
		print("combo %-20s n=%d 乱序%s 择优%s" % [ck, n, _fmt_pct(ar), _fmt_pct(br)])

	# ── T5 定稿验收指标 ──
	var avg_rel := 0.0
	for g in rel_gains:
		avg_rel += g
	avg_rel /= rel_gains.size()
	var l10_b: float = level_b_rates[9] if level_b_rates.size() >= 10 else 0.0
	var pass_a := avg_rel >= 0.15
	var pass_b := tot_b >= 0.40 and tot_b <= 0.65
	var pass_c := l10_b >= 0.25
	lines.append("")
	lines.append("────────────── T5 定稿验收指标 ──────────────")
	lines.append("a) 排序相对收益（全场平均）≥ 15%%：实际 %.1f%% → %s" % [avg_rel * 100.0, "PASS" if pass_a else "FAIL"])
	lines.append("b) 择优总胜率落在 40%%~65%%：实际 %s → %s" % [_fmt_pct(tot_b), "PASS" if pass_b else "FAIL"])
	lines.append("c) L10 择优胜率 ≥ 25%%：实际 %s → %s" % [_fmt_pct(l10_b), "PASS" if pass_c else "FAIL"])
	lines.append("三项判定：%s" % ("全部 PASS，可定稿" if (pass_a and pass_b and pass_c) else "存在 FAIL，需继续调参"))
	lines.append("")
	lines.append("────────────── 调参建议（供 T5 下一轮参考）──────────────")
	var suggest: Array[String] = []
	if not pass_a:
		suggest.append("· 排序收益 %.1f%% < 15%%：建议 LEAD_BONUS 1→2 或 FINISH_BONUS 2→3（二选一），"
				% (avg_rel * 100.0) + "让首尾槽位决策更值钱。")
	else:
		suggest.append("· 排序收益 %.1f%% ≥ 15%%：顺序杠杆达标。" % (avg_rel * 100.0))
	if tot_b > 0.70:
		suggest.append("· 择优总胜率 %s > 70%%：建议 OBS_CHARGE 3→4（发育流被惩罚更狠）。" % _fmt_pct(tot_b))
	elif tot_b < 0.40:
		suggest.append("· 择优总胜率 %s < 40%%：整体偏难，可放宽 OBS_CHARGE 或 OBS_BRACE。" % _fmt_pct(tot_b))
	else:
		suggest.append("· 择优总胜率 %s 在目标区间。" % _fmt_pct(tot_b))
	if l10_b < 0.25:
		suggest.append("· L10 择优胜率 %s < 25%%：BOSS 关对最优操作压力过大。" % _fmt_pct(l10_b))
	else:
		suggest.append("· L10 择优胜率 %s ≥ 25%%：BOSS 有压力但不绝望。" % _fmt_pct(l10_b))
	for s in suggest:
		lines.append(s)
	lines.append("· 观察者触发：鸽笼定理——3 张手牌只有攻/发育两类必有 ≥2 同类，「≥2」恒成立，")
	lines.append("  观察者=每回合必发动的变招，强度（OBS_BRACE=%d / OBS_CHARGE=%d）是调参杠杆。" % [OBS_BRACE, OBS_CHARGE])
	lines.append("· T5 全牌堆采样后每回合手牌跨回合变化，开局组合不再锁死命运；")
	lines.append("  排序收益（连段/槽位/成长时机）在全卡组随机样本上逐回合重新展开。")
	var report := "\n".join(lines)
	var path := "res://.godot/sim_report.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		path = "user://sim_report.txt"
		f = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(report)
		f.close()
	print("")
	print(report)
	print("")
	print("[sim] 报告已写入：%s" % path)
	quit()
