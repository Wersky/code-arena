class_name StateMachine extends Node
## 顶层状态机。装在角色节点下，子节点即状态（或子状态机）。
## 每物理帧 tick 当前状态。

@export var initial_state: State = null
@export var enable_log: bool = false
@export var disabled: bool = false

var current_state: State = null
var last_state: State = null

func _ready() -> void:
	for child: State in get_children():
		child.change.connect(change_state)
	current_state = initial_state
	last_state = current_state

func change_state(target: String) -> void:
	var state: State = get_node_or_null(target)
	if state == null:
		return
	if current_state != null:
		last_state = current_state
		current_state.exit()
	current_state = state
	current_state.enter()
	if enable_log:
		print("[%d]%s: %s -> %s" % [
			Engine.get_frames_drawn(), name, last_state.name, current_state.name])

func state_name() -> String:
	return current_state.name

func _physics_process(delta: float) -> void:
	if not disabled and current_state != null:
		current_state.tick(delta)
