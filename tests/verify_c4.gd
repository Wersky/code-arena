extends SceneTree
## 独立复算契约 C.4 的四组算例（用实际实现跑，不看文档里的结论数字）
## 断言值取自 docs/01-新机制设计.md C.4（该章已按规则表实现值修正过）
func _initialize() -> void:
	var ai = AiPool.get_ai("deepdeek")
	if ai == null:
		print("FAIL: 取不到 deepdeek")
		quit(1); return
	var by_title: Dictionary = {}
	for c in CardPool.all_cards():
		by_title[c.title] = c
	# 每例：卡标题顺序（对应命令行片段顺序）
	var cases := [
		{"titles": ["资深工程师","写个函数","附上报错堆栈","输出一段 JSON","给一个正例","不得编造事实"], "expect": 1228},
		{"titles": ["写个函数","资深工程师","附上报错堆栈","输出一段 JSON","给一个正例","不得编造事实"], "expect": 1045},
		{"titles": ["不得编造事实","输出一段 JSON","写个函数","资深工程师","给一个正例","附上报错堆栈"], "expect": 799},
		{"titles": ["资深工程师","小学老师","写个函数"], "expect": 113},
	]
	var fail := 0
	for i in cases.size():
		var titles: Array = cases[i]["titles"]
		var cards: Array[CardData] = []
		var parts: Array[String] = []
		for t in titles:
			var card: CardData = by_title[t]
			cards.append(card)
			parts.append(card.cli_fragment())
		var ctx := {
			"token_budget": 12, "items": [] as Array[AiItemData],
			"turn_index": 0, "rule": LevelData.Rule.NONE, "shield": false,
			"preview": false, "ai": ai, "command_parts": parts,
		}
		var r := Scoring.evaluate(cards, ctx)
		var got := int(r["score"])
		var expect := int(cases[i]["expect"])
		var ok := got == expect
		if not ok: fail += 1
		print("%s 例%d  期望=%d 实得=%d  order_flat=%s order_mult=%s" % [
			"ok  " if ok else "FAIL", i+1, expect, got,
			str(r.get("order_flat","?")), str(r.get("order_mult","?"))])
		print("      %s" % str(r.get("command_text","?")))
	print("\n不匹配 %d / %d" % [fail, cases.size()])
	quit(1 if fail > 0 else 0)
