extends Control
class_name ArenaScreen
## 战斗界面：一场杀戮尖塔式战斗（2026-10-25 大改，取代德州扑克）。
##
## 布局：
##   左侧竖栏   玩家状态（HP / 格挡 / 能量 / 牌堆 / 回合）
##   中上       BAT 风格控制台（PromptConsole）——战斗日志，出牌流式敲卡名
##   中下舞台   敌人像素形象 + 意图 + HP 条（程序化画的小怪，按关卡换色）
##   右上       敌人信息（名字 / HP / 意图）
##   右侧       AI 娘吉祥物（deepdeek 睡觉 Q 版）
##   下方       手牌横向一排（点击打出），右下「结束回合」
##
## 纪律：本文件**不含任何战斗规则**——数值结算全在 StsCombat，
## 这里只把返回的事件渲染成动画和日志。

signal level_cleared(final_score: int)
signal level_failed(final_score: int)
signal advance_requested

const CARD_W := 150.0
const CARD_H := 226.0
const PAD := 24.0

# ── 布局刻度 ───────────────────────────────────────────
const RAIL_W := 220.0
const CONSOLE_X := 268.0
const CONSOLE_H := 300.0
const SIDE_W := 320.0
const STATUS_W := 700.0

# ── 手牌横排参数 ───────────────────────────────────────
const HAND_BOTTOM := 30.0
const HAND_GAP := 10.0
const HAND_MIN_GAP := -34.0
const HOVER_LIFT := 30.0

# ── 敌人舞台 ───────────────────────────────────────────
const STAGE_TOP := 348.0
const STAGE_BOTTOM := 812.0

var run: RunState = null
var level: LevelData = null
var combat: StsCombat = null

var _console: PromptConsole = null
var _card_layer: Control = null
var _hand_views: Array[StsCardView] = []
var _busy: bool = false
var _hovered: StsCardView = null

# 左侧竖栏（玩家状态）
var _rail: PanelContainer = null
var _rail_box: VBoxContainer = null
var _brief_label: Label = null
var _hp_label: Label = null
var _hp_fill: ColorRect = null
var _hp_host: Control = null
var _block_label: Label = null
var _energy_label: Label = null
var _piles_label: Label = null
var _turn_label: Label = null

# 右上敌人 HUD
var _enemy_name_label: Label = null
var _enemy_hp_label: Label = null
var _enemy_fill: ColorRect = null
var _enemy_hp_host: Control = null
var _enemy_block_label: Label = null
var _intent_label: Label = null

# 舞台敌人
var _enemy_root: Control = null
var _enemy_sprite: TextureRect = null
var _enemy_shadow: ColorRect = null

# 底部
var _status_label: Label = null
var _end_turn_button: Button = null

# AI 娘
var _companion: AiCompanion = null

# 特效层
var _fx_enabled := true
var _fx_root: Control = null
var _fx_flash: ColorRect = null

# 覆盖层（结算弹窗）
var _overlay: PanelContainer = null
var _overlay_title: Label = null
var _overlay_body: Label = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_console = PromptConsole.new()
	_console.name = "PromptConsole"


func setup(run_state: RunState, lv: LevelData) -> void:
	run = run_state
	level = lv


func _ready() -> void:
	_build_ui()
	resized.connect(_layout)
	await get_tree().process_frame
	_layout()
	_start_battle()


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

	var veil := ColorRect.new()
	veil.color = Color(0.043, 0.055, 0.086, 0.52)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var fx_bg := BgFx.new()
	fx_bg.name = "BgFx"
	fx_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fx_bg)

	_build_rail()
	_build_console_area()
	_build_right_hud()
	_build_stage()
	_build_bottom()
	_build_companion()

	_card_layer = Control.new()
	_card_layer.name = "CardLayer"
	_card_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_layer)

	_build_fx()
	_build_overlay()


## 左侧竖栏：玩家状态
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

	var head := UiKit.title_bar("L1 · 战斗", 0.0, HORIZONTAL_ALIGNMENT_LEFT, UiKit.TEXT)
	head.name = "RailTitle"
	_rail_box.add_child(head)

	_brief_label = UiKit.dim("", UiKit.FS_XS)
	_brief_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rail_box.add_child(_brief_label)

	_rail_box.add_child(UiKit.rule())

	_hp_label = UiKit.label("HP 80/80", UiKit.FS_S, Color(0.95, 0.35, 0.4))
	_rail_box.add_child(_hp_label)

	_hp_host = Control.new()
	_hp_host.custom_minimum_size = Vector2(0, 10)
	_hp_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail_box.add_child(_hp_host)
	var hp_bg := ColorRect.new()
	hp_bg.color = UiKit.LINE.darkened(0.45)
	hp_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_host.add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.86, 0.28, 0.34)
	_hp_fill.size = Vector2(0, 10)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_host.add_child(_hp_fill)

	_block_label = UiKit.label("格挡 0", UiKit.FS_XS, Color(0.31, 0.64, 0.88))
	_rail_box.add_child(_block_label)

	_energy_label = UiKit.label("能量 3/3", UiKit.FS_M, Color(0.31, 0.76, 0.97))
	_rail_box.add_child(_energy_label)

	_rail_box.add_child(UiKit.rule())

	_piles_label = UiKit.dim("抽牌堆 0 ｜ 弃牌堆 0", UiKit.FS_XS)
	_rail_box.add_child(_piles_label)
	_turn_label = UiKit.dim("回合 1", UiKit.FS_XS)
	_rail_box.add_child(_turn_label)

	_rail_box.add_child(UiKit.rule())
	var tip := UiKit.dim("点手牌打出 ｜ 右下结束回合\n能量每回合回满，格挡开回合清零。", UiKit.FS_XS)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rail_box.add_child(tip)


