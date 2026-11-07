class_name LLMEventEngine
extends RefCounted
## AI 事件引擎（方案二「AI 即事件引擎」机械层）。
##
## 分工红线（圆桌终案）：
##   · LLM 只在本地预筛出的「特赦名单」里 pick 一个槽位，并写 ≤20 字叙事；
##   · 槽位 ID 是唯一协议真值，池外词 / 非法 pick 一律静默落本地默认候选；
##   · **所有数字在本地掷**（run.rng），LLM 永远不接触数值管线。
##
## 预算与保护：
##   每局 ≤2 次、同模板每局 ≤1 次、单事件净值钳 [−8,+6]、单局累计 ≥−10、
##   HP < 50% 才把 DAMAGE/CURSE 放进候选池、L1-2 无负面事件。
##
## 跨文件状态：RunState 不在本任务授权改动范围内，引擎计数/标记统一挂在
## run 的 Object metadata 上（键见下方 META_*），并随 run_seed 自动换局清零。
##
## 下游接线契约：
##   · CHAIN_HEAD → run.get_meta("llm_event_chain_head") 场次数，战斗开始时
##     由 arena 侧给 StsCombat.seq_streak 预置 1 阶后清零；
##   · MODIFY「可复读」→ 目标牌 set_meta("llm_repeat", 1)，play_card 侧读到
##     后按复读处理并清标记（若战斗侧未接，则该模式只留标记，不产生数值）。

const SCENE_TAG := "event"

const META_RUN_SEED := &"llm_event_run_seed"
const META_COUNT := &"llm_event_count"
const META_TOTAL_NET := &"llm_event_total_net"
const META_USED := &"llm_event_used_slots"
const META_CHAIN_HEAD := &"llm_event_chain_head"
const META_LAST := &"llm_event_last"

const CANDIDATE_MIN := 2
const CANDIDATE_MAX := 3

## GAIN_CARD 随机池：只放通用基础卡（与现有事件 card_random 同档），
## 排除 ChatPPT 专属（cp_*）、白米饭（RICE 槽位自有身份）与觉醒专属（cannon/rage）。
const GAIN_POOL := ["fish_ram", "taunt", "loop", "parallel"]

const SYSTEM_PROMPT := "你是《代码擂台》的 AI 事件引擎。槽位词表是唯一真值，禁止输出池外词，禁止输出任何数值。只能从给定候选池中选一个，只输出一行 JSON，形如 {\"pick\":1,\"reason\":\"不超过20字的AI圈自嘲\"}，不要解释。"


static func scene_tag() -> String:
	return SCENE_TAG


# ── 预算 / 状态读取 ───────────────────────────────────

static func event_count(run: RunState) -> int:
	if run == null:
		return 0
	_ensure_scope(run)
	return int(run.get_meta(META_COUNT, 0))


static func total_net(run: RunState) -> int:
	if run == null:
		return 0
	_ensure_scope(run)
	return int(run.get_meta(META_TOTAL_NET, 0))


static func budget_left(run: RunState) -> int:
	return maxi(0, LLMEventSlots.MAX_EVENTS_PER_RUN - event_count(run))


static func used_slots(run: RunState) -> Array:
	if run == null:
		return []
	_ensure_scope(run)
	var used: Array = run.get_meta(META_USED, [])
	return used.duplicate()


static func chain_head_pending(run: RunState) -> int:
	if run == null:
		return 0
	_ensure_scope(run)
	return int(run.get_meta(META_CHAIN_HEAD, 0))


## 本局是否还能再触发 AI 事件（预算 + 至少 1 个合法槽位）。
static func can_trigger(run: RunState) -> bool:
	if run == null:
		return false
	_ensure_scope(run)
	if int(run.get_meta(META_COUNT, 0)) >= LLMEventSlots.MAX_EVENTS_PER_RUN:
		return false
	return not _eligible_slots(run).is_empty()


# ── 预筛：本地特赦名单 ────────────────────────────────

