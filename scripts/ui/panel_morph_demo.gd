class_name PanelMorphDemo
extends Control
## 面板动态伸缩演示（2026-11-09 主人要求）：
## 模仿主界面布局（左侧竖框 + 下方横框），点击按钮触发联动收缩动画：
##   ① 左边框向上收缩：**上边固定不动**，下边向上挪（高度变小）
##   ② 下边框向左收缩：整体缩到左下角，然后向上移动，与左边框的侧边对齐
## 全部用 Tween 驱动 Control.size / position，可重复播放、可中途打断重播。
##
## 关键实现要点（Godot Control 动画坑）：
##   - PanelContainer 会自动被内容撑回最小尺寸 → 收缩前必须把 custom_minimum_size 一起改，
##     并且先 set_anchors_preset(PRESET_TOP_LEFT) 让 position/size 完全受控（不被父容器布局覆盖）
##   - 上边不动 = 只改 size.y，不改 position.y；下边向上挪是 size 变化的自然结果

signal back_requested

const SIDEBAR_BASE := Vector2(24.0, 0.0)
const SIDEBAR_W := 232.0
const SIDEBAR_H := 900.0
const DIALOG_BASE := Vector2(280.0, 670.0)
const DIALOG_W := 880.0
const DIALOG_H := 230.0

var _sidebar: PanelContainer = null
var _dialog: PanelContainer = null
var _status: Label = null
var _btn: Button = null
var _reset_btn: Button = null
var _tw_sidebar: Tween = null
var _tw_dialog: Tween = null
var _busy := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.016, 0.032)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := UiKit.label("面板动态伸缩演示", 30, Color(0.92, 0.95, 1.0))
	title.position = Vector2(300, 40)
	add_child(title)
	var sub := UiKit.dim("左边框向上收缩（上边不动）｜下边框向左收缩到左下角、再上移与左边框对齐", 15,
			Color(0.55, 0.72, 0.9))
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


## 主演示：两段联动收缩
func _play_morph() -> void:
	if _busy:
		return
	_busy = true
	_kill_tweens()
	_btn.disabled = true
	_status.text = "① 左边框向上收缩（上边不动，下边向上挪）…"

	# ① 左边框：上边 y 固定，高度收缩 → 下边上移。同时宽度略收，做出「侧栏收拢」感
	var sb_target_h := 300.0
	_tw_sidebar = create_tween().set_parallel(true)
	_tw_sidebar.tween_property(_sidebar, "size",
			Vector2(SIDEBAR_W * 0.72, sb_target_h), 0.55) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# position 保持不变 → 上边不动
	_tw_sidebar.chain().tween_callback(func() -> void:
		_status.text = "② 下边框向左收缩到左下角，再上移与左边框侧边对齐…"
		_play_dialog_morph())


## ② 下边框：向左收缩到左下角 → 再上移与左边框右边线对齐
func _play_dialog_morph() -> void:
	if _dialog == null:
		return
	var sb_right: float = _sidebar.position.x + _sidebar.size.x
	var compact := Vector2(320.0, DIALOG_H)
	_tw_dialog = create_tween()
	# 第一步：向左收缩（宽度变窄、左边贴到 sidebar 左边线同一 x）
	_tw_dialog.set_parallel(true)
	_tw_dialog.tween_property(_dialog, "size", compact, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw_dialog.tween_property(_dialog, "position",
			Vector2(_sidebar.position.x, _dialog.position.y), 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# 第二步：整体上移，贴到左边框底部下方（与左边框侧边对齐）
	_tw_dialog.chain().tween_property(_dialog, "position",
			Vector2(_sidebar.position.x, _sidebar.position.y + _sidebar.size.y + 12.0), 0.50) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw_dialog.chain().tween_callback(func() -> void:
		_busy = false
		_btn.disabled = false
		_status.text = "✓ 完成：左边框向上收（上边固定），下边框收到左下并上移，右边线对齐 x=%.0f" % sb_right)


func _reset_layout() -> void:
	_kill_tweens()
	_busy = false
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


## 逐帧验收钩子：直接停在指定进度（0=原始布局，1=收缩完成）
func debug_set_morph(p: float) -> void:
	_kill_tweens()
	_busy = false
	var k := clampf(p, 0.0, 1.0)
	# 阶段划分：0~0.5 左边框收，0.5~1 下边框收+上移
	var k1 := clampf(k / 0.5, 0.0, 1.0)
	var k2 := clampf((k - 0.5) / 0.5, 0.0, 1.0)
	if _sidebar != null:
		_sidebar.position = SIDEBAR_BASE
		_sidebar.size = Vector2(
				lerpf(SIDEBAR_W, SIDEBAR_W * 0.72, k1),
				lerpf(SIDEBAR_H, 300.0, k1))
	if _dialog != null:
		var sb_x: float = _sidebar.position.x
		var narrow := Vector2(lerpf(DIALOG_W, 320.0, minf(k2 * 1.6, 1.0)),
				DIALOG_H)
		var x := lerpf(DIALOG_BASE.x, sb_x, minf(k2 * 1.6, 1.0))
		var ty := lerpf(DIALOG_BASE.y,
				_sidebar.position.y + _sidebar.size.y + 12.0,
				clampf((k2 - 0.4) / 0.6, 0.0, 1.0))
		_dialog.size = narrow
		_dialog.position = Vector2(x, ty)
	if _status != null:
		_status.text = "调试进度 %.0f%%" % (k * 100.0)
