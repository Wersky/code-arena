class_name EffectCombo
extends RefCounted
## 牌组级组合审计（圆桌第 3 轮：维度写集并集 + 30 场差分抽样）。
##
## 为什么卡对判定不够（平衡师第 2 轮的反例）：
##   两张单场无害的卡，放进同一副牌里可能叠出跨场效应——这是**牌组级属性**，
##   按卡看 clause 永远看不出来。
##
## 两层做法：
##   1. 静态：全牌组写集并集 → 找出「共享可累积维度 + 同相位序」的候选卡对
##   2. 动态：对候选对做**固定牌组规模的差分抽样**，算交互项
##        excess = S(AB) - S(A) - S(B) + S(base)
##      excess 显著为正 → 两张卡在一起比各自单独之和更强 → 判 block
##
## 牌组规模必须固定（用 vanilla 填充卡补齐），否则测出来的是"多一张牌"的价值，
## 不是两张卡之间的交互——这个坑在单卡定价时踩过一次。

const FILLER_DAMAGE := 6
const REF_DECK_SIZE := 14
## 14 张牌的参考牌组比 11 张强得多：擂台血量单独标定（实测 hp=600 → 胜率 0.47）。
## 沿用单卡定价的 hp=200 会让胜率饱和在 0.96，差分失去分辨力。
const COMBO_HP := 600
const DIFF_SAMPLES := 30
## 交互项超过这个值判为复合增长（win_rate 按 0–100 计，turn 按 2 倍权重）
const SUPER_ADDITIVE := 12.0
## 噪声地板：30 场抽样的交互项噪声约 ±2–4，低于地板的正值不算"可疑"
const VERIFY_FLOOR := 3.0
const MAX_PAIRS := 8
## 三元组：三阶交互（容斥）阈值更高——三项叠加本身波动更大
const TRIPLE_ADDITIVE := 15.0
const TRIPLE_VERIFY_FLOOR := 5.0
const MAX_TRIPLES := 6
## 四张组：四阶交互（容斥 16 组评分），阈值再抬高
const QUAD_ADDITIVE := 18.0
const QUAD_VERIFY_FLOOR := 6.0
const MAX_QUADS := 4
## 组检测上限：候选池本身封顶 6 张，所以子集总数永远 ≤ 2^6 = 64，
## 把上限提到 6 不会让成本失控（memo 跨组共享，子集只算一次）。
const MAX_GROUP := 6

## ── 持久化子集评分缓存（2026-11-10）──────────────────────────
## 战前同步跑全量审计，本机实测：2 张效果卡 0ms、4 张 1.7s、6 张 9.2s。
## 9 秒塞不进开战流程，所以照搬 EffectPricing 已验证的「离线算 + 在线查表」：
## 子集评分落盘，命中零成本；miss 时按 budget_ms 截断，缺失的组标 unverified。
## **铁律：unverified 绝不算 clean**——把没算过的组当无害，等于审计形同虚设。
const COMBO_CACHE_PATH := "user://effect_combo_cache.json"
const COMBO_CACHE_VERSION := 1
## 离线预热与在线审计必须用同一个 samples，否则缓存键不同、永远 miss。
const DEFAULT_SAMPLES := 30

static var _scache: Dictionary = {}
static var _scache_loaded := false
static var _scache_dirty := false
## 本次审计的墙钟截止（0 = 不限）。由 audit() 设置，_score_cached 检查。
static var _audit_deadline := 0


