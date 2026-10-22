extends Control
class_name ArenaScreen
## 战斗界面：一张 Benchmark 评测任务。
##
## 布局（主人草图 图2，整改后）：
##   左侧竖栏   面板（标题条装饰）＋ 图标列 / 标签列 / **数值列** 三列对齐
##   中上       BAT 风格控制台框（PromptConsole）——梗卡在这里被"敲"出来
##   右上       预计分 / 本关分 / 代码结构（右边缘统一钉在屏幕右边距 − 24）
##   下方       梗卡沿圆弧扇形展开，悬停时该卡放大
##
## 机制（新）：
##   点手牌 → 梗卡离手 → 控制台**流式打出梗名**
##           → 凑成连携时控制台打出 `→ 触发连携【无限续饭】…` + 绶带横幅 + AI娘吐槽
##   点「▶ 运行」 → MemeCombo.evaluate 结算 → 控制台打印分数明细 + AI娘回应。
##
## 纪律：本文件**不含任何计分规则**——只负责收集"打了哪几张梗卡"，
## 把结果交给 MemeCombo.evaluate，再把返回的明细渲染出来。

signal level_cleared(final_score: int)
signal level_failed(final_score: int)
## 玩家在结算弹窗上点了「继续」——由主控决定去奖励界面还是回地图
signal advance_requested

const HAND_SIZE := 8
const CARD_W := 150.0
const CARD_H := 226.0
const PAD := 24.0

# ── 布局刻度（契约 F.2.2）─────────────────────────────
const RAIL_W := 220.0            ## 左侧竖栏宽
const CONSOLE_X := 268.0         ## = PAD + RAIL_W + PAD
const CONSOLE_H := 300.0         ## 控制台框高
const SIDE_W := 320.0            ## 右侧 HUD 宽
const STATUS_W := 700.0          ## 状态栏宽
const BANNER_W := 720.0          ## 连携横幅宽
const BANNER_H := 32.0           ## 连携横幅高

# ── 圆弧扇形参数（手感不变，别回退）─────────────────────
const ARC_RADIUS := 1150.0        # 半径越大弧越平
const ARC_MAX_ANGLE := 0.30       # 最外侧卡的角度（弧度）
const ARC_BOTTOM := 30.0          # 中间那张卡离屏幕底边的距离
const SELECT_LIFT := 36.0     # 选中时抬起
const HOVER_LIFT := 30.0          # 悬停时抬起的距离
const HOVER_SCALE := 1.16         # 悬停时的放大倍率

## 每回合最多打几张（与 RunState.HAND_LIMIT 一致）
const MAX_PARTS := RunState.POKER_PLAY_LIMIT

## 命中结构时控制台的短评（不带角色，纯工具口吻）
const GENERIC_LINES := [
	"顺序对上了。",
	"这段成型了。",
	"结构成立。",
]

var run: RunState = null
var level: LevelData = null

var _console: PromptConsole = null
var _card_layer: Control = null
var _hand_views: Array[CardView] = []
## 已打出的代码卡
var _played: Array[PokerCard] = []
var _busy: bool = false
var _hovered: CardView = null
## 已经播报过的结构加成（同一项不重复弹横幅）
var _fired_combos: Array[String] = []
var _line_idx: int = 0

# 左侧竖栏
var _rail: PanelContainer = null
var _rail_box: VBoxContainer = null
var _brief_label: Label = null
var _turn_label: Label = null
var _score_value: Label = null
var _hud_rows: Dictionary = {}      ## key → HBoxContainer（Icon / Key / Value）

# 右侧 HUD
var _estimate_label: Label = null
var _target_label: Label = null
var _hits_label: Label = null

# 状态栏
var _status_label: Label = null

# 底部
var _run_button: Button = null
var _reroll_button: Button = null
var _back_button: Button = null

# 连携横幅（绶带）
var _banner: Control = null
var _banner_text: Label = null
var _banner_tween: Tween = null

# 覆盖层
var _overlay: PanelContainer = null
var _overlay_title: Label = null
var _overlay_body: Label = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_console = PromptConsole.new()
	_console.name = "PromptConsole"
	_console.segment_clicked.connect(_on_console_segment_clicked)


