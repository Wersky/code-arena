class_name EffectDSL
extends RefCounted
## 效果 DSL 的编译层：AI 写的 JSON 程序 → 本地合法 AST。
##
## 铁律（圆桌第 1 轮）：
##   - 非法 clause **静默丢弃**，不报错、不重试（重试会让 20–60s 的等待翻倍）
##   - 定价必须按**丢弃后的最终 AST** 算，不能按原始意图算
##   - 校验通过后 `clauses` 即唯一真相，运行期不再做二次判断

## 编译结果：
##   ok       是否至少留下 1 条合法 clause
##   clauses  规范化后的 AST（触发器/条件/操作都填好默认值）
##   dropped  被丢弃的 clause 数
##   ops      最终 op 总数
##   errors   人话原因列表（调试用，不进玩家界面）
static func compile(program, max_ops_override: int = -1) -> Dictionary:
	var out := {"ok": false, "clauses": [], "dropped": 0, "ops": 0, "errors": [],
			"version": EffectSpec.VERSION}
	if not (program is Array):
		out["errors"].append("program 不是数组")
		return out
	var max_clauses: int = EffectSpec.LIMITS["max_clauses"]
	## 好感度加成可临时抬升 op 上限（默认走规格表）
	var max_ops: int = max_ops_override if max_ops_override > 0 			else int(EffectSpec.LIMITS["max_ops"])
	var clauses: Array = []
	var ops_total := 0
	var dropped := 0
	for raw in program:
		if clauses.size() >= max_clauses:
			dropped += program.size() - clauses.size() - dropped
			out["errors"].append("超过 %d 条 clause，多余丢弃" % max_clauses)
			break
		if not (raw is Dictionary):
			dropped += 1
			continue
		var when := String(raw.get("when", "")).strip_edges().to_lower()
		if not EffectSpec.TRIGGERS.has(when):
			dropped += 1
			out["errors"].append("未知触发器：%s" % when)
			continue
		var cond := _normalize_cond(raw.get("if", {}))
		var then_raw = raw.get("then", [])
		if not (then_raw is Array):
			dropped += 1
			continue
		var ops: Array = []
		for op_raw in then_raw:
			if ops_total >= max_ops:
				out["errors"].append("超过 %d 个 op，多余丢弃" % max_ops)
				break
			var op := _normalize_op(op_raw)
			if op.is_empty():
				continue
			ops.append(op)
			ops_total += 1
		if ops.is_empty():
			dropped += 1
			continue
		var clause := {"when": when, "then": ops}
		if not cond.is_empty():
			clause["if"] = cond
		clauses.append(clause)
	out["clauses"] = clauses
	out["dropped"] = dropped
	out["ops"] = ops_total
	out["ok"] = not clauses.is_empty()
	return out


## 条件归一：只支持单计数器比较（v1），未知字段丢弃
## 形如 {"counter": "hand_size", "gte": 5}
static func _normalize_cond(raw) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var counter := String(raw.get("counter", "")).strip_edges()
	if not EffectSpec.COUNTERS.has(counter):
		return {}
	for key in ["gte", "lte"]:
		if raw.has(key) and (raw[key] is int or raw[key] is float):
			return {"counter": counter, key: int(raw[key])}
	return {}


static func _normalize_op(raw) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var do_key := String(raw.get("do", "")).strip_edges().to_lower()
	if not EffectSpec.OPS.has(do_key):
		return {}
	var spec: Dictionary = EffectSpec.OPS[do_key]
	var args_spec: Dictionary = spec.get("args", {})
	var op := {"do": do_key}
	for arg_name in args_spec.keys():
		var aspec: Dictionary = args_spec[arg_name]
		var v = raw.get(arg_name, aspec.get("default"))
		op[arg_name] = _coerce(v, aspec)
	return op


