class_name AiSelectScreen
extends Control
## 「选择你的ai」界面：4 个竖排方框，对应主人草图 1。
##
## 布局契约（docs/01-新机制设计.md F.3）：
##   · 4 个 150×226 方框横向并排，间距 24，整排水平居中
##   · 标题「选择你的ai」48px，位于整排上方 40px
##   · 只有已解锁的 AI 显示完整形象，其余 3 位用 ai-locked.png 剪影（阴影涂黑只留轮廓）
##   · 锁定的方框不可选：点击只给提示文案，不发信号
##   · 方框下方显示名（tint 着色）+ 家族 + 一句 intro_line + 小字注记

## 玩家选定了一位 AI 娘
signal ai_chosen(ai: AiData)
## 玩家按 ESC / 返回键取消（返回主菜单）
signal cancelled

# ── 布局常量（契约 F.3）───────────────────────────────
const BOX_W := 150.0
const BOX_H := 226.0
const BOX_GAP := 24.0        ## = UiKit.SP_5
const TITLE_GAP := 40.0      ## 标题与整排之间的空隙
const ROW_LIFT := 40.0       ## 整排相对垂直中心的让位
## ChibiRig 显示尺寸：画布 192×256 × 0.5（= 原始 48×64 美术的 ×2 整数放大）
const _RIG_VIS_W := 96.0
const _RIG_VIS_H := 128.0

var _ais: Array[AiData] = []
var _frames: Array[PanelContainer] = []
var _styles: Array[StyleBoxFlat] = []
var _rigs := {}              ## index -> ChibiRig（有切件骨架的角色用活立绘，其余静态图）
var _row: HBoxContainer = null
var _title: Label = null
var _hint: Label = null
var _back: Button = null
var _built := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build()
	resized.connect(_layout)
	await get_tree().process_frame
	_layout()


# ─────────────────────────────────────────────────────────
#  对外 API
# ─────────────────────────────────────────────────────────
## 注入 4 位 AI 娘（locked 标记与 unlock_hint 已由 AiPool.ai_list_for_select 设好）
func setup(ais: Array[AiData]) -> void:
	_ais = ais
	_clear_ui()
	_build()
	if is_inside_tree():
		_layout()


## 供测试用：按下第 i 个方框（0 起）
func select_by_index(i: int) -> void:
	if i < 0 or i >= _ais.size():
		return
	var ai := _ais[i]
	if ai == null:
		return
	if ai.locked:
		_set_hint("%s 尚未解锁 · %s" % [ai.display_name, ai.unlock_hint])
		return
	if i < _frames.size() and is_instance_valid(_frames[i]) and _frames[i].is_inside_tree():
		UiKit.pop(_frames[i])
	ai_chosen.emit(ai)


## 当前界面上给出的 AI 娘（测试/调试用）
func current_ais() -> Array[AiData]:
	return _ais


# ─────────────────────────────────────────────────────────
#  UI 构建
# ─────────────────────────────────────────────────────────
func _clear_ui() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_frames.clear()
	_styles.clear()
	_row = null
	_title = null
	_hint = null
	_back = null
	_built = false


