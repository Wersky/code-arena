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
##   下方       对话框内：手牌横排（点击打出）+ 操作键行（弃牌/结束回合/发送）
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
## 左侧边栏拉满上下、底部对话框、战斗画面在上方 —— 与启动界面同一套架构（主人 2026-10-30）
const RAIL_W := 230.0
const DIALOG_X := 280.0     ## 对话框左缘：让开左侧栏（24..256），留 24 缝隙
const DIALOG_W := 880.0     ## 对话框宽：止于 1160，AI 娘在它右侧不被盖住
## 底部输入条：参考 ZCode 输入框 —— 窄（96 高）、长（880 宽）、两行
## 上行提示文案，下行控件 + 发送；**下缘与左侧栏下缘齐平**（都到 900）
const DIALOG_H := 96.0
const DIALOG_Y := 900.0 - DIALOG_H
const AI_X := 1170.0        ## AI 娘左缘：对话框右侧外侧（不压对话框）
const ENEMY_W := 440.0      ## 敌人 HUD 宽
const DISCARD_LIMIT_PER_TURN := 3   ## 每回合主动弃牌上限（弃 1 抽 1，也算 1 次）
const CONSOLE_H := 300.0

# ── 手牌横排参数 ───────────────────────────────────────
const HAND_GAP := 10.0
const HAND_MIN_GAP := -34.0
const HOVER_LIFT := 30.0

# ── 敌人舞台 ───────────────────────────────────────────
const STAGE_TOP := 40.0
const STAGE_BOTTOM := 540.0

# ── 进场立绘（终端 → 战斗的衔接点）────────────────────
const HERO_HOLD := 0.45         ## 进度条满之后的停顿（然后揭幕进战斗）
const HERO_FADE_OUT := 0.45     ## 淡出时长
const MOSAIC_SHADER := preload("res://shaders/mosaic.gdshader")
const MOSAIC_CELLS := 1.0       ## 起始马赛克块 = 终端一个字符格 × 这个倍数（1.0 = 与符号格严丝合缝）
const MOSAIC_TIME := 1.4        ## 马赛克 → 清晰的时长
const COLOR_IN := 2.2           ## 彩色盖住符号的时长（主人要求「尽量拉长」，原来 0.55 太快看不见上色）
const SYMBOL_HOLD := 0.35       ## 第一帧保留终端画面的时长（主人：第一帧就是终端那张）
const SYMBOL_DECODE := 0.9      ## 符号随机解码时长：每个符号闪成别的符号，再逐格定稿

var _mosaic_warm: TextureRect = null   ## 预热用的隐藏立绘（见 _prewarm_mosaic_shader）
var _hero_tween: Tween = null          ## 衔接动画的句柄（--shot=hero 自检要 pause 它拍首帧）

var run: RunState = null
var level: LevelData = null
var combat: StsCombat = null

var _card_layer: Control = null
var _hand_views: Array[StsCardView] = []
var _busy: bool = false
var _hovered: StsCardView = null

# 左侧竖栏（玩家状态）
var _rail: PanelContainer = null
var _rail_box: VBoxContainer = null

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
var _dialog: PanelContainer = null   ## 底部对话框底板（手牌 + 操作按钮都放它上面）

# AI 娘
var _companion: AiCompanion = null
var _discard_mode := false
var _discard_btn: Button = null
var _rice_label: Label = null
var _send_btn: Button = null
var _discards_left := DISCARD_LIMIT_PER_TURN

# 特效层
var _fx_enabled := true
var _fx_root: Control = null
var _fx_flash: ColorRect = null
## 观察者反应（E）：最近一条（落到状态栏显示，debug_console_log 读取）
var _observer_note := ""

# 覆盖层（结算弹窗）
var _overlay: PanelContainer = null
var _overlay_title: Label = null
var _overlay_body: Label = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(run_state: RunState, lv: LevelData) -> void:
	run = run_state
	level = lv


func _ready() -> void:
	# 全程同一首（主人 2026-10-30：进战斗也用 bgm_gemini2，不切曲）
	SfxNode.music("bgm_gemini2")
	_build_ui()
	resized.connect(_layout)
	await get_tree().process_frame
	_layout()
	_start_battle()


# ─────────────────────────────────────────────────────────
#  UI 构建
# ─────────────────────────────────────────────────────────
func _build_ui() -> void:
	# 沿用初始化界面的设定：背景全黑（去掉蓝色背景图、暗化层与粒子层，主人要求简洁）
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_build_rail()
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
	# 沿用初始化界面的侧边栏：暗底 + 细蓝边，内容是当前模型的技能与 MCP
	var rail_sb := StyleBoxFlat.new()
	rail_sb.bg_color = Color(0.045, 0.06, 0.10)
	rail_sb.border_color = Color(0.20, 0.28, 0.45)
	rail_sb.set_border_width_all(2)
	rail_sb.content_margin_left = 14.0
	rail_sb.content_margin_right = 14.0
	rail_sb.content_margin_top = 14.0
	rail_sb.content_margin_bottom = 14.0
	_rail.add_theme_stylebox_override("panel", rail_sb)
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rail)

	_rail_box = VBoxContainer.new()
	_rail_box.name = "RailBox"
	_rail_box.add_theme_constant_override("separation", 8)
	_rail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.add_child(_rail_box)

	var ai_name := run.ai.display_name if run.ai != null else "AI"
	_rail_box.add_child(UiKit.title_bar(ai_name, 0.0, HORIZONTAL_ALIGNMENT_LEFT, UiKit.TEXT))
	_rail_box.add_child(UiKit.rule())

	_rail_box.add_child(UiKit.label("▸ 技能", UiKit.FS_S, Color(0.6, 0.85, 1.0)))
	if run.ai != null:
		for sk in run.ai.taste_rules:
			_rail_box.add_child(UiKit.dim("  · " + sk, UiKit.FS_XS))

	_rail_box.add_child(UiKit.rule())
	_rail_box.add_child(UiKit.label("▸ MCP", UiKit.FS_S, Color(0.6, 0.85, 1.0)))
	for item in LaunchScreen.MCP_ITEMS:
		_rail_box.add_child(UiKit.dim("  · " + item, UiKit.FS_XS))


