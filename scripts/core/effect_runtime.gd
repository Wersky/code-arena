class_name EffectRuntime
extends RefCounted
## 效果程序的求值器：纯函数，不碰战斗状态，只把 op 解析成「效果意图」列表。
##
## 求值器不做任何 IO / 随机 / 递归——这是圆桌定下的承重性质：
## 只要它是纯函数、输入输出可快照，AI 写出来的就只是数据。
##
## 运行期预算（圆桌第 1 轮）：全局 op 预算 64 + 触发深度 1。
## 深度 1 由结构保证：本求值器**不产生新事件**，效果无法再触发效果。

## ctx 约定（由 StsCombat 填）：
##   hand_size / same_kind_streak / cards_played_this_turn / enemy_status_count / turn
static func eval(clauses: Array, trigger: String, ctx: Dictionary) -> Array:
	var out: Array = []
	if clauses.is_empty():
		return out
	var budget: int = EffectSpec.LIMITS["op_budget"]
	for clause in clauses:
		if budget <= 0:
			break
		if String(clause.get("when", "")) != trigger:
			continue
		if not _cond_ok(clause.get("if", {}), ctx):
			continue
		for op in clause.get("then", []):
			if budget <= 0:
				break
			budget -= 1
			var r := resolve(op, ctx)
			if not r.is_empty():
				out.append(r)
	return out


static func _cond_ok(cond, ctx: Dictionary) -> bool:
	if not (cond is Dictionary) or cond.is_empty():
		return true
	var v := int(ctx.get(String(cond.get("counter", "")), 0))
	if cond.has("gte") and v < int(cond["gte"]):
		return false
	if cond.has("lte") and v > int(cond["lte"]):
		return false
	return true


## 单 op → 效果意图；未知 op 返回空字典（调用方跳过）
static func resolve(op: Dictionary, ctx: Dictionary) -> Dictionary:
	match String(op.get("do", "")):
		"damage":
			return {"op": "damage", "amount": maxi(0, int(op.get("amount", 0)))}
		"damage_scaled":
			var base := maxi(0, int(op.get("amount", 0)))
			var step := maxi(0, int(op.get("step", 0)))
			var n := int(ctx.get(String(op.get("per", "")), 0))
			return {"op": "damage", "amount": base + step * n}
		"apply_status":
			return {
				"op": "apply_status",
				"status": String(op.get("status", "weak")),
				"tier": clampi(int(op.get("tier", 1)), 1, 3),
				"target": String(op.get("target", "enemy")),
			}
		"heal":
			return {"op": "heal", "amount": maxi(1, int(op.get("amount", 3)))}
		"draw":
			return {"op": "draw", "amount": maxi(1, int(op.get("amount", 1)))}
		"discard_random":
			return {"op": "discard_random", "amount": maxi(1, int(op.get("amount", 1)))}
		"multiply_next":
			return {"op": "multiply_next", "factor": maxi(2, int(op.get("factor", 2)))}
		"block":
			return {"op": "block", "amount": maxi(0, int(op.get("amount", 5)))}
		"duplicate_next":
			return {"op": "duplicate_next"}
		"modify_intent":
			return {"op": "modify_intent",
					"delta": clampi(int(op.get("delta", -3)), -10, 10)}
	return {}


## 求值轨迹（调试/定价用）：返回每条 clause 是否命中，便于定位"为什么没触发"
static func trace(clauses: Array, trigger: String, ctx: Dictionary) -> Array:
	var rows: Array = []
	for clause in clauses:
		var when := String(clause.get("when", ""))
		var row := {"when": when, "matched": false, "ops": 0}
		if when == trigger and _cond_ok(clause.get("if", {}), ctx):
			row["matched"] = true
			row["ops"] = (clause.get("then", []) as Array).size()
		rows.append(row)
	return rows
