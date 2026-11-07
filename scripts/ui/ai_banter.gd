class_name AIBanter
extends Control
## AI 娘「小鲸」战斗气泡组件（4 钩子 + 本地兜底，全程不阻塞演出）。
##
## 钩子与频次（圆桌纪要第 2 轮定稿）：
##   · 开场问候 battle_started()                 1 次/场
##   · 连段喝彩 on_streak(streak, turn)          ≥3 阶；2 次/场；两次间隔 ≥2 回合
##   · 濒危关心 on_hp_changed(hp, max_hp)        HP 首次 <30%；1 次/场
##   · 回怼敌人 notify_enemy_line(enemy_text)    敌 MARK/TAUNT 后调用，延迟 0.5s；2 次/场；最高优先级
##
## 纪律：
##   · 只播 UI 气泡，不锁输入、不暂停结算、不 await 网络；台词永不进数值管线。
##   · 同帧多钩只播 1 条，其余进队列顺延；回怼优先级最高。
##   · 接入 LLM 时用 set_provider()：provider 必须立刻返回、异步回调 reply(text)；
##     超过 llm_timeout（默认 3s）未回 → 已播本地兜底，迟到回调直接丢弃。
##   · 不依赖 arena；接线由战斗界面任务负责（见文件末尾「接线示例」）。
##
## 接线示例（另一个任务在 arena 里做，本文件不引用 arena）：
##   var banter := AIBanter.new()
##   banter.name = "AIBanter"
##   add_child(banter)
##   banter.setup(_companion, LLMClient.make_dialog_provider())   # provider 可省略
##   banter.battle_started()
##   banter.on_streak(streak, turn)
##   banter.on_hp_changed(hp, RunState.MAX_HP)
##   banter.notify_enemy_line("MARK\n检测到非法连击")   # 仅敌 MARK/TAUNT 时调用

## 一条台词真正播出（hook: opening/cheer/danger/retort；text 已清洗）
signal line_spoken(hook: String, text: String)
## 气泡显示（供接线层做声音/表情联动，纯通知，不影响流程）
signal bubble_shown(text: String)

const H_OPENING := "opening"
const H_CHEER := "cheer"
const H_DANGER := "danger"
const H_RETORT := "retort"

## 队列优先级：回怼最高；濒危其次；开场要在同帧喝彩之前先亮相；喝彩最低
const PRIORITY := {
	H_RETORT: 4,
	H_DANGER: 3,
	H_OPENING: 2,
	H_CHEER: 1,
}

## 台词上限（prompt 要求 ≤50 字，超出截断，避免气泡撑爆）
const MAX_CHARS := 50

## 气泡外观（像素硬边 + 冰蓝描边，与 AI 娘深蓝调色板同族）
## 气泡显示开关（2026-11-05 主人要求：气泡弹出会遮挡左下角侧栏 → 默认不显示。
## 台词逻辑/钩子计数照跑，只是不上屏；想恢复改成 true 即可）
var show_bubbles := false
const BUBBLE_W := 272.0
const BUBBLE_PAD := 10
const BUBBLE_BG := Color(0.91, 0.95, 1.0)
const BUBBLE_BORDER := Color(0.310, 0.757, 0.965)
const BUBBLE_TEXT := Color(0.098, 0.133, 0.235)

## 本地兜底台词（大肥鱼风格；LLM 未接/超时/空回时用，永远站玩家这边）
const FALLBACKS := {
	H_OPENING: [
		"本鲸上线！白米饭先摆好，今天别鬼抽。",
		"醒了醒了，token 已就位，开打。",
		"AI 娘到位，这局我陪你到底。",
	],
	H_CHEER: [
		"三连了，这波白饭没白吃！",
		"连段起飞，本鲸批准了！",
		"就这手感，铁盆都敲出火星了。",
	],
	H_DANGER: [
		"额度见底了，先苟一口白饭？",
		"别硬撑，token 烧光我可不管你。",
		"血条比我的显存还虚，稳住。",
	],
	H_RETORT: [
		"我要验牌！你满屏幻觉，铁盆先扣你头上。",
		"丢的是脸又不是 token，睡你的觉去。",
		"本鲸这叫活人感，含机量爆表。",
		"真当我是便宜货啊？",
	],
}

# ── 可调参数（接线层/测试可改）────────────────────────
var llm_timeout := 3.0          ## LLM 回调等待上限；超时先播兜底，迟到回调丢弃
var retort_delay := 0.5         ## 敌台词后延迟多久回怼
var bubble_hold := 2.4          ## 一条台词停留时长（不含淡出）
var fade_sec := 0.22            ## 淡出时长
var cheer_streak_threshold := 3 ## 连段喝彩门槛
var cheer_min_turn_gap := 2     ## 两次喝彩最小回合间隔
var danger_ratio := 0.3         ## 濒危阈值（HP/MAX < 该值）
var max_cheer := 2              ## 每场喝彩上限
var max_retort := 2             ## 每场回怼上限

