class_name RunState
extends RefCounted
## 一局 Run（肉鸽）的全部状态：卡组、HP、AI 道具、算力点、进度。
##
## 2026-10-25 大改：德州扑克机制退场，改**杀戮尖塔制**——
## 牌库 / 抽牌堆 / 弃牌堆 / 能量 / 格挡的战斗状态在 StsCombat 里，
## 这里只存**跨关持久**的东西（卡组、HP、道具、进度、累计伤害）。

## 玩家生命上限（杀戮尖塔铁人起步值）
const MAX_HP := 80

var deck: Array[StsCard] = []
var items: Array[AiItemData] = []
var compute: int = 0
var chapter: int = 1
var level_index: int = 0          # 已通关数量
var rng := RandomNumberGenerator.new()
## 本局的随机种子基准。每一关的洗牌种子 = run_seed + 关卡 id 哈希。
var run_seed: int = 0

# ── 跨关状态 ──────────────────────────────────────────
var hp := MAX_HP
## 终端进场只在开始游戏时播一次（2026-10-31 主人钦定：每场战斗打完不再进加载）
var intro_played := false
## 累计造成的伤害（结算画面 / 排行用）
var score: int = 0
var last_result: Dictionary = {}

## 本局的核心 AI 娘。reset_run() 时置空，选定后整局不变。
var ai: AiData = null

# ── 运行序列（选关地图的节点，2026-11-01 主人钦定：战斗/事件两种类型）──
## 每 2 场战斗插 1 个事件节点：B1 B2 E B3 B4 E … B9 B10（10 战斗 + 4 事件）
var run_seq: Array[Dictionary] = []
var seq_idx := 0               ## 当前节点（map 上高亮的那个）


func build_run_seq() -> void:
	run_seq.clear()
	seq_idx = 0
	var battles := 0
	for lv in LevelPool.all_levels():
		run_seq.append({"type": "battle", "level": lv})
		battles += 1
		if battles % 2 == 0 and battles < 10:
			run_seq.append({"type": "event", "index": battles / 2})


func current_node() -> Dictionary:
	return run_seq[seq_idx] if seq_idx < run_seq.size() else {}


## 完成当前节点，推进到下一个
func node_finished() -> void:
	seq_idx += 1


func _init() -> void:
	rng.randomize()


func reset_run() -> void:
	rng.randomize()
	run_seed = rng.randi()
	deck = StsCardPool.starter_deck()
	items.clear()
	compute = 0
	chapter = 1
	level_index = 0
	hp = MAX_HP
	score = 0
	last_result = {}
	ai = null
	intro_played = false
	build_run_seq()


## 设定核心 AI 娘
func set_ai(a: AiData) -> void:
	ai = a


## 过关奖励往卡组里加一张
func add_card(card_id: String) -> void:
	var c := StsCardPool.card(card_id)
	if c != null:
		deck.append(c)


## 开一场战斗：卡组洗进抽牌堆、HP 续接上关、敌人数据来自关卡。
## 战斗状态机由此返回，arena 拿去驱动 UI。
func start_battle(level: LevelData) -> StsCombat:
	var cb := StsCombat.new()
	cb.setup(deck, level.enemy_name, level.enemy_hp,
			level.enemy_pattern(), hp, run_seed + level.id.hash() + 7717)
	return cb


## 战斗胜利：结算入账 + 小额回血
func win_battle(cb: StsCombat, level: LevelData) -> int:
	score += cb.damage_dealt
	hp = mini(MAX_HP, cb.hp + StsCombat.HEAL_ON_WIN)
	return award_compute(level)


## 战斗失败：结算入账
func lose_battle(cb: StsCombat) -> void:
	score += cb.damage_dealt


func add_item(item: AiItemData) -> void:
	items.append(item)


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


## 过关奖励算力点（战斗制：基础值随关卡走，不再有溢出分）
func award_compute(level: LevelData) -> int:
	var gain := 60 + level.index_in_chapter * 20
	compute += gain
	return gain
