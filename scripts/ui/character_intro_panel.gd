class_name CharacterIntroPanel
extends Control
## 角色介绍面板（2026-11-11 主人要求）：
##   「对应角色的对应风格 UI 动态弹入界面，然后展开，用于介绍角色」
##   三段式：① 从某条边滑入（只有一条边，像从画外抽出来）
##          ② 滚到最终位置停稳
##          ③ 沿长边展开，露出里面的介绍内容
##
## 四套风格各自用一种「物质隐喻」承载内容，不是换皮的同一块面板
## （主人要求「观察立绘并据此设计」）：
##   · deepdeek 深蓝试剂瓶 —— 侧脸贴着蓝黑玻璃，面板是**冷凝金属条**：
##               边缘有冷光描边，展开时从顶部滚下一条液体状的光带
##   · kweno    青花瓷执壶 —— 茶室白瓷，面板是**卷轴**：
##               米白纸面 + 青花细线，从左侧像铺开画轴一样横向展开
##   · chatppt  白龙圣女   —— 冰晶神殿，面板是**冰裂棱柱**：
##               冷白半透明 + 棱线高光，展开时像晶体沿着裂纹生长
##   · grock    熔岩小恶魔 —— 火海黑岩，面板是**熔岩裂口**：
##               暗红岩面 + 炽金裂纹，展开时裂纹先亮后撕开
##
## 定位：四个角色的最终位置由主人在参考图里用红框标定（2026-11-11），
## 已换算成 1600×900 基准坐标，见 PRESETS 的 rect 字段。
##
## 用法：
##   var p := CharacterIntroPanel.new()
##   add_child(p)
##   p.present("deepdeek")   # 播完三段式
##   p.dismiss()             # 逆向收起

signal present_finished
signal dismiss_finished

## 1600×900 基准下的最终位置（来自主人 4 张参考图的红框实测换算）
##   deepseek x[1148.6,1446.8] y[154.4,686.9]
##   kweno    x[ 132.6, 429.5] y[135.6,690.6]
##   chatppt  x[1195.5,1485.6] y[163.8,737.5]
##   grock    x[1219.9,1480.6] y[145.6,688.1]
## 四个框都是竖版（约 290~298 × 532~574），统一取整到设计网格。
## ⚠ 2026-11-11 主人二次修订：**展开态必须紧贴画框那一侧**，不能悬在空中。
##   原来的位置照抄红框图内边界，结果右侧留了 153px 空档（x 1148 + 299 = 1447 ≠ 1600）。
##   现在把「贴边侧」钉死在 0 / 1600，纵向位置仍用红框的原值。
const PRESETS := {
	"deepdeek": {
		"rect": Rect2(1301, 154, 299, 533),   # 右缘贴 1600
		"edge": "right",        # 从右边缘滑入（立绘在左，面板在右，从屏幕外抽出）
		"expand": "down",       # 向下展开
		"accent": Color("#4fc1f6"),
		"fill": Color(0.043, 0.071, 0.129, 0.93),
		"line": Color(0.180, 0.329, 0.478),
	},
	"kweno": {
		"rect": Rect2(0, 136, 297, 555),      # 左缘贴 0
		"edge": "left",         # 千问立绘在右，面板在左，从左边抽出
		"expand": "right",      # 向右展开（像铺开画轴）
		# 色板统一到花青 #3A5A78（元青花：钴蓝只活在立体瓷器上，平面一律花青）
		"accent": Color("#3A5A78"),
		"fill": Color(0.890, 0.851, 0.776, 0.94),   # #E3D9C6 灰黄纸色（旧米白微调）
		"line": Color("#3A5A78"),
	},
	"chatppt": {
		"rect": Rect2(1310, 164, 290, 574),   # 右缘贴 1600
		"edge": "right",
		"expand": "down",
		"accent": Color("#b9c4f0"),
		"fill": Color(0.898, 0.914, 0.965, 0.90),
		"line": Color(0.667, 0.729, 0.878),
	},
	"grock": {
		"rect": Rect2(1339, 146, 261, 542),   # 右缘贴 1600
		"edge": "right",
		"expand": "down",
		"accent": Color("#e39357"),
		"fill": Color(0.180, 0.102, 0.086, 0.94),
		"line": Color(0.502, 0.231, 0.161),
	},
}

