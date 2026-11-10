class_name PortraitBreathLayer
extends Control
## 选角大立绘「呼吸」层（2026-11-09，integrate 任务产物）。
##
## ── 为什么是独立一层、叠在 RippleSwapPortrait **之上** ────────────────────────
## RippleSwapPortrait 内部是一张不透明、铺满全屏的 ColorRect，材质被转场 shader 独占
## （tex_prev / tex_next / progress / slashes / sweep 一大串）。所以：
##   · 放它**下面**在几何上不可能——它不透明，会盖住一切；
##   · 复用它的材质会把转场参数冲掉，等于毁掉一人一款转场；
##   · 于是只留一条路：自己做一层不透明全屏 ColorRect，材质跑 portrait_breath，
##     作为 RippleSwapPortrait 的**子节点**（后入树 = 画在上面），纹理与它同步。
## 转场期间本层 hide（见 CharacterSelectScreen._swap_to_character）：
## 两个动画同时改画面会互相打架，而且转场 shader 的 tex_prev/tex_next 语义与
## 单一 tex_src 根本不兼容。转场结束后 0.15s 淡入接管画面，避免相位跳变被看见。
##
## ── 相位 ──────────────────────────────────────────────────────────────────
## 只有一条全局 Tween 在推进 _cycle（0→1 无限循环）。某角色的实际进度 =
## fposmod(_cycle + _offset + base_phase + 0.25 * char_index, 1.0)。
## 四个角色因此永久相差 1/4 周期（错相），而 _cycle 在切角色时**不重置**。
## _offset 是「改周期时把当前 _cycle 折叠进来」的补偿量：重建 Tween 会让输出回到 0，
## 把旧值折进 offset 就保证那一刻画面上的进度完全连续，不会闪一下。
##
## ── 不用 maxf/sin 之外的技巧 ───────────────────────────────────────────────
## shader 里只有 max（maxf 会白屏，本项目踩过），本文件是 GDScript，用 maxf 没问题。

## 与 BreathDebugPanel.Mode 对齐（不引用那个类，避免循环依赖；数值由面板传进来）
## 与 BreathDebugPanel.Mode 对齐（2026-11-10 四态）：
##   0=上下起伏 1=左右起伏 2=整图缩放 3=关闭
const MODE_UV := 0
const MODE_UV_HORZ := 1
const MODE_SCALE := 2
const MODE_OFF := 3

## 四人错相步长：第 i 个角色初相 = i * 0.25
const CHAR_PHASE_STEP := 0.25
## SCALE 模式下 amp 的倍率：默认 amp 0.008 → 最大 1.6% 整图缩放
const SCALE_GAIN := 2.0

const SHADER := preload("res://assets/shaders/portrait_breath.gdshader")

## 三层各自的 gain / phase 偏移（2026-11-10 主人要求每层可调、且按角色独立）
## 由 CharacterSelectScreen 在切角色时从 GameSettings 拉该角色的值填进来。
var hair_gain := 1.00
var face_gain := 0.60
var body_gain := 0.32
var hair_phase := 0.06
var face_phase := 0.00
var body_phase := -0.07

## 当前生效参数（唯一真相；面板改了就走 set_params）
var amp := 0.008
var period := 4.0
var base_phase := 0.0
var mode := MODE_UV
## 当前展示的是第几位角色（决定错相）
var char_index := 0

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _tween: Tween = null

## Tween 输出（0→1，经 TRANS_SINE + EASE_IN_OUT）
var _cycle := 0.0
## 改周期时折叠进来的相位补偿（见文件头）
var _offset := 0.0

## 定格（截图钩子）：为 true 时 Tween 的写入被忽略，进度固定为 _frozen_progress
var _frozen := false
var _frozen_progress := 0.0

var _tex: Texture2D = null
## 三层遮罩（2026-11-10 主人要求拆层）：脸单独一层，避免眼睛被头发拖动
var _mask_hair: Texture2D = null
var _mask_face: Texture2D = null
var _mask_body: Texture2D = null


func _init() -> void:
	name = "PortraitBreath"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 本层只负责画，绝不接鼠标（底下的箭头/圆点/开始键照常可点）
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("progress", 0.0)
	_mat.set_shader_parameter("amp", amp)
	_mat.set_shader_parameter("use_layers", false)

	_rect = ColorRect.new()
	_rect.name = "BreathRect"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_on_resized)
	_on_resized()
	_restart_tween()
	_apply()


## SCALE 模式绕底边中点缩放：立绘像被地面钉住，往上长（不会在左右露底）
func _on_resized() -> void:
	pivot_offset = Vector2(size.x * 0.5, size.y)


# ── 对外：纹理 / 遮罩 ────────────────────────────────────────────────��────
## 切到某位角色：纹理 + 遮罩 + 错相下标一起换。mask 为 null 时自动降级纯 shader。
func set_character(idx: int, tex: Texture2D, hair: Texture2D = null,
		face: Texture2D = null, body: Texture2D = null) -> void:
	char_index = idx
	_tex = tex
	_mask_hair = hair
	_mask_face = face
	_mask_body = body
	if _mat == null:
		return
	_mat.set_shader_parameter("tex_src", tex)
	# 三层遮罩：任一为 null 时该层不参与（shader 侧 sum 归一化会自动退让）
	_mat.set_shader_parameter("tex_hair", hair)
	_mat.set_shader_parameter("tex_face", face)
	_mat.set_shader_parameter("tex_body", body)
	# 三层全缺时 use_layers=false，退化为「全身统一底边锚定」
	_mat.set_shader_parameter("use_layers", hair != null or face != null or body != null)
	# 没有立绘就没有可画的东西：整层隐藏，交给底下 RippleSwapPortrait 的兜底
	visible = tex != null
	_apply()


