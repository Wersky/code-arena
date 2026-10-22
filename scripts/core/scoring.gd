class_name Scoring
extends RefCounted
## 计分引擎。全部是纯静态函数，不持有状态、不引用 UI，可被单元测试直接调用。
##
## 最终分 = round((base + flat) × mult) − 超预算罚 − 幻觉罚
##   base  = Σ 卡基础分（含道具修正）
##   flat  = Σ 牌型加分 + Σ 道具加分
##   mult  = Π 牌型倍率 × Π 道具倍率
##
## ctx 约定（缺省项都有安全默认）：
##   token_budget: int        本关 Token 预算
##   items: Array[AiItemData] 已拥有的 AI 道具
##   turn_index: int          本关内第几回合（0 起）
##   rule: LevelData.Rule     本关特殊规则
##   shield: bool             是否有护盾可用（OlaMo）
##   preview: bool            true = 实时预估，不含随机项
##   rng: RandomNumberGenerator
##   ai: AiData                本局核心 AI 娘；null 时顺序层只跑通用规则
##   command_parts: Array[String] 本回合已敲进命令行的片段（顺序 = 点击顺序）
##
## 最终分 = round((base + flat) × mult × order_mult) + order_flat − 超预算罚 − 幻觉罚

const K := CardData.Kind

const OVERFLOW_COST := 15          # 每超 1 Token 的罚分
const HALUCINATION_COST := 70      # 幻觉惩罚
const RISK_MULT := 1.40           # 风险卡倍率
const PERFECT_MULT := 1.50        # 完美配方倍率


## 有效 Token 预算 = 本关预算 + 所有 Mistraline 之类的加成
static func effective_budget(ctx: Dictionary) -> int:
	var budget: int = int(ctx.get("token_budget", 99))
	for it in _items(ctx):
		if it.effect_id == "budget":
			budget += it.power
	return budget


static func _items(ctx: Dictionary) -> Array[AiItemData]:
	var raw = ctx.get("items", [])
	var out: Array[AiItemData] = []
	for it in raw:
		out.append(it)
	return out


static func _count_kinds(cards: Array[CardData]) -> Dictionary:
	var counts := {}
	for k in CardData.KIND_ORDER:
		counts[k] = 0
	for c in cards:
		counts[c.kind] = int(counts.get(c.kind, 0)) + 1
	return counts


