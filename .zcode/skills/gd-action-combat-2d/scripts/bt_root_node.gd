class_name RootNode extends BehaviorTreeNode
## 行为树根节点：每物理帧 tick 唯一子节点。
## 挂法：Enemy/Boss 场景里的 BehaviorTree 节点 + `disabled` 开关（Boss 未开战时禁用）。

@export var disabled: bool = false

func _ready() -> void:
	super()
	# 收集时跳过 disabled 的子节点
	child_nodes.clear()
	for child: Node in get_children():
		if child is BehaviorTreeNode and not child.disabled:
			child_nodes.append(child)
	if child_nodes.size() >= 1:
		child_nodes[0]._enter()

func _physics_process(delta: float) -> void:
	if disabled:
		return
	if child_nodes.size() != 1:
		push_warning("%s/%s should have exactly 1 child, got %d" % [
			get_path(), name, child_nodes.size()])
		return
	child_nodes[0].tick(delta)