## 三段式时长（秒）——主人要「滑入 → 停稳 → 展开」，三拍要分得清
const T_SLIDE := 0.52      ## 从画外抽到最终位置
const T_SETTLE := 0.10     ## 停稳（给眼睛一拍）
const T_EXPAND := 0.46     ## 沿长边展开
const T_DISMISS := 0.34    ## 收起

## 收起时面板缩到「一条边」（只剩 4px），滑出时带着这个厚度一起走
const THIN := 4.0

## 朱砂：立轴右下角朱文小印的印泥色（与 sts_card_view.C_VERMILION 同值 #A0323A）。
## 印框与印面文字共用这一处定义，改色只改这里。
const C_VERMILION := Color(0.627, 0.196, 0.227)

## 折叠态：整块面板**完全滑出画面**，屏内只留箭头把手。
## （2026-11-11 主人二次修订：第一版收成了贴边窄条，主人指着截图说
##   「红框这些地方也要缩进去，仅留箭头选项」—— 要的是干净全屏，
##   所以面板本体必须彻底出屏，不能留任何余条。）
## 屏内残留 = 0：折叠后面板左缘刚好在 1600 之外（右侧角色）或右缘在 0 之外（左侧角色）。
## 折叠/展开的动画时长
const T_FOLD := 0.30

var _char_id := ""
var _preset: Dictionary = {}
var _cur := Rect2()          ## 当前动画中的矩形
var _tw: Tween = null
var _revealed := false
## 是否处于「整块缩到屏外」的折叠态（屏内只剩箭头）
var _folded := false

## 面板本体（画在这里；用 draw 而非子节点，四套风格的纹理感才好做）
var _panel: Control = null
## 内容容器（展开完成后淡入）
var _body: Control = null
## 贴边箭头把手（常驻，折叠时是唯一可见可点的东西）
var _handle: Button = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	## ⚠ 显式装主题（2026-11-18 修中文方框）：
	##   本面板所有 Label 只设 font_size、不设 font，完全依赖全局 theme 继承。
	##   但 Web 版里继承链没把中文字体送到这里 → 中文全渲染成方框
	##   （同一构建的 LaunchScreen 因为每个 Label 都显式 add_theme_font_override
	##    所以中文正常，这就是最有力的对照）。
	##   在根节点装一份 theme，子节点自然继承，比逐个 Label 打补丁可靠。
	theme = PixelTheme.build()
	_panel = Control.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_panel)
	_panel.resized.connect(func() -> void: _panel.queue_redraw())
	add_child(_panel)

	_body = Control.new()
	_body.name = "Body"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.modulate.a = 0.0
	add_child(_body)

	# 贴边把手：常驻在最上层，负责「收起 / 展开」切换。
	# 用 Button 而不是自绘：要可点、要 hover、要让主人一眼看出能按。
	_handle = Button.new()
	_handle.name = "FoldHandle"
	_handle.focus_mode = Control.FOCUS_NONE
	_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_handle.add_theme_font_size_override("font_size", 18)
	_handle.pressed.connect(toggle_fold)
	add_child(_handle)

	visible = false


## 播完整三段式。同一角色重复调用 = 无事发生；换了角色 = 立刻换内容重播。
## ⚠ 幂等条件必须同时看「已展开」**和**「角色相同」：只判 _revealed 会让切角色后
##   面板继续显示上一位的介绍（实测 kweno 画面里写着 DeepDeek）。
func present(char_id: String) -> void:
	if not PRESETS.has(char_id):
		return
	if _revealed and _char_id == char_id:
		return
	_char_id = char_id
	_preset = PRESETS[char_id]
	_build_body(char_id)
	visible = true
	if _handle != null:
		_handle.visible = true
	# 重播前必须清掉旧的「已展开」标记与进度，否则换角色后 is_revealed()
	# 会继续返回 true，外部据此判断就会以为新面板已就位。
	_revealed = false
	_folded = false          # 切角色一律回到展开态：主人想看新角色是谁
	_prog = 0.0
	if _body != null:
		_body.modulate.a = 0.0

	var target := _preset["rect"] as Rect2
	var edge: String = _preset["edge"]
	var expand: String = _preset["expand"]

	# ① 起点：贴在目标边的画外，且是「一条边」的厚度
	var start := target
	if edge == "right":
		start.position.x = 1600.0 + 8.0
	else:
		start.position.x = -target.size.x - 8.0
	if expand == "right":
		start.size.x = THIN      # 横向展开 → 起手是一条竖边
	else:
		start.size.y = THIN      # 纵向展开 → 起手是一条横边

	# ② 滑入：从画外到最终位置（保持「一条边」的形态，位置先到位）
	_kill()
	_cur = Rect2(start.position, start.size)
	_apply_cur()
	_tw = create_tween()
	# 用 EASE_OUT：滑入段末尾减速，视觉上「到位」而不是「撞停」
	_tw.tween_method(_set_slide, 0.0, 1.0, T_SLIDE) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# ③ 停稳一拍，再把「一条边」撑开成整块面板
	_tw.tween_interval(T_SETTLE)
	_tw.tween_method(_set_expand, 0.0, 1.0, T_EXPAND) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# ④ 内容淡入
	_tw.tween_property(_body, "modulate:a", 1.0, 0.26)
	_tw.tween_callback(func() -> void:
		_revealed = true
		present_finished.emit())
	# 面板重绘跟着整段动画走（把进度推给 _draw_panel 做流光/裂纹）
	_tw.parallel().tween_property(self, "_prog", 1.0, T_SLIDE + T_SETTLE + T_EXPAND) \
			.set_delay(0.0)