## 返回 {tag, dims, pairs:[...], triples:[...], blocked, verified, unverified, pending}
##   tag: clean / verify / block / partial
##
## budget_ms 语义（三档，2026-11-10）：
##   < 0  不限时（离线批次 / 工具用）
##   = 0  纯查表，**一个子集都不新算**（开战瞬间用，保证不阻塞）
##   > 0  墙钟预算，到点停手（入牌组时的渐进预热用，不卡帧）
##
## 未算完的组标 unverified、整体 tag 降级为 partial。
## **partial 不等于 clean**：调用方必须把 partial 当作"未知风险"处理。
static func audit(deck: Array[StsCard], level_index: int = 1,
		samples: int = DIFF_SAMPLES, include_triples: bool = true,
		budget_ms: int = -1) -> Dictionary:
	_load_scache()
	if budget_ms < 0:
		_audit_deadline = -1
	elif budget_ms == 0:
		_audit_deadline = 0
	else:
		_audit_deadline = Time.get_ticks_msec() + budget_ms
	_scache_dirty = false

	var dims := {}
	var fx_cards: Array[StsCard] = []
	for c in deck:
		if c.effects.is_empty():
			continue
		fx_cards.append(c)
		for d in EffectDSL.writeset(c.effects).keys():
			dims[String(d)] = true

	## 牌组里没有可组合的效果卡时，无事可审，直接放行
	if fx_cards.size() < 2:
		_audit_deadline = -1
		return {"tag": "clean", "dims": dims, "pairs": [], "triples": [],
				"quads": [], "blocked": 0, "verified": 0,
				"unverified": 0, "pending": 0}

	var cands: Array = []
	for i in fx_cards.size():
		for j in range(i + 1, fx_cards.size()):
			var info := _pair_info(fx_cards[i], fx_cards[j])
			if info.is_empty():
				continue
			cands.append(info)
	## 风险排序：同相位序 + 共享状态维度优先，最多算 MAX_PAIRS 对
	cands.sort_custom(func(x, y): return int(x["score"]) > int(y["score"]))
	if cands.size() > MAX_PAIRS:
		cands = cands.slice(0, MAX_PAIRS)

	var pairs: Array = []
	var blocked := 0
	var verified := 0
	var unverified := 0
	var pending := 0
	var memo_pair := {}
	for c in cands:
		if not _prime_group([c["a"], c["b"]], level_index, samples, memo_pair):
			## 算不了：这对标 unverified（绝不当作 clean）
			unverified += 1
			pairs.append({"a": c["a"].id, "b": c["b"].id,
					"shared": c["shared"], "same_phase": c["same_phase"],
					"excess": 0.0, "tag": "unverified"})
			continue
		var ex := _interaction(c["a"], c["b"], level_index, samples, memo_pair)
		var row := {
			"a": c["a"].id, "b": c["b"].id,
			"shared": c["shared"], "same_phase": c["same_phase"],
			"excess": ex,
			"tag": classify(ex),
		}
		if String(row["tag"]) == "block":
			blocked += 1
		elif String(row["tag"]) == "verify":
			verified += 1
		pairs.append(row)

	var tag := "clean"
	if blocked > 0:
		tag = "block"
	elif verified > 0:
		tag = "verify"

	## 三阶 / 四阶：容斥法算 n 阶交互（memo 与配对共享，子集只跑一次）
	var triples: Array = []
	var quads: Array = []
	if include_triples and fx_cards.size() > 2:
		for size in range(3, mini(MAX_GROUP, fx_cards.size()) + 1):
			var cap: int = MAX_TRIPLES if size == 3 else (MAX_QUADS if size == 4 else 2)
			for g in _group_candidates(fx_cards, size, cap, cands):
				var ids: Array = []
				for gc in g:
					ids.append(String(gc.id))
				if not _prime_group(g, level_index, samples, memo_pair):
					unverified += 1
					var skip := {"cards": ids, "size": size, "excess": 0.0,
							"tag": "unverified"}
					if size == 3:
						triples.append(skip)
					else:
						quads.append(skip)
					continue
				var ex := _subset_interaction(g, level_index, samples, memo_pair)
				var row := {"cards": ids, "size": size, "excess": ex,
						"tag": classify_group(ex, size)}
				if String(row["tag"]) == "block":
					blocked += 1
					tag = "block"
				elif String(row["tag"]) == "verify":
					verified += 1
					if tag == "clean":
						tag = "verify"
				if size == 3:
					triples.append(row)
				else:
					quads.append(row)

	## partial：有组没算完 → 整体降级，调用方不得当成 clean
	if unverified > 0 and tag == "clean":
		tag = "partial"
	pending = unverified

	_audit_deadline = 0
	if _scache_dirty:
		_save_scache()

	return {"tag": tag, "dims": dims, "pairs": pairs, "triples": triples,
			"quads": quads,
			"blocked": blocked, "verified": verified,
			"unverified": unverified, "pending": pending}


