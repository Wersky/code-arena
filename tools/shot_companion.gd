extends SceneTree
## 无头目检（杀戮尖塔制）：战斗界面几何断言 + 导出卡面贴图。
## 不开窗口、不出声（开窗口截图会放 BGM，主人明确禁过）。
##
## 运行：
##   godot --headless --path <项目> --script res://tools/shot_companion.gd

const OUT_ART := "res://.godot/sts_card_art.png"


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

	# ① 八大区域构建
	var missing := ""
	for zone in ["HudLeft", "HudRight", "PromptArea", "EnemyStage",
			"Overlay", "AiCompanion", "CardLayer", "BottomSide"]:
		if arena.get_node_or_null(zone) == null:
			missing += zone + " "
	if missing == "":
		print("[OK] 战斗界面八大区域齐全")
	else:
		print("[FAIL] 区域未构建：%s" % missing)

	# ② 结束回合按钮贴右下角
	var side := arena.get_node_or_null("BottomSide") as Control
	var btn: Button = null
	if side != null:
		for c in side.get_children():
			if c is Button:
				btn = c
	if btn != null and "结束回合" in btn.text \
			and side.position.x + side.size.x > 1700.0 \
			and side.position.y + side.size.y > 950.0:
		print("[OK] 「结束回合」按钮位于右下角")
	else:
		print("[FAIL] 结束回合按钮缺失或位置不对")

	# ③ 手牌横排：全在牌区内、不旋转、底边对齐
	var cards: Array = []
	var layer := arena.get_node_or_null("CardLayer")
	if layer != null:
		for c in layer.get_children():
			if c is StsCardView:
				cards.append(c)
	var in_zone := true
	var no_rot := true
	var same_bottom := true
	var bottom := -1.0
	for c in cards:
		var cv := c as StsCardView
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

	# ④ 控制台字号 = 16
	var fs := _first_font_size(arena.get_node_or_null("PromptArea"))
	var font_ok := "OK" if fs == 16 else "FAIL"
	print("[%s] 控制台字号 = %d（要求 16）" % [font_ok, fs])

	# ⑤ 战斗状态：手牌 5 ｜ 能量 3 ｜ 敌 HP 40
	var st: Dictionary = arena.debug_combat_state()
	var ok5 := int(st.get("hand", -1)) == 5 and int(st.get("energy", -1)) == 3 \
			and int(st.get("enemy_hp", -1)) == 40
	print("[%s] 战斗状态：手牌 %d ｜ 能量 %d ｜ 敌 HP %d" % ["OK" if ok5 else "FAIL",
			int(st.get("hand", -1)), int(st.get("energy", -1)), int(st.get("enemy_hp", -1))])

	# ⑥ 费用球必须是子节点且排在框之后（画在框上面）
	if cards.size() > 0:
		var v0 := cards[0] as StsCardView
		var fi := -1
		var oi := -1
		for i in v0.get_child_count():
			var ch := v0.get_child(i)
			if ch.name == "Frame":
				fi = i
			elif ch.name == "CostOrb":
				oi = i
		var orb_ok := oi > fi and fi >= 0
		print("[%s] 费用球是子节点且绘制在框之上（Frame#%d CostOrb#%d）" % [
			"OK" if orb_ok else "FAIL", fi, oi])
		var orb_node: Control = v0.get_node_or_null("CostOrb") as Control
		var frame_node: Control = v0.get_node_or_null("Frame") as Control
		if orb_node != null and frame_node != null:
			print("[cost] 数字 rect=%s ｜ 框 rect=%s ｜ 卡=%s" % [
				str(orb_node.get_rect()), str(frame_node.get_rect()), str(v0.get_rect())])

	# ⑦ 导出第一张卡面贴图（生成立绘）供人工目检
	if cards.size() > 0:
		var view := cards[0] as StsCardView
		var art := view.get_node_or_null("Art") as TextureRect
		if art != null and art.texture != null:
			var img := art.texture.get_image()
			if img.get_width() <= 512:
				img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
			var abs := ProjectSettings.globalize_path(OUT_ART)
			img.save_png(abs)
			print("[OK] 卡面贴图已导出：%s（%d×%d）" % [abs, img.get_width(), img.get_height()])
		else:
			print("[FAIL] 卡面贴图节点缺失")
	# ⑦ 导出敌人像素形象（6x）供预览合成
	var etex := arena._enemy_texture(LevelPool.get_level("L1").enemy_tint, false)
	var eimg := etex.get_image()
	eimg.resize(eimg.get_width() * 6, eimg.get_height() * 6, Image.INTERPOLATE_NEAREST)
	eimg.save_png(ProjectSettings.globalize_path("res://.godot/sts_enemy.png"))
	print("[OK] 敌人贴图已导出（%d×%d）" % [eimg.get_width(), eimg.get_height()])
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
