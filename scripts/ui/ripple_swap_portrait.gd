class_name RippleSwapPortrait
extends Control
## 角色立绘转场控件（2026-11-08 起**一人一款**）：
##   - RIPPLE 水波扩散（DeepDeek 女仆·柔和向）：中心水花不规则扩散，波内显现新立绘
##   - FAN    折扇开屏（Kweno 千金·青花折扇）：扇面从左往右逐扇骨展开
##   - SLASH  X 双斩（Grock 毒舌小恶魔·扛 X 巨斧）：两道剑光交叉劈开，四片滑开坠落
##   - HEX    龙鳞剥落（ChatPPT 白龙千金）：六边形鳞片底部先剥、沿线翘金边
##
## 用法：
##   set_portrait(tex_a)          → 初始立绘
##   swap_to(tex_b)               → 按 style 播转场，结束后 tex_b 成为当前立绘
##   debug_prepare(a, b) + debug_set_progress(p) → 逐帧验收
## 约束：tex_prev/tex_next 用同宽高比贴图（内部按 UV 直采）。

signal swap_finished

enum Style { RIPPLE, FAN, SLASH, HEX }

const SHADERS := {
	Style.RIPPLE: preload("res://assets/shaders/ripple_reveal.gdshader"),
	Style.FAN: preload("res://assets/shaders/fan_sprite_reveal.gdshader"),
	Style.SLASH: preload("res://assets/shaders/x_slash.gdshader"),
	Style.HEX: preload("res://assets/shaders/hex_scale.gdshader"),
}
## 实物扇子素材（2026-11-08 主人定稿：像素风扇布——合拢竖在左缘，展开扫满全画框，无支架）
const FAN_TEX_CLOTH_PX := preload("res://assets/art/fx/fan-cloth-pixel.png")
## 画面侧扇轴（左下角内收一点）
const FAN_PIVOT_S := Vector2(0.06, 0.94)
## 一次 swap 的总时长（秒）。demo 页有调速滑杆，主人的数值存 GameSettings 跨启动记住。
var swap_time := 0.7
var style: int = Style.RIPPLE

var _mat: ShaderMaterial = null
var _swapping := false
var _current: Texture2D = null
## 实物扇子（FAN 风格专用）：合拢扇精灵 + 角度揭示 shader
var _fan_closed: TextureRect = null
var _fan_swapped := false   ## 盖满后，背后已换成新立绘
var _fan_next: Texture2D = null


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := ColorRect.new()
	rect.name = "RippleRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADERS[style]
	_mat.set_shader_parameter("progress", 0.0)
	rect.material = _mat
	add_child(rect)
	resized.connect(_update_geo)
	_update_geo()
	_build_fan_sprites()


func _build_fan_sprites() -> void:
	# 合拢态 = 扇布收成的窄竖条，贴在立绘左边缘（像素布裁条，无骨）
	_fan_closed = TextureRect.new()
	_fan_closed.name = "FanClosed"
	var at := AtlasTexture.new()
	at.atlas = FAN_TEX_CLOTH_PX
	at.region = Rect2(0, 0, 13, 128)   ## 布贴图最左一条 ≈ 收拢的扇布
	_fan_closed.texture = at
	_fan_closed.position = Vector2.ZERO
	_fan_closed.size = Vector2(52, 512)  ## 13px ×4，立在左缘
	_fan_closed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fan_closed.stretch_mode = TextureRect.STRETCH_SCALE
	_fan_closed.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fan_closed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fan_closed.visible = false
	add_child(_fan_closed)


func _update_geo() -> void:
	if _mat == null or size.y <= 0.0:
		return
	var asp := size.x / size.y
	_mat.set_shader_parameter("aspect", asp)
	# max_dist：水波用（中心到最远角，aspect 校正 + 少量余量）；其余风格忽略它
	_mat.set_shader_parameter("max_dist", Vector2(0.5 * asp, 0.5).length() + 0.02)


