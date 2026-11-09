class_name PanelMorphDemo
extends Control
## 面板动态伸缩演示（2026-11-09 主人要求，第四轮修订）：
## 模仿主界面布局（左侧竖框 + 下方横框），点击按钮后：
##   ① 两框**同时**开始收缩，各自收完即停、互不牵连：
##        左边框向上收缩（**上边固定不动**，只改 size.y，下边向上挪）
##        下边框向左收缩到左下角，**右边线与「原左边框」右边线对齐**
##   ② 下边框一路向上：先升到左框底部，**碰到左框后不停顿**，继续顶着左框
##      一起冲上去，两框同时弹出画面顶部（②③ 是**同一条连续曲线**）
##
## 关键实现要点（Godot Control 动画坑）：
##   - PanelContainer 会自动被内容撑回最小尺寸 → 收缩前必须把 custom_minimum_size 一起改，
##     并且先 set_anchors_preset(PRESET_TOP_LEFT) 让 position/size 完全受控（不被父容器布局覆盖）
##   - 上边不动 = 只改 size.y，不改 position.y；下边向上挪是 size 变化的自然结果
##   - 右对齐基准取「原左边框」= SIDEBAR_BASE.x + SIDEBAR_W（动画中途左边框会变窄，
##     但它自己会同时收缩，所以对齐基准必须是动画前的常量，不能用 _sidebar.size.x）
##   - **无停顿的关键**：不要写成「上移 tween（EASE_OUT → 末尾速度归零）」+「弹射 tween（EASE_IN → 从零起步）」
##     两个串行段——接缝处速度归零，视觉上就是「碰一下停一停」。
##     改为**一条 tween_method 跑完全程**，左框位置由下框位置实时推导（y = 下框顶 - 左框高），
##     两框在接触点之后刚性同速，接缝处速度完全连续（构造上不可能出现停顿）。

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
const GAP := 12.0                                ## 下边框升到左框底部时预留的间距

## ── 时间轴 ──
const SIDEBAR_DUR := 0.55                        ## 左框竖向收缩（独立，先结束）
const DIALOG_SHRINK := 0.45                      ## 下框收窄 + 右移到左下角
const RISE_PUSH_DUR := 1.05                      ## ②③ 合体：上移 + 顶出，一条曲线跑完
const MORPH_TOTAL := 0.45 + 1.05                 ## = 1.50s

## ── 位移 ──
## 升到位时下框顶部 y（贴到左框底部下方 GAP）
## 继续上冲的额外距离：保证两框完全离开画面顶部
const PUSH_DIST := 582.0

var _sidebar: PanelContainer = null
var _dialog: PanelContainer = null
var _status: Label = null
var _btn: Button = null
var _reset_btn: Button = null
var _tw_sidebar: Tween = null
var _tw_dialog: Tween = null
var _busy := false
var _pending := 0                                  ## 尚未走完的动画支路数（=0 时解锁按钮）


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


## 下边框刚贴到左框底部时的顶部 y（②③ 的分界高度）
func _dialog_rise_y() -> float:
	return SIDEBAR_BASE.y + SIDEBAR_COMPACT_H + GAP


## ②③ 合体段的总位移：先升到接触位置，再继续冲出 PUSH_DIST
func _rise_push_dist() -> float:
	return (DIALOG_BASE.y - _dialog_rise_y()) + PUSH_DIST


## ②③ 合体段驱动：k=0 起始 → k=1 两框完全出画。
## 左框位置由下框位置**实时推导**（贴上后就刚性跟随），因此接触点处速度天然连续、不会停顿。
func _set_rise_push(k: float) -> void:
	if _dialog == null or _sidebar == null:
		return
	var y: float = DIALOG_BASE.y - _rise_push_dist() * k
	_dialog.position = Vector2(_dialog_compact_x(), y)
	# 下框升到接触位（左框底 + GAP）之前左框不动；之后两者刚性同速上移，间距恒为 GAP
	_sidebar.position = Vector2(SIDEBAR_BASE.x, minf(0.0, y - SIDEBAR_COMPACT_H - GAP))


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
			"两框同时收缩 → 左框先停 → 下框一路上冲，碰到左框不停顿、顶着它一起弹出画面（右边线对齐原左框 x=%.0f）" % _orig_sidebar_right(),
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


