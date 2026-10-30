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
const REFILL_BY_AI := {"deepdeek": 3}
var _refill_count := 3
# 敌人
var enemy_name := ""
var enemy_hp := 1
var enemy_max_hp := 1
var enemy_block := 0
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
		pattern: Array, start_hp: int, seed_i: int, hand_refill: int = 3) -> void:
	rng.seed = seed_i
	_refill_count = maxi(1, hand_refill)
	hp = maxi(1, start_hp)
	max_hp = maxi(hp, 80)
	block = 0
	enemy_name = e_name
	enemy_hp = e_hp
	enemy_max_hp = e_hp
	enemy_block = 0
	_pattern = pattern.duplicate(true)
	_pattern_idx = 0
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


## 新回合：格挡清零、上手残余进弃牌堆、手牌空了从弃牌堆随机补
func start_turn() -> void:
	turn += 1
	block = 0
	for c in hand:
		discard_pile.append(c)
	hand.clear()
	_refill()
	if hand.is_empty():
		_draw(_refill_count)    ## 弃牌堆也没牌（开局/打光）→ 从牌堆抽


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


## 打一张牌。返回事件字典（UI 拿去播动画 / 打日志）。
func play_card(card: StsCard) -> Dictionary:
	var ev := {"ok": false, "card": card, "kind": "", "value": 0, "to_enemy": false}
	if not can_play(card):
		ev["reason"] = "按顺序出牌：先打最左边那张" if hand.has(card) else "不在手牌"
		return ev
	hand.erase(card)
	discard_pile.append(card)
	if card.kind == StsCard.Kind.ATTACK:
		var dealt := _hit_enemy(card.damage)
		damage_dealt += dealt
		ev.merge({"ok": true, "kind": "attack", "value": dealt, "to_enemy": true}, true)
	else:
		block += card.block
		ev.merge({"ok": true, "kind": "defend", "value": card.block, "to_enemy": false}, true)
	_refill()                   ## 手牌打空 → 立刻从弃牌堆随机补
	if enemy_hp <= 0:
		over = Result.WIN
	return ev


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
func _refill() -> void:
	if not hand.is_empty():
		return
	var n := mini(_refill_count, discard_pile.size())
	for i in n:
		var idx := rng.randi_range(0, discard_pile.size() - 1)
		hand.append(discard_pile[idx])
		discard_pile.remove_at(idx)


## 该角色每轮回补几张（因角色而异，主人钦定 DeepSeek 3 张）
static func refill_for(ai_id: String) -> int:
	return int(REFILL_BY_AI.get(ai_id, 3))


func set_refill(n: int) -> void:
	_refill_count = maxi(1, n)


## 对敌人结算伤害（先扣敌人格挡）。返回实际造成的伤害。
func _hit_enemy(dmg: int) -> int:
	var d := dmg
	if enemy_block > 0:
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
	start_turn()
	events.append({"kind": "new_turn", "turn": turn})
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


## 当前手牌里能量够的牌数（UI 提示用）
func playable_count() -> int:
	var n := 0
	for c in hand:
		if c == hand[0]:
			n += 1
	return n
