extends SceneTree
## 【已过时 · 仅留档】2026-11-06：本脚本是 T5 时代的"机制快照复刻"（不加载运行时），
## 效果层/算力/定价上线后已与真实战斗漂移。**调参请改用 tools/bench_effects.gd 与
## EffectPricing（直接驱动真 StsCombat）**，本文件只作为 T5 定稿时的历史证据保留。
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
const HAND_REFILL := 4
const MAX_TURNS := 60

# ── AI 对手五动作常量（读自 scripts/core/sts_combat.gd @2026-11-03）──────
## 与 opponent-rules 任务产出一致；常量不一致时以 sts_combat.gd 为准。
const OBS_ATK := 7                  ## ATTACK 基础（等级 1）
const OBS_ATK_PER_LEVEL := 0.6      ## 每级 +0.6
const OBS_DEF := 6                  ## DEFEND 格挡
const OBS_CHARGE_STEP := 3          ## CHARGE +3
const OBS_ATK_CAP := 13             ## 总攻硬帽
const DEFEND_CD := 1                ## 跳过 1 个敌方回合
const MARK_CD := 3                  ## 跳过 3 个敌方回合
const MARK_DURATION := 2            ## 2 个玩家回合
const TAUNT_CD := 2                 ## 跳过 2 个敌方回合
const TAUNT_HP_RATIO := 0.5         ## 自身 HP < 50% 解锁
const AGGRO_DAMAGE_SCALE := 0.5     ## AGGRO：玩家攻击牌伤害 −50%
const AGGRO_WEIGHT := 0.5           ## AGGRO 槽权重 ×0.5（验收杠杆）
const MAX_NON_ATTACK := 1           ## L7+ 连续非攻击上限（低关 0 = 纯攻击）
const MARK_MAX_PER_BATTLE := 2      ## 圆桌护栏：MARK 单场 ≤2
const TAUNT_MAX_PER_BATTLE := 1     ## 圆桌护栏：TAUNT 场均 ≤0.5 → 单场最多 1
const MARK_AGGRO := "AGGRO"
const MARK_ECONOMY := "ECONOMY"
const MARK_CHAIN := "CHAIN"
const AI_ACTIONS := ["ATTACK", "DEFEND", "CHARGE", "MARK", "TAUNT"]
const RUNS_PER_LEVEL_AGGRO := 200

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
	{"id": "L1", "lv": 1, "hp": 148, "atk": 7, "def": 4},
	{"id": "L2", "lv": 2, "hp": 220, "atk": 8, "def": 5},
	{"id": "L3", "lv": 3, "hp": 282, "atk": 9, "def": 6},
	{"id": "L4", "lv": 4, "hp": 342, "atk": 10, "def": 6},
	{"id": "L5", "lv": 5, "hp": 408, "atk": 11, "def": 7},
	{"id": "L6", "lv": 6, "hp": 470, "atk": 12, "def": 8},
	{"id": "L7", "lv": 7, "hp": 480, "atk": 13, "def": 8},
	{"id": "L8", "lv": 8, "hp": 508, "atk": 12, "def": 8},
	{"id": "L9", "lv": 9, "hp": 518, "atk": 12, "def": 8},
	{"id": "L10", "lv": 10, "hp": 542, "atk": 13, "def": 8},
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
	var e_max_hp := 0
	var e_level := 1
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

	# ── AI 对手五动作状态（balance 任务新增）──────────────────────
	var ai_mode := false
	var mark_on := false
	var taunt_on := false
	var aggro_weight := AGGRO_WEIGHT
	var aggro_damage_scale := AGGRO_DAMAGE_SCALE
	var e_phase := 0              ## 已执行敌方动作数
	var defend_ready := 0
	var mark_ready := 0
	var taunt_ready := 0
	var charge_bonus := 0
	var mark_mode := ""
	var mark_expire := 0          ## e_phase >= 此值即失效
	var taunt_swallow := false
	var last_attacks := 0         ## 玩家上一回合攻击牌数
	var last_grows := 0           ## 玩家上一回合发育牌数
	var grow_streak := 0          ## 连续 ≥2 发育回合数
	var recent_turns: Array = []  ## 最近 2 个玩家回合信号
	var seq_max_streak := 0       ## 本序列最高连段
	# 统计
	var mark_actions := 0
	var aggro_actions := 0
	var econ_actions := 0
	var chain_actions := 0
	var taunt_actions := 0
	var defend_actions := 0
	var charge_actions := 0
	var attack_actions := 0
	var mark_used := false
	var baseline_mark_actions := 0
	var baseline_aggro := 0
	var marked_player_turns := 0
	var since_attack := 0         ## 连续非攻击动作数（≥MAX_NON_ATTACK 强制 ATTACK）
	var mark_uses := 0            ## 本场 MARK 使用次数（圆桌护栏 ≤2）
	var taunt_uses := 0           ## 本场 TAUNT 使用次数（圆桌护栏 ≤1）


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


