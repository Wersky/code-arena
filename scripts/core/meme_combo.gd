class_name MemeCombo
extends RefCounted
## 梗卡连携引擎：新卡牌机制的判定与结算（与旧 Scoring 完全平行，互不影响）。
##
## 计分公式（唯一一条）：
##   base  = Σ (卡基础分 × 主题倍率 × 连携类型倍率) + 连携的"所有卡加 N 分"
##   flat  = Σ 连携的加分（可为负）
##   mult  = Π 连携的倍率
##   score = round((base + flat) × mult) − 惩罚
##
## Token 预算默认 9，每张卡消耗自己的 Token，超预算每点罚 12 分。
##
## 静态 API（下游界面层只用这几个）：
##   MemeCombo.table()                    -> Array[Dictionary] 全部连携定义
##   MemeCombo.combo_count()              -> int
##   MemeCombo.get_combo(id)              -> Dictionary
##   MemeCombo.detect(cards, theme_id)    -> Array[Dictionary] 命中列表
##   MemeCombo.evaluate(cards, ctx)       -> Dictionary 完整结算
##
## ctx 约定（缺省项都有安全默认）：
##   theme_id: String      AI娘主题 id（deepdeek / gemigo / grock / kweno）
##   token_budget: int     Token 预算，默认 9
##   rng: RandomNumberGenerator  随机效果用这个（可注入，便于测试复现）
##   carry: Dictionary     上一回合留下的状态：
##                          next_mult(float) 本回合总分倍率
##                          penalty_shield(bool) 本回合惩罚归零
##                          hand_limit_delta(int) 手牌上限累计变化
##                          hand_delta_next(int) 下回合手牌张数变化
##
## 返回值：
##   score:int flat:int mult:float hits:Array[Dictionary] penalty:int
##   token_used:int token_budget:int
##   base:int per_card:Array[Dictionary] blocked:Array[String]
##   effects:Dictionary carry:Dictionary notes:Array[String]

const DEFAULT_TOKEN_BUDGET := 9
const OVERFLOW_COST := 12          # 每超 1 Token 罚 12 分
const DEFAULT_HAND_SIZE := 5       # 每回合最多打 5 张

const K := MemeCard.Kind

static var _table: Array[Dictionary] = []


