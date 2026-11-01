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
const MapScene := preload("res://scripts/ui/map_screen.gd")
const EventScene := preload("res://scripts/ui/event_screen.gd")
const RiftScene := preload("res://scripts/ui/rift_transition.gd")
const ChibiRigScene := preload("res://scripts/ui/chibi_rig.gd")

var run := RunState.new()
var _current: Control = null
var _pending_level: LevelData = null
var _last_passed: bool = false
var _levels: Array[LevelData] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--mute":
			AudioServer.set_bus_mute(0, true)
	_levels = LevelPool.all_levels()
	get_window().title = "代码擂台 Code Arena"
	PixelTheme.install(self)
	GameSettings.load_from_disk()
	# 实测调参器（Dev 工具，不进玩法）：F1 开关面板，F5 存 docs/ui-tune.json
	var tuner := UiTuner.new()
	add_child(tuner)
	for a in OS.get_cmdline_user_args():
		if a == "--tune":
			tuner.open()
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
	# 主人 2026-10-30：启动界面重做为「初始化 → Agent 对话框」流程（旧菜单 --oldmenu 保留）
	if not OS.get_cmdline_user_args().has("--oldmenu"):
		_show_launch()
		return
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
	# 裂隙转场（2026-11-01 主人钦定）：黑幕→中央裂纹向上下张开→左右分开露出奖励
	if DisplayServer.get_name() != "headless":
		r.add_child(RiftScene.new())


