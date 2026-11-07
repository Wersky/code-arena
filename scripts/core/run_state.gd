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
## 金币（2026-11-07 好感度系统）：打完关卡按伤害结算，商店里花
var gold: int = 0
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

## 许愿卡已用次数（2026-11-04）：额度 = min(2 + 关卡序号/2, 4)
var wish_used := 0
## 高费（cost=3）许愿卡的持有上限：试玩档「限获取」的口径
const MAX_TIER3 := 2


## 当前牌组里 cost=3 的许愿卡数量
func tier3_count() -> int:
	var n := 0
	for c in deck:
		if c.price_tier >= 3:
			n += 1
	return n


## 这张卡还能不能再拿：cost=3 的卡限量，其余不限
func can_acquire(card: StsCard) -> bool:
	if card == null:
		return false
	if card.price_tier < 3:
		return true
	return tier3_count() < MAX_TIER3


## 试玩档校正：只信缓存命中（samples>0），临时价不动；返回校正的卡数
func reprice_deck() -> int:
	var changed := 0
	for c in deck:
		if c.effects.is_empty():
			continue
		var r := EffectPricing.price_cached(c, level_index, EffectPricing.SAMPLES, false)
		if int(r.get("samples", 0)) <= 0:
			continue
		var tier := int(r["cost"])
		if tier != c.price_tier:
			c.price_tier = tier
			c.cost = clampi(tier, 1, 3)
			changed += 1
	return changed

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
	gold = 0
	chapter = 1
	level_index = 0
	hp = MAX_HP
	score = 0
	last_result = {}
	ai = null
	intro_played = false


## 门类型掷骰（2026-11-02 抽出，2026-11-07 加商店门）：
## 35% 战斗 / 25% 事件 / 10% 奖励 / 20% 精英 / 10% 商店。force 非空时**优先于随机**。
static func pick_special(roll: float, force: String) -> String:
	if force != "":
		return force
	if roll < 0.20:
		return "elite"
	if roll < 0.45:
		return "event"
	if roll < 0.55:
		return "bonus"
	if roll < 0.65:
		return "shop"
	return ""


## 设定核心 AI 娘；开局前同步该角色的起始卡组（ChatPPT 有专属攻防卡）。
func set_ai(a: AiData) -> void:
	ai = a
	if a != null:
		deck = StsCardPool.starter_deck_for(a.id)


## 过关奖励往卡组里加一张
func add_card(card_id: String) -> void:
	var c := StsCardPool.card(card_id)
	if c != null:
		deck.append(c)


## 开一场战斗：卡组洗进抽牌堆、HP 续接上关、敌人数据来自关卡。
## 战斗状态机由此返回，arena 拿去驱动 UI。
func start_battle(level: LevelData, elite: bool = false) -> StsCombat:
	## 试玩档校正：离线批次跑完后，把缓存里的真价套回许愿卡（2026-11-06）
	reprice_deck()
	# 电子木鱼（道具）：**先结算再开战**，否则战斗对象拿到的是旧 HP（2026-11-02 修）
	for it in items:
		if not it.broken and it.effect_id == "muyu":
			hp = mini(MAX_HP, hp + 5)
	var cb := StsCombat.new()
	cb.setup(deck, level.enemy_name, level.enemy_hp,
			level.enemy_pattern(), hp, run_seed + level.id.hash() + 7717)
	# 精英怪（2026-11-01 门选制）：精英门强制精英；事件效果挂载
	cb.is_elite = elite
	cb.enemy_hp = maxi(1, cb.enemy_hp + next_pre_hp)
	cb.atk_bonus += run_atk_bonus
	cb.hand_bonus += next_hand_bonus
	next_pre_hp = 0
	next_hand_bonus = 0
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


## 金币公式（2026-11-07 主人钦定：对数增长）——
## 前段伤害每点值钱，后段数值涨得快，金币增速放缓：
##   gold = GOLD_BASE · ln(1 + dmg / GOLD_DIV)
## 实测：dmg100→18 / 500→31 / 1000→46 / 2000→55 / 4000→65
const GOLD_BASE := 14.0
const GOLD_DIV := 40.0
static func gold_for_damage(dmg: int) -> int:
	return int(round(GOLD_BASE * log(1.0 + float(maxi(0, dmg)) / GOLD_DIV)))


## 本场结算的增量（arena 结算画面读）
var last_gold_gain := 0
var last_affection_gain := 0.0


## 喂白米饭 = 投喂 Deep Sick：本场吃下的每碗饭都涨好感（2026-11-07）
func _settle_affection(cb: StsCombat) -> float:
	var pts := float(cb.rice_eaten) * Affection.RICE_POINTS
	if pts > 0.0:
		Affection.add(pts)
		last_affection_gain += pts
	return pts


## 战斗胜利：结算入账 + 小额回血
func win_battle(cb: StsCombat, level: LevelData) -> int:
	score += cb.damage_dealt
	hp = mini(MAX_HP, cb.hp + StsCombat.HEAL_ON_WIN)
	_settle_affection(cb)
	last_gold_gain = gold_for_damage(cb.damage_dealt)
	gold += last_gold_gain
	return award_compute(level)


## 战斗失败：结算入账（喂饭的好感照算——饭是真吃了）
func lose_battle(cb: StsCombat) -> void:
	score += cb.damage_dealt
	_settle_affection(cb)
	last_gold_gain = gold_for_damage(cb.damage_dealt) / 2
	gold += last_gold_gain


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


## 运行级攻击加成（事件「AI 会取代人类吗」嘲讽路线）
var run_atk_bonus := 0
## 下一场战斗敌人先扣的血（事件效果）
var next_pre_hp := 0
## 下一场战斗手牌上限加成（事件「温度旋钮」）
var next_hand_bonus := 0


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