## 主演示：两框同时收缩 → 左框先停 → 下框一路上冲顶走左框
func _play_morph() -> void:
	if _busy:
		return
	_busy = true
	_pending = 2
	_kill_tweens()
	_btn.disabled = true
	_status.text = "① 两个框同时收缩中…"

	# ① 左框：只改 size（position 不动 → 上边固定），0.55s 先结束
	_tw_sidebar = create_tween()
	_tw_sidebar.tween_property(_sidebar, "size",
			Vector2(SIDEBAR_COMPACT_W, SIDEBAR_COMPACT_H), SIDEBAR_DUR) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw_sidebar.tween_callback(func() -> void:
		_status.text = "左框已收好并停住；下框继续上冲…"
		_morph_done())

	# ②③ 下框：同帧开始。第一段收窄+右移到左下角；第二段**一条曲线**跑完上移+顶出
	var compact := Vector2(DIALOG_COMPACT_W, DIALOG_H)
	_tw_dialog = create_tween()
	_tw_dialog.set_parallel(true)
	_tw_dialog.tween_property(_dialog, "size", compact, DIALOG_SHRINK) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw_dialog.tween_property(_dialog, "position:x", _dialog_compact_x(), DIALOG_SHRINK) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# 关键：单个 tween_method 覆盖「上升 → 接触 → 顶飞」，中途没有换段 → 速度连续，不会停一下
	_tw_dialog.chain().tween_method(_set_rise_push, 0.0, 1.0, RISE_PUSH_DUR) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw_dialog.chain().tween_callback(func() -> void:
		_status.text = "下框已顶走左框，两框出画…"
		_morph_done())


## 每条支路走完各报一票，全部走完才解锁按钮
func _morph_done() -> void:
	_pending = maxi(_pending - 1, 0)
	if _pending > 0:
		return
	_busy = false
	if _btn != null:
		_btn.disabled = false
	_status.text = "✓ 完成：左框先收到高 %.0f 停住（上边固定），下框对齐 x=%.0f 后一路上冲、顶走左框" % [
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
	_tw_sidebar = null
	_tw_dialog = null


## 逐帧验收钩子：直接停在指定进度（0=原始布局，1=两框都飞出画面）。
## 时间轴与真实 Tween 完全一致：左框 [0,0.55]；下框 [0,0.45] 收 + [0.45,1.50] 上移顶出（同一条缓动曲线）。
func debug_set_morph(p: float) -> void:
	_kill_tweens()
	_busy = false
	_pending = 0
	var t: float = clampf(p, 0.0, 1.0) * MORPH_TOTAL
	var k1: float = clampf(t / SIDEBAR_DUR, 0.0, 1.0)
	var ks: float = clampf(t / DIALOG_SHRINK, 0.0, 1.0)
	var tp: float = clampf((t - DIALOG_SHRINK) / RISE_PUSH_DUR, 0.0, 1.0)
	# SINE + EASE_IN_OUT 的缓动曲线：k = 0.5 - 0.5*cos(pi*t)
	var ke: float = 0.5 - 0.5 * cos(PI * tp)
	if _sidebar != null:
		_sidebar.size = Vector2(
				lerpf(SIDEBAR_W, SIDEBAR_COMPACT_W, k1),
				lerpf(SIDEBAR_H, SIDEBAR_COMPACT_H, k1))
	if _dialog != null:
		_dialog.size = Vector2(lerpf(DIALOG_W, DIALOG_COMPACT_W, ks), DIALOG_H)
		_set_rise_push(ke)
	if _status != null:
		_status.text = "调试进度 %.0f%%" % (clampf(p, 0.0, 1.0) * 100.0)