func _build() -> void:
	if _built:
		return
	_built = true

	var bg := TextureRect.new()
	bg.texture = Art.tex("bg-map")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var veil := ColorRect.new()
	veil.color = Color(0.043, 0.055, 0.086, 0.74)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	_title = UiKit.label("选择你的ai", UiKit.FS_M, UiKit.TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_row = HBoxContainer.new()
	_row.name = "AiRow"
	_row.add_theme_constant_override("separation", int(BOX_GAP))
	add_child(_row)
	for i in _ais.size():
		_row.add_child(_build_box(i))

	_hint = UiKit.dim("ESC 返回主菜单 · 点击已解锁的形象开始", UiKit.FS_XS, UiKit.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	_back = UiKit.button("← 返回主菜单", UiKit.FS_XS)
	_back.custom_minimum_size = Vector2(160, 32)
	_back.pressed.connect(func() -> void: cancelled.emit())
	add_child(_back)


## 造一个方框（框内：intro / 形象 / 家族；框下：显示名 / 小字注记）
##
## **严格等宽等高**：框体是一个 custom_minimum_size = (BOX_W, BOX_H) 的普通 Control，
## 里面所有子节点都是"手动定位"的——子节点的最小尺寸**不会**把框撑大，
## 所以 4 个框的顶边与底边必然严格对齐。
func _build_box(index: int) -> Control:
	var ai := _ais[index]

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiKit.SP_1)
	col.custom_minimum_size = Vector2(BOX_W, 0)

	# 方框本体
	var style := UiKit.flat(UiKit.PANEL_2, UiKit.LINE, 2, 0)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", style)
	frame.custom_minimum_size = Vector2(BOX_W, BOX_H)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.gui_input.connect(_on_box_input.bind(index))
	frame.mouse_entered.connect(_on_box_hover.bind(index))
	frame.mouse_exited.connect(_on_box_unhover.bind(index))
	col.add_child(frame)
	_frames.append(frame)
	_styles.append(style)

	# 框内内容：普通 Control + 手动定位（不参与最小尺寸计算）
	var content := Control.new()
	content.name = "Content"
	content.custom_minimum_size = Vector2(BOX_W, BOX_H)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(content)

	# 一句 intro（形象上方一行小字）
	var intro := UiKit.dim(ai.intro_line, UiKit.FS_XS, UiKit.TEXT_DIM)
	intro.position = Vector2(10, 4)
	intro.size = Vector2(BOX_W - 20, 36)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intro.clip_text = true
	intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(intro)

	# 形象位（未解锁 = 剪影）
	var holder := Control.new()
	holder.name = "Portrait"
	holder.position = Vector2(12, 44)
	holder.size = Vector2(BOX_W - 24, 142)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(holder)
	_fill_portrait(holder, ai, index)

	# 家族 + 被动（被动是选人的唯一依据，必须看得见）
	var passive := PokerHand.ai_passive_text(ai.id)
	var family := UiKit.dim(ai.family if passive == "" else passive,
			UiKit.FS_XS, UiKit.GOLD if passive != "" else UiKit.TEXT_DIM)
	family.position = Vector2(10, 190)
	family.size = Vector2(BOX_W - 20, 24)
	family.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	family.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	family.clip_text = true
	family.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(family)

	# 显示名：锁定态用暗色（名字与家族保留，只是不刺眼）
	var name_color := UiKit.TEXT_DIM if ai.locked else ai.tint_color
	var name_label := UiKit.label(ai.display_name, UiKit.FS_S, name_color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(BOX_W, 32)
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)

	# 小字：锁定态写解锁条件，已解锁写原型注记
	var note_text := ai.unlock_hint if ai.locked else ai.prototype_note
	var note := UiKit.dim(note_text, UiKit.FS_XS, UiKit.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.custom_minimum_size = Vector2(BOX_W, 24)
	note.clip_text = true
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(note)

	# ui-ai-frame.png 九宫格边框（patch margin 5），盖在方框最上层
	var deco := UiKit.nine_node(UiKit.TEX_AI_FRAME, UiKit.M_AI_FRAME, UiKit.M_AI_FRAME,
			UiKit.M_AI_FRAME, UiKit.M_AI_FRAME)
	deco.name = "AiFrame"
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(deco)

	return col


## 形象位填充：已解锁 = 自己的形象（缺图降级占位框）；未解锁 = ai-locked.png 剪影
## 有切件骨架（assets/art/rig/<id>/rig.json + parts/）的角色用 ChibiRig 播活立绘
## （idle 呼吸，悬停 shake），没有的退回静态立绘——按角色天然降级，绝不报错。
func _fill_portrait(holder: Control, ai: AiData, index: int = -1) -> void:
	var rig_dir := "res://assets/art/rig/%s" % ai.id
	if not ai.locked and index >= 0 \
			and FileAccess.file_exists(rig_dir.path_join("rig.json")):
		var rig := ChibiRig.new()
		rig.name = "ChibiRig"
		rig.setup(rig_dir)
		# rig 画布 192×256，按 0.5 显示 = 原始 48×64 美术的 ×2 整数放大（资产规矩）。
		# 96×128 在 126×142 的形象位里居中。
		rig.scale = Vector2(0.5, 0.5)
		rig.position = Vector2((holder.size.x - _RIG_VIS_W) * 0.5,
				(holder.size.y - _RIG_VIS_H) * 0.5)
		holder.add_child(rig)
		_rigs[index] = rig
		return

	var path := ""
	if ai.locked:
		path = AiPool.locked_silhouette()
	elif ai.portrait_path != "" and ResourceLoader.exists(ai.portrait_path):
		path = ai.portrait_path

	var tex: Texture2D = null
	if path != "":
		tex = load(path) as Texture2D

	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ai.locked:
			# 剪影压暗一档：只剩亮轮廓与金锁
			tr.modulate = Color(0.95, 0.95, 1.0)
		holder.add_child(tr)

		if ai.locked:
			# 阴影涂黑：盖一层暗色，只留剪影轮廓透出来
			var shade := ColorRect.new()
			shade.color = Color(0.043, 0.055, 0.086, 0.30)
			shade.set_anchors_preset(Control.PRESET_FULL_RECT)
			shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(shade)
		return

	# 降级：没有可用贴图时的占位框（绝不报错）
	var ph := ColorRect.new()
	ph.color = UiKit.PANEL_3 if not ai.locked else Color(0.02, 0.02, 0.03)
	ph.set_anchors_preset(Control.PRESET_FULL_RECT)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ph)

	var q := UiKit.dim("形象待补" if not ai.locked else "？？？", UiKit.FS_XS, UiKit.TEXT_DIM)
	q.set_anchors_preset(Control.PRESET_FULL_RECT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(q)


# ─────────────────────────────────────────────────────────
#  布局
# ─────────────────────────────────────────────────────────
func _layout() -> void:
	if not _built:
		return
	var vp := size
	if vp.x < 64 or vp.y < 64:
		vp = get_viewport_rect().size

	var count := _ais.size()
	var row_w := count * BOX_W + maxf(0.0, float(count - 1)) * BOX_GAP
	var row_x := (vp.x - row_w) * 0.5
	var row_y := vp.y * 0.5 - BOX_H * 0.5 - ROW_LIFT

	if _row != null:
		_row.position = Vector2(row_x, row_y)

	if _title != null:
		_title.position = Vector2(0, row_y - TITLE_GAP - float(UiKit.FS_M))
		_title.size = Vector2(vp.x, float(UiKit.FS_M))

	# 方框下方：显示名 + 小字 ≈ 64px，再留 16px 放提示行
	var below := row_y + BOX_H + 80
	if _hint != null:
		_hint.position = Vector2(0, below)
		_hint.size = Vector2(vp.x, 24)
	if _back != null:
		_back.position = Vector2((vp.x - _back.custom_minimum_size.x) * 0.5, below + 32)


# ─────────────────────────────────────────────────────────
#  交互
# ─────────────────────────────────────────────────────────
func _on_box_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			select_by_index(index)


func _on_box_hover(index: int) -> void:
	if index < 0 or index >= _frames.size():
		return
	var ai := _ais[index]
	var frame := _frames[index]
	if not is_instance_valid(frame):
		return
	if ai != null and ai.locked:
		_set_hint("%s 尚未解锁 · %s" % [ai.display_name, ai.unlock_hint])
		return
	var tint: Color = ai.tint_color if ai != null else UiKit.ACCENT
	_set_border(index, tint)
	_tween_scale(frame, 1.04)
	# 有活立绘的角色：悬停时摇一次头（一次性动作，播完自动回 idle）
	var rig: ChibiRig = _rigs.get(index)
	if rig != null and is_instance_valid(rig):
		rig.play("shake")


func _on_box_unhover(index: int) -> void:
	if index < 0 or index >= _frames.size():
		return
	var frame := _frames[index]
	if not is_instance_valid(frame):
		return
	_set_border(index, UiKit.LINE)
	_tween_scale(frame, 1.0)


func _set_border(index: int, color: Color) -> void:
	if index < 0 or index >= _styles.size():
		return
	var st := _styles[index]
	if st != null:
		st.border_color = color


func _tween_scale(node: Control, to: float) -> void:
	if node == null or not node.is_inside_tree():
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector2.ONE * to, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_hint(text: String) -> void:
	if _hint != null:
		_hint.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
