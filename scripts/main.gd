extends Node
## 屏幕路由：主菜单 → 关卡 → 奖励 → （商店）→ 下一关 ……
##
## 流程是**线性**的，没有关卡选择界面：按顺序闯 L1~L10。
## 每一关的洗牌种子不同（run_state.start_level 里按关卡 id 派生）。

const ArenaScene := preload("res://scripts/ui/arena.gd")
const RewardScene := preload("res://scripts/ui/reward.gd")
const MenuScene := preload("res://scripts/ui/main_menu.gd")
const AiSelectScene := preload("res://scripts/ui/ai_select.gd")
const ResultScene := preload("res://scripts/ui/result_screen.gd")

var run := RunState.new()
var _current: Control = null
var _pending_level: LevelData = null
var _last_passed: bool = false
var _levels: Array[LevelData] = []


func _ready() -> void:
	_levels = LevelPool.all_levels()
	get_window().title = "代码擂台 Code Arena"
	PixelTheme.install(self)
	_show_menu()
	_maybe_capture()


func _swap(screen: Control) -> void:
	if _current != null:
		_current.queue_free()
	_current = screen
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)


# ── 界面 ─────────────────────────────────────────────
func _show_menu() -> void:
	var menu := MenuScene.new()
	menu.start_run.connect(_on_start_run)
	menu.quit_game.connect(func() -> void: get_tree().quit())
	_swap(menu)


func _show_level(level: LevelData) -> void:
	_pending_level = level
	_last_passed = false
	# 正常流程由选人界面设定；调试/直跳路径兜底给初始伙伴
	if run.ai == null:
		run.set_ai(AiPool.get_ai("deepdeek"))
	var arena := ArenaScene.new()
	arena.setup(run, level)
	arena.level_cleared.connect(_on_level_cleared)
	arena.level_failed.connect(_on_level_failed)
	arena.advance_requested.connect(_on_advance)
	_swap(arena)


func _show_reward() -> void:
	var r := RewardScene.new()
	r.setup(run)
	r.chosen.connect(_after_reward)
	_swap(r)


func _show_result(win: bool) -> void:
	var rs := ResultScreen.new()
	if win:
		rs.setup("全部评测通过", "你带着 %d 件 AI 道具闯完了 10 关评测。\n最终得分 %d ｜ 剩余算力 %d" % [
			run.items.size(), run.score, run.compute
		], [
			{"text": "再来一局", "id": "menu", "accent": true},
		])
	else:
		rs.setup("评测未通过", "本关得分 %d / 目标 %d\n可以重打本关（AI 道具保留），或者放弃本局。" % [
			run.score, _pending_level.target_score
		], [
			{"text": "重打本关", "id": "retry", "accent": true},
			{"text": "放弃本局，回到主菜单", "id": "menu"},
		])
	rs.retry.connect(_on_retry)
	rs.to_menu.connect(_show_menu)
	_swap(rs)


# ── 事件 ─────────────────────────────────────────────
func _on_start_run() -> void:
	run.reset_run()
	_show_ai_select()


## 选 AI 娘：她会被画在**每一张牌的中间**，并给一套被动
func _show_ai_select() -> void:
	var sel := AiSelectScene.new()
	sel.setup(AiPool.ai_list_for_select(run.level_index))
	sel.ai_chosen.connect(_on_ai_chosen)
	sel.cancelled.connect(_show_menu)
	_swap(sel)


func _on_ai_chosen(ai: AiData) -> void:
	run.set_ai(ai)
	_show_level(_levels[0])


## 关卡结算完成（战斗界面自己弹结果窗，这里只记账，不切屏）
func _on_level_cleared(_final_score: int) -> void:
	run.level_index += 1
	if _pending_level != null:
		run.chapter = _pending_level.chapter
	_last_passed = true


func _on_level_failed(_final_score: int) -> void:
	_last_passed = false


## 玩家在结算弹窗点了「继续」
func _on_advance() -> void:
	if _last_passed:
		_show_reward()
	else:
		_show_result(false)


func _after_reward() -> void:
	# 基础玩法没有商店与货币：奖励完直接下一关
	_go_next_level()