## 中上方：BAT 控制台（战斗日志）
func _build_console_area() -> void:
	var area := Control.new()
	area.name = "PromptArea"
	area.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(area)
	_console.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.add_child(_console)


## 右上敌人 HUD
func _build_right_hud() -> void:
	var right := VBoxContainer.new()
	right.name = "HudRight"
	right.add_theme_constant_override("separation", UiKit.SP_1)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)

	var head := UiKit.title_bar("敌人", SIDE_W, HORIZONTAL_ALIGNMENT_RIGHT, UiKit.TEXT_DIM)
	head.name = "RightTitle"
	right.add_child(head)

	_enemy_name_label = UiKit.label("", UiKit.FS_S, UiKit.TEXT)
	_enemy_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_enemy_name_label)

	_enemy_hp_label = UiKit.label("HP 0/0", UiKit.FS_XS, Color(0.95, 0.35, 0.4))
	_enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_enemy_hp_label)

	_enemy_hp_host = Control.new()
	_enemy_hp_host.custom_minimum_size = Vector2(SIDE_W, 10)
	_enemy_hp_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_enemy_hp_host)
	var ebg := ColorRect.new()
	ebg.color = UiKit.LINE.darkened(0.45)
	ebg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ebg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_hp_host.add_child(ebg)
	_enemy_fill = ColorRect.new()
	_enemy_fill.color = Color(0.86, 0.28, 0.34)
	_enemy_fill.size = Vector2(SIDE_W, 10)
	_enemy_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_hp_host.add_child(_enemy_fill)

	_enemy_block_label = UiKit.label("", UiKit.FS_XS, Color(0.31, 0.64, 0.88))
	_enemy_block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_enemy_block_label)

	_intent_label = UiKit.label("", UiKit.FS_S, UiKit.GOLD)
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_intent_label)


## 中下舞台：敌人像素形象（程序化）+ 意图气泡
func _build_stage() -> void:
	_enemy_root = Control.new()
	_enemy_root.name = "EnemyStage"
	_enemy_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_enemy_root)

	var intent_bubble := PanelContainer.new()
	intent_bubble.name = "IntentBubble"
	intent_bubble.add_theme_stylebox_override("panel",
			UiKit.flat(UiKit.PANEL_2, UiKit.GOLD, 2, UiKit.SP_2))
	intent_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_root.add_child(intent_bubble)

	_intent_label = UiKit.label("", UiKit.FS_XS, UiKit.GOLD)
	_intent_label.name = "IntentText"
	intent_bubble.add_child(_intent_label)

	var sprite_box := Control.new()
	sprite_box.name = "SpriteBox"
	sprite_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_root.add_child(sprite_box)

	_enemy_sprite = TextureRect.new()
	_enemy_sprite.name = "EnemySprite"
	_enemy_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_enemy_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_enemy_sprite.stretch_mode = TextureRect.STRETCH_SCALE
	_enemy_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite_box.add_child(_enemy_sprite)


## 底部：状态行 + 结束回合（右下）
func _build_bottom() -> void:
	var tip := VBoxContainer.new()
	tip.name = "BottomTip"
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tip)

	_status_label = UiKit.dim("", UiKit.FS_XS)
	_status_label.custom_minimum_size = Vector2(STATUS_W, 0)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_child(_status_label)

	var side := VBoxContainer.new()
	side.name = "BottomSide"
	side.alignment = BoxContainer.ALIGNMENT_END
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(side)

	_end_turn_button = UiKit.accent_button("结束回合", UiKit.FS_S)
	_end_turn_button.custom_minimum_size = Vector2(SIDE_W, 48)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	side.add_child(_end_turn_button)

	var piles := UiKit.dim("", UiKit.FS_XS)
	piles.name = "PileCounts"
	piles.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(piles)


func _build_companion() -> void:
	_companion = AiCompanion.new()
	_companion.name = "AiCompanion"
	add_child(_companion)
	if run != null:
		_companion.setup(run.ai)


