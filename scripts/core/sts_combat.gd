class_name StsCombat
extends RefCounted
## 一场杀戮尖塔式战斗的**纯逻辑状态机**（无 UI，无 SceneTree 依赖）。
##
## 最纯粹的核心循环：
##   开战 → 抽 5 / 能量回满 3
##   → 出牌（攻击扣敌人血、防御给自己格挡；牌进弃牌堆）
##   → 结束回合 → 敌人按意图行动（攻击/防御）→ 手牌弃掉 → 新回合
##   牌堆抽干自动洗回弃牌堆。
##
## 敌人死亡 → over = WIN；玩家死亡 → over = LOSE。
## UI（arena.gd）只负责调用并渲染返回的事件列表。

enum Result { RUNNING, WIN, LOSE }

## 终结技充能满时通知 UI（arena 播提示音/点亮按钮）
signal ult_ready_changed(ready: bool)

const HEAL_ON_WIN := 6


var rng := RandomNumberGenerator.new()

# 玩家
var hp := 80
var max_hp := 80
var block := 0
## 算力（2026-11-05）：每回合 3 点，**只有 cost ≥2 的复杂指令才消耗**。
## cost 1 的基础卡免费——起始卡全是 cost 1，所以旧手感完全不变；
## 许愿卡按定价取 cost 1–3，cost 3 会吃掉整回合算力。
const ENERGY_PER_TURN := 3
var energy := ENERGY_PER_TURN
## 效果层状态（圆桌 v1）：id → {"tier": int, "turns": int}
## 数值走 EffectSpec.STATUSES 本地表；空字典 = 旧行为，所有修正项为恒等。
var p_status: Dictionary = {}
var e_status: Dictionary = {}
## 效果层：下一张牌倍率、抽牌/伤害触发重入保护与每回合上限、击杀只触发一次
var next_mult := 1.0
var _firing_draw := false
var _draw_fx_count := 0
var _kill_fired := false
var _firing_damage := false
var _damage_fx_count := 0

# ── 终结技「深度思考」（2026-11-05）──────────────────────
const ULT_MAX := 100
const ULT_PER_CARD := 8       ## 每条指令充能
const ULT_PER_HIT := 15       ## 每次受创充能
const ULT_DAMAGE := 40        ## 释放伤害（无视格挡）
var ult_charge := 0
## 手牌打空后从弃牌堆随机补几张：因角色而异（主人 2026-10-30，DeepSeek 默认 3）
const REFILL_BY_AI := {"deepdeek": 4}

## 白米饭成长（2026-10-31 主人钦定三段）：
##   0..1 碗 = 睡眠（躺）｜2..4 碗 = 翻身（坐起，仍睡眠）｜5 碗 = 完全觉醒（站立）
## 觉醒瞬间：赠 2 张特殊攻击牌进弃牌堆（鲸鱼铁头炮/觉醒怒涛），每局重置
const RICE_STIR := 2
const RICE_AWAKE := 5
const RICE_BUFF := 1.2
## ChatPPT 被动「模板对齐」：每回合第一张非指令行卡（攻/防）额外 +2。
const CHATPPT_FIRST_BONUS := 2
var ai_id := "deepdeek"
var _chatppt_bonus_used := false
var rice_eaten := 0
var _refill_count := 4
## 道具效果（run.start_battle 按持有道具注入）
var atk_bonus := 0        ## 提示词优化器：攻击牌伤害 +N
var hand_bonus := 0       ## 上下文压缩：手牌上限 +N

# ── 执行序列机制（2026-10-31 主人钦定 A/B/C/E）──────────
## 一回合 = 一次程序运行：发送执行整手 → 自动进入敌方回合。
## 玩家唯一的杠杆是队列顺序——连段、槽位、成长时机全部由此展开。
const STREAK_STEP := 3      ## A 连段阶梯：同类连击每进一阶 +3（6→9→12）
const LEAD_BONUS := 2       ## B 首位「初始化」：+2（热机，T5 定稿）
const FINISH_BONUS := 2     ## B 末位「收尾」：+2（大招）
var seq_streak := 0         ## 本序列同类连击阶数（1 起，0 = 未开打）
var seq_kind := -1          ## 连段类型
var seq_open := false       ## 正在执行序列（首位判定用）
var seq_attacks := 0        ## E 观察者统计：本序列攻击张数
var seq_grows := 0          ## E 观察者统计：本序列发育张数（饭/防）
var pending_repeat := 0     ## D 复读机：下一张非米饭卡执行两次
var streak_lock := false    ## D 并行：本序列换类型不断连
var last_observer_note := ""  ## 观察者反应（UI 日志用，读后即清）
const OBS_BRACE := 0        ## 观察者反爆牌：≥2 攻 → 敌下回合架基本盾（T5 定稿不加码）
const OBS_CHARGE := 3

# ── AI 对手规则层（LLM 接入 · 圆桌终案 v1.1，2026-11-03）────────
## 五动作白名单：LLM 只能出枚举，数值一律走下面的本地常量表。
## 旧观察者规则（≥2 攻 → 防御 / ≥2 发育 → 蓄力攻击）保留为 local_choose 兜底。
const AI_ATTACK := "ATTACK"
const AI_DEFEND := "DEFEND"
const AI_CHARGE := "CHARGE"
const AI_MARK := "MARK"
const AI_TAUNT := "TAUNT"
const AI_ACTIONS := ["ATTACK", "DEFEND", "CHARGE", "MARK", "TAUNT"]

## 数值常量表 v1（圆桌终案；balance 任务以此为准）
const OBS_ATK := 7                  ## 基础攻击（等级 1）
const OBS_ATK_PER_LEVEL := 0.6      ## 每级 +0.6
const OBS_DEF := 6                  ## DEFEND 格挡值
const OBS_CHARGE_STEP := 3          ## CHARGE 每次 +3
const OBS_ATK_CAP := 13             ## 总攻硬帽（含蓄力）
const DEFEND_CD := 1                ## 防御冷却：跳过 1 个敌方回合
const MARK_CD := 3                  ## 标记冷却：跳过 3 个敌方回合
const MARK_DURATION := 2            ## 标记持续：2 个玩家回合
const TAUNT_CD := 2                 ## 嘲讽冷却：跳过 2 个敌方回合
const TAUNT_HP_RATIO := 0.5         ## 自身 HP < 50% 解锁

