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

const HEAL_ON_WIN := 6


var rng := RandomNumberGenerator.new()

# 玩家
var hp := 80
var max_hp := 80
var block := 0
## 手牌打空后从弃牌堆随机补几张：因角色而异（主人 2026-10-30，DeepSeek 默认 3）
const REFILL_BY_AI := {"deepdeek": 4}

## 白米饭成长（2026-10-31 主人钦定三段）：
##   0..1 碗 = 睡眠（躺）｜2..4 碗 = 翻身（坐起，仍睡眠）｜5 碗 = 完全觉醒（站立）
## 觉醒瞬间：赠 2 张特殊攻击牌进弃牌堆（鲸鱼铁头炮/觉醒怒涛），每局重置
const RICE_STIR := 2
const RICE_AWAKE := 5
const RICE_BUFF := 1.2
var rice_eaten := 0
var _refill_count := 4

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


## setup(卡组, 敌人名, 敌人HP, 意图序列, 种子)
## pattern 例：[{"kind":"attack","value":8}, {"kind":"defend","value":6}]，循环取用
func setup(deck: Array[StsCard], e_name: String, e_hp: int,
		pattern: Array, start_hp: int, seed_i: int, hand_refill: int = 4) -> void:
	rng.seed = seed_i
	_refill_count = maxi(1, hand_refill)
	rice_eaten = 0              ## 每局重置
	seq_streak = 0
	seq_kind = -1
	seq_open = false
	seq_attacks = 0
	seq_grows = 0
	pending_repeat = 0
	streak_lock = false
	last_observer_note = ""
	hp = maxi(1, start_hp)
	max_hp = maxi(hp, 80)
	block = 0
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
	_draw(_refill_count)        ## 初始手牌：从牌堆抽
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
	for c in hand:
		discard_pile.append(c)
	hand.clear()
	refill_from_deck()
	if hand.is_empty():
		_draw(_refill_count)    ## 整卡组都不在手（极端兜底）→ 直接抽


func _draw(n: int) -> void:
	for i in n:
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				return
			draw_pile.append_array(discard_pile)
			discard_pile.clear()
			_shuffle(draw_pile)
		hand.append(draw_pile.pop_back())


## 按顺序出牌：只有手牌最左（最先）那张能打（主人 2026-10-30，取消能量）
func can_play(card: StsCard) -> bool:
	return over == Result.RUNNING and not hand.is_empty() and hand[0] == card


## 打一张牌（执行序列中的一行）。
## is_lead / is_finish：首尾槽位标记（arena 按队列位置传入）。
## 返回事件字典（UI 拿去播动画 / 打日志）。
func play_card(card: StsCard, auto_refill: bool = true,
		is_lead: bool = false, is_finish: bool = false) -> Dictionary:
	var ev := {"ok": false, "card": card, "kind": "", "value": 0, "to_enemy": false,
			"streak": 0, "lead": is_lead, "finish": is_finish, "repeat": false}
	if not can_play(card):
		ev["reason"] = "按顺序出牌：先打最左边那张" if hand.has(card) else "不在手牌"
		return ev
	hand.erase(card)
	discard_pile.append(card)
	if not seq_open:
		seq_open = true

	# 白米饭：程序里的「注释行」——不断连段，只推进成长
	if card.id == "rice":
		# 复读机对米饭生效（2026-11-01 主人钦定）：一次吃 2 碗
		var bowls := 1 + (1 if pending_repeat > 0 else 0)
		pending_repeat = 0
		if bowls == 2:
			ev["repeat"] = true
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
		seq_streak += 1
	elif not streak_lock:
		seq_streak = 1
	seq_kind = card.kind

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
	var slot := LEAD_BONUS if is_lead else (FINISH_BONUS if is_finish else 0)
	var dealt := 0
	var blk_gain := 0
	for i in times:
		var step := STREAK_STEP * (seq_streak - 1)
		var v: int = (card.damage if card.kind == StsCard.Kind.ATTACK else card.block) \
				+ step + slot
		if is_awake():
			v = int(round(float(v) * RICE_BUFF))
		if card.kind == StsCard.Kind.ATTACK:
			dealt += _hit_enemy(v, card.id == "cannon")
		else:
			blk_gain += v
		if i < times - 1:
			seq_streak += 1     ## 复读第二次：连段进阶（连段算两阶）

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
		ev.merge({"ok": true, "kind": "defend", "value": blk_gain, "to_enemy": false}, true)
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
	var n := mini(_refill_count, discard_pile.size())
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
	_draw(_refill_count)


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