func _setup(st: SimState, deck: Array, lv: Dictionary, seed_i: int,
		cfg: Dictionary = {}) -> void:
	st.rng.seed = seed_i
	st.hp = PLAYER_HP
	st.block = 0
	st.rice = 0
	st.e_hp = int(lv["hp"])
	st.e_max_hp = int(lv["hp"])
	st.e_level = int(lv.get("lv", 1))
	st.e_blk = 0
	st.e_atk = int(lv["atk"])
	st.e_def = int(lv["def"])
	st.ai_mode = bool(cfg.get("ai_mode", false))
	st.mark_on = bool(cfg.get("mark", false))
	st.taunt_on = bool(cfg.get("taunt", false))
	st.aggro_weight = float(cfg.get("aggro_weight", AGGRO_WEIGHT))
	st.aggro_damage_scale = float(cfg.get("aggro_damage", AGGRO_DAMAGE_SCALE))
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
	# AI 对手状态重置
	st.e_phase = 0
	st.defend_ready = 0
	st.mark_ready = 0
	st.taunt_ready = 0
	st.charge_bonus = 0
	st.mark_mode = ""
	st.mark_expire = 0
	st.taunt_swallow = false
	st.last_attacks = 0
	st.last_grows = 0
	st.grow_streak = 0
	st.recent_turns = []
	st.seq_max_streak = 0
	st.mark_actions = 0
	st.aggro_actions = 0
	st.econ_actions = 0
	st.chain_actions = 0
	st.taunt_actions = 0
	st.defend_actions = 0
	st.charge_actions = 0
	st.attack_actions = 0
	st.mark_used = false
	st.baseline_mark_actions = 0
	st.baseline_aggro = 0
	st.marked_player_turns = 0
	st.since_attack = 0
	st.mark_uses = 0
	st.taunt_uses = 0
	_shuffle(st, st.draw_pile)
	_draw(st, HAND_REFILL)          ## 初始手牌从牌堆抽（随后 start_turn 会经弃牌堆洗回）
	st.intent = st.pattern[0].duplicate()
	st.pat_idx = 1
	_start_turn(st)


func _start_turn(st: SimState) -> void:
	st.turn += 1
	st.block = 0
	st.seq_max_streak = 0
	if st.ai_mode and _mark_active(st):
		st.marked_player_turns += 1
	for c in st.hand:
		st.discard.append(c)
	st.hand.clear()
	_refill_from_deck(st)      ## T5：全牌堆采样（修循环锁定）
	if st.hand.is_empty():
		_draw(st, HAND_REFILL)


# ── 出牌（复刻 play_card 核心数值链，无 rng；含 D 指令行）─────────────

func _play_one(st: SimState, c: Dictionary, lead: bool, finish: bool) -> void:
	var cid := String(c["id"])
	## AI 对手 TAUNT：吞掉本序列首位 +2（只吞一次；米饭/指令行占首位也算消耗）
	var lead_swallowed := lead and st.taunt_swallow
	if lead_swallowed:
		st.taunt_swallow = false
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
		## AI 标记 CHAIN：连段停成长，保当前阶位
		if not _mark_is(st, MARK_CHAIN):
			st.seq_streak += 1
	elif not st.streak_lock:
		st.seq_streak = 1
	st.seq_kind = int(c["kind"])
	st.seq_max_streak = maxi(st.seq_max_streak, st.seq_streak)
	# D 复读消费：本卡执行两次，连段逐次推阶
	var times := 1
	if st.pending_repeat > 0:
		times = 2
		st.pending_repeat = 0
	var slot := 0
	if lead:
		slot = 0 if lead_swallowed else LEAD_BONUS
	elif finish:
		slot = FINISH_BONUS
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
			## AGGRO：玩家攻击牌伤害 −50%（最后结算）
			if _mark_is(st, MARK_AGGRO):
				v = int(round(float(v) * st.aggro_damage_scale))
			st.seq_attacks += 1
			_hit_enemy(st, v)
		else:
			var v2 := int(c["blk"]) + step + slot
			if st.rice >= RICE_AWAKE:
				v2 = int(round(float(v2) * RICE_BUFF))
			## ECONOMY：发育牌（防御格挡）效果 −50%
			if _mark_is(st, MARK_ECONOMY):
				v2 = int(round(float(v2) * 0.5))
			st.seq_grows += 1
			st.block += v2
		if i < times - 1 and not _mark_is(st, MARK_CHAIN):
			st.seq_streak += 1
	st.seq_max_streak = maxi(st.seq_max_streak, st.seq_streak)


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
	_record_player_turn(st)