func dismiss() -> void:
	if not visible:
		return
	_revealed = false
	_kill()
	_tw = create_tween()
	_tw.tween_property(_body, "modulate:a", 0.0, 0.14)
	# 逆向：先收回一条边，再滑出画外
	_tw.tween_method(_set_dismiss, 0.0, 1.0, T_DISMISS) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tw.tween_callback(func() -> void:
		visible = false
		if _handle != null:
			_handle.visible = false
		dismiss_finished.emit())


## 收起：k=0 当前整块 → k=0.55 收回一条边 → k=1 滑出画外
func _set_dismiss(k: float) -> void:
	var tr := _preset["rect"] as Rect2
	var edge: String = _preset.get("edge", "right")
	var expand: String = _preset.get("expand", "down")
	var r := Rect2(tr.position, tr.size)
	# 前段：把长边收回 THIN
	var collapse := clampf(k / 0.55, 0.0, 1.0)
	if expand == "right":
		r.size.x = lerpf(tr.size.x, THIN, collapse)
	else:
		r.size.y = lerpf(tr.size.y, THIN, collapse)
	# 后段：沿滑入方向退出画外
	var out := clampf((k - 0.55) / 0.45, 0.0, 1.0)
	if edge == "right":
		r.position.x = lerpf(tr.position.x, 1600.0 + 8.0, out)
	else:
		r.position.x = lerpf(tr.position.x, -tr.size.x - 8.0, out)
	_cur = r
	_apply_cur()


func is_revealed() -> bool:
	return _revealed


func is_folded() -> bool:
	return _folded


## 切换折叠 / 展开（主人点贴边箭头时调）。
## 折叠态 = 面板收成贴住屏幕对应侧的一条窄边，只留把手 → 他要看角色全图。
func toggle_fold() -> void:
	set_folded(not _folded)


func set_folded(fold: bool) -> void:
	if _preset.is_empty() or _folded == fold:
		return
	_folded = fold
	_kill()
	var from := _cur
	var to := _fold_rect() if fold else (_preset["rect"] as Rect2)
	_tw = create_tween()
	# 折叠时先淡出内容（文字在半宽时挤成一团很难看），展开时最后再淡入
	if fold:
		_tw.tween_property(_body, "modulate:a", 0.0, 0.12)
	# 从折叠态展开：内容等面板撑开后再出现。
	# 判据是「当前矩形整体在屏外」，不再依赖某个宽度常量（折叠后宽度仍是终态值）。
	var off_screen := from.position.x >= 1600.0 or (from.position.x + from.size.x) <= 0.0
	if not fold and off_screen:
		_body.modulate.a = 0.0
	_tw.tween_method(func(k: float) -> void:
		_cur = Rect2(from.position.lerp(to.position, k), from.size.lerp(to.size, k))
		_apply_cur(), 0.0, 1.0, T_FOLD) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not fold:
		_tw.tween_property(_body, "modulate:a", 1.0, 0.18)


## 折叠态的矩形：整块推到画面之外，屏内一点不留。
## 高度保持 —— 出屏动画是纯横向平移，看起来像「面板被吸进边框」。
func _fold_rect() -> Rect2:
	var tr := _preset["rect"] as Rect2
	var edge: String = _preset.get("edge", "right")
	var r := Rect2(tr.position, tr.size)
	if edge == "right":
		r.position.x = 1600.0        # 左缘正好压在右边界 → 整块在屏外
	else:
		r.position.x = -tr.size.x    # 右缘正好压在左边界 → 整块在屏外
	return r