## 是否应该停止新算（-1 = 不限；0 = 纯查表；>0 = 到点）
static func _over_budget() -> bool:
	if _audit_deadline < 0:
		return false
	if _audit_deadline == 0:
		return true
	return Time.get_ticks_msec() >= _audit_deadline


## 子集评分是否已在内存 memo 或磁盘缓存里（不触发计算）
static func _score_in_cache(memo: Dictionary, cards: Array, level_index: int,
		samples: int) -> bool:
	var ids: Array[String] = []
	for c in cards:
		ids.append(String(c.id))
	ids.sort()
	if memo.has(",".join(ids)):
		return true
	return _scache.has(_deck_key(cards, level_index, samples))



## 交互项 → 判定（阈值逻辑单独抽出来，便于确定性测试）
static func classify(excess: float) -> String:
	return classify_group(excess, 2)


## 三阶交互项 → 判定（阈值更高，三阶噪声更大）
static func classify_triple(excess: float) -> String:
	return classify_group(excess, 3)


## 四阶交互项 → 判定
static func classify_quad(excess: float) -> String:
	return classify_group(excess, 4)


## 组大小 → 判定阈值（阶数越高，噪声越大，阈值越严）
static func classify_group(excess: float, size: int) -> String:
	var hi := SUPER_ADDITIVE
	var lo := VERIFY_FLOOR
	if size == 3:
		hi = TRIPLE_ADDITIVE
		lo = TRIPLE_VERIFY_FLOOR
	elif size >= 4:
		## 阶数越高噪声越大：每多一阶，阈值抬一档
		hi = QUAD_ADDITIVE + float(size - 4) * 3.0
		lo = QUAD_VERIFY_FLOOR + float(size - 4) * 1.0
	if excess >= hi:
		return "block"
	if excess >= lo:
		return "verify"
	return "clean"


## 候选组：牌组里效果卡 ≤6 张时全枚举；更大时只围绕"有配对风险"的卡扩展
static func _group_candidates(fx_cards: Array[StsCard], size: int, cap: int,
		pair_cands: Array) -> Array:
	var pool: Array[StsCard] = fx_cards
	if fx_cards.size() > 6:
		var risky := {}
		for c in pair_cands:
			risky[c["a"].id] = true
			risky[c["b"].id] = true
		pool = []
		for c in fx_cards:
			if risky.has(c.id):
				pool.append(c)
	var out: Array = []
	_combine(pool, size, 0, [], out)
	if out.size() > cap:
		out = out.slice(0, cap)
	return out


static func _combine(pool: Array, size: int, start: int, cur: Array, out: Array) -> void:
	if cur.size() == size:
		out.append(cur.duplicate())
		return
	for i in range(start, pool.size()):
		cur.append(pool[i])
		_combine(pool, size, i + 1, cur, out)
		cur.pop_back()


## 三阶交互（容斥）：I = Σ_{S⊆{a,b,c}} (-1)^(n-|S|) · S(S)
static func _triplet_interaction(tri: Array, level_index: int, samples: int,
		memo: Dictionary) -> float:
	return _subset_interaction(tri, level_index, samples, memo)