func _show_result(win: bool) -> void:
	var rs := ResultScreen.new()
	if win:
		rs.setup("全部战斗胜利", "你带着 %d 张卡（%d 件 AI 道具）闯完了 10 场战斗。
累计伤害 %d ｜ 剩余算力 %d" % [
			run.deck.size(), run.items.size(), run.score, run.compute
		], [
			{"text": "再来一局", "id": "menu", "accent": true},
		])
	else:
		rs.setup("战败", "倒在【%s】面前。
可以重打本场（卡组保留），或者放弃本局。" % [
			_pending_level.enemy_name
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
	# 主人要求的新版选角：楼梯秀场（demo）。默认走旧界面，--stairs 切新版
	if OS.get_cmdline_user_args().has("--stairs"):
		_show_stairs()
		return
	var sel := AiSelectScene.new()
	sel.setup(AiPool.ai_list_for_select(run.level_index))
	sel.ai_chosen.connect(_on_ai_chosen)
	sel.cancelled.connect(_show_menu)
	_swap(sel)


## 新启动流程：黑屏「初始化」按钮 → Agent 对话框选模型 → 发送进游戏。
## launched 带回模型 id，照旧走 reset_run + 进第一关（终端进场照旧触发）。
func _show_launch() -> void:
	var sc := LaunchScreen.new()
	sc.launched.connect(func(ai_id: String) -> void:
		sc.queue_free()
		run.reset_run()
		var ai := AiPool.get_ai(ai_id)
		if ai == null:
			ai = AiPool.get_ai("deepdeek")
		run.set_ai(ai)
		_show_level(_levels[0]))
	_swap(sc)


## 楼梯选角 demo：3D 楼梯 + 仰视相机，四位 AI 娘分立两侧待选。
## 确认后仍然走原来的 _on_ai_chosen 流程，不影响后续进场/战斗。
func _show_stairs() -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	var sc := SelectStairs.new()
	sc.selected.connect(func(ai_id: String) -> void:
		sc.queue_free()
		_on_ai_chosen(AiPool.get_ai(ai_id)))
	add_child(sc)


func _on_ai_chosen(ai: AiData) -> void:
	run.set_ai(ai)
	_show_level(_levels[0])


## 关卡结算完成（战斗界面自己弹结果窗，这里只记账，不切屏）
func _on_level_cleared(_final_score: int) -> void:
	run.level_index += 1
	run.events_since_battle = 0   ## 事件门冷却重置
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
	_show_map()


## 选关界面（战斗 / 事件节点）
## 选关界面（门选制）：每次到达掷一次遭遇——50% 战斗 / 40% 事件 / 10% 奖励关
## 战斗门常驻；事件门与奖励门按概率出现（主人 2026-11-01 概率表）
func _show_map() -> void:
	if run.level_index >= _levels.size():
		_show_result(true)
		return
	var roll := run.rng.randf()
	var special := ""
	if roll < 0.10:
		special = "bonus"
	elif roll < 0.50:
		special = "event"
	var m := MapScene.new()
	m.setup(run, special)
	m.battle_entered.connect(_on_battle_door)
	m.event_entered.connect(_on_event_door)
	m.bonus_entered.connect(_show_bonus)
	_swap(m)


## 奖励关：开宝箱得一件道具
func _show_bonus() -> void:
	var b := BonusScreen.new()
	b.setup(run)
	b.finished.connect(_show_map)
	_swap(b)


func _on_battle_door() -> void:
	_show_level(_levels[run.level_index])


func _on_event_door() -> void:
	_show_event(0)


## 事件节点
func _show_event(event_index: int) -> void:
	var e := EventScene.new()
	e.setup(run, event_index)
	e.finished.connect(_on_event_finished)
	_swap(e)


func _on_event_finished() -> void:
	run.events_since_battle += 1
	_show_map()


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
	if screen in ["menu", "arena", "battle", "intro", "reward", "result",
			"menuhover", "rig", "rigwalk", "loadrun", "card", "cardtext", "cardcost", "terminal", "termgif",
			"termdump", "hero", "stairs", "launch", "launch2", "arenalayout", "sendtest", "ricetest"]:
		run.reset_run()
		if screen == "launch" or screen == "launch2":
			var sc := _current as LaunchScreen
			if sc == null:
				sc = LaunchScreen.new()
				_swap(sc)
			if screen == "launch2":
				sc.expand()
			await get_tree().create_timer(1.0).timeout
			get_viewport().get_texture().get_image().save_png(out_path)
			print("[shot=%s] 已存 → %s" % [screen, out_path])
			get_tree().quit()
			return
		if screen == "stairs":
			await _capture_stairs(out_path)
			return
		if screen == "hero":
			# 只验「终端 → Godot 立绘」这一段：假造终端排版，抓 4 帧看马赛克收敛与对齐。
			# 配套参数：--nointro（跳过真实进场）
			await _capture_hero_mosaic(out_path)
			return
		if screen == "termdump":
			# 只生成 .ps1 + 字符画文本，**不启动终端**：给宿主侧做语法/尺寸自检
			_capture_term_dump(out_path)
			return
		if screen == "rig":
			# 目检：Q 版角色 walk 的第 0/1/2/3 帧 → 2×2 拼图
			await _capture_rig(out_path)
			return
		if screen == "rigwalk":
			# 动图：真实播放 walk，24fps 采样 → .tmp/riggif/ 48 张 PNG（ffmpeg 拼 GIF 用）
			await _capture_rig_walk(out_path)
			return
		if screen == "loadrun":
			# 演示：进入游戏进度条 + Q 版角色跟着填充边缘跑 → .tmp/loadrun/ PNG 序列
			await _capture_loadrun(out_path)
			return
		if screen == "ricetest":
			# 验收白米饭成长：喂满 2 碗 → 伙伴换成「有点睡醒」+ HUD 显示增益
			_show_ai_select()
			if _current != null:
				_current.queue_free()
				_current = null
			_show_level(_levels[0])
			await get_tree().create_timer(1.2).timeout
			var arr := _current as ArenaScreen
			if arr != null:
				arr.debug_feed_rice(2)
				await get_tree().create_timer(1.2).timeout
				print("[shot=ricetest] 白米饭=%d 醒=%s" % [
					arr.combat.rice_eaten, str(arr.combat.is_awake())])
			_shot(out_path)
			print("[shot=ricetest] 已存 → %s" % out_path)
			get_tree().quit()
			return
		if screen == "sendtest":
			# 验收「点发送后手牌尺寸」：打一整手 → 补牌 → 再截图，牌应与开局同样大
			_show_ai_select()
			if _current != null:
				_current.queue_free()
				_current = null
			_show_level(_levels[0])
			await get_tree().create_timer(1.2).timeout
			var ar := _current as ArenaScreen
			if ar != null:
				ar._on_send_pressed()
				await get_tree().create_timer(2.4).timeout
				var sc0 := ar.debug_hand_scale()
				print("[shot=sendtest] 补牌后首张 scale=%s 手牌=%d" % [
					str(sc0), ar.debug_hand_count()])
			_shot(out_path)
			print("[shot=sendtest] 已存 → %s" % out_path)
			get_tree().quit()
			return
		if screen == "aiselect" or screen == "arenalayout":
			# arenalayout：验收战斗区新布局（侧边栏拉满 + 底部对话框 + AI 娘右端）
			_show_ai_select()
			if screen == "arenalayout":
				if _current != null:
					_current.queue_free()
					_current = null
				_show_level(_levels[0])
				await get_tree().create_timer(1.4).timeout
				var ar := _current as ArenaScreen
				if ar != null:
					print("[shot=arenalayout] %s" % ar.debug_layout_rects())
				_shot(out_path)
				print("[shot=arenalayout] 已存 → %s" % out_path)
				get_tree().quit()
		elif screen == "reward":
			_show_reward()
		elif screen == "result":
			_show_result(true)
		elif screen == "termgif":
			# 动图采帧：12fps 抓 5.8 秒 → .tmp/termgif/*.png（ffmpeg 拼 GIF）
			_show_level(_levels[0])
			DirAccess.make_dir_recursive_absolute("res://.tmp/termgif")
			var fps := 12
			for i in int(5.8 * fps):
				var img := get_viewport().get_texture().get_image()
				img.save_png("res://.tmp/termgif/f%03d.png" % i)
				await get_tree().create_timer(1.0 / float(fps)).timeout
			print("[shot=termgif] 采帧完成")
		elif screen == "terminal":
			# 终端进场三相：代码打字中 / 字符画扫描中 / 完成
			_show_level(_levels[0])
			for st in [1.1, 3.0, 4.3]:
				await get_tree().create_timer(st - (0.0 if st == 1.1 else (1.1 if st == 3.0 else 3.0))).timeout
				get_viewport().get_texture().get_image().save_png(
						_outname(out_path, "terminal", "t%d" % int(st * 10)))
		elif screen in ["card", "cardtext", "cardcost"]:
			# 验收钩子：两张卡画在**已知坐标**（40,40）/（240,40），便于像素级量文字墨迹中心。
			# 布局框居中 ≠ 字形居中（描边上下不对称），肉眼验收容易放过，这里给个可量的靶。
			var probe := Control.new()
			probe.set_anchors_preset(Control.PRESET_FULL_RECT)
			var pbg := ColorRect.new()
			pbg.color = Color("#0b0f18")
			pbg.set_anchors_preset(Control.PRESET_FULL_RECT)
			probe.add_child(pbg)
			var ids := ["fish_ram", "taunt"]
			var text_only := screen == "cardtext" or screen == "cardcost"
			for i in ids.size():
				var cv := StsCardView.new()
				cv.setup(StsCardPool.card(ids[i]))
				cv.position = Vector2(40 + i * 200, 40)
				if text_only:
					# 只留文字层：藏掉框与立绘，墨迹测量不受污染
					for ch in cv.get_children():
						if ch is TextureRect:
							(ch as TextureRect).visible = false
						elif screen == "cardcost" and ch is Label and (ch as Label).name != "CostOrb":
							(ch as Label).visible = false
				probe.add_child(cv)
			_swap(probe)
		elif screen == "intro":
			# 实测转场：中段（3D 翻飞中）存一张 -mid，结尾（落回 2D）存主文件
			_show_level(_levels[0])
			await get_tree().create_timer(0.85).timeout
			var mid := get_viewport().get_texture().get_image()
			mid.save_png(_outname(out_path, "intro", "mid"))
			await get_tree().create_timer(1.6).timeout
		elif screen == "battle":
			# 目检：进战斗打一张牌，看敌人受击特效与战斗日志
			_show_level(_levels[0])
			await get_tree().process_frame
			var arena_shot := _current as ArenaScreen
			if arena_shot != null:
				arena_shot.debug_play_card(0)
				await get_tree().create_timer(0.6).timeout
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


# ── Q 版角色骨架目检 ─────────────────────────────────────────
## 出三张图：
##   <shotout>            8 帧横排（循环 4 帧 + 下一循环 4 帧），叠脚底地线
##   <shotout>-sheet      2×2、放大 2 倍（验接缝 / 肩部豁口）
##   <shotout>-legs       只裁腿+裙摆下沿、放大 4 倍、4 帧横排
##   <shotout>-legs-12x   同上但 12 倍（审核要求：证明 f1/f3 真的不同）
## 另外往 .tmp/rig/rig-static.png 存静止姿态，并和 cutout.png 逐像素对比。
const RIG_DIR := "res://assets/art/rig/deepdeek"
const RIG_CUT := "res://assets/art/rig/deepdeek/cutout.png"
const RIG_CANVAS := Vector2i(192, 256)
const RIG_BAND := 26     # 每格上方的帧号条
const RIG_PAD := 6       # 每格左右留白
const RIG_BPAD := 16     # 每格底部留白（影子会画出画布下沿）
const RIG_BG := Color("#232a3a")
const RIG_GROUND := Color("#6b7796")
const RIG_SPLIT := Color("#2e3648")
## 腿部专图的裁剪窗口（画布坐标）：x 62..124、y 206..257 = 审核给的 strip（68..130, 232..283）减去格内偏移
const LEG_RECT := Rect2i(62, 206, 62, 51)
const LEG_RECT4 := Rect2i(52, 216, 84, 52)


## 楼梯选角 demo 截图验收：
##   godot --path <项目> -- --shot=stairs --shotout=<绝对路径>.png
func _capture_stairs(out_path: String) -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	var sc := SelectStairs.new()
	add_child(sc)
	await get_tree().create_timer(0.9).timeout
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[shot=stairs] 已存 → %s" % out_path)
	get_tree().quit()


## 定点验收「终端 → Godot 立绘」：假造一份终端排版（全屏 179x56 格、50 行字符画、居中），
## 然后抓 4 帧看马赛克是否收敛、矩形是否落在预期位置。配套 --nointro。
##   godot --path <项目> -w --resolution 1600x1000 -- --shot=hero --nointro --shotout=<绝对路径>.png
func _capture_hero_mosaic(out_path: String) -> void:
	var geom := "cols=179,rows=56,padx=49,pady=6,artw=80,arth=44,capx=81,capy=51"
	var gf := FileAccess.open(OS.get_temp_dir().path_join("arena_term_geom.txt"), FileAccess.WRITE)
	if gf == null:
		print("[shot=hero] 几何文件写不进去")
		get_tree().quit(1)
		return
	gf.store_string(geom)
	gf.close()

	_show_level(_levels[0])
	await get_tree().process_frame
	await get_tree().process_frame
	var arena := _current as ArenaScreen
	if arena == null:
		print("[shot=hero] 没拿到 ArenaScreen")
		get_tree().quit(1)
		return
	var tex := load("res://assets/art/rig/deepdeek-front/front-hi.png") as Texture2D
	if tex == null:
		print("[shot=hero] 立绘没读到")
		get_tree().quit(1)
		return
	arena._show_hero_portrait(tex, func() -> void: pass)
	# 立刻停住：不然后续每一帧都会推进，拍不到首帧
	if arena._hero_tween != null:
		arena._hero_tween.pause()
	await get_tree().process_frame      ## 这一帧把着色器编译掉（tween 已停，画面不变）
	var dbg := arena.get_node_or_null("HeroPortrait") as TextureRect
	var sym := arena.get_node_or_null("HeroSymbol") as SymbolFrame
	print("[shot=hero] 节点检查: portrait=%s symbol=%s" % [dbg != null, sym != null])
	if dbg != null:
		var dm := dbg.material as ShaderMaterial
		print("[shot=hero] 首帧 block=%.2f alpha=%.2f size=%s" % [
			float(dm.get_shader_parameter("block")), float(dm.get_shader_parameter("alpha")),
			str(dbg.size)])
	get_viewport().get_texture().get_image().save_png(_outname(out_path, "hero", "f0"))
	# 解冻，每 0.45s 一张：0.35 保留 → 0.35~1.25 解码 → 1.25~3.45 上色 → 3.45~4.85 收细
	arena._hero_tween.play()
	for i in range(1, 12):
		await get_tree().create_timer(0.45, true, false, true).timeout
		get_viewport().get_texture().get_image().save_png(
				_outname(out_path, "hero", "f%d" % i))
		if dbg != null:
			var m2 := dbg.material as ShaderMaterial
			print("  f%d t=%.2fs block=%.2f alpha=%.2f 解码=%.2f" % [i, i * 0.45,
				float(m2.get_shader_parameter("block")),
				float(m2.get_shader_parameter("alpha")),
				sym._shuffle if sym != null else -1.0])
	print("[shot=hero] 12 帧已存（首帧为纯符号帧）几何=%s" % geom)
	get_tree().quit()


## 只把终端脚本 + 字符画落盘（不启动终端），给宿主侧做语法与尺寸自检：
##   godot --path <项目> --headless -- --shot=termdump --shotout=<绝对路径>.txt
func _capture_term_dump(out_path: String) -> void:
	var ai_id := "deepdeek"
	var ai_name := "DeepDeek"
	if run != null and run.ai != null:
		ai_id = run.ai.id
		ai_name = run.ai.display_name
	var tex := load("res://assets/art/rig/%s-front/front-hi.png" % ai_id) as Texture2D
	var art := AsciiArt.build(tex, ExtTerminal.ART_ROWS, ExtTerminal.ART_MAX_COLS,
			ExtTerminal.CELL_ASPECT)
	if art.is_empty():
		print("[shot=termdump] 字符画为空：图没读到？")
		get_tree().quit(1)
		return
	var wmax := 0
	for l in art:
		wmax = maxi(wmax, l.length())
	var et := ExtTerminal.new()
	var body := et._compose(ai_name, IntroScript.code_for(ai_id, ai_name), art)
	et.free()
	var base := out_path.get_basename()
	# .ps1 必须带 UTF-8 BOM（和生产路径 ExtTerminal.play 一致），
	# 否则 PS 5.1 按系统 ANSI 解码，中文注释全变乱码——自检也就白验了
	for pair in [[base + ".txt", "\n".join(art) + "\n", false], [base + ".ps1", body, true]]:
		var f := FileAccess.open(pair[0], FileAccess.WRITE)
		if f != null:
			if bool(pair[2]):
				f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
			f.store_string(pair[1])
			f.close()
	print("[shot=termdump] %d 行 / 最宽 %d 列 → %s.ps1" % [art.size(), wmax, base])
	get_tree().quit()


func _capture_rig(out_path: String) -> void:
	var sheet_path := _outname(out_path, "strip", "sheet")
	var legs_path := _outname(out_path, "strip", "legs")
	var legs12_path := _outname(out_path, "strip", "legs-12x")

	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_swap(host)

	var bg := ColorRect.new()
	bg.color = RIG_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	var rig: ChibiRig = ChibiRigScene.new()
	rig.position = Vector2(160, 180)
	host.add_child(rig)
	rig.setup(RIG_DIR)
	rig.set_speed(0.0)

	var tag := Label.new()
	tag.add_theme_font_size_override("font_size", 18)
	tag.add_theme_color_override("font_color", Color("#9fb0d8"))
	host.add_child(tag)

	# ── 静止姿态：和 cutout.png 逐像素对比，确认切件对位 ──
	for _k in 6:
		await get_tree().process_frame
	var still := _grab_viewport()
	print("[shot=rig] 静止对位自检：%s" % _rig_static_check(still, rig.position))
	DirAccess.make_dir_recursive_absolute("res://.tmp/rig")
	_crop(still, rect_of(rig.position, 1)).save_png("res://.tmp/rig/rig-static.png")

	# ── 亚帧检查：帧与帧之间取 32 个采样点，确认腿不会被插值压到地线以下 ──
	# （用 CUBIC 的话这里会读到 dy≈+1.2，支撑脚在中间帧穿地；腿轨已改 LINEAR）
	var worst := 0.0
	for k in 32:
		var p := rig.debug_seek_walk(float(k) / 8.0)
		for nm in ["leg_l", "leg_r"]:
			worst = maxf(worst, float(p.get("dy_" + nm, 0.0)))
	print("[shot=rig] 亚帧检查：腿的最大下沉 dy=%.2f（>0 就是穿地）" % worst)

	# ── ① 8 帧横排（1x）：循环 4 帧 + 下一循环 4 帧 ──
	var cw := RIG_CANVAS.x + RIG_PAD * 2
	var ch := RIG_BAND + RIG_CANVAS.y + RIG_BPAD
	var strip := Image.create_empty(cw * 8, ch, false, Image.FORMAT_RGBA8)
	strip.fill(RIG_BG)
	var cells: Array[Image] = []
	for i in 8:
		tag.text = "f%d" % i
		tag.position = rig.position + Vector2(-RIG_PAD + 6, -RIG_BAND + 2)
		var pose := rig.debug_seek_walk(i)
		for _k in 3:
			await get_tree().process_frame
		var img := _crop(_grab_viewport(), rect_of(rig.position, 1))
		# 拼到第 i 格；seek 内部走 fposmod → 第 4..7 帧就是下一次循环
		strip.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * cw, 0))
		if i < 4:
			cells.append(img)
		print("[shot=rig] f%d %s" % [i, str(pose)])
	# 地线 + 分格线：沿整条图直线画过去，任何一帧脚离地都看得见
	var sole_y := RIG_BAND + RIG_CANVAS.y
	for x in strip.get_width():
		strip.set_pixel(x, sole_y, RIG_GROUND)
		strip.set_pixel(x, sole_y + 1, RIG_GROUND.darkened(0.55))
	for i in range(1, 8):
		for y in ch:
			strip.set_pixel(i * cw, y, RIG_SPLIT)
	strip.save_png(out_path)

	# ── ② 2×2 放大 2 倍（4 帧）：看部件接缝 / 肩部 ──
	rig.scale = Vector2(2, 2)
	rig.position = Vector2(60, 60)
	tag.add_theme_font_size_override("font_size", 22)
	var cw2 := RIG_CANVAS.x * 2 + RIG_PAD * 2
	var ch2 := RIG_BAND + RIG_CANVAS.y * 2 + RIG_BPAD
	var sheet := Image.create_empty(cw2 * 2, ch2 * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(RIG_BG)
	for i in ChibiRigScene.WALK_FRAMES:
		tag.text = "f%d  2x" % i
		tag.position = rig.position + Vector2(-RIG_PAD + 6, -RIG_BAND + 2)
		rig.debug_seek_walk(i)
		for _k in 3:
			await get_tree().process_frame
		var img := _crop(_grab_viewport(), rect_of(rig.position, 2))
		var col := i % 2
		var row := i / 2
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i(col * cw2, row * ch2))
	var sole2 := RIG_BAND + RIG_CANVAS.y * 2
	for i in 4:
		var gx := (i % 2) * cw2
		var gy := (i / 2) * ch2 + sole2
		for x in range(gx, gx + cw2):
			sheet.set_pixel(x, gy, RIG_GROUND)
			sheet.set_pixel(x, gy + 1, RIG_GROUND.darkened(0.55))
	for y in ch2 * 2:
		sheet.set_pixel(cw2, y, RIG_SPLIT)
	for y in ch2:
		sheet.set_pixel(cw2, y, RIG_SPLIT)
	sheet.save_png(sheet_path)

	# ── ③④ 腿部专图（4x / 12x）：证明 f1 与 f3 的腿真的不同 ──
	var m4 := _leg_montage(cells, LEG_RECT4, 4)
	m4.save_png(legs_path)
	var m12 := _leg_montage(cells, LEG_RECT, 12)
	m12.save_png(legs12_path)

	# ── 数字自检（影子关掉再量，别让影子的缩放混进腿部差异）──
	var sh := rig.get_node_or_null("Root/Shadow") as CanvasItem
	if sh != null:
		sh.visible = false
	var plain: Array[Image] = []
	for i in ChibiRigScene.WALK_FRAMES:
		rig.debug_seek_walk(i)
		for _k in 2:
			await get_tree().process_frame
		plain.append(_crop(_grab_viewport(), rect_of(rig.position, 2)))
	if sh != null:
		sh.visible = true
	var leg_rect2 := Rect2i(Vector2i(RIG_PAD + LEG_RECT.position.x * 2, RIG_BAND + LEG_RECT.position.y * 2),
			LEG_RECT.size * 2)
	var pairs := []
	for i in 4:
		for j in range(i + 1, 4):
			pairs.append("f%d/f%d=%d" % [i, j, _xor_px(plain[i], plain[j], leg_rect2)])
	print("[shot=rig] 腿部区域两两 XOR（2x，%d 个采样像素）：%s" % [
		leg_rect2.size.x * leg_rect2.size.y, "  ".join(pairs)])
	var tops := []
	for i in 4:
		tops.append((_top_ink_row(plain[i], RIG_BAND, Vector2i(RIG_PAD + 20, RIG_PAD + 172)) - RIG_BAND) / 2)
	print("[shot=rig] 头顶 y（画布坐标）：%s  极差=%d" % [str(tops), tops.max() - tops.min()])
	print("横排已保存：%s（%dx%d）" % [out_path, strip.get_width(), strip.get_height()])
	print("放大图已保存：%s（%dx%d）" % [sheet_path, sheet.get_width(), sheet.get_height()])
	print("腿部4x已保存：%s（%dx%d）" % [legs_path, m4.get_width(), m4.get_height()])
	print("腿部12x已保存：%s（%dx%d）" % [legs12_path, m12.get_width(), m12.get_height()])
	get_tree().quit()