## 针对标记三模式（效果全在本地表，AI 只出标签）
const MARK_AGGRO := "AGGRO"         ## 玩家攻击牌伤害 −50%，标记期敌方禁 DEFEND
const MARK_ECONOMY := "ECONOMY"     ## 玩家发育牌效果 −50%（格挡/米饭）
const MARK_CHAIN := "CHAIN"         ## 玩家连段停成长，保当前阶位
const AI_MARK_MODES := ["AGGRO", "ECONOMY", "CHAIN"]
const AI_ACTION_NAMES := {
	"ATTACK": "攻击", "DEFEND": "防御", "CHARGE": "蓄力",
	"MARK": "针对标记", "TAUNT": "嘲讽吞噬",
}
const AI_MARK_MODE_NAMES := {
	"AGGRO": "连攻针对", "ECONOMY": "发育针对", "CHAIN": "连段冻结",
}
const AI_ACTION_ALIASES := {
	"攻击": "ATTACK", "防御": "DEFEND", "蓄力": "CHARGE",
	"标记": "MARK", "针对标记": "MARK", "嘲讽": "TAUNT", "嘲讽吞噬": "TAUNT",
}

# 敌人
var enemy_name := ""
var enemy_hp := 1
var enemy_max_hp := 1
var enemy_block := 0
var enemy_atk := 6
var enemy_def := 4
## 意图：{"kind": "attack"/"defend", "value": int}
var intent: Dictionary = {}
var _pattern: Array = []
var _pattern_idx := 0

# 牌堆
var draw_pile: Array[StsCard] = []
var hand: Array[StsCard] = []
var discard_pile: Array[StsCard] = []

var turn := 0
var over: int = Result.RUNNING
var damage_dealt := 0
## 精英怪标记（15% 概率，红光+宝箱掉落，主人 2026-11-01）
var is_elite := false

# ── AI 对手运行时状态（默认全关：不调用 apply_ai_action 时旧规则零差异）──
var ai_action := ""                 ## 最近一次 AI 动作（枚举）
var ai_action_reason := ""          ## 最近一次 AI 台词/理由（永不进数值管线）
var enemy_level := 1                ## 敌人等级：ATTACK = OBS_ATK + 0.6×(级-1)
var mark_mode := ""                 ## 当前针对标记模式
var mark_expire_phase := 0          ## 标记失效阶段：_enemy_phase >= 此值即失效
var _enemy_phase := 0               ## 已执行的敌方动作计数（每个敌方回合 +1）
var _defend_ready_phase := 0        ## 防御最早可用的敌方阶段
var _mark_ready_phase := 0          ## 标记最早可用的敌方阶段
var _taunt_ready_phase := 0         ## 嘲讽最早可用的敌方阶段
var _charge_bonus := 0              ## 蓄力累计伤害（下次 ATTACK 消耗）
var _taunt_swallow := false         ## 玩家下一序列首位 +2 被吞
var _last_turn_attacks := 0         ## 玩家上一回合攻击牌数
var _last_turn_grows := 0           ## 玩家上一回合发育牌数
var _grow_streak := 0               ## 玩家连续发育≥2 的回合数
var _recent_turns: Array = []       ## 最近 2 个玩家回合信号（attacks/grows/max_streak）
var _player_turn_recorded := false  ## 本玩家回合信号是否已入账
var _seq_max_streak := 0            ## 本序列达到过的最高连段阶


## setup(卡组, 敌人名, 敌人HP, 意图序列, 种子, 补牌数, 敌人等级)
## pattern 例：[{"kind":"attack","value":8}, {"kind":"defend","value":6}]，循环取用
func setup(deck: Array[StsCard], e_name: String, e_hp: int,
		pattern: Array, start_hp: int, seed_i: int, hand_refill: int = 4,
		level: int = 1) -> void:
	rng.seed = seed_i
	_refill_count = maxi(1, hand_refill)
	enemy_level = maxi(1, level)
	_chatppt_bonus_used = false
	rice_eaten = 0              ## 每局重置
	seq_streak = 0
	seq_kind = -1
	seq_open = false
	seq_attacks = 0
	seq_grows = 0
	pending_repeat = 0
	streak_lock = false
	last_observer_note = ""
	## AI 对手状态重置（新局默认旧规则：未调用 apply_ai_action 不产生任何行为差异）
	ai_action = ""
	ai_action_reason = ""
	mark_mode = ""
	mark_expire_phase = 0
	_enemy_phase = 0
	_defend_ready_phase = 0
	_mark_ready_phase = 0
	_taunt_ready_phase = 0
	_charge_bonus = 0
	_taunt_swallow = false
	_last_turn_attacks = 0
	_last_turn_grows = 0
	_grow_streak = 0
	_recent_turns.clear()
	_player_turn_recorded = false
	_seq_max_streak = 0
	hp = maxi(1, start_hp)
	max_hp = maxi(hp, 80)
	block = 0
	energy = ENERGY_PER_TURN
	ult_charge = 0
	p_status.clear()
	e_status.clear()
	next_mult = 1.0
	_firing_draw = false
	_draw_fx_count = 0
	_kill_fired = false
	_firing_damage = false
	_damage_fx_count = 0
	enemy_name = e_name
	enemy_hp = e_hp
	enemy_max_hp = e_hp
	enemy_block = 0
	_pattern = pattern.duplicate(true)
	_pattern_idx = 0
	## 敌人攻防取自意图序列（原实现读的是赋值前的旧 _pattern，新局永远拿默认 6/4）
	for it in _pattern:
		if String(it.get("kind", "")) == "attack":
			enemy_atk = int(it.get("value", 0))
		else:
			enemy_def = int(it.get("value", 0))
	draw_pile = deck.duplicate()
	discard_pile.clear()
	hand.clear()
	turn = 0
	over = Result.RUNNING
	damage_dealt = 0
	_shuffle(draw_pile)
	_draw(hand_size())        ## 初始手牌：从牌堆抽
	refresh_intent()
	start_turn()