## 右上敌人 HUD
func _build_right_hud() -> void:
	var right := VBoxContainer.new()
	right.name = "HudRight"
	right.add_theme_constant_override("separation", UiKit.SP_1)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)

	var head := UiKit.title_bar("敌人", ENEMY_W, HORIZONTAL_ALIGNMENT_RIGHT, UiKit.TEXT_DIM)
	head.name = "RightTitle"
	right.add_child(head)

	_enemy_name_label = UiKit.label("", UiKit.FS_S, UiKit.TEXT)
	_enemy_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_enemy_name_label)

	_enemy_hp_label = UiKit.label("HP 0/0", UiKit.FS_XS, Color(0.95, 0.35, 0.4))
	_enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_enemy_hp_label)

	_enemy_hp_host = Control.new()
	_enemy_hp_host.custom_minimum_size = Vector2(ENEMY_W, 10)
	_enemy_hp_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_enemy_hp_host)
	var ebg := ColorRect.new()
	ebg.color = UiKit.LINE.darkened(0.45)
	ebg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ebg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_hp_host.add_child(ebg)
	_enemy_fill = ColorRect.new()
	_enemy_fill.color = Color(0.86, 0.28, 0.34)
	_enemy_fill.size = Vector2(ENEMY_W, 10)
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


## 底部：手牌 + 操作按钮，全部收进一块对话框里
## （沿用初始化界面 AgentDialog 的样子：底板 + 一行操作键；主人 2026-10-30 要求右侧那排挪下来）
func _build_bottom() -> void:
	# 底部输入条：参考 ZCode 输入框的窄长造型，沿用初始化界面的配色
	_dialog = UiKit.panel_box(Color(0.055, 0.075, 0.12), Color(0.22, 0.32, 0.5), 10)
	_dialog.name = "ActionDialog"
	_dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 尺寸钉死：PanelContainer 会按内容最小尺寸回写，不设最小尺寸就钉不住下缘
	_dialog.custom_minimum_size = Vector2(DIALOG_W, DIALOG_H)
	add_child(_dialog)

	var box := VBoxContainer.new()
	box.name = "DialogBox"
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(box)

	# 上行：提示文案（对应参考图里的 placeholder 行）
	_status_label = UiKit.dim("", UiKit.FS_XS)
	_status_label.custom_minimum_size = Vector2(0, 18)
	_status_label.clip_text = true
	box.add_child(_status_label)

	# 下行：控件 + 发送（发送在最右）
	var side := HBoxContainer.new()
	side.name = "BottomSide"
	side.alignment = BoxContainer.ALIGNMENT_BEGIN
	side.add_theme_constant_override("separation", 10)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(side)

	_discard_btn = UiKit.accent_button("弃牌模式", UiKit.FS_XS)
	_discard_btn.toggle_mode = true
	_discard_btn.custom_minimum_size = Vector2(140, 36)
	_discard_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_discard_btn.toggled.connect(_on_discard_toggled)
	side.add_child(_discard_btn)

	var piles := UiKit.dim("", UiKit.FS_XS)
	piles.name = "PileCounts"
	piles.custom_minimum_size = Vector2(96, 0)
	piles.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	piles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	side.add_child(piles)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(gap)

	_end_turn_button = UiKit.accent_button("结束回合", UiKit.FS_XS)
	_end_turn_button.custom_minimum_size = Vector2(150, 36)
	_end_turn_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	side.add_child(_end_turn_button)

	_send_btn = UiKit.accent_button("发 送", UiKit.FS_S)
	_send_btn.custom_minimum_size = Vector2(160, 40)
	_send_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_send_btn.pressed.connect(_on_send_pressed)
	side.add_child(_send_btn)