# ── 状态 ─────────────────────────────────────────────
var _provider := Callable()
var _anchor: Control = null
var _bubble: PanelContainer = null
var _label: Label = null
var _tail: Label = null
var _built := false

var _now := 0.0
var _seq := 0
var _queue: Array[Dictionary] = []
var _active_job: Dictionary = {}
var _active_text := ""
var _active_left := 0.0
var _fading := false
var _pending := false
var _pending_left := 0.0
var _request_serial := 0
var _used: Dictionary = {}
var _fallback_i: Dictionary = {}
var _last_cheer_turn := -9999
var _danger_done := false
var _spoken: Array[Dictionary] = []
var _pop_tw: Tween = null
var _fade_tw: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_bubble()


func _exit_tree() -> void:
	# 作废所有在途回调，防止场景销毁后 provider 回调打到野对象
	_request_serial += 1
	_pending = false


# ─────────────────────────────────────────────────────────
#  公共接口
# ─────────────────────────────────────────────────────────
## 绑定气泡锚点（一般是 AiCompanion）与 LLM provider。
## provider 形如 func(job: Dictionary, reply: Callable) -> void：
##   job = {"hook": "retort", "context": {...}}；必须立刻返回，异步时再 reply.call(text)。
## 不给 provider 时全部走本地兜底。
func setup(anchor: Control = null, provider: Callable = Callable()) -> void:
	_anchor = anchor
	if provider.is_valid():
		_provider = provider
	_build_bubble()
	_ensure_defaults()


## 换 provider（null / 无效 Callable 即回到本地兜底）
func set_provider(provider: Callable) -> void:
	_provider = provider


## 换锚点（AI 娘立绘/companion 控件）
func set_anchor_control(anchor: Control) -> void:
	_anchor = anchor


## 开一场战斗：清空上一场状态并排入开场问候（1 次/场）
func battle_started() -> void:
	_reset_battle()
	_used[H_OPENING] = 1
	_enqueue(H_OPENING, {})


## 收场：清空队列/在途/气泡，不再补开场
func stop_battle() -> void:
	_reset_battle()


## 连段喝彩：streak ≥3，2 次/场，两次间隔 ≥2 回合（turn 由战斗界面传入）
func on_streak(streak: int, turn: int) -> void:
	_ensure_defaults()
	if streak < cheer_streak_threshold:
		return
	if int(_used.get(H_CHEER, 0)) >= max_cheer:
		return
	if turn - _last_cheer_turn < cheer_min_turn_gap:
		return
	_used[H_CHEER] = int(_used.get(H_CHEER, 0)) + 1
	_last_cheer_turn = turn
	_enqueue(H_CHEER, {"streak": streak, "turn": turn})


## 濒危关心：HP 首次跌破 30%，1 次/场（回血后再掉不再触发）
func on_hp_changed(hp: int, max_hp: int) -> void:
	_ensure_defaults()
	if max_hp <= 0 or _danger_done:
		return
	if float(hp) / float(max_hp) >= danger_ratio:
		return
	_danger_done = true
	_used[H_DANGER] = 1
	_enqueue(H_DANGER, {"hp": hp, "max_hp": max_hp})


## 敌人刚说完 MARK/TAUNT 台词：延迟 0.5s 回怼，2 次/场，最高优先级。
## 只应由战斗界面在敌人 MARK/TAUNT 后调用；文本原样传入即可。
func notify_enemy_line(text: String) -> void:
	_ensure_defaults()
	var line := text.strip_edges()
	if line == "":
		return
	if int(_used.get(H_RETORT, 0)) >= max_retort:
		return
	_used[H_RETORT] = int(_used.get(H_RETORT, 0)) + 1
	_enqueue(H_RETORT, {"enemy_line": line})


## 是否还有气泡在播/排队（接线层可用于错峰）
func is_busy() -> bool:
	return not _active_job.is_empty() or _pending or not _queue.is_empty()


# ─────────────────────────────────────────────────────────
#  钩子调度（内部时钟，全部在 _process 里推进，不 await）
# ─────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_now += delta

	# 1) LLM 超时：先播兜底；迟到回调由 serial 校验丢弃
	if _pending:
		_pending_left -= delta
		if _pending_left <= 0.0:
			_pending = false
			var hook := String(_active_job.get("hook", H_OPENING))
			_show_line(_fallback_for(hook))

	# 2) 当前气泡计时 + 淡出
	if not _active_job.is_empty():
		_active_left -= delta
		if _active_left <= fade_sec and not _fading:
			_start_fade()
		if _active_left <= 0.0:
			_active_job = {}
			_active_text = ""

	# 3) 空出来了才取队首（同帧多钩只放 1 条）
	if _active_job.is_empty() and not _pending:
		_pump()


