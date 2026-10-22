class_name TimesLimiter extends BehaviorTreeNode
## 次数限制装饰器：做"这招最多连放 N 次，然后换阶段"。
##
## ⚠️ 两个反直觉点（2026-09-12 headless 实测确认，容易踩）：
##   ① **要限次就必须设 ignore_child = true**。ignore_child = false（默认）时，子节点的
##      非 RUNNING 结果会直接透传给父节点，计数恒为 0——那是"直通"语义，不产生限次效果。
##   ② 计数在 _enter() 里重置。父节点（如 Selector）每次重新进入它 = 一个新的连放窗口。
##
## 典型用法（Boss 阶段切换）：
##   Selector
##   └─ Sequence（阶段 1）
##      ├─ Inverter → TimesLimiter(limit=3, ignore_child=true) → Sequence(单次出招)
##      └─ ...
## 注意它只能有一个子节点。

@export var limit: int = 1
@export var ignore_child: bool = false   ## ★ 要限次必须置 true

var current_count: int = 0

func _ready() -> void:
	super()
	child_nodes = []
	for child: Node in get_children():
		if child is BehaviorTreeNode:
			child_nodes.append(child)

func _enter() -> void:
	super()
	if child_nodes.size() > 0:
		child_nodes[0]._enter()
	current_count = 0

func _exit() -> void:
	if child_nodes.size() > 0:
		child_nodes[0]._exit()
	current_count = 0
	super()

func tick(delta: float) -> BTState:
	if child_nodes.size() != 1:
		push_warning("%s/%s should have exactly 1 child, got %d" % [
			get_path(), name, child_nodes.size()])
		return BTState.FAILURE
	if current_count >= limit:
		child_nodes[0].reset()
		return BTState.FAILURE
	var child_state: BTState = child_nodes[0].tick(delta)
	if not ignore_child and child_state != BTState.RUNNING:
		return child_state
	if child_state != BTState.RUNNING:
		current_count += 1
	return BTState.RUNNING