func _build_companion() -> void:
	_companion = AiCompanion.new()
	_companion.name = "AiCompanion"
	add_child(_companion)
	if run != null:
		_companion.setup(run.ai)
	_rice_label = UiKit.label("白米饭 0/2", UiKit.FS_XS, Color(1.0, 0.9, 0.55))
	_rice_label.name = "RiceLabel"
	_rice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rice_label)


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

	# 侧边栏：沿用初始化设定，拉满上下
	var rail := get_node_or_null("HudLeft") as Control
	if rail:
		rail.position = Vector2(24.0, 0.0)
		rail.size = Vector2(232.0, H)

	# 底部对话框：手牌与操作键都收进来（Agent 对话软件的样子）
	var dlg := get_node_or_null("ActionDialog") as Control
	if dlg:
		# 底边对齐侧栏底边（都在 H）：用 H - DIALOG_H 定位，而不是写死常量
		dlg.position = Vector2(DIALOG_X, H - DIALOG_H)
		dlg.size = Vector2(DIALOG_W, DIALOG_H)

	var area := get_node_or_null("PromptArea") as Control
	if area:
		area.position = Vector2(DIALOG_X, DIALOG_Y)
		area.size = Vector2(DIALOG_W, DIALOG_H)

	# 敌人 HUD：战斗画面右上
	var right := get_node_or_null("HudRight") as Control
	if right:
		right.position = Vector2(W - ENEMY_W - PAD, PAD)
		right.size = Vector2(ENEMY_W, 150.0)

	# 状态提示：战斗画面左上




	# AI 娘：对话框右端里侧（手绘稿红框位置）
	if _companion:
		_companion.position = Vector2(AI_X, H - 324.0)
		_companion.size = Vector2(W - AI_X - PAD, 304.0)
	if _rice_label:
		_rice_label.position = Vector2(AI_X + 8.0, H - 350.0)
		_rice_label.size = Vector2(W - AI_X - PAD - 8.0, 24.0)

	if _overlay:
		_overlay.position = Vector2(W * 0.5 - 280.0, H * 0.5 - 170.0)
		_overlay.size = Vector2(560, 340)

	# 敌人舞台：对话框上方、状态栏下方的中央
	if _enemy_root:
		var cx := (DIALOG_X + AI_X) * 0.5
		var bottom := minf(H - CARD_H - 40.0, STAGE_BOTTOM)
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


## 手牌槽位：横排、贴在对话框上沿内侧，底边与按钮行留出间距
func _hand_slot(i: int, n: int) -> Dictionary:
	var left := DIALOG_X + 10.0
	var right := AI_X - 12.0
	var avail := right - left
	var gap := HAND_GAP
	if n > 1:
		gap = clampf((avail - CARD_W * n) / float(n - 1), HAND_MIN_GAP, HAND_GAP)
	var total := CARD_W * n + gap * float(n - 1)
	var x := (left + right) * 0.5 - total * 0.5 + i * (CARD_W + gap)
	return {"pos": Vector2(x, DIALOG_Y - 12.0 - CARD_H)}


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
			tw.set_parallel(true)
			# **必须连 scale 一起归一**：补进来的新牌是从 0.7 起手的，
			# 只补 position 的话 scale 永远停在 0.7 —— 表现就是「点了发送牌变小」
			tw.tween_property(view, "scale", Vector2.ONE, 0.18)
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
	combat.set_refill(StsCombat.refill_for(run.ai.id))

	if _enemy_sprite:
		var art_path := "res://assets/art/enemy-%s.png" % level.id
		if ResourceLoader.exists(art_path):
			_enemy_sprite.texture = load(art_path)
			_enemy_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		else:
			_enemy_sprite.texture = _enemy_texture(level.enemy_tint, level.is_boss)
		_enemy_sprite.modulate = Color.WHITE
		_enemy_sprite.visible = true
		_enemy_sprite.pivot_offset = _enemy_sprite.size * 0.5
		# 呼吸动效（2026-10-31 主人钦定）：敌人也轻轻起伏
		var breath := _enemy_sprite.create_tween().set_loops()
		breath.tween_property(_enemy_sprite, "scale:y", 1.04, 1.6) 				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		breath.tween_property(_enemy_sprite, "scale:y", 1.0, 1.6) 				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var head := _rail_box.get_node_or_null("RailTitle")
	if head != null:
		var ht := head.get_node_or_null("Text") as Label
		if ht != null:
			ht.text = "%s · %s" % [level.id, level.title]
	_status_label.text = level.brief
	_update_rice_hud()
	_enemy_name_label.text = level.enemy_name

	_rebuild_hand()
	_refresh_hud()

	# 进场转场：仅开始游戏后的第一场战斗播（2026-10-31 主人钦定：
	# 每场战斗打完不再进终端/加载，直接开打）。无头环境跳过。
	if _fx_enabled and run != null and not run.intro_played:
		run.intro_played = true
		_play_intro()
	else:
		_status_label.text = "战斗开始！意图：%s" % _intent_text()


## 进场转场：手牌与敌人先藏起，3D 翻飞结束后 2D 弹入
func _play_intro() -> void:
	# --nointro：跳过整个进场（只给 --shot=hero 这类定点验收用）
	if OS.get_cmdline_user_args().has("--nointro"):
		return
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
		# 主人钦定：用这张高清立绘（front-hi = 从"蓝发女仆的挑衅邀战"抠出的 1114x1210）
		if ResourceLoader.exists(hi):
			art_tex = load(hi) as Texture2D
		elif ResourceLoader.exists(front):
			art_tex = load(front) as Texture2D
		elif ResourceLoader.exists(cut):
			art_tex = load(cut) as Texture2D
		elif run.ai.portrait_path != "" and ResourceLoader.exists(run.ai.portrait_path):
			art_tex = load(run.ai.portrait_path) as Texture2D
	# 预热马赛克着色器（必须放在黑幕之前：黑幕会盖住它）
	_prewarm_mosaic_shader(art_tex)
	# 终端演完之后：黑幕淡出，游戏画面「逐渐融入」（主人要求）
	var veil := ColorRect.new()
	veil.name = "IntroVeil"
	veil.color = Color(0, 0, 0, 1)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var on_done := func() -> void:
		# 终端关掉后：把这张立绘**原分辨率全屏淡入**（终端只有 179x54 格，画不出五官，
		# 但游戏窗口可以 1:1 显示），再淡出进战斗。
		_show_hero_portrait(art_tex, func() -> void:
			_reveal_from_intro()
			var tw := create_tween()
			tw.tween_property(veil, "color:a", 0.0, 0.75).set_trans(Tween.TRANS_SINE) \
				.set_ease(Tween.EASE_OUT)
			tw.tween_callback(veil.queue_free))

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
	# 游戏内终端不写排版文件 → 先清掉上次外部终端留下的，否则立绘会按旧矩形摆
	ExtTerminal.clear_geometry()
	term.play(ai_id, ai_name, art_tex, on_done)