func _enqueue(hook: String, ctx: Dictionary, delay: float = -1.0) -> void:
	var wait := retort_delay if hook == H_RETORT else 0.0
	if delay >= 0.0:
		wait = delay
	_queue.append({
		"hook": hook,
		"context": ctx,
		"priority": int(PRIORITY.get(hook, 0)),
		"ready_at": _now + maxf(0.0, wait),
		"seq": _seq,
	})
	_seq += 1


## 取「已到点 + 优先级最高 + 同优先级先来」的一条
func _pump() -> void:
	var best := -1
	for i in _queue.size():
		var job: Dictionary = _queue[i]
		if float(job.get("ready_at", 0.0)) > _now:
			continue
		if best < 0:
			best = i
			continue
		var bj: Dictionary = _queue[best]
		if int(job.get("priority", 0)) > int(bj.get("priority", 0)):
			best = i
		elif int(job.get("priority", 0)) == int(bj.get("priority", 0)) \
				and int(job.get("seq", 0)) < int(bj.get("seq", 0)):
			best = i
	if best < 0:
		return
	var job: Dictionary = _queue[best]
	_queue.remove_at(best)
	_start_job(job)


func _start_job(job: Dictionary) -> void:
	_active_job = job
	_active_text = ""
	_fading = false
	if _provider.is_valid() and show_bubbles:
		## 气泡不显示时跳过 LLM 请求（纯省 token，本地兜底台词也不上屏）
		_pending = true
		_pending_left = maxf(0.01, llm_timeout)
		_request_serial += 1
		var serial := _request_serial
		var reply := func(text: String) -> void:
			_on_provider_reply(serial, text)
		_provider.call({"hook": String(job.get("hook", "")),
				"context": job.get("context", {})}, reply)
	else:
		_show_line(_fallback_for(String(job.get("hook", H_OPENING))))


func _on_provider_reply(serial: int, text: String) -> void:
	# 超时后的迟到回调 / 换局后的旧回调：丢弃
	if not _pending or serial != _request_serial:
		return
	_pending = false
	var hook := String(_active_job.get("hook", H_OPENING))
	var line := _sanitize(text)
	if line == "":
		line = _fallback_for(hook)
	_show_line(line)


# ─────────────────────────────────────────────────────────
#  气泡
# ─────────────────────────────────────────────────────────
func _build_bubble() -> void:
	if _built:
		return
	_built = true
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_theme_stylebox_override("panel",
			UiKit.flat(BUBBLE_BG, BUBBLE_BORDER, 2, BUBBLE_PAD))
	_bubble.custom_minimum_size = Vector2(BUBBLE_W, 0)
	_bubble.z_index = 40
	_bubble.visible = false
	add_child(_bubble)

	_label = UiKit.label("", UiKit.FS_XS, BUBBLE_TEXT)
	_label.name = "Text"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.custom_minimum_size = Vector2(BUBBLE_W - BUBBLE_PAD * 2, 0)
	_bubble.add_child(_label)

	_tail = UiKit.label("▼", UiKit.FS_XS, BUBBLE_BORDER)
	_tail.name = "Tail"
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.z_index = 41
	_tail.visible = false
	add_child(_tail)


func _show_line(raw: String) -> void:
	var hook := String(_active_job.get("hook", H_OPENING))
	var text := _sanitize(raw)
	if text == "":
		text = _fallback_for(hook)
	_active_text = text
	_active_left = maxf(0.2, bubble_hold) + maxf(0.0, fade_sec)
	_fading = false
	_spoken.append({"hook": hook, "text": text, "at": _now})
	line_spoken.emit(hook, text)

	if not _built:
		return
	_label.text = text
	_label.visible = true

	# 按实际行数定气泡高度（中文按宽自动换行；最深 3 行内不撑爆屏幕）
	var content_w := BUBBLE_W - BUBBLE_PAD * 2
	var h := 30.0
	var f: Font = _label.get_theme_font("font")
	if f != null:
		var fs: int = _label.get_theme_font_size("font_size")
		var ts := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, content_w, fs)
		h = maxf(28.0, ts.y + BUBBLE_PAD * 2 + 2.0)
	_bubble.custom_minimum_size = Vector2(BUBBLE_W, h)
	_bubble.size = Vector2(BUBBLE_W, h)
	_label.custom_minimum_size = Vector2(content_w, maxf(12.0, h - BUBBLE_PAD * 2 - 2.0))
	_place_bubble()

	_bubble.visible = show_bubbles
	_tail.visible = show_bubbles
	_bubble.modulate = Color(1, 1, 1, 0)
	_tail.modulate = Color(1, 1, 1, 0)
	_bubble.pivot_offset = Vector2(BUBBLE_W * 0.5, h)
	_bubble.scale = Vector2(0.88, 0.88)
	if is_inside_tree():
		_pop_tw = create_tween()
		_pop_tw.set_parallel(true)
		_pop_tw.tween_property(_bubble, "scale", Vector2.ONE, 0.16) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_pop_tw.tween_property(_bubble, "modulate:a", 1.0, 0.12)
		_pop_tw.tween_property(_tail, "modulate:a", 1.0, 0.12)
	bubble_shown.emit(text)


