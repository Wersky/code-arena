class_name RunState
extends RefCounted
## 一局 Run（肉鸽）的全部状态：牌库、AI 道具、算力点、进度。
##
## 牌库顺序用 Array 管理，UI 只读不依赖 SceneTree 顺序。

## 命令行片段上限（最多 6 段，对应 6 种 flag）
const MAX_COMMAND_PARTS := 6

var deck: Array[CardData] = []
var items: Array[AiItemData] = []
var compute: int = 0
var chapter: int = 1
var level_index: int = 0          # 已通关数量
var rng := RandomNumberGenerator.new()
## 本局的随机种子基准。每一关的洗牌种子 = run_seed + 关卡 id 哈希，
## 保证**每一关的牌序都不一样**，但同一关在同一局里是可复现的。
var run_seed: int = 0

# ── 本关内状态 ──────────────────────────────────────
var draw_pile: Array[CardData] = []
var discard_pile: Array[CardData] = []
var hand: Array[CardData] = []
var score: int = 0
var turn: int = 0
var shield_ready: int = 0
var rerolls_left: int = 0
var last_result: Dictionary = {}

# ── 命令行机制 ──────────────────────────────────────
## 本局的核心 AI 娘。reset_run() 时置空，选定后整局不变。
var ai: AiData = null
## 本回合命令行片段（顺序 = 玩家点击顺序）
var command_parts: Array[String] = []

# ── 扑克牌机制（**当前主玩法**）──────────────────────────
## 起始牌池：**扑克 52 张全牌**（4 花色 × 点数 1~13），2026-10-22 起不再是手写 9 张
const POKER_RANKS := 13
## 一副完整扑克的张数（写死给断言用，避免两边算错）
const POKER_DECK_SIZE := 52
## 每回合发几张到手牌
const POKER_HAND_SIZE := 8
## 一次最多打几张
const POKER_PLAY_LIMIT := 5

var poker_deck: Array[PokerCard] = []
var poker_draw: Array[PokerCard] = []
## 弃牌堆：**还会回来**（抽牌堆空了就洗回来）
var poker_discard: Array[PokerCard] = []
## 失效堆：**打出去的牌**，本关内不再回到手牌（按主人的机制：打完即失效）
var poker_void: Array[PokerCard] = []
var poker_hand: Array[PokerCard] = []
## 本关剩余出牌次数 / 弃牌次数
var hands_left: int = 0
var discards_left: int = 0
## 本局永久加成（奖励累积）
var bonus_chips: int = 0
var bonus_mult: int = 0
var _poker_deck_built: bool = false


func _init() -> void:
	rng.randomize()


func reset_run() -> void:
	rng.randomize()
	run_seed = rng.randi()
	deck = CardPool.starting_deck()
	items.clear()
	compute = 0
	chapter = 1
	level_index = 0
	score = 0
	turn = 0
	draw_pile.clear()
	discard_pile.clear()
	hand.clear()
	ai = null
	command_parts.clear()
	reset_poker()


## ── 扑克牌机制 ──────────────────────────────────────

## 清空扑克状态（reset_run 时调用）
func reset_poker() -> void:
	poker_deck.clear()
	_poker_deck_built = false
	poker_draw.clear()
	poker_discard.clear()
	poker_void.clear()
	poker_hand.clear()
	hands_left = 0
	discards_left = 0
	bonus_chips = 0
	bonus_mult = 0


## 起始牌池：一副完整扑克（4 花色 × 13 点数 = 52 张）
func ensure_poker_deck() -> void:
	if _poker_deck_built:
		return
	poker_deck.clear()
	for suit in [PokerCard.Suit.HEART, PokerCard.Suit.DIAMOND,
			PokerCard.Suit.SPADE, PokerCard.Suit.CLUB]:
		for rank in range(1, POKER_RANKS + 1):
			poker_deck.append(PokerCard.make(suit, rank))
	_poker_deck_built = true


func build_poker_deck() -> Array[PokerCard]:
	ensure_poker_deck()
	return poker_deck.duplicate()


## 往牌库加一张（奖励用）
func add_poker_card(suit: int, rank: int) -> void:
	ensure_poker_deck()
	poker_deck.append(PokerCard.make(suit, rank))


## 开一关：清零分数、按关卡种子洗牌、发手牌、给足出牌/弃牌次数
func start_poker_level(level: LevelData) -> void:
	rng.seed = run_seed + level.id.hash() + 9311
	score = 0
	turn = 0
	last_result = {}
	hands_left = level.turns
	discards_left = 2
	poker_draw.clear()
	poker_discard.clear()
	poker_void.clear()
	poker_hand.clear()
	poker_draw = build_poker_deck()
	_shuffle_poker(poker_draw)
	draw_poker(POKER_HAND_SIZE)