## 预热马赛克着色器。
##
## 首次绘制要编译，实测吃 ~120ms。而那一刻正好是「终端关闭 → 符号帧出现」的衔接点，
## 不预热的话衔接会顿一下。这里趁终端还在播（十几秒）先让它画一次，编译结果进缓存。
## 注意必须放在黑幕**之前**添加，否则会露出来；alpha 用 0.004 而不是 0 —— 全透明可能被
## 渲染器整个跳过，那就白预热了。
func _prewarm_mosaic_shader(tex: Texture2D) -> void:
	if _mosaic_warm != null or tex == null:
		return
	var warm := TextureRect.new()
	warm.name = "MosaicWarm"
	warm.texture = tex
	warm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	warm.stretch_mode = TextureRect.STRETCH_SCALE
	warm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = MOSAIC_SHADER
	m.set_shader_parameter("block", 6.0)
	m.set_shader_parameter("alpha", 0.004)
	warm.material = m
	add_child(warm)
	_mosaic_warm = warm


## 终端切回 Godot 的立绘，四段走：
##   ① **符号帧**：把终端那一屏字符画 1:1 重画一遍（同字、同格、同矩形）→ 第一帧就是终端画面
##   ② **符号解码**：每个符号随机闪成别的符号，再逐格定稿回真符号
##   ③ **符号 → 马赛克**：同格的彩色马赛克淡入（一块马赛克 = 一个字符格）
##   ④ **马赛克 → 清晰**：块大小逐帧收到 1
## 然后停留、淡出、回调。
##
## 为什么第一步必须是「重画」而不是「淡入图片」：终端一关，屏幕上原本是符号；
## 如果 Godot 第一帧直接给彩色图，就等于在两个不同画面之间硬切一次。
## 重画一份符号，切换那一帧前后完全一致，观众看不到「切」。
func _show_hero_portrait(tex: Texture2D, on_end: Callable) -> void:
	if tex == null:
		on_end.call()
		return
	var geom := ExtTerminal.read_geometry()
	var box := _portrait_box(tex, geom)
	if _mosaic_warm != null:
		_mosaic_warm.queue_free()
		_mosaic_warm = null
	var lines := _portrait_art(tex)
	var artw := 1
	for l in lines:
		artw = maxi(artw, l.length())
	var arth := maxi(1, lines.size())
	# 一格 = 字符画矩形 / 字符数，保证符号网格和后面的马赛克块一一对应
	var cell := Vector2(box.size.x / float(artw), box.size.y / float(arth))

	var bg := ColorRect.new()
	bg.name = "HeroBackdrop"
	bg.color = Color.BLACK      ## 与终端背景同色：切换瞬间看不出边界
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# ① 符号帧（终端画面的复刻），第一帧全亮
	var sym := SymbolFrame.new()
	sym.name = "HeroSymbol"
	sym.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sym)
	sym.setup(lines, cell, box.position)

	# ②③ 彩色立绘：起始为「一格一块」的马赛克，且不可见
	var img := TextureRect.new()
	img.name = "HeroPortrait"
	img.texture = tex
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# STRETCH_SCALE 而不是 KEEP_ASPECT_CENTERED：矩形已经是终端那块的尺寸，
	# 再让 TextureRect 自己等比适配一次就会缩回去，对齐就白算了。
	img.stretch_mode = TextureRect.STRETCH_SCALE
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(img)
	img.position = box.position
	img.size = box.size

	var mat := ShaderMaterial.new()
	mat.shader = MOSAIC_SHADER
	var block0 := _mosaic_block0(tex.get_width(), artw)
	mat.set_shader_parameter("block", block0)
	mat.set_shader_parameter("alpha", 0.0)
	img.material = mat

	# 字幕「正在生成 AI 娘中」：和终端那一行 1:1 —— 同一套字符格、同一位置、同一字号。
	# 位置由终端写回的 capx/capy 反推（相对字符画原点），所以两边逐字对齐。
	var cap_cols := IntroScript.caption_cells()
	var capx_rel := int(floor((artw - cap_cols) * 0.5))
	var capy_rel := arth + 1
	if not geom.is_empty():
		capx_rel = int(geom.get("capx", 0)) - int(geom.get("padx", 0))
		capy_rel = int(geom.get("capy", 0)) - int(geom.get("pady", 0))
	var cap := SymbolFrame.new()
	cap.name = "HeroCaption"
	cap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cap)
	# 保险：终端网格铺满整块屏幕（比 16:9 画布高），字幕有可能算到画布外被裁掉 → 夹回来
	var cap_pos := box.position + Vector2(float(capx_rel) * cell.x, float(capy_rel) * cell.y)
	cap_pos.y = minf(cap_pos.y, get_viewport_rect().size.y - cell.y * 1.2)
	cap.setup(PackedStringArray([IntroScript.CAPTION]), cell, cap_pos)

	var tw := create_tween()
	_hero_tween = tw        ## 存句柄：自检时 pause 它才能拍到「第一帧」
	# ① 第一帧保留终端画面：同字同格同位置，先停一拍让观众看清「这就是刚才终端那张」
	tw.tween_interval(SYMBOL_HOLD)
	# ② 符号解码：每个符号随机闪成别的符号，再逐格定稿回真符号
	tw.tween_method(func(v: float) -> void: sym.set_shuffle(v), 0.0, 1.0, SYMBOL_DECODE)
	# ③ 彩色马赛克盖上去：每个格子变成「清晰立绘对应部位」的颜色块。
	# **符号不淡出，让彩色从上面盖上去**。两边同时淡（交叉淡入淡出）实测太生硬，
	# 且中途会发暗；覆盖式更像「符号被上了色」。
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("alpha", v),
			0.0, 1.0, COLOR_IN)
	tw.tween_callback(func() -> void: sym.hide())   ## 覆盖完成后把符号层收掉，免得末尾淡出时又露出来
	# ④ 马赛克 → 清晰。线性、不要 EASE_OUT：实测 cubic/ease_out 会把变化全堆在前 0.3 秒，
	# 0.5 秒就已经完全清晰，后半段等于空转。线性才「逐渐」。
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("block", v),
			block0, 1.0, MOSAIC_TIME)
	tw.tween_interval(HERO_HOLD)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("alpha", v),
			1.0, 0.0, HERO_FADE_OUT).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(bg, "color:a", 0.0, HERO_FADE_OUT)
	tw.parallel().tween_property(cap, "modulate:a", 0.0, HERO_FADE_OUT)
	tw.tween_callback(func() -> void:
		bg.queue_free()
		sym.queue_free()
		cap.queue_free()
		img.queue_free()
		on_end.call())