func _outname(path: String, from_tag: String, to_tag: String) -> String:
	var p := path.replace("-" + from_tag, "-" + to_tag)
	if p == path:
		p = path.get_basename() + "-" + to_tag + ".png"
	return p


## 把一个画布区域的 4 帧裁出来、放大 zoom 倍、横排；每格上方带帧号（从单元格里裁的）。
func _leg_montage(cells: Array, canvas_rect: Rect2i, zoom: int) -> Image:
	var w := canvas_rect.size.x * zoom
	var h := canvas_rect.size.y * zoom
	var gap := 8
	var out := Image.create_empty(gap + cells.size() * (w + gap), 26 + h + gap, false, Image.FORMAT_RGBA8)
	out.fill(RIG_BG)
	var src := Rect2i(canvas_rect.position + Vector2i(RIG_PAD, RIG_BAND), canvas_rect.size)
	var line_y := 26 + (RIG_CANVAS.y - canvas_rect.position.y) * zoom
	for i in cells.size():
		var cell: Image = cells[i]
		var part := cell.get_region(src)
		part.resize(w, h, Image.INTERPOLATE_NEAREST)
		var ox := gap + i * (w + gap)
		out.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(ox, 26))
		var lab := cell.get_region(Rect2i(2, 2, 56, 22))
		out.blit_rect(lab, Rect2i(Vector2i.ZERO, lab.get_size()), Vector2i(ox + 2, 2))
		for x in range(ox - gap, ox):
			for y in out.get_height():
				out.set_pixel(x, y, RIG_SPLIT)
	if line_y >= 0 and line_y < out.get_height():
		for x in out.get_width():
			out.set_pixel(x, line_y, RIG_GROUND)
			if line_y + 1 < out.get_height():
				out.set_pixel(x, line_y + 1, RIG_GROUND.darkened(0.55))
	return out


