extends SceneTree
## 行为树逻辑验证（headless）：验证 Sequence/Selector 的 RUNNING 语义、
## TimesLimiter 的次数控制、reset() 的中断能力。
## 跑法：godot_console.exe --headless --path . --script bt_smoke.gd
##
## ⚠️ 遵循 gd-headless-testing 铁律 #1：节点 _ready 在 _initialize 阶段尚未执行，
## 而本测试依赖 _ready 里的 child_nodes 收集 —— 所以一切等 physics_frame 之后再做。

var failures: Array[String] = []
var frames: int = 0
var done: bool = false

func _initialize() -> void:
	physics_frame.connect(_tick)

func _tick() -> void:
	frames += 1
	if frames == 2:                       # 等首帧入树，_ready 已跑完
		_run_all()
		_report()
		done = true
	return

func _run_all() -> void:
	_test_sequence_running()
	_test_selector_or()
	_test_times_limiter()
	_test_reset_interrupts()

func _test_sequence_running() -> void:
	# Sequence 的语义：子节点返回 RUNNING 时停在那一步，不能跳过它也不能重头
	var seq := Sequence.new()
	var leaf_a := _CountLeaf.new()
	var leaf_b := _CountLeaf.new()
	seq.add_child(leaf_a)
	seq.add_child(leaf_b)
	root.add_child(seq)
	leaf_a.result = BehaviorTreeNode.BTState.SUCCESS
	leaf_b.result = BehaviorTreeNode.BTState.RUNNING

	var r1 := seq.tick(0.016)
	_expect(r1 == BehaviorTreeNode.BTState.RUNNING, "Sequence: 子节点 RUNNING 时父应 RUNNING")
	_expect(leaf_a.tick_count == 1, "Sequence: 第一个子节点只 tick 一次（不重头）")
	_expect(leaf_b.tick_count == 1, "Sequence: 第二个子节点已 tick")

	seq.tick(0.016)
	_expect(leaf_a.tick_count == 1, "Sequence: RUNNING 期间不重跑已完成的子节点")
	_expect(leaf_b.tick_count == 2, "Sequence: RUNNING 的子节点被继续 tick")

	leaf_b.result = BehaviorTreeNode.BTState.SUCCESS
	var r3 := seq.tick(0.016)
	_expect(r3 == BehaviorTreeNode.BTState.SUCCESS, "Sequence: 全部成功应返回 SUCCESS")
	seq.queue_free()

func _test_selector_or() -> void:
	# Selector 的语义：遇到第一个成功就返回，失败则继续下一个
	var sel := Selector.new()
	var fail_leaf := _CountLeaf.new()
	var ok_leaf := _CountLeaf.new()
	fail_leaf.result = BehaviorTreeNode.BTState.FAILURE
	ok_leaf.result = BehaviorTreeNode.BTState.SUCCESS
	sel.add_child(fail_leaf)
	sel.add_child(ok_leaf)
	root.add_child(sel)

	var r := sel.tick(0.016)
	_expect(r == BehaviorTreeNode.BTState.SUCCESS, "Selector: 有一个成功应返回 SUCCESS")
	_expect(fail_leaf.tick_count == 1 and ok_leaf.tick_count == 1,
		"Selector: 失败后应继续尝试下一个")

	ok_leaf.result = BehaviorTreeNode.BTState.FAILURE
	var r2 := sel.tick(0.016)
	_expect(r2 == BehaviorTreeNode.BTState.FAILURE, "Selector: 全失败应返回 FAILURE")
	sel.queue_free()

func _test_times_limiter() -> void:
	# TimesLimiter 的真实语义（读源码 + 实测确认，两个反直觉点）：
	#   ① 计数只在 ignore_child = true 时累加。ignore_child = false（默认）时子节点的
	#      非 RUNNING 结果直接透传给父节点，计数恒为 0——那是"直通"语义，不是限次。
	#      要"这招最多连放 N 次"，必须 ignore_child = true。
	#   ② 计数在 _enter() 时重置 —— 父节点每次重新进入它就是一个新的"连放窗口"。
	var lim := TimesLimiter.new()
	lim.limit = 3
	lim.ignore_child = true                    # ★ 不限次就必须开这个
	var leaf := _CountLeaf.new()
	leaf.result = BehaviorTreeNode.BTState.SUCCESS
	lim.add_child(leaf)
	root.add_child(lim)

	var completed := 0
	lim._enter()                               # 父节点进入 → 计数归零
	for i in 20:
		var before := leaf.tick_count
		lim.tick(0.016)
		if leaf.tick_count > before:
			completed += 1
	_expect(completed == 3,
		"TimesLimiter: 一次进入窗口内 limit=3 时子节点只应执行 3 次，实际 %d" % completed)
	_expect(lim.tick(0.016) == BehaviorTreeNode.BTState.FAILURE,
		"TimesLimiter: 达到 limit 后应返回 FAILURE（让父节点换招/换阶段）")

	# 重新进入 → 计数重置 → 又可连放 3 次
	completed = 0
	lim._enter()
	for i in 20:
		var before := leaf.tick_count
		lim.tick(0.016)
		if leaf.tick_count > before:
			completed += 1
	_expect(completed == 3,
		"TimesLimiter: _enter 应重置计数（新的连放窗口）")
	lim.queue_free()

func _test_reset_interrupts() -> void:
	# reset() 必须中断 RUNNING 的子节点（敌人受击打断 AI 依赖它）
	var seq := Sequence.new()
	var monitor := _InterruptMonitoredLeaf.new()
	monitor.result = BehaviorTreeNode.BTState.RUNNING
	seq.add_child(monitor)
	root.add_child(seq)

	seq.tick(0.016)
	_expect(monitor.entered and not monitor.exited, "reset 前：子节点应在运行中")
	seq.reset()
	_expect(monitor.exited, "reset(): 必须 _exit() 正在运行的子节点（AI 打断的关键）")
	seq.queue_free()

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)

func _report() -> void:
	if failures.is_empty():
		print("bt_smoke: PASS - 行为树核心语义全通过（Sequence/Selector RUNNING、TimesLimiter、reset 中断）")
		quit(0)
	else:
		for f in failures:
			print("  FAIL: " + f)
		print("bt_smoke: FAIL - %d 项" % failures.size())
		quit(1)


class _CountLeaf extends BehaviorTreeNode:
	var result: BTState = BTState.SUCCESS
	var tick_count: int = 0
	func tick(_delta: float) -> BTState:
		tick_count += 1
		return result

class _InterruptMonitoredLeaf extends BehaviorTreeNode:
	var result: BTState = BTState.RUNNING
	var entered: bool = false
	var exited: bool = false
	func enter() -> void: entered = true
	func exit() -> void: exited = true
	func tick(_delta: float) -> BTState: return result