## setup(run_state, lv)
## 基础玩法**没有 AI 娘**：提示符固定为 "prompt"。
func setup(run_state: RunState, lv: LevelData) -> void:
	run = run_state
	level = lv
	_console.set_prefix(_prefix())


func _ready() -> void:
	_build_ui()
	resized.connect(_layout)
	await get_tree().process_frame
	_layout()
	_start_level()


# ─────────────────────────────────────────────────────────
#  UI 构建
# ─────────────────────────────────────────────────────────
func _build_ui() -> void:
	var bg := TextureRect.new()
	bg.texture = Art.tex("bg-arena")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 压暗层轻一点，让像素场景透出来
	var veil := ColorRect.new()
	veil.color = Color(0.043, 0.055, 0.086, 0.52)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	_build_rail()
	_build_console_area()
	_build_right_hud()
	_build_bottom()
	_build_banner()

	_card_layer = Control.new()
	_card_layer.name = "CardLayer"
	_card_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_layer)

	_build_overlay()


## 左侧竖栏：面板（标题条装饰）＋ 图标列 / 标签列 / 数值列（三列严格对齐）
func _build_rail() -> void:
	_rail = PanelContainer.new()
	_rail.name = "HudLeft"
	_rail.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, UiKit.LINE, 2, UiKit.PANEL_PAD))
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rail)

	_rail_box = VBoxContainer.new()
	_rail_box.name = "RailBox"
	_rail_box.add_theme_constant_override("separation", UiKit.SP_2)
	_rail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.add_child(_rail_box)

	# 标题条：ui-titlebar 装饰 + 标题文字叠在凹槽里
	var head := UiKit.title_bar("L1 · 日常翻译", 0.0, HORIZONTAL_ALIGNMENT_LEFT, UiKit.TEXT)
	head.name = "RailTitle"
	_rail_box.add_child(head)

	_brief_label = UiKit.dim("", UiKit.FS_XS)
	_brief_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief_label.custom_minimum_size = Vector2(0, 0)
	_rail_box.add_child(_brief_label)

	_rail_box.add_child(UiKit.rule())

	# 三行 HUD：图标列 + 标签列 + 数值列（数值列右对齐到内容区右边缘 − 12）
	_hud_row("level", UiKit.TEX_ICON_LEVEL, "关卡", "L1")
	_hud_row("round", UiKit.TEX_ICON_COMPUTE, "出牌", "3")

	_rail_box.add_child(UiKit.rule())

	# 牌型小抄常驻在左栏——玩家不用记，抬头就能看
	var rule_head := UiKit.label("牌型", UiKit.FS_XS, UiKit.TEXT_DIM)
	_rail_box.add_child(rule_head)
	for pair in PokerHand.cheat_sheet():
		var t := int(pair[0])
		var base := PokerHand.type_base(t)
		var rl := UiKit.label("%s  %d×%d" % [str(pair[1]), int(base["chips"]), int(base["mult"])],
				UiKit.FS_XS, UiKit.ACCENT)
		_rail_box.add_child(rl)
	var rule_note := UiKit.dim("红牌 +3 倍率 ｜ 黑牌 +25 筹码", UiKit.FS_XS)
	rule_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rail_box.add_child(rule_note)

	_rail_box.add_child(UiKit.rule())

	_turn_label = UiKit.dim("", UiKit.FS_XS)
	_rail_box.add_child(_turn_label)

	var score_row := UiKit.kv_row("本关得分", "0", UiKit.GOLD, UiKit.FS_XS, UiKit.FS_S)
	score_row.name = "ScoreRow"
	_score_value = score_row.get_node("Value") as Label
	_rail_box.add_child(score_row)


## 一行 HUD：图标 + 标签 + 数值。**全部走 UiKit.icon_row**，不许散着写。
func _hud_row(key: String, icon_name: String, label_text: String, value: String) -> void:
	var row := UiKit.icon_row(icon_name, label_text, value, UiKit.TEXT)
	row.name = "Hud" + key.capitalize()
	_rail_box.add_child(row)
	_hud_rows[key] = row


