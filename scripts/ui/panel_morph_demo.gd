class_name PanelMorphDemo
extends Control
## 面板动态伸缩演示（2026-11-09 主人要求，第三轮修订）：
## 模仿主界面布局（左侧竖框 + 下方横框），点击按钮后：
##   ① 两框**同时**开始收缩，各自收完即停、互不牵连：
##        左边框向上收缩（**上边固定不动**，只改 size.y，下边向上挪）
##        下边框向左收缩到左下角，**右边线与「原左边框」右边线对齐**，再整体上移
##   ② 左边框先收完（0.55s）先停住；下边框后收完（0.95s）
##   ③ 下边框升到位后**继续上冲，顶着左边框一起弹射出画面**（两者刚性同速上移）
##
## 关键实现要点（Godot Control 动画坑）：
##   - PanelContainer 会自动被内容撑回最小尺寸 → 收缩前必须把 custom_minimum_size 一起改，
##     并且先 set_anchors_preset(PRESET_TOP_LEFT) 让 position/size 完全受控（不被父容器布局覆盖）
##   - 上边不动 = 只改 size.y，不改 position.y；下边向上挪是 size 变化的自然结果
##   - 右对齐基准取「原左边框」= SIDEBAR_BASE.x + SIDEBAR_W（动画中途左边框会变窄，
##     但它自己会同时收缩，所以对齐基准必须是动画前的常量，不能用 _sidebar.size.x）
##   - 第三段联动：两框用同一位移量 + 同一时长并行 tween，相对位置天然保持（不用手算跟随）

signal back_requested

const SIDEBAR_BASE := Vector2(24.0, 0.0)
const SIDEBAR_W := 232.0
const SIDEBAR_H := 900.0
const DIALOG_BASE := Vector2(280.0, 670.0)
const DIALOG_W := 880.0
const DIALOG_H := 230.0

## 收缩终态
const SIDEBAR_COMPACT_H := 300.0
## 左边框只做竖向收缩（主人只要求上下边），宽度不变 → 终态与下边框左右边都齐平
const SIDEBAR_COMPACT_W := SIDEBAR_W
const DIALOG_COMPACT_W := SIDEBAR_W              ## 收窄到与原左边框同宽 → 右边线正好落在原右边线上
const GAP := 12.0                                ## 下边框上移后与左边框底部的间距

## 时间轴（下边框三段串行；左边框 0.55s 先结束）
const SIDEBAR_DUR := 0.55
const DIALOG_SHRINK := 0.45
const DIALOG_RISE := 0.50
const PUSH_DUR := 0.55
## 弹出距离 = 整个立柱高度（左框 + 间距 + 下框）+ 余量，保证两者完全离开画面顶部
const PUSH_DIST := SIDEBAR_COMPACT_H + GAP + DIALOG_H + 40.0
const MORPH_TOTAL := SIDEBAR_DUR + DIALOG_RISE + PUSH_DUR   ## 完整时间轴总长 = 1.60s

var _sidebar: PanelContainer = null
var _dialog: PanelContainer = null
var _status: Label = null
var _btn: Button = null
var _reset_btn: Button = null
var _tw_sidebar: Tween = null
var _tw_dialog: Tween = null
var _tw_push: Tween = null
var _busy := false
var _pending := 0                                  ## 尚未收完的框数量（=0 时解锁按钮）


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


## 原左边框右边线 x：整个动画期间恒定，作为下边框的右对齐基准
func _orig_sidebar_right() -> float:
	return SIDEBAR_BASE.x + SIDEBAR_W


## 下边框收窄后的左边界 x（右边界 = 原左边框右边线）
func _dialog_compact_x() -> float:
	return _orig_sidebar_right() - DIALOG_COMPACT_W


