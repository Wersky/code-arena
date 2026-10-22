class_name AiItemPool
extends RefCounted
## AI 道具池。全部使用规避版权的虚构名，对应各家大模型的"性格"。

const R := AiItemData.Rarity


static func _it(id: String, name: String, family: String, desc: String,
		effect: String, power: int, rarity: int, min_chapter: int = 1) -> AiItemData:
	var it := AiItemData.new()
	it.id = id
	it.display_name = name
	it.family = family
	it.description = desc
	it.effect_id = effect
	it.power = power
	it.rarity = rarity
	it.min_chapter = min_chapter
	return it


static func all_items() -> Array[AiItemData]:
	return [
		_it("deepdeek", "DeepDeek", "深度思考",
			"回合内第一张 任务/范例 卡，基础分 ×2。",
			"first_core_x2", 2, R.COMMON, 1),
		_it("chatppt", "ChatPPT", "通用对话",
			"每张 角色 卡额外 +25 分。",
			"persona_flat", 25, R.COMMON, 1),
		_it("gemigo", "Gemigo", "多模态",
			"命令行含 素材 卡（--knowledge）时，顺序层倍率 ×1.08。",
			"knowledge_mult", 1, R.RARE, 2),
		_it("kimo", "Kimo", "国产大模型",
			"某回合若只用了 ≤2 张卡，该回合得分 ×2。",
			"minimal_x2", 2, R.RARE, 2),
		_it("grock", "Grock", "实时联网",
			"第 3/6/9… 回合结算时，随机 ×0.6 或 ×1.6。",
			"gamble", 60, R.EPIC, 3),
		_it("glmio", "GLMio", "国产大模型",
			"每关 1 次，完全免除幻觉惩罚。",
			"shield", 1, R.RARE, 2),
		_it("kweno", "Kweno", "中文优化",
			"角色 / 范例 卡基础分 +15。",
			"cn_bonus", 15, R.COMMON, 1),
		_it("mistryl", "Mistryl", "欧系长文",
			"本关 Token 预算 +3。",
			"budget", 3, R.COMMON, 1),
		_it("rlhf", "RLHF 偏好对齐", "对齐后训练",
			"每关的第一个回合得分 ×1.5。",
			"first_turn_x15", 15, R.RARE, 2),
		_it("dpo", "DPO 偏好优化", "成对偏好",
			"每关可以重抽 1 次手牌。",
			"reroll", 1, R.RARE, 2),
		_it("sft", "SFT 微调", "监督微调",
			"所有卡基础分 +2。",
			"flat_all", 2, R.COMMON, 1),
		_it("distill", "Distill 蒸馏", "知识蒸馏",
			"每次结算后额外抽 1 张卡到手牌。",
			"extra_draw", 1, R.RARE, 3),
		_it("sorana", "Sorana 十四行", "诗性模型",
			"打出完美配方时额外 +150 分。",
			"perfect_bonus", 150, R.EPIC, 3),
		_it("prompteng", "PromptEng 提示工程", "方法论",
			"每命中 1 种牌型，额外 +10 分。",
			"combo_bonus", 10, R.COMMON, 1),
	]


## 按当前章节与已拥有情况抽 3 个候选奖励。
static func roll_rewards(rng: RandomNumberGenerator, chapter: int,
		owned: Array[AiItemData], count: int = 3) -> Array[AiItemData]:
	var pool: Array[AiItemData] = []
	var owned_ids := {}
	for it in owned:
		owned_ids[it.id] = true
	for it in all_items():
		if it.min_chapter <= chapter and not owned_ids.has(it.id):
			pool.append(it)
	# 已拥有的道具允许重复出现（做成叠层），稀有度高的概率更大
	for it in all_items():
		if owned_ids.has(it.id) and it.rarity == R.COMMON:
			pool.append(it)

	var out: Array[AiItemData] = []
	var guard := 0
	while out.size() < count and guard < 200:
		guard += 1
		if pool.is_empty():
			break
		var pick: AiItemData = pool[rng.randi_range(0, pool.size() - 1)]
		if out.has(pick):
			continue
		out.append(pick)
	return out
