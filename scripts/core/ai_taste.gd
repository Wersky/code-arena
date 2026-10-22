class_name AiTaste
extends RefCounted
## 顺序层：把一条命令行（参数片段数组）按规则表评分。
## 纯静态函数，不持有状态，可被单元测试直接调用。
##
## 规则表 = 23 条通用顺序规则（str_ 前缀，所有 AI 娘共享）+ 16 条口味规则（tas_ 前缀，
## 仅当规则 id 出现在 AiData.taste_rules 中才参与判定）。

## 参数名常量
const ARG_ROLE := "--role"
const ARG_TASK := "--task"
const ARG_KNOWLEDGE := "--knowledge"
const ARG_FORMAT := "--format"
const ARG_EXAMPLE := "--example"
const ARG_CONSTRAINT := "--constraint"

## 参数名 → 类型序号（判定逆序用；与 CardData.KIND_ORDER 一致）
const KIND_INDEX := {
	"--role": 0,
	"--task": 1,
	"--knowledge": 2,
	"--format": 3,
	"--example": 4,
	"--constraint": 5,
}

## 命令行总字符数的"精简"阈值
const COMPACT_MAX_CHARS := 80
## 命令行总字符数的"冗长"阈值
const VERBOSE_MIN_CHARS := 120

## 口味倍率上限
const TASTE_MULT_MAX := 1.20
## 顺序层倍率下限
const ORDER_MULT_MIN := 0.50

## 片段数 → 通用加分（str_len_2 ~ str_len_6）
const LEN_FLAT := {2: 10, 3: 14, 4: 18, 5: 22, 6: 26}

## 道具顺序层效果表（**不属于 39 条规则表**，scope = "item"）
## 持有对应道具时生效：倍率叠加在**规则层倍率之上**（规则层仍钳制 [0.50, 1.20]）。
## 键 = AiItemData.effect_id；每种 effect_id 只算一次（叠层道具不重复乘）。
## id / scope / mult / flat 见契约 C.3.1 与 E.3。
const ITEM_MULT_EFFECTS := {
	"knowledge_mult": {
		"id": "itm_gemigo_knowledge",
		"name": "多模态素材加成",
		"scope": "item",
		"mult": 1.08,
		"flat": 0,
		"flag": "--knowledge",
	},
}

## 中文判定用的码点区间（CJK 统一表意文字）
const CJK_MIN := 0x4E00
const CJK_MAX := 0x9FFF

## DeepDeek 推理词
const REASONING_WORDS := ["为什么", "解释", "原因", "步骤"]
## ChatPPT 结构化关键词（英文小写匹配）
const STRUCTURED_WORDS := ["json", "xml", "sql", "yaml", "markdown", "表格", "步骤"]
## Grock 时效词
const LIVE_WORDS := ["最新", "实时", "搜", "公告", "当前", "近期"]

static var _regex: RegEx = null


