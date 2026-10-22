class_name Selector extends BehaviorTreeNode
## 选择节点（OR）：依次 tick 子节点，任一成功即成功、全部失败才失败。
## is_random 时打乱子节点顺序（用于"随机挑一招"的敌人）。
##
## ★ 关键：从上次 RUNNING 的子节点继续执行，而不是每帧重头再来。

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
				_reset_index()
				return BTState.SUCCESS
			BTState.FAILURE:
				current_child_index += 1
				if current_child_index >= child_nodes.size():
					_reset_index()
					return BTState.FAILURE
	return BTState.FAILURE

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