func _shuffle_poker(arr: Array[PokerCard]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: PokerCard = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 抽 n 张进手牌；抽牌堆空就洗回**弃牌堆**（失效堆不参与洗回）
func draw_poker(count: int) -> void:
	var added := 0
	while added < count:
		if poker_draw.is_empty():
			if poker_discard.is_empty():
				break
			poker_draw.append_array(poker_discard)
			poker_discard.clear()
			_shuffle_poker(poker_draw)
		poker_hand.append(poker_draw.pop_back())
		added += 1


## 打出一手：打出的牌进**失效堆**（本关不再回来），补满手牌，出牌次数 −1
func play_poker_hand(played: Array[PokerCard]) -> void:
	for c in played:
		poker_void.append(c)
		poker_hand.erase(c)
	draw_poker(POKER_HAND_SIZE - poker_hand.size())
	hands_left = maxi(0, hands_left - 1)
	turn += 1


## 弃掉选中的牌，补满手牌，弃牌次数 −1
func discard_poker(cards: Array[PokerCard]) -> bool:
	if discards_left <= 0 or cards.is_empty():
		return false
	for c in cards:
		poker_discard.append(c)
		poker_hand.erase(c)
	draw_poker(POKER_HAND_SIZE - poker_hand.size())
	discards_left -= 1
	return true


## 设定核心 AI 娘；换人时清空命令行（命令行前缀会变）
func set_ai(a: AiData) -> void:
	ai = a
	command_parts.clear()


## 清空本回合命令行
func clear_command() -> void:
	command_parts.clear()


## 完整命令行文本；ai 为 null 时前缀用 "prompt"
func command_text() -> String:
	var prefix := "prompt"
	if ai != null:
		prefix = ai.id
	return AiTaste.compose_command(prefix, command_parts)


## 追加一个命令行片段（选卡 → 追加参数片段）。返回 false = 被拒绝（已达上限）。
func add_command_part(fragment: String) -> bool:
	if fragment == "":
		return false
	if command_parts.size() >= MAX_COMMAND_PARTS:
		return false
	command_parts.append(fragment)
	return true


## 追加一张卡对应的命令行片段（用它的 cli_fragment()）。
func add_card_part(card: CardData) -> bool:
	if card == null:
		return false
	return add_command_part(card.cli_fragment())


## 撤回第 index 个片段（0 起）；其后的片段自动前移。返回被撤回的片段。
func remove_command_part(index: int) -> String:
	if index < 0 or index >= command_parts.size():
		return ""
	var removed := command_parts[index]
	command_parts.remove_at(index)
	return removed


func add_item(item: AiItemData) -> void:
	items.append(item)
	match item.effect_id:
		"shield":
			shield_ready += item.power
		"reroll":
			rerolls_left += item.power


func has_effect(effect_id: String) -> bool:
	for it in items:
		if it.effect_id == effect_id:
			return true
	return false


func items_with(effect_id: String) -> Array[AiItemData]:
	var out: Array[AiItemData] = []
	for it in items:
		if it.effect_id == effect_id:
			out.append(it)
	return out


## 开一关：按关卡规则过滤牌库、洗牌、发初始手牌。
func start_level(level: LevelData) -> void:
	# 每关独立种子：同一局里不同关的牌序完全不同；同一关重打则可复现
	rng.seed = run_seed + level.id.hash()

	draw_pile.clear()
	discard_pile.clear()
	hand.clear()
	score = 0
	turn = 0
	last_result = {}
	command_parts.clear()

	# 重置一次性资源
	shield_ready = 0
	rerolls_left = 0
	for it in items:
		match it.effect_id:
			"shield":
				shield_ready += it.power
			"reroll":
				rerolls_left += it.power

	for c in deck:
		draw_pile.append(c)
	_shuffle(draw_pile)
	draw_hand(8)


func _shuffle(arr: Array[CardData]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: CardData = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func draw_hand(count: int) -> void:
	var added := 0
	while added < count:
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			draw_pile.append_array(discard_pile)
			discard_pile.clear()
			_shuffle(draw_pile)
		hand.append(draw_pile.pop_back())
		added += 1


## 结算一回合：整手牌（打出的 + 没打出的）都进弃牌堆，然后补满手牌。
## 与小丑牌一致——每回合手牌作废重抽，牌库耗尽时自动把弃牌堆洗回。
func end_turn(played: Array[CardData]) -> void:
	for c in hand:
		discard_pile.append(c)
	for c in played:
		# 打出前通常已从 hand 移除；这里兜底防止同一张牌进两次弃牌堆
		if not discard_pile.has(c):
			discard_pile.append(c)
	hand.clear()
	draw_hand(8)
	turn += 1


## 重抽整副手牌（DPO 效果）。返回是否成功。
func reroll_hand() -> bool:
	if rerolls_left <= 0:
		return false
	rerolls_left -= 1
	for c in hand:
		discard_pile.append(c)
	hand.clear()
	draw_hand(8)
	return true


## 过关奖励算力点。
## 基础值按关卡回合数给（回合通常是用完的，只按"剩余回合"算等于只给溢出分，
## 会导致打完第一关连一张卡都买不起）；溢出目标分再额外折算。
func award_compute(level: LevelData) -> int:
	var base := level.turns * 15
	var overflow_pts: int = maxi(0, score - level.target_score) / 10
	var gain := base + overflow_pts
	compute += gain
	return gain