func _after_shop() -> void:
	_go_next_level()


func _go_next_level() -> void:
	if run.level_index >= _levels.size():
		_show_result(true)
		return
	_show_level(_levels[run.level_index])


func _on_retry() -> void:
	if _pending_level != null:
		_show_level(_pending_level)


# ─────────────────────────────────────────────────────────
#  开发用截图钩子（仅命令行带参时生效）：
##   godot --path <项目> -- --shot=arena --shotout=<绝对路径>.png
##   可选 screen：menu / arena / reward / result / flow
##                 flip / slot / hover / typing / typebreak / runresult / syntax
# ─────────────────────────────────────────────────────────
func _maybe_capture() -> void:
	var args := OS.get_cmdline_user_args()
	var screen := ""
	var out_path := ""
	for a in args:
		if a.begins_with("--shot="):
			screen = a.substr(7)
		elif a.begins_with("--shotout="):
			out_path = a.substr(10)
	if out_path.is_empty():
		return
	if screen in ["menu", "arena", "reward", "result", "flow", "flip", "slot", "hover",
			"typing", "typebreak", "runresult", "memeverify", "aiselect", "poker", "slot"]:
		run.reset_run()
		if screen == "memeverify":
			await _verify_meme()
		elif screen == "aiselect":
			_show_ai_select()
		elif screen == "reward":
			_show_reward()
		elif screen == "result":
			_show_result(true)
		elif screen == "flow":
			# 端到端：主菜单 → 关卡 → 打完 → 结算 → 继续 → 奖励
			_show_level(_levels[0])
			await get_tree().process_frame
			var arena := _current as ArenaScreen
			if arena != null:
				var lv := _levels[0]
				arena.run.score = lv.target_score
				arena.run.turn = lv.turns - 1
				arena.debug_place_card(0)
				arena.debug_place_card(1)
				arena.debug_run()
				await get_tree().create_timer(1.0).timeout
				arena.debug_click_continue()
		elif screen == "arena":
			_show_level(_levels[0])
		elif screen == "poker":
			# 目检：手里凑一对打出去，看横幅 + 筹码×倍率预估
			_show_level(_levels[0])
			await get_tree().process_frame
			var ar := _current as ArenaScreen
			if ar != null:
				ar.debug_set_hand(["H3", "D3", "S6", "C1", "S2"])
				ar.debug_place_card_id("H3")
				ar.debug_place_card_id("D3")
				await get_tree().create_timer(0.5).timeout
		elif screen == "slot":
			# 目检槽位对位：把两张卡放进槽 1、槽 2
			_show_level(_levels[0])
			await get_tree().process_frame
			var arena := _current as ArenaScreen
			if arena != null:
				arena.debug_place_card(0)
				arena.debug_place_card(1)
				await get_tree().create_timer(0.5).timeout
		elif screen == "hover":
			# 目检扇形悬停放大
			_show_level(_levels[0])
			await get_tree().process_frame
			var arena := _current as ArenaScreen
			if arena != null:
				arena.debug_hover(2)
				await get_tree().create_timer(0.6).timeout
		elif screen == "flip":
			# 翻牌目检：把第一张手牌翻到背面
			_show_level(_levels[0])
			await get_tree().process_frame
			var arena := _current as ArenaScreen
			if arena != null:
				arena.debug_flip_first()
				await get_tree().create_timer(0.6).timeout
		elif screen == "typing":
			# 打字机目检：选一张卡，等 0.25 秒（片段还没打完）时截图
			_show_level(_levels[0])
			await get_tree().process_frame
			var arena := _current as ArenaScreen
			if arena != null:
				arena.debug_place_card(0)
				await get_tree().create_timer(0.25).timeout
				print("[shot=typing] 正在打字=%s ｜ 命令行=%s" % [
					arena.debug_console_typing(), arena.debug_console_line()])
		elif screen == "typebreak":
			# 打断补全目检：第一段还没打完就选第二张卡 → 第一段必须被立刻补全
			_show_level(_levels[0])
			await get_tree().process_frame
			var arena := _current as ArenaScreen
			if arena != null:
				arena.debug_place_card(0)
				await get_tree().create_timer(0.25).timeout
				print("[shot=typebreak] 打断前 正在打字=%s ｜ 命令行=%s" % [
					arena.debug_console_typing(), arena.debug_console_line()])
				arena.debug_place_card(1)
				print("[shot=typebreak] 打断后 正在打字=%s ｜ 命令行=%s" % [
					arena.debug_console_typing(), arena.debug_console_line()])
				await get_tree().create_timer(0.25).timeout
				print("[shot=typebreak] 0.25s 后 正在打字=%s ｜ 命令行=%s" % [
					arena.debug_console_typing(), arena.debug_console_line()])
		elif screen == "runresult":
			# 运行目检：选 4 张卡 → 运行 → 看 AI 娘回应 + 分数明细
			_show_level(_levels[0])
			await get_tree().process_frame
			var arena := _current as ArenaScreen
			if arena != null:
				for i in 4:
					arena.debug_place_card(i)
				await get_tree().create_timer(1.6).timeout
				print("[shot=runresult] 运行前 命令行=%s" % arena.debug_console_line())
				arena.debug_run()
				await get_tree().create_timer(1.2).timeout
				print("[shot=runresult] 控制台日志：\n%s" % arena.debug_console_log())
		else:
			_show_menu()
	for _i in 6:
		await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err == OK:
		print("截图已保存：", out_path)
	else:
		printerr("截图失败：", err)
	get_tree().quit()