## 把手位置：折叠前后都在**屏内边缘**，是唯一可见可点的东西。
## 展开态时它贴在面板朝画面中心的那一侧（尖头指回侧边，提示能收）；
## 折叠态时它贴在屏幕边缘（尖头指向画面内，提示能拉出来）。
func _place_handle() -> void:
	if _handle == null or _preset.is_empty():
		return
	var edge: String = _preset.get("edge", "right")
	var hw := 22.0
	var hh := 76.0
	# 纵向：跟着面板可见部分的中点走。折叠时面板已在屏外，
	# 所以用终态 rect 的中点，保证把手不会跟着飞出屏幕。
	var tr := _preset["rect"] as Rect2
	var cy := tr.position.y + tr.size.y * 0.5 - hh * 0.5
	var cx: float
	if edge == "right":
		# 面板贴右边界：展开时把手在面板左侧，折叠时贴在屏幕右缘内侧
		cx = (_cur.position.x - hw) if not _folded else (1600.0 - hw)
	else:
		cx = (_cur.position.x + _cur.size.x) if not _folded else 0.0
	_handle.position = Vector2(cx, cy)
	_handle.size = Vector2(hw, hh)
	# 箭头指向「点下去会发生什么」：折叠态 → 拉出来（朝画面内）；展开态 → 收进去（朝侧边）
	if edge == "right":
		_handle.text = "◀" if _folded else "▶"
	else:
		_handle.text = "▶" if _folded else "◀"
	var accent: Color = _preset["accent"]
	_handle.add_theme_color_override("font_color", accent)
	_handle.add_theme_color_override("font_hover_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color((_preset["fill"] as Color), 0.92)
	sb.border_color = Color(accent, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	_handle.add_theme_stylebox_override("normal", sb)
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = Color(accent, 0.30)
	sbh.border_color = accent
	_handle.add_theme_stylebox_override("hover", sbh)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = Color(accent, 0.45)
	_handle.add_theme_stylebox_override("pressed", sbp)


## 测试/截图用：直接跳到「滑入+展开」全部完成的终态（不播动画）
func debug_finish_present() -> void:
	if _preset.is_empty():
		return
	_kill()
	_prog = 1.0
	_revealed = true
	_folded = false
	visible = true
	_cur = _preset["rect"] as Rect2
	_apply_cur()
	if _body != null:
		_body.modulate.a = 1.0


func current_rect() -> Rect2:
	return _cur


func _kill() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = null


## 滑入段：位置从画外走到最终位置，**尺寸此时仍是「一条边」**
## ⚠ 这里必须带 thinned size，不能直接用 target.size —— 否则滑入的过程中
##   面板已经是完整大小，就变成「整块面板横着飞进来」，主人要的
##   「从某条边弹出、之后才展开」的两段感就没了（实测就是这个 bug）。
func _set_slide(k: float) -> void:
	var target := _preset["rect"] as Rect2
	var edge: String = _preset["edge"]
	var expand: String = _preset["expand"]
	var start_x := (1600.0 + 8.0) if edge == "right" else (-target.size.x - 8.0)
	var sz := target.size
	if expand == "right":
		sz.x = THIN
	else:
		sz.y = THIN
	_cur = Rect2(Vector2(lerpf(start_x, target.position.x, k), target.position.y), sz)
	_apply_cur()


func _set_expand(k: float) -> void:
	var target := _preset["rect"] as Rect2
	var expand: String = _preset["expand"]
	var r := Rect2(target.position, target.size)
	if expand == "right":
		r.size.x = lerpf(THIN, target.size.x, k)
	else:
		r.size.y = lerpf(THIN, target.size.y, k)
	_cur = r
	_apply_cur()


func _apply_cur() -> void:
	_panel.position = _cur.position
	_panel.size = _cur.size
	_panel.queue_redraw()
	# 内容区跟着面板走，但**不跟着变窄**：折叠时内容会淡出，
	# 若把它的 size 一起压窄，展开回来的第一帧文字会重排一次（看得见的抖）。
	# 所以只对齐位置与高度，宽度固定用终态宽度。
	if _body != null:
		var tr := _preset.get("rect", _cur) as Rect2
		_body.position = _cur.position
		_body.size = Vector2(tr.size.x, _cur.size.y)
	_place_handle()


## 面板重绘进度 0..1（滑入+停稳+展开全程）。tween 直接推它，setter 触发重绘。
var _prog := 0.0:
	set(v):
		_prog = v
		if _panel != null:
			_panel.queue_redraw()


func _draw_panel() -> void:
	if _preset.is_empty():
		return
	var sz := _panel.size
	if sz.x < 1.0 or sz.y < 1.0:
		return
	var accent: Color = _preset["accent"]
	var fill: Color = _preset["fill"]
	var line: Color = _preset["line"]

	match _char_id:
		"deepdeek":
			_draw_coldmetal(sz, fill, line, accent)
		"kweno":
			_draw_scroll(sz, fill, line, accent)
		"chatppt":
			_draw_ice(sz, fill, line, accent)
		"grock":
			_draw_lava(sz, fill, line, accent)


## 深蓝冷凝金属：冷光描边 + 一条自上而下滚动的液体光带
func _draw_coldmetal(sz: Vector2, fill: Color, line: Color, accent: Color) -> void:
	_panel.draw_rect(Rect2(Vector2.ZERO, sz), fill)
	# 双层描边：外冷光、内实线
	_panel.draw_rect(Rect2(Vector2.ZERO, sz), Color(accent, 0.30), false, 3.0)
	_panel.draw_rect(Rect2(Vector2(3, 3), sz - Vector2(6, 6)), line, false, 1.0)
	# 顶部冷凝光带：随 _prog 从上滚到中段
	var band_y := lerpf(-24.0, sz.y * 0.34, clampf(_prog / 0.72, 0.0, 1.0))
	for i in 3:
		var a := 0.20 - i * 0.06
		_panel.draw_rect(Rect2(4, band_y + i * 5.0, sz.x - 8, 3.0), Color(accent, a))
	# 左缘竖向刻度线（试剂瓶刻度的意象）
	var n := int(sz.y / 26.0)
	for i in n:
		var y := 14.0 + i * 26.0
		var w := 10.0 if i % 4 == 0 else 6.0
		_panel.draw_line(Vector2(6, y), Vector2(6 + w, y), Color(accent, 0.22), 1.0)


## 青花卷轴（kweno）：米白纸面 + 左右两条青花竖带 + 一串缠枝点。
## 纸色来自 PRESETS 的 fill（#E3D9C6 灰黄纸），竖带用 line 色（#3A5A78 花青）。
func _draw_scroll(sz: Vector2, fill: Color, line: Color, accent: Color) -> void:
	# 纸面
	_panel.draw_rect(Rect2(0, 0, sz.x, sz.y), fill)
	# 左右两条竖带（各 9px），像横披的天地边
	var band_w := 9.0
	_panel.draw_rect(Rect2(0, 0, band_w, sz.y), line)
	_panel.draw_rect(Rect2(sz.x - band_w, 0, band_w, sz.y), line)
	# 缠枝点：沿两条竖带外侧各缀一串小圆点（等距）
	var step := maxf(9.0, sz.y / 22.0)
	var y := step * 0.5
	while y < sz.y:
		_panel.draw_circle(Vector2(4.5, y), 2.0, accent)
		_panel.draw_circle(Vector2(sz.x - 4.5, y), 2.0, accent)
		y += step


func _draw_ice(sz: Vector2, fill: Color, line: Color, accent: Color) -> void:
	_panel.draw_rect(Rect2(Vector2.ZERO, sz), fill)
	# 外棱：比纸面更冷的白
	_panel.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.55), false, 2.0)
	# 竖向棱线（晶体解理面）：多条平行斜线
	var cols := 4
	for i in cols:
		var x := sz.x * (0.18 + i * 0.22)
		_panel.draw_line(Vector2(x, 0), Vector2(x - sz.x * 0.06, sz.y),
				Color(accent, 0.13), 1.0)
	# 裂纹高光：随 _prog 从上往下长
	var grow := clampf(_prog * 1.25, 0.0, 1.0) * sz.y
	_panel.draw_line(Vector2(sz.x * 0.5, 0), Vector2(sz.x * 0.5, grow),
			Color(1, 1, 1, 0.55), 1.6)
	for side: float in [-1.0, 1.0]:
		var bx: float = sz.x * 0.5 + side * sz.x * 0.17
		_panel.draw_line(Vector2(sz.x * 0.5, grow * 0.45),
				Vector2(bx, minf(grow * 0.78, sz.y)), Color(1, 1, 1, 0.34), 1.1)
	# 顶部霜光
	_panel.draw_rect(Rect2(0, 0, sz.x, 3.0), Color(1, 1, 1, 0.30))