func _build_fx() -> void:
	_fx_root = Control.new()
	_fx_root.name = "FxLayer"
	_fx_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_root)

	_fx_flash = ColorRect.new()
	_fx_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_flash.color = Color(1, 1, 1, 0)
	_fx_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_root.add_child(_fx_flash)

	_fx_enabled = DisplayServer.get_name() != "headless"


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
		tip.size = Vector2(STATUS_W, 40)

	var side := get_node_or_null("BottomSide") as Control
	if side:
		side.position = Vector2(W - PAD - SIDE_W, H - 120.0)
		side.size = Vector2(SIDE_W, 90)

	if _companion:
		var c_top := PAD + CONSOLE_H + UiKit.SP_4
		_companion.position = Vector2(W - PAD - SIDE_W, c_top)
		_companion.size = Vector2(SIDE_W, (H - 120.0) - c_top - 8.0)

	if _overlay:
		_overlay.position = Vector2(W * 0.5 - 280.0, H * 0.5 - 170.0)
		_overlay.size = Vector2(560, 340)

	# 敌人舞台：控制台下方、手牌上方之间的中央区域
	if _enemy_root:
		var stage_l := CONSOLE_X
		var stage_r := W - PAD - SIDE_W
		var cx := (stage_l + stage_r) * 0.5
		var bottom := minf(H - CARD_H - 92.0, STAGE_BOTTOM)
		_enemy_root.position = Vector2(cx - 90.0, bottom - 150.0)
		_enemy_root.size = Vector2(180.0, 150.0)
		if _enemy_sprite:
			var sc := 2.6 if level != null and level.is_boss else 2.0
			_enemy_sprite.size = Vector2(48.0, 56.0) * sc
			_enemy_sprite.position = Vector2(90.0 - _enemy_sprite.size.x * 0.5,
					150.0 - _enemy_sprite.size.y)
		var bubble := _enemy_root.get_node_or_null("IntentBubble") as Control
		if bubble:
			bubble.position = Vector2(180.0 - 96.0, 0.0)
			bubble.size = Vector2(96.0, 30.0)

	_layout_hand(false)


## 手牌槽位：横向一排、底边对齐
func _hand_slot(i: int, n: int) -> Dictionary:
	var left := CONSOLE_X
	var right := size.x - PAD - SIDE_W
	var avail := right - left
	var gap := HAND_GAP
	if n > 1:
		gap = clampf((avail - CARD_W * n) / float(n - 1), HAND_MIN_GAP, HAND_GAP)
	var total := CARD_W * n + gap * float(n - 1)
	var x := (left + right) * 0.5 - total * 0.5 + i * (CARD_W + gap)
	return {"pos": Vector2(x, size.y - HAND_BOTTOM - CARD_H)}


func _layout_hand(animate: bool = true) -> void:
	var n := _hand_views.size()
	for i in n:
		var view := _hand_views[i]
		var slot := _hand_slot(i, n)
		var target: Vector2 = slot["pos"]
		view.pivot_offset = Vector2(CARD_W * 0.5, CARD_H)
		if view == _hovered:
			target.y -= HOVER_LIFT
		if animate:
			var tw := _hand_tween(view)
			tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(view, "position", target, 0.18)
		else:
			view.position = target


## 造一张手牌位移动画，并顶掉旧动画
func _hand_tween(view: StsCardView) -> Tween:
	if view.has_meta("hand_tween"):
		var old: Tween = view.get_meta("hand_tween")
		if old != null and old.is_valid():
			old.kill()
	var tw := view.create_tween()
	view.set_meta("hand_tween", tw)
	return tw


# ─────────────────────────────────────────────────────────
#  战斗流程
# ─────────────────────────────────────────────────────────
func _start_battle() -> void:
	combat = run.start_battle(level)
	_console.set_prefix(_prefix())
	_console.clear()
	_console.append_line("%s · %s · %s" % [_prefix(), level.id, level.title], PromptConsole.DOS_GRAY)
	_console.append_line("遭遇【%s】！HP %d ｜ 攻 %d 防 %d" % [
		level.enemy_name, level.enemy_hp, level.enemy_atk, level.enemy_def], PromptConsole.DOS_GRAY)
	_console.append_line("点手牌出招（能量每回合回满）。", PromptConsole.DOS_GRAY)

	if _enemy_sprite:
		_enemy_sprite.texture = _enemy_texture(level.enemy_tint, level.is_boss)
		_enemy_sprite.modulate = Color.WHITE
		_enemy_sprite.visible = true
		_enemy_sprite.pivot_offset = _enemy_sprite.size * 0.5

	var head := _rail_box.get_node_or_null("RailTitle")
	if head != null:
		var ht := head.get_node_or_null("Text") as Label
		if ht != null:
			ht.text = "%s · %s" % [level.id, level.title]
	_brief_label.text = level.brief
	_enemy_name_label.text = level.enemy_name

	_rebuild_hand()
	_refresh_hud()

	# 进场转场（2D → 3D → 2D，主人 2026-10-26 钦定）。
	# 无头环境跳过动画直接开打（不拖慢冒烟测试）。
	if _fx_enabled:
		_play_intro()
	else:
		_status_label.text = "战斗开始！意图：%s" % _intent_text()


