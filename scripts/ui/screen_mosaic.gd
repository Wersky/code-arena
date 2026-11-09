class_name ScreenMosaic
extends Control
## 全屏马赛克转场（2026-11-09 主人要求）：
## 「初始化界面 → 选角界面」过渡，风格对齐「终端 → Godot 立绘」那段马赛克加载。
##
## 为什么不用 hint_screen_texture：本项目走 gl_compatibility 渲染器，
## backbuffer 采样在该后端不可靠（实测遮罩全透明、画面毫无变化）。
## 改为**冻结帧**方案：先把当前画面抓成 ImageTexture 铺满全屏，
## 再逐帧生成降采样→放大（最近邻）的块化贴图。渲染器无关，且能精确控制块大小。
##
## 用法：
##   var m := ScreenMosaic.new()
##   add_child(m)              # 必须压在场景之上
##   await m.cover(0.45)       # 抓当前画面 → 逐渐块化到糊掉
##   <换场景>
##   await m.reveal(0.45)      # 从糊到清晰；结束后自行 queue_free 由调用方决定

## **块数语义（极易搞反）**：blocks = 横排块数。blocks 大 → 块小 → 清晰；blocks=1 → 整屏一块 → 最糊。
## 所以 cover() 是 FINE→COARSE，reveal() 是 COARSE→FINE。
const FINE_BLOCKS := 400     ## 清晰档（>= 屏幕像素列数即完全清晰，400 足够）
const COARSE_BLOCKS := 1     ## 极限档：整屏一块（**转场不使用**，见 PEAK_BLOCKS）
## 转场实际峰值：横排 48 块（1600 宽下约 33px 一块）。
## 为什么不用 COARSE_BLOCKS=1：整屏变成一个平均色时看起来只是「淡出成纯色」，
## 看不出任何马赛克 —— 主人反馈「马赛克化没出现」正是此因。
## 48 块：方块颗粒清楚可辨，画面结构（面板轮廓、代码雨分布）仍在，
## 不会糊成一片深色让观众以为"画面灭了"。
const PEAK_BLOCKS := 48
## 过渡阶梯：索引 0 = 清晰，末尾 = 最糊
const STEPS := [400, 160, 96, 64, 44, 30, 20, 13, 8, 5, 3, 2, 1]

var _tex_rect: TextureRect = null
var _snapshot: Image = null
var _cur_blocks := 400         ## 当前横排块数（越大越清晰）


func _ready() -> void:
	# 注意：_init 里调 set_anchors_preset 时还没有父节点，尺寸算不出来会留下 (0,0)；
	# 必须在 _ready（已入树）再设一次，并用 anchors+offset 双保险铺满全屏。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex_rect = TextureRect.new()
	_tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# 最近邻放大：块边缘必须是硬的，这是「像素材质」的关键
	_tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex_rect)
	visible = false


## 抓当前屏幕（必须在遮罩隐藏状态下调用，否则抓到自己）
func grab() -> void:
	visible = false
	await get_tree().process_frame
	var vp := get_viewport()
	if vp == null:
		return
	var img := vp.get_texture().get_image()
	if img == null:
		return
	_snapshot = img
	_apply_blocks(FINE_BLOCKS)


## 按块数（横排块数）生成块化贴图并贴上去
func _apply_blocks(blocks: int) -> void:
	if _snapshot == null or _tex_rect == null:
		return
	var w := int(maxi(1, blocks))
	var sw := _snapshot.get_width()
	var sh := _snapshot.get_height()
	if sw <= 0 or sh <= 0:
		return
	var h := int(maxi(1, round(float(sh) / float(sw) * float(w))))
	var small := _snapshot.duplicate() as Image
	small.resize(w, h, Image.INTERPOLATE_BILINEAR)
	small.resize(sw, sh, Image.INTERPOLATE_NEAREST)
	_tex_rect.texture = ImageTexture.create_from_image(small)
	_cur_blocks = w
	# 注意：这里**不**设 visible。可见性必须由调用方显式控制。
	# 早期版本在此 visible=true，导致 grab() 抓完帧就把遮罩盖上去，
	# 后面的面板退出动画全在冻结截图底下播、观众完全看不见（主人实测反馈）。


## 块化：画面逐渐糊掉（blocks FINE → PEAK，停在能看清方块颗粒的档位）
func cover(dur: float = 0.45) -> void:
	if _snapshot == null:
		await grab()
	if _snapshot == null:
		return
	visible = true
	# 注意：这里曾写成 1.0 → peak(=1)，全程停在 blocks=1（整屏一个平均色），
	# 视觉上只是「淡出成纯色」，完全看不到马赛克 —— 这就是主人反馈
	# 「马赛克化没出现」的根因。必须从 FINE_BLOCKS 往 PEAK_BLOCKS 插值。
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_apply_blocks(int(round(v))), float(FINE_BLOCKS), float(PEAK_BLOCKS),
			maxf(0.05, dur)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	_apply_blocks(PEAK_BLOCKS)


## 换场景后重新抓帧：遮罩先藏一帧抓新画面，再以「最糊」状态贴回去。
## 这样 reveal 消退的是**新界面**的块化版，而不是旧界面的残影。
func recapture() -> void:
	if _tex_rect == null:
		return
	_tex_rect.visible = false
	visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport()
	if vp == null:
		return
	var img := vp.get_texture().get_image()
	if img != null:
		_snapshot = img
	_apply_blocks(PEAK_BLOCKS)
	visible = true


## 消退：从当前块化状态回到清晰，最后隐藏（让真实画面露出来）
func reveal(dur: float = 0.45) -> void:
	if _snapshot == null or _tex_rect == null:
		visible = false
		return
	var from_blocks := _cur_blocks
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_apply_blocks(int(round(v))), float(from_blocks), float(FINE_BLOCKS),
			maxf(0.05, dur)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	visible = false


## 调试/逐帧验收：按 STEPS 索引设档（0=清晰，最后=整屏一块）
func debug_set_step(index: int) -> void:
	if _snapshot == null:
		return
	var i: int = clampi(index, 0, STEPS.size() - 1)
	_apply_blocks(int(STEPS[i]))
	visible = true


## 调试用：块数直接给（1..48）
func debug_set_blocks(blocks: int) -> void:
	_apply_blocks(maxi(1, blocks))
	visible = true      # 调试接口：设了块数就是要看，必须显示


func has_snapshot() -> bool:
	return _snapshot != null