func _place_bubble() -> void:
	if not _built:
		return
	var ar := Rect2(Vector2.ZERO, size)
	if _anchor != null and is_instance_valid(_anchor):
		var g := _anchor.get_global_rect()
		var host := get_global_rect()
		ar = Rect2(g.position - host.position, g.size)
	var bw := _bubble.size.x
	var bh := _bubble.size.y
	var cx := ar.position.x + ar.size.x * 0.44
	var max_x := maxf(8.0, size.x - bw - 8.0)
	var x := clampf(cx - bw * 0.5, 8.0, max_x)
	var y := ar.position.y + ar.size.y * 0.18 - bh - 10.0
	if y < 8.0:
		# 上方放不下（小窗口/测试宿主）：落到头顶下方，仍不遮卡面
		y = ar.position.y + ar.size.y * 0.18 + 10.0
	_bubble.position = Vector2(x, y)
	_tail.position = Vector2(x + bw * 0.5 - 8.0, y + bh - 2.0)


func _start_fade() -> void:
	_fading = true
	if not _built or not is_inside_tree():
		return
	_fade_tw = create_tween()
	_fade_tw.set_parallel(true)
	_fade_tw.tween_property(_bubble, "modulate:a", 0.0, maxf(0.01, fade_sec))
	_fade_tw.tween_property(_tail, "modulate:a", 0.0, maxf(0.01, fade_sec))


func _hide_bubble() -> void:
	if _pop_tw != null:
		_pop_tw.kill()
		_pop_tw = null
	if _fade_tw != null:
		_fade_tw.kill()
		_fade_tw = null
	if _bubble != null:
		_bubble.visible = false
		_bubble.modulate = Color.WHITE
	if _tail != null:
		_tail.visible = false
		_tail.modulate = Color.WHITE


# ─────────────────────────────────────────────────────────
#  工具
# ─────────────────────────────────────────────────────────
func _reset_battle() -> void:
	_queue.clear()
	_active_job = {}
	_active_text = ""
	_active_left = 0.0
	_fading = false
	_pending = false
	_pending_left = 0.0
	_request_serial += 1
	_used = {H_OPENING: 0, H_CHEER: 0, H_DANGER: 0, H_RETORT: 0}
	_fallback_i.clear()
	_last_cheer_turn = -9999
	_danger_done = false
	_spoken.clear()
	_hide_bubble()


func _ensure_defaults() -> void:
	if _used.is_empty():
		_used = {H_OPENING: 0, H_CHEER: 0, H_DANGER: 0, H_RETORT: 0}


func _fallback_for(hook: String) -> String:
	var arr: Array = FALLBACKS.get(hook, FALLBACKS[H_OPENING])
	var i := int(_fallback_i.get(hook, 0))
	_fallback_i[hook] = i + 1
	if arr.is_empty():
		return "……"
	return String(arr[i % arr.size()])


## 清洗 LLM 输出：去换行/引号/「小鲸：」前缀，压到 ≤50 字
func _sanitize(text: String) -> String:
	var t := text.strip_edges()
	if t.begins_with("小鲸：") or t.begins_with("小鲸:"):
		t = t.substr(3).strip_edges()
	t = t.replace("\r", " ").replace("\n", " ").strip_edges()
	if t.length() >= 2 and ((t.begins_with("\"") and t.ends_with("\"")) \
			or (t.begins_with("「") and t.ends_with("」"))):
		t = t.substr(1, t.length() - 2).strip_edges()
	if t.length() > MAX_CHARS:
		t = t.substr(0, MAX_CHARS) + "…"
	return t


# ─────────────────────────────────────────────────────────
#  测试钩子（headless 验收用，不参与玩法）
# ─────────────────────────────────────────────────────────
func debug_state() -> Dictionary:
	return {
		"used": _used.duplicate(),
		"queue": _queue.size(),
		"active": String(_active_job.get("hook", "")),
		"active_text": _active_text,
		"pending": _pending,
		"spoken": _spoken.duplicate(),
		"now": _now,
	}


func debug_spoken(hook: String = "") -> Array:
	if hook == "":
		return _spoken.duplicate()
	var out: Array = []
	for s in _spoken:
		if String(s.get("hook", "")) == hook:
			out.append(s.duplicate())
	return out
