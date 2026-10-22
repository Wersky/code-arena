class_name ControlManager extends Node
## 输入缓冲：每个动作一个 0.1s 一次性 Timer。
## 状态机用 control_request("attack") 查询，而不是自己读 Input——
## 于是"攻击后摇里按的下一刀"不会丢，且输入检测与动作执行彻底分离。

const BUFFER_TIME: float = 0.1

var control_direction: String = "NONE"   # 或换 enum Constant.ControlDirection
var control_buffer_timer: Dictionary = {
	"jump": null, "dash": null, "attack": null, "shoot": null, "throw": null,
}
## "本次滞空是否已用"的状态门（比 CD 更准：状态轴 vs 时间轴）
var double_jumped: bool = false
var dashed: bool = false
var threw_jelly: bool = false

@export var auto_attack: bool = false

func _ready() -> void:
	for key: String in control_buffer_timer.keys():
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = BUFFER_TIME
		control_buffer_timer[key] = timer
		add_child(timer)

func _physics_process(_delta: float) -> void:
	for key: String in control_buffer_timer.keys():
		if Input.is_action_just_pressed(key):
			control_buffer_timer[key].start()
		# 自动攻击：按住即连发（可选）
		if auto_attack and key in ["attack", "shoot"]:
			if Input.is_action_pressed(key):
				control_buffer_timer[key].start()

func control_request(action: String) -> bool:
	var timer: Timer = control_buffer_timer.get(action)
	if timer == null:
		return false
	return not timer.is_stopped()

## 落地时调用，重置滞空门
func reset_air_flags() -> void:
	double_jumped = false
	dashed = false
	threw_jelly = false
