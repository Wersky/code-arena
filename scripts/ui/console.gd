class_name PromptConsole
extends Control
## 100% 还原 Windows BAT/DOS 风格的提示词命令行控制台。
##
## 它只负责「显示与打字」，不知道任何计分规则。
## 命令行片段由外部通过 type_in() 逐段喂进来；它按顺序拼成一行。
##
## 打字机核心规则（主人原话，不得改）：
##   "如果快速打字还未结束时选择下一张卡牌，那么快速打字立刻停止并且补全，
##    轮到下一张卡牌快速输入。"
##   → type_in() 入口处若正在打字，先把当前那段**一次性补全**，再打新的一段。
##     绝不允许片段半截留在命令行里。

## 打字速度默认值：字符/秒。契约给的 45 是"快"的上限感，
## 实际按片段长度归一到 TYPE_MIN_TIME~TYPE_MAX_TIME（0.6~1.2 秒），
## 这才是主人要的"快速打字"观感：一段话唰一下就出来了。
const DEFAULT_SPEED := 45.0
## 闪烁光标的周期与亮灭占比
const CURSOR_PERIOD := 1.0
const CURSOR_ON_RATIO := 0.55

## 提示符。**所有行（命令行 + 回显 + 日志）统一用这个前缀**，
## 保证控制台区整列对齐（C:\PROMPT_ARENA 挪到面板标题条上去了）。
const PROMPT := "> "

## DOS 配色（不占用 UiKit 调色板，避免改动全局主题）
const DOS_BLACK := Color(0.0, 0.0, 0.0)
const DOS_GREEN := Color(0.20, 1.0, 0.20)
const DOS_AMBER := Color(1.0, 0.78, 0.24)
const DOS_GRAY := Color(0.55, 0.55, 0.55)
const DOS_CYAN := Color(0.35, 0.85, 1.0)
const DOS_RED := Color(0.95, 0.42, 0.42)

## 玩家点击了命令行中的第 index 个片段（0 起）→ arena 负责把卡退回手牌
signal segment_clicked(index: int)
## 一段片段打字完成（可用于播放音效 / 计数）
signal segment_completed(segment: String)
## 全部待打内容写完
signal typing_finished

## 历史区最多保留的行数（超出丢最旧）
const MAX_HISTORY_LINES := 200
## 一段片段的打字时长区间（秒）
const TYPE_MIN_TIME := 0.6
const TYPE_MAX_TIME := 1.2

## 日志行统一前缀（所有历史行都对齐到这一列）与统一行高
const LOG_PREFIX := "> "
## 字号与行高（2026-10-24 主人要求调大：12/18 → 16/26）
const FONT_SIZE := 16
const LOG_LINE_H := 26

var _prefix := "prompt"
## 已完整显示的片段（顺序 = 玩家点击顺序）
var _segments: Array[String] = []
## 正在打的那一段（完整文本），_typed_len 是已写出的字符数
var _pending := ""
var _typed_len := 0
var _type_accum := 0.0
var _type_speed := 0.0
var _cursor_time := 0.0
var _built := false

# ── 内部节点 ─────────────────────────────────────────
var _frame: PanelContainer = null
var _history_scroll: ScrollContainer = null
var _history_box: VBoxContainer = null
var _cmd_scroll: ScrollContainer = null
var _cmd_row: HBoxContainer = null
var _prompt_label: Label = null
var _prefix_label: Label = null
var _typing_label: Label = null
var _cursor_label: Label = null
var _syntax_label: Label = null

## 语法状态条的三种状态
const SYNTAX_HIDDEN := 0
const SYNTAX_OK := 1
const SYNTAX_ERROR := 2


func _init() -> void:
	custom_minimum_size = Vector2(0, 300)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	_build()