# ── ★ 梗卡机制实战验收 ─────────────────────────────────
## 三件事必须**亲眼**看到（截图 + 控制台回显），不能只读代码：
##   ① 一对：两张同点数 → 牌型/筹码/倍率正确
##   ② 同花：五张同花色 → 牌型升级
## 运行：godot --path <项目> -- --shot=memeverify --shotout=<绝对路径>.png
func _verify_meme() -> void:
	print("=== 扑克牌型实战验收 ===")

	# ── ① 一对（两张红牌）──
	_show_level(_levels[0])
	await get_tree().process_frame
	var a1 := _current as ArenaScreen
	a1.debug_set_hand(["H3", "D3", "S6", "C1", "S2"])
	a1.debug_place_card_id("H3")
	a1.debug_place_card_id("D3")
	await get_tree().create_timer(0.3).timeout
	var pair := a1.debug_hand_eval()
	print("[① 一对] 牌型=%s 筹码=%d 倍率=%d 得分=%d（期望 一对 16×10=160）" % [
		str(pair["type_name"]), int(pair["chips"]), int(pair["mult"]), int(pair["score"])])
	await _shot("res://docs/shots/poker-pair-verify.png")

	# ── ② 同花（五张红心）──
	_show_level(_levels[0])
	await get_tree().process_frame
	var a2 := _current as ArenaScreen
	a2.debug_set_hand(["H1", "H3", "H5", "H7", "H9"])
	for cid in ["H1", "H3", "H5", "H7", "H9"]:
		a2.debug_place_card_id(cid)
	await get_tree().create_timer(0.3).timeout
	var flush := a2.debug_hand_eval()
	print("[② 同花] 牌型=%s 筹码=%d 倍率=%d 得分=%d（期望 同花）" % [
		str(flush["type_name"]), int(flush["chips"]), int(flush["mult"]), int(flush["score"])])
	await _shot("res://docs/shots/poker-flush-verify.png")
	print("=== 验收结束 ===")


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		print("截图已保存：", path)
	else:
		printerr("截图失败：", err)


# ── 测试/调试接口 ─────────────────────────────────────
## 当前挂载的界面数量。正常情况下任何时刻都应恒为 1——
## 旧界面没被 queue_free 掉就会 >1（界面会互相叠加、内存泄漏）。
func debug_screen_count() -> int:
	var n := 0
	for c in get_children():
		if c is Control:
			n += 1
	return n


## 测试用：直接跳到某个界面
func debug_show(screen: String) -> void:
	match screen:
		"menu":
			_show_menu()
		"arena":
			_show_level(_levels[0])
		"reward":
			_show_reward()
		"result":
			_show_result(true)
