class_name UiTuner
extends CanvasLayer
## 通用 UI / 文本位置调参器（实测用，Dev2 工具，不进玩法逻辑）。
##
## 用途：进游戏实测时直接拖 UI、改字号，改完存盘；存盘文件就是"参数真值"，
## 下一棒（人或 AI）读 docs/ui-tune.json 即可照抄进代码。
##
## 键位：
##   F1        显示 / 隐藏调参面板（**面板显示时才拦截输入**，隐藏时游戏正常玩）
##   鼠标左键   点选鼠标下的 Control；按住拖动 = 移动（改 global_position）
##   方向键     微调 1px（Shift = 10px）
##   滚轮       字号 ±1（Label）/ 尺寸 ±2（其他 Control）
##   Shift+滚轮 缩放 ±0.02（Control.scale）
##   F5        保存到 res://docs/ui-tune.json
##   F9        删除"当前选中节点"的记录（下次启动不再套用）
##
## 已知限制（写清楚，别踩）：
##   · 容器（VBox/HBox/Margin/CenterContainer）的子节点位置每帧被布局重算，
##     拖了会弹回去 → 这类节点请调字号 / 缩放，或把位移记下来交给代码改布局。
##   · 记录按**节点路径**匹配；界面重刷（换屏）后路径变了的记录不会自动套用。

const SAVE_PATH := "res://docs/ui-tune.json"

var _panel: PanelContainer = null
var _info: Label = null
var _title: Label = null
var _sel: Control = null
var _dragging := false
var _drag_off := Vector2.ZERO
var _records: Dictionary = {}          ## path -> {"pos":[x,y], "size":[w,h], "font":int, "scale":float}
var _applied_to: Dictionary = {}       ## path -> instance_id（已套用过的实例，避免每帧覆盖手动改动）
var _scan_t := 0.0


func _ready() -> void:
	layer = 128                        ## 盖在所有界面之上
	_load_records()
	_build_panel()
	visible = false
	set_process_input(true)
	set_process(true)


## 程序化打开面板（调参器启动时是否可见由 main.gd 决定，如 `--tune` 参数）
func open() -> void:
	visible = true
	_refresh_info()


# ── 面板 ─────────────────────────────────────────────
func _build_panel() -> void:
	var root := Control.new()
	root.name = "TunerRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 12)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.92)
	sb.border_color = Color("#37D8F0")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_panel.add_child(col)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", Color("#37D8F0"))
	col.add_child(_title)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 12)
	_info.add_theme_color_override("font_color", Color("#dbe3ec"))
	col.add_child(_info)

	var tips := Label.new()
	tips.add_theme_font_size_override("font_size", 11)
	tips.add_theme_color_override("font_color", Color("#7d8fa4"))
	tips.text = "左键选中并拖动 · 方向键微调(Shift×10) · 滚轮字号±1/尺寸±2\n" \
			+ "Shift+滚轮 缩放±0.02 · F5 保存 · F9 删除选中记录 · F1 退出"
	col.add_child(tips)


# ── 输入 ─────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_F1:
			visible = not visible
			if not visible:
				_sel = null
				_dragging = false
			get_viewport().set_input_as_handled()
			return
		if not visible:
			return
		match k:
			KEY_F5:
				_save_records()
				get_viewport().set_input_as_handled()
			KEY_F9:
				if _sel != null:
					_records.erase(_path_of(_sel))
					_applied_to.erase(_path_of(_sel))
					_save_records()
				get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
				_nudge(k, 10.0 if event.shift_pressed else 1.0)
				get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pick()
				_dragging = _sel != null
				if _dragging:
					_drag_off = get_viewport().get_mouse_position() - _sel.global_position
			else:
				if _dragging:
					_save_records()
				_dragging = false
			get_viewport().set_input_as_handled()
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var dir := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			if mb.shift_pressed:
				_scale_step(dir * 0.02)
			else:
				_font_or_size_step(dir)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging and _sel != null \
			and is_instance_valid(_sel):
		_sel.global_position = get_viewport().get_mouse_position() - _drag_off
		_touch_record(_sel)          ## 只更新内存，松手时统一存盘
		get_viewport().set_input_as_handled()


func _pick() -> void:
	# 鼠标下的 Control；点到调参面板自己就忽略
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null or _is_own(hovered):
		_sel = null
		return
	_sel = hovered
	_refresh_info()


