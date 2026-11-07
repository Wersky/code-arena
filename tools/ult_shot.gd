extends SceneTree
## 终结技演出截图钩子（隐藏桌面跑，--audio-driver Dummy 无声）：
## 搭真战斗 → 充满能量 → 释放终结技 → 关键帧存 PNG。
## 用法：
##   godot --path <项目> --audio-driver Dummy --script res://tools/ult_shot.gd

const OUT_DIR := "res://.godot/ult_shots"
## GIF 模式：0.2s 间隔密集采样到 4.4s（拼动图用，文件名 3 位序号）
const GIF_STEP := 0.2
const GIF_UNTIL := 5.8


func _initialize() -> void:
	await _run()
	quit()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var run := RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))
	run.intro_played = true          # 跳过进场演出，直奔终结技

	var arena := ArenaScreen.new()
	arena.setup(run, LevelPool.get_level("L1"))
	arena.size = Vector2(1600, 900)
	root.add_child(arena)
	for _i in 8:
		await process_frame

	# 充满能量 → 释放（走 arena 真实释放流程：锁按钮/演出/结算一整套）
	arena.combat.ult_charge = StsCombat.ULT_MAX
	arena._cast_ult()                # async 协程，自身按时间轴推进
	print("[ult_shot] cast_ult 已触发")

	var t0 := Time.get_ticks_msec()
	var frame := 0
	var t := 0.0
	while t <= GIF_UNTIL:
		var target_ms := int(t * 1000.0)
		while Time.get_ticks_msec() - t0 < target_ms:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/g%03d.png" % [OUT_DIR, frame]
		img.save_png(ProjectSettings.globalize_path(path))
		frame += 1
		t += GIF_STEP
	print("[ok] %d 帧 -> %s" % [frame, OUT_DIR])
	# 等演出收尾（arena 侧 finished 回调解锁）
	while arena._ult_playing:
		await process_frame
	print("[done] 演出结束，敌人血量=%d" % arena.combat.enemy_hp)
