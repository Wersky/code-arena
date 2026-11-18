class_name BlackHoleSpinner
extends Control
## GPT 角色「血色黑洞」全效层（2026-11-10 主人要求旋转，2026-11-11 扩成四层特效）。
##
## ── 为什么独立一层、不并进呼吸 shader ──────────────────────────────────
## 呼吸是**往复**的纵向位移（sin 来回），黑洞是**持续单向**旋转（累加不回头）。
## 两者节奏、语义、时间模型都不同：塞进同一个 shader 会互相牵制，
## 而且呼吸的 progress 是 0→1→0 往复，拿去驱动旋转会变成正转-反转-正转。
## 所以做成独立的叠加层，自己跑三条只增不减的时间轴。
##
## ── 层序 ─────────────────────────────────────────────────────────────
## 挂在 PortraitBreathLayer 之后（后入树 = 画在上面），只覆盖黑洞那一小块
## （靠 region 遮罩限定，**区域外 shader 输出全透明**，绝不重绘基图）。
##
## ── 只对 GPT 生效 ─────────────────────────────────────────────────────
## set_region(null) 时 visible=false **且 set_process(false)**，
## 其他三个角色完全零开销（不进 _process，也不提交绘制）。

const SHADER := preload("res://assets/shaders/blackhole_spin.gdshader")

## 旋转一圈所需秒数（越小转得越快）
const SPIN_PERIOD := 6.0
## 快搏动周期（秒）—— 与角色呼吸默认 4.0s 刻意错开（比值 1.41，非整数）
const PULSE_PERIOD := 2.83
## 慢涌动周期（秒）—— 与上面两个都不成整数比（7.10/2.83 = 2.51）
const SURGE_PERIOD := 7.10

## 黑洞中心（归一化 UV）。由 Python 定位 GPT 立绘里黑洞最暗核得出。
const CENTER_UV := Vector2(0.3581, 0.1218)
## 核心黑洞半径（height 单位，与 shader 的 core 对应）= 21.15px / 900
const CORE_R := 0.0235
## 吸积盘椭圆的半轴（height 单位）：遮罩实测 51px × 28px @900 高
const DISK_HALF := Vector2(0.0567, 0.0311)

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
## 三条**单调递增**的时间累加（绝不往复）：
## 拿 sin 之类的往复量驱动旋转会变成「正转-反转-正转」，一眼假。
var _t_spin := 0.0
var _t_pulse := 0.0
var _t_surge := 0.0
var _on := false


func _init() -> void:
	name = "BlackHoleSpin"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("spin", 0.0)
	_mat.set_shader_parameter("pulse", 0.0)
	_mat.set_shader_parameter("surge", 0.0)
	_mat.set_shader_parameter("center", CENTER_UV)
	_mat.set_shader_parameter("aspect", 16.0 / 9.0)
	_mat.set_shader_parameter("core", CORE_R)
	_mat.set_shader_parameter("disk_half", DISK_HALF)

	_rect = ColorRect.new()
	_rect.name = "SpinRect"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	visible = false
	set_process(false)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_on_resized()
	resized.connect(_on_resized)


func _on_resized() -> void:
	if _mat == null or size.y <= 0.0:
		return
	_mat.set_shader_parameter("aspect", size.x / size.y)


## 只有 GPT 在场时才进这里（其余角色 set_process(false)，零开销）
func _process(delta: float) -> void:
	if not _on:
		return
	# 三条都单调累加 → 永远朝一个方向走，不会像 sin 那样来回
	_t_spin += delta / maxf(SPIN_PERIOD, 0.1)
	_t_pulse += delta / maxf(PULSE_PERIOD, 0.1)
	_t_surge += delta / maxf(SURGE_PERIOD, 0.1)
	_push_time()


## 把三条相位推给 shader（fposmod 只做区间收口，不会改变单调性带来的观感）
func _push_time() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("spin", fposmod(_t_spin, 1.0))
	_mat.set_shader_parameter("pulse", fposmod(_t_pulse, 1.0))
	_mat.set_shader_parameter("surge", fposmod(_t_surge, 1.0))


## 设置黑洞区域遮罩（null = 该角色没有黑洞，整层隐藏 + 停掉 _process）
func set_region(base_tex: Texture2D, region_tex: Texture2D) -> void:
	if base_tex == null or region_tex == null:
		_on = false
		visible = false
		# **必须停掉 _process**：其余三个角色在选角界面轮播时会长期存在，
		# 留着一个空转的 _process 就是白烧 CPU（主人明确要求零开销）
		set_process(false)
		return
	_mat.set_shader_parameter("tex_src", base_tex)
	_mat.set_shader_parameter("tex_region", region_tex)
	_on = true
	visible = true
	set_process(true)


## 定格（截图钩子）：直接指定三条相位。
## 顺序必须保持「先 visible/on，再 push」——debug 路径不依赖 _process 也能生效。
func debug_set_time(t_spin: float, t_pulse: float = -1.0, t_surge: float = -1.0) -> void:
	_t_spin = t_spin
	# 未指定时按固定比例派生，保证三轴联动（截图时只需要给一个 t）
	_t_pulse = (t_spin * SPIN_PERIOD / PULSE_PERIOD) if t_pulse < 0.0 else t_pulse
	_t_surge = (t_spin * SPIN_PERIOD / SURGE_PERIOD) if t_surge < 0.0 else t_surge
	_push_time()


## 兼容旧接口（v1 只旋转时用的名字）
func debug_set_spin(v: float) -> void:
	debug_set_time(v * SPIN_PERIOD)


## 按秒定格：便于截图脚本按「真实时间点 t=0/2/4s」抓帧
func debug_set_seconds(sec: float) -> void:
	debug_set_time(sec / SPIN_PERIOD, sec / PULSE_PERIOD, sec / SURGE_PERIOD)


func spin_state() -> Dictionary:
	return {
		"on": _on,
		"t_spin": _t_spin,
		"t_pulse": _t_pulse,
		"t_surge": _t_surge,
		"visible": visible,
		"processing": is_processing(),
		"center": CENTER_UV,
		"core": CORE_R,
		"disk_half": DISK_HALF,
		"periods": [SPIN_PERIOD, PULSE_PERIOD, SURGE_PERIOD],
	}