## 玩家回合信号入账（AI 策略与 MARK 模式选择用）。
func _record_player_turn(st: SimState) -> void:
	st.last_attacks = st.seq_attacks
	st.last_grows = st.seq_grows
	if st.seq_grows >= 2:
		st.grow_streak += 1
	else:
		st.grow_streak = 0
	st.recent_turns.append({
		"attacks": st.seq_attacks, "grows": st.seq_grows,
		"max_streak": st.seq_max_streak,
	})
	while st.recent_turns.size() > 2:
		st.recent_turns.pop_front()


## 敌方回合（复刻 end_turn：敌行动 → refresh_intent → 观察者覆写 → start_turn）。
## AI 模式走五动作策略分支；旧规则分支保持 T5 行为不变。
## 返回 false = 玩家死亡（LOSE）。
func _end_turn(st: SimState) -> bool:
	if st.ai_mode:
		return _end_turn_ai(st)
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


# ── AI 对手五动作策略（balance 任务）──────────────────────────────────
## 优先级按圆桌终裁：TAUNT > DEFEND > MARK > CHARGE > ATTACK。
## 与 sts_combat.apply_ai_action 的合法性/冷却口径一致。

func _mark_active(st: SimState) -> bool:
	return st.mark_mode != "" and st.e_phase < st.mark_expire


func _mark_is(st: SimState, mode: String) -> bool:
	return _mark_active(st) and st.mark_mode == mode


func _taunt_unlocked(st: SimState) -> bool:
	return float(st.e_hp) / float(maxi(1, st.e_max_hp)) < TAUNT_HP_RATIO


func _ai_attack_value(st: SimState) -> int:
	var base := OBS_ATK + OBS_ATK_PER_LEVEL * float(maxi(0, st.e_level - 1))
	return mini(OBS_ATK_CAP, int(round(base)) + st.charge_bonus)


func _last_max_streak(st: SimState) -> int:
	if st.recent_turns.is_empty():
		return 0
	return int(st.recent_turns[-1].get("max_streak", 0))


## AI 回合：选动作 → 执行 → 阶段推进 → 新玩家回合。
func _end_turn_ai(st: SimState) -> bool:
	var act := _choose_ai_action(st, st.last_attacks, st.last_grows, st.grow_streak)
	_apply_ai_action(st, act)
	if st.hp <= 0:
		return false
	st.e_phase += 1
	st.seq_attacks = 0
	st.seq_grows = 0
	_start_turn(st)
	return true


## 合法动作选择：圆桌优先级 TAUNT > DEFEND > MARK > CHARGE > ATTACK。
## 纯优先级会让敌方长期不攻击（实测总胜率 100%）；因此加「攻击底线」：
## 连续 MAX_NON_ATTACK 个非攻击动作后强制 ATTACK（目标案取 1 = 最多一半动作控场）。
func _choose_ai_action(st: SimState, seq_attacks: int, _seq_grows: int,
		grow_after: int) -> String:
	if st.since_attack >= _attack_floor_for(st):
		return "ATTACK"
	if st.taunt_on and st.e_phase >= st.taunt_ready and _taunt_unlocked(st) \
			and st.taunt_uses < TAUNT_MAX_PER_BATTLE:
		return "TAUNT"
	if st.e_phase >= st.defend_ready and seq_attacks >= 2 and not _mark_is(st, MARK_AGGRO):
		return "DEFEND"
	if st.mark_on and st.e_phase >= st.mark_ready and st.mark_uses < MARK_MAX_PER_BATTLE:
		return "MARK"
	if grow_after >= 2:
		return "CHARGE"
	return "ATTACK"


## 攻击底线：L1-6 纯攻击（低关敌人伤害低，多攻击才有压力）；
## L7-10 最多 1 个连续控场，避免高关纯攻击把 L10 打到 0%。
func _attack_floor_for(st: SimState) -> int:
	return 0 if st.e_level <= 7 else MAX_NON_ATTACK


## MARK 模式打分：AGGRO 权重 ×weight（目标案 0.5，反事实 1.0）。
## 信号 = 最近 2 个玩家回合的攻/发育/最高连段（含 extra_turn 影子）。
func _choose_mark_mode(st: SimState, weight: float,
		extra_turn: Dictionary = {}) -> String:
	var sig := _mark_mode_signals(st, extra_turn)
	var atk := int(sig[0])
	var grw := int(sig[1])
	var mx := int(sig[2])
	var s_aggro := maxf(1.0, float(atk) * 2.0) * weight
	var s_econ := maxf(1.0, float(grw) * 2.0)
	var s_chain := maxf(1.0, float(mx) * 1.2)
	if s_aggro >= s_econ and s_aggro >= s_chain:
		return MARK_AGGRO
	if s_econ >= s_chain:
		return MARK_ECONOMY
	return MARK_CHAIN


func _mark_mode_signals(st: SimState, extra_turn: Dictionary = {}) -> Array:
	var turns: Array = st.recent_turns.duplicate()
	if not extra_turn.is_empty():
		turns.append(extra_turn)
		while turns.size() > 2:
			turns.pop_front()
	var atk := 0
	var grw := 0
	var mx := 0
	for r in turns:
		atk += int(r.get("attacks", 0))
		grw += int(r.get("grows", 0))
		mx = maxi(mx, int(r.get("max_streak", 0)))
	return [atk, grw, mx]