# ─────────────────────────────────────────────────────────
#  构建
# ─────────────────────────────────────────────────────────
func _build() -> void:
	if _built:
		return
	_built = true

	_frame = PanelContainer.new()
	_frame.name = "ConsoleFrame"
	_frame.add_theme_stylebox_override("panel", UiKit.flat(DOS_BLACK, UiKit.LINE, 1, UiKit.SP_2))
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_frame)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiKit.SP_1)
	_frame.add_child(v)

	# 面板标题条：ui-titlebar.png 装饰 + 标题叠在装饰条凹槽里
	var head := UiKit.title_bar("C:\\PROMPT_ARENA · 程序日志", 0.0, HORIZONTAL_ALIGNMENT_LEFT,
			UiKit.TEXT_DIM)
	head.name = "TitleBar"
	v.add_child(head)

	# 历史区（纵向滚动）
	_history_scroll = ScrollContainer.new()
	_history_scroll.name = "HistoryScroll"
	_history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_history_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_history_scroll)

	_history_box = VBoxContainer.new()
	_history_box.name = "HistoryBox"
	_history_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_box.add_theme_constant_override("separation", 0)
	_history_scroll.add_child(_history_box)

	# 命令行区（横向滚动）
	_cmd_scroll = ScrollContainer.new()
	_cmd_scroll.name = "CmdScroll"
	_cmd_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_cmd_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cmd_scroll.custom_minimum_size = Vector2(0, 30)
	v.add_child(_cmd_scroll)

	_cmd_row = HBoxContainer.new()
	_cmd_row.name = "CmdRow"
	_cmd_row.add_theme_constant_override("separation", 0)
	_cmd_scroll.add_child(_cmd_row)

	_prompt_label = _mk_label(PROMPT, DOS_GRAY)
	_prefix_label = _mk_label(_prefix, DOS_AMBER)
	_typing_label = _mk_label("", DOS_GREEN)
	_cursor_label = _mk_label("█", DOS_GREEN)
	_rebuild_cmd_row()

	# 语法状态条：紧贴命令行下方，实时告诉玩家「这段程序合法吗」
	_syntax_label = _mk_label("", DOS_GREEN)
	_syntax_label.name = "SyntaxLabel"
	_syntax_label.custom_minimum_size = Vector2(0, LOG_LINE_H)
	_syntax_label.visible = false
	v.add_child(_syntax_label)

	# 四角像素角饰
	var corners := PixelFrame.new()
	corners.name = "Corners"
	corners.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(corners)


func _mk_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", UiKit.LINE_SPACING)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


# ─────────────────────────────────────────────────────────
#  公开 API（契约 F.1）
# ─────────────────────────────────────────────────────────

## 设置命令行前缀（如 "deepdeek"）。会立即重排当前命令行（不触发打字）。
func set_prefix(prefix: String) -> void:
	_prefix = prefix if prefix != "" else "prompt"
	if _prefix_label != null:
		_prefix_label.text = _prefix


## 敲入一个片段。
## 语义（**打字机核心规则，不得改**）：
##   1. 若当前正在打字 → 立刻把未打完的那一段补全（剩余字符一次性写入），
##      然后才开始打新的一段。
##   2. 若当前命令行已有内容，先补一个空格分隔符。
##   3. 新片段按 speed 字符/秒逐字写入。
## speed <= 0 表示立即完成（同步写完）。
func type_in(segment: String, speed: float = DEFAULT_SPEED) -> void:
	if segment.is_empty():
		return
	# ① 打断补全：正在打字 → 先把当前那段一次性补全
	if _pending != "":
		_commit_pending()
	# ② 新片段开始打字
	_pending = segment
	_typed_len = 0
	_type_accum = 0.0
	_type_speed = _effective_speed(segment.length(), speed)
	_typing_label.add_theme_color_override("font_color", DOS_GREEN)
	_typing_label.text = _typing_text()
	if speed <= 0.0:
		_commit_pending()


## 立即写完所有待打内容（点「运行」时调用）。
func finish_all() -> void:
	if _pending != "":
		_commit_pending()
	typing_finished.emit()


