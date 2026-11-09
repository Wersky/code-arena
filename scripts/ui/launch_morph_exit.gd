class_name LaunchMorphExit
extends RefCounted
## 主界面「收缩 → 顶飞」退出动画（2026-11-09 主人要求：把 demo 第 8 页的动画用到真实主界面）。
##
## 作用于 LaunchScreen 的两个真实面板：
##   · 侧栏 SidePanel：上边固定，只改 size.y 向上收（900 → 300）
##   · Agent 对话框：收窄到与侧栏同宽、右边线对齐原侧栏右边线，再上移贴到侧栏底部下方
##   · 最后下框一路上冲，顶着侧栏一起弹出画面顶部
##
## 与 demo 的差异（真实面板才会遇到）：
##   - `_dialog.custom_minimum_size = (880,230)` 必须**先清零**，否则 size 会被钳在 880 宽，
##     收窄动画直接失效（实测确认）。旧值在复位时恢复。
##   - 面板里的内容控件会在收窄时被挤压 → 动画开始时先淡出内容（modulate:a → 0），
##     视觉上是「内容退场、空壳收缩」，比让文字挤成一坨干净。
##
## 用法：
##   var ex := LaunchMorphExit.new(sidebar, dialog)
##   await ex.play()          # 播完自动恢复可交互状态（不复位布局）
##   ex.restore_layout()      # 需要复原时再调

const SIDEBAR_BASE := Vector2(24.0, 0.0)
const SIDEBAR_W := 232.0
const SIDEBAR_H := 900.0
const DIALOG_BASE := Vector2(280.0, 670.0)
const DIALOG_W := 880.0
const DIALOG_H := 230.0

const SIDEBAR_COMPACT_H := 300.0
const DIALOG_COMPACT_W := SIDEBAR_W
const GAP := 12.0

const SIDEBAR_DUR := 0.55
const DIALOG_SHRINK := 0.45
const RISE_PUSH_DUR := 0.70
const ANTICIPATE_PX := 10.0
const ANTICIPATE_DUR := 0.09
const SIDEBAR_LAG := 0.07
const PUSH_DIST := SIDEBAR_COMPACT_H + GAP + DIALOG_H + 40.0
const TOTAL := DIALOG_SHRINK + ANTICIPATE_DUR + RISE_PUSH_DUR

var _sidebar: Control = null
var _dialog: Control = null
var _sb_old_custom_min := Vector2.ZERO
var _dl_old_custom_min := Vector2.ZERO
var _sb_size := Vector2.ZERO
var _sb_pos := Vector2.ZERO
var _dl_size := Vector2.ZERO
var _dl_pos := Vector2.ZERO
var _tw_sidebar: Tween = null
var _tw_dialog: Tween = null
## tween 必须由 Node 创建（RefCounted 没有 create_tween），所以持有一个宿主节点
var _host: Node = null
## 额外的退场节点（左下角图标入口等：不属于任何面板，但必须一起淡出，
## 否则面板飞走时它们会孤零零留在原地）
var _extras: Array[CanvasItem] = []


func _init(sidebar: Control, dialog: Control, host: Node = null) -> void:
	_sidebar = sidebar
	_dialog = dialog
	_host = host
	if _host == null and sidebar != null:
		_host = sidebar.get_tree().current_scene if sidebar.is_inside_tree() else null
	if _sidebar != null:
		_sb_old_custom_min = _sidebar.custom_minimum_size
		_sb_size = _sidebar.size
		_sb_pos = _sidebar.position
		_sidebar.offset_transform_enabled = true
	if _dialog != null:
		_dl_old_custom_min = _dialog.custom_minimum_size
		_dl_size = _dialog.size
		_dl_pos = _dialog.position
		_dialog.offset_transform_enabled = true
	# 收集「不属面板、但在主界面上」的控件（图标入口 / 背景雨不淡出，避免整屏变黑）
	if _host != null:
		for child in _host.get_children():
			if child is CanvasItem and child != _sidebar and child != _dialog:
				if child is TextureButton or child is Button:
					_extras.append(child)


func _orig_sidebar_right() -> float:
	return SIDEBAR_BASE.x + SIDEBAR_W


func _dialog_compact_x() -> float:
	return _orig_sidebar_right() - DIALOG_COMPACT_W


func _dialog_rise_y() -> float:
	return SIDEBAR_BASE.y + SIDEBAR_COMPACT_H + GAP


func _rise_push_dist() -> float:
	return (DIALOG_BASE.y - _dialog_rise_y()) + PUSH_DIST


## ②③ 合体驱动：k=0 起始 → k=1 两框完全出画。
## 走渲染通道 offset_transform_position（4.7）：真实 position/size 不动，
## 不触发容器重排、kill 后无脏状态、不受 min-size 钳制。
func _set_rise_push(k: float) -> void:
	if _dialog == null or _sidebar == null:
		return
	var dy: float = -_rise_push_dist() * k
	_dialog.offset_transform_position = Vector2(0.0, dy)
	var contact: float = _dialog_rise_y() - DIALOG_BASE.y     # 负值
	_sidebar.offset_transform_position = Vector2(0.0, minf(0.0, dy - contact))