## 中上方：BAT 控制台框
func _build_console_area() -> void:
	var area := Control.new()
	area.name = "PromptArea"
	area.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(area)
	_console.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.add_child(_console)


## 右上 HUD：预计分 + 本关分 + 代码结构（右边缘统一钉在屏幕右边距 − 24）
func _build_right_hud() -> void:
	var right := VBoxContainer.new()
	right.name = "HudRight"
	right.add_theme_constant_override("separation", UiKit.SP_1)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)

	var head := UiKit.title_bar("结算预估", SIDE_W, HORIZONTAL_ALIGNMENT_RIGHT, UiKit.TEXT_DIM)
	head.name = "RightTitle"
	right.add_child(head)

	_estimate_label = UiKit.label("预计 0", UiKit.FS_S, UiKit.GOLD)
	_estimate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_estimate_label)

	_target_label = UiKit.dim("本关 0 / 0", UiKit.FS_XS)
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_target_label)

	right.add_child(UiKit.rule())

	_hits_label = UiKit.label("", UiKit.FS_XS, UiKit.ACCENT)
	_hits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hits_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hits_label.custom_minimum_size = Vector2(SIDE_W, 0)
	right.add_child(_hits_label)


func _build_bottom() -> void:
	# 状态文字（控制台框下方左侧）
	var tip := VBoxContainer.new()
	tip.name = "BottomTip"
	tip.add_theme_constant_override("separation", UiKit.SP_1)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tip)

	_status_label = UiKit.dim("", UiKit.FS_XS)
	_status_label.custom_minimum_size = Vector2(STATUS_W, 0)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_child(_status_label)

	# 工具条（右下）
	var side := VBoxContainer.new()
	side.name = "BottomSide"
	side.add_theme_constant_override("separation", UiKit.SP_2)
	side.alignment = BoxContainer.ALIGNMENT_END
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(side)

	_run_button = UiKit.accent_button("▶  运行", UiKit.FS_S)
	_run_button.custom_minimum_size = Vector2(0, 48)
	_run_button.pressed.connect(_on_run_pressed)
	side.add_child(_run_button)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiKit.SP_2)
	side.add_child(row)

	_back_button = UiKit.button("⌫  退格", UiKit.FS_XS)
	_back_button.custom_minimum_size = Vector2(0, 32)
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button.pressed.connect(_on_back_pressed)
	row.add_child(_back_button)

	_reroll_button = UiKit.button("↺  重抽手牌", UiKit.FS_XS)
	_reroll_button.custom_minimum_size = Vector2(0, 32)
	_reroll_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reroll_button.pressed.connect(_on_reroll_pressed)
	row.add_child(_reroll_button)


## 结构横幅：ui-ribbon.png 九宫格 + 居中的文案
func _build_banner() -> void:
	_banner = Control.new()
	_banner.name = "ComboBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_banner.modulate = Color(1, 1, 1, 0)
	add_child(_banner)

	var ribbon := UiKit.nine_node(UiKit.TEX_RIBBON, UiKit.M_RIBBON_L, UiKit.M_RIBBON_R, 0, 0)
	ribbon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.add_child(ribbon)

	_banner_text = UiKit.label("", UiKit.FS_XS, UiKit.GOLD)
	_banner_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_text.offset_left = 32
	_banner_text.offset_right = -32
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_banner_text)


func _build_overlay() -> void:
	_overlay = PanelContainer.new()
	_overlay.name = "Overlay"
	_overlay.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL_2, UiKit.GOLD, 2, UiKit.SP_5, UiKit.EL_2))
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiKit.SP_3)
	_overlay.add_child(v)
	_overlay_title = UiKit.title("过关", UiKit.FS_S)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_overlay_title)
	_overlay_body = UiKit.label("", UiKit.FS_XS)
	_overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_overlay_body)
	var btn := UiKit.accent_button("继续", UiKit.FS_S)
	btn.pressed.connect(_on_overlay_continue)
	v.add_child(btn)