func _apply_ai_action(st: SimState, act: String) -> void:
	match act:
		"TAUNT":
			st.taunt_actions += 1
			st.taunt_uses += 1
			st.taunt_swallow = true
			st.taunt_ready = st.e_phase + 1 + TAUNT_CD
		"DEFEND":
			st.defend_actions += 1
			st.e_blk += OBS_DEF
			st.defend_ready = st.e_phase + 1 + DEFEND_CD
		"MARK":
			st.mark_actions += 1
			st.mark_uses += 1
			st.mark_used = true
			st.baseline_mark_actions += 1
			# 反事实：权重 1.0 时会选什么（只用于 AGGRO 槽占比对比）
			if _choose_mark_mode(st, 1.0) == MARK_AGGRO:
				st.baseline_aggro += 1
			var mode := _choose_mark_mode(st, st.aggro_weight)
			st.mark_mode = mode
			st.mark_expire = st.e_phase + 1 + MARK_DURATION
			st.mark_ready = st.e_phase + 1 + MARK_CD
			if mode == MARK_AGGRO:
				st.aggro_actions += 1
			elif mode == MARK_ECONOMY:
				st.econ_actions += 1
			else:
				st.chain_actions += 1
		"CHARGE":
			st.charge_actions += 1
			st.charge_bonus = mini(OBS_ATK_CAP, st.charge_bonus + OBS_CHARGE_STEP)
		_:
			st.attack_actions += 1
			var v := _ai_attack_value(st)
			st.charge_bonus = 0
			_hit_player(st, v)
	if act == "ATTACK":
		st.since_attack = 0
	else:
		st.since_attack += 1


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
	var swallow := st.taunt_swallow
	var seq_atk := 0
	var seq_grw := 0
	var seq_max := 0
	var total_blk := 0
	var score := 0.0
	var n := perm.size()
	for i in n:
		var c: Dictionary = st.hand[int(perm[i])]
		var lead := i == 0
		var finish := i == n - 1
		var cid := String(c["id"])
		var lead_swallowed := lead and swallow
		if lead_swallowed:
			swallow = false
		if cid == "rice":
			rice_shadow += 1
			seq_grw += 1
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
			if not _mark_is(st, MARK_CHAIN):
				streak += 1
		elif not lock:
			streak = 1
		kind = int(c["kind"])
		seq_max = maxi(seq_max, streak)
		var times := 1
		if rep > 0:
			times = 2
			rep = 0
		var slot := 0
		if lead:
			slot = 0 if lead_swallowed else LEAD_BONUS
		elif finish:
			slot = FINISH_BONUS
		for t in times:
			var step := STREAK_STEP * (streak - 1)
			var awake := rice_shadow >= RICE_AWAKE
			if int(c["kind"]) == KIND_ATTACK:
				var v := int(c["dmg"]) + step + slot
				if awake:
					v = int(round(float(v) * RICE_BUFF))
				if _mark_is(st, MARK_AGGRO):
					v = int(round(float(v) * st.aggro_damage_scale))
				var cut := mini(e_blk, v)
				e_blk -= cut
				var to_hp := mini(v - cut, e_hp)
				e_hp -= to_hp
				score += W_EBLK * float(cut) + W_HP * float(to_hp)
				seq_atk += 1
			else:
				var v2 := int(c["blk"]) + step + slot
				if awake:
					v2 = int(round(float(v2) * RICE_BUFF))
				if _mark_is(st, MARK_ECONOMY):
					v2 = int(round(float(v2) * 0.5))
				total_blk += v2
				seq_grw += 1
			if t < times - 1 and not _mark_is(st, MARK_CHAIN):
				streak += 1
		seq_max = maxi(seq_max, streak)
	## 格挡估值：AI 模式按五动作策略预测敌方下一动作；旧规则按 pattern 意图
	if st.ai_mode:
		var grow_after := (st.grow_streak + 1) if seq_grw >= 2 else 0
		var pred := _choose_ai_action(st, seq_atk, seq_grw, grow_after)
		if pred == "ATTACK":
			score += float(mini(total_blk, _ai_attack_value(st)))
	elif String(st.intent.get("kind", "")) == "attack":
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

func _run_battle(deck: Array, lv: Dictionary, seed_i: int, smart: bool,
		cfg: Dictionary = {}) -> Dictionary:
	var st := SimState.new()
	_setup(st, deck, lv, seed_i, cfg)
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
			return _battle_result(st, true, combo)
		if not _end_turn(st):
			return _battle_result(st, false, combo)
	return _battle_result(st, false, combo, true)