## 要复刻的字符画：优先用终端真正画过的那一份（ExtTerminal 缓存）。
## 缓存为空才现算——AsciiArt.build 要扫百万像素，在衔接点上重算会卡住整整一秒。
func _portrait_art(tex: Texture2D) -> PackedStringArray:
	if not ExtTerminal.last_art.is_empty():
		return ExtTerminal.last_art
	return AsciiArt.build(tex, ExtTerminal.ART_ROWS, ExtTerminal.ART_MAX_COLS,
			ExtTerminal.CELL_ASPECT)


## 立绘该占的矩形（画布坐标）。
##
## 关键：终端排版是「屏幕比例」，而 Godot 画布 1600x900 全屏时会按 keep 信箱化
## （16:10 屏幕上上下各 80px 黑边）。直接拿比例当画布坐标用，上下就差 4%——
## 这就是「位置还是有些偏差」的真因。所以先还原屏幕比例，再换回画布坐标。
func _portrait_box(tex: Texture2D, geom: Dictionary) -> Rect2:
	var base := get_viewport_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	if win.x < 1.0 or win.y < 1.0:
		win = base
	var s := minf(win.x / base.x, win.y / base.y)      ## 信箱化缩放比
	var off := (win - base * s) * 0.5                  ## 黑边宽度

	var rect: Rect2
	if geom.is_empty():
		# 兜底（走的是游戏内终端）：画布内居中、高度占 90%
		var src := tex.get_size()
		var h := base.y * 0.90
		var w := h * (src.x / maxf(1.0, src.y))
		rect = Rect2((base - Vector2(w, h)) * 0.5, Vector2(w, h))
	else:
		var cols := float(geom["cols"])
		var rows := float(geom["rows"])
		rect = Rect2(
			(float(geom["padx"]) / cols * win.x - off.x) / s,
			(float(geom["pady"]) / rows * win.y - off.y) / s,
			float(geom["artw"]) / cols * win.x / s,
			float(geom["arth"]) / rows * win.y / s)

	# 保险：掉进黑边会被画布裁掉 → 先等比缩进画布，再夹位置
	var fit := minf(base.x / maxf(1.0, rect.size.x), base.y / maxf(1.0, rect.size.y))
	if fit < 1.0:
		var c := rect.get_center()
		rect.size *= fit
		rect.position = c - rect.size * 0.5
	rect.position.x = clampf(rect.position.x, 0.0, maxf(0.0, base.x - rect.size.x))
	rect.position.y = clampf(rect.position.y, 0.0, maxf(0.0, base.y - rect.size.y))
	return rect


## 起始马赛克块（纹理像素）：一块 = 终端的一个字符格，和符号帧的网格一一对齐。
func _mosaic_block0(tex_w: int, artw: int) -> float:
	return clampf(float(tex_w) / float(maxi(1, artw)) * MOSAIC_CELLS, 2.0, 128.0)