## 进场转场：手牌与敌人先藏起，3D 翻飞结束后 2D 弹入
func _play_intro() -> void:
	_busy = true
	_end_turn_button.disabled = true
	for v in _hand_views:
		v.scale = Vector2.ZERO
	_enemy_sprite.scale = Vector2.ZERO
	SfxNode.play("deal")

	# 终端式进场（2026-10-28 主人钦定）：全屏终端 → 敲代码 → 扫出角色字符画 → 进战斗。
	# 旧的 3D 转场保留在 --intro3d 开关后面，方便对比。
	if OS.get_cmdline_user_args().has("--intro3d"):
		var intro3d := BattleIntro.new()
		intro3d.name = "BattleIntro"
		add_child(intro3d)
		await get_tree().process_frame
		var card_texs: Array = []
		for v in _hand_views:
			card_texs.append(_card_full_texture(v.card))
		intro3d.play(card_texs, _enemy_sprite.texture, func() -> void: _reveal_from_intro())
		return

	await get_tree().process_frame
	var art_tex: Texture2D = null
	var ai_id := "agent"
	var ai_name := "Agent"
	if run != null and run.ai != null:
		ai_id = run.ai.id
		ai_name = run.ai.display_name
		# 优先用带透明底的切件（字符画背景才干净），没有再退回立绘
		# 主人指定：字符画统一用「设定图正面视图」那一套；没有才退回切件/立绘
		# 优先高清版（front-hi = 立绘原图 1114x1210）；front.png 是低清像素版，只做兜底
		var hi := "res://assets/art/rig/%s-front/front-hi.png" % ai_id
		var front := "res://assets/art/rig/%s-front/front.png" % ai_id
		var cut := "res://assets/art/rig/%s/cutout.png" % ai_id
		if ResourceLoader.exists(hi):
			art_tex = load(hi) as Texture2D
		elif ResourceLoader.exists(front):
			art_tex = load(front) as Texture2D
		elif ResourceLoader.exists(cut):
			art_tex = load(cut) as Texture2D
		elif run.ai.portrait_path != "" and ResourceLoader.exists(run.ai.portrait_path):
			art_tex = load(run.ai.portrait_path) as Texture2D
	# 终端演完之后：黑幕淡出，游戏画面「逐渐融入」（主人要求）
	var veil := ColorRect.new()
	veil.name = "IntroVeil"
	veil.color = Color(0, 0, 0, 1)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var on_done := func() -> void:
		_reveal_from_intro()
		var tw := create_tween()
		tw.tween_property(veil, "color:a", 0.0, 0.75).set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_OUT)
		tw.tween_callback(veil.queue_free)

	# 先试「真实系统终端」（主人钦定：要电脑本体的终端）；
	# --interm 强制游戏内版本，启动失败也自动回退。
	var use_ext := not OS.get_cmdline_user_args().has("--interm")
	if use_ext:
		var ext := ExtTerminal.new()
		ext.name = "ExtTerminal"
		add_child(ext)
		if ext.play(ai_id, ai_name, art_tex, on_done):
			return
		ext.queue_free()

	var term := TerminalIntro.new()
	term.name = "TerminalIntro"
	add_child(term)
	term.play(ai_id, ai_name, art_tex, on_done)


## 转场落回 2D：手牌错峰弹出、敌人砸落 + 震屏
func _reveal_from_intro() -> void:
	for i in _hand_views.size():
		var v := _hand_views[i]
		var tw := v.create_tween()
		tw.tween_property(v, "scale", Vector2.ONE, 0.30).set_delay(i * 0.05) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var base_pos := _enemy_sprite.position
	_enemy_sprite.position = base_pos - Vector2(0, 90)
	var tw := _enemy_sprite.create_tween()
	tw.tween_property(_enemy_sprite, "position", base_pos, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_enemy_sprite, "scale", Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		_shake(6.0, 0.14)
		_flash(Color(1.0, 0.5, 0.5), 0.14)
		SfxNode.play("hand_big"))
	await get_tree().create_timer(0.65).timeout
	_busy = false
	_end_turn_button.disabled = false
	_status_label.text = "战斗开始！意图：%s" % _intent_text()


## 合成整卡贴图（框 + 立绘）给 3D 转场用；按卡 id 缓存
## 卡框素材 750x1130 = 游戏内 150x226 的 5 倍，画窗坐标按这个倍数换算
const FRAME_SCALE := 5
var _card_tex_cache: Dictionary = {}


## 等比「cover」：先放缩到铺满 target，再居中裁切（不拉伸变形）
func _fit_cover(img: Image, target: Vector2i) -> Image:
	var s := maxf(float(target.x) / float(img.get_width()),
			float(target.y) / float(img.get_height()))
	img.resize(maxi(1, roundi(float(img.get_width()) * s)),
			maxi(1, roundi(float(img.get_height()) * s)))
	var x := (img.get_width() - target.x) / 2
	var y := (img.get_height() - target.y) / 2
	return img.get_region(Rect2i(x, y, target.x, target.y))

