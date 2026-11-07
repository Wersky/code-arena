extends SceneTree
## 校验真模型输出：把 tools/probe_out.jsonl 里的卡 JSON 丢进本地 EffectDSL 编译。
##
## 运行：godot --headless --path <项目> --script res://tools/check_programs.gd
##
## 输出：每张卡的解析结果 + 汇总（JSON 可解析率 / program 出现率 / 编译合法率 / 平均 op 数）

const IN_PATH := "res://tools/probe_out.jsonl"


func _init() -> void:
	var f := FileAccess.open(IN_PATH, FileAccess.READ)
	if f == null:
		print("找不到 %s（先跑 tools/probe_programs.py）" % IN_PATH)
		quit(1)
		return
	var total := 0
	var parse_ok := 0
	var used_fx := 0
	var empty_fx := 0
	var attempted := 0
	var compile_ok := 0
	var ops_total := 0
	var lat_total := 0.0
	var rows: Array = []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty():
			continue
		var row = JSON.parse_string(line)
		if not (row is Dictionary):
			continue
		total += 1
		var txt := String(row.get("content", ""))
		lat_total += float(row.get("latency_s", 0.0))
		var card := _extract_card(txt)
		var status := "无JSON"
		var ops := 0
		var dropped := 0
		var desc := ""
		var row_legal := false
		if not card.is_empty():
			parse_ok += 1
			var prog = card.get("program", null)
			if prog is Array and (prog as Array).is_empty():
				empty_fx += 1
				status = "未用效果（合法选择）"
			elif prog is Array:
				used_fx += 1
				attempted += 1
				var c := EffectDSL.compile(prog)
				ops = int(c["ops"])
				dropped = int(c["dropped"])
				if bool(c["ok"]):
					compile_ok += 1
					row_legal = true
					desc = EffectDSL.describe(c["clauses"])
				status = "ok" if bool(c["ok"]) else "程序被丢空"
			else:
				status = "无program字段"
		ops_total += ops
		rows.append([String(row.get("model", "?")), String(row.get("prompt", "")),
				status, ops, dropped, desc])
		## 闭环：合法的程序直接进定价器（100 样本，约 0.1s）
		var cost_txt := "  —"
		if row_legal and ops > 0:
			var c2 := EffectDSL.compile(card.get("program", []))
			var pc := StsCard.make("probe_%d" % total, StsCard.Kind.ATTACK, 1,
					clampi(int(card.get("damage", 6)), 0, 20), 0, "")
			pc.effects = c2["clauses"]
			pc.dsl_version = EffectSpec.VERSION
			var pr := EffectPricing.price(pc, 1, 100)
			cost_txt = "  cost=%d EV=%+.1f" % [int(pr["cost"]), float(pr["ev"])]
		print("%-14s %-16s %-16s ops=%d dropped=%d  %s%s" % [
			String(row.get("model", "?")), String(row.get("prompt", "")),
			status, ops, dropped, desc.substr(0, 40), cost_txt])

	print("\n=== 汇总（%d 条）===" % total)
	print("JSON 可解析：%d/%d" % [parse_ok, total])
	print("写了效果   ：%d/%d（其余为 program=[] 的合法选择）" % [used_fx, total])
	print("尝试后合法 ：%d/%d（%.0f%%）" % [compile_ok, attempted,
			(float(compile_ok) / maxf(1.0, float(attempted))) * 100.0])
	print("平均 op 数 ：%.1f（仅统计写了效果的）" % (float(ops_total) / maxf(1.0, float(used_fx))))
	print("平均耗时   ：%.1fs" % (lat_total / maxf(1.0, float(total))))
	quit()


## 从模型输出里抠卡 JSON：括号配对扫描（跳过字符串字面量）。
## 模型偶尔会在 JSON 后多吐一个 }，用 rfind 会带上垃圾导致解析失败（实测踩过）。
func _extract_card(txt: String) -> Dictionary:
	var start := txt.find("{\"name\"")
	if start < 0:
		start = txt.find("{")
	if start < 0:
		return {}
	var depth := 0
	var in_str := false
	var esc := false
	for k in range(start, txt.length()):
		var ch := txt[k]
		if esc:
			esc = false
			continue
		if in_str:
			if ch == "\\":
				esc = true
			elif ch == "\"":
				in_str = false
			continue
		if ch == "\"":
			in_str = true
		elif ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				var parsed = JSON.parse_string(txt.substr(start, k - start + 1))
				return parsed if parsed is Dictionary else {}
	return {}