## ── walk 动图抓帧 ────────────────────────────────────────────
## --shot=rigwalk：真实播放 walk，24fps 采样（walk 8fps × 每帧 3 个亚帧，含插值姿态），
## 抓 2 个循环 = 48 张 PNG 到 res://.tmp/riggif/，交给 ffmpeg 拼成 GIF。
## 姿态走 debug_seek_walk(帧号/3.0) 逐拍定格——和真实播放逐帧等价，但不会漏采样。
func _capture_rig_walk(out_path: String) -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_swap(host)

	var bg := ColorRect.new()
	bg.color = RIG_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	var rig: ChibiRig = ChibiRigScene.new()
	rig.scale = Vector2(2, 2)
	# 2x 画布 384×512，窗口 720 高：top=60 → 脚底 572，影子（到画布 y≈260）不裁
	rig.position = Vector2(200, 60)
	host.add_child(rig)
	rig.setup(RIG_DIR)
	rig.play("walk")

	# 地线垫在角色后面（树序：bg → ground → rig），脚踩在线上看得更清
	var ground_y := int(rig.position.y) + RIG_CANVAS.y * 2
	var ground := ColorRect.new()
	ground.color = RIG_GROUND
	ground.position = Vector2(0, ground_y)
	ground.size = Vector2(4096, 2)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(ground)
	host.move_child(ground, 1)

	var out_dir := "res://.tmp/riggif"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var fps := 24
	var frames := fps * 2   # 2 个循环
	for i in frames:
		rig.debug_seek_walk(float(i) * ChibiRigScene.WALK_FPS / float(fps))
		for _k in 3:
			await get_tree().process_frame
		var crop := Rect2i(Vector2i(rig.position) - Vector2i(20, 16),
				Vector2i(RIG_CANVAS.x * 2 + 40, RIG_CANVAS.y * 2 + 64))
		_crop(_grab_viewport(), crop).save_png("%s/w%03d.png" % [out_dir, i])
	print("[shot=rigwalk] %d 张已保存：%s（fps=%d，时长 %.2f 秒）→ 用 ffmpeg 拼 GIF" % [
		frames, out_dir, fps, float(frames) / fps])