## 转场落回 2D：手牌错峰弹出、敌人砸落 + 震屏
func _reveal_from_intro() -> void:
	for i in _hand_views.size():
		var v := _hand_views[i]
		# 卡牌从对话框左侧弹入（主人手绘稿）：先藏到对话框左缘外，再滑进各自槽位
		var slot := _hand_slot(i, _hand_views.size())
		v.position = Vector2(DIALOG_X - CARD_W - 24.0, slot["pos"].y + 14.0)
		v.scale = Vector2(0.7, 0.7)
		var tw := v.create_tween()
		tw.set_parallel()
		tw.tween_property(v, "position", slot["pos"], 0.34).set_delay(i * 0.06) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(v, "scale", Vector2.ONE, 0.34).set_delay(i * 0.06) \
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
	_update_seq_preview()


func _refresh_playable() -> void:
	var mult := 1.0
	if combat != null and combat.is_awake():
		mult = StsCombat.RICE_BUFF
	for v in _hand_views:
		if v != null and v.card != null:
			v.set_playable(combat != null and combat.can_play(v.card))
			v.set_multiplier(mult)


## 序列预览接线：把 preview_sequence 的影子推演刷到每张手牌上——
## 首位/末位槽位徽标（set_slot）+ 该位置将打出的数值（set_seq_value）。
## 手牌发生变化的所有出口（重建 / 补位同步 / 发送逐张 / 新回合）都要调一次。
func _update_seq_preview() -> void:
	if combat == null:
		return
	var seq := combat.preview_sequence()
	for i in _hand_views.size():
		var v := _hand_views[i]
		if v == null or v.card == null:
			continue
		var info: Dictionary = seq[i] if i < seq.size() else {}
		v.set_slot(bool(info.get("lead", false)), bool(info.get("finish", false)))
		v.set_seq_value(info)


func _refresh_hud() -> void:
	if combat == null:
		return
	_enemy_hp_label.text = "HP %d/%d" % [combat.enemy_hp, combat.enemy_max_hp]
	var er := clampf(float(combat.enemy_hp) / float(maxi(1, combat.enemy_max_hp)), 0.0, 1.0)
	_enemy_fill.size = Vector2(ENEMY_W * er, 10.0)
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
	if card == null:
		return
	# 弃牌模式：点谁弃谁，弃 1 抽 1（从牌堆）；每回合有次数上限
	if _discard_mode:
		if _discards_left <= 0:
			_status_label.text = "本回合弃牌次数用完（上限 %d 张），先结束回合。" \
					% DISCARD_LIMIT_PER_TURN
			return
		if combat.discard_card(card):
			_discards_left -= 1
			_update_discard_btn()
			_busy = true
			_float_text(view.position + Vector2(CARD_W * 0.5, 0.0),
					"弃", Color(1.0, 0.75, 0.4), UiKit.FS_M)
			SfxNode.play("card_select")
			# 弃牌动画：斜着飞向右下角（弃牌堆方向）并缩小淡出
			if _fx_enabled:
				var tw := view.create_tween()
				tw.set_parallel(true)
				tw.tween_property(view, "position",
						Vector2(size.x - CARD_W * 0.7, size.y - CARD_H * 0.55), 0.26) \
						.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
				tw.tween_property(view, "rotation", 0.42, 0.26)
				tw.tween_property(view, "scale", Vector2(0.5, 0.5), 0.26)
				tw.tween_property(view, "modulate:a", 0.0, 0.24)
				await tw.finished
			view.queue_free()
			_sync_hand_views()  ## 补抽的 1 张从对话框左侧滑入
			_refresh_playable()
			_busy = false
		return
	# 点牌不再单张出牌：整理手牌（弃牌）后点下方「发送」整手打出
	_status_label.text = "点「发送」打出整手牌。"