## 任意 n 张组的 n 阶交互（容斥，含空集 = 全填充基线）
##   n=2: S(AB) - S(A) - S(B) + S(base)
##   n=3: S(ABC) - S(AB) - S(AC) - S(BC) + S(A) + S(B) + S(C) - S(base)
static func _subset_interaction(group: Array, level_index: int, samples: int,
		memo: Dictionary) -> float:
	var n := group.size()
	var total := 0.0
	for mask in range(0, 1 << n):
		var sub: Array = []
		for i in n:
			if mask & (1 << i) != 0:
				sub.append(group[i])
		var sign := 1.0 if ((n - sub.size()) % 2 == 0) else -1.0
		total += sign * _score_cached(memo, sub, level_index, samples)
	return total


## 预热一个"组"：逐个把它的子集评分算进缓存，每算一个就检查预算。
## 预算粒度必须是「单次子集评分」（约 20–60ms），不能是「整个组」（可达 300ms+），
## 否则 200ms 预算会被一个三元组一口气吃掉 460ms（实测踩过）。
## 返回 true = 这一组算完整了；false = 中途没预算，整组作废（下次重来）。
static func _prime_group(group: Array, level_index: int, samples: int,
		memo: Dictionary) -> bool:
	var n := group.size()
	for mask in range(0, 1 << n):
		var sub: Array = []
		for i in n:
			if mask & (1 << i) != 0:
				sub.append(group[i])
		if not _score_in_cache(memo, sub, level_index, samples) and _over_budget():
			return false
		_score_cached(memo, sub, level_index, samples)
	return true


## 带记忆的牌组评分：同一次审计里每种子集只跑一次；跨会话走磁盘缓存。
static func _score_cached(memo: Dictionary, cards: Array, level_index: int,
		samples: int) -> float:
	var ids: Array[String] = []
	for c in cards:
		ids.append(String(c.id))
	ids.sort()
	var key := ",".join(ids)
	if memo.has(key):
		return float(memo[key])
	## 磁盘键必须包含"卡的实质"而非仅 id：同名卡换了程序/数值要重算，
	## 不同名但程序数值全同的卡（filler、复制品）应该命中同一条。
	var dkey := _deck_key(cards, level_index, samples)
	if _scache.has(dkey):
		var cached := float(_scache[dkey])
		memo[key] = cached
		return cached
	var s := _score(_deck_with(cards, level_index), level_index, samples)
	memo[key] = s
	_scache[dkey] = s
	_scache_dirty = true
	return s


## 磁盘缓存键：只依赖"参与评分的那几张卡 + 擂台参数 + 采样数"。
## 用 JSON 排序后哈希——牌组顺序不影响评分，顺序不该影响键。
static func _deck_key(cards: Array, level_index: int, samples: int) -> String:
	var sig: Array = []
	for c in cards:
		sig.append(_card_sig(c))
	sig.sort()
	var payload := {
		"v": COMBO_CACHE_VERSION,
		"lv": level_index,
		"n": samples,
		"hp": COMBO_HP,
		"size": REF_DECK_SIZE,
		"filler": FILLER_DAMAGE,
		"cards": sig,
	}
	return JSON.stringify(payload).sha256_text()


## 一张卡的实质签名：程序 AST + 影响战斗的数值。不含 art/id/cost——
## cost 只影响能量，而审计擂台不打这张卡的实际费用（统一按 cost 1 铺进去）。
static func _card_sig(c: StsCard) -> String:
	return JSON.stringify({
		"k": c.kind, "d": c.damage, "b": c.block, "dr": c.draw,
		"fx": c.effects, "dsl": c.dsl_version,
	})


static func clear_scache() -> void:
	_scache.clear()
	_scache_loaded = true
	_save_scache()


static func scache_size() -> int:
	_load_scache()
	return _scache.size()