## 主入口：对一条命令行评分。
## parts      = 参数片段数组，每项形如 `--role "资深工程师"`（含引号）
## ai         = 当前核心 AI 娘（null 时只跑通用顺序规则，不跑口味规则）
## 返回 {score:int, mult:float, combos:Array[String], notes:Array[String]}
static func evaluate(parts: Array[String], ai: AiData) -> Dictionary:
	var combos: Array[String] = []
	var notes: Array[String] = []
	if parts.is_empty():
		combos.append("str_empty")
		notes.append("命令行是空的——我什么都没收到。")
		return {"score": 0, "mult": 1.0, "combos": combos, "notes": notes}

	var parsed := parse(parts)
	var inv := inversions(parsed)
	var n := parts.size()

	# ── 解析出的结构信息 ────────────────────────────────
	var counts := {}          # arg -> 出现次数
	var first_pos := {}       # arg -> 首次出现的位置
	var distinct := 0
	for p in parsed:
		var a := str(p.get("arg", ""))
		if a == "":
			continue
		if not counts.has(a):
			first_pos[a] = int(p.get("pos", 0))
			distinct += 1
		counts[a] = int(counts.get(a, 0)) + 1

	var head_arg := str(parsed[0].get("arg", ""))
	var tail_arg := str(parsed[n - 1].get("arg", ""))

	var hits := {}            # 规则 id -> true
	var flat_override := {}   # 规则 id -> int（按次数累计的规则用）

	# ── 通用顺序规则（str_）────────────────────────────
	# 片段数（互斥，只命中与当前片段数相等的那一条）
	if LEN_FLAT.has(n):
		hits["str_len_%d" % n] = true

	# 逆序分层（互斥）
	if inv == 0 and n >= 3:
		hits["str_clean"] = true
	elif inv == 1:
		hits["str_one_swap"] = true
	elif inv == 2:
		hits["str_messy"] = true
	elif inv >= 3:
		hits["str_scramble"] = true

	# 角色开篇 / 角色缺位（互斥）
	if head_arg == ARG_ROLE:
		hits["str_role_head"] = true
	elif n >= 3:
		hits["str_no_role_head"] = true

	# 任务居中 / 任务错位（互斥）
	if counts.has(ARG_TASK):
		var task_pos := int(first_pos[ARG_TASK])
		var anchor := true
		if counts.has(ARG_ROLE) and task_pos <= int(first_pos[ARG_ROLE]):
			anchor = false
		if counts.has(ARG_FORMAT) and task_pos >= int(first_pos[ARG_FORMAT]):
			anchor = false
		if anchor:
			hits["str_task_anchor"] = true
		else:
			hits["str_task_misplaced"] = true

	# 格式先于范例
	if counts.has(ARG_FORMAT) and counts.has(ARG_EXAMPLE):
		if int(first_pos[ARG_FORMAT]) < int(first_pos[ARG_EXAMPLE]):
			hits["str_format_before_example"] = true

	# 约束收尾 / 约束未收尾（互斥）
	if counts.has(ARG_CONSTRAINT):
		if tail_arg == ARG_CONSTRAINT:
			hits["str_constraint_tail"] = true
		else:
			hits["str_constraint_broken"] = true

	# 广谱链
	if distinct >= 5:
		hits["str_wide_chain"] = true

	# 参数重复（flat 按重复次数累计，下限 −30）
	var dup_total := 0
	for a in counts:
		dup_total += maxi(0, int(counts[a]) - 1)
	if dup_total >= 1:
		hits["str_dup_flag"] = true
		flat_override["str_dup_flag"] = maxi(-30, -14 - 8 * (dup_total - 1))

	# 任务素材相邻
	if counts.has(ARG_TASK) and counts.has(ARG_KNOWLEDGE):
		if absi(int(first_pos[ARG_TASK]) - int(first_pos[ARG_KNOWLEDGE])) == 1:
			hits["str_adjacent_task_knowledge"] = true

	# 结构断裂（相邻两片段类型序号差 ≥ 3，每处 −6，下限 −18）
	var gaps := 0
	for i in range(n - 1):
		var ka := int(parsed[i].get("kind_index", -1))
		var kb := int(parsed[i + 1].get("kind_index", -1))
		if ka < 0 or kb < 0:
			continue
		if absi(ka - kb) >= 3:
			gaps += 1
	if gaps > 0:
		hits["str_gap"] = true
		flat_override["str_gap"] = maxi(-18, -6 * gaps)

	# 精简 / 冗长
	var prefix := ""
	if ai != null:
		prefix = ai.id
	var cmd_len := command_length(prefix, parts)
	if cmd_len <= COMPACT_MAX_CHARS:
		hits["str_compact"] = true
	if cmd_len > VERBOSE_MIN_CHARS:
		hits["str_verbose"] = true

	# ── 口味规则（tas_）───────────────────────────────
	if ai != null:
		var values: Array[String] = []
		for p in parsed:
			values.append(str(p.get("value", "")))
		var cjk_count := 0
		for v in values:
			if _has_cjk(v):
				cjk_count += 1

		for rule_id in ai.taste_rules:
			match rule_id:
				"tas_dd_grounded":
					if counts.has(ARG_KNOWLEDGE):
						hits[rule_id] = true
				"tas_dd_constraint_tail":
					if counts.has(ARG_CONSTRAINT) and tail_arg == ARG_CONSTRAINT:
						hits[rule_id] = true
				"tas_dd_reasoning":
					for v in values:
						if _contains_any(v, REASONING_WORDS):
							hits[rule_id] = true
							break
				"tas_dd_strict":
					if counts.has(ARG_KNOWLEDGE) and counts.has(ARG_CONSTRAINT):
						hits[rule_id] = true
				"tas_kw_cjk":
					if cjk_count >= 2:
						hits[rule_id] = true
				"tas_kw_long":
					if n >= 5:
						hits[rule_id] = true
				"tas_kw_example_pair":
					if counts.has(ARG_EXAMPLE) and counts.has(ARG_TASK):
						if int(first_pos[ARG_EXAMPLE]) > int(first_pos[ARG_TASK]):
							hits[rule_id] = true
				"tas_kw_fluent":
					if cjk_count >= 3 and n >= 4:
						hits[rule_id] = true
				"tas_cp_no_example":
					if not counts.has(ARG_EXAMPLE):
						hits[rule_id] = true
				"tas_cp_structured":
					for v in values:
						if _contains_any(v.to_lower(), STRUCTURED_WORDS):
							hits[rule_id] = true
							break
				"tas_cp_format":
					if counts.has(ARG_FORMAT):
						hits[rule_id] = true
				"tas_cp_neat":
					if counts.has(ARG_FORMAT) and not counts.has(ARG_EXAMPLE):
						hits[rule_id] = true
				"tas_gr_live":
					for v in values:
						if _contains_any(v, LIVE_WORDS):
							hits[rule_id] = true
							break
				"tas_gr_anchor":
					if counts.has(ARG_KNOWLEDGE) and counts.has(ARG_TASK):
						if absi(int(first_pos[ARG_KNOWLEDGE]) - int(first_pos[ARG_TASK])) == 1:
							hits[rule_id] = true
				"tas_gr_evidence_pair":
					if counts.has(ARG_KNOWLEDGE) and counts.has(ARG_EXAMPLE):
						hits[rule_id] = true
				"tas_gr_fresh":
					if counts.has(ARG_KNOWLEDGE) and n >= 3:
						hits[rule_id] = true

	# ── 汇总（按 rule_table 顺序）──────────────────────
	var score := 0
	var mult := 1.0
	for rule in rule_table():
		var rid := str(rule["id"])
		if not hits.has(rid):
			continue
		var f := int(flat_override.get(rid, int(rule["flat"])))
		var m := float(rule["mult"])
		score += f
		mult *= m
		combos.append(rid)
		notes.append(_note(rid, f, m, ai))

	mult = clampf(mult, ORDER_MULT_MIN, TASTE_MULT_MAX)
	return {"score": score, "mult": mult, "combos": combos, "notes": notes}