## 预筛 2~3 个合法候选（池序 1 即本地默认候选）。
## 返回空数组 = 本局不能再走 AI 事件，调用方回退原 5 则热梗事件。
static func build_candidates(run: RunState, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if run == null:
		return out
	_ensure_scope(run)
	if int(run.get_meta(META_COUNT, 0)) >= LLMEventSlots.MAX_EVENTS_PER_RUN:
		return out
	var pool := _eligible_slots(run)
	if pool.is_empty():
		return out
	var r := rng if rng != null else _local_rng()
	_shuffle(pool, r)
	var want := mini(CANDIDATE_MAX, pool.size())
	if want < CANDIDATE_MIN:
		want = pool.size()
	for i in want:
		out.append(_make_candidate(int(pool[i]), i + 1, run))
	return out


## 单个槽位现在能不能落地（预算 / 同模板 / HP 门槛 / L1-2 / 单局净值下限）。
static func can_apply(run: RunState, slot_ref: Variant) -> bool:
	if run == null:
		return false
	_ensure_scope(run)
	var slot := LLMEventSlots.slot_of(slot_ref)
	if slot < 0:
		return false
	if int(run.get_meta(META_COUNT, 0)) >= LLMEventSlots.MAX_EVENTS_PER_RUN:
		return false
	var used: Array = run.get_meta(META_USED, [])
	if used.has(LLMEventSlots.id_of(slot)):
		return false
	if LLMEventSlots.is_negative(slot):
		if _is_early_game(run):
			return false
		if not _is_low_hp(run):
			return false
		if not LLMEventSlots.fits_run_floor(int(run.get_meta(META_TOTAL_NET, 0)), slot):
			return false
	return true


## 本地兜底：预筛序 1。空池返回 {}。
static func pick_default(candidates: Array) -> Dictionary:
	if candidates == null or candidates.is_empty():
		return {}
	var first: Dictionary = candidates[0]
	return first.duplicate(true)


## LLM 的 pick 是 1 基序号；越界/非整数一律视为无效，返回 {}。
static func pick_candidate(candidates: Array, pick: int) -> Dictionary:
	if candidates == null or pick < 1 or pick > candidates.size():
		return {}
	var c: Dictionary = candidates[pick - 1]
	return c.duplicate(true)


## 一步到位：pick 无效 → 默认候选；池空 → ok=false。
static func apply_pick(run: RunState, candidates: Array, pick: int) -> Dictionary:
	var c := pick_candidate(candidates, pick)
	if c.is_empty():
		c = pick_default(candidates)
	if c.is_empty():
		return {"ok": false, "error": "no_candidate", "scene_tag": SCENE_TAG}
	return apply_slot(run, c)


# ── 应用：本地掷数值并写 run ──────────────────────────

## 应用恰好 1 个槽位。slot_ref 可以是枚举 int / 机械 ID / 候选字典。
## 返回结果字典带 ok/id/name/rolled/net/detail/text/count/total_net/budget_left。
static func apply_slot(run: RunState, slot_ref: Variant) -> Dictionary:
	if run == null:
		return {"ok": false, "error": "no_run", "scene_tag": SCENE_TAG}
	_ensure_scope(run)
	var slot := LLMEventSlots.slot_of(slot_ref)
	if slot < 0:
		return {"ok": false, "error": "invalid_slot", "scene_tag": SCENE_TAG}
	if not can_apply(run, slot):
		return {"ok": false, "error": "slot_ineligible", "scene_tag": SCENE_TAG}

	var rng := run.rng if run.rng != null else _local_rng()
	var res := _apply_effect(run, slot, rng)
	if not bool(res.get("ok", false)):
		return res

	var raw_net := int(res.get("net", 0))
	var net := LLMEventSlots.clamp_net(raw_net)
	res["net"] = net
	res["clamped"] = net != raw_net

	var count := int(run.get_meta(META_COUNT, 0)) + 1
	var total := int(run.get_meta(META_TOTAL_NET, 0)) + net
	run.set_meta(META_COUNT, count)
	run.set_meta(META_TOTAL_NET, total)
	var used: Array = run.get_meta(META_USED, [])
	used.append(LLMEventSlots.id_of(slot))
	run.set_meta(META_USED, used)

	res["slot"] = slot
	res["id"] = LLMEventSlots.id_of(slot)
	res["name"] = LLMEventSlots.narrative_name(slot)
	res["count"] = count
	res["total_net"] = total
	res["budget_left"] = maxi(0, LLMEventSlots.MAX_EVENTS_PER_RUN - count)
	res["scene_tag"] = SCENE_TAG
	res["text"] = "%s · %s" % [res["name"], String(res.get("detail", ""))]
	run.set_meta(META_LAST, res.duplicate(true))
	return res


## 换局清账（main.gd 的 run.reset_run 之后由接线方调用；引擎也会按 run_seed 自动清）。
static func reset_run(run: RunState) -> void:
	if run == null:
		return
	run.set_meta(META_RUN_SEED, run.run_seed)
	run.set_meta(META_COUNT, 0)
	run.set_meta(META_TOTAL_NET, 0)
	run.set_meta(META_USED, [])
	run.set_meta(META_CHAIN_HEAD, 0)
	run.set_meta(META_LAST, {})


# ── prompt 组装（自足兜底；LLMPrompts 的事件 v2 若可用，优先用那份） ──

## 返回 OpenAI 兼容 messages；候选带 1 基序号，LLM 只需回 {"pick":N,"reason":"…"}。
static func build_messages(run: RunState, candidates: Array) -> Array[Dictionary]:
	var lines: Array[String] = []
	lines.append("局面：HP %d/%d，第 %d 章，已通关 %d 关；本局 AI 事件 %d/%d，累计净值 %+d。"
			% [run.hp, RunState.MAX_HP, run.chapter, run.level_index,
			event_count(run), LLMEventSlots.MAX_EVENTS_PER_RUN, total_net(run)])
	lines.append("候选池（只能选一个，序号从 1 开始）：")
	for i in candidates.size():
		var c: Dictionary = candidates[i]
		lines.append("%d. %s" % [i + 1, String(c.get("summary", ""))])
	lines.append("只输出一行 JSON：{\"pick\":N,\"reason\":\"≤20字\"}")

	var msgs: Array[Dictionary] = []
	msgs.append({"role": "system", "content": SYSTEM_PROMPT})
	msgs.append({"role": "user", "content": "\n".join(lines)})
	return msgs


# ── 内部 ─────────────────────────────────────────────

static func _ensure_scope(run: RunState) -> void:
	## 注意：Godot 的 get_meta(key, null) 仍会打错误日志，先 has_meta 再取。
	if not run.has_meta(META_RUN_SEED) or int(run.get_meta(META_RUN_SEED)) != run.run_seed:
		reset_run(run)


static func _is_low_hp(run: RunState) -> bool:
	return float(run.hp) < float(RunState.MAX_HP) * LLMEventSlots.NEGATIVE_HP_RATIO


static func _is_early_game(run: RunState) -> bool:
	## L1-2：第 1 章且尚未通关 2 关（level_index 0/1 即正在 L1/L2）。
	return run.chapter <= 1 and run.level_index <= 1


static func _eligible_slots(run: RunState) -> Array[int]:
	var out: Array[int] = []
	var used: Array = run.get_meta(META_USED, [])
	var net_now := int(run.get_meta(META_TOTAL_NET, 0))
	for raw in LLMEventSlots.SLOT_ORDER:
		var slot := int(raw)
		if used.has(LLMEventSlots.id_of(slot)):
			continue
		if LLMEventSlots.is_negative(slot):
			if _is_early_game(run):
				continue
			if not _is_low_hp(run):
				continue
			if not LLMEventSlots.fits_run_floor(net_now, slot):
				continue
		out.append(slot)
	return out


static func _make_candidate(slot: int, index: int, run: RunState) -> Dictionary:
	return {
		"index": index,
		"slot": slot,
		"id": LLMEventSlots.id_of(slot),
		"name": LLMEventSlots.narrative_name(slot),
		"negative": LLMEventSlots.is_negative(slot),
		"net_min": LLMEventSlots.min_net(slot),
		"net_max": LLMEventSlots.max_net(slot),
		"summary": LLMEventSlots.candidate_text(slot),
		"hp": run.hp,
	}


static func _apply_effect(run: RunState, slot: int, rng: RandomNumberGenerator) -> Dictionary:
	match slot:
		LLMEventSlots.Slot.DRAW:
			var n := rng.randi_range(LLMEventSlots.DRAW_MIN, LLMEventSlots.DRAW_MAX)
			run.next_hand_bonus += n
			return _ok(slot, n, n, "下场合抽牌 +%d（累计 +%d）"
					% [n, run.next_hand_bonus])
		LLMEventSlots.Slot.DAMAGE:
			var n := rng.randi_range(LLMEventSlots.DAMAGE_MIN, LLMEventSlots.DAMAGE_MAX)
			var before := run.hp
			run.hp = maxi(1, run.hp - n)
			return _ok(slot, n, -n, "Token −%d（%d→%d）" % [before - run.hp, before, run.hp])
		LLMEventSlots.Slot.MODIFY:
			return _apply_modify(run, rng)
		LLMEventSlots.Slot.RICE:
			run.add_card("rice")
			return _ok(slot, LLMEventSlots.RICE_BOWLS, LLMEventSlots.RICE_BOWLS,
					"白米饭 +%d 碗（牌库 %d 张）" % [LLMEventSlots.RICE_BOWLS, run.deck.size()])
		LLMEventSlots.Slot.HEAL:
			var n := rng.randi_range(LLMEventSlots.HEAL_MIN, LLMEventSlots.HEAL_MAX)
			var before := run.hp
			run.hp = mini(RunState.MAX_HP, run.hp + n)
			return _ok(slot, n, n, "Token +%d（%d→%d）" % [run.hp - before, before, run.hp])
		LLMEventSlots.Slot.GAIN_CARD:
			var card_id: String = GAIN_POOL[rng.randi_range(0, GAIN_POOL.size() - 1)]
			run.add_card(card_id)
			var r := _ok(slot, 1, 2, "随机卡牌 +1：%s（牌库 %d 张）"
					% [StsCardPool.card_name(card_id), run.deck.size()])
			r["card_id"] = card_id
			return r
		LLMEventSlots.Slot.CHAIN_HEAD:
			var cur := int(run.get_meta(META_CHAIN_HEAD, 0))
			var next := mini(LLMEventSlots.MAX_EVENTS_PER_RUN, cur + LLMEventSlots.CHAIN_HEAD_TIERS)
			run.set_meta(META_CHAIN_HEAD, next)
			return _ok(slot, LLMEventSlots.CHAIN_HEAD_TIERS, LLMEventSlots.CHAIN_HEAD_TIERS,
					"下一场初始连段 +%d 阶（累计 %d）" % [LLMEventSlots.CHAIN_HEAD_TIERS, next])
		LLMEventSlots.Slot.CURSE:
			run.deck.append(LLMEventSlots.make_curse_card())
			var r2 := _ok(slot, 1, LLMEventSlots.NET_RANGES[slot].x,
					"牌库 +1「%s」（可弃换抽 %d）"
					% [LLMEventSlots.CURSE_CARD_ID, LLMEventSlots.CURSE_DISCARD_DRAW])
			r2["card_id"] = LLMEventSlots.CURSE_CARD_ID
			return r2
	return {"ok": false, "error": "unhandled_slot", "slot": slot, "scene_tag": SCENE_TAG}


## MODIFY：本地三选一（+1 攻 / +1 发育 / 可复读），随机挑一张合法目标牌。
static func _apply_modify(run: RunState, rng: RandomNumberGenerator) -> Dictionary:
	var modes: Array = LLMEventSlots.MODIFY_MODES.duplicate()
	_shuffle(modes, rng)
	for raw in modes:
		var mode := String(raw)
		var target := _pick_modify_target(run, mode, rng)
		if target == null:
			continue
		var label := StsCardPool.card_name(target.id)
		if label == "":
			label = target.id
		if mode == "atk":
			var before := target.damage
			target.damage += LLMEventSlots.MODIFY_STEP
			return _ok(LLMEventSlots.Slot.MODIFY, LLMEventSlots.MODIFY_STEP,
					LLMEventSlots.MODIFY_STEP,
					"「%s」攻击 +%d（%d→%d）"
					% [label, LLMEventSlots.MODIFY_STEP, before, target.damage])
		if mode == "grow":
			var before := target.block
			target.block += LLMEventSlots.MODIFY_STEP
			return _ok(LLMEventSlots.Slot.MODIFY, LLMEventSlots.MODIFY_STEP,
					LLMEventSlots.MODIFY_STEP,
					"「%s」护盾 +%d（%d→%d）"
					% [label, LLMEventSlots.MODIFY_STEP, before, target.block])
		target.set_meta(&"llm_repeat", 1)
		var r := _ok(LLMEventSlots.Slot.MODIFY, LLMEventSlots.MODIFY_STEP,
				LLMEventSlots.MODIFY_STEP,
				"「%s」获得复读标记（战斗侧读取 llm_repeat）" % label)
		r["card_id"] = target.id
		return r
	return _ok(LLMEventSlots.Slot.MODIFY, 0, 0, "没有可改造的牌（空过）")


static func _pick_modify_target(run: RunState, mode: String, rng: RandomNumberGenerator) -> StsCard:
	var pool: Array[StsCard] = []
	for c in run.deck:
		if c == null:
			continue
		if mode == "atk" and c.kind == StsCard.Kind.ATTACK:
			pool.append(c)
		elif mode == "grow" and c.kind == StsCard.Kind.SKILL and c.block > 0:
			pool.append(c)
		elif mode == "repeat" and (c.kind == StsCard.Kind.ATTACK or c.block > 0):
			pool.append(c)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _ok(slot: int, rolled: int, net: int, detail: String) -> Dictionary:
	return {
		"ok": true,
		"slot": slot,
		"id": LLMEventSlots.id_of(slot),
		"name": LLMEventSlots.narrative_name(slot),
		"rolled": rolled,
		"net": net,
		"detail": detail,
		"scene_tag": SCENE_TAG,
	}


static func _local_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
