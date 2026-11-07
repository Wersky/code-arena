extends SceneTree
## 复现：上下文压缩（hand +1）在战斗里是否生效
func _initialize() -> void:
	await process_frame
	# 路径 A：正常 RunState.start_battle
	var run := RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))
	var it := StsItemPool.make("compress")
	run.items.append(it)
	print("[A] 持有道具 compress power=%d charges=%d" % [it.power, it.charges])
	var cb := run.start_battle(LevelPool.get_level("L1"))
	cb.set_refill(StsCombat.refill_for(run.ai.id))
	print("[A] refill=%d hand_bonus=%d hand_size=%d 实际手牌=%d" % [
			cb._refill_count, cb.hand_bonus, cb.hand_size(), cb.hand.size()])
	# 打空补牌后
	for i in 6:
		if cb.hand.is_empty():
			break
		cb.play_card(cb.hand[0])
	print("[A] 出牌后补牌 hand=%d (期望 %d)" % [cb.hand.size(), cb.hand_size()])

	# 路径 B：LLMDemoScreen 的真对战（手工 StsCombat）
	print("[B] demo 真对战是手工 StsCombat.new()，不经过 run.start_battle —— 道具天然不生效")
	quit()