func _shuffle(arr: Array[StsCard]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: StsCard = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 新回合：格挡清零、上手残余进弃牌堆、补牌改为**全牌堆采样**（T5 修循环锁定）
func start_turn() -> void:
	turn += 1
	block = 0
	energy = ENERGY_PER_TURN
	_chatppt_bonus_used = false
	## 新玩家回合：本轮信号尚未入账；本序列最高连段从 0 起
	_player_turn_recorded = false
	_seq_max_streak = 0
	for c in hand:
		discard_pile.append(c)
	hand.clear()
	_draw_fx_count = 0
	_damage_fx_count = 0
	refill_from_deck()
	if hand.is_empty():
		_draw(hand_size())    ## 整卡组都不在手（极端兜底）→ 直接抽
	## 效果层：回合开始（牌组光环，v1 语义）
	var start_ev: Array[Dictionary] = []
	_fire_deck_effects("on_turn_start", start_ev)


## 手牌上限（基础补牌数 + 上下文压缩加成）
func hand_size() -> int:
	return _refill_count + hand_bonus


func _draw(n: int) -> void:
	for i in n:
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				return
			draw_pile.append_array(discard_pile)
			discard_pile.clear()
			_shuffle(draw_pile)
		hand.append(draw_pile.pop_back())
		_fire_draw_effects(hand[-1])


## 效果层：抽到时触发（重入保护 + 每回合最多 6 次，防"抽牌→再抽"自激）
func _fire_draw_effects(card: StsCard) -> void:
	if card.effects.is_empty() or _firing_draw or _draw_fx_count >= 6:
		return
	_firing_draw = true
	_draw_fx_count += 1
	var ev := {}
	_apply_effects(EffectRuntime.eval(card.effects, "on_draw", _effect_ctx()), ev)
	_firing_draw = false


## 效果层：造成/受到伤害后触发（重入保护 + 每回合最多 6 次，防伤害→伤害自激）
func _fire_damage_event(trigger: String) -> void:
	if _firing_damage or _damage_fx_count >= 6:
		return
	_firing_damage = true
	_damage_fx_count += 1
	var ev: Array[Dictionary] = []
	_fire_deck_effects(trigger, ev)
	_firing_damage = false


## 按顺序出牌：只有手牌最左（最先）那张能打；cost ≥2 的卡还要付得起算力。
## （cost 1 = 基础指令，免费；这是 2026-10-30「无能量」手感的延续）
func can_play(card: StsCard) -> bool:
	if over != Result.RUNNING or hand.is_empty() or hand[0] != card:
		return false
	if card.cost <= 1:
		return true
	return energy >= card.cost


## 打一张牌（执行序列中的一行）。
## is_lead / is_finish：首尾槽位标记（arena 按队列位置传入）。
## 返回事件字典（UI 拿去播动画 / 打日志）。
## 打一张牌（执行序列中的一行）——成功即积累终结技充能
func play_card(card: StsCard, auto_refill: bool = true,
		is_lead: bool = false, is_finish: bool = false) -> Dictionary:
	var ev := _play_card_impl(card, auto_refill, is_lead, is_finish)
	if ev.get("ok", false):
		add_ult_charge(ULT_PER_CARD)
	return ev


func _play_card_impl(card: StsCard, auto_refill: bool = true,
		is_lead: bool = false, is_finish: bool = false) -> Dictionary:
	var ev := {"ok": false, "card": card, "kind": "", "value": 0, "to_enemy": false,
			"streak": 0, "lead": is_lead, "finish": is_finish, "repeat": false}
	if not can_play(card):
		ev["reason"] = "算力不足" if (hand.has(card) and hand[0] == card and card.cost > 1
				and energy < card.cost) else ("按顺序出牌：先打最左边那张" if hand.has(card) else "不在手牌")
		return ev
	if card.cost > 1:
		energy -= card.cost
	hand.erase(card)
	discard_pile.append(card)
	if not seq_open:
		seq_open = true
	## AI 对手 TAUNT：吞掉本序列首位 +2（只吞一次；米饭/指令行占首位也算消耗）
	var lead_swallowed := is_lead and _taunt_swallow
	if lead_swallowed:
		_taunt_swallow = false

	# 白米饭：程序里的「注释行」——不断连段，只推进成长
	if card.id == "rice":
		# 复读机对米饭生效（2026-11-01 主人钦定）：一次吃 2 碗
		var repeated := pending_repeat > 0
		var bowls := 1 + (1 if repeated else 0)
		pending_repeat = 0
		if repeated:
			ev["repeat"] = true
		## AI 标记 ECONOMY：发育牌效果 −50%（米饭最少保留 1 碗，防成长完全锁死）
		if _is_economy_mark():
			bowls = maxi(1, int(round(float(bowls) * 0.5)))
		rice_eaten += bowls
		seq_grows += 1
		## 翻身（2 碗）与觉醒（5 碗）的瞬间 → 事件标记（UI 飘字/赠卡）
		var was_stir := rice_eaten - bowls >= RICE_STIR
		var was_awake := rice_eaten - bowls >= RICE_AWAKE
		if not was_stir and is_stir():
			ev["stir_now"] = true
		if not was_awake and is_awake():
			_grant_awake_cards()
			ev["granted"] = 2
			ev["awake_now"] = true
		if auto_refill:
			_refill()
		ev.merge({"ok": true, "kind": "rice", "value": rice_eaten, "to_enemy": false}, true)
		return ev

	# D 指令行：复读机——不连段、不结算数值，给下一张非米饭卡挂「执行两次」
	# （缓冲保留到同序列里被消费；米饭不消费它，end_send 收尾时作废）
	if card.id == "loop":
		pending_repeat = 1
		if auto_refill:
			_refill()
		ev.merge({"ok": true, "kind": "loop", "value": 0, "to_enemy": false}, true)
		return ev

	# D 指令行：并行——本次运行内换类型不断连（阶数冻结，见上方连段推进）
	if card.id == "parallel":
		streak_lock = true
		if auto_refill:
			_refill()
		ev.merge({"ok": true, "kind": "parallel", "value": 0, "to_enemy": false}, true)
		return ev

	# 连段阶梯（A）：同类连击进阶；换类型断连重置。
	# D 并行卡可锁：锁 = 阶数冻结——换类型的行不清链也不进阶，
	# 下一张同类卡接着往上走（主人钦定数值 [parallel][fish][taunt][fish] → 6/5/8）。
	if seq_streak == 0:
		seq_streak = 1
	elif seq_kind == card.kind:
		## AI 标记 CHAIN：连段停成长，保当前阶位（换类型仍按原规则断连）
		if not _is_chain_mark():
			seq_streak += 1
	elif not streak_lock:
		seq_streak = 1
	seq_kind = card.kind
	_seq_max_streak = maxi(_seq_max_streak, seq_streak)

	# 复读机（D）：本卡效果执行两次，连段也算两阶——第二次从下一阶起步
	# 觉醒怒涛（觉醒赠卡）：自带执行两次
	var times := 1
	if pending_repeat > 0 and card.id != "rice":
		times = 2
		pending_repeat = 0
		ev["repeat"] = true
	elif card.id == "rage":
		times = 2

	# 数值 = 基础 + 连段阶梯 + 槽位，再乘成长倍率。
	# 复读的两次逐次推阶（如末位鱼 8 → 10）；槽位在两次执行里都生效（同占一个槽）。
	var slot := 0
	if is_lead:
		slot = 0 if lead_swallowed else LEAD_BONUS
	elif is_finish:
		slot = FINISH_BONUS
	var dealt := 0
	var blk_gain := 0
	## ChatPPT 被动：本回合第一张数值牌 +2（米饭/复读/并行不消耗）
	var first_bonus := 0
	if ai_id == "chatppt" and not _chatppt_bonus_used:
		first_bonus = CHATPPT_FIRST_BONUS
		_chatppt_bonus_used = true
	for i in times:
		var step := STREAK_STEP * (seq_streak - 1)
		var v: int = (card.damage if card.kind == StsCard.Kind.ATTACK else card.block) \
				+ step + slot
		if i == 0:
			v += first_bonus
		if card.kind == StsCard.Kind.ATTACK:
			v += atk_bonus
			v += _player_strength_bonus()
		if is_awake():
			v = int(round(float(v) * RICE_BUFF))
		## 效果层：上一张挂的「增幅」在这里消费（下一张牌 ×factor）
		if next_mult > 1.0:
			v = int(round(float(v) * next_mult))
		## AI 针对标记（本地表，最后结算）：
		##   AGGRO   攻击牌伤害 −50%
		##   ECONOMY 发育牌（防御格挡）效果 −50%
		if card.kind == StsCard.Kind.ATTACK:
			if _is_aggro_mark():
				v = int(round(float(v) * 0.5))
		elif _is_economy_mark():
			v = int(round(float(v) * 0.5))
		if card.kind == StsCard.Kind.ATTACK:
			dealt += _hit_enemy(v, card.id == "cannon")
			_apply_thorns()
		else:
			blk_gain += v
		if i < times - 1 and not _is_chain_mark():
			seq_streak += 1     ## 复读第二次：连段进阶（连段算两阶）
	_seq_max_streak = maxi(_seq_max_streak, seq_streak)

	# E 观察者统计
	if card.kind == StsCard.Kind.ATTACK:
		seq_attacks += times
	else:
		seq_grows += times

	if card.kind == StsCard.Kind.ATTACK:
		damage_dealt += dealt
		ev.merge({"ok": true, "kind": "attack", "value": dealt, "to_enemy": true}, true)
	else:
		block += blk_gain
		if card.draw > 0:          ## 许愿卡超限档：外观专属梗卡，补偿抽牌
			_draw(card.draw)
			ev["draw"] = card.draw
		ev.merge({"ok": true, "kind": "defend", "value": blk_gain, "to_enemy": false}, true)
	## 增幅只作用于紧跟的一张牌；本张已消费，先清掉（本张自己的效果稍后再设）
	next_mult = 1.0
	## 效果程序（AI 写的）：on_play。空 effects 直接跳过，零开销。
	if not card.effects.is_empty():
		_apply_effects(EffectRuntime.eval(card.effects, "on_play", _effect_ctx()), ev)
	## 效果层：击杀时触发（每次战斗只一次）
	if enemy_hp <= 0 and not _kill_fired:
		_kill_fired = true
		var kill_ev: Array[Dictionary] = []
		_fire_deck_effects("on_kill", kill_ev)
		if not kill_ev.is_empty():
			if not ev.has("fx"):
				ev["fx"] = []
			for row in kill_ev:
				(ev["fx"] as Array).append(row)
	ev["streak"] = seq_streak
	if auto_refill:
		_refill()               ## 单张出牌：打空立刻从弃牌堆随机补
	if enemy_hp <= 0:
		over = Result.WIN
	return ev


## 序列收尾：关闭本次运行。连段阶梯按「序列」计，收尾即清零——
## 这样下一回合的发送从连段 1 起步，且与 preview_sequence 每次从 0 推演一致。
## （观察者统计的清零在 end_turn 里做：观察者要看整序列。）
func end_send() -> void:
	seq_open = false
	seq_streak = 0
	seq_kind = -1
	## D 机制收尾（主人钦定「简单可预测」：缓冲不跨运行）：
	## - streak_lock：并行锁只保本序列，收尾即解
	## - pending_repeat：复读缓冲未消费就作废（「保留到下回合」方案更难预测，弃用）
	streak_lock = false
	pending_repeat = 0
	next_mult = 1.0           ## 增幅不跨序列（与「简单可预测」一致）
	## 效果层：序列结束触发（在连段清零之后、信号定格之前）
	var seq_ev: Array[Dictionary] = []
	_fire_deck_effects("on_seq_end", seq_ev)
	## 玩家回合的观察者信号在此定格（legal_actions / local_choose 下一敌方回合要用）
	_record_player_turn()


## 主动弃牌（每回合不限次）：弃掉这张，立刻从牌堆补 1 张。
## 牌堆空了会自动把弃牌堆洗回去（沿用 _draw 的回收逻辑）。
func discard_card(card: StsCard) -> bool:
	if over != Result.RUNNING or not hand.has(card):
		return false
	hand.erase(card)
	discard_pile.append(card)
	_draw(1)
	return true


## 手牌为空时才补：从弃牌堆**随机**抽 _refill_count 张（顺序也随机）
## （仅存于 play_card 的单张出牌路径；回合补牌已改走 refill_from_deck）
func _refill() -> void:
	if not hand.is_empty():
		return
	var n := mini(hand_size(), discard_pile.size())
	for i in n:
		var idx := rng.randi_range(0, discard_pile.size() - 1)
		hand.append(discard_pile[idx])
		discard_pile.remove_at(idx)


## 回合补牌 = **全牌堆采样**（T5 修「卡组循环锁定」，2026-10-31）：
## 旧 _refill 只从弃牌堆抽回刚打的几张 → 每回合同几张无限循环，
## 抽牌堆其余卡永不进循环，顺序杠杆被开局组合锁死。
## 现在：弃牌堆全部并回抽牌堆 → 洗混 → 抽 _refill_count 张，
## 每回合手牌是全卡组的随机样本，跨回合组合真正变化。
func refill_from_deck() -> void:
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	_shuffle(draw_pile)
	_draw(hand_size())


## 是否已成长到「有点睡醒」（吃满 2 碗白米饭）
func is_awake() -> bool:
	return rice_eaten >= RICE_AWAKE


## 翻身阶段（2..4 碗）：还睡着，但视觉上坐起来了
func is_stir() -> bool:
	return rice_eaten >= RICE_STIR and not is_awake()


## 觉醒瞬间赠卡（进弃牌堆，随循环进入手牌）
const AWAKE_GRANT_IDS := ["cannon", "rage"]

func _grant_awake_cards() -> void:
	for card_id in AWAKE_GRANT_IDS:
		var c := StsCardPool.card(card_id)
		if c != null:
			discard_pile.append(c)


## 整手打出后由 UI 调一次补牌（T5 起与回合补牌同语义：全牌堆采样）
func refill_hand() -> void:
	refill_from_deck()


## 该角色每轮回补几张（因角色而异，主人钦定 DeepSeek 4 张）
static func refill_for(ai_id: String) -> int:
	return int(REFILL_BY_AI.get(ai_id, 4))


## 设定核心 AI 娘（影响被动：ChatPPT 首牌加成）
func set_ai_id(id: String) -> void:
	ai_id = id


func set_refill(n: int) -> void:
	_refill_count = maxi(1, n)


## 对敌人结算伤害（先扣敌人格挡）。返回实际造成的伤害。
func _hit_enemy(dmg: int, ignore_block: bool = false) -> int:
	var d := dmg
	## 效果层：易伤（受到伤害 +25%），无状态时恒等
	if e_status.has("vulnerable"):
		d = int(round(float(d) * float(EffectSpec.STATUSES["vulnerable"]["dmg_in_mult"])))
	if enemy_block > 0 and not ignore_block:
		var absorbed: int = mini(enemy_block, d)
		enemy_block -= absorbed
		d -= absorbed
	enemy_hp = maxi(0, enemy_hp - d)
	if d > 0:
		_fire_damage_event("on_damage_dealt")
	return d


## 结束回合：敌人按当前意图行动 → 换下个意图 → 新回合。
## 返回本步事件列表（先敌人行动、再回合交接）。
func end_turn() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if over != Result.RUNNING:
		return events
	_record_player_turn()
	_taunt_swallow = false      ## 本回合没被消耗的 TAUNT 吞噬过期
	var it := intent
	if String(it.get("kind", "")) == "attack":
		var atk_val := int(it.get("value", 0))
		## 效果层：敌人「降智」→ 造成伤害 −25%（无状态时恒等）
		if e_status.has("weak"):
			atk_val = maxi(0, int(round(float(atk_val) * float(EffectSpec.STATUSES["weak"]["dmg_out_mult"]))))
		var dealt := _hit_player(atk_val)
		events.append({"kind": "enemy_attack", "value": atk_val,
				"dealt": dealt, "blocked": atk_val - dealt})
	else:
		enemy_block += int(it.get("value", 0))
		events.append({"kind": "enemy_defend", "value": int(it.get("value", 0))})
	if hp <= 0:
		over = Result.LOSE
		return events
	## 效果层：回合结束结算（中毒掉血 + 状态回合数递减）；空状态时整段为空
	events.append_array(_tick_statuses())
	if hp <= 0:
		over = Result.LOSE
		return events
	if enemy_hp <= 0:
		over = Result.WIN
		return events
	## 效果层：牌组内 on_turn_end 程序（光环型，v1 语义）
	_fire_deck_effects("on_turn_end", events)
	if enemy_hp <= 0:
		over = Result.WIN
		return events
	refresh_intent()
	# E 观察者：敌人看完你这段程序，调整下回合意图（循环 pattern 被覆写一次）
	if seq_attacks >= 2:
		intent = {"kind": "defend", "value": enemy_def + OBS_BRACE}
		last_observer_note = "它看穿了你的连攻，架起了盾"
	elif seq_grows >= 2:
		intent = {"kind": "attack", "value": enemy_atk + OBS_CHARGE}
		last_observer_note = "它趁你发育，蓄起了大力"
	_enemy_phase += 1           ## AI 冷却/标记按敌方阶段推进（旧规则无副作用）
	seq_attacks = 0
	seq_grows = 0
	start_turn()
	events.append({"kind": "new_turn", "turn": turn})
	if last_observer_note != "":
		events.append({"kind": "observer", "note": last_observer_note})
		last_observer_note = ""
	return events


# ── AI 对手规则层（五动作白名单 · 圆桌终案 v1.1）──────────────────

## 设定敌人等级（ATTACK = OBS_ATK + 0.6×(级-1)，总攻帽 13）。
func set_opponent_level(lv: int) -> void:
	enemy_level = maxi(1, lv)


## 当前局势下合法的 AI 动作（白名单顺序：ATTACK/DEFEND/CHARGE/MARK/TAUNT）。
## state 参数保留给模拟器/外部快照覆盖；实例自身状态是唯一真值。
func legal_actions(_state: Dictionary = {}) -> Array[String]:
	var out: Array[String] = [AI_ATTACK]
	if _defend_available():
		out.append(AI_DEFEND)
	if _charge_available():
		out.append(AI_CHARGE)
	if _mark_available():
		out.append(AI_MARK)
	if _taunt_available():
		out.append(AI_TAUNT)
	return out


## 本地兜底（LLM 未接入/超时/非法时用）：
## 保留旧观察者行为——玩家上回合 ≥2 攻 → 防御；连续 2 回合 ≥2 发育 → 蓄力。
func local_choose(_state: Dictionary = {}) -> String:
	if _last_turn_attacks >= 2 and _defend_available():
		return AI_DEFEND
	if _grow_streak >= 2 and _charge_available():
		return AI_CHARGE
	return AI_ATTACK


## 执行一次 AI 敌方回合（LLM 回调与本地兜底共用入口）。
## action：五动作枚举；也接受 "MARK:AGGRO" / "MARK:ECONOMY" / "MARK:CHAIN"。
## 非法/空动作 → local_choose() 静默兜底（不抛错、不中断演出）。
## 返回事件形状与 end_turn() 一致：敌方动作 → new_turn → observer。
func apply_ai_action(action: String, reason: String = "") -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if over != Result.RUNNING:
		return events
	## 若调用方漏了 end_send，这里补齐：连段/缓冲/玩家信号统一收尾（重复调用幂等）
	end_send()
	_taunt_swallow = false      ## 上一回合没被消耗的吞噬过期

	var act := _normalize_ai_action(action)
	var mode := ""
	if act.begins_with("MARK:"):
		mode = act.substr(5)
		act = AI_MARK
	if not legal_actions().has(act):
		act = local_choose()
		mode = ""
	if act == AI_MARK and not AI_MARK_MODES.has(mode):
		mode = pick_mark_mode()

	ai_action = act
	ai_action_reason = reason
	var ev := {"ai_action": act, "reason": reason}

	match act:
		AI_DEFEND:
			enemy_block += OBS_DEF
			_defend_ready_phase = _enemy_phase + 1 + DEFEND_CD
			ev.merge({"kind": "enemy_defend", "value": OBS_DEF}, true)
		AI_CHARGE:
			_charge_bonus = mini(OBS_ATK_CAP, _charge_bonus + OBS_CHARGE_STEP)
			ev.merge({"kind": "enemy_charge", "value": OBS_CHARGE_STEP,
					"charge": _charge_bonus}, true)
		AI_MARK:
			mark_mode = mode
			mark_expire_phase = _enemy_phase + 1 + MARK_DURATION
			_mark_ready_phase = _enemy_phase + 1 + MARK_CD
			ev.merge({"kind": "enemy_mark", "mark_mode": mode, "value": 0}, true)
		AI_TAUNT:
			_taunt_swallow = true
			_taunt_ready_phase = _enemy_phase + 1 + TAUNT_CD
			ev.merge({"kind": "enemy_taunt", "value": LEAD_BONUS}, true)
		_:
			act = AI_ATTACK
			ai_action = act
			ev["ai_action"] = act
			var atk := ai_attack_value()
			_charge_bonus = 0
			var dealt := _hit_player(atk)
			ev.merge({"kind": "enemy_attack", "value": atk, "dealt": dealt,
					"blocked": atk - dealt}, true)
	events.append(ev)
	_enemy_phase += 1

	if hp <= 0:
		over = Result.LOSE
		return events

	seq_attacks = 0
	seq_grows = 0
	refresh_intent()
	start_turn()
	events.append({"kind": "new_turn", "turn": turn})

	var note := _ai_note(act, mode, reason)
	last_observer_note = note
	events.append({"kind": "observer", "note": note})
	last_observer_note = ""
	return events


## 下一次 ATTACK 的伤害（含蓄力，硬帽 13）。
func ai_attack_value() -> int:
	var base := OBS_ATK + OBS_ATK_PER_LEVEL * float(maxi(0, enemy_level - 1))
	return mini(OBS_ATK_CAP, int(round(base)) + _charge_bonus)


func is_mark_active() -> bool:
	return mark_mode != "" and _enemy_phase < mark_expire_phase


## 标记还剩几个玩家回合（含当前回合；0 = 未标记）。
func mark_turns_left() -> int:
	if mark_mode == "":
		return 0
	return maxi(0, mark_expire_phase - _enemy_phase)


## 本地模式兜底：按最近 2 回合计数最高者选
## （连段阶高 → CHAIN；攻击多 → AGGRO；发育多 → ECONOMY；无信号 → AGGRO）。
func pick_mark_mode() -> String:
	var atk := 0
	var grw := 0
	var st := 0
	for r in _recent_turns:
		atk += int(r.get("attacks", 0))
		grw += int(r.get("grows", 0))
		st = maxi(st, int(r.get("max_streak", 0)))
	if st >= 3 and st >= atk and st >= grw:
		return MARK_CHAIN
	if atk >= 2 and atk >= grw:
		return MARK_AGGRO
	if grw >= 2:
		return MARK_ECONOMY
	if st >= 2:
		return MARK_CHAIN
	return MARK_AGGRO


## 局面快照：给 LLMOpponentPool / prompt 用的只读字典（不含牌的细节）。
func ai_state_snapshot() -> Dictionary:
	var last_max := 0
	if not _recent_turns.is_empty():
		last_max = int(_recent_turns[-1].get("max_streak", 0))
	return {
		"turn": turn,
		"player_hp": hp, "player_max_hp": max_hp, "player_block": block,
		"enemy_hp": enemy_hp, "enemy_max_hp": enemy_max_hp,
		"enemy_block": enemy_block, "enemy_level": enemy_level,
		"attacks_last_turn": _last_turn_attacks,
		"grows_last_turn": _last_turn_grows,
		"grow_streak": _grow_streak,
		"max_streak_last_turn": last_max,
		"mark_active": is_mark_active(),
		"mark_mode": mark_mode if is_mark_active() else "",
		"mark_turns_left": mark_turns_left(),
		"defend_ready": _defend_available(),
		"charge_ready": _charge_available(),
		"mark_ready": _mark_available(),
		"taunt_ready": _taunt_available(),
		"taunt_unlocked": _taunt_unlocked(),
		"enemy_phase": _enemy_phase,
		"ai_action": ai_action,
		"ai_action_reason": ai_action_reason,
	}


## 动作枚举 → UI 名（MARK 可带模式，如 "MARK:AGGRO"）。
static func ai_action_ui_name(action: String) -> String:
	var s := String(action).strip_edges().to_upper()
	if s.begins_with("MARK:"):
		var m := s.substr(5)
		var mn := String(AI_MARK_MODE_NAMES.get(m, m))
		return "%s·%s" % [String(AI_ACTION_NAMES.get("MARK", "MARK")), mn]
	return String(AI_ACTION_NAMES.get(s, action))


## 容错归一：大小写/空白/中文别名/MARK:模式。
static func _normalize_ai_action(raw: String) -> String:
	var s := String(raw).strip_edges().to_upper()
	if AI_ACTION_ALIASES.has(s):
		return String(AI_ACTION_ALIASES[s])
	if s.begins_with("MARK:"):
		var m := s.substr(5).strip_edges()
		var mode_alias := {"连攻": "AGGRO", "攻击": "AGGRO", "发育": "ECONOMY",
				"经济": "ECONOMY", "连段": "CHAIN"}
		if mode_alias.has(m):
			m = String(mode_alias[m])
		return "MARK:" + m
	return s


func _is_aggro_mark() -> bool:
	return is_mark_active() and mark_mode == MARK_AGGRO


func _is_economy_mark() -> bool:
	return is_mark_active() and mark_mode == MARK_ECONOMY


func _is_chain_mark() -> bool:
	return is_mark_active() and mark_mode == MARK_CHAIN


func _defend_available() -> bool:
	if _enemy_phase < _defend_ready_phase:
		return false
	if _last_turn_attacks < 2:
		return false
	## AGGRO 标记期禁 DEFEND（防 −50% × 6 格挡的零破防死锁）
	if _is_aggro_mark():
		return false
	return true


func _charge_available() -> bool:
	return _grow_streak >= 2


func _mark_available() -> bool:
	return _enemy_phase >= _mark_ready_phase


func _taunt_unlocked() -> bool:
	return float(enemy_hp) / float(maxi(1, enemy_max_hp)) < TAUNT_HP_RATIO


func _taunt_available() -> bool:
	return _enemy_phase >= _taunt_ready_phase and _taunt_unlocked()


## 玩家回合信号入账（end_send / end_turn / apply_ai_action 三处共用，幂等）。
func _record_player_turn() -> void:
	if _player_turn_recorded:
		return
	_player_turn_recorded = true
	_last_turn_attacks = seq_attacks
	_last_turn_grows = seq_grows
	if seq_grows >= 2:
		_grow_streak += 1
	else:
		_grow_streak = 0
	_recent_turns.append({
		"attacks": seq_attacks, "grows": seq_grows, "max_streak": _seq_max_streak,
	})
	while _recent_turns.size() > 2:
		_recent_turns.pop_front()


func _ai_note(act: String, mode: String, reason: String) -> String:
	var label := ai_action_ui_name(act)
	if act == AI_MARK and mode != "":
		label = ai_action_ui_name("MARK:" + mode)
	var why := reason.strip_edges()
	if why != "":
		return "%s：%s" % [label, why]
	return label


## 对玩家结算伤害（先扣格挡）。返回实际掉的血。
func _hit_player(dmg: int) -> int:
	var d := dmg
	if block > 0:
		var absorbed: int = mini(block, d)
		block -= absorbed
		d -= absorbed
	hp = maxi(0, hp - d)
	if d > 0:
		add_ult_charge(ULT_PER_HIT)   ## 受创蓄思：掉血加速深度思考
		_fire_damage_event("on_damage_taken")
	return d


## 敌人下个意图（循环取用 pattern）
func refresh_intent() -> void:
	if _pattern.is_empty():
		_pattern = [{"kind": "attack", "value": 6}]
	intent = _pattern[_pattern_idx % _pattern.size()].duplicate()
	_pattern_idx += 1


## 序列预览：按当前队列顺序逐卡推演「将打出的数值」。
## 返回数组与 hand 等长，条目字段：
##   growth        是否白米饭（成长行，无数值）
##   lead/finish   首位/末位槽位标记（B）
##   streak        该位置的连段阶数（A）
##   value         阶梯+槽位+标记后的数值（**未乘**睡醒加成；AGGRO/ECONOMY/吞首位已计入）
##   buffed        is_awake() 时是否乘 RICE_BUFF（C）
##   buffed_value  int(round(value * RICE_BUFF))（buffed 时才是最终结算值）
##   kind          卡类型（米饭条目无此字段）
## 跑一遍"影子执行"：不改任何真实状态（TAUNT 吞噬只在本函数内影子消耗）。
func preview_sequence() -> Array:
	var out: Array = []
	var streak := 0
	var kind := -1
	var first_bonus_used := false
	var swallow := _taunt_swallow
	var n := hand.size()
	for i in n:
		var c := hand[i]
		var lead := i == 0
		var finish := i == n - 1
		var lead_swallowed := lead and swallow
		if lead_swallowed:
			swallow = false
		## 指令行（米饭/复读机/并行）：无数值行——growth 标记让 UI 显示卡面描述
		if c.id == "rice" or c.id == "loop" or c.id == "parallel":
			out.append({"growth": true, "lead": lead, "finish": finish, "streak": streak,
					"value": 0, "buffed": false})
			continue
		## 连段推进与 play_card 同构（含并行「冻结」/CHAIN 停成长语义），预览不撒谎
		if streak == 0:
			streak = 1
		elif kind == c.kind:
			if not _is_chain_mark():
				streak += 1
		elif not streak_lock:
			streak = 1
		kind = c.kind
		var step := STREAK_STEP * (streak - 1)
		var slot := 0
		if lead:
			slot = 0 if lead_swallowed else LEAD_BONUS
		elif finish:
			slot = FINISH_BONUS
		var v: int = (c.damage if c.kind == StsCard.Kind.ATTACK else c.block) + step + slot
		if ai_id == "chatppt" and not first_bonus_used:
			v += CHATPPT_FIRST_BONUS
			first_bonus_used = true
		if c.kind == StsCard.Kind.ATTACK:
			if _is_aggro_mark():
				v = int(round(float(v) * 0.5))
		elif _is_economy_mark():
			v = int(round(float(v) * 0.5))
		out.append({"growth": false, "lead": lead, "finish": finish, "streak": streak,
				"value": v, "kind": c.kind,
				"buffed": is_awake(), "buffed_value": int(round(float(v) * RICE_BUFF))})
	return out


## 当前手牌里能量够的牌数（UI 提示用）
func playable_count() -> int:
	var n := 0
	for c in hand:
		if c == hand[0]:
			n += 1
	return n


# ── 终结技「深度思考」──────────────────────────────────

func add_ult_charge(n: int) -> void:
	if over != Result.RUNNING:
		return
	var was := can_cast_ult()
	ult_charge = mini(ULT_MAX, ult_charge + n)
	if not was and can_cast_ult():
		ult_ready_changed.emit(true)


func can_cast_ult() -> bool:
	return over == Result.RUNNING and ult_charge >= ULT_MAX


## 释放：无视格挡的固定伤害，清空充能；返回实际伤害
func cast_ult() -> int:
	if not can_cast_ult():
		return 0
	ult_charge = 0
	var dealt := _hit_enemy(ULT_DAMAGE, true)
	damage_dealt += dealt
	if enemy_hp <= 0:
		over = Result.WIN
	return dealt


# ── 效果层（AI 自拟卡牌效果 · 圆桌 v1）────────────────────────
## 设计约束（见 scripts/core/effect_spec.gd）：
##   静态 ≤4 clause / ≤6 op；运行期 op 预算 64；触发深度 1（效果不再触发效果）
## 所有函数在 p_status/e_status 为空、card.effects 为空时是恒等操作。

## 求值上下文：给 EffectRuntime 的只读计数器
func _effect_ctx() -> Dictionary:
	return {
		"hand_size": hand.size(),
		"same_kind_streak": seq_streak,
		"cards_played_this_turn": seq_attacks + seq_grows,
		"enemy_status_count": e_status.size(),
		"turn": turn,
		"turn_number": turn,
		"hp_missing_pct": int(round(float(max_hp - hp) / float(maxi(1, max_hp)) * 100.0)),
		"block": block,
	}


## 玩家「算力注入」加成（无状态返回 0）
func _player_strength_bonus() -> int:
	if not p_status.has("strength"):
		return 0
	var tier := int((p_status["strength"] as Dictionary).get("tier", 1))
	return EffectSpec.status_value("strength", tier, "atk_bonus")


## 敌人「防火墙」反伤（被攻击后结算，无状态为空操作）
func _apply_thorns() -> void:
	if not e_status.has("thorns"):
		return
	var tier := int((e_status["thorns"] as Dictionary).get("tier", 1))
	var refl := EffectSpec.status_value("thorns", tier, "reflect")
	if refl > 0:
		_hit_player(refl)


## 施加状态：同 id 刷新为「更高档 + 更长回合」，不叠加层数（v1 规则）
func _add_status(status: String, tier: int, target: String) -> void:
	if not EffectSpec.STATUSES.has(status):
		return
	var box: Dictionary = e_status if target == "enemy" else p_status
	var turns := EffectSpec.status_turns(status, tier)
	if box.has(status):
		var old: Dictionary = box[status]
		box[status] = {
			"tier": maxi(int(old.get("tier", 1)), tier),
			"turns": maxi(int(old.get("turns", 0)), turns),
		}
	else:
		box[status] = {"tier": tier, "turns": turns}


## 回合结束结算：中毒掉血（无视护盾）+ 回合数递减。空状态返回空数组。
func _tick_statuses() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not e_status.is_empty():
		var es := e_status.keys()
		for id in es:
			var st: Dictionary = e_status[id]
			if String(id) == "poison":
				var dot := EffectSpec.status_value("poison", int(st.get("tier", 1)), "dot")
				if dot > 0:
					enemy_hp = maxi(0, enemy_hp - dot)
					events.append({"kind": "status_tick", "target": "enemy",
							"status": "poison", "value": dot})
			st["turns"] = int(st.get("turns", 0)) - 1
			if int(st["turns"]) <= 0:
				e_status.erase(id)
	if not p_status.is_empty():
		var ps := p_status.keys()
		for id in ps:
			var st2: Dictionary = p_status[id]
			if String(id) == "poison":
				var dot2 := EffectSpec.status_value("poison", int(st2.get("tier", 1)), "dot")
				if dot2 > 0:
					hp = maxi(0, hp - dot2)
					events.append({"kind": "status_tick", "target": "self",
							"status": "poison", "value": dot2})
			st2["turns"] = int(st2.get("turns", 0)) - 1
			if int(st2["turns"]) <= 0:
				p_status.erase(id)
	return events


## 把求值结果落到战斗状态上（只经由既有结算函数，不绕过护盾规则）
func _apply_effects(list: Array, ev: Dictionary) -> void:
	for e in list:
		match String(e.get("op", "")):
			"damage":
				var d := _hit_enemy(int(e.get("amount", 0)))
				damage_dealt += d
				if not ev.has("fx"):
					ev["fx"] = []
				(ev["fx"] as Array).append({"kind": "effect_damage", "value": d})
			"apply_status":
				var st := String(e.get("status", ""))
				var tier := int(e.get("tier", 1))
				_add_status(st, tier, String(e.get("target", "enemy")))
				if not ev.has("fx"):
					ev["fx"] = []
				(ev["fx"] as Array).append({"kind": "effect_status", "status": st, "tier": tier})
			"heal":
				var heal := int(e.get("amount", 0))
				var before := hp
				hp = mini(max_hp, hp + heal)
				if not ev.has("fx"):
					ev["fx"] = []
				(ev["fx"] as Array).append({"kind": "effect_heal", "value": hp - before})
			"draw":
				var dn := int(e.get("amount", 1))
				_draw(dn)
				if not ev.has("fx"):
					ev["fx"] = []
				(ev["fx"] as Array).append({"kind": "effect_draw", "value": dn})
			"discard_random":
				var dis := _discard_random(int(e.get("amount", 1)))
				if not ev.has("fx"):
					ev["fx"] = []
				(ev["fx"] as Array).append({"kind": "effect_discard", "value": dis})
			"multiply_next":
				var f := maxf(2.0, float(e.get("factor", 2)))
				next_mult = maxf(next_mult, f)
				if not ev.has("fx"):
					ev["fx"] = []
				(ev["fx"] as Array).append({"kind": "effect_mult", "value": int(f)})
			"block":
				var blk := int(e.get("amount", 0))
				block += blk
				if not ev.has("fx"):
					ev["fx"] = []
				(ev["fx"] as Array).append({"kind": "effect_block", "value": blk})
			"duplicate_next":
				pending_repeat = 1
				if not ev.has("fx"):
					ev["fx"] = []
				(ev["fx"] as Array).append({"kind": "effect_duplicate"})
			"modify_intent":
				var delta := int(e.get("delta", 0))
				var cur := int(intent.get("value", 0))
				intent["value"] = maxi(0, cur + delta)
				if not ev.has("fx"):
					ev["fx"] = []
				(ev["fx"] as Array).append({"kind": "effect_intent", "value": delta})


## 随机弃 N 张并补抽 N 张；返回实际弃掉的数量
func _discard_random(n: int) -> int:
	var done := 0
	for i in n:
		if hand.is_empty():
			break
		var idx := rng.randi_range(0, hand.size() - 1)
		var c: StsCard = hand[idx]
		hand.remove_at(idx)
		discard_pile.append(c)
		done += 1
	if done > 0:
		_draw(done)
	return done


## 牌组内程序（光环型；v1 遍历三个牌堆，不重复计同一张卡）
func _fire_deck_effects(trigger: String, events: Array[Dictionary]) -> void:
	var seen := {}
	for pile in [hand, draw_pile, discard_pile]:
		for card in pile:
			if card.effects.is_empty() or seen.has(card):
				continue
			seen[card] = true
			var ctx := _effect_ctx()
			var outs := EffectRuntime.eval(card.effects, trigger, ctx)
			if outs.is_empty():
				continue
			var ev := {}
			_apply_effects(outs, ev)
			if ev.has("fx"):
				for fx in ev["fx"]:
					var row: Dictionary = (fx as Dictionary).duplicate()
					row["kind"] = "card_effect"
					events.append(row)