## 熔岩裂口：暗红岩面 + 炽金裂纹先亮后撕开
func _draw_lava(sz: Vector2, fill: Color, line: Color, accent: Color) -> void:
	_panel.draw_rect(Rect2(Vector2.ZERO, sz), fill)
	# 岩面：随机暗斑（用确定性伪随机，逐帧重绘不闪）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261111
	for i in 26:
		var px := rng.randf() * sz.x
		var py := rng.randf() * sz.y
		var rr := rng.randf_range(4.0, 16.0)
		_panel.draw_circle(Vector2(px, py), rr, Color(0.10, 0.06, 0.05, 0.35))
	# 边框：烧红的岩缘
	_panel.draw_rect(Rect2(Vector2.ZERO, sz), Color(accent, 0.40), false, 2.0)
	# 主裂纹：从顶部往下蜿蜒，亮度随 _prog 先增后稳
	var heat := clampf(_prog * 1.6, 0.0, 1.0)
	var pts := PackedVector2Array()
	var n := 9
	for i in n:
		var t := float(i) / float(n - 1)
		var y := t * sz.y
		var x := sz.x * (0.5 + sin(t * 5.1 + 0.7) * 0.16 + sin(t * 11.3) * 0.05)
		pts.append(Vector2(x, y))
	var lit := int(ceil(n * heat))
	for i in maxi(lit - 1, 0):
		var a := 0.85 if i < lit - 2 else 0.45
		_panel.draw_line(pts[i], pts[i + 1], Color(1.0, 0.72, 0.32, a), 2.2)
		_panel.draw_line(pts[i], pts[i + 1], Color(1.0, 0.92, 0.70, a * 0.55), 1.0)
	# 分叉
	if lit >= 4:
		_panel.draw_line(pts[3], pts[3] + Vector2(sz.x * 0.22, sz.y * 0.09),
				Color(1.0, 0.62, 0.26, 0.42), 1.4)
	if lit >= 6:
		_panel.draw_line(pts[5], pts[5] + Vector2(-sz.x * 0.20, sz.y * 0.07),
				Color(1.0, 0.62, 0.26, 0.38), 1.3)


