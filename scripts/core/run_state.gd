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

## 事件冷却（2026-11-01 门选制）：每打完一场战斗可进 1 次事件门
var events_since_battle := 0
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
	# 精英怪（2026-11-01 主人钦定）：15% 概率红光精英，打倒掉宝箱道具
	cb.is_elite = rng.randf() < 0.15
	# 道具效果注入（2026-11-01 道具系统）
	for it in items:
		if it.broken:
			continue
		match it.effect_id:
			"prompt_opt":
				cb.atk_bonus += it.power
			"compress":
				cb.hand_bonus += it.power
				it.charges -= 1        ## 每打一场消耗 1 点耐久
				if it.charges <= 0:
					it.broken = true   ## 3 场用完 → 本局损坏（下一局重置自动修好）
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


## 精英宝箱：随机一件道具（打倒精英怪后由 arena 调用）
func grant_elite_chest() -> AiItemData:
	var it := StsItemPool.make(StsItemPool.random_id(rng))
	if it != null:
		add_item(it)
	return it


## 过关奖励算力点（战斗制：基础值随关卡走，不再有溢出分）
func award_compute(level: LevelData) -> int:
	var gain := 60 + level.index_in_chapter * 20
	compute += gain
	return gain