func _is_own(n: Node) -> bool:
	while n != null:
		if n.name == "TunerRoot" or n == self:
			return true
		n = n.get_parent()
	return false


# ── 调整 ─────────────────────────────────────────────
func _nudge(k: int, step: float) -> void:
	if _sel == null or not is_instance_valid(_sel):
		return
	match k:
		KEY_LEFT: _sel.position.x -= step
		KEY_RIGHT: _sel.position.x += step
		KEY_UP: _sel.position.y -= step
		KEY_DOWN: _sel.position.y += step
	_touch_record(_sel)
	_refresh_info()


func _font_or_size_step(dir: float) -> void:
	if _sel == null or not is_instance_valid(_sel):
		return
	if _sel is Label:
		var lbl := _sel as Label
		var cur := lbl.get_theme_font_size("font_size")
		lbl.add_theme_font_size_override("font_size", maxi(6, cur + int(dir)))
	elif _sel is Control:
		var c := _sel as Control
		c.size += Vector2(dir * 2.0, dir * 2.0)
	_touch_record(_sel)
	_refresh_info()


func _scale_step(d: float) -> void:
	if _sel == null or not is_instance_valid(_sel):
		return
	var c := _sel as Control
	if c == null:
		return
	c.scale = Vector2(maxf(0.05, c.scale.x + d), maxf(0.05, c.scale.y + d))
	_touch_record(_sel)
	_refresh_info()


func _touch_record(c: Control) -> void:
	if not c.is_inside_tree():
		return                      ## 还没进树（路径拿不到）→ 不记录，避免脏键
	var p := _path_of(c)
	if p.is_empty():
		return
	var rec := {
		"pos": [snappedf(c.position.x, 0.1), snappedf(c.position.y, 0.1)],
		"scale": snappedf(c.scale.x, 0.001),
	}
	if c is Label:
		rec["font"] = c.get_theme_font_size("font_size")
	else:
		rec["size"] = [snappedf(c.size.x, 0.1), snappedf(c.size.y, 0.1)]
	_records[p] = rec
	_applied_to[p] = c.get_instance_id()


# ── 套用 ─────────────────────────────────────────────
func _process(delta: float) -> void:
	_scan_t += delta
	if _scan_t < 0.4:
		return
	_scan_t = 0.0
	for p: String in _records.keys():
		var rec: Dictionary = _records[p]
		var node := get_node_or_null(p)
		if node == null or not (node is Control):
			continue
		var c := node as Control
		if _applied_to.get(p, 0) == c.get_instance_id():
			continue
		_apply(c, rec)
		_applied_to[p] = c.get_instance_id()
	_refresh_info()


func _apply(c: Control, rec: Dictionary) -> void:
	var pos: Array = rec.get("pos", [])
	if pos.size() == 2:
		c.position = Vector2(float(pos[0]), float(pos[1]))
	if rec.has("scale"):
		var s := float(rec["scale"])
		c.scale = Vector2(s, s)
	if c is Label and rec.has("font"):
		(c as Label).add_theme_font_size_override("font_size", int(rec["font"]))
	elif rec.has("size"):
		var sz: Array = rec["size"]
		if sz.size() == 2:
			c.size = Vector2(float(sz[0]), float(sz[1]))


func _refresh_info() -> void:
	if _info == null:
		return
	_title.text = "UI 调参器 · F1 关闭 · 记录 %d 条" % _records.size()
	if _sel == null or not is_instance_valid(_sel):
		_info.text = "未选中（左键点一个 UI）"
		return
	var c := _sel
	var s := "%s\npos %s  缩放 %.2f" % [_path_of(c).get_file(), str(c.position), c.scale.x]
	if c is Label:
		s += "   字号 %d" % c.get_theme_font_size("font_size")
	else:
		s += "   size %s" % str(c.size)
	_info.text = s


func _path_of(n: Node) -> String:
	return String(n.get_path())


# ── 存取 ─────────────────────────────────────────────
func _load_records() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		_records = parsed
		print("[UiTuner] 已载入 %d 条记录：%s" % [_records.size(), SAVE_PATH])


func _save_records() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_PATH.get_base_dir())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[UiTuner] 存盘失败（只读目录？）：%s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(_records, "  "))
	f.close()
	print("[UiTuner] 已保存 %d 条 → %s" % [_records.size(), SAVE_PATH])