## 下边框上移后的顶部 y（贴到左边框最终底部下方）
func _dialog_rise_y() -> float:
	return SIDEBAR_BASE.y + SIDEBAR_COMPACT_H + GAP


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.016, 0.032)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := UiKit.label("面板动态伸缩演示", 30, Color(0.92, 0.95, 1.0))
	title.position = Vector2(300, 40)
	add_child(title)
	var sub := UiKit.dim(
			"两框同时收缩 → 左框先收完停住 → 下框收到左下（右边线对齐原左框右边线 x=%.0f）→ 下框上冲顶着左框一起弹出画面" % _orig_sidebar_right(),
			15, Color(0.55, 0.72, 0.9))
	sub.position = Vector2(302, 84)
	add_child(sub)

	var back := UiKit.accent_button("← 返回", 16)
	back.position = Vector2(1330, 48)
	back.size = Vector2(150, 44)
	back.pressed.connect(func() -> void: back_requested.emit())
	add_child(back)

	# 左框（模仿主界面 SidePanel）：上边固定 y=0
	_sidebar = _make_panel("左框 Sidebar", Vector2(SIDEBAR_BASE),
			Vector2(SIDEBAR_W, SIDEBAR_H),
			Color(0.045, 0.06, 0.10), Color(0.20, 0.28, 0.45))
	# 下框（模仿主界面 AgentDialog）
	_dialog = _make_panel("下框 Dialog", Vector2(DIALOG_BASE),
			Vector2(DIALOG_W, DIALOG_H),
			Color(0.055, 0.075, 0.12), Color(0.22, 0.32, 0.5))

	_btn = UiKit.accent_button("▶ 播放收缩动画", 20)
	_btn.position = Vector2(300, 250)
	_btn.size = Vector2(260, 56)
	_btn.pressed.connect(_play_morph)
	add_child(_btn)

	_reset_btn = UiKit.button("↻ 复位", 18)
	_reset_btn.position = Vector2(590, 250)
	_reset_btn.size = Vector2(150, 56)
	_reset_btn.pressed.connect(_reset_layout)
	add_child(_reset_btn)

	_status = UiKit.dim("待播放", 16, Color(0.6, 0.85, 1.0))
	_status.position = Vector2(300, 330)
	_status.size = Vector2(900, 30)
	add_child(_status)


func _make_panel(nm: String, pos: Vector2, sz: Vector2, fill: Color, line: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = nm
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = line
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.position = pos
	p.size = sz
	p.custom_minimum_size = Vector2.ZERO   # 不靠内容撑大小，完全由动画控制
	p.clip_contents = true
	add_child(p)

	var lbl := UiKit.label(nm, 20, Color(0.55, 0.85, 1.0))
	lbl.position = Vector2(16, 12)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl)
	return p


## 主演示：两框同时开始 → 左框先停 → 下框收完后顶左框一起飞出
func _play_morph() -> void:
	if _busy:
		return
	_busy = true
	_pending = 2
	_kill_tweens()
	_btn.disabled = true
	_status.text = "① 两个框同时收缩中…"

	# ① 左边框：只改 size（position 不动 → 上边固定），0.55s 先结束
	_tw_sidebar = create_tween().set_parallel(true)
	_tw_sidebar.tween_property(_sidebar, "size",
			Vector2(SIDEBAR_COMPACT_W, SIDEBAR_COMPACT_H), SIDEBAR_DUR) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw_sidebar.chain().tween_callback(func() -> void:
		_status.text = "左边框已收好并停住；下边框继续…"
		_morph_done())

	# ② 下边框：同一帧开始。第一段「向左收窄 + 右移到左下角」，第二段「整体上移」
	var compact := Vector2(DIALOG_COMPACT_W, DIALOG_H)
	var at_bottom_left := Vector2(_dialog_compact_x(), DIALOG_BASE.y)
	var risen := Vector2(_dialog_compact_x(), _dialog_rise_y())
	_tw_dialog = create_tween()
	_tw_dialog.set_parallel(true)
	_tw_dialog.tween_property(_dialog, "size", compact, DIALOG_SHRINK) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw_dialog.tween_property(_dialog, "position", at_bottom_left, DIALOG_SHRINK) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw_dialog.chain().tween_property(_dialog, "position", risen, DIALOG_RISE) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# ③ 升到位后继续上冲，把左框一并顶出画面
	_tw_dialog.chain().tween_callback(_start_push)