## ── 进入游戏进度条 + Q 版跑动 演示 ──────────────────────────
## --shot=loadrun：进度条 0→100%（4 秒），Q 版 DeepSeek 用 run 动作跟着填充边缘跑。
## 24fps 抓 96 张 PNG 到 res://.tmp/loadrun/，ffmpeg 拼 GIF。
## 确定性抓帧：每帧直接 set_value + debug_seek("run", t*RUN_FPS)，和真实播放逐帧等价。
const LOADRUN_BAR := Rect2(280, 590, 720, 80)   ## 进度条位置与尺寸（720x80 = 资产 360x40 ×2）
const LOADRUN_SCALE := 0.6                       ## 角色显示缩放（0.6 = 115×154）
const LOADRUN_FPS := 24
const LOADRUN_SECS := 4.0
const LOADRUN_RIG := "res://assets/art/rig/deepdeek-side"       ## 侧面切件（面朝右）
const LOADRUN_FRONT := "res://assets/art/rig/deepdeek-front/front.png"   ## 正面精灵（备用：平面 twirl 不再用，留给以后多视角方案）
## 跳舞转圈窗口（进度区间）：经过时边前进边自转一圈，期间条继续走
const DANCE_WINDOWS := [Vector2(0.26, 0.48), Vector2(0.60, 0.82)]
## 8 视角旋转序列（turnaround sheet 切片；s0=正面 … s4=背面 … 顺时针 45°/帧）
const SPIN_DIR := "res://assets/art/rig/deepdeek-spin"
const SPIN_FRAMES := 8
## LoadBar 内槽的显示坐标（SLOT 常量 ×2 + bar 位置）
const LOADRUN_SLOT := Rect2(40, 26, 640, 28)     ## 相对 bar 左上角的内槽矩形


