extends SceneTree
## 梗卡机制**独立自测**：23 张卡 + 24 条连携的命中与结算。
##
## 运行：godot --headless --path . --script res://tests/_meme_selftest.gd
##
## 与 tests/smoke_test.gd 的分工：
##   smoke_test.gd —— 全项目冒烟（含梗卡断言），**回归跑这个**
##   本脚本 —— 梗卡引擎的**单独深测**（219 项），出问题时用它定位
##   两者互相独立，都能单独跑。

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_test_card_pool()
	_test_themes()
	_test_every_combo_hits()
	_test_scoring_numbers()
	_test_exclusive_blocking()
	_test_token_penalty()
	_test_random_reproducible()
	_test_double_next()
	print("\n==== %d 项检查，%d 项失败 ====" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok  : " + msg)
	else:
		_fails += 1
		printerr("FAIL  : " + msg)


func _eq(actual, expected, msg: String) -> void:
	_check(actual == expected, "%s 期望=%s 实得=%s" % [msg, str(expected), str(actual)])


## 按 id 造卡（可重复以满足 ×2 / ×3）
func _cards(ids: Array) -> Array[MemeCard]:
	var out: Array[MemeCard] = []
	for cid in ids:
		var c := MemeCard.get_card(str(cid))
		if c == null:
			return out
		out.append(c.duplicate())
	return out


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# ── 牌池 ─────────────────────────────────────────────
func _test_card_pool() -> void:
	print("[牌池]")
	var all := MemeCard.all_cards()
	_eq(all.size(), 23, "牌池共 23 张（19 通用 + 4 专属，逐字照抄任务卡表格）")
	var ids := {}
	for c in all:
		_check(not ids.has(c.id), "卡 id 唯一：" + c.id)
		ids[c.id] = true
		_check(c.base_score > 0, "卡有基础分：" + c.id)
		_check(c.token_cost >= 1, "卡有 Token 消耗：" + c.id)
		_check(c.flavor != "", "卡有梗注解：" + c.id)
	for expect in ["rice", "mantou", "hotpot", "foodie", "while_kw", "for_kw",
			"if_kw", "else_kw", "recursion", "try_kw", "catch_kw", "printf",
			"deadlock", "illusion", "temp", "emerge", "context", "cache", "token",
			"bigfish", "rice_freedom", "binge", "deepfish"]:
		_check(MemeCard.get_card(expect) != null, "存在卡 " + expect)
	# 数值抽查
	_eq(MemeCard.get_card("rice").base_score, 12, "白米饭基础分 12")
	_eq(MemeCard.get_card("hotpot").base_score, 16, "火锅基础分 16")
	_eq(MemeCard.get_card("bigfish").base_score, 20, "大肥鱼基础分 20")
	_eq(MemeCard.get_card("bigfish").unique_owner, "deepdeek", "大肥鱼专属 deepdeek")
	_eq(MemeCard.get_card("rice").unique_owner, "", "白米饭无归属")
	_eq(MemeCard.Kind.FOOD, 0, "饭类型枚举值 0")


# ── 主题 ─────────────────────────────────────────────
func _test_themes() -> void:
	print("[主题]")
	_eq(MemeCard.themes().size(), 4, "共 4 位 AI娘主题")
	for t in MemeCard.themes():
		_check(str(t.get("id", "")) != "", "主题有 id")
		_check(str(t.get("desc", "")) != "", "主题有说明：" + str(t["id"]))
	# deepdeek 饭类 ×1.3
	var rice := MemeCard.get_card("rice")
	var hotpot := MemeCard.get_card("hotpot")
	var while_card := MemeCard.get_card("while_kw")
	var ctx := {"theme_id": "deepdeek", "token_budget": 99}
	var r_food := MemeCombo.evaluate(_cards(["rice", "hotpot"]), ctx)
	_eq(r_food["base"], int(round(12 * 1.3)) + int(round(16 * 1.3)), "deepdeek 饭类卡 ×1.3")
	var r_code := MemeCombo.evaluate(_cards(["while_kw"]), ctx)
	_eq(r_code["base"], 12, "deepdeek 代码卡不加成")
	# gemigo 玄学 ×1.3
	var r_mystic := MemeCombo.evaluate(_cards(["illusion"]), {"theme_id": "gemigo"})
	_eq(r_mystic["base"], int(round(14 * 1.3)), "gemigo 玄学卡 ×1.3")
	# grock 代码 ×1.3
	var r_code2 := MemeCombo.evaluate(_cards(["while_kw"]), {"theme_id": "grock"})
	_eq(r_code2["base"], int(round(12 * 1.3)), "grock 代码卡 ×1.3")
	# kweno 所有卡 +8（用 mantou + token，避免触发 c_infinite）
	var r_all := MemeCombo.evaluate(_cards(["mantou", "token"]), {"theme_id": "kweno"})
	_eq(r_all["base"], (10 + 8) + (10 + 8), "kweno 所有卡 +8")
	# kweno 加成可与连携叠加：rice + while_kw 同时吃 kweno +8 与 c_infinite 饭类 ×1.4
	var r_all2 := MemeCombo.evaluate(_cards(["rice", "while_kw"]), {"theme_id": "kweno"})
	_eq(r_all2["base"], int(round(12 * 1.4)) + 8 + 12 + 8, "kweno +8 与 c_infinite 叠加")


# ── 每条连携都能命中 ─────────────────────────────────
func _test_every_combo_hits() -> void:
	print("[连携命中]")
	var table := MemeCombo.table()
	_check(table.size() >= 16, "连携表 ≥16 条，实际 %d 条" % table.size())
	for combo in table:
		var ids: Array = []
		for req in combo["requires"]:
			var pair: Array = req
			for _i in int(pair[1]):
				ids.append(str(pair[0]))
		var theme := "deepdeek"
		var cards := _cards(ids)
		# 专属卡组合必须在 deepdeek 主题下测
		var r := MemeCombo.evaluate(cards, {"theme_id": theme, "token_budget": 99})
		var hit_ids := []
		for h in r["hits"]:
			hit_ids.append(str(h["combo_id"]))
		_check(hit_ids.has(str(combo["id"])),
			"连携可命中：%s（%s）" % [str(combo["id"]), str(combo["name"])])
		# hits 元素字段完整
		for h in r["hits"]:
			_check(h.has("combo_id") and h.has("name") and h.has("desc"),
				"hit 含 combo_id/name/desc：" + str(h["combo_id"]))


# ── 数值 ─────────────────────────────────────────────
func _test_scoring_numbers() -> void:
	print("[计分数值]")
	# 一饭两吃：白米饭×2 → 每张饭卡 ×2 → 12*2 + 12*2 = 48
	var r := MemeCombo.evaluate(_cards(["rice", "rice"]), {"theme_id": "none"})
	_eq(r["base"], 48, "c_rice2 饭类 ×2")
	_eq(r["score"], 48, "c_rice2 总分 48")
	# 无限续饭：米饭 + while → 饭类 ×1.4
	var r2 := MemeCombo.evaluate(_cards(["rice", "while_kw"]), {"theme_id": "none"})
	_eq(r2["base"], int(round(12 * 1.4)) + 12, "c_infinite 饭类 +40%")
	# 干饭人的干饭：foodie+rice → +50 分
	var r3 := MemeCombo.evaluate(_cards(["foodie", "rice"]), {"theme_id": "none"})
	_eq(r3["flat"], 50, "c_foodie 加 50 分")
	_eq(r3["base"], 14 + 12, "c_foodie 基础分")
	_eq(r3["score"], (14 + 12 + 50), "c_foodie 总分")
	# 火锅局：hotpot+foodie → ×1.25
	var r4 := MemeCombo.evaluate(_cards(["hotpot", "foodie"]), {"theme_id": "none"})
	_eq(r4["mult"], 1.25, "c_hotpot 倍率 1.25")
	_eq(r4["score"], int(round((16 + 14) * 1.25)), "c_hotpot 总分")
	# 刷屏：printf×3 → −40
	var r5 := MemeCombo.evaluate(_cards(["printf", "printf", "printf"]), {"theme_id": "none"})
	_eq(r5["flat"], -40, "c_spam 扣 40 分")
	# 兜住了：try+catch → 下回合免罚
	var r6 := MemeCombo.evaluate(_cards(["try_kw", "catch_kw"]), {"theme_id": "none"})
	_eq(bool(r6["carry"]["penalty_shield"]), true, "c_catch 留下免罚")
	# 卡死：while+deadlock → 本回合 0 分，下回合 ×1.3
	var r7 := MemeCombo.evaluate(_cards(["while_kw", "deadlock"]), {"theme_id": "none"})
	_eq(r7["score"], 0, "c_stuck 本回合 0 分")
	_eq(float(r7["carry"]["next_mult"]), 1.3, "c_stuck 下回合 ×1.3")
	# 命中缓存：cache+context → 不消耗 Token
	var r8 := MemeCombo.evaluate(_cards(["cache", "context"]), {"theme_id": "none", "token_budget": 9})
	_eq(r8["token_used"], 0, "c_hit 本回合 0 Token")
	# 爆上下文：context+token → 所有卡 +10
	var r9 := MemeCombo.evaluate(_cards(["context", "token"]), {"theme_id": "none"})
	_eq(r9["base"], (12 + 10) + (10 + 10), "c_overflow 每卡 +10")
	# 扶墙出：bigfish+binge → +120
	var r10 := MemeCombo.evaluate(_cards(["bigfish", "binge"]), {"theme_id": "deepdeek"})
	_eq(r10["flat"], 120, "c_binge 加 120 分")
	# 长胖自由：bigfish+rice_freedom → ×1.4，手牌上限 −1
	var r11 := MemeCombo.evaluate(_cards(["bigfish", "rice_freedom"]), {"theme_id": "deepdeek"})
	_eq(r11["mult"], 1.4, "c_salary 倍率 1.4")
	_eq(int(r11["carry"]["hand_limit_delta"]), -1, "c_salary 手牌上限 −1")


# ── 专属卡限制 ───────────────────────────────────────
func _test_exclusive_blocking() -> void:
	print("[专属卡]")
	var r := MemeCombo.evaluate(_cards(["bigfish", "rice"]), {"theme_id": "grock"})
	_eq(r["blocked"].size(), 1, "非 deepdeek 主题下大肥鱼被拦")
	_eq(r["base"], 12, "被拦的卡不计分")
	var hit_ids := []
	for h in r["hits"]:
		hit_ids.append(str(h["combo_id"]))
	_check(not hit_ids.has("c_free"), "非 deepdeek 主题下 c_free 不命中")
	var r2 := MemeCombo.evaluate(_cards(["bigfish", "rice"]), {"theme_id": "deepdeek"})
	_eq(r2["blocked"].size(), 0, "deepdeek 主题下大肥鱼可用")
	var hit_ids2 := []
	for h in r2["hits"]:
		hit_ids2.append(str(h["combo_id"]))
	_check(hit_ids2.has("c_free"), "deepdeek 主题下 c_free 命中")
	_check(MemeCard.card_allowed_in("deepdeek", MemeCard.get_card("bigfish")), "专属卡判定正确")


# ── Token 惩罚 ───────────────────────────────────────
func _test_token_penalty() -> void:
	print("[Token]")
	var r := MemeCombo.evaluate(_cards(["hotpot", "bigfish", "binge", "rice_freedom"]),
		{"theme_id": "deepdeek", "token_budget": 2})
	_eq(r["token_used"], 8, "Token 累计 8")
	_eq(r["penalty"], (8 - 2) * 12, "超预算每点罚 12")
	var expect_score := maxi(0, int(round((float(r["base"]) + float(r["flat"])) * float(r["mult"]))) - int(r["penalty"]))
	_eq(r["score"], expect_score, "总分 = round((base+flat)×mult) − 惩罚")
	var r2 := MemeCombo.evaluate(_cards(["hotpot"]), {"token_budget": 9})
	_eq(r2["penalty"], 0, "不超预算无惩罚")


# ── 随机可复现 ───────────────────────────────────────
func _test_random_reproducible() -> void:
	print("[随机]")
	var a := MemeCombo.evaluate(_cards(["illusion", "temp"]),
		{"theme_id": "none", "rng": _rng(12345)})
	var b := MemeCombo.evaluate(_cards(["illusion", "temp"]),
		{"theme_id": "none", "rng": _rng(12345)})
	_eq(a["score"], b["score"], "同一 seed 分数可复现")
	_check(float(a["mult"]) == 0.5 or float(a["mult"]) == 2.0, "c_halluc 倍率为 0.5 或 2.0")


# ── 下一张触发两次 ───────────────────────────────────
func _test_double_next() -> void:
	print("[套娃/米生米]")
	# 米生米：rice + recursion，之后的饭卡 ×2
	var r := MemeCombo.evaluate(_cards(["rice", "recursion", "hotpot"]), {"theme_id": "none"})
	var hotpot_score := -1
	for pc in r["per_card"]:
		if str(pc["id"]) == "hotpot":
			hotpot_score = int(pc["score"])
	_eq(hotpot_score, 16 * 2, "c_rice_rec 让下一张饭卡翻倍")
	# 套娃：for + recursion，之后任意卡 ×2
	var r2 := MemeCombo.evaluate(_cards(["for_kw", "recursion", "catch_kw"]), {"theme_id": "none"})
	var catch_score := -1
	for pc in r2["per_card"]:
		if str(pc["id"]) == "catch_kw":
			catch_score = int(pc["score"])
	_eq(catch_score, 12 * 2, "c_nest 让下一张卡翻倍")