## 把片段数组解析成结构化列表。
## 返回 [{arg:String, value:String, kind_index:int, pos:int}, ...]
static func parse(parts: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var re := _get_regex()
	for i in parts.size():
		var raw := parts[i]
		var m := re.search(raw)
		if m == null:
			out.append({"arg": "", "value": raw, "kind_index": -1, "pos": i})
			continue
		var arg := m.get_string(1)
		var value := m.get_string(2).replace("\\\"", "\"").replace("\\\\", "\\")
		out.append({
			"arg": arg,
			"value": value,
			"kind_index": int(KIND_INDEX.get(arg, -1)),
			"pos": i,
		})
	return out


## 逆序对数量
static func inversions(parsed: Array[Dictionary]) -> int:
	var seq: Array[int] = []
	for p in parsed:
		var k := int(p.get("kind_index", -1))
		if k >= 0:
			seq.append(k)
	var inv := 0
	for i in seq.size():
		for j in range(i + 1, seq.size()):
			if seq[i] > seq[j]:
				inv += 1
	return inv


## 全量规则表（23 条通用 + 16 条口味 = 39 条），按 C.2/C.3 的顺序
## 返回 [{id:String, name:String, scope:String, mult:float, flat:int}, ...]
## scope 取值："universal" | "taste"
static func rule_table() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# ── 通用顺序规则（23 条）─────────────────────────────
	out.append(_rule("str_empty", "空命令行", "universal", 1.00, 0))
	out.append(_rule("str_len_2", "双要素", "universal", 1.00, 10))
	out.append(_rule("str_len_3", "三要素", "universal", 1.00, 14))
	out.append(_rule("str_len_4", "四要素", "universal", 1.00, 18))
	out.append(_rule("str_len_5", "五要素", "universal", 1.00, 22))
	out.append(_rule("str_len_6", "完整六段", "universal", 1.00, 26))
	out.append(_rule("str_clean", "标准序", "universal", 1.05, 15))
	out.append(_rule("str_one_swap", "一处错位", "universal", 1.00, 5))
	out.append(_rule("str_messy", "两处错位", "universal", 0.95, -12))
	out.append(_rule("str_scramble", "三处错位", "universal", 0.88, -28))
	out.append(_rule("str_role_head", "角色开篇", "universal", 1.00, 8))
	out.append(_rule("str_no_role_head", "角色缺位", "universal", 0.93, -16))
	out.append(_rule("str_task_anchor", "任务居中", "universal", 1.00, 8))
	out.append(_rule("str_task_misplaced", "任务错位", "universal", 1.00, -10))
	out.append(_rule("str_format_before_example", "格式先于范例", "universal", 1.00, 6))
	out.append(_rule("str_constraint_tail", "约束收尾", "universal", 1.00, 8))
	out.append(_rule("str_constraint_broken", "约束未收尾", "universal", 0.95, -12))
	out.append(_rule("str_wide_chain", "广谱链", "universal", 1.08, 30))
	out.append(_rule("str_dup_flag", "参数重复", "universal", 0.92, -14))
	out.append(_rule("str_adjacent_task_knowledge", "任务素材相邻", "universal", 1.00, 6))
	out.append(_rule("str_gap", "结构断裂", "universal", 0.98, -6))
	out.append(_rule("str_compact", "精简命令行", "universal", 1.00, 8))
	out.append(_rule("str_verbose", "冗长命令行", "universal", 1.00, -10))
	# ── 口味规则（16 条）────────────────────────────────
	out.append(_rule("tas_dd_grounded", "接地思考", "taste", 1.00, 8))
	out.append(_rule("tas_dd_constraint_tail", "约束收尾", "taste", 1.00, 12))
	out.append(_rule("tas_dd_reasoning", "要求推理", "taste", 1.00, 12))
	out.append(_rule("tas_dd_strict", "严谨链", "taste", 1.04, 6))
	out.append(_rule("tas_kw_cjk", "中文值", "taste", 1.00, 10))
	out.append(_rule("tas_kw_long", "长命令", "taste", 1.00, 10))
	out.append(_rule("tas_kw_example_pair", "先任务后范例", "taste", 1.00, 12))
	out.append(_rule("tas_kw_fluent", "中文流畅", "taste", 1.04, 6))
	out.append(_rule("tas_cp_no_example", "免范例", "taste", 1.00, 12))
	out.append(_rule("tas_cp_structured", "结构化", "taste", 1.00, 12))
	out.append(_rule("tas_cp_format", "要格式", "taste", 1.00, 10))
	out.append(_rule("tas_cp_neat", "整洁", "taste", 1.04, 6))
	out.append(_rule("tas_gr_live", "时效优先", "taste", 1.00, 14))
	out.append(_rule("tas_gr_anchor", "检索锚点", "taste", 1.00, 12))
	out.append(_rule("tas_gr_evidence_pair", "双证据", "taste", 1.00, 10))
	out.append(_rule("tas_gr_fresh", "新料", "taste", 1.04, 6))
	return out


## 某位 AI 娘实际参与判定的规则表 = 23 条通用 + 其 taste_rules 命中的口味规则
static func rules_for(ai: AiData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var taste_ids := {}
	if ai != null:
		for id in ai.taste_rules:
			taste_ids[id] = true
	for r in rule_table():
		var rid := str(r["id"])
		if str(r["scope"]) == "universal" or taste_ids.has(rid):
			out.append(r)
	return out


## 把 prefix + 片段拼成完整命令行文本
static func compose_command(prefix: String, parts: Array[String]) -> String:
	var head := prefix.strip_edges()
	if parts.is_empty():
		return head
	if head == "":
		return " ".join(parts)
	return head + " " + " ".join(parts)


## 命令行总字符数（含 prefix、引号、空格）
static func command_length(prefix: String, parts: Array[String]) -> int:
	return compose_command(prefix, parts).length()


## 命令行里是否含有某个 flag 的片段（"--knowledge" / "--task" ...）
static func has_flag(parts: Array[String], flag: String) -> bool:
	for p in parse(parts):
		if str(p.get("arg", "")) == flag:
			return true
	return false


## 道具带来的顺序层倍率加成（Gemigo 多模态：命令行含 --knowledge 片段时 ×1.08）。
## 叠加在规则层倍率之上；同一种 effect_id 只算一次。
static func item_order_mult(parts: Array[String], items: Array[AiItemData]) -> float:
	var mult := 1.0
	var applied := {}
	for it in items:
		var e = ITEM_MULT_EFFECTS.get(it.effect_id, null)
		if e == null or applied.has(it.effect_id):
			continue
		applied[it.effect_id] = true
		var flag := str(e.get("flag", ""))
		if flag == "" or has_flag(parts, flag):
			mult *= float(e["mult"])
	return mult


# ── 内部工具 ─────────────────────────────────────────
static func _rule(id: String, name: String, scope: String, mult: float, flat: int) -> Dictionary:
	return {"id": id, "name": name, "scope": scope, "mult": mult, "flat": flat}


static func _get_regex() -> RegEx:
	if _regex == null:
		var re := RegEx.new()
		re.compile("^(--[a-z]+)\\s+\"((?:[^\"\\\\]|\\\\.)*)\"$")
		_regex = re
	return _regex


static func _has_cjk(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= CJK_MIN and c <= CJK_MAX:
			return true
	return false


static func _contains_any(s: String, words: Array) -> bool:
	for w in words:
		if s.contains(str(w)):
			return true
	return false


## 生成一条评语。格式：`<AI 显示名>：<一句评语>（+N 分）` 或 `（×1.04）`
static func _note(rule_id: String, flat: int, mult: float, ai: AiData) -> String:
	var who := "系统"
	if ai != null and ai.display_name != "":
		who = ai.display_name
	var tail := ""
	if not is_equal_approx(mult, 1.0):
		tail = "（×%.2f）" % mult
	else:
		tail = "（%+d 分）" % flat
	return "%s：%s%s" % [who, _comment(rule_id), tail]


static func _comment(rule_id: String) -> String:
	match rule_id:
		"str_empty":
			return "命令行是空的——我什么都没收到。"
		"str_len_2":
			return "两段命令，够跑但不够稳。"
		"str_len_3":
			return "三段要素齐了，骨架有了。"
		"str_len_4":
			return "四段要素齐全，信息量够了。"
		"str_len_5":
			return "五段要素齐全，写得挺细。"
		"str_len_6":
			return "六段全用上了，命令行写满了。"
		"str_clean":
			return "顺序一点没乱，我读得很顺。"
		"str_one_swap":
			return "有一处顺序颠了一下。"
		"str_messy":
			return "两处错位，读起来有点别扭。"
		"str_scramble":
			return "顺序全乱了，我得自己猜你要什么。"
		"str_role_head":
			return "你把身份放在开头了，我知道该用什么口吻。"
		"str_no_role_head":
			return "开头不是 --role，我不知道该用什么身份回答。"
		"str_task_anchor":
			return "任务放在该在的位置。"
		"str_task_misplaced":
			return "任务的位置不对，它该排在角色后面。"
		"str_format_before_example":
			return "格式在范例前面，先定形再举例。"
		"str_constraint_tail":
			return "约束收尾了，边界很明确。"
		"str_constraint_broken":
			return "约束没放在最后，边界被后面的内容盖住了。"
		"str_wide_chain":
			return "要素种类铺得很开，链路够完整。"
		"str_dup_flag":
			return "同一个参数写了两遍，我按后面那条理解。"
		"str_adjacent_task_knowledge":
			return "任务和素材挨着，读起来很连贯。"
		"str_gap":
			return "中间跳掉了几类要素，结构有断层。"
		"str_compact":
			return "命令行很短，没有废话。"
		"str_verbose":
			return "命令行太长了，我读了两遍。"
		"tas_dd_grounded":
			return "给了素材，我就不是靠猜。"
		"tas_dd_constraint_tail":
			return "约束收尾了，我先划边界再动手。"
		"tas_dd_reasoning":
			return "你让我讲道理、说步骤，我按推理链来。"
		"tas_dd_strict":
			return "素材加约束，这就严谨了。"
		"tas_kw_cjk":
			return "中文值我读得最顺。"
		"tas_kw_long":
			return "写这么长，说明你想清楚了。"
		"tas_kw_example_pair":
			return "先给任务再给范例，跟我想的一样。"
		"tas_kw_fluent":
			return "中文多、段数也够，读起来很顺。"
		"tas_cp_no_example":
			return "没有范例反而清爽，直接按格式来。"
		"tas_cp_structured":
			return "值里带了结构化关键词，我能照着排。"
		"tas_cp_format":
			return "你说了格式，我照着输出。"
		"tas_cp_neat":
			return "有格式无范例，整洁得像模板。"
		"tas_gr_live":
			return "提到最新、实时，我按新鲜的说。"
		"tas_gr_anchor":
			return "素材紧挨任务，先接料再下活。"
		"tas_gr_evidence_pair":
			return "素材加范例，双份证据。"
		"tas_gr_fresh":
			return "有素材且段数够，我抓得到重点。"
	return rule_id
