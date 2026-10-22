class_name Waiter extends BehaviorTreeNode
## 等待节点：等待 time 秒（可带随机偏移）后返回 SUCCESS。
## 等待期间返回 RUNNING，于是父 Sequence 会停在这一步。

@export var time: float = 1.0
@export var random_offset: float = 0.0

var timer: Timer = null

func _ready() -> void:
	super()
	timer = Timer.new()
	timer.one_shot = true
	add_child(timer)

func _enter() -> void:
	super()
	timer.start(time + random_offset * randf_range(-1.0, 1.0))

func _exit() -> void:
	timer.stop()
	super()

func tick(_delta: float) -> BTState:
	if timer.is_stopped():
		return BTState.SUCCESS
	return BTState.RUNNING