## 播放完整退出动画（await 直到两框完全飞出画面）
func play() -> void:
	if _sidebar == null or _dialog == null:
		return
	_kill()
	# 关键：真实面板的 custom_minimum_size 会把 size 钳死，先清零才能收窄
	_sidebar.custom_minimum_size = Vector2.ZERO
	_dialog.custom_minimum_size = Vector2.ZERO
	_sidebar.size = Vector2(SIDEBAR_W, SIDEBAR_H)
	_sidebar.position = SIDEBAR_BASE
	_sidebar.offset_transform_position = Vector2.ZERO
	_dialog.position = DIALOG_BASE
	_dialog.size = Vector2(DIALOG_W, DIALOG_H)
	_dialog.offset_transform_position = Vector2.ZERO

	# 内容淡出：面板里塞着输入框/按钮/标签，收窄时会被挤成一坨 → 先让内容退场；
	# 左下角的图标入口不属任何面板，也必须一起淡出，否则面板飞走后它们会留在原地
	if _host != null:
		for panel in [_sidebar, _dialog]:
			for child in panel.get_children():
				if child is CanvasItem:
					var ctw := _host.create_tween()
					ctw.tween_property(child, "modulate:a", 0.0, 0.18)
		for extra in _extras:
			if is_instance_valid(extra):
				var etw := _host.create_tween()
				etw.tween_property(extra, "modulate:a", 0.0, 0.18)

	# ① 左框：只改 size（上边固定），比下框晚 SIDEBAR_LAG 启动（secondary motion）
	_tw_sidebar = _host.create_tween() if _host != null else null
	if _tw_sidebar == null:
		return
	_tw_sidebar.set_ignore_time_scale(true)
	_tw_sidebar.tween_interval(SIDEBAR_LAG)
	_tw_sidebar.tween_property(_sidebar, "size",
			Vector2(SIDEBAR_W, SIDEBAR_COMPACT_H), SIDEBAR_DUR) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# ②③ 下框：收窄 + 右移 → 蓄力 → 一路上冲顶飞
	var compact := Vector2(DIALOG_COMPACT_W, DIALOG_H)
	_tw_dialog = _host.create_tween()
	_tw_dialog.set_ignore_time_scale(true)
	_tw_dialog.set_parallel(true)
	_tw_dialog.tween_property(_dialog, "size", compact, DIALOG_SHRINK) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw_dialog.tween_property(_dialog, "position:x", _dialog_compact_x(), DIALOG_SHRINK) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw_dialog.chain().tween_property(_dialog, "offset_transform_position:y",
			ANTICIPATE_PX, ANTICIPATE_DUR) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tw_dialog.chain().tween_method(_set_rise_push, 0.0, 1.0, RISE_PUSH_DUR) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _tw_dialog.finished


## 复原布局（用于「返回主界面」时重建，正常退出流程不需要）
func restore_layout() -> void:
	_kill()
	if _sidebar != null:
		_sidebar.position = _sb_pos
		_sidebar.size = _sb_size
		_sidebar.custom_minimum_size = _sb_old_custom_min
		_sidebar.offset_transform_position = Vector2.ZERO
		for child in _sidebar.get_children():
			if child is CanvasItem:
				child.modulate.a = 1.0
	if _dialog != null:
		_dialog.position = _dl_pos
		_dialog.size = _dl_size
		_dialog.custom_minimum_size = _dl_old_custom_min
		_dialog.offset_transform_position = Vector2.ZERO
		for child in _dialog.get_children():
			if child is CanvasItem:
				child.modulate.a = 1.0
	for extra in _extras:
		if is_instance_valid(extra):
			extra.modulate.a = 1.0


func _kill() -> void:
	if _tw_sidebar != null and _tw_sidebar.is_valid():
		_tw_sidebar.kill()
	if _tw_dialog != null and _tw_dialog.is_valid():
		_tw_dialog.kill()
	_tw_sidebar = null
	_tw_dialog = null


## 供测试/验收：定格到指定进度（0=起始，1=完全飞出）
func debug_set_progress(p: float) -> void:
	_kill()
	if _sidebar == null or _dialog == null:
		return
	_sidebar.custom_minimum_size = Vector2.ZERO
	_dialog.custom_minimum_size = Vector2.ZERO
	var t: float = clampf(p, 0.0, 1.0) * TOTAL
	# 内容淡出进度与真播一致（0~0.18s 内淡完），定格帧才看得出真实效果
	var fade_a: float = clampf(1.0 - t / 0.18, 0.0, 1.0)
	for panel in [_sidebar, _dialog]:
		for child in panel.get_children():
			if child is CanvasItem:
				child.modulate.a = fade_a
	for extra in _extras:
		if is_instance_valid(extra):
			extra.modulate.a = fade_a
	var k1: float = clampf((t - SIDEBAR_LAG) / SIDEBAR_DUR, 0.0, 1.0)
	var ks: float = clampf(t / DIALOG_SHRINK, 0.0, 1.0)
	var ka: float = clampf((t - DIALOG_SHRINK) / ANTICIPATE_DUR, 0.0, 1.0)
	var tp: float = clampf((t - DIALOG_SHRINK - ANTICIPATE_DUR) / RISE_PUSH_DUR, 0.0, 1.0)
	var k_anticipate: float = sin(PI * 0.5 * ka)
	var k_fly: float = tp * tp
	_sidebar.position = SIDEBAR_BASE
	_sidebar.size = Vector2(SIDEBAR_W, lerpf(SIDEBAR_H, SIDEBAR_COMPACT_H, k1))
	_dialog.size = Vector2(lerpf(DIALOG_W, DIALOG_COMPACT_W, ks), DIALOG_H)
	_dialog.position = Vector2(lerpf(DIALOG_BASE.x, _dialog_compact_x(), ks), DIALOG_BASE.y)
	_set_rise_push(k_fly)
	if k_fly <= 0.0:
		_dialog.offset_transform_position = Vector2(0.0, ANTICIPATE_PX * k_anticipate)