# ─────────────────────────────────────────────────────────
#  布局
# ─────────────────────────────────────────────────────────
func _layout() -> void:
	var W := size.x
	var H := size.y

	var rail := get_node_or_null("HudLeft") as Control
	if rail:
		rail.position = Vector2(PAD, PAD)
		rail.size = Vector2(RAIL_W, H - PAD * 2.0)

	var area := get_node_or_null("PromptArea") as Control
	if area:
		area.position = Vector2(CONSOLE_X, PAD)
		area.size = Vector2(W - CONSOLE_X - PAD - SIDE_W - UiKit.SP_4, CONSOLE_H)

	var right := get_node_or_null("HudRight") as Control
	if right:
		right.position = Vector2(W - PAD - SIDE_W, PAD)
		right.size = Vector2(SIDE_W, CONSOLE_H)

	var tip := get_node_or_null("BottomTip") as Control
	if tip:
		tip.position = Vector2(CONSOLE_X, PAD + CONSOLE_H + UiKit.SP_4)
		tip.size = Vector2(STATUS_W, 96)

	var side := get_node_or_null("BottomSide") as Control
	if side:
		side.position = Vector2(W - PAD - SIDE_W, H - 150.0)
		side.size = Vector2(SIDE_W, 120)

	if _banner:
		_banner.position = Vector2((W - BANNER_W) * 0.5, PAD)
		_banner.size = Vector2(BANNER_W, BANNER_H)

	if _overlay:
		_overlay.position = Vector2(W * 0.5 - 280.0, H * 0.5 - 170.0)
		_overlay.size = Vector2(560, 340)

	_layout_hand()


## 圆弧扇形：中间最低，两边抬高并外旋
func _arc_point(i: int, n: int) -> Dictionary:
	var mid := (n - 1) * 0.5
	var a := 0.0
	if n > 1:
		a = (float(i) - mid) / mid * ARC_MAX_ANGLE
	var pivot_x := size.x * 0.5
	var pivot_y := (size.y - ARC_BOTTOM) - ARC_RADIUS
	var px := pivot_x + ARC_RADIUS * sin(a)
	var py := pivot_y + ARC_RADIUS * cos(a)
	return {"pos": Vector2(px, py), "angle": a}


func _layout_hand(animate: bool = true) -> void:
	var n := _hand_views.size()
	for i in n:
		var view := _hand_views[i]
		var arc := _arc_point(i, n)
		var pos: Vector2 = arc["pos"]
		var ang: float = arc["angle"]
		# 卡以"底边中点"为支点贴到弧上，旋转跟随弧线
		view.pivot_offset = Vector2(CARD_W * 0.5, CARD_H)
		var target := pos - Vector2(CARD_W * 0.5, CARD_H)
		if view.selected:
			target.y -= SELECT_LIFT
		elif view == _hovered:
			target.y -= HOVER_LIFT
		var target_rot := 0.0 if view.selected else (ang * (0.55 if view == _hovered else 1.0))
		if animate:
			var tw := view.create_tween()
			tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(view, "position", target, 0.18)
			tw.parallel().tween_property(view, "rotation", target_rot, 0.18)
		else:
			view.position = target
			view.rotation = target_rot


# ─────────────────────────────────────────────────────────
#  关卡流程
# ─────────────────────────────────────────────────────────
func _start_level() -> void:
	run.start_poker_level(level)

	_played.clear()
	_fired_combos.clear()
	_line_idx = 0
	_hovered = null
	_console.clear()
	_console.set_command(_prefix(), [])
	_console.append_line("%s · %s · %s" % [_prefix(), level.id, level.title], PromptConsole.DOS_GRAY)
	_console.append_line("选牌 → 运行。红牌加倍率，黑牌加筹码。", PromptConsole.DOS_GRAY)
	_rebuild_hand_views()
	_refresh_top()
	_status_label.text = "点手牌选牌（最多 5 张）。点控制台里的牌可以撤回。"
	_refresh_preview()