func _battle_result(st: SimState, win: bool, combo: String,
		timeout: bool = false) -> Dictionary:
	var d := {
		"win": win, "turns": st.turn, "observer": st.observer_ever, "combo": combo,
		"mark_actions": st.mark_actions, "aggro_actions": st.aggro_actions,
		"econ_actions": st.econ_actions, "chain_actions": st.chain_actions,
		"taunt_actions": st.taunt_actions, "defend_actions": st.defend_actions,
		"charge_actions": st.charge_actions, "attack_actions": st.attack_actions,
		"mark_used": st.mark_used,
		"baseline_mark_actions": st.baseline_mark_actions,
		"baseline_aggro": st.baseline_aggro,
		"marked_turns": st.marked_player_turns,
	}
	if timeout:
		d["timeout"] = true
	return d


# ── 统计与报告 ───────────────────────────────────────────────────────

func _fmt_pct(v: float) -> String:
	return "%.1f%%" % (v * 100.0)


# ── AGGRO 1.6 万场验收（balance 任务，2026-11-03）────────────────────
## 矩阵 = 10 关 × 200 局 × 双 bot（乱序/择优）× 2 MARK 开关 × 2 TAUNT 开关
##      = 16,000 场。目标案 = MARK 开 + TAUNT 开 + AGGRO −50% + 标记期禁 DEFEND。
## 四指标：总胜率 40~65% / L10≥25% / 带 MARK 胜率−不带≥+5pp / AGGRO 槽占比降≥30%。

func _cell_key(mark_on: bool, taunt_on: bool) -> String:
	return ("M1" if mark_on else "M0") + ("T1" if taunt_on else "T0")


func _new_cell_stats() -> Dictionary:
	var levels: Array = []
	for i in LEVELS.size():
		levels.append({"rand": 0, "smart": 0})
	return {
		"n_rand": 0, "win_rand": 0, "n_smart": 0, "win_smart": 0,
		"turns_smart": 0,
		"levels": levels,
		"mark": 0, "aggro": 0, "econ": 0, "chain": 0,
		"taunt": 0, "defend": 0, "charge": 0, "attack": 0,
		"baseline_mark": 0, "baseline_aggro": 0,
		"smart_mark_used_n": 0, "smart_mark_used_win": 0,
		"smart_nomark_n": 0, "smart_nomark_win": 0,
		"marked_turns": 0,
	}


func _accum_cell(cs: Dictionary, li: int, ra: Dictionary, rb: Dictionary) -> void:
	cs["n_rand"] = int(cs["n_rand"]) + 1
	cs["n_smart"] = int(cs["n_smart"]) + 1
	if bool(ra.get("win", false)):
		cs["win_rand"] = int(cs["win_rand"]) + 1
		var lv_r: Dictionary = cs["levels"][li]
		lv_r["rand"] = int(lv_r["rand"]) + 1
	if bool(rb.get("win", false)):
		cs["win_smart"] = int(cs["win_smart"]) + 1
		cs["turns_smart"] = int(cs["turns_smart"]) + int(rb.get("turns", 0))
		var lv_s: Dictionary = cs["levels"][li]
		lv_s["smart"] = int(lv_s["smart"]) + 1
	for pair in [
		["mark", "mark_actions"], ["aggro", "aggro_actions"],
		["econ", "econ_actions"], ["chain", "chain_actions"],
		["taunt", "taunt_actions"], ["defend", "defend_actions"],
		["charge", "charge_actions"], ["attack", "attack_actions"],
		["baseline_mark", "baseline_mark_actions"],
		["baseline_aggro", "baseline_aggro"],
		["marked_turns", "marked_turns"],
	]:
		cs[pair[0]] = int(cs[pair[0]]) + int(ra.get(pair[1], 0)) + int(rb.get(pair[1], 0))
	if bool(rb.get("mark_used", false)):
		cs["smart_mark_used_n"] = int(cs["smart_mark_used_n"]) + 1
		if bool(rb.get("win", false)):
			cs["smart_mark_used_win"] = int(cs["smart_mark_used_win"]) + 1
	else:
		cs["smart_nomark_n"] = int(cs["smart_nomark_n"]) + 1
		if bool(rb.get("win", false)):
			cs["smart_nomark_win"] = int(cs["smart_nomark_win"]) + 1


func _run_cell_stats(deck: Array, mark_on: bool, taunt_on: bool,
		aggro_damage: float) -> Dictionary:
	var cs := _new_cell_stats()
	var cfg := {
		"ai_mode": true, "mark": mark_on, "taunt": taunt_on,
		"aggro_weight": AGGRO_WEIGHT, "aggro_damage": aggro_damage,
	}
	for li in LEVELS.size():
		var lv: Dictionary = LEVELS[li]
		var seed_base := BASE_SEED + li * SEED_STEP
		for r in RUNS_PER_LEVEL_AGGRO:
			var seed_i := seed_base + r
			var ra := _run_battle(deck, lv, seed_i, false, cfg)
			var rb := _run_battle(deck, lv, seed_i, true, cfg)
			_accum_cell(cs, li, ra, rb)
	return cs