static func _load_scache() -> void:
	if _scache_loaded:
		return
	_scache_loaded = true
	if not FileAccess.file_exists(COMBO_CACHE_PATH):
		return
	var f := FileAccess.open(COMBO_CACHE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_scache = parsed


static func _save_scache() -> void:
	var f := FileAccess.open(COMBO_CACHE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_scache))
	_scache_dirty = false


## 静态配对：共享可累积维度才算候选
static func _pair_info(a: StsCard, b: StsCard) -> Dictionary:
	var wa := EffectDSL.writeset(a.effects)
	var wb := EffectDSL.writeset(b.effects)
	var shared: Array[String] = []
	for k in wa.keys():
		if wb.has(k) and String(k).contains("status"):
			shared.append(String(k))
	if not shared.is_empty():
		var pa := _triggers(a.effects)
		var pb := _triggers(b.effects)
		var same_phase := false
		for t in pa:
			if pb.has(t):
				same_phase = true
		return {"a": a, "b": b, "shared": shared, "same_phase": same_phase,
				"score": 2 if same_phase else 1}
	## 成长型伤害也构成候选（乘性叠乘不靠状态）
	if _has_op(a.effects, "damage_scaled") or _has_op(b.effects, "damage_scaled"):
		return {"a": a, "b": b, "shared": shared, "same_phase": false, "score": 1}
	## 直伤 × 易伤：写维度不相交，但一个改写另一个的产出速率——静态看不出来，
	## 正是圆桌说的"跨维度涌现"，必须进差分
	var a_dmg := _has_op(a.effects, "damage") or _has_op(a.effects, "damage_scaled")
	var b_dmg := _has_op(b.effects, "damage") or _has_op(b.effects, "damage_scaled")
	if (a_dmg and _applies(b.effects, "vulnerable")) \
			or (b_dmg and _applies(a.effects, "vulnerable")):
		return {"a": a, "b": b, "shared": ["enemy_hp×vulnerable"],
				"same_phase": true, "score": 2}
	return {}


static func _applies(clauses: Array, status: String) -> bool:
	for c in clauses:
		for op in c.get("then", []):
			if String(op.get("do", "")) == "apply_status" \
					and String(op.get("status", "")) == status:
				return true
	return false


## 交互项：固定牌组规模下的超加性（走缓存，热路径零成本）
static func _interaction(a: StsCard, b: StsCard, level_index: int, samples: int,
		memo: Dictionary = {}) -> float:
	var base := _score_cached(memo, [], level_index, samples)
	var sa := _score_cached(memo, [a], level_index, samples)
	var sb := _score_cached(memo, [b], level_index, samples)
	var sab := _score_cached(memo, [a, b], level_index, samples)
	return sab - sa - sb + base


## 固定规模参考牌组：起始牌组 + vanilla 填充到 REF_DECK_SIZE
static func _deck_with(cards: Array, level_index: int) -> Array[StsCard]:
	var deck: Array[StsCard] = StsCardPool.starter_deck()
	for c in cards:
		deck.append(c)
	var filler_i := 0
	while deck.size() < REF_DECK_SIZE:
		var f := StsCard.make("filler_%d" % filler_i, StsCard.Kind.ATTACK, 1,
				FILLER_DAMAGE, 0, "")
		deck.append(f)
		filler_i += 1
	return deck


## 牌组强度标量：平均伤害 + 胜率修正 - 回合修正（组合擂台单独标定）
static func _score(deck: Array[StsCard], level_index: int, samples: int) -> float:
	var r := EffectPricing._run_deck(deck, level_index, samples, COMBO_HP)
	return float(r["avg_damage"]) + float(r["win_rate"]) * 30.0 - float(r["avg_turns"]) * 2.0


static func _triggers(clauses: Array) -> Dictionary:
	var t := {}
	for c in clauses:
		t[String(c.get("when", ""))] = true
	return t


static func _has_op(clauses: Array, op_name: String) -> bool:
	for c in clauses:
		for op in c.get("then", []):
			if String(op.get("do", "")) == op_name:
				return true
	return false