func _rebuild_hand_views() -> void:
	for view in _hand_views:
		view.queue_free()
	_hand_views.clear()
	for c in run.poker_hand:
		_hand_views.append(_make_hand_view(c))
	_layout_hand(false)


## 造一张手牌视图（在手牌里 / 撤回后重新入队都用它）
func _make_hand_view(card: PokerCard) -> CardView:
	var v := CardView.new()
	v.setup(card)
	v.clicked.connect(_on_card_clicked)
	v.mouse_entered.connect(_on_hand_hover.bind(v, true))
	v.mouse_exited.connect(_on_hand_hover.bind(v, false))
	_card_layer.add_child(v)
	return v


func _on_hand_hover(view: CardView, entered: bool) -> void:
	if _busy or _overlay.visible:
		return
	if entered:
		if _hovered == view:
			return
		if _hovered != null:
			_hovered.set_hovered(false)
		_hovered = view
		view.set_hovered(true)
	else:
		if _hovered != view:
			return
		_hovered = null
		view.set_hovered(false)
	_layout_hand(true)


func _refresh_top() -> void:
	var head := _rail_box.get_node_or_null("RailTitle") as Control
	if head != null:
		var ht := head.get_node_or_null("Text") as Label
		if ht != null:
			ht.text = "%s · %s" % [level.id, level.title]
	_brief_label.text = level.brief
	_reroll_button.disabled = run.discards_left <= 0 or _played.is_empty()
	_reroll_button.text = "弃牌（%d）" % run.discards_left if run.discards_left > 0 else "弃牌"
	_back_button.disabled = _played.is_empty()
	_set_hud("level", level.id)
	_set_hud("round", str(run.hands_left))


func _set_hud(key: String, value: String) -> void:
	var row: HBoxContainer = _hud_rows.get(key, null) as HBoxContainer
	if row == null:
		return
	var l := row.get_node_or_null("Value") as Label
	if l != null:
		l.text = value


# ─────────────────────────────────────────────────────────
#  梗卡交互
# ─────────────────────────────────────────────────────────
func _on_card_clicked(view: CardView) -> void:
	if _busy or _overlay.visible:
		return
	var card := view.card
	if card == null:
		return

	# 再点一次 = 取消选中
	if _played.has(card):
		_played.erase(card)
		view.selected = false
		_console.finish_all()
		_console.set_command(_prefix(), _segment_names())
		_layout_hand(true)
		_refresh_preview()
		_check_combos()
		return

	if _played.size() >= MAX_PARTS:
		_status_label.text = "一手最多 %d 张，先取消一张。" % MAX_PARTS
		return

	_played.append(card)
	view.selected = true
	# 控制台流式打出这张牌（花色符号 + 点数）
	_console.type_in(card.display_name())
	_layout_hand(true)
	_refresh_preview()
	_check_combos()


## 点控制台里的某个梗名 → 撤回：卡退回手牌，其后前移
func _on_console_segment_clicked(index: int) -> void:
	if _busy or _overlay.visible:
		return
	if index < 0 or index >= _played.size():
		return
	_console.finish_all()
	var card: PokerCard = _played[index]
	_deselect_view(card)
	_played.remove_at(index)
	_console.set_command(_prefix(), _segment_names())
	_layout_hand(true)
	_refresh_preview()
	_status_label.text = "已取消 %s。" % card.display_name()


## 「⌫ 退格」：取消最后一张
func _on_back_pressed() -> void:
	if _busy or _overlay.visible:
		return
	if _played.is_empty():
		_status_label.text = "还没选任何牌。"
		return
	_console.finish_all()
	var card: PokerCard = _played.pop_back()
	_deselect_view(card)
	_console.set_command(_prefix(), _segment_names())
	_layout_hand(true)
	_refresh_preview()
	_status_label.text = "已去掉最后一张 %s。" % card.display_name()


## 把某张牌对应的视图标记为未选中
func _deselect_view(card: PokerCard) -> void:
	for v in _hand_views:
		if v != null and v.card == card:
			v.selected = false
			return


# ─────────────────────────────────────────────────────────
#  牌型播报
# ─────────────────────────────────────────────────────────