## 介绍内容：从 AiPool 的现成字段组合生成（主人 2026-11-11 授权「介绍方案你来取」）。
## 不另写一份文案表，避免两处数据漂移 —— display_name / family / intro_line /
## taste_rules 都是既有真相，这里只负责排版。
func _build_body(cid: String) -> void:
	for c in _body.get_children():
		c.queue_free()
	var ai := AiPool.get_ai(cid)
	if ai == null:
		return
	var sz := (_preset["rect"] as Rect2).size
	var accent: Color = _preset["accent"]
	var is_light: bool = _is_light(_preset["fill"] as Color)
	var ink := Color(0.16, 0.18, 0.26) if is_light else Color(0.88, 0.92, 1.0)
	var ink_dim := Color(0.36, 0.40, 0.50) if is_light else Color(0.62, 0.68, 0.82)

	_body.position = _preset["rect"].position
	_body.size = sz

	var W := sz.x
	var pad := 20.0
	var y := pad + 8.0

	# ① 角色名（大字距）
	var nm := Label.new()
	nm.text = ai.display_name
	nm.add_theme_font_size_override("font_size", 34)
	nm.add_theme_color_override("font_color", ink)
	nm.position = Vector2(pad, y)
	_body.add_child(nm)
	y += 44.0

	# ② 定位标签（family）+ 一条风格分隔线
	var fam := Label.new()
	fam.text = "／ %s" % ai.family
	fam.add_theme_font_size_override("font_size", 18)
	fam.add_theme_color_override("font_color", accent)
	fam.position = Vector2(pad, y)
	_body.add_child(fam)
	y += 30.0

	var sep := ColorRect.new()
	sep.color = Color(accent, 0.45)
	sep.position = Vector2(pad, y)
	sep.size = Vector2(W - pad * 2.0, 2.0)
	_body.add_child(sep)
	y += 20.0

	# ③ 口头禅（intro_line）—— 这是角色最有辨识度的一句
	var quote := Label.new()
	quote.text = "「%s」" % ai.intro_line
	quote.add_theme_font_size_override("font_size", 20)
	quote.add_theme_color_override("font_color", ink)
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.position = Vector2(pad, y)
	quote.size = Vector2(W - pad * 2.0, 62.0)
	_body.add_child(quote)
	y += 76.0

	# ④ 擅长维度（taste_rules → 中文短标签）
	var dims := _dimension_labels(cid)
	if dims.size() > 0:
		var hd := Label.new()
		hd.text = "擅长"
		hd.add_theme_font_size_override("font_size", 16)
		hd.add_theme_color_override("font_color", ink_dim)
		hd.position = Vector2(pad, y)
		_body.add_child(hd)
		y += 24.0
		for d in dims:
			var bullet := Label.new()
			bullet.text = "· %s" % d
			bullet.add_theme_font_size_override("font_size", 17)
			bullet.add_theme_color_override("font_color", ink)
			bullet.position = Vector2(pad + 6.0, y)
			_body.add_child(bullet)
			y += 24.0
		y += 12.0

	# ⑤ 呼吸手感条（V4 数值的图形化，让面板跟具体角色产生联系）
	var stats := _breath_stats(cid)
	if stats.size() > 0:
		var hs := Label.new()
		hs.text = "呼吸"
		hs.add_theme_font_size_override("font_size", 16)
		hs.add_theme_color_override("font_color", ink_dim)
		hs.position = Vector2(pad, y)
		_body.add_child(hs)
		y += 26.0
		var bar_w := W - pad * 2.0 - 66.0
		for pair in stats:
			var lbl: String = pair[0]
			var val: float = pair[1]
			var pct: float = clampf(pair[2], 0.0, 1.0)
			var lb := Label.new()
			lb.text = lbl
			lb.add_theme_font_size_override("font_size", 15)
			lb.add_theme_color_override("font_color", ink_dim)
			lb.position = Vector2(pad, y - 2.0)
			_body.add_child(lb)
			# 底槽
			var track := ColorRect.new()
			track.color = Color(accent, 0.14)
			track.position = Vector2(pad + 46.0, y + 6.0)
			track.size = Vector2(bar_w, 5.0)
			_body.add_child(track)
			# 填充条
			var fillb := ColorRect.new()
			fillb.color = Color(accent, 0.82)
			fillb.position = track.position
			fillb.size = Vector2(bar_w * pct, 5.0)
			_body.add_child(fillb)
			var vb := Label.new()
			vb.text = "%.1f" % val
			vb.add_theme_font_size_override("font_size", 14)
			vb.add_theme_color_override("font_color", ink_dim)
			vb.position = Vector2(pad + 46.0 + bar_w + 8.0, y - 2.0)
			_body.add_child(vb)
			y += 22.0