static func _coerce(v, aspec: Dictionary) -> Variant:
	match String(aspec.get("type", "int")):
		"enum":
			var s := String(v)
			var vals: Array = aspec.get("values", [])
			return s if vals.has(s) else String(aspec.get("default", ""))
		_:
			var n := int(v) if (v is int or v is float or (v is String and v.is_valid_int())) else -999
			if n == -999:
				return int(aspec.get("default", 0))
			return clampi(n, int(aspec.get("min", 0)), int(aspec.get("max", 999)))


## 写集签名：AST 里所有 op 触达的维度（组合检测的输入）
static func writeset(clauses: Array) -> Dictionary:
	var ws := {}
	for clause in clauses:
		for op in clause.get("then", []):
			var spec: Dictionary = EffectSpec.OPS.get(String(op.get("do", "")), {})
			for dim in spec.get("writes", []):
				ws[String(dim)] = true
	return ws


## 静态复杂度（定价第二轴：只回答"多难读"，不回答"多强"）
static func complexity(clauses: Array) -> int:
	var score := 0
	for clause in clauses:
		score += 1
		if clause.has("if"):
			score += 1
		score += (clause.get("then", []) as Array).size()
	return score


## 人话反渲染：卡面永远显示这句，不显示 AI 写的 desc
static func describe(clauses: Array) -> String:
	var parts: Array[String] = []
	for clause in clauses:
		var when := String(EffectSpec.TRIGGERS.get(String(clause.get("when", "")), "?"))
		var cond := _describe_cond(clause.get("if", {}))
		var acts: Array[String] = []
		for op in clause.get("then", []):
			acts.append(_describe_op(op))
		var line := "%s：%s" % [when, "，".join(acts)]
		if cond != "":
			line += "（%s）" % cond
		parts.append(line)
	return "；".join(parts)


static func _describe_cond(cond) -> String:
	if not (cond is Dictionary) or cond.is_empty():
		return ""
	var counter := String(EffectSpec.COUNTERS.get(String(cond.get("counter", "")), "?"))
	if cond.has("gte"):
		return "%s ≥ %d" % [counter, int(cond["gte"])]
	if cond.has("lte"):
		return "%s ≤ %d" % [counter, int(cond["lte"])]
	return ""


static func _describe_op(op: Dictionary) -> String:
	match String(op.get("do", "")):
		"damage":
			return "造成 %d 点伤害" % int(op.get("amount", 0))
		"damage_scaled":
			var base := int(op.get("amount", 0))
			var per := String(EffectSpec.COUNTERS.get(String(op.get("per", "")), "?"))
			var step := int(op.get("step", 0))
			if base <= 0:
				return "伤害 = %s × %d" % [per, step]
			return "造成 %d 点伤害 + %s × %d" % [base, per, step]
		"apply_status":
			var st := String(op.get("status", ""))
			var tier := int(op.get("tier", 1))
			var label := String(EffectSpec.STATUSES.get(st, {}).get("label", st))
			var tgt := "自身" if String(op.get("target", "enemy")) == "self" else "敌人"
			var val := _status_amount(st, tier)
			return "%s获得 %s%s" % [tgt, label, val]
		"heal":
			return "回复 %d 点生命" % int(op.get("amount", 0))
		"draw":
			return "抽 %d 张牌" % int(op.get("amount", 0))
		"discard_random":
			return "随机弃 %d 张并补抽" % int(op.get("amount", 0))
		"multiply_next":
			return "下一张牌效果 ×%d" % int(op.get("factor", 2))
		"block":
			return "获得 %d 点格挡" % int(op.get("amount", 0))
		"duplicate_next":
			return "下一张牌执行两次"
		"modify_intent":
			return "敌人下次行动 %+d" % int(op.get("delta", 0))
	return "?"


static func _status_amount(status: String, tier: int) -> String:
	match status:
		"poison", "thorns":
			return "（%d，%d 回合）" % [EffectSpec.status_value(status, tier, "dot" if status == "poison" else "reflect"),
					EffectSpec.status_turns(status, tier)]
		"strength":
			return " +%d" % EffectSpec.status_value(status, tier, "atk_bonus")
		_:
			return "（%d 回合）" % EffectSpec.status_turns(status, tier)