## 返回控制台当前完整文本：历史行 + 当前命令行（不含光标字符）。
func get_log() -> String:
	var lines: Array[String] = []
	if _history_box != null:
		for c in _history_box.get_children():
			if c is Label:
				lines.append((c as Label).text)
	lines.append(current_line())
	return "\n".join(lines)


## 直接把命令行重置为 prefix + segments（用于撤回/重排，不经过打字）。
## segments 为空时只显示前缀。
func set_command(prefix: String, segments: Array[String]) -> void:
	_prefix = prefix if prefix != "" else "prompt"
	_pending = ""
	_typed_len = 0
	_type_accum = 0.0
	_segments.clear()
	for s in segments:
		_segments.append(s)
	if _prefix_label != null:
		_prefix_label.text = _prefix
	if _typing_label != null:
		_typing_label.text = ""
	_rebuild_cmd_row()


## 设置语法状态条（紧贴命令行下方的那一行）。
## state: SYNTAX_HIDDEN / SYNTAX_OK / SYNTAX_ERROR
func set_syntax(state: int, text: String) -> void:
	if _syntax_label == null:
		return
	if state == SYNTAX_HIDDEN or text == "":
		_syntax_label.visible = false
		_syntax_label.text = ""
		return
	_syntax_label.visible = true
	_syntax_label.text = text
	var c := DOS_GREEN
	if state == SYNTAX_ERROR:
		c = DOS_RED
	elif state == SYNTAX_OK:
		c = Color(0.45, 0.95, 0.55)
	_syntax_label.add_theme_color_override("font_color", c)


