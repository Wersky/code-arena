class_name Sequence extends BehaviorTreeNode
## 顺序节点（AND）：依次 tick 子节点，任一失败即失败、全部成功才成功。
##
## Boss 招式序列主要靠它编排：
##   Sequence: IsStageChange → PlayHurt → WaitFall → Idle → Waiter → PlayAttackAnim → PushStageChange
## 每个子节点返回 SUCCESS 才推进到下一个；Waiter 用 RUNNING 表示"还在等"。

@export var is_random: bool = false

var current_child_index: int = 0
var running_child_index: int = -1

func _ready() -> void:
	super()
	if is_random:
		child_nodes.shuffle()

func tick(delta: float) -> BTState:
	if child_nodes.is_empty():
		return BTState.FAILURE
	while current_child_index < child_nodes.size():
		var child: BehaviorTreeNode = child_nodes[current_child_index]
		if current_child_index != running_child_index:
			child._enter()
			running_child_index = current_child_index
		var child_state: BTState = child.tick(delta)
		if child_state == BTState.RUNNING:
			return BTState.RUNNING
		child._exit()
		match child_state:
			BTState.SUCCESS:
				current_child_index += 1
				if current_child_index >= child_nodes.size():
					_reset_index()
					return BTState.SUCCESS
			BTState.FAILURE:
				_reset_index()
				return BTState.FAILURE
	return BTState.RUNNING

func reset() -> void:
	super()
	if running_child_index >= 0 and current_child_index < child_nodes.size():
		child_nodes[current_child_index]._exit()
	_reset_index()

func _reset_index() -> void:
	current_child_index = 0
	running_child_index = -1
	if is_random:
		child_nodes.shuffle()
