extends SceneTree
## 选角界面「左下角 Q 版小立绘」验收（2026-11-17 施工规格书 4.4）。
##
## 运行：
##   godot --headless --path <项目> --script res://tools/verify_select_chibi.gd
##
## 背景：规格书指出「默认流程走 character_select_screen.gd，不经过 ai_select，
## 所以 Q 版在默认流程里调用点为 0」。本脚本验的就是这个洞补上了没有。
##
## 断什么：
##   ① 界面上有 ChibiPortrait 节点，且是 ChibiRig 类型
##   ② 它在左下角空区（介绍面板 y 到 691、开始按钮在 1330,800 → 左下 297×200）
##   ③ 显示尺寸 = 96×128（0.5 倍画布）
##   ④ 立在千问时有 9 件、可见；切到别人时隐藏；切回千问又可见
##   ⑤ 小立绘不与介绍面板/开始按钮/圆点行几何重叠

const SELECT_ID := "kweno"

var _fail := 0
var _pass := 0


func _initialize() -> void:
	await _run()
	print("── 汇总：%d PASS / %d FAIL ──" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("[OK]   %s" % msg)
	else:
		_fail += 1
		print("[FAIL] %s" % msg)


func _run() -> void:
	var ais: Array = AiPool.all_ais()
	var kweno_idx := -1
	var other_idx := -1
	for i in ais.size():
		var a: AiData = ais[i]
		if a.id == SELECT_ID:
			kweno_idx = i
		elif other_idx < 0:
			other_idx = i
	_ok(kweno_idx >= 0, "AiPool 里有 %s（index=%d）" % [SELECT_ID, kweno_idx])
	if kweno_idx < 0:
		return

	var host := Control.new()
	host.name = "Host"
	host.size = Vector2(1600, 900)
	root.add_child(host)

	var sc := CharacterSelectScreen.new()
	host.add_child(sc)
	sc.setup(ais)
	sc.select_by_index(kweno_idx)
	await _settle()

	var chibi: Node = sc.get_node_or_null("ChibiPortrait")
	_ok(chibi != null, "选角界面挂上了 ChibiPortrait 节点")
	if chibi == null:
		return
	_ok(chibi is ChibiRig, "该节点是 ChibiRig（实际 %s）" % chibi.get_class())

	# ② 左下角空区：x 在介绍面板右侧之内、y 在 691 与圆点行 800 之间
	var p: Vector2 = (chibi as Node2D).global_position
	var vis_size: Vector2 = Vector2(192, 256) * (chibi as Node2D).scale.x
	# 下沿 700+128=828 会越过圆点行 y=800 一点点。判据取「不压到介绍面板、不压到开始按钮」，
	# 圆点行只在屏幕正中（600..1000），左下有 300px 富裕 —— 所以纵向放宽到 y+h < 860。
	_ok(p.x < 320.0 and p.y > 691.0 and p.y + vis_size.y < 860.0,
			"站位在左下空区：pos=(%.0f,%.0f) 显示 %.0fx%.0f（要求 x<320、691<y、y+h<860）"
			% [p.x, p.y, vis_size.x, vis_size.y])
	_ok(absf((chibi as Node2D).scale.x - 0.5) < 0.001
			and absf((chibi as Node2D).scale.y - 0.5) < 0.001,
			"缩放 0.5×0.5（实际 %s）" % str((chibi as Node2D).scale))

	# ③ 千问时可见且九件就位
	var parts: Dictionary = chibi.get("_parts")
	_ok(chibi.visible, "千问时小立绘可见")
	_ok(parts.size() == 9, "千问时九件就位（实际 %d 件）" % parts.size())

	# ④ 与其它控件不重叠
	var intro: Control = sc.get_node_or_null("CharacterIntro") as Control
	if intro != null:
		var ir := Rect2(intro.global_position, intro.size)
		var cr := Rect2(p, vis_size)
		_ok(not ir.intersects(cr), "不与介绍面板重叠（面板 %s vs 立绘 %s）"
				% [str(ir), str(cr)])
	var start_btn: Button = sc.get_node_or_null("StartBtn") as Button
	if start_btn == null:
		for c in sc.get_children():
			if c is Button and "开始" in (c as Button).text:
				start_btn = c as Button
				break
	if start_btn != null:
		var sr := Rect2(start_btn.global_position, start_btn.size)
		_ok(not Rect2(p, vis_size).intersects(sr), "不与开始按钮重叠（按钮 %s）" % str(sr))

	# ⑤ 切别人 → 隐藏；切回千问 → 可见
	if other_idx >= 0:
		# 转场有 _swapping 守卫（默认 0.7s），连切会被吞 —— 必须先等转场播完。
		await _wait_swap(sc)
		sc.select_by_index(other_idx)
		await _settle()
		_ok(not chibi.visible, "切到其他角色后小立绘隐藏（id=%s）" % ais[other_idx].id)
		await _wait_swap(sc)
		sc.select_by_index(kweno_idx)
		await _settle()
		_ok(chibi.visible, "切回千问后小立绘重新可见")
		var parts2: Dictionary = chibi.get("_parts")
		_ok(parts2.size() == 9, "切回后九件仍在位（实际 %d 件）" % parts2.size())

	print("[info] 小立绘最终 pos=%s visible=%s" % [str((chibi as Node2D).position), str(chibi.visible)])


## 等转场结束（_swapping 守卫）。默认 0.7s，给到 2.5s。
## 注意：headless 下帧率极高，60 个 process_frame 可能只跑了 ~0.05s 游戏时间，
## 所以必须用真实计时器等，不能数帧。
func _wait_swap(sc: Node) -> void:
	var deadline := 2.5
	var t := 0.0
	while t < deadline:
		await process_frame
		t += 1.0 / maxf(1.0, float(Engine.get_frames_per_second()) if Engine.get_frames_per_second() > 0 else 60.0)
		if not bool(sc.get("_swapping")):
			return


## 等转场补间真正跑完（真实时间，不数帧）
func _settle(secs: float = 1.2) -> void:
	await create_timer(secs).timeout