func _card_full_texture(card: StsCard) -> ImageTexture:
	if _card_tex_cache.has(card.id):
		return _card_tex_cache[card.id]
	var frame_path := String(StsCardView.FRAME_PATHS.get(card.kind,
			StsCardView.FRAME_PATHS[StsCard.Kind.ATTACK]))
	var img: Image = null
	if ResourceLoader.exists(frame_path):
		var ft: Resource = load(frame_path)
		if ft is Texture2D:
			img = (ft as Texture2D).get_image()
	if img == null:
		img = Image.create_empty(750, 1130, false, Image.FORMAT_RGBA8)
		img.fill(UiKit.PANEL)
	# 框图导入后可能是 RGB8、立绘是 RGBA8——blit_rect 要求同格式，先统一转 RGBA8
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if card.art_path != "" and ResourceLoader.exists(card.art_path):
		var at: Resource = load(card.art_path)
		if at is Texture2D:
			var art := (at as Texture2D).get_image()
			if art.get_format() != Image.FORMAT_RGBA8:
				art.convert(Image.FORMAT_RGBA8)
			# 画窗：与 2D 卡面共用 StsCardView.ART_RECT（显示坐标），换算到 750x1130 原生分辨率。
			# 原来是 0,130 + 750x700（铺满全宽），立绘会压出框边。
			var win := Rect2i(
					int(StsCardView.ART_RECT.position.x) * FRAME_SCALE,
					int(StsCardView.ART_RECT.position.y) * FRAME_SCALE,
					int(StsCardView.ART_RECT.size.x) * FRAME_SCALE,
					int(StsCardView.ART_RECT.size.y) * FRAME_SCALE)
			art = _fit_cover(art, win.size)
			img.blit_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), win.position)
	var tex := ImageTexture.create_from_image(img)
	_card_tex_cache[card.id] = tex
	return tex


func _prefix() -> String:
	if run != null and run.ai != null:
		return run.ai.id
	return "player"


## 意图文字（右上 HUD 与舞台气泡共用）
func _intent_text() -> String:
	if combat == null or combat.intent.is_empty():
		return "？"
	var v := int(combat.intent.get("value", 0))
	if String(combat.intent.get("kind", "")) == "attack":
		return "意图：攻击 %d" % v
	return "意图：防御 %d" % v


func _rebuild_hand() -> void:
	for view in _hand_views:
		view.queue_free()
	_hand_views.clear()
	if combat == null:
		return
	for c in combat.hand:
		var v := StsCardView.new()
		v.setup(c)
		v.clicked.connect(_on_card_clicked)
		v.mouse_entered.connect(_on_hand_hover.bind(v, true))
		v.mouse_exited.connect(_on_hand_hover.bind(v, false))
		_card_layer.add_child(v)
		_hand_views.append(v)
	_layout_hand(false)
	_refresh_playable()


func _refresh_playable() -> void:
	for v in _hand_views:
		if v != null and v.card != null:
			v.set_playable(combat != null and combat.can_play(v.card))


func _refresh_hud() -> void:
	if combat == null:
		return
	_hp_label.text = "HP %d/%d" % [combat.hp, combat.max_hp]
	var ratio := clampf(float(combat.hp) / float(maxi(1, combat.max_hp)), 0.0, 1.0)
	var avail := _hp_host.size.x
	if avail < 4.0:
		avail = RAIL_W - UiKit.PANEL_PAD * 2.0
	_hp_fill.size = Vector2(avail * ratio, 10.0)
	_block_label.text = "格挡 %d" % combat.block
	_energy_label.text = "能量 %d/%d" % [combat.energy, StsCombat.ENERGY_MAX]
	_piles_label.text = "抽牌堆 %d ｜ 弃牌堆 %d" % [combat.draw_pile.size(), combat.discard_pile.size()]
	_turn_label.text = "回合 %d" % combat.turn

	_enemy_hp_label.text = "HP %d/%d" % [combat.enemy_hp, combat.enemy_max_hp]
	var er := clampf(float(combat.enemy_hp) / float(maxi(1, combat.enemy_max_hp)), 0.0, 1.0)
	_enemy_fill.size = Vector2(SIDE_W * er, 10.0)
	_enemy_block_label.text = "格挡 %d" % combat.enemy_block if combat.enemy_block > 0 else ""
	_intent_label.text = _intent_text()
	var piles := get_node_or_null("BottomSide/PileCounts") as Label
	if piles != null:
		piles.text = "抽 %d ｜ 弃 %d" % [combat.draw_pile.size(), combat.discard_pile.size()]


func _on_hand_hover(view: StsCardView, entered: bool) -> void:
	if _busy or _overlay.visible:
		return
	if entered:
		if _hovered == view:
			return
		_hovered = view
	else:
		if _hovered != view:
			return
		_hovered = null
	_layout_hand(true)