func _capture_loadrun(out_path: String) -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_swap(host)

	var bg := ColorRect.new()
	bg.color = Color("#10141f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	# 标题（进度条上方，抬高避开跳舞的角色）
	var title := Label.new()
	title.text = "进入游戏"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#9fb0d8"))
	title.position = Vector2(LOADRUN_BAR.position.x, LOADRUN_BAR.position.y - 116)
	host.add_child(title)

	# 生图进度条（track 框 + 引擎填充）
	var bar := LoadBar.new()
	bar.position = LOADRUN_BAR.position
	host.add_child(bar)

	# Q 版角色：挂在「舞者 wrapper」下，画布中心对齐 wrapper 原点，
	# 这样旋转/缩放/位移全部绕身体中心，跑步与跳舞共用一套定位。
	var rig: ChibiRig = ChibiRigScene.new()
	rig.setup(LOADRUN_RIG)
	rig.play("run")

	# 舞者 wrapper：跳舞时绕「腰轴」做平面内整体旋转（twirl）。
	var dancer := Node2D.new()
	dancer.name = "Dancer"
	host.add_child(dancer)
	rig.position = Vector2(-RIG_CANVAS.x * 0.5, -RIG_CANVAS.y * 0.5)
	dancer.add_child(rig)
	var rig_shadow := rig.get_node_or_null("Root/Shadow") as CanvasItem

	# 自转序列帧精灵（8 视角；只在跳舞窗口显示，替掉 rig）
	var spin_frames: Array[Texture2D] = []
	for k in SPIN_FRAMES:
		spin_frames.append(load("%s/s%d.png" % [SPIN_DIR, k]) as Texture2D)
	var spin := Sprite2D.new()
	spin.name = "Spin"
	spin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 帧画布 192x256、脚底在 y=248 → 节点原点 = 脚底中心
	spin.centered = false
	spin.offset = Vector2(-96, -248)
	spin.scale = Vector2.ONE * LOADRUN_SCALE
	spin.visible = false
	host.add_child(spin)

	var out_dir := "res://.tmp/loadrun"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var frames := int(LOADRUN_FPS * LOADRUN_SECS)
	for i in frames:
		var t := float(i) / float(frames - 1)          ## 0..1
		var v := minf(t * 1.06, 1.0)                   ## 前 94% 走完，结尾停一小拍
		bar.set_value(v)
		var edge := LOADRUN_BAR.position.x + LOADRUN_SLOT.position.x + LOADRUN_SLOT.size.x * v

		# ── 跳舞：8 视角序列帧自转（竖轴旋转，身体始终直立），边前进边转 ──
		#   进度进入窗口 → 用角度帧轮播一整圈（s0 正 → s2 侧 → s4 背 → s6 侧 → 回s0）；
		#   期间进度条不停（边走边转），落地带轻微上下弹。
		var in_dance := false
		var dance_p := 0.0
		for w: Vector2 in DANCE_WINDOWS:
			if v >= w.x and v <= w.y:
				in_dance = true
				dance_p = (v - w.x) / (w.y - w.x)
		if in_dance:
			rig.visible = false
			spin.visible = true
			spin.texture = spin_frames[mini(int(dance_p * SPIN_FRAMES), SPIN_FRAMES - 1)]
			var hop := -absf(sin(dance_p * PI * 4.0)) * 6.0     ## 转圈时的小弹跳
			spin.position = Vector2(edge, LOADRUN_BAR.position.y + hop)
		else:
			rig.visible = true
			spin.visible = false
			dancer.position = Vector2(edge, LOADRUN_BAR.position.y - 126.0 * LOADRUN_SCALE)
			dancer.rotation = 0.0
			dancer.scale = Vector2.ONE * LOADRUN_SCALE
			if rig_shadow != null:
				rig_shadow.visible = true
			rig.debug_seek("run", t * LOADRUN_SECS * ChibiRig.RUN_FPS)
		for _k in 3:
			await get_tree().process_frame
		# 裁剪带：只留角色 + 进度条附近（GIF 体积友好）
		var crop := Rect2i(160, int(LOADRUN_BAR.position.y) - 200, 960, 300)
		_crop(_grab_viewport(), crop).save_png("%s/l%03d.png" % [out_dir, i])
	print("[shot=loadrun] %d 张已保存：%s（fps=%d，时长 %.1f 秒）→ 用 ffmpeg 拼 GIF" % [
		frames, out_dir, LOADRUN_FPS, LOADRUN_SECS])


## 一格在视口里的裁剪矩形：左 pad、上帧号条、右 pad、下 pad。
func rect_of(origin: Vector2, scale_f: int) -> Rect2i:
	return Rect2i(Vector2i(origin) - Vector2i(RIG_PAD, RIG_BAND),
			Vector2i(RIG_CANVAS.x * scale_f + RIG_PAD * 2,
					RIG_BAND + RIG_CANVAS.y * scale_f + RIG_BPAD))


func _grab_viewport() -> Image:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _crop(img: Image, r: Rect2i) -> Image:
	var rr := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	return img.get_region(rr)


## 和底色差得够远 = 有墨（角色）；影子比底色更暗，也算墨，所以量的那次要先把影子关掉。
func _is_ink(c: Color) -> bool:
	return absf(c.r - RIG_BG.r) + absf(c.g - RIG_BG.g) + absf(c.b - RIG_BG.b) > 0.047


func _xor_px(a: Image, b: Image, r: Rect2i) -> int:
	var n := 0
	for y in range(r.position.y, min(r.position.y + r.size.y, a.get_height())):
		for x in range(r.position.x, min(r.position.x + r.size.x, a.get_width())):
			if _is_ink(a.get_pixel(x, y)) != _is_ink(b.get_pixel(x, y)):
				n += 1
	return n


## 从 y0 往下扫，第一行有墨的 y（返回绝对 y）。
func _top_ink_row(img: Image, y0: int, xr: Vector2i) -> int:
	for y in range(y0, min(y0 + 320, img.get_height())):
		for x in range(xr.x, min(xr.y, img.get_width())):
			if _is_ink(img.get_pixel(x, y)):
				return y
	return -1


## 静止姿态 vs cutout.png：把 cutout 按 RIG_BG 底色合成为期望图，逐像素比。
## 全对位 → 差异像素 0；有错位/重影 → 成片差异。
func _rig_static_check(shot: Image, origin: Vector2) -> String:
	if not FileAccess.file_exists(RIG_CUT):
		return "跳过（没有 cutout.png）"
	if not FileAccess.file_exists(RIG_DIR.path_join("rig.json")):
		return "跳过（rig.json 不存在 = 跑的是占位骨架，比原图没有意义）"
	var cut := Image.load_from_file(ProjectSettings.globalize_path(RIG_CUT))
	if cut == null:
		return "跳过（cutout.png 读不出来）"
	cut.convert(Image.FORMAT_RGBA8)
	var cell := _crop(shot, rect_of(origin, 1))
	# 影子也在这个格子里，但它不参与"拼回去像不像原图"，所以只比有影子的那张会误报
	# → 这里比的是 alpha 复合后的颜色，影子在 8 件之外，需要先排除掉
	var got := _crop(cell, Rect2i(Vector2i(RIG_PAD, RIG_BAND), RIG_CANVAS))
	var bad := 0
	var worst := 0
	for y in RIG_CANVAS.y:
		for x in RIG_CANVAS.x:
			var c := cut.get_pixel(x, y)
			var want := Color(
				c.r * c.a + RIG_BG.r * (1.0 - c.a),
				c.g * c.a + RIG_BG.g * (1.0 - c.a),
				c.b * c.a + RIG_BG.b * (1.0 - c.a))
			var g := got.get_pixel(x, y)
			# 原图透明的地方，影子可能盖上来 → 只比原图不透明的位置
			if c.a < 0.5:
				continue
			var d := maxf(absf(want.r - g.r), maxf(absf(want.g - g.g), absf(want.b - g.b)))
			if d > 0.04:
				bad += 1
				worst = maxi(worst, int(d * 255.0))
	return "差异像素 %d（只比原图不透明的像素，最大通道差 %d）%s" % [
		bad, worst, "" if bad == 0 else "  ← 有错位，查一下"]


# ── ★ 梗卡机制实战验收 ─────────────────────────────────
## 三件事必须**亲眼**看到（截图 + 控制台回显），不能只读代码：
##   ① 一对：两张同点数 → 牌型/筹码/倍率正确
##   ② 同花：五张同花色 → 牌型升级
## 运行：godot --path <项目> -- --shot=memeverify --shotout=<绝对路径>.png
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
		"map":
			_show_map()
		"event":
			_show_event(0)
		"arena":
			_show_level(_levels[0])
		"reward":
			_show_reward()
		"result":
			_show_result(true)