## 选牌变化后：牌型变了就播报一次（横幅 + 控制台）
func _check_combos() -> void:
	if _played.is_empty():
		_fired_combos.clear()
		return
	var t := PokerHand.evaluate_type(_played)
	var key := str(t)
	if _fired_combos.has(key):
		return
	_fired_combos.clear()
	_fired_combos.append(key)
	var res := PokerHand.score(_played_cards_now(), _ctx(true))
	_show_banner("%s ｜ %d 筹码 × %d 倍率" % [
		PokerHand.type_name(t), int(res["chips"]), int(res["mult"])])


## 绶带横幅：弹入 → 停一下 → 淡出
func _show_banner(text: String) -> void:
	if _banner == null:
		return
	_banner_text.text = text
	_banner.visible = true
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate = Color(1, 1, 1, 0)
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(1.6)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_banner_tween.tween_callback(func() -> void: _banner.visible = false)


## 结算后的收尾语气（基础玩法没有角色，用通用短句轮换）
func _next_flavor_line() -> String:
	var s := str(GENERIC_LINES[_line_idx % GENERIC_LINES.size()])
	_line_idx += 1
	return s


# ─────────────────────────────────────────────────────────
#  实时预估
# ─────────────────────────────────────────────────────────
func _played_cards_now() -> Array[PokerCard]:
	return _played.duplicate()


func _segment_names() -> Array[String]:
	var out: Array[String] = []
	for c in _played:
		out.append(c.display_name())
	return out


## 命令行前缀 = 当前 AI 娘（她同时在每张牌的中间）
func _prefix() -> String:
	if run != null and run.ai != null:
		return run.ai.id
	return "player"


func _ctx(preview: bool) -> Dictionary:
	return {
		"ai_id": _prefix(),
		"bonus_chips": run.bonus_chips,
		"bonus_mult": run.bonus_mult,
		"preview": preview,
	}


func _refresh_preview() -> void:
	var res := PokerHand.score(_played_cards_now(), _ctx(true))
	_estimate_label.text = "%d × %d = %d" % [
		int(res["chips"]), int(res["mult"]), int(res["score"])]
	_hits_label.text = PokerHand.type_name(int(res["type"])) if not _played.is_empty() else ""

	_turn_label.text = "手牌 %d 张 ｜ 出牌 %d ｜ 弃牌 %d" % [
		run.poker_hand.size(), run.hands_left, run.discards_left]
	_score_value.text = str(run.score)
	_target_label.text = "本关 %d / %d" % [run.score, level.target_score]

	# 实时把牌型摆在命令行下方：一手牌在出手前就知道值多少
	if _played.is_empty():
		_console.set_syntax(PromptConsole.SYNTAX_HIDDEN, "")
	elif bool(res["score"] > 0):
		_console.set_syntax(PromptConsole.SYNTAX_OK,
				"%s ｜ %d 筹码 × %d 倍率 = %d" % [
					str(res["type_name"]), int(res["chips"]), int(res["mult"]), int(res["score"])])

	if not res["notes"].is_empty():
		_status_label.text = " · ".join(res["notes"])


# ─────────────────────────────────────────────────────────
#  运行与结算
# ─────────────────────────────────────────────────────────
func _on_run_pressed() -> void:
	if _busy or _overlay.visible:
		return
	if _played.is_empty():
		_status_label.text = "先至少选一张牌。"
		return
	if run.hands_left <= 0:
		_status_label.text = "本关出牌次数用完了。"
		return
	_busy = true
	_run_button.disabled = true

	# 打字没完就运行 → 立刻补全
	_console.finish_all()

	var res := PokerHand.score(_played_cards_now(), _ctx(false))
	var gained := int(res["score"])
	run.score += gained

	_print_run_result(res, gained)
	_animate_score(gained)

	run.play_poker_hand(_played)
	_played.clear()
	_fired_combos.clear()
	_console.set_command(_prefix(), [])
	_hovered = null
	_rebuild_hand_views()
	_refresh_top()
	_refresh_preview()

	if run.hands_left <= 0:
		await get_tree().create_timer(0.6).timeout
		_finish_level()
	else:
		_busy = false
		_run_button.disabled = false
		_refresh_preview()