# ─────────────────────────────────────────────────────────
#  出牌
# ─────────────────────────────────────────────────────────
func _on_card_clicked(view: StsCardView) -> void:
	if _busy or _overlay.visible or combat == null:
		return
	var card := view.card
	if card == null or not combat.can_play(card):
		if card != null and combat.hand.has(card):
			_status_label.text = "能量不够啦，先结束回合吧。"
		return
	_busy = true
	view.flash()
	SfxNode.play("card_select")
	_console.finish_all()
	_console.type_in(StsCardPool.card_name(card.id))

	var ev := combat.play_card(card)
	# 从视图层移除这张牌
	for i in range(_hand_views.size() - 1, -1, -1):
		if _hand_views[i] == view:
			_hand_views.remove_at(i)
			break

	if _fx_enabled:
		await _play_card_fx(view, card, ev)
	view.queue_free()

	_refresh_hud()
	_layout_hand(true)
	_refresh_playable()

	if bool(ev.get("ok", false)):
		if String(ev.get("kind", "")) == "attack":
			_console.append_line("→ %s！%s 受到 %d 点伤害（剩余 %d）" % [
				StsCardPool.card_name(card.id), level.enemy_name,
				int(ev.get("value", 0)), combat.enemy_hp], PromptConsole.DOS_AMBER)
		else:
			_console.append_line("→ %s！获得 %d 点格挡" % [
				StsCardPool.card_name(card.id), int(ev.get("value", 0))], PromptConsole.DOS_CYAN)

	if combat.over == StsCombat.Result.WIN:
		await get_tree().create_timer(0.5).timeout
		_finish_battle(true)
		return
	_busy = false