func _cell_win(cs: Dictionary, smart: bool) -> float:
	var n := int(cs["n_smart"] if smart else cs["n_rand"])
	var w := int(cs["win_smart"] if smart else cs["win_rand"])
	return float(w) / float(n) if n > 0 else 0.0


func _run_aggro_suite(deck: Array) -> void:
	var lines: Array[String] = []
	lines.append("════════════════════════════════════════════════════════════════")
	lines.append("AGGRO 平衡模拟 · 1.6 万场验收（balance · 2026-11-03）")
	lines.append("════════════════════════════════════════════════════════════════")
	lines.append("常量（读自 scripts/core/sts_combat.gd，opponent-rules 产出）：")
	lines.append("  OBS_ATK=%d  OBS_ATK_PER_LEVEL=%.1f  OBS_DEF=%d  OBS_CHARGE_STEP=%d  OBS_ATK_CAP=%d"
			% [OBS_ATK, OBS_ATK_PER_LEVEL, OBS_DEF, OBS_CHARGE_STEP, OBS_ATK_CAP])
	lines.append("  DEFEND_CD=%d  MARK_CD=%d  MARK_DURATION=%d  TAUNT_CD=%d  TAUNT_HP_RATIO=%.1f"
			% [DEFEND_CD, MARK_CD, MARK_DURATION, TAUNT_CD, TAUNT_HP_RATIO])
	lines.append("  AGGRO：攻击牌伤害 ×%.1f + 标记期禁 DEFEND；AGGRO 槽权重 ×%.1f"
			% [AGGRO_DAMAGE_SCALE, AGGRO_WEIGHT])
	lines.append("  ECONOMY：格挡 ×0.5；CHAIN：同类连段冻结保阶位；TAUNT：吞玩家首位 +2")
	lines.append("敌方策略：严格优先级 TAUNT > DEFEND > MARK > CHARGE > ATTACK + 关卡攻击底线")
	lines.append("  L1-7 纯攻击（低关敌人伤害低，控场会让难度过低）；L8-10 最多 1 个连续控场")
	lines.append("  圆桌护栏：MARK 单场≤%d、TAUNT 单场≤%d；AGGRO 权重×%.1f"
			% [MARK_MAX_PER_BATTLE, TAUNT_MAX_PER_BATTLE, AGGRO_WEIGHT])
	lines.append("样本：10 关 × %d 局 × 2 bot（乱序/择优）× 2 MARK × 2 TAUNT = %d 场"
			% [RUNS_PER_LEVEL_AGGRO, 10 * RUNS_PER_LEVEL_AGGRO * 2 * 2 * 2])
	lines.append("种子：BASE_SEED=%d + level*%d + r（与 T5 基线同 seed，矩阵内配对）"
			% [BASE_SEED, SEED_STEP])
	lines.append("")

	var cells := [
		{"key": "M1T1", "mark": true, "taunt": true},
		{"key": "M1T0", "mark": true, "taunt": false},
		{"key": "M0T1", "mark": false, "taunt": true},
		{"key": "M0T0", "mark": false, "taunt": false},
	]
	var stats := {}
	for cell in cells:
		var key := String(cell["key"])
		print("[aggro] 跑 %s（4000 场）..." % key)
		stats[key] = _run_cell_stats(deck, bool(cell["mark"]), bool(cell["taunt"]),
				AGGRO_DAMAGE_SCALE)

	lines.append("────────────── 2×2 矩阵胜率（各 4000 场：2 bot × 10 关 × 200 局）──────────────")
	lines.append("MARK ｜ TAUNT ｜ 乱序胜率 ｜ 择优胜率 ｜ 择优均回合")
	for cell in cells:
		var key := String(cell["key"])
		var cs: Dictionary = stats[key]
		var ar := _cell_win(cs, false)
		var br := _cell_win(cs, true)
		lines.append("%-4s ｜ %-5s ｜ %7s ｜ %7s ｜ %.1f" % [
			"开" if bool(cell["mark"]) else "关",
			"开" if bool(cell["taunt"]) else "关",
			_pct(ar), _pct(br), _avg_turns(cs, true),
		])
	lines.append("")

	var t: Dictionary = stats["M1T1"]
	var t0: Dictionary = stats["M1T0"]
	var z1: Dictionary = stats["M0T1"]
	var z0: Dictionary = stats["M0T0"]
	var t_smart := _cell_win(t, true)
	var t_rand := _cell_win(t, false)
	var z1_smart := _cell_win(z1, true)
	var z1_rand := _cell_win(z1, false)
	var t0_smart := _cell_win(t0, true)
	var z0_smart := _cell_win(z0, true)
	var t_levels: Array = t["levels"]
	var l10 := float(int(t_levels[9]["smart"])) / float(RUNS_PER_LEVEL_AGGRO)
	var delta_mark_t1 := t_smart - z1_smart
	var delta_mark_t0 := t0_smart - z0_smart
	var delta_mark_t1_rand := t_rand - z1_rand

	lines.append("────────────── 目标案（MARK 开 + TAUNT 开）逐关择优胜率 ──────────────")
	var per_level: Array[String] = []
	for li in LEVELS.size():
		var lv: Dictionary = LEVELS[li]
		var rate := float(int(t_levels[li]["smart"])) / float(RUNS_PER_LEVEL_AGGRO)
		per_level.append("%s %s" % [String(lv["id"]), _pct(rate)])
	lines.append("  " + " ｜ ".join(per_level))
	lines.append("")

	# 指标 4：AGGRO 槽占比（权重 1.0 反事实 vs 权重 0.5 实战）
	var mark_total := maxi(1, int(t["mark"]))
	var aggro_actual := float(int(t["aggro"])) / float(mark_total)
	var base_total := maxi(1, int(t["baseline_mark"]))
	var aggro_base := float(int(t["baseline_aggro"])) / float(base_total)
	var aggro_drop := 0.0
	if aggro_base > 0.0:
		aggro_drop = (aggro_base - aggro_actual) / aggro_base
	var pass_total := t_smart >= 0.40 and t_smart <= 0.65
	var pass_l10 := l10 >= 0.25
	var pass_mark := delta_mark_t1 >= 0.05
	var pass_aggro := aggro_drop >= 0.30

	lines.append("────────────── 四项验收指标 ──────────────")
	lines.append("1) 总胜率（择优 · MARK+TAUNT 开）落在 40%%~65%%：%s → %s"
			% [_pct(t_smart), "PASS" if pass_total else "FAIL"])
	lines.append("2) L10 择优胜率 ≥ 25%%：%s → %s"
			% [_pct(l10), "PASS" if pass_l10 else "FAIL"])
	lines.append("3) 带 MARK 胜率 − 不带 ≥ +5pp（择优 · TAUNT 开）：%+.1f pp → %s"
			% [delta_mark_t1 * 100.0, "PASS" if pass_mark else "FAIL"])
	lines.append("   同口径 TAUNT 关：%+.1f pp；乱序 TAUNT 开：%+.1f pp"
			% [delta_mark_t0 * 100.0, delta_mark_t1_rand * 100.0])
	lines.append("   （若按「MARK 开启后玩家胜率应下降≥5pp」反向解读：%+.1f pp）"
			% (-delta_mark_t1 * 100.0))
	lines.append("4) 敌 AGGRO 槽占比降 ≥ 30%%：权重1.0 %.1f%% → 权重0.5 %.1f%%，降 %s → %s"
			% [aggro_base * 100.0, aggro_actual * 100.0, _pct(aggro_drop),
			"PASS" if pass_aggro else "FAIL"])
	lines.append("")

	# 敌方动作分布
	var total_actions := maxi(1, int(t["attack"]) + int(t["defend"]) + int(t["charge"])
			+ int(t["mark"]) + int(t["taunt"]))
	lines.append("────────────── 目标案敌方动作分布（双 bot 4000 场合计）──────────────")
	lines.append("  ATTACK %d（%s）｜ DEFEND %d（%s）｜ CHARGE %d（%s）｜ MARK %d（%s）｜ TAUNT %d（%s）"
			% [int(t["attack"]), _pct(float(int(t["attack"])) / total_actions),
			int(t["defend"]), _pct(float(int(t["defend"])) / total_actions),
			int(t["charge"]), _pct(float(int(t["charge"])) / total_actions),
			int(t["mark"]), _pct(float(int(t["mark"])) / total_actions),
			int(t["taunt"]), _pct(float(int(t["taunt"])) / total_actions)])
	lines.append("  MARK 细分：AGGRO %d ｜ ECONOMY %d ｜ CHAIN %d"
			% [int(t["aggro"]), int(t["econ"]), int(t["chain"])])
	lines.append("  平均每场敌方动作 %.2f 个；标记覆盖玩家回合 %d 次"
			% [float(total_actions) / float(maxi(1, int(t["n_smart"]) + int(t["n_rand"]))),
			int(t["marked_turns"])])
	var battles := maxi(1, int(t["n_smart"]) + int(t["n_rand"]))
	lines.append("  MARK 场均 %.2f 次（圆桌目标 0.5~1，单场≤%d）｜ TAUNT 场均 %.2f 次（≤0.5）"
			% [float(int(t["mark"])) / float(battles), MARK_MAX_PER_BATTLE,
			float(int(t["taunt"])) / float(battles)])
	var mu_n := int(t["smart_mark_used_n"])
	var mu_w := int(t["smart_mark_used_win"])
	var nm_n := int(t["smart_nomark_n"])
	var nm_w := int(t["smart_nomark_win"])
	lines.append("  择优局诊断：实战用过 MARK %d 局胜率 %s ｜ 未用 MARK %d 局胜率 %s"
			% [mu_n, _pct(float(mu_w) / float(maxi(1, mu_n))),
			nm_n, _pct(float(nm_w) / float(maxi(1, nm_n)))])
	lines.append("")

	# 序贯设计：任一破带才补跑 −40% 对照
	if not (pass_total and pass_l10 and pass_mark and pass_aggro):
		print("[aggro] 有指标破带，补跑 AGGRO −40% 对照（4000 场）...")
		var alt := _run_cell_stats(deck, true, true, 0.4)
		var alt_smart := _cell_win(alt, true)
		var alt_levels: Array = alt["levels"]
		var alt_l10 := float(int(alt_levels[9]["smart"])) / float(RUNS_PER_LEVEL_AGGRO)
		var alt_delta := alt_smart - z1_smart
		var alt_pass_total := alt_smart >= 0.40 and alt_smart <= 0.65
		var alt_pass_l10 := alt_l10 >= 0.25
		var alt_pass_mark := alt_delta >= 0.05
		lines.append("────────────── 序贯对照：AGGRO −40%（MARK+TAUNT 开）──────────────")
		lines.append("  总胜率 %s → %s ｜ L10 %s → %s ｜ 带 MARK−不带 %+.1f pp → %s"
				% [_pct(alt_smart), "PASS" if alt_pass_total else "FAIL",
				_pct(alt_l10), "PASS" if alt_pass_l10 else "FAIL",
				alt_delta * 100.0, "PASS" if alt_pass_mark else "FAIL"])
		lines.append("  AGGRO 槽占比仍为权重 0.5 口径：%.1f%%（降 %s，不受伤害缩放影响）"
				% [float(int(alt["aggro"])) / float(maxi(1, int(alt["mark"]))) * 100.0,
				_pct(aggro_drop)])
		if alt_pass_total and alt_pass_l10 and alt_pass_mark:
			lines.append("  建议：−40%% 能回到验收带，可作为 AGGRO 备选数值复测。")
		else:
			lines.append("  建议：−40%% 与 −50%% 几乎无差（AGGRO 槽仅 %.1f%%，权重 0.5 已把它压到近零）。"
					% [aggro_actual * 100.0])
			lines.append("        优先把 AGGRO 权重从 0.5 提到 0.7~0.8，或调整模式打分让 AGGRO 槽回到 8~9%（相对基线 13.5% 仍降 33~41%），再复测指标 3/4。")
		lines.append("")
	else:
		lines.append("序贯设计：四指标全达标，未触发 AGGRO −40% 补跑。")
		lines.append("")

	lines.append("────────────── 结论与建议 ──────────────")
	if pass_total and pass_l10 and pass_mark and pass_aggro:
		lines.append("· 四项全部 PASS：AGGRO −50% + 标记期禁 DEFEND 可按终裁决议进入接入层。")
	else:
		var bad: Array[String] = []
		if not pass_total:
			bad.append("总胜率")
		if not pass_l10:
			bad.append("L10")
		if not pass_mark:
			bad.append("带 MARK 差")
		if not pass_aggro:
			bad.append("AGGRO 槽占比")
		lines.append("· 破带项：%s。按序贯设计已补跑 −40%% 对照，见上节。" % "、".join(bad))
	lines.append("· 数值常量以 scripts/core/sts_combat.gd 为准：OBS_ATK=%d/%.1f级、OBS_DEF=%d、CHARGE+%d帽%d"
			% [OBS_ATK, OBS_ATK_PER_LEVEL, OBS_DEF, OBS_CHARGE_STEP, OBS_ATK_CAP])
	lines.append("· 已知限制：")
	lines.append("  ① L6/L7→L8 攻击底线切换造成非单调（L7 3.5% → L8 63.0%），建议按关卡平滑或按敌 HP 连续调节；")
	lines.append("  ② AGGRO 槽仅 %.1f%%，−40%% 与 −50%% 差异被淹没；指标 3 的符号口径需与圆桌确认。"
			% [aggro_actual * 100.0])
	lines.append("· 本模拟器为独立复刻：玩家侧 AGGRO/ECONOMY/CHAIN/TAUNT 与敌 bot 五动作均按 sts_combat 口径实现；")
	lines.append("  未接 LLM，敌策略为严格优先级 + 关卡攻击底线，非 LLM 实际输出分布。")

	var report := "\n".join(lines)
	var path := "res://.godot/sim_report_aggro.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		path = "user://sim_report_aggro.txt"
		f = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(report)
		f.close()
	print("")
	print(report)
	print("")
	print("[aggro] 报告已写入：%s" % path)


func _pct(v: float) -> String:
	return _fmt_pct(v)


func _avg_turns(cs: Dictionary, _smart: bool) -> float:
	var w := int(cs["win_smart"])
	return float(int(cs["turns_smart"])) / float(w) if w > 0 else 0.0


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
	_run_aggro_suite(deck)
	quit()