## ③ 弹射：下框继续向上，左框被它顶住同速上移（同一位移量 + 同一时长 → 相对位置不变）
func _start_push() -> void:
	if _status != null:
		_status.text = "③ 下框顶住左框，两框一起弹出画面…"
	var up := Vector2(0.0, -PUSH_DIST)
	_tw_push = create_tween().set_parallel(true)
	_tw_push.tween_property(_dialog, "position", _dialog.position + up, PUSH_DUR) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tw_push.tween_property(_sidebar, "position", _sidebar.position + up, PUSH_DUR) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tw_push.chain().tween_callback(func() -> void: _morph_done())


## 每个框收完各报一票，全部阶段走完才解锁按钮
func _morph_done() -> void:
	_pending = maxi(_pending - 1, 0)
	if _pending > 0:
		return
	_busy = false
	if _btn != null:
		_btn.disabled = false
	_status.text = "✓ 完成：左框先收到高 %.0f 停住（上边固定），下框右边线对齐 x=%.0f 后上冲，两框一起弹出画面" % [
		SIDEBAR_COMPACT_H, _orig_sidebar_right()]


func _reset_layout() -> void:
	_kill_tweens()
	_busy = false
	_pending = 0
	if _btn != null:
		_btn.disabled = false
	if _sidebar != null:
		_sidebar.position = SIDEBAR_BASE
		_sidebar.size = Vector2(SIDEBAR_W, SIDEBAR_H)
	if _dialog != null:
		_dialog.position = DIALOG_BASE
		_dialog.size = Vector2(DIALOG_W, DIALOG_H)
	if _status != null:
		_status.text = "已复位，可再次播放"


func _kill_tweens() -> void:
	if _tw_sidebar != null and _tw_sidebar.is_valid():
		_tw_sidebar.kill()
	if _tw_dialog != null and _tw_dialog.is_valid():
		_tw_dialog.kill()
	if _tw_push != null and _tw_push.is_valid():
		_tw_push.kill()
	_tw_sidebar = null
	_tw_dialog = null
	_tw_push = null


## 逐帧验收钩子：直接停在指定进度（0=原始布局，1=两框都飞出画面）。
## 时间轴与真实 Tween 完全一致：左框 [0,0.55]；下框 [0,0.45] 收 + [0.45,0.95] 上移
## + [0.95,1.50] 弹出画面。
func debug_set_morph(p: float) -> void:
	_kill_tweens()
	_busy = false
	_pending = 0
	var t: float = clampf(p, 0.0, 1.0) * MORPH_TOTAL
	var k1: float = clampf(t / SIDEBAR_DUR, 0.0, 1.0)
	var ks: float = clampf(t / DIALOG_SHRINK, 0.0, 1.0)
	var kr: float = clampf((t - DIALOG_SHRINK) / DIALOG_RISE, 0.0, 1.0)
	var kp: float = clampf((t - DIALOG_SHRINK - DIALOG_RISE) / PUSH_DUR, 0.0, 1.0)
	if _sidebar != null:
		_sidebar.position = SIDEBAR_BASE + Vector2(0.0, -PUSH_DIST * kp)
		_sidebar.size = Vector2(
				lerpf(SIDEBAR_W, SIDEBAR_COMPACT_W, k1),
				lerpf(SIDEBAR_H, SIDEBAR_COMPACT_H, k1))
	if _dialog != null:
		_dialog.size = Vector2(lerpf(DIALOG_W, DIALOG_COMPACT_W, ks), DIALOG_H)
		_dialog.position = Vector2(
				lerpf(DIALOG_BASE.x, _dialog_compact_x(), ks),
				lerpf(DIALOG_BASE.y, _dialog_rise_y(), kr) - PUSH_DIST * kp)
	if _status != null:
		_status.text = "调试进度 %.0f%%" % (clampf(p, 0.0, 1.0) * 100.0)