## 控制台打印：牌型 → 筹码×倍率明细 → AI娘被动
func _print_run_result(res: Dictionary, gained: int) -> void:
	_console.append_line("→ %s ｜ %d × %d = %d" % [
		str(res["type_name"]), int(res["chips"]), int(res["mult"]), gained],
		PromptConsole.DOS_AMBER)
	_console.append_line("筹码 = 牌型 %d ＋ 点数 ＋ 黑牌 %d×%d" % [
		int(PokerHand.type_base(int(res["type"]))["chips"]),
		int(res["black_count"]), PokerHand.BLACK_CHIPS], PromptConsole.DOS_AMBER)
	_console.append_line("倍率 = 牌型 %d ＋ 红牌 %d×%d" % [
		int(PokerHand.type_base(int(res["type"]))["mult"]),
		int(res["red_count"]), PokerHand.RED_MULT], PromptConsole.DOS_AMBER)
	for n in res.get("notes", []):
		_console.append_line(str(n), PromptConsole.DOS_CYAN)


func _animate_score(gained: int) -> void:
	UiKit.pop(_score_value, 1.2, 0.3)
	UiKit.flash_text(_score_value, UiKit.WHITE, 0.35)
	UiKit.pop(_estimate_label, 1.15, 0.25)


func _finish_level() -> void:
	var passed := run.score >= level.target_score
	if passed:
		_overlay_title.text = "通过"
		_overlay_body.text = "得分 %d / 目标 %d\n下一步：挑一张卡加进牌库。" % [
			run.score, level.target_score
		]
		_overlay.visible = true
		level_cleared.emit(run.score)
	else:
		_overlay_title.text = "未通过"
		_overlay_body.text = "得分 %d / 目标 %d\n差距 %d 分。\n提示：把语句拼成合法代码——顺序对了才给分。" % [
			run.score, level.target_score, level.target_score - run.score
		]
		_overlay.visible = true
		level_failed.emit(run.score)
	_busy = false


func _on_overlay_continue() -> void:
	_overlay.visible = false
	advance_requested.emit()


func _on_reroll_pressed() -> void:
	if _busy or _overlay.visible:
		return
	if _played.is_empty():
		_status_label.text = "先在手里选出要弃掉的牌。"
		return
	if run.discards_left <= 0:
		_status_label.text = "本关弃牌次数用完了。"
		return
	var n := _played.size()
	if run.discard_poker(_played):
		_console.set_command(_prefix(), [])
		_played.clear()
		_fired_combos.clear()
		_hovered = null
		_rebuild_hand_views()
		_refresh_top()
		_refresh_preview()
		_status_label.text = "弃掉 %d 张，补回来了。" % n


func debug_place_card(index: int) -> bool:
	if _busy or _overlay.visible:
		return false
	if index < 0 or index >= _hand_views.size():
		return false
	var before := _played.size()
	_on_card_clicked(_hand_views[index])
	return _played.size() > before


func debug_played_count() -> int:
	return _played.size()


## 目检用：把手牌里第一张 id 形如 "H3" 的牌打出去（找不到返回 false）
func debug_place_card_id(card_id: String) -> bool:
	for i in _hand_views.size():
		var v := _hand_views[i]
		if v != null and v.card != null and v.card.id() == card_id:
			return debug_place_card(i)
	return false


func debug_command_parts() -> int:
	return _played.size()


func debug_run() -> void:
	_on_run_pressed()


func debug_overlay_visible() -> bool:
	return _overlay.visible


func debug_click_continue() -> void:
	_on_overlay_continue()


func debug_flip_first() -> bool:
	if _hand_views.is_empty():
		return false
	_hand_views[0].toggle_flip()
	return true


func debug_first_is_back() -> bool:
	if _hand_views.is_empty():
		return false
	return _hand_views[0]._showing_back()


## 测试用：模拟悬停第 index 张手牌
func debug_hover(index: int) -> bool:
	if index < 0 or index >= _hand_views.size():
		return false
	_on_hand_hover(_hand_views[index], true)
	return true