# ── 对外：参数 ───────────────────────────────────────────────────────────
## 面板 params_changed 直连这里（amp / period / phase / mode）
func set_params(new_amp: float, new_period: float, new_phase: float, new_mode: int) -> void:
	var period_changed := not is_equal_approx(new_period, period)
	amp = new_amp
	base_phase = new_phase
	mode = new_mode
	period = maxf(0.05, new_period)
	if period_changed:
		_restart_tween()          # 内部折叠偏移，画面相位不跳
	_apply()


## 设置三层参数（CharacterSelectScreen 切角色时调用；面板改动也走这里）
func set_layer_params(hg: float, fg: float, bg: float,
		hp: float, fp: float, bp: float) -> void:
	hair_gain = maxf(hg, 0.0)
	face_gain = maxf(fg, 0.0)
	body_gain = maxf(bg, 0.0)
	hair_phase = hp
	face_phase = fp
	body_phase = bp
	_apply()


## 有没有可画的立绘（没有时本层自动隐藏，让底下转场层兜底）
func has_portrait() -> bool:
	return _tex != null


## 当前进度的对外快照（截图验收 / smoke 断言读它）
func breath_state() -> Dictionary:
	return {
		"amp": amp,
		"period": period,
		"phase": base_phase,
		"mode": mode,
		"progress": current_progress(),
		"char_index": char_index,
		"use_layers": _mask_hair != null or _mask_face != null or _mask_body != null,
		"has_hair": _mask_hair != null,
		"has_face": _mask_face != null,
		"has_body": _mask_body != null,
		"hair_gain": hair_gain, "face_gain": face_gain, "body_gain": body_gain,
		"hair_phase": hair_phase, "face_phase": face_phase, "body_phase": body_phase,
		"has_tex": _tex != null,
		"frozen": _frozen,
		"cycle": _cycle,
		"offset": _offset,
	}


## 本角色此刻的有效进度（0..1）
func current_progress() -> float:
	if _frozen:
		return _frozen_progress
	return fposmod(_cycle + _offset + base_phase + CHAR_PHASE_STEP * float(char_index), 1.0)


# ── 对外：定格（截图钩子）────────────────────────────────────────────────
## 定格到某个进度。**暂停** Tween（不是杀掉，恢复时从原地续跑），立即按 p 重绘。
func debug_set_breath(p: float) -> void:
	_frozen = true
	_frozen_progress = fposmod(p, 1.0)
	visible = _tex != null
	if _tween != null and _tween.is_valid():
		_tween.pause()
	_apply()


## 恢复自动呼吸：Tween 从暂停处继续（相位不重置）
func debug_resume_breath() -> void:
	_frozen = false
	if _tween != null and _tween.is_valid():
		_tween.play()
	else:
		_restart_tween()      # Tween 被重建/回收过：补一条，别停在定格
	_apply()


## 是 debug_set_breath 的别名：verify 任务按 spec 里的名字调也能通
func debug_set_breath_progress(p: float) -> void:
	debug_set_breath(p)


# ── Tween：0→1 无限循环 ──────────────────────────────────────────────────
func _restart_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# 把当前输出折叠进 offset：重建后有效进度在那一刻完全连续（不会闪相位）
	_offset = fposmod(_offset + _cycle, 1.0)
	_cycle = 0.0
	if _frozen or not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_method(_set_cycle, 0.0, 1.0, maxf(0.05, period)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.set_loops()        # 0 = 无限：0→1→0 无缝衔接（两端速度都为 0）
	_tween = tw


func _set_cycle(v: float) -> void:
	if _frozen:
		return
	_cycle = v
	_apply()


# ── 把参数落到材质 / 变换上 ──────────────────────────────────────────────
func _apply() -> void:
	if _mat == null:
		return
	var p := current_progress()
	_mat.set_shader_parameter("progress", p)
	if mode == MODE_OFF:
		# 关闭：位移与缩放都归零 → 本层就是底图的精确复制，看不出任何差别
		_mat.set_shader_parameter("amp", 0.0)
		_mat.set_shader_parameter("axis", 0)
		scale = Vector2.ONE
		return
	if mode == MODE_SCALE:
		# 仅整图缩放：shader 位移关掉，改绕底边中点缩放。
		# 用 (1-cos)/2 而不是 raw sin：scale 恒 ≥ 1，左右永远不会露出底图外的缝。
		_mat.set_shader_parameter("amp", 0.0)
		var k: float = 0.5 * (1.0 - cos(p * TAU))
		var s: float = 1.0 + amp * SCALE_GAIN * k
		scale = Vector2(s, s)
		return
	# UV 起伏：上下（axis=0）/ 左右（axis=1）靠 shader 的 axis uniform 切换，
	# 两个轴互斥，所以永远不会出现「斜着走」的旋转观感。
	_mat.set_shader_parameter("amp", amp)
	_mat.set_shader_parameter("axis", 1 if mode == MODE_UV_HORZ else 0)
	# 三层各自的 gain / phase：这是「头发先动、身体跟上」的实现处
	_mat.set_shader_parameter("hair_gain", hair_gain)
	_mat.set_shader_parameter("face_gain", face_gain)
	_mat.set_shader_parameter("body_gain", body_gain)
	_mat.set_shader_parameter("hair_phase", hair_phase)
	_mat.set_shader_parameter("face_phase", face_phase)
	_mat.set_shader_parameter("body_phase", body_phase)
	scale = Vector2.ONE