func set_portrait(tex: Texture2D) -> void:
	_current = tex
	if _mat != null:
		_mat.set_shader_parameter("tex_prev", tex)
		_mat.set_shader_parameter("progress", 0.0)


func swap_to(tex: Texture2D) -> void:
	if _swapping or tex == null or _mat == null or tex == _current:
		return
	_swapping = true
	if style == Style.FAN:
		# 实物扇子：合拢扇啪上对角线 → 扇骨从对角线向两侧开花盖满 → 背后换图 → 逆向收拢
		_fan_swapped = false
		_fan_next = tex
		_mat.shader = SHADERS[style]
		_mat.set_shader_parameter("tex_fan", FAN_TEX_CLOTH_PX)
		_mat.set_shader_parameter("tex_next", tex)
		_mat.set_shader_parameter("sweep", 0.0)
		_mat.set_shader_parameter("dim", 0.0)
		_update_fan_geo()
		_fan_closed.visible = false
		var tw := create_tween()
		tw.tween_method(_apply_fan, 0.0, 1.0, maxf(0.05, swap_time))
		tw.tween_callback(func() -> void:
			_fan_closed.visible = false
			_mat.set_shader_parameter("tex_prev", tex)
			_mat.set_shader_parameter("sweep", 0.0)
			_mat.set_shader_parameter("dim", 0.0)
			_current = tex
			_swapping = false
			swap_finished.emit())
		return
	_mat.shader = SHADERS[style]          # 转场风格在开跑瞬间切换
	_mat.set_shader_parameter("tex_next", tex)
	_mat.set_shader_parameter("progress", 0.0)
	_update_geo()
	if style == Style.SLASH:
		_apply_slash_params(true)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_mat.set_shader_parameter("progress", v), 0.0, 1.0, maxf(0.05, swap_time)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		_mat.set_shader_parameter("tex_prev", tex)
		_mat.set_shader_parameter("progress", 0.0)
		_current = tex
		_swapping = false
		swap_finished.emit())


