extends Camera2D
## 噪声震屏：同时补间"噪声索引"（轨迹连续有形）与"强度"（收敛到 0）。
## 挂在 Camera2D 上，配一个 FastNoiseLite 资源给 shake_noise。
## 受击调用：camera.shake(2.0, 0.3)

@export var shake_noise: FastNoiseLite = null
@export var close_shake: bool = false   ## 无障碍/设置项：关闭震屏

var shake_strength: float = 0.0
var shake_tween: Tween = null
var noise_index: float = 0.0:
	set(v):
		if not is_node_ready():
			return
		noise_index = v
		offset = Vector2(
			shake_strength * shake_noise.get_noise_2d(noise_index, 0.0),
			shake_strength * shake_noise.get_noise_2d(0.0, noise_index))

func shake(strength: float, duration: float) -> void:
	if close_shake:
		stop_shake()
		return
	shake_strength = strength
	if shake_tween != null and shake_tween.is_running():
		shake_tween.kill()
	shake_tween = create_tween()
	shake_tween.set_parallel()
	# 索引前进 distance 与 duration 挂钩 → 不同时长的震动频率可比
	shake_tween.tween_property(self, "noise_index",
		noise_index + 100.0 * duration, duration)
	shake_tween.tween_property(self, "shake_strength", 0.0, duration)
	shake_tween.finished.connect(stop_shake, CONNECT_ONE_SHOT)

func stop_shake() -> void:
	if shake_tween != null and shake_tween.is_running():
		shake_tween.kill()
	set_deferred("offset", Vector2.ZERO)

## 备用方案（toziuha 式创伤值）：trauma 平方后当强度，自然衰减
## var trauma: float = 0.0
## func add_trauma(amount: float) -> void:
##     trauma = minf(1.0, trauma + amount)
## var _t: float = 0.0
## func _process(delta):
##     var s: float = trauma * trauma
##     offset = Vector2(maxf(0.0, 1.0 - s) * randf_range(-1, 1),
##                      maxf(0.0, 1.0 - s) * randf_range(-1, 1)) * s * max_offset
##     trauma = maxf(0.0, trauma - delta)