## 出牌动画：攻击 → 牌飞向敌人 + 敌人闪红震屏 + 伤害飘字；防御 → 牌飞向左下 + 格挡飘字
func _play_card_fx(view: StsCardView, card: StsCard, ev: Dictionary) -> void:
	var is_attack := String(ev.get("kind", "")) == "attack"
	var dest: Vector2
	if is_attack:
		dest = _enemy_root.position + _enemy_root.size * 0.5 - Vector2(CARD_W, CARD_H) * 0.35
	else:
		dest = Vector2(CONSOLE_X + 60.0, size.y - 140.0)
	var tw := view.create_tween()
	tw.set_parallel(true)
	tw.tween_property(view, "position", dest, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(view, "scale", Vector2(0.6, 0.6), 0.22)
	tw.tween_property(view, "modulate:a", 0.0, 0.20).set_delay(0.08)
	await tw.finished

	if is_attack:
		_enemy_hit_fx(int(ev.get("value", 0)))
		SfxNode.play("hand_big")
	else:
		_float_text(Vector2(PAD + RAIL_W * 0.5, size.y - CARD_H - 70.0),
				"+%d 格挡" % int(ev.get("value", 0)), Color(0.31, 0.64, 0.88), UiKit.FS_M)
		SfxNode.play("hand_small")


## 敌人受击：闪红 + 抖动 + 头顶飘伤害数字
func _enemy_hit_fx(dmg: int) -> void:
	if _enemy_sprite == null:
		return
	_flash(Color(1.0, 0.45, 0.45), 0.16)
	var tw := _enemy_sprite.create_tween()
	tw.tween_property(_enemy_sprite, "modulate", Color(2.2, 0.8, 0.8), 0.05)
	tw.tween_property(_enemy_sprite, "modulate", Color.WHITE, 0.18)
	var shake := _enemy_root.create_tween()
	for i in 4:
		var off := Vector2(randf_range(-7, 7), randf_range(-4, 4)) * (1.0 - float(i) / 4.0)
		shake.tween_callback(func() -> void:
			_enemy_sprite.position = Vector2(90.0 - _enemy_sprite.size.x * 0.5,
					150.0 - _enemy_sprite.size.y) + off)
		shake.tween_interval(0.03)
	shake.tween_callback(func() -> void:
		_enemy_sprite.position = Vector2(90.0 - _enemy_sprite.size.x * 0.5,
				150.0 - _enemy_sprite.size.y))
	_float_text(_enemy_root.position + Vector2(_enemy_root.size.x * 0.5, 24.0),
			"-%d" % dmg, Color(1.0, 0.42, 0.42), UiKit.FS_L)


# ─────────────────────────────────────────────────────────
#  结束回合（敌人行动）
# ─────────────────────────────────────────────────────────
func _on_end_turn_pressed() -> void:
	if _busy or _overlay.visible or combat == null:
		return
	_busy = true
	_end_turn_button.disabled = true
	_console.finish_all()
	_console.append_line("— 结束回合 —", PromptConsole.DOS_GRAY)

	if _fx_enabled:
		await get_tree().create_timer(0.25).timeout

	var events := combat.end_turn()
	for e in events:
		var kind := String(e.get("kind", ""))
		if kind == "enemy_attack":
			if _fx_enabled:
				await _enemy_attack_fx(int(e.get("value", 0)), int(e.get("dealt", 0)),
						int(e.get("blocked", 0)))
			_console.append_line("← %s 攻击 %d！%s" % [
				level.enemy_name, int(e.get("value", 0)),
				"被格挡吸收" if int(e.get("dealt", 0)) <= 0 else "掉血 %d（HP %d）" % [
					int(e.get("dealt", 0)), combat.hp]], PromptConsole.DOS_RED)
		elif kind == "enemy_defend":
			_console.append_line("← %s 蓄力防御，格挡 +%d" % [
				level.enemy_name, int(e.get("value", 0))], PromptConsole.DOS_CYAN)
			if _fx_enabled:
				_float_text(_enemy_root.position + Vector2(_enemy_root.size.x * 0.5, 44.0),
						"+%d 防" % int(e.get("value", 0)), Color(0.31, 0.64, 0.88), UiKit.FS_M)
				await get_tree().create_timer(0.3).timeout

	_refresh_hud()
	_rebuild_hand()

	if combat.over == StsCombat.Result.LOSE:
		await get_tree().create_timer(0.4).timeout
		_finish_battle(false)
		return

	_busy = false
	_end_turn_button.disabled = false
	_status_label.text = "新回合：%s" % _intent_text()
	SfxNode.play("deal")


## 敌人攻击动画：往前顶一下 + 玩家侧震屏 + 受伤飘字
func _enemy_attack_fx(raw: int, dealt: int, blocked: int) -> void:
	if _enemy_root == null:
		return
	var base_y := _enemy_root.position.y
	var lunge := _enemy_root.create_tween()
	lunge.tween_property(_enemy_root, "position:y", base_y + 26.0, 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	lunge.tween_property(_enemy_root, "position:y", base_y, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.12).timeout
	if blocked > 0 and dealt <= 0:
		_float_text(Vector2(size.x * 0.5 - 40.0, size.y - CARD_H - 80.0),
				"格挡！-%d" % blocked, Color(0.31, 0.64, 0.88), UiKit.FS_M)
		SfxNode.play("hand_small")
	else:
		_flash(Color(1.0, 0.3, 0.3), 0.18)
		_shake(7.0, 0.16)
		if dealt > 0:
			_float_text(Vector2(size.x * 0.5 - 40.0, size.y - CARD_H - 80.0),
					"-%d HP" % dealt, Color(1.0, 0.42, 0.42), UiKit.FS_L)
			SfxNode.play("score_land")
	await get_tree().create_timer(0.25).timeout


# ─────────────────────────────────────────────────────────
#  结算
# ─────────────────────────────────────────────────────────
func _finish_battle(win: bool) -> void:
	_busy = false
	if win:
		SfxNode.play("win")
		var gain := run.win_battle(combat, level)
		_overlay_title.text = "胜利"
		_overlay_body.text = "击败【%s】！\n本战造成 %d 伤害 ｜ 剩余 HP %d（回复 %d）\n算力 +%d ｜ 下一步：往卡组里加一张牌。" % [
			level.enemy_name, combat.damage_dealt, run.hp,
			StsCombat.HEAL_ON_WIN, gain]
		_pop_overlay()
		level_cleared.emit(run.score)
	else:
		SfxNode.play("lose")
		run.lose_battle(combat)
		_overlay_title.text = "战败"
		_overlay_body.text = "被【%s】打倒了（HP %d/%d）。\n提示：防御牌能挡下攻击——\n看准敌人的「攻击 N」意图再开防。" % [
			level.enemy_name, combat.hp, combat.max_hp]
		_pop_overlay()
		level_failed.emit(run.score)


func _pop_overlay() -> void:
	if _overlay == null:
		return
	_overlay.visible = true
	if not _fx_enabled:
		return
	_overlay.pivot_offset = _overlay.size * 0.5
	_overlay.scale = Vector2(0.92, 0.92)
	_overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_overlay, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.16)


func _on_overlay_continue() -> void:
	_overlay.visible = false
	advance_requested.emit()


# ─────────────────────────────────────────────────────────
#  通用特效
# ─────────────────────────────────────────────────────────
func _flash(color: Color, dur: float) -> void:
	if _fx_flash == null:
		return
	_fx_flash.color = Color(color.r, color.g, color.b, 0.28)
	var tw := create_tween()
	tw.tween_property(_fx_flash, "color:a", 0.0, maxf(0.10, dur))


func _shake(amp: float, dur: float) -> void:
	if _card_layer == null:
		return
	var steps := 5
	var tw := create_tween()
	for i in steps:
		var k := 1.0 - float(i) / float(steps)
		var off := Vector2(randf_range(-amp, amp), randf_range(-amp, amp)) * k
		tw.tween_callback(func() -> void: _card_layer.position = off).set_delay(dur / float(steps))
	tw.tween_callback(func() -> void: _card_layer.position = Vector2.ZERO)


## 飘字：在 pos 弹出 → 上飘渐隐
func _float_text(pos: Vector2, text: String, color: Color, fs: int) -> void:
	if _fx_root == null:
		return
	var l := UiKit.label(text, fs, color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_root.add_child(l)
	l.pivot_offset = l.get_minimum_size() * 0.5
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y - 42.0, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.30).set_delay(0.30)
	tw.chain().tween_callback(func() -> void: l.queue_free())


## 程序化敌人像素形象：48×56 小怪（圆身、红眼、獠牙、小角；BOSS 戴皇冠）
func _enemy_texture(tint: Color, boss: bool) -> ImageTexture:
	var img := Image.create_empty(48, 56, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark := tint.darkened(0.55)
	var mid := tint.darkened(0.25)
	# 角
	for i in 3:
		_rect(img, 10 + i * 3, 8 - i, 3, 3, mid, dark)
		_rect(img, 35 - i * 3, 8 - i, 3, 3, mid, dark)
	# 身体
	for y in range(10, 50):
		var w := 34 + (10 - absi(y - 30) if absi(y - 30) < 10 else 0)
		_rect(img, 24 - w / 2, y, w, 1, tint if y < 34 else mid, dark, false)
	_rect(img, 5, 48, 38, 3, dark, Color(0, 0, 0, 0), false)
	# BOSS 皇冠
	if boss:
		var gold := Color(1.0, 0.82, 0.4)
		_rect(img, 16, 4, 16, 5, gold, gold.darkened(0.4))
		_rect(img, 17, 2, 2, 3, gold, Color(0, 0, 0, 0), false)
		_rect(img, 23, 1, 2, 4, gold, Color(0, 0, 0, 0), false)
		_rect(img, 29, 2, 2, 3, gold, Color(0, 0, 0, 0), false)
	# 眼睛（红底黑瞳）
	_rect(img, 13, 20, 8, 8, Color(0.98, 0.9, 0.85), dark)
	_rect(img, 27, 20, 8, 8, Color(0.98, 0.9, 0.85), dark)
	_rect(img, 15, 23, 4, 4, Color(0.85, 0.12, 0.15), Color(0, 0, 0, 0), false)
	_rect(img, 29, 23, 4, 4, Color(0.85, 0.12, 0.15), Color(0, 0, 0, 0), false)
	# 獠牙嘴
	_rect(img, 15, 36, 18, 4, dark, Color(0, 0, 0, 0), false)
	_rect(img, 16, 40, 3, 4, Color(0.98, 0.9, 0.85), Color(0, 0, 0, 0), false)
	_rect(img, 23, 40, 3, 4, Color(0.98, 0.9, 0.85), Color(0, 0, 0, 0), false)
	_rect(img, 30, 40, 3, 4, Color(0.98, 0.9, 0.85), Color(0, 0, 0, 0), false)
	# 小手
	_rect(img, 2, 28, 5, 10, mid, dark)
	_rect(img, 41, 28, 5, 10, mid, dark)
	return ImageTexture.create_from_image(img)


func _rect(img: Image, x: int, y: int, w: int, h: int, col: Color,
		outline: Color, do_outline: bool = true) -> void:
	var r := Rect2i(x, y, w, h)
	if r.size.x <= 0 or r.size.y <= 0:
		return
	img.fill_rect(r, col)
	if not do_outline or outline.a <= 0.0:
		return
	img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 1), outline)
	img.fill_rect(Rect2i(r.position.x, r.position.y + r.size.y - 1, r.size.x, 1), outline)
	img.fill_rect(Rect2i(r.position.x, r.position.y, 1, r.size.y), outline)
	img.fill_rect(Rect2i(r.position.x + r.size.x - 1, r.position.y, 1, r.size.y), outline)


