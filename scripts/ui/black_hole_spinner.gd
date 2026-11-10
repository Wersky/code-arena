class_name BlackHoleSpinner
extends Control
## GPT 角色「血色黑洞」持续旋转特效（2026-11-10 主人要求）。
##
## ── 为什么独立一层、不并进呼吸 shader ──────────────────────────────────
## 呼吸是**往复**的纵向位移（sin 来回），黑洞是**持续单向**旋转（累加不回头）。
## 两者节奏、语义、时间模型都不同：塞进同一个 shader 会互相牵制，
## 而且呼吸的 progress 是 0→1→0 往复，拿去驱动旋转会变成正转-反转-正转。
## 所以做成独立的叠加层，自己跑一条只增不减的时间轴。
##
## ── 层序 ─────────────────────────────────────────────────────────────
## 挂在 PortraitBreathLayer 之后（后入树 = 画在上面），只覆盖黑洞那一小块
## （靠 region 遮罩限定，区域外 shader 直接放行原图）。
##
## ── 只对 GPT 生效 ─────────────────────────────────────────────────────
## set_region(null) 时整层 visible=false，其他三个角色完全不受影响。

const SHADER := preload("res://assets/shaders/blackhole_spin.gdshader")

## 旋转一圈所需秒数（越小转得越快）
const SPIN_PERIOD := 6.0
## 黑洞中心（归一化 UV）。由 Python 定位 GPT 立绘里黑洞最暗核得出。
const CENTER_UV := Vector2(0.3581, 0.1218)
## 核心黑洞半径（UV 单位，与 shader 的 core 对应）
const CORE_R := 0.0235

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _t := 0.0          ## 单调递增的时间累加（不往复）
var _on := false


func _init() -> void:
	name = "BlackHoleSpin"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("spin", 0.0)
	_mat.set_shader_parameter("center", CENTER_UV)
	_mat.set_shader_parameter("aspect", 16.0 / 9.0)
	_mat.set_shader_parameter("core", CORE_R)

	_rect = ColorRect.new()
	_rect.name = "SpinRect"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_on_resized()
	resized.connect(_on_resized)


func _on_resized() -> void:
	if _mat == null or size.y <= 0.0:
		return
	_mat.set_shader_parameter("aspect", size.x / size.y)


func _process(delta: float) -> void:
	if not _on:
		return
	# 单调累加 → 永远朝一个方向转，不会像 sin 那样来回
	_t += delta / maxf(SPIN_PERIOD, 0.1)
	_mat.set_shader_parameter("spin", fposmod(_t, 1.0))


## 设置黑洞区域遮罩（null = 该角色没有黑洞，整层隐藏）
func set_region(base_tex: Texture2D, region_tex: Texture2D) -> void:
	if base_tex == null or region_tex == null:
		_on = false
		visible = false
		return
	_mat.set_shader_parameter("tex_src", base_tex)
	_mat.set_shader_parameter("tex_region", region_tex)
	_on = true
	visible = true


## 定格（截图钩子）：直接指定 spin 值
func debug_set_spin(v: float) -> void:
	_t = v
	_mat.set_shader_parameter("spin", fposmod(v, 1.0))


func spin_state() -> Dictionary:
	return {
		"on": _on,
		"t": _t,
		"visible": visible,
		"center": CENTER_UV,
		"core": CORE_R,
		"period": SPIN_PERIOD,
	}
