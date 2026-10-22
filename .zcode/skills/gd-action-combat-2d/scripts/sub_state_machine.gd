class_name SubStateMachine extends State
## 可嵌套的子状态机。装在 StateMachine 下面就是"战斗分层"，再往下装就是"移动分层"。
##
## 装配示例（玩家）：
##   StateMachine (initial_state = AttackSubFSM)
##   └─ AttackSubFSM (initial_state = ActionSubFSM)   ← Hurt/Dash/Shield 等也挂这一层
##      └─ ActionSubFSM (initial_state = Idle)        ← Idle/Run/Fall/Attack 在这层
##         只有最内层消费攻击键，所以一次按键不会触发两个动作。

@export var initial_state: State = null
@export var enable_log: bool = false

var current_state: State = null
var last_state: State = null

func _ready() -> void:
	for child: State in get_children():
		child.change.connect(change_state)
	current_state = initial_state
	last_state = current_state

func enter() -> void:
	## 重入时归位到初始状态，避免受击结束后回到上一次的动作
	if current_state != null:
		current_state.exit()
	current_state = initial_state
	if current_state != null:
		current_state.enter()

func exit() -> void:
	if current_state != null:
		current_state.exit()

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

func tick(delta: float) -> void:
	if current_state != null:
		current_state.tick(delta)