func set_refill(n: int) -> void:
	_refill_count = maxi(1, n)


## 对敌人结算伤害（先扣敌人格挡）。返回实际造成的伤害。
func _hit_enemy(dmg: int, ignore_block: bool = false) -> int:
	var d := dmg
	if enemy_block > 0 and not ignore_block:
		var absorbed: int = mini(enemy_block, d)
		enemy_block -= absorbed
		d -= absorbed
	enemy_hp = maxi(0, enemy_hp - d)
	return d


## 结束回合：敌人按当前意图行动 → 换下个意图 → 新回合。
## 返回本步事件列表（先敌人行动、再回合交接）。
func end_turn() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if over != Result.RUNNING:
		return events
	var it := intent
	if String(it.get("kind", "")) == "attack":
		var dealt := _hit_player(int(it.get("value", 0)))
		events.append({"kind": "enemy_attack", "value": int(it.get("value", 0)),
				"dealt": dealt, "blocked": int(it.get("value", 0)) - dealt})
	else:
		enemy_block += int(it.get("value", 0))
		events.append({"kind": "enemy_defend", "value": int(it.get("value", 0))})
	if hp <= 0:
		over = Result.LOSE
		return events
	refresh_intent()
	# E 观察者：敌人看完你这段程序，调整下回合意图（循环 pattern 被覆写一次）
	if seq_attacks >= 2:
		intent = {"kind": "defend", "value": enemy_def + OBS_BRACE}
		last_observer_note = "它看穿了你的连攻，架起了盾"
	elif seq_grows >= 2:
		intent = {"kind": "attack", "value": enemy_atk + OBS_CHARGE}
		last_observer_note = "它趁你发育，蓄起了大力"
	seq_attacks = 0
	seq_grows = 0
	start_turn()
	events.append({"kind": "new_turn", "turn": turn})
	if last_observer_note != "":
		events.append({"kind": "observer", "note": last_observer_note})
		last_observer_note = ""
	return events


## 对玩家结算伤害（先扣格挡）。返回实际掉的血。
func _hit_player(dmg: int) -> int:
	var d := dmg
	if block > 0:
		var absorbed: int = mini(block, d)
		block -= absorbed
		d -= absorbed
	hp = maxi(0, hp - d)
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
##   value         阶梯+槽位后的数值（**未乘**睡醒加成）
##   buffed        is_awake() 时是否乘 RICE_BUFF（C）
##   buffed_value  int(round(value * RICE_BUFF))（buffed 时才是最终结算值）
##   kind          卡类型（米饭条目无此字段）
## 跑一遍"影子执行"：不改任何真实状态。
func preview_sequence() -> Array:
	var out: Array = []
	var streak := 0
	var kind := -1
	var n := hand.size()
	for i in n:
		var c := hand[i]
		var lead := i == 0
		var finish := i == n - 1
		## 指令行（米饭/复读机/并行）：无数值行——growth 标记让 UI 显示卡面描述
		if c.id == "rice" or c.id == "loop" or c.id == "parallel":
			out.append({"growth": true, "lead": lead, "finish": finish, "streak": streak,
					"value": 0, "buffed": false})
			continue
		## 连段推进与 play_card 同构（含并行「冻结」语义），预览不撒谎
		if streak == 0:
			streak = 1
		elif kind == c.kind:
			streak += 1
		elif not streak_lock:
			streak = 1
		kind = c.kind
		var step := STREAK_STEP * (streak - 1)
		var slot := LEAD_BONUS if lead else (FINISH_BONUS if finish else 0)
		var v: int = (c.damage if c.kind == StsCard.Kind.ATTACK else c.block) + step + slot
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
