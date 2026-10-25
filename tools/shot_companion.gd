extends SceneTree
## 无头目检：右侧 AI 娘 / 排序按钮 / 控制台字号 的几何断言 + 导出睡觉小人贴图。
## 不开窗口、不出声（开窗口截图会放 BGM，主人明确禁过）。
##
## 运行：
##   godot --headless --path <项目> --script res://tools/shot_companion.gd

const OUT_SLEEP := "res://.godot/ai_companion_sleep.png"


func _initialize() -> void:
	await _run()
	quit()


func _run() -> void:
	var run := RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))

	var host := Control.new()
	host.name = "Host"
	host.size = Vector2(1920, 1080)
	root.add_child(host)

	var arena := ArenaScreen.new()
	arena.setup(run, LevelPool.get_level("L1"))
	host.add_child(arena)
	for _i in 6:
		await process_frame

	# ① 几何：AI 娘盒子应落在右上 HUD 下方、右下按钮上方之间的右列
	var comp := arena.get_node_or_null("AiCompanion") as AiCompanion
	if comp == null:
		print("[FAIL] AiCompanion 未挂载")
		return
	print("[companion] rect = %s ｜ mode = %s" % [str(comp.get_rect()), comp.debug_mode()])
	var inside: bool = comp.position.x >= 1920.0 - 24.0 - 320.0 - 0.5 \
			and comp.position.y >= 24.0 + 300.0 \
			and comp.position.y + comp.size.y <= 1080.0 - 156.0 + 0.5
	print("[%s] AI 娘盒子在右列空档内（右上 HUD 与右下按钮之间）" % ("OK" if inside else "FAIL"))

	# ② 排序按钮在右下工具条里、位于屏幕右下角
	var side := arena.get_node_or_null("BottomSide") as Control
	var found := 0
	if side != null:
		for row in side.get_children():
			if row is HBoxContainer:
				for b in row.get_children():
					if b is Button and ("花色" in b.text or "点数" in b.text):
						found += 1
		print("[sort] 按钮数 = %d ｜ 工具条 rect = %s" % [found, str(side.get_rect())])
		var cornered := found >= 2 \
				and side.position.x + side.size.x > 1700.0 \
				and side.position.y + side.size.y > 900.0
		print("[%s] 排序按钮 ≥2 个且工具条贴右下角" % ("OK" if cornered else "FAIL"))
	else:
		print("[FAIL] BottomSide 未找到")

	# ③ 控制台字号：第一个日志/命令行 label 应为 16
	var fs := -1
	var area := arena.get_node_or_null("PromptArea")
	if area != null:
		fs = _first_font_size(area)
	var font_ok := "OK" if fs == 16 else "FAIL"
	print("[%s] 控制台字号 = %d（要求 16）" % [font_ok, fs])

	# ④ 导出睡觉小人贴图（4x 最近邻放大）供人工目检
	var art := comp.get_node_or_null("Art") as TextureRect
	if art != null and art.texture != null:
		var img := art.texture.get_image()
		if img.get_width() <= 512:
			img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
		var abs := ProjectSettings.globalize_path(OUT_SLEEP)
		img.save_png(abs)
		print("[OK] 睡觉小人贴图已导出：%s（%d×%d）" % [abs, img.get_width(), img.get_height()])
	else:
		print("[FAIL] 睡觉小人贴图导出失败")

	# ⑤ 手牌横排：全部落在牌区（左栏右缘 → 右列左缘）、不旋转、底边对齐
	var cards: Array = []
	var layer := arena.get_node_or_null("CardLayer")
	if layer != null:
		for c in layer.get_children():
			if c is CardView:
				cards.append(c)
	var in_zone := true
	var no_rot := true
	var same_bottom := true
	var bottom := -1.0
	for c in cards:
		var cv := c as CardView
		if absf(cv.rotation) > 0.001:
			no_rot = false
		if cv.position.x < 267.0 or cv.position.x + 150.0 > 1577.0:
			in_zone = false
		if bottom < 0.0:
			bottom = cv.position.y
		elif absf(cv.position.y - bottom) > 0.5:
			same_bottom = false
	print("[%s] 手牌 %d 张横排：全部落在牌区 268..1576 内" % ["OK" if in_zone else "FAIL", cards.size()])
	print("[%s] 手牌全部不旋转" % ("OK" if no_rot else "FAIL"))
	print("[%s] 手牌底边对齐" % ("OK" if same_bottom else "FAIL"))
	host.queue_free()


func _first_font_size(n: Node) -> int:
	if n is Label:
		var l := n as Label
		if l.text.begins_with(">"):
			return l.get_theme_font_size("font_size")
	for c in n.get_children():
		var hit := _first_font_size(c)
		if hit > 0:
			return hit
	return -1