## 在当前命令行**下方**追加一行输出（AI 娘的回应、分数明细）。
## 所有行统一加 `> ` 前缀 + 统一行高，保证日志区是一列对齐的缩进。
##
## echo = true（默认）：终端行为——先把命令行回显进历史区再输出
##   （用于「运行」后的结算输出，那条命令确实已经交付了）。
## echo = false：**不回显、不动命令行**——用于玩家还在拼程序时的即时播报
##   （结构加成 / 语法提示）。否则刚拼到一半的命令行会被卷进历史区，
##   玩家看不到自己写到哪儿了。
func append_line(text: String, color: Color = DOS_GREEN, echo: bool = true) -> void:
	if _history_box == null:
		return
	# 终端行为：命令行有内容时先回显进历史区，输出跟在它下面
	if echo:
		_echo_command()
	var l := _mk_label(LOG_PREFIX + text, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.custom_minimum_size = Vector2(0, LOG_LINE_H)
	_history_box.add_child(l)
	while _history_box.get_child_count() > MAX_HISTORY_LINES:
		var old := _history_box.get_child(0)
		_history_box.remove_child(old)
		old.queue_free()
	_scroll_history_bottom()


## 清空全部内容（历史行 + 命令行）。
func clear() -> void:
	_pending = ""
	_typed_len = 0
	_type_accum = 0.0
	_segments.clear()
	if _history_box != null:
		for c in _history_box.get_children():
			_history_box.remove_child(c)
			c.queue_free()
	if _typing_label != null:
		_typing_label.text = ""
	if _syntax_label != null:
		_syntax_label.visible = false
		_syntax_label.text = ""
	_rebuild_cmd_row()


## 当前是否正在打字
func is_typing() -> bool:
	return _pending != ""


## 当前命令行片段数组（只读副本）
func get_segments() -> Array[String]:
	var out := _segments.duplicate()
	if _pending != "":
		out.append(_pending)
	return out


## 当前命令行文本（提示符 + 前缀 + 片段 + 正在打的那段，不含光标）
func current_line() -> String:
	var s := PROMPT + _prefix
	for seg in _segments:
		s += " " + seg
	if _pending != "":
		s += " " + _pending.substr(0, _typed_len)
	return s


# ─────────────────────────────────────────────────────────
#  打字机内部
# ─────────────────────────────────────────────────────────

## 按契约的速度算出实际字符/秒：把一段的时长夹到 0.6~1.2 秒。
func _effective_speed(n: int, speed: float) -> float:
	if speed <= 0.0 or n <= 0:
		return speed
	var dur := float(n) / speed
	dur = clampf(dur, TYPE_MIN_TIME, TYPE_MAX_TIME)
	return float(n) / dur


## 正在打的那段的显示文本（前面补一个空格分隔符）
func _typing_text() -> String:
	return " " + _pending.substr(0, _typed_len)


## 把待打的那段一次性补全并落成正式片段
func _commit_pending() -> void:
	if _pending == "":
		return
	var seg := _pending
	_pending = ""
	_typed_len = 0
	_type_accum = 0.0
	_typing_label.text = ""
	_segments.append(seg)
	_rebuild_cmd_row()
	segment_completed.emit(seg)


func _process(delta: float) -> void:
	if _cursor_label == null:
		return
	_cursor_time += delta
	_cursor_label.visible = fmod(_cursor_time, CURSOR_PERIOD) < CURSOR_PERIOD * CURSOR_ON_RATIO
	if _pending == "":
		return
	_type_accum += delta * _type_speed
	var total := int(floor(_type_accum))
	if total >= _pending.length():
		_commit_pending()
		typing_finished.emit()
	else:
		_typed_len = total
		_typing_label.text = _typing_text()


# ─────────────────────────────────────────────────────────
#  命令行渲染
# ─────────────────────────────────────────────────────────

func _rebuild_cmd_row() -> void:
	if _cmd_row == null:
		return
	var persist: Array = [_prompt_label, _prefix_label, _typing_label, _cursor_label]
	for c in _cmd_row.get_children():
		_cmd_row.remove_child(c)
		if not persist.has(c):
			c.queue_free()
	_cmd_row.add_child(_prompt_label)
	_cmd_row.add_child(_prefix_label)
	for i in _segments.size():
		_cmd_row.add_child(_make_segment_label(i, _segments[i]))
	_cmd_row.add_child(_typing_label)
	_cmd_row.add_child(_cursor_label)


func _make_segment_label(index: int, text: String) -> Label:
	# 每段前面都补一个空格分隔符（前面一定是命令行前缀）
	var l := _mk_label(" " + text, DOS_GREEN)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.gui_input.connect(_on_segment_gui_input.bind(index))
	l.mouse_entered.connect(_on_segment_hover.bind(l, true))
	l.mouse_exited.connect(_on_segment_hover.bind(l, false))
	return l


func _on_segment_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			segment_clicked.emit(index)
			accept_event()


func _on_segment_hover(l: Label, entered: bool) -> void:
	if l == null:
		return
	if entered:
		l.add_theme_color_override("font_color", Color.WHITE)
	else:
		l.add_theme_color_override("font_color", DOS_GREEN)


## 命令行有内容 → 先把整条命令回显进历史区（终端行为），并清空实时命令行
func _echo_command() -> void:
	if _segments.is_empty() and _pending == "":
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, LOG_LINE_H)
	row.add_child(_mk_label(PROMPT, DOS_GRAY))
	row.add_child(_mk_label(_prefix, DOS_AMBER))
	for i in _segments.size():
		row.add_child(_mk_label(" " + _segments[i], DOS_GREEN))
	if _pending != "":
		row.add_child(_mk_label(" " + _pending.substr(0, _typed_len), DOS_GREEN))
	_history_box.add_child(row)
	_segments.clear()
	_pending = ""
	_typed_len = 0
	_type_accum = 0.0
	_typing_label.text = ""
	_rebuild_cmd_row()


func _scroll_history_bottom() -> void:
	if _history_scroll == null or not is_inside_tree():
		return
	_history_scroll.set_deferred("scroll_vertical", 1000000)
	# 布局完成后再压一次底（刚加进去的行此时才有高度）
	call_deferred("_apply_scroll_bottom")


func _apply_scroll_bottom() -> void:
	if _history_scroll != null and is_instance_valid(_history_scroll):
		_history_scroll.scroll_vertical = 1000000