# ── 连携表（唯一真值；新增连携只改这里，引擎是数据驱动的）──────────
static func table() -> Array[Dictionary]:
	if not _table.is_empty():
		return _table
	var t: Array[Dictionary] = []
	# ── 原始 16 条 ────────────────────────────────
	t.append(_c("c_rice2", "一饭两吃", "饭类卡分值 ×2",
		[["rice", 2]], {"kind_mult": {K.FOOD: 2.0}}))
	t.append(_c("c_infinite", "无限续饭", "饭类卡分值 +40%",
		[["rice", 1], ["while_kw", 1]], {"kind_mult": {K.FOOD: 1.4}}))
	t.append(_c("c_rice_rec", "米生米", "下一张饭卡触发两次",
		[["rice", 1], ["recursion", 1]], {"next_food_double": true}))
	t.append(_c("c_stuck", "卡死", "跳过本回合，下一次结算 ×1.3",
		[["while_kw", 1], ["deadlock", 1]],
		{"skip_round": true, "next_settle_mult": 1.3}))
	t.append(_c("c_nest", "套娃", "下一张卡的效果触发两次",
		[["for_kw", 1], ["recursion", 1]], {"next_card_double": true}))
	t.append(_c("c_catch", "兜住了", "抵消下一次惩罚",
		[["try_kw", 1], ["catch_kw", 1]], {"penalty_shield_next": true}))
	t.append(_c("c_choice", "选择困难", "打出时可以撤回上一次出牌",
		[["if_kw", 1], ["else_kw", 1]], {"undo_allowed": true}))
	t.append(_c("c_spam", "刷屏", "分数 −40，抽 2 张牌",
		[["printf", 3]], {"flat": -40, "draw": 2}))
	t.append(_c("c_halluc", "一本正经胡说八道", "得分随机 ×0.5 或 ×2",
		[["illusion", 1], ["temp", 1]], {"random_mult": [0.5, 2.0]}))
	t.append(_c("c_overflow", "爆上下文", "手牌上限 −1，所有卡 +10 分",
		[["context", 1], ["token", 1]],
		{"all_cards_flat": 10, "hand_limit_delta": -1}))
	t.append(_c("c_foodie", "干饭人的干饭", "+50 分，抽 1 张牌",
		[["foodie", 1], ["rice", 1]], {"flat": 50, "draw": 1}))
	t.append(_c("c_hotpot", "火锅局", "本回合得分 ×1.25",
		[["hotpot", 1], ["foodie", 1]], {"mult": 1.25}))
	t.append(_c("c_hit", "命中缓存", "本回合不消耗 Token",
		[["cache", 1], ["context", 1]], {"free_token": true}))
	t.append(_c("c_free", "干饭自由", "饭类卡分值 ×1.5",
		[["bigfish", 1], ["rice", 1]], {"kind_mult": {K.FOOD: 1.5}}))
	t.append(_c("c_binge", "扶墙出", "+120 分，下回合少 1 张手牌",
		[["bigfish", 1], ["binge", 1]],
		{"flat": 120, "hand_delta_next": -1}))
	t.append(_c("c_salary", "长胖自由", "分数 ×1.4，但手牌上限 −1",
		[["bigfish", 1], ["rice_freedom", 1]],
		{"mult": 1.4, "hand_limit_delta": -1}))
	# ── 新增 8 条 ────────────────────────────────
	t.append(_c("c_canteen", "食堂三连", "饭类卡分值 ×1.5，Token 消耗 −1",
		[["foodie", 1], ["hotpot", 1], ["rice", 1]],
		{"kind_mult": {K.FOOD: 1.5}, "token_delta": -1}))
	t.append(_c("c_nested", "双层循环", "代码类卡分值 ×1.2，抽 1 张牌",
		[["while_kw", 1], ["for_kw", 1]],
		{"kind_mult": {K.CODE: 1.2}, "draw": 1}))
	t.append(_c("c_dive", "深海下潜", "专属卡分值 ×1.4，抽 1 张牌",
		[["bigfish", 1], ["deepfish", 1]],
		{"kind_mult": {K.EXCLUSIVE: 1.4}, "draw": 1}))
	t.append(_c("c_buffet", "自助餐厅", "分数 ×1.3，抽 2 张牌",
		[["rice_freedom", 1], ["binge", 1]],
		{"mult": 1.3, "draw": 2}))
	t.append(_c("c_emerge2", "涌现涌现", "玄学类卡分值 ×1.5",
		[["emerge", 2]], {"kind_mult": {K.MYSTIC: 1.5}}))
	t.append(_c("c_hotpot_binge", "扶墙火锅", "+150 分，抽 1 张牌",
		[["hotpot", 1], ["binge", 1]], {"flat": 150, "draw": 1}))
	t.append(_c("c_mantou2", "馒头管够", "+60 分，Token 消耗 −1",
		[["mantou", 2]], {"flat": 60, "token_delta": -1}))
	t.append(_c("c_hot_cache", "热缓存", "+70 分，下回合 Token 预算 +1",
		[["cache", 1], ["token", 1]],
		{"flat": 70, "token_budget_next": 1}))
	_table = t
	return _table


static func _c(id: String, name: String, desc: String,
		requires: Array, effects: Dictionary = {}) -> Dictionary:
	return {
		"id": id, "name": name, "desc": desc,
		"requires": requires, "effects": effects,
	}


static func combo_count() -> int:
	return table().size()


static func get_combo(combo_id: String) -> Dictionary:
	for c in table():
		if str(c["id"]) == combo_id:
			return c
	return {}


# ── 判定 ───────────────────────────────────────────────────
## 统计可用卡片的 id 出现次数（专属卡不在对应主题下时视为不存在）
static func _counts(cards: Array[MemeCard], theme_id: String) -> Dictionary:
	var out := {}
	for c in cards:
		if c == null:
			continue
		if not MemeCard.card_allowed_in(theme_id, c):
			continue
		out[c.id] = int(out.get(c.id, 0)) + 1
	return out


## 连携命中列表。返回 [{combo_id, name, desc, effects}]，顺序即连携表顺序。
static func detect(cards: Array[MemeCard], theme_id: String = "") -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if cards.is_empty():
		return hits
	var counts := _counts(cards, theme_id)
	for combo in table():
		if _requires_met(combo["requires"], counts):
			hits.append({
				"combo_id": str(combo["id"]),
				"name": str(combo["name"]),
				"desc": str(combo["desc"]),
				"effects": (combo["effects"] as Dictionary).duplicate(true),
			})
	return hits


static func _requires_met(requires: Array, counts: Dictionary) -> bool:
	for req in requires:
		var pair: Array = req
		var card_id := str(pair[0])
		var need := int(pair[1])
		if int(counts.get(card_id, 0)) < need:
			return false
	return true