## 发送：整手牌按 **从左到右** 的顺序一张张打出，每张往对话框左侧弹出
func _on_send_pressed() -> void:
	if _busy or _overlay.visible or combat == null:
		return
	if _discard_mode:
		_status_label.text = "先关掉弃牌模式再发送。"
		return
	if combat.hand.is_empty():
		_status_label.text = "手牌是空的，等补牌或结束回合。"
		return
	_busy = true
	_send_btn.disabled = true
	_end_turn_button.disabled = true
	var order := 0
	# hand[0] 就是最左那张：一张张打出，打完才补（play_card 传 auto_refill=false，
	# 否则中途一打空就补，永远打不完）
	var seq_n := combat.hand.size()
	while not combat.hand.is_empty() and combat.over == StsCombat.Result.RUNNING:
		var card := combat.hand[0]
		var view := _view_of(card)
		if view != null:
			_hand_views.erase(view)     ## 先移出队列，剩下的牌才能补位
		var is_lead := order == 0
		var is_finish := order == seq_n - 1
		var ev := combat.play_card(card, false, is_lead, is_finish)
		if not bool(ev.get("ok", false)):
			break
		order += 1
		_layout_hand(true)
		# 数值反馈：攻击 → 敌人闪红飘伤害（带连段/复读标记）；防御 → 格挡飘字；
		# 白米饭 → 成长进度；吃满那碗 → 睡醒提示
		var kind := String(ev.get("kind", ""))
		if kind == "rice":
			_float_text(Vector2(size.x * 0.5, size.y - CARD_H - 90.0),
					"吃掉白米饭 %d/%d" % [int(ev.get("value", 0)), StsCombat.RICE_AWAKE],
					Color(1.0, 0.9, 0.55), UiKit.FS_M)
			SfxNode.play("hand_small")
			_update_rice_hud()
			## 恰好吃满第 RICE_AWAKE 碗的瞬间（sts_combat 在事件里标 awake_now）
			if bool(ev.get("awake_now", false)):
				_float_text(Vector2(size.x * 0.5, size.y - CARD_H - 130.0),
						"有点睡醒！", Color(0.6, 1.0, 0.75), UiKit.FS_L)
		elif kind == "attack":
			var tag := ""
			if bool(ev.get("repeat", false)):
				tag = "复读！"
			elif int(ev.get("streak", 1)) >= 2:
				tag = "连段%d " % int(ev.get("streak", 1))
			_enemy_hit_fx(int(ev.get("value", 0)), tag)
			SfxNode.play("hand_big")
		elif kind == "loop":
			_float_text(Vector2(size.x * 0.5, size.y - CARD_H - 90.0),
					"复读机就绪", Color("ffcf7a"), UiKit.FS_M)
			SfxNode.play("hand_small")
		elif kind == "parallel":
			_float_text(Vector2(size.x * 0.5, size.y - CARD_H - 90.0),
					"并行：连段锁定", Color(0.31, 0.64, 0.88), UiKit.FS_M)
			SfxNode.play("hand_small")
		else:
			_float_text(Vector2(size.x * 0.5, size.y - CARD_H - 90.0),
					"+%d 格挡" % int(ev.get("value", 0)), Color(0.31, 0.64, 0.88), UiKit.FS_M)
			SfxNode.play("hand_small")
		if view != null:
			if _fx_enabled:
				await _send_card_fx(view)
			view.queue_free()
		_refresh_playable()
		_update_seq_preview()

	_update_rice_hud()
	combat.end_send()           ## 序列收尾（观察者统计就此定格）

	if combat.over == StsCombat.Result.WIN:
		_refresh_hud()
		await get_tree().create_timer(0.5).timeout
		_finish_battle(true)
		return
	# 发送 = 运行程序 → 程序跑完自动进入敌方回合（2026-10-31 主人钦定：
	# 每回合一次运行，杜绝无限连发；顺序策略集中在执行前的队列编辑）
	if _fx_enabled:
		await get_tree().create_timer(0.3).timeout
	await _run_enemy_turn()

	if combat.over == StsCombat.Result.WIN:
		await get_tree().create_timer(0.5).timeout
		_finish_battle(true)
		return
	_send_btn.disabled = false
	_end_turn_button.disabled = false
	_busy = false


## 发送动画：这张牌往**对话框左侧**弹出去并淡出
## 白米饭成长 HUD：进度 + 到点换伙伴立绘
func _update_rice_hud() -> void:
	if combat == null:
		return
	var awake := combat.is_awake()
	if _rice_label != null:
		if awake:
			_rice_label.text = "白米饭 %d/%d · 有点睡醒" % [
				combat.rice_eaten, StsCombat.RICE_AWAKE]
			_rice_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.75))
		else:
			_rice_label.text = "白米饭 %d/%d" % [combat.rice_eaten, StsCombat.RICE_AWAKE]
	if _companion != null:
		if awake:
			_companion.set_stage("stand")
		elif combat.is_stir():
			_companion.set_stage("stir")
		else:
			_companion.set_stage("sleep")


func _send_card_fx(view: StsCardView) -> void:
	var tw := view.create_tween()
	tw.set_parallel(true)
	tw.tween_property(view, "position",
			Vector2(DIALOG_X - CARD_W * 0.9, view.position.y - 18.0), 0.24) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(view, "rotation", -0.24, 0.24)
	tw.tween_property(view, "scale", Vector2(0.8, 0.8), 0.24)
	tw.tween_property(view, "modulate:a", 0.0, 0.22)
	await tw.finished


func _view_of(card: StsCard) -> StsCardView:
	for v in _hand_views:
		if v != null and v.card == card:
			return v
	return null


## 手牌视图与 combat.hand 对齐：
##   · 不在手牌里的视图移除（出牌/弃牌的已在调用方播完退场动画）
##   · 新补的牌建视图，从对话框左侧滑入（补牌的入场动画）
func _sync_hand_views() -> void:
	if combat == null:
		return
	for i in range(_hand_views.size() - 1, -1, -1):
		if not combat.hand.has(_hand_views[i].card):
			_hand_views[i].queue_free()
			_hand_views.remove_at(i)
	for c in combat.hand:
		var have := false
		for v in _hand_views:
			if v.card == c:
				have = true
				break
		if not have:
			var v := StsCardView.new()
			v.setup(c)
			v.clicked.connect(_on_card_clicked)
			v.mouse_entered.connect(_on_hand_hover.bind(v, true))
			v.mouse_exited.connect(_on_hand_hover.bind(v, false))
			_card_layer.add_child(v)
			var slot := _hand_slot(_hand_views.size(), combat.hand.size())
			v.position = Vector2(DIALOG_X - CARD_W - 24.0, slot["pos"].y + 14.0)
			v.scale = Vector2(0.7, 0.7)
			_hand_views.append(v)
	_layout_hand(true)
	_refresh_playable()
	_update_seq_preview()