# ─────────────────────────────────────────────────────────
#  测试钩子
# ─────────────────────────────────────────────────────────
func debug_play_card(index: int) -> bool:
	if index < 0 or index >= _hand_views.size():
		return false
	var v := _hand_views[index]
	var before := combat.hand.size()
	_on_card_clicked(v)
	return combat.hand.size() < before


func debug_play_card_id(card_id: String) -> bool:
	for v in _hand_views:
		if v != null and v.card != null and v.card.id == card_id:
			return debug_play_card(_hand_views.find(v))
	return false


func debug_end_turn() -> void:
	_on_end_turn_pressed()


func debug_hand_count() -> int:
	return _hand_views.size()


func debug_energy() -> int:
	return combat.energy if combat != null else -1


func debug_combat_state() -> Dictionary:
	if combat == null:
		return {}
	return {
		"hp": combat.hp, "block": combat.block,
		"enemy_hp": combat.enemy_hp, "enemy_block": combat.enemy_block,
		"energy": combat.energy, "turn": combat.turn,
		"over": combat.over, "hand": combat.hand.size(),
		"draw": combat.draw_pile.size(), "discard": combat.discard_pile.size(),
	}


func debug_overlay_visible() -> bool:
	return _overlay.visible


func debug_click_continue() -> void:
	_on_overlay_continue()


func debug_status_text() -> String:
	return _status_label.text if _status_label != null else ""


func debug_console_log() -> String:
	return _console.get_log() if _console != null else ""