## 亮度判别：决定文字用深色还是浅色（青花瓷/冰晶面板是浅底）
func _is_light(c: Color) -> bool:
	return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) > 0.55


## 各角色擅长的维度（来自 AiPool.taste_rules 的语义归类，不是另编数据）
func _dimension_labels(cid: String) -> PackedStringArray:
	match cid:
		"deepdeek":
			return PackedStringArray(["需求边界", "结构化推理", "严格约束"])
		"kweno":
			return PackedStringArray(["中文长文", "成对示例", "表达流畅"])
		"chatppt":
			return PackedStringArray(["格式对齐", "通用对话", "条目清晰"])
		"grock":
			return PackedStringArray(["实时联网", "事实锚点", "证据成对"])
	return PackedStringArray()


## 呼吸手感（V4 预设值 → 条形图）。取最能体现角色差异的三项。
## 归一化上限取四项预设里的最大值：胸横 7.0 / 发纵 13.5 / 底锁 0.18
func _breath_stats(cid: String) -> Array:
	var p: Dictionary = GameSettings.breath_v4_preset(cid)
	if p.is_empty():
		return []
	return [
		["胸腔", float(p.get("chest_x", 0.0)), float(p.get("chest_x", 0.0)) / 7.0],
		["发梢", float(p.get("hair_y", 0.0)), float(p.get("hair_y", 0.0)) / 13.5],
		["底锁", float(p.get("lock_bottom", 0.0)), float(p.get("lock_bottom", 0.0)) / 0.18],
	]