func _update_discard_btn() -> void:
	if _discard_btn == null:
		return
	if _discard_mode:
		_discard_btn.text = "弃牌模式：开（本回合剩 %d 次）" % _discards_left
	else:
		_discard_btn.text = "弃牌模式：关"


## 弃牌模式开关
func _on_discard_toggled(on: bool) -> void:
	_discard_mode = on
	## 次数**不**在这里回满——只在新回合开始时回满，否则反复开关就能绕过上限
	_update_discard_btn()
	_status_label.text = ("弃牌模式开启：点手牌弃掉，弃 1 张从牌堆抽 1 张（本回合剩 %d 次）。"
			% _discards_left) if on else "弃牌模式关闭。"


## 敌人受击：闪红 + 抖动 + 头顶飘伤害数字（tag = 连段/复读标记，缀在数字前）
func _enemy_hit_fx(dmg: int, tag: String = "") -> void:
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
	var txt := "-%d" % dmg
	if not tag.is_empty():
		txt = "%s-%d" % [tag, dmg]
	_float_text(_enemy_root.position + Vector2(_enemy_root.size.x * 0.5, 24.0),
			txt, Color(1.0, 0.42, 0.42), UiKit.FS_L)


# ─────────────────────────────────────────────────────────
#  结束回合（敌人行动）
# ─────────────────────────────────────────────────────────
func _on_end_turn_pressed() -> void:
	if _busy or _overlay.visible or combat == null:
		return
	combat.end_send()           ## 没发送直接结束：本次运行没有统计
	await _run_enemy_turn()


## 敌方回合 + 新回合发牌（发送后自动走，手动结束也走）
func _run_enemy_turn() -> void:
	_busy = true
	_end_turn_button.disabled = true
	_send_btn.disabled = true
	_discards_left = DISCARD_LIMIT_PER_TURN   ## 新回合弃牌次数回满
	_update_discard_btn()
	if _fx_enabled:
		await get_tree().create_timer(0.25).timeout

	var events := combat.end_turn()
	for e in events:
		var kind := String(e.get("kind", ""))
		if kind == "enemy_attack":
			if _fx_enabled:
				await _enemy_attack_fx(int(e.get("value", 0)), int(e.get("dealt", 0)),
						int(e.get("blocked", 0)))
		elif kind == "enemy_defend":
			if _fx_enabled:
				_float_text(_enemy_root.position + Vector2(_enemy_root.size.x * 0.5, 44.0),
						"+%d 防" % int(e.get("value", 0)), Color(0.31, 0.64, 0.88), UiKit.FS_M)
				await get_tree().create_timer(0.3).timeout

	# 观察者反应（E）：一行日志，不弹窗。（2026-10-30 简化改版拆掉了控制台，
	# 这里存进 _observer_note 并在回合交接时缀到状态栏；debug_console_log 可读）
	for e2 in events:
		if String(e2.get("kind", "")) == "observer":
			_observer_note = String(e2.get("note", ""))

	_refresh_hud()
	_rebuild_hand()
	_update_seq_preview()

	if combat.over == StsCombat.Result.LOSE:
		await get_tree().create_timer(0.4).timeout
		_finish_battle(false)
		return

	_busy = false
	_end_turn_button.disabled = false
	_send_btn.disabled = false
	_status_label.text = "新回合：%s" % _intent_text()
	if _observer_note != "":
		_status_label.text += " ｜ %s" % _observer_note
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
	## 出牌方式改成「整手发送」后，这个钩子直接触发一次发送
	if combat == null or combat.hand.is_empty():
		return false
	_on_send_pressed()
	return true


func debug_play_card_id(card_id: String) -> bool:
	for v in _hand_views:
		if v != null and v.card != null and v.card.id == card_id:
			return debug_play_card(_hand_views.find(v))
	return false


func debug_end_turn() -> void:
	_on_end_turn_pressed()


func debug_hand_count() -> int:
	return _hand_views.size()


## 手牌首张的缩放（验收「发送后牌变小」用）
## 自检：直接喂 n 碗白米饭，用来看成长后的伙伴立绘与 HUD
func debug_feed_rice(n: int) -> void:
	if combat == null:
		return
	combat.rice_eaten = mini(combat.rice_eaten + n, StsCombat.RICE_AWAKE)
	_update_rice_hud()


## 输入条与侧栏的实际矩形（验收「下缘齐平」用）
func debug_layout_rects() -> String:
	var dlg := get_node_or_null("ActionDialog") as Control
	var rail := get_node_or_null("HudLeft") as Control
	if dlg == null or rail == null:
		return "no nodes"
	return "侧栏 y=%.0f..%.0f ｜ 输入条 y=%.0f..%.0f x=%.0f..%.0f" % [
		rail.position.y, rail.position.y + rail.size.y,
		dlg.position.y, dlg.position.y + dlg.size.y,
		dlg.position.x, dlg.position.x + dlg.size.x]


func debug_hand_scale() -> float:
	return _hand_views[0].scale.x if not _hand_views.is_empty() else -1.0




func debug_combat_state() -> Dictionary:
	if combat == null:
		return {}
	return {
		"hp": combat.hp, "block": combat.block,
		"enemy_hp": combat.enemy_hp, "enemy_block": combat.enemy_block,
		"turn": combat.turn,
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
	return _observer_note