## 乱斩参数（随机种子）：6 刀，角度/截距/起刀时刻全随机；第一刀偏中保证切得大。
## shake=true 时每刀落下画面小震一下。
func _apply_slash_params(shake: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var arr := PackedVector4Array()
	for k in 6:
		var ang := deg_to_rad(rng.randf_range(-80.0, 80.0))
		var c: float = rng.randf_range(-0.12, 0.12) if k == 0 else rng.randf_range(-0.34, 0.34)
		var delay: float = 0.08 + k * 0.088 + rng.randf_range(-0.015, 0.015)
		arr.append(Vector4(cos(ang), sin(ang), c, delay))
	_mat.set_shader_parameter("slashes", arr)
	_mat.set_shader_parameter("seed_n", rng.randf_range(0.0, 10.0))
	if not shake:
		return
	var base_pos := position
	var dur := maxf(0.05, swap_time)
	for k in 6:
		var sh := create_tween()
		sh.tween_interval(arr[k].w * dur)
		for i in 3:
			sh.tween_property(self, "position",
					base_pos + Vector2(randf_range(-7.0, 7.0), randf_range(-6.0, 6.0)), 0.025)
		sh.tween_property(self, "position", base_pos, 0.04)


## 实物扇子分镜（p 0→1，由 tween/逐帧验收推进）：
##   0~0.16  啪：合拢扇拍上立绘（回弹缩小）
##   0.16~0.46 从中间向左右展开（scale.x 中心为轴 0→1），完全遮住立绘
##   0.46~0.56 扇面定住——p≥0.5 时背后已换成新立绘
##   0.56~0.88 逆向收扇（scale.x 1→0），露出新立绘
##   0.88~1  合拢扇滑走淡出
func _update_fan_geo() -> void:
	if _mat == null or size.y <= 0.0:
		return
	var asp := size.x / size.y
	## 像素扇布：起始角（左缘略过，兜住左上角）与终止角（右缘略过，兜住右下角）
	_mat.set_shader_parameter("pivot_s", FAN_PIVOT_S)
	_mat.set_shader_parameter("a_start", -95.0)
	_mat.set_shader_parameter("a_end", 8.0)
	_mat.set_shader_parameter("r_scale", 0.6)
	_mat.set_shader_parameter("aspect", asp)


func _apply_fan(p: float) -> void:
	if _fan_closed == null or _mat == null:
		return
	# 合拢扇布竖条：贴左缘立着，绕底部扇轴（左下）做回弹
	_fan_closed.pivot_offset = Vector2(size.x * 0.05, size.y * 0.97)
	var sweep := 0.0
	var dim := 0.0
	var rim := 0.0
	if p < 0.14:
		# 啪：收拢的扇布在左缘立起来（回弹放大落定）
		var k: float = p / 0.14
		_fan_closed.visible = true
		_fan_closed.modulate = Color(1, 1, 1, clampf(k * 2.0, 0.0, 1.0))
		_fan_closed.scale = Vector2(1.3 - 0.3 * smoothstep(0.0, 1.0, k), 1.0)
	elif p < 0.38:
		# 勾边：金色扇沿弧线从左缘画到另一侧（整个扇子的边沿先出现）
		var k: float = (p - 0.14) / 0.24
		rim = smoothstep(0.0, 1.0, k)
		dim = 0.18
		_fan_closed.visible = k < 0.3
		_fan_closed.modulate = Color(1, 1, 1, clampf(1.0 - k / 0.3, 0.0, 1.0))
	elif p < 0.62:
		# 潇洒铺布：扇布沿着已画好的边沿从左缘铺满全画框
		var k: float = (p - 0.38) / 0.24
		sweep = smoothstep(0.0, 1.0, k)
		rim = 1.0
		dim = 0.18 + 0.77 * sweep
		_fan_closed.visible = false
	elif p < 0.68:
		# 盖满：定住（背后已换成新立绘）
		sweep = 1.0
		rim = 1.0
		dim = 0.95
		_fan_closed.visible = false
	elif p < 0.9:
		# 逆向：扇布合回左缘（金沿重现），露出新立绘
		var k: float = (p - 0.68) / 0.22
		sweep = 1.0 - smoothstep(0.0, 1.0, k)
		rim = 1.0
		dim = 0.95 * sweep
		_fan_closed.visible = false
	else:
		# 收尾：边沿淡出
		var k: float = (p - 0.9) / 0.1
		sweep = 0.0
		rim = 1.0 - k
		dim = 0.0
		_fan_closed.visible = false
	_fan_closed.rotation_degrees = 0.0
	_mat.set_shader_parameter("sweep", sweep)
	_mat.set_shader_parameter("dim", dim)
	_mat.set_shader_parameter("outline", rim)
	# 完全盖住的瞬间，背后换成新立绘
	if p >= 0.62 and not _fan_swapped and _fan_next != null:
		_mat.set_shader_parameter("tex_prev", _fan_next)
		_current = _fan_next
		_fan_swapped = true


func is_swapping() -> bool:
	return _swapping


## 逐帧验收：把两张图摆好、直接停在某个进度（不播动画）
func debug_prepare(prev: Texture2D, next: Texture2D) -> void:
	_swapping = false
	_mat.shader = SHADERS[style]
	_mat.set_shader_parameter("tex_prev", prev)
	_mat.set_shader_parameter("tex_next", next)
	_mat.set_shader_parameter("progress", 0.0)
	_update_geo()
	_current = prev
	if style == Style.FAN:
		_fan_swapped = false
		_fan_next = next
		_mat.set_shader_parameter("tex_fan", FAN_TEX_CLOTH_PX)
		_update_fan_geo()
		_fan_closed.visible = false
	elif style == Style.SLASH:
		_apply_slash_params(false)


func debug_set_progress(p: float) -> void:
	if style == Style.FAN:
		_apply_fan(clampf(p, 0.0, 1.0))
	elif _mat != null:
		_mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))
