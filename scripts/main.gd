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
const ChibiRigScene := preload("res://scripts/ui/chibi_rig.gd")

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
			"typing", "typebreak", "runresult", "memeverify", "aiselect", "poker", "slot",
			"fx", "fxfly", "menuhover", "rig"]:
		run.reset_run()
		if screen == "rig":
			# 目检：Q 版角色 walk 的第 0/1/2/3 帧 → 2×2 拼图
			await _capture_rig(out_path)
			return
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
		elif screen == "menuhover":
			# 开始界面悬停目检：把鼠标挪到「开始游戏」上，等 0.4 秒让扫光扫过去
			_show_menu()
			await get_tree().process_frame
			await get_tree().process_frame
			var menu := _current as MainMenuScreen
			if menu != null:
				Input.warp_mouse(menu.debug_start_button_center())
				menu.debug_hover_start()
				await get_tree().create_timer(0.30).timeout
		elif screen == "fxfly":
			# 出牌特效第二帧：得分数字飞向右上角 HUD
			_show_level(_levels[0])
			await get_tree().process_frame
			var arena_fly := _current as ArenaScreen
			if arena_fly != null:
				for i in 4:
					arena_fly.debug_place_card(i)
				await get_tree().create_timer(0.35).timeout
				arena_fly.debug_run()
				await get_tree().create_timer(1.16).timeout
		elif screen == "fx":
			# 出牌特效目检：选 4 张 → 运行 → 停在总分炸开的瞬间
			_show_level(_levels[0])
			await get_tree().process_frame
			var arena_fx := _current as ArenaScreen
			if arena_fx != null:
				for i in 4:
					arena_fx.debug_place_card(i)
				await get_tree().create_timer(0.35).timeout
				arena_fx.debug_run()
				await get_tree().create_timer(0.78).timeout
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
