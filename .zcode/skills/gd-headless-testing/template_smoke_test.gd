extends SceneTree
# 冒烟测试：headless 验证 new_game → 计分 → mob 生成 → game_over 全链路。
# 用法：D:/zcode-work/godot/engine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script smoke_test.gd
# 通过输出 "smoke: PASS"，失败输出 "smoke: FAIL - 原因" 并以退出码 1 结束。
# 设计说明：
# 1. 不能在 _initialize 里直接调 new_game()——节点尚未完成入树，get_tree() 为 null，必须等 _process 首帧。
# 2. 不依赖真实时钟等 Timer 自然超时——headless 下帧率与真实时间脱钩，等待不可靠；
#    改为手动触发各 Timer 的超时回调做确定性断言（游戏测试方法论：确定性 > 真实性）。

var frames = 0
var main_scene

func _initialize():
	main_scene = load("res://main.tscn").instantiate()
	root.add_child(main_scene)

func _process(_delta):
	frames += 1
	if frames == 2:
		main_scene.new_game()
		# 模拟 StartTimer(2s) 超时：启动 MobTimer/ScoreTimer
		main_scene._on_start_timer_timeout()
	elif frames == 10:
		# 模拟 ScoreTimer 超时两次，断言计分与 HUD 同步
		main_scene._on_score_timer_timeout()
		main_scene._on_score_timer_timeout()
		var score = main_scene.score
		var hud_text = main_scene.get_node("HUD/ScoreLabel").text
		print("smoke: score=%d hud=%s" % [score, hud_text])
		if score != 2 or hud_text != "2":
			print("smoke: FAIL - 计分链路断裂（score 或 HUD 不同步）")
			quit(1)
			return true
		# 模拟 MobTimer 超时三次，断言 mob 进组
		for i in 3:
			main_scene._on_mob_timer_timeout()
		var mobs = get_nodes_in_group(&"mobs").size()
		print("smoke: 生成后 mobs=%d" % mobs)
		if mobs < 1:
			print("smoke: FAIL - mob 生成失败")
			quit(1)
			return true
		main_scene.game_over()
	elif frames == 30:
		print("smoke: PASS - new_game/计分/mob生成/game_over 全链路无报错")
		quit(0)
		return true
	return false