# ── 结算 ───────────────────────────────────────────────────
static func evaluate(cards: Array[MemeCard], ctx: Dictionary = {}) -> Dictionary:
	var theme_id := str(ctx.get("theme_id", ctx.get("ai_id", "")))
	var carry: Dictionary = ctx.get("carry", {})
	var budget := int(ctx.get("token_budget", DEFAULT_TOKEN_BUDGET)) \
		+ int(carry.get("token_budget_delta", 0))
	var rng: RandomNumberGenerator = ctx.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var notes: Array[String] = []
	# 关卡特殊规则（梗卡语义）与本局永久加成
	var level_rule := int(ctx.get("level_rule", 0))
	var flat_bonus := int(ctx.get("all_cards_flat_bonus", 0))

	var result := {
		"score": 0, "base": 0, "flat": 0, "mult": 1.0,
		"hits": [] as Array[Dictionary], "penalty": 0,
		"token_used": 0, "token_budget": budget,
		"per_card": [] as Array[Dictionary], "blocked": [] as Array[String],
		"effects": {} as Dictionary, "carry": {} as Dictionary,
		"notes": notes,
	}

	# ── 0. 专属卡过滤：专属卡只在对应主题下可用 ─────────────
	var usable: Array[MemeCard] = []
	var blocked: Array[String] = []
	for c in cards:
		if c == null:
			continue
		if MemeCard.card_allowed_in(theme_id, c):
			usable.append(c)
		else:
			blocked.append("%s（专属卡，仅限对应主题）" % c.name)
	result["blocked"] = blocked
	if not blocked.is_empty():
		notes.append("有 %d 张专属卡在本主题下不可用，已忽略。" % blocked.size())

	if usable.is_empty():
		result["notes"] = notes
		return result

	# ── 1. 连携判定 ─────────────────────────────────────
	var hits := detect(usable, theme_id)
	result["hits"] = hits

	# ── 2. 汇总连携效果 ─────────────────────────────────
	var kind_mult := {}            # Kind -> float（连携带来的类型倍率）
	var flat := 0
	var mult := 1.0
	var all_cards_flat := 0
	var draw := 0
	var token_delta := 0
	var token_budget_next := 0
	var skip_round := false
	var next_settle_mult := 1.0
	var penalty_shield_next := false
	var undo_allowed := false
	var free_token := false
	var hand_limit_delta := 0
	var hand_delta_next := 0
	var random_mults: Array = []

	for h in hits:
		var fx: Dictionary = h["effects"]
		for k in (fx.get("kind_mult", {}) as Dictionary).keys():
			kind_mult[k] = float(kind_mult.get(k, 1.0)) * float((fx["kind_mult"] as Dictionary)[k])
		flat += int(fx.get("flat", 0))
		mult *= float(fx.get("mult", 1.0))
		all_cards_flat += int(fx.get("all_cards_flat", 0))
		draw += int(fx.get("draw", 0))
		token_delta += int(fx.get("token_delta", 0))
		token_budget_next += int(fx.get("token_budget_next", 0))
		hand_limit_delta += int(fx.get("hand_limit_delta", 0))
		hand_delta_next += int(fx.get("hand_delta_next", 0))
		if bool(fx.get("skip_round", false)):
			skip_round = true
		if bool(fx.get("penalty_shield_next", false)):
			penalty_shield_next = true
		if bool(fx.get("undo_allowed", false)):
			undo_allowed = true
		if bool(fx.get("free_token", false)):
			free_token = true
		var nsm := float(fx.get("next_settle_mult", 1.0))
		if nsm != 1.0:
			next_settle_mult *= nsm
		if fx.has("random_mult"):
			random_mults.append((fx["random_mult"] as Array).duplicate())

	# 随机倍率（可注入 RNG，测试可复现）
	for opts in random_mults:
		var pick: float = float(opts[rng.randi_range(0, opts.size() - 1)])
		mult *= pick
		notes.append("随机倍率 ×%s" % ("%.2f" % pick))

	# ── 3. 逐卡基础分 ───────────────────────────────────
	#   主题倍率 → 连携类型倍率 → +所有卡加 N 分
	#   "下一张 X 触发两次"：以该连携的**最后一张触发牌**为锚点，
	#   往后找第一张符合条件的牌，该牌本回合得分 ×2（可叠加）。
	var double_count := {}
	for h in hits:
		var fx: Dictionary = h["effects"]
		var want_food := bool(fx.get("next_food_double", false))
		var want_any := bool(fx.get("next_card_double", false))
		if not (want_food or want_any):
			continue
		var anchor := _anchor_index(h, usable)
		if anchor < 0:
			continue
		for i in range(anchor + 1, usable.size()):
			var c := usable[i]
			if want_any or c.kind == K.FOOD:
				double_count[i] = int(double_count.get(i, 0)) + 1
				break

	var per_card: Array[Dictionary] = []
	var base := 0.0
	for i in usable.size():
		var c := usable[i]
		var tb := MemeCard.theme_bonus(theme_id, c)
		var v := float(c.base_score) * float(tb["mult"])
		var km := float(kind_mult.get(c.kind, 1.0))
		if km != 1.0:
			v *= km
		v += float(tb["flat"])
		if flat_bonus != 0:
			v += float(flat_bonus)
		# 关卡规则：指定类型基础分减半
		match level_rule:
			LevelData.Rule.HALF_PERSONA:
				if c.kind == MemeCard.Kind.FOOD:
					v *= 0.5
			LevelData.Rule.HALF_EXAMPLE:
				if c.kind == MemeCard.Kind.MISC:
					v *= 0.5
			LevelData.Rule.HALF_RISKY:
				if c.kind == MemeCard.Kind.EXCLUSIVE:
					v *= 0.5
		if all_cards_flat != 0:
			v += float(all_cards_flat)
		var doubles := int(double_count.get(i, 0))
		if doubles > 0:
			v *= pow(2.0, float(doubles))
		var iv := int(round(v))
		base += float(iv)
		per_card.append({
			"id": c.id, "name": c.name, "kind": c.kind,
			"kind_name": MemeCard.kind_name(c.kind),
			"base_score": c.base_score, "token_cost": c.token_cost,
			"score": iv, "doubled": doubles > 0,
		})
	result["per_card"] = per_card
	result["base"] = int(round(base))

	# ── 4. Token 与惩罚 ────────────────────────────────
	var token_used := 0
	for c in usable:
		token_used += c.token_cost
	token_used = maxi(0, token_used + token_delta)
	if free_token:
		token_used = 0
	var overflow := maxi(0, token_used - budget)
	var penalty := overflow * OVERFLOW_COST
	if level_rule == LevelData.Rule.DOUBLE_OVERFLOW:
		penalty *= 2
	if bool(carry.get("penalty_shield", false)) and penalty > 0:
		penalty = 0
		notes.append("「兜住了」抵消了本次惩罚。")

	# ── 5. 总分 ────────────────────────────────────────
	var total_mult := mult * float(carry.get("next_mult", 1.0))
	var score := int(round((float(result["base"]) + float(flat)) * total_mult)) - penalty
	# 关卡规则：必须包含某类型 / 至少 2 张，否则减半
	match level_rule:
		LevelData.Rule.NEED_FORMAT:
			if not _has_kind(usable, MemeCard.Kind.CODE):
				score = int(round(float(score) * 0.5))
				notes.append("本关必须至少打出 1 张 代码 卡：得分减半。")
		LevelData.Rule.NEED_KNOWLEDGE:
			if not _has_kind(usable, MemeCard.Kind.MYSTIC):
				score = int(round(float(score) * 0.5))
				notes.append("本关必须至少打出 1 张 玄学 卡：得分减半。")
		LevelData.Rule.BOSS:
			if usable.size() < 2:
				score = int(round(float(score) * 0.5))
				notes.append("每回合至少打出 2 张卡：得分减半。")
	if skip_round:
		score = 0
		notes.append("「卡死」跳过本回合，下一次结算 ×%s。" % ("%.2f" % next_settle_mult))
	score = maxi(0, score)

	result["score"] = score
	result["flat"] = flat
	result["mult"] = total_mult
	result["penalty"] = penalty
	result["token_used"] = token_used
	result["token_budget"] = budget
	result["effects"] = {
		"kind_mult": kind_mult, "draw": draw, "token_delta": token_delta,
		"skip_round": skip_round, "undo_allowed": undo_allowed,
		"free_token": free_token, "hand_limit_delta": hand_limit_delta,
		"hand_delta_next": hand_delta_next, "all_cards_flat": all_cards_flat,
	}
	result["carry"] = {
		"next_mult": next_settle_mult,
		"penalty_shield": penalty_shield_next,
		"hand_limit_delta": int(carry.get("hand_limit_delta", 0)) + hand_limit_delta,
		"hand_delta_next": hand_delta_next,
		"token_budget_delta": token_budget_next,
	}
	result["notes"] = notes
	return result


## 该连携的"最后一张触发牌"在可用牌序列中的下标；找不到返回 -1
## 牌组里有没有某一类
static func _has_kind(cards: Array[MemeCard], kind: int) -> bool:
	for c in cards:
		if c.kind == kind:
			return true
	return false


static func _anchor_index(hit: Dictionary, usable: Array[MemeCard]) -> int:
	var combo := get_combo(str(hit["combo_id"]))
	if combo.is_empty():
		return -1
	var anchor := -1
	for req in (combo["requires"] as Array):
		var card_id := str((req as Array)[0])
		for i in range(usable.size() - 1, -1, -1):
			if usable[i].id == card_id:
				anchor = maxi(anchor, i)
				break
	return anchor
