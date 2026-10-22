class_name BehaviorTreeNode extends Node
## 行为树节点基类。整棵树是普通 Node 树，在编辑器里可见可调参。
##
## 自研最小集（约 400 行覆盖全部）：
##   ControlNode:  Selector（OR，可随机）/ Sequence（AND）/ Parallel（AND|OR）
##   Decorator:    Inverter / Failer / Succeeder / Waiter / Delayer / TimeLimiter / TimesLimiter
##   Leaf:         Action 子类（每招式一个脚本，只回答"怎么打"）
##   Root:         RootNode（每物理帧 tick 唯一子节点）
##
## 关键纪律：
##   - Selector/Sequence 必须"从上次 RUNNING 的子节点继续"，否则 RUNNING 语义会错
##   - reset() 要在控制节点里正确 _exit() 正在运行的子节点（受击打断 AI 依赖它）

enum BTState { RUNNING = 0, SUCCESS = 1, FAILURE = 2 }

var child_nodes: Array[BehaviorTreeNode] = []

func _ready() -> void:
	for child: Node in get_children():
		if child is BehaviorTreeNode:
			child_nodes.append(child)

func _enter() -> void:
	enter()

func _exit() -> void:
	exit()

func enter() -> void:
	pass

func exit() -> void:
	pass

func tick(_delta: float) -> BTState:
	return BTState.RUNNING

func reset() -> void:
	for child in child_nodes:
		child.reset()