## 测试用：控制台当前命令行文本（不含光标）
func debug_console_line() -> String:
	return _console.current_line() if _console != null else ""


## 测试用：控制台是否正在打字
func debug_console_typing() -> bool:
	return _console.is_typing() if _console != null else false


## 测试用：控制台历史日志（含当前命令行）
func debug_console_log() -> String:
	return _console.get_log() if _console != null else ""


## 测试用：状态栏文字
func debug_status_text() -> String:
	return _status_label.text if _status_label != null else ""


## 测试用：当前已打出的代码卡的结算明细（只算不写回）
func debug_hand_eval() -> Dictionary:
	return PokerHand.score(_played_cards_now(), _ctx(false))


## 测试用：连携横幅是否可见 / 横幅文案
func debug_banner() -> Dictionary:
	return {
		"visible": _banner.visible if _banner != null else false,
		"text": _banner_text.text if _banner_text != null else "",
	}


## 测试用：把手牌换成指定的梗卡 id 列表（按顺序），用于造连携局面
func debug_set_hand(ids: Array) -> void:
	run.poker_hand.clear()
	for id in ids:
		var c := _card_from_id(str(id))
		if c != null:
			run.poker_hand.append(c)
	_rebuild_hand_views()
	_layout_hand(false)


## "H3" / "D5" / "S9" / "C2" → PokerCard
func _card_from_id(card_id: String) -> PokerCard:
	if card_id.length() < 2:
		return null
	var s := -1
	match card_id.substr(0, 1).to_upper():
		"H": s = PokerCard.Suit.HEART
		"D": s = PokerCard.Suit.DIAMOND
		"S": s = PokerCard.Suit.SPADE
		"C": s = PokerCard.Suit.CLUB
	if s < 0:
		return null
	var r := int(card_id.substr(1))
	if r < 1:
		return null
	return PokerCard.make(s, r)


## 测试用：按 id 直接打出梗卡（绕过手牌顺序）
func debug_play_card(card_id: String) -> bool:
	var c := _card_from_id(card_id)
	if c == null:
		return false
	_played.append(c)
	run.poker_hand.erase(c)
	# 与真实点击路径保持一致：把对应的手牌视图一起摘掉
	for i in range(_hand_views.size() - 1, -1, -1):
		var v := _hand_views[i]
		if v != null and v.card == c:
			_hand_views.remove_at(i)
			v.queue_free()
			break
	_layout_hand(true)
	_check_combos()
	_refresh_preview()
	return true


## ★ 核心验收项：侧栏三列的**像素坐标**报告。
## 图标列左边缘 / 标签列左边缘 / 数值列右边缘 是否落在同一条竖线上。
func debug_alignment_report() -> Array:
	var out: Array = []
	for key in ["level", "token", "compute", "ai"]:
		var row: HBoxContainer = _hud_rows.get(key, null) as HBoxContainer
		if row == null:
			continue
		var ic := row.get_node_or_null("Icon") as Control
		var kl := row.get_node_or_null("Key") as Control
		var vl := row.get_node_or_null("Value") as Control
		out.append({
			"key": key,
			"icon_left": ic.global_position.x if ic != null else -1.0,
			"label_left": kl.global_position.x if kl != null else -1.0,
			"value_left": vl.global_position.x if vl != null else -1.0,
			"value_right": (vl.global_position.x + vl.size.x) if vl != null else -1.0,
			"row_top": row.global_position.y,
			"row_h": row.size.y,
		})
	return out


## 右侧角标的右边缘（应统一 = 屏幕宽 − 24）
func debug_right_edge_report() -> Dictionary:
	var right := get_node_or_null("HudRight") as Control
	var e: Label = _estimate_label
	var t: Label = _target_label
	return {
		"column_right": (right.global_position.x + right.size.x) if right != null else -1.0,
		"estimate_right": (e.global_position.x + e.size.x) if e != null else -1.0,
		"target_right": (t.global_position.x + t.size.x) if t != null else -1.0,
	}