## 牌型判定。返回 [{id, name, mult, flat}]，顺序即展示顺序。
static func detect_combos(cards: Array[CardData]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cards.is_empty():
		return out
	var counts := _count_kinds(cards)
	var distinct := 0
	for k in counts:
		if int(counts[k]) > 0:
			distinct += 1

	# 堆叠：同类型 ≥3
	for k in CardData.KIND_ORDER:
		var n := int(counts.get(k, 0))
		if n >= 3:
			out.append({
				"id": "stack", "name": "堆叠 · %s" % CardData.kind_name(k),
				"mult": 1.15, "flat": 15 * n,
			})

	var has_persona := int(counts.get(K.PERSONA, 0)) > 0
	var has_task := int(counts.get(K.TASK, 0)) > 0
	var has_knowledge := int(counts.get(K.KNOWLEDGE, 0)) > 0
	var has_format := int(counts.get(K.FORMAT, 0)) > 0
	var has_example := int(counts.get(K.EXAMPLE, 0)) > 0
	var has_constraint := int(counts.get(K.CONSTRAINT, 0)) > 0

	if has_task and has_persona:
		out.append({"id": "brief", "name": "委托明确", "mult": 1.10, "flat": 30})
	if has_format:
		out.append({"id": "format", "name": "结构化输出", "mult": 1.10, "flat": 20})
	if has_example and has_task:
		out.append({"id": "fewshot", "name": "范例驱动", "mult": 1.15, "flat": 25})
	if has_knowledge:
		out.append({"id": "ground", "name": "接地", "mult": 1.05, "flat": 15})
	if has_constraint:
		out.append({"id": "control", "name": "受控", "mult": 1.10, "flat": 0})
	if has_task and has_example and has_constraint:
		out.append({"id": "cot", "name": "深度推理", "mult": 1.20, "flat": 40})
	if cards.size() >= 5 and distinct >= 5:
		out.append({"id": "perfect", "name": "完美配方", "mult": PERFECT_MULT, "flat": 100})

	var risky := false
	for c in cards:
		if c.risky:
			risky = true
			break
	if risky:
		out.append({"id": "hallucination", "name": "幻觉", "mult": RISK_MULT, "flat": -HALUCINATION_COST})
	return out


## 主入口。返回结算明细。
static func evaluate(cards: Array[CardData], ctx: Dictionary) -> Dictionary:
	# ── 2.5 顺序层（命令行结构 + AI 娘口味）────────────
	# 与牌型无关，先算好，空牌组也能返回完整的 taste 结构。
	var ai: AiData = ctx.get("ai", null) as AiData
	var raw_parts = ctx.get("command_parts", [])
	var command_parts: Array[String] = []
	if raw_parts is Array:
		for p in raw_parts:
			command_parts.append(str(p))
	var taste: Dictionary = AiTaste.evaluate(command_parts, ai)
	var order_flat := int(taste.get("score", 0))
	var order_mult := float(taste.get("mult", 1.0))
	var cmd_prefix := "prompt"
	if ai != null:
		cmd_prefix = ai.id
	var command_text := AiTaste.compose_command(cmd_prefix, command_parts)

	var result := {
		"score": 0, "base": 0, "flat": 0, "mult": 1.0,
		"combos": [] as Array[Dictionary], "penalty": 0, "notes": [] as Array[String],
		"token_cost": 0, "token_budget": 0, "overflow": 0,
		"has_risk": false, "shield_used": false,
		"taste": taste, "order_flat": order_flat, "order_mult": order_mult,
		"command_text": command_text, "item_mult": 1.0,
	}
	if cards.is_empty():
		result["notes"] = ["没有打出任何卡。" as String]
		return result

	var items := _items(ctx)
	var rule: int = int(ctx.get("rule", LevelData.Rule.NONE))
	var preview: bool = bool(ctx.get("preview", false))
	var notes: Array[String] = []

	# ── 2.6 道具层（顺序层倍率）───────────────────────
	# Gemigo（多模态）：命令行含 --knowledge 片段时，顺序层倍率 ×1.08。
	# 叠加在规则层倍率之上（规则层仍钳制 [0.50, 1.20]）。
	var item_mult := AiTaste.item_order_mult(command_parts, items)
	order_mult *= item_mult

	# ── 1. 基础分（逐卡算，再叠道具修正）────────────────
	var per_card: Array[float] = []
	for c in cards:
		var v := float(c.base_score)
		# 关卡规则：特定类型的基础分打折（保留牌型结构，只压分数）
		if rule == LevelData.Rule.HALF_PERSONA and c.kind == K.PERSONA:
			v *= 0.5
		elif rule == LevelData.Rule.HALF_EXAMPLE and c.kind == K.EXAMPLE:
			v *= 0.5
		elif rule == LevelData.Rule.HALF_RISKY and c.risky:
			v *= 0.5
		per_card.append(v)

	# 受控：约束卡基础分 ×2
	for i in cards.size():
		if cards[i].kind == K.CONSTRAINT:
			per_card[i] *= 2.0

	# 逐卡道具修正
	for it in items:
		match it.effect_id:
			"flat_all":
				for i in per_card.size():
					per_card[i] += float(it.power)
			"cn_bonus":
				for i in cards.size():
					if cards[i].kind == K.PERSONA or cards[i].kind == K.EXAMPLE:
						per_card[i] += float(it.power)
			"persona_flat":
				for i in cards.size():
					if cards[i].kind == K.PERSONA:
						per_card[i] += float(it.power)
			"first_core_x2":
				for i in cards.size():
					if cards[i].kind == K.TASK or cards[i].kind == K.EXAMPLE:
						per_card[i] *= 2.0
						break

	var base := 0.0
	for v in per_card:
		base += v

	# ── 2. 牌型 ────────────────────────────────────────
	var combos := detect_combos(cards)
	var flat := 0
	var mult := 1.0
	for combo in combos:
		# 幻觉的 −70 在结算末尾统一扣除，这里不重复计入（否则罚两次）
		if str(combo["id"]) != "hallucination":
			flat += int(combo["flat"])
		mult *= float(combo["mult"])

	# ── 3. 道具加分 / 倍率 ─────────────────────────────
	for it in items:
		match it.effect_id:
			"combo_bonus":
				flat += it.power * maxi(0, combos.size() - 1)  # 幻觉不算正牌型
			"perfect_bonus":
				for combo in combos:
					if combo["id"] == "perfect":
						flat += it.power

	if int(ctx.get("turn_index", 0)) == 0:
		for it in items:
			if it.effect_id == "first_turn_x15":
				mult *= 1.5
	if cards.size() <= 2:
		for it in items:
			if it.effect_id == "minimal_x2":
				mult *= 2.0
	if not preview:
		for it in items:
			if it.effect_id == "gamble":
				var t := int(ctx.get("turn_index", 0))
				if t > 0 and t % 3 == 0:
					var rng: RandomNumberGenerator = ctx.get("rng", null)
					if rng == null:
						rng = RandomNumberGenerator.new()
						rng.randomize()
					var roll := rng.randf()
					if roll < 0.5:
						mult *= 0.6
						notes.append("Grock 实时：本次联网结果不理想（×0.6）。")
					else:
						mult *= 1.6
						notes.append("Grock 实时：抓到了热点（×1.6）。")

	# ── 4. Token 与惩罚 ────────────────────────────────
	var token_cost := 0
	for c in cards:
		token_cost += c.token_cost
	var budget := effective_budget(ctx)
	var overflow := maxi(0, token_cost - budget)
	var overflow_penalty := overflow * OVERFLOW_COST
	if rule == LevelData.Rule.DOUBLE_OVERFLOW:
		overflow_penalty *= 2
		if overflow > 0:
			notes.append("超预算惩罚翻倍。")

	var has_risk := false
	for c in cards:
		if c.risky:
			has_risk = true
			break
	var hallucination_penalty := 0
	var shield_used := false
	if has_risk:
		var shielded := false
		for it in items:
			if it.effect_id == "shield" and bool(ctx.get("shield", false)):
				shielded = true
				shield_used = true
		if shielded:
			notes.append("OlaMo 护盾吸收了幻觉惩罚。")
		else:
			hallucination_penalty = HALUCINATION_COST

	# ── 5. 关卡规则 ────────────────────────────────────
	match rule:
		LevelData.Rule.NEED_FORMAT:
			var has_format := false
			for c in cards:
				if c.kind == K.FORMAT:
					has_format = true
					break
			if not has_format:
				mult *= 0.5
				notes.append("本关必须打出 格式 卡：得分减半。")
		LevelData.Rule.NEED_KNOWLEDGE:
			var has_knowledge := false
			for c in cards:
				if c.kind == K.KNOWLEDGE:
					has_knowledge = true
					break
			if not has_knowledge:
				mult *= 0.5
				notes.append("本关必须打出 素材 卡：得分减半。")
		LevelData.Rule.BOSS:
			if cards.size() < 2:
				mult *= 0.5
				notes.append("终局评测要求每回合至少 2 张卡：得分减半。")

	# 顺序层的 flat 在乘法之外（硬约定），倍率参与乘法
	var score := int(round((base + flat) * mult * order_mult)) + order_flat
	score = maxi(0, score - overflow_penalty - hallucination_penalty)

	result["score"] = score
	result["base"] = int(base)
	result["flat"] = flat
	result["mult"] = mult
	result["combos"] = combos
	result["penalty"] = overflow_penalty + hallucination_penalty
	result["notes"] = notes
	result["token_cost"] = token_cost
	result["token_budget"] = budget
	result["overflow"] = overflow
	result["has_risk"] = has_risk
	result["shield_used"] = shield_used
	result["taste"] = taste
	result["order_flat"] = order_flat
	result["order_mult"] = order_mult
	result["command_text"] = command_text
	result["item_mult"] = item_mult
	return result
