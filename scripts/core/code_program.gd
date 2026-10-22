class_name CodeProgram
extends RefCounted
## 代码程序：把打出的代码卡当成一段程序来校验与结算。
##
## ★ 核心铁律（主人定的，2026-10-22 简化为 3 条）：
##   **代码语句规则正确才算给分**。语法不合法 → 每张卡只值 1 分（最少的基础分），
##   零结构加成；语法合法 → 按卡面分 + 结构加成给分。
##
## 三条语法规则（每条都有一句中文提示，界面上原样显示）：
##   R1  while 后面必须紧跟 if      （用条件限制循环，不然死循环）
##   R2  try   后面必须紧跟 catch   （出错要接住）；catch 前面也必须有 try
##   R3  else  前面必须有 if        （没有岔路口就没有"另一条路"）
##
## 三个结构加成（语法合法之后才生效）：
##   护栏 while+if +20 ／ 兜底 try+catch +25 ／ 分支 if+else +20
##
## 计分（唯一一条，没有乘区、没有 Token、没有主题加成）：
##   合法：score = Σ 卡面分 + Σ 结构加成
##   非法：score = 卡数（每张 1 分）
##
## printf / cache 是普通语句，放哪都不影响语法，只提供卡面分。

## 规则提示文案 → 界面直接显示
const RULE_TEXT := {
	"while_needs_if": "while 后面必须紧跟 if（用条件限制循环）",
	"try_needs_catch": "try 后面必须紧跟 catch（出错要接住）",
	"catch_needs_try": "catch 前面必须有 try（没有 try 就没有异常可接）",
	"else_needs_if": "else 前面必须有 if（没有岔路口就没有另一条路）",
}

## 结构加成表：id -> {name, desc, flat}
const STRUCTURES := {
	"guard": {"name": "护栏", "desc": "while 后面接了 if，循环有出口", "flat": 20},
	"fallback": {"name": "兜底", "desc": "try 后面接了 catch，出错也接得住", "flat": 25},
	"branch": {"name": "分支", "desc": "if 后面接了 else，两条路都照顾到", "flat": 20},
}


static func _ids(cards: Array[CodeCard]) -> Array[String]:
	var out: Array[String] = []
	for c in cards:
		if c != null:
			out.append(c.id)
	return out


## 语法校验。返回 {ok: bool, errors: Array[String]}
static func validate(cards: Array[CodeCard]) -> Dictionary:
	var ids := _ids(cards)
	var n := ids.size()
	var errors: Array[String] = []

	# R1：while 后面必须紧跟 if
	for i in n:
		if ids[i] == "while_kw":
			if i + 1 >= n or ids[i + 1] != "if_kw":
				errors.append(str(RULE_TEXT["while_needs_if"]))

	# R2：try 后面必须紧跟 catch
	for i in n:
		if ids[i] == "try_kw":
			if i + 1 >= n or ids[i + 1] != "catch_kw":
				errors.append(str(RULE_TEXT["try_needs_catch"]))

	# R2b：catch 前面必须是 try（成对）
	for i in n:
		if ids[i] == "catch_kw":
			if i == 0 or ids[i - 1] != "try_kw":
				errors.append(str(RULE_TEXT["catch_needs_try"]))

	# R3：else 前面必须是 if
	for i in n:
		if ids[i] == "else_kw":
			if i == 0 or ids[i - 1] != "if_kw":
				errors.append(str(RULE_TEXT["else_needs_if"]))

	return {"ok": errors.is_empty(), "errors": errors}


## 前缀体检：给平衡模拟的束搜索用。
## hard = 这一位已经不可能被后续补牌救回来（else 前面没 if）；其余错误补牌还能修。
static func prefix_issues(cards: Array[CodeCard]) -> Dictionary:
	var v := validate(cards)
	var hard := 0
	for e in (v["errors"] as Array):
		if str(e) == str(RULE_TEXT["else_needs_if"]):
			hard += 1
	return {"hard": hard, "errors": v["errors"]}


## 命中的结构加成列表：[{combo_id, name, desc, flat}]
static func structures(cards: Array[CodeCard]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := _ids(cards)
	var n := ids.size()

	var guard := 0
	var fallback := 0
	var branch := 0
	for i in n:
		if ids[i] == "while_kw" and i + 1 < n and ids[i + 1] == "if_kw":
			guard += 1
		if ids[i] == "try_kw" and i + 1 < n and ids[i + 1] == "catch_kw":
			fallback += 1
		# 分支：if 紧跟 else。while 的护栏 if 后面接 else 也算（很自然）。
		if ids[i] == "if_kw" and i + 1 < n and ids[i + 1] == "else_kw":
			branch += 1

	if guard > 0:
		out.append(_struct("guard", guard))
	if fallback > 0:
		out.append(_struct("fallback", fallback))
	if branch > 0:
		out.append(_struct("branch", branch))
	return out


static func _struct(struct_id: String, count: int) -> Dictionary:
	var s: Dictionary = STRUCTURES[struct_id]
	var desc := str(s["desc"])
	if count > 1:
		desc += "（×%d）" % count
	return {
		"combo_id": struct_id,
		"name": str(s["name"]),
		"desc": desc,
		"flat": int(s["flat"]) * count,
	}


## 结算。ctx 只有一个可选键 carried_flat（奖励累积的永久加成）——
## Token / 主题 / 关卡规则在基础玩法里**全部不存在**。
static func evaluate(cards: Array[CodeCard], ctx: Dictionary = {}) -> Dictionary:
	var out := {
		"score": 0, "base": 0, "flat": 0,
		"hits": [] as Array[Dictionary], "errors": [] as Array[String],
		"valid": true, "per_card": [] as Array[Dictionary],
		"notes": [] as Array[String],
	}

	var usable: Array[CodeCard] = []
	for c in cards:
		if c != null:
			usable.append(c)
	if usable.is_empty():
		return out

	var v := validate(usable)
	out["valid"] = bool(v["ok"])
	out["errors"] = v["errors"]

	var per_card: Array[Dictionary] = []
	var base := 0

	if not bool(v["ok"]):
		# 语法错误：每张卡只值 1 分，零结构加成
		for c in usable:
			base += 1
			per_card.append({
				"id": c.id, "name": c.name, "kind": c.kind,
				"base_score": 1, "score": 1,
			})
		for e in (v["errors"] as Array):
			out["notes"].append("✗ 语法错误：%s" % str(e))
		out["notes"].append("程序跑不起来，只给最少的基础分。")
	else:
		var hits := structures(usable)
		for h in hits:
			out["flat"] = int(out["flat"]) + int(h["flat"])
		out["hits"] = hits
		for c in usable:
			base += c.base_score
			per_card.append({
				"id": c.id, "name": c.name, "kind": c.kind,
				"base_score": c.base_score, "score": c.base_score,
			})

	out["base"] = base
	out["per_card"] = per_card
	out["score"] = maxi(0, base + int(out["flat"]) + int(ctx.get("carried_flat", 0)))
	return out
