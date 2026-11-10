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
## LLM 决策先到 / 3s 超时到（内部信号：_run_enemy_turn 靠它继续推进，二者只赢一次）
signal ai_decision_ready

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
var _skill_title: Button = null
var _skill_list_box: VBoxContainer = null
var _mcp_title: Button = null
var _mcp_box: VBoxContainer = null

# 右上敌人 HUD
var _enemy_name_label: Label = null
var _enemy_hp_label: Label = null
var _enemy_fill: ColorRect = null
var _enemy_hp_host: Control = null
var _enemy_block_label: Label = null
var _enemy_status_label: Label = null
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

# 终结技「深度思考」（DeepSeek 专属，2026-11-03）
var _ult_btn: TextureButton = null
var _ult_bar: ColorRect = null
var _ult_bar_bg: ColorRect = null
var _ult_label: Label = null
var _ult_playing := false

# 许愿卡（AI 作画，2026-11-04 圆桌定稿；2026-11-07 起去掉文字输入，AI 纯看图）
var _wish_btn: Button = null
var _wish_panel: PanelContainer = null
var _wish_feedback: Label = null
var _wish_pending_card: StsCard = null
var _wish_pending_name := ""
var _wish_canvas: WishCanvas = null
var _wish_mode_vision := false
## 截断重试标记：每张卡只重试一次
var _wish_retried := false
var _wish_confirm_btn: Button = null
var _wish_hint_label: Label = null
var _wish_canvas_clear_btn: Button = null
var _wish_undo_btn: Button = null
var _wish_eraser_btn: TextureButton = null
var _wish_picker_btn: TextureButton = null
var _wish_size_slider: HSlider = null
var _wish_size_label: Label = null
var _wish_hue_slider: HSlider = null
var _wish_sv_rect: TextureRect = null
var _wish_color_swatch: Panel = null
## 调色盘当前 HSV（0..1）
var _wish_hue := 0.6
var _wish_sat := 0.2
var _wish_val := 0.15
var _wish_size_preview_gen := 0

var _elite := false   ## 精英战斗（门选制：精英门必为精英）
var _rice_label: Label = null
## Token 额度标签（主人钦定：额度 = 生命值，AI 娘头顶显示）
var _token_label: Label = null
## 效果层：玩家状态条（降智/中毒等）
var _player_status_label: Label = null
## 牌堆/弃牌堆图标与查看面板（2026-11-01 主人钦定：右栏左下两图标，点开看列表）
var _pile_draw_icon: TextureRect = null
var _pile_discard_icon: TextureRect = null
var _pile_draw_count: Label = null
var _pile_discard_count: Label = null
var _pile_panel: PanelContainer = null
var _pile_panel_title: Label = null
var _pile_panel_list: VBoxContainer = null
var _pile_panel_mode := -1   ## -1 关闭 ｜ 0 抽牌堆 ｜ 1 弃牌堆
var _send_btn: Button = null
var _discards_left := DISCARD_LIMIT_PER_TURN

## 弃牌次数上限（子代理零件：+1）
func _discard_limit() -> int:
	return DISCARD_LIMIT_PER_TURN + (1 if run != null and run.has_effect("subagent") else 0)


## 本回合还能不能弃（剩 > 0）。2026-11-05 修：旧判定 `< 上限` 导致只能弃 1 张。
func _can_discard() -> bool:
	return _discards_left > 0

# 特效层
var _fx_enabled := true
var _fx_root: Control = null
var _fx_flash: ColorRect = null
## 观察者反应（E）：最近一条（落到状态栏显示，debug_console_log 读取）
var _observer_note := ""

# ── LLM 接入（battle-integration · 2026-11-03）──────────
## AI 对手：AI 开启 && 普通战斗（非精英/Boss）才走 LLM 决策；其余一律原规则零差异。
## AI 娘：AIBanter 四钩子，provider 异步不阻塞、失败落本地兜底。
var ai_timeout := 3.0            ## 决策预算：请求发出当帧起算（ignore_time_scale）
var _llm_cfg: LLMConfig = null
var _llm: LLMClient = null
var _banter: AIBanter = null
var _ai_done := false            ## 本次决策是否已定（回调与超时只赢一次）
var _ai_action := ""
var _ai_reason := ""
var _ai_source := ""
var _ai_think: Label = null      ## 敌人头顶「思考中…」气泡

# 覆盖层（结算弹窗）
var _overlay: PanelContainer = null
var _overlay_title: Label = null
var _overlay_body: Label = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(run_state: RunState, lv: LevelData, elite: bool = false) -> void:
	run = run_state
	level = lv
	_elite = elite


## 视觉验收：--wish-demo 时自动打开许愿面板
var auto_open_wish := false


func _ready() -> void:
	# 全程同一首（主人 2026-10-30：进战斗也用 bgm_gemini2，不切曲）
	SfxNode.music("bgm_gemini2")
	_build_ui()
	resized.connect(_layout)
	await get_tree().process_frame
	_layout()
	_start_battle()
	if auto_open_wish:
		_open_wish_panel()


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

	# 终端代码雨背景（2026-11-07 主人要求：主界面与战斗背景都下雨）——
	# 在黑底之上、所有 HUD/卡牌之下，只在不遮挡战局的地方下雨
	var rain := TerminalRain.new()
	rain.name = "TerminalRainBg"
	rain.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rain)

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
	_rail_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_rail.add_child(_rail_box)

	var ai_name := run.ai.display_name if run.ai != null else "AI"
	_rail_box.add_child(UiKit.title_bar(ai_name, 0.0, HORIZONTAL_ALIGNMENT_LEFT, UiKit.TEXT))
	_rail_box.add_child(UiKit.rule())

	# 技能 / MCP 下拉（2026-11-03 主人要求，与启动界面一致）
	_skill_title = _dropdown_title("▸ 技能")
	_skill_title.pressed.connect(_toggle_skill_list)
	_rail_box.add_child(_skill_title)
	_skill_list_box = VBoxContainer.new()
	_skill_list_box.add_theme_constant_override("separation", 2)
	_skill_list_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_list_box.visible = false
	if run.ai != null:
		for sk in run.ai.taste_rules:
			_skill_list_box.add_child(UiKit.dim("  · " + sk, UiKit.FS_XS))
	_rail_box.add_child(_skill_list_box)

	_rail_box.add_child(UiKit.rule())
	_mcp_title = _dropdown_title("▸ MCP")
	_mcp_title.pressed.connect(_toggle_mcp_list)
	_rail_box.add_child(_mcp_title)
	_mcp_box = VBoxContainer.new()
	_mcp_box.add_theme_constant_override("separation", 2)
	_mcp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mcp_box.visible = false
	for item in LaunchScreen.MCP_ITEMS:
		_mcp_box.add_child(UiKit.dim("  · " + item, UiKit.FS_XS))
	_rail_box.add_child(_mcp_box)
	_refresh_item_lists()


## 道具按 Skill / MCP 两类挂进左侧下拉（2026-11-04 主人钦定）：
## skill = AI 自身能力（子代理零件/上下文压缩）；mcp = 外挂工具（提示词优化器/电子木鱼）。
func _refresh_item_lists() -> void:
	if _skill_list_box == null or _mcp_box == null or run == null:
		return
	for box in [_skill_list_box, _mcp_box]:
		for c in box.get_children():
			if bool(c.get_meta("item_row", false)):
				box.remove_child(c)
				c.queue_free()
	for it in run.items:
		var target := _skill_list_box if it.category == "skill" else _mcp_box
		var col := Color(0.42, 0.45, 0.52) if it.broken else Color(0.62, 0.88, 1.0)
		var state := "已损坏"
		if not it.broken:
			state = ("耐久 %d" % it.charges) if it.charges > 0 else "常驻"
		var l := UiKit.dim("  ▸ %s（%s）" % [it.display_name, state], UiKit.FS_XS, col)
		l.set_meta("item_row", true)
		l.tooltip_text = it.description
		target.add_child(l)


## 侧栏下拉标题按钮（扁平、左对齐、可点）
func _dropdown_title(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", PixelTheme.font())
	b.add_theme_font_size_override("font_size", UiKit.FS_S)
	b.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	b.add_theme_color_override("font_hover_color", Color(0.85, 0.95, 1.0))
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


func _toggle_skill_list() -> void:
	if _skill_list_box == null:
		return
	_skill_list_box.visible = not _skill_list_box.visible
	_skill_title.text = ("▾ 技能" if _skill_list_box.visible else "▸ 技能")


func _toggle_mcp_list() -> void:
	if _mcp_box == null:
		return
	_mcp_box.visible = not _mcp_box.visible
	_mcp_title.text = ("▾ MCP" if _mcp_box.visible else "▸ MCP")


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

	_enemy_hp_label = UiKit.label("故障强度 0/0", UiKit.FS_XS, Color(0.95, 0.35, 0.4))
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

	_enemy_status_label = UiKit.label("", UiKit.FS_XS, Color(0.95, 0.62, 0.35))
	_enemy_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_status_label.clip_text = true
	_enemy_status_label.add_theme_stylebox_override("normal", _status_badge_style(
			Color(0.36, 0.20, 0.08, 0.88)))
	right.add_child(_enemy_status_label)

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
	_rice_label = UiKit.label("白米饭 0/5", UiKit.FS_XS, Color(1.0, 0.9, 0.55))
	_token_label = UiKit.label("Token 额度 %dK/%dK" % [run.hp, RunState.MAX_HP],
			UiKit.FS_XS, Color(0.31, 0.76, 0.97))
	_token_label.name = "TokenLabel"
	_token_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_token_label)
	## 效果层：玩家状态条（降智/中毒等），空时隐藏
	_player_status_label = UiKit.label("", UiKit.FS_XS, Color(0.55, 0.85, 1.0))
	_player_status_label.name = "PlayerStatusLabel"
	_player_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_status_label.clip_text = true
	_player_status_label.add_theme_stylebox_override("normal", _status_badge_style(
			Color(0.08, 0.22, 0.30, 0.88)))
	add_child(_player_status_label)
	_rice_label.name = "RiceLabel"
	_rice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rice_label)
	_build_pile_ui()
	_build_ult_ui()
	_build_wish_ui()


## 工具侧栏小图标（生图素材，40px 显示）
func _wish_tool_icon(path: String) -> TextureRect:
	var r := TextureRect.new()
	if ResourceLoader.exists(path):
		r.texture = load(path)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(40, 40)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 组合审计标记（2026-11-10）：判 block 只在开战时提示一次，**不拦不夺卡**。
## partial（有组没算完）刻意不提示——把"没算过"当风险告警会让玩家莫名其妙。
func _show_combo_mark() -> void:
	var a := run.combo_audit
	if a.is_empty():
		return
	if String(a.get("tag", "")) != "block":
		return
	var names: Array[String] = []
	for row in (a.get("pairs", []) as Array):
		if String(row.get("tag", "")) != "block":
			continue
		names.append("%s × %s" % [
			StsCardPool.card_name(String(row["a"])),
			StsCardPool.card_name(String(row["b"]))])
	if names.is_empty():
		for row in ((a.get("triples", []) as Array) + (a.get("quads", []) as Array)):
			if String(row.get("tag", "")) != "block":
				continue
			var ids: Array = row.get("cards", [])
			var group: Array[String] = []
			for cid in ids:
				group.append(StsCardPool.card_name(String(cid)))
			names.append(" × ".join(group))
	if names.is_empty():
		return
	_toast("⚖ 组合警告（不拦）：%s 叠起来超模" % names[0],
			Color(1.0, 0.78, 0.42))


## 醒目提示条（屏幕中央偏上，2.6 秒淡出）——许愿卡完成、组合警告等关键事件用
func _toast(text: String, col: Color = Color(0.62, 0.95, 1.0)) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			UiKit.flat(Color(0.04, 0.07, 0.12, 0.95), UiKit.ACCENT, 2, UiKit.SP_2, 0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, UiKit.FS_S, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	add_child(panel)
	panel.reset_size()
	var vp_toast := get_viewport_rect().size
	panel.position = Vector2((vp_toast.x - panel.size.x) * 0.5, vp_toast.y * 0.22)
	panel.modulate.a = 0.0
	panel.z_index = 90
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.35)
	tw.tween_callback(panel.queue_free)


## 许愿卡入口（左下角，终结技按钮上方）：写下画面 → AI 作画 → 15 秒像素保险丝
## → 成图后无缝替换，卡进牌组（2026-11-04 圆桌定稿）。
func _build_wish_ui() -> void:
	_wish_btn = Button.new()
	_wish_btn.name = "WishButton"
	_wish_btn.text = "愿"
	_wish_btn.flat = true
	_wish_btn.add_theme_font_override("font", PixelTheme.font())
	_wish_btn.add_theme_font_size_override("font_size", 22)
	_wish_btn.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	_wish_btn.add_theme_color_override("font_hover_color", Color(0.9, 0.97, 1.0))
	_wish_btn.add_theme_stylebox_override("normal",
			UiKit.flat(Color(0.05, 0.07, 0.12, 0.9), UiKit.ACCENT, 2, 6, 0))
	_wish_btn.tooltip_text = "许愿卡：画点什么，AI 看图给你造一张专属卡"
	_wish_btn.custom_minimum_size = Vector2(56, 56)
	_wish_btn.size = Vector2(56, 56)
	_wish_btn.pressed.connect(_open_wish_panel)
	add_child(_wish_btn)

	_wish_panel = PanelContainer.new()
	_wish_panel.name = "WishPanel"
	_wish_panel.add_theme_stylebox_override("panel",
			UiKit.flat(Color(0.05, 0.07, 0.12), UiKit.ACCENT, 2, UiKit.SP_3, UiKit.EL_2))
	_wish_panel.visible = false
	_wish_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_wish_panel.size = Vector2(980, 580)
	add_child(_wish_panel)

	## 背景层：终端代码雨（2026-11-07 主人要求）——PanelContainer 会把它铺满，
	## 后加的 outer 在它上面；雨自身 IGNORE 输入、面板隐藏时自动停帧
	var rain := TerminalRain.new()
	rain.name = "TerminalRainBg"
	_wish_panel.add_child(rain)

	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	_wish_panel.add_child(outer)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	outer.add_child(v)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	var ttl := UiKit.label("许愿卡 · 让 AI 给你画一张", UiKit.FS_S, Color(0.55, 0.85, 1.0))
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(ttl)
	var close_btn := UiKit.button("✕ 关闭", UiKit.FS_XS)
	close_btn.custom_minimum_size = Vector2(84, 32)
	close_btn.tooltip_text = "关闭许愿面板（Esc）"
	close_btn.pressed.connect(_close_wish_panel)
	title_row.add_child(close_btn)
	v.add_child(title_row)

	_wish_hint_label = UiKit.dim("", UiKit.FS_XS, Color(0.6, 0.85, 1.0))
	_wish_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_wish_hint_label)

	_wish_canvas = WishCanvas.new()
	outer.add_child(_wish_canvas)
	_wish_canvas.stroke_finished.connect(_on_wish_stroke_finished)
	_wish_canvas.color_picked.connect(func(col: Color) -> void:
		_wish_canvas.brush_color = col
		_wish_canvas.tool = "brush"
		if _wish_picker_btn != null:
			_wish_picker_btn.button_pressed = false
		_wish_sync_color_ui(col))

	## 工具侧栏（2026-11-05 主人要求：画笔大小 / 画笔格式 / 颜色，图标全部用生图）
	var tools := VBoxContainer.new()
	tools.custom_minimum_size = Vector2(88, 0)
	tools.add_theme_constant_override("separation", 6)
	outer.add_child(tools)
	# —— 画笔大小：1–100 滑杆（拖动时画布中心显示黑点预览）——
	var size_head := HBoxContainer.new()
	size_head.add_theme_constant_override("separation", 4)
	size_head.add_child(_wish_tool_icon("res://assets/art/ui-brush-size.png"))
	_wish_size_label = UiKit.label("24", UiKit.FS_XS, UiKit.TEXT_DIM)
	size_head.add_child(_wish_size_label)
	tools.add_child(size_head)

	_wish_size_slider = HSlider.new()
	_wish_size_slider.min_value = WishCanvas.SIZE_MIN
	_wish_size_slider.max_value = WishCanvas.SIZE_MAX
	_wish_size_slider.step = 1
	_wish_size_slider.value = _wish_canvas.brush_size
	_wish_size_slider.custom_minimum_size = Vector2(84, 18)
	_wish_size_slider.value_changed.connect(func(v: float) -> void:
		if _wish_canvas != null:
			_wish_canvas.brush_size = v
			_wish_show_size_preview(v)
		if _wish_size_label != null:
			_wish_size_label.text = "%d" % int(round(v)))
	tools.add_child(_wish_size_slider)

	# —— 画笔形状 ——
	var style_row := HBoxContainer.new()
	style_row.add_theme_constant_override("separation", 4)
	var style_btns: Array[TextureButton] = []
	for si in 2:
		var mode: String = ["round", "square"][si]
		var sb := TextureButton.new()
		sb.ignore_texture_size = true
		sb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		sb.custom_minimum_size = Vector2(34, 34)
		sb.texture_normal = load("res://assets/art/ui-brush-%s.png" % mode)
		sb.tooltip_text = "圆头笔刷" if mode == "round" else "方头笔刷"
		var m := mode
		var sidx := si
		sb.pressed.connect(func() -> void:
			_wish_canvas.brush_style = m
			for k in style_btns.size():
				style_btns[k].modulate = Color.WHITE if k == sidx else Color(0.5, 0.55, 0.62))
		style_row.add_child(sb)
		style_btns.append(sb)
	tools.add_child(style_row)

	# —— 橡皮（图标开关 + 独立 S/M/L）——
	_wish_eraser_btn = TextureButton.new()
	_wish_eraser_btn.toggle_mode = true
	_wish_eraser_btn.ignore_texture_size = true
	_wish_eraser_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_wish_eraser_btn.custom_minimum_size = Vector2(34, 34)
	_wish_eraser_btn.texture_normal = load("res://assets/art/ui-eraser.png")
	_wish_eraser_btn.tooltip_text = "橡皮擦（大小用下面 S/M/L）"
	_wish_eraser_btn.toggled.connect(func(on: bool) -> void:
		if _wish_canvas == null:
			return
		if on:
			_wish_canvas.tool = "eraser"
			if _wish_picker_btn != null:
				_wish_picker_btn.button_pressed = false
		elif _wish_canvas.tool == "eraser":
			_wish_canvas.tool = "brush")
	tools.add_child(_wish_eraser_btn)

	var er_size_row := HBoxContainer.new()
	er_size_row.add_theme_constant_override("separation", 4)
	var er_btns: Array[Button] = []
	for i in 3:
		var esz: float = [10.0, 24.0, 48.0][i]
		var eb := UiKit.button(["S", "M", "L"][i], UiKit.FS_XS)
		eb.custom_minimum_size = Vector2(26, 26)
		eb.tooltip_text = "橡皮大小 %s" % ["小", "中", "大"][i]
		var eidx := i
		eb.pressed.connect(func() -> void:
			_wish_canvas.eraser_size = esz
			if _wish_canvas.tool != "eraser":
				_wish_eraser_btn.button_pressed = true
			for k in er_btns.size():
				er_btns[k].modulate = Color.WHITE if k == eidx else Color(0.5, 0.55, 0.62))
		er_size_row.add_child(eb)
		er_btns.append(eb)
	tools.add_child(er_size_row)

	# —— 吸管（采色笔）——
	_wish_picker_btn = TextureButton.new()
	_wish_picker_btn.toggle_mode = true
	_wish_picker_btn.ignore_texture_size = true
	_wish_picker_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_wish_picker_btn.custom_minimum_size = Vector2(34, 34)
	_wish_picker_btn.texture_normal = load("res://assets/art/ui-eyedropper.png")
	_wish_picker_btn.tooltip_text = "采色笔：点画布取色"
	_wish_picker_btn.toggled.connect(func(on: bool) -> void:
		if _wish_canvas == null:
			return
		if on:
			_wish_canvas.tool = "picker"
			if _wish_eraser_btn != null:
				_wish_eraser_btn.button_pressed = false
		elif _wish_canvas.tool == "picker":
			_wish_canvas.tool = "brush")
	tools.add_child(_wish_picker_btn)

	# —— 调色盘：色相条 + 饱和度/明度方块 + 快捷色 ——
	tools.add_child(_wish_tool_icon("res://assets/art/ui-palette.png"))
	_wish_hue_slider = HSlider.new()
	_wish_hue_slider.min_value = 0
	_wish_hue_slider.max_value = 360
	_wish_hue_slider.step = 1
	_wish_hue_slider.custom_minimum_size = Vector2(84, 16)
	_wish_hue_slider.tooltip_text = "色相"
	_wish_hue_slider.value_changed.connect(func(v: float) -> void:
		_wish_hue = clampf(v / 360.0, 0.0, 1.0)
		_wish_refresh_sv()
		_wish_apply_sv_color())
	tools.add_child(_wish_hue_slider)

	_wish_sv_rect = TextureRect.new()
	_wish_sv_rect.custom_minimum_size = Vector2(80, 80)
	_wish_sv_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wish_sv_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_wish_sv_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_wish_sv_rect.tooltip_text = "饱和度 × 明度（按住拖动选色）"
	_wish_sv_rect.gui_input.connect(_on_sv_gui_input)
	tools.add_child(_wish_sv_rect)

	_wish_color_swatch = Panel.new()
	_wish_color_swatch.custom_minimum_size = Vector2(80, 18)
	_wish_color_swatch.tooltip_text = "当前画笔颜色"
	tools.add_child(_wish_color_swatch)

	var color_grid := GridContainer.new()
	color_grid.columns = 3
	color_grid.add_theme_constant_override("h_separation", 4)
	color_grid.add_theme_constant_override("v_separation", 4)
	var palette_cols := [Color(0.12, 0.13, 0.16), Color(0.98, 0.98, 0.96),
			Color(0.55, 0.85, 1.0), Color(0.35, 0.55, 0.95),
			Color(1.0, 0.82, 0.35), Color(0.95, 0.42, 0.45)]
	var color_btns: Array[Button] = []
	for ci in palette_cols.size():
		var col: Color = palette_cols[ci]
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(24, 24)
		cb.add_theme_stylebox_override("normal", UiKit.flat(col, Color(0.2, 0.28, 0.45), 2, 0))
		cb.add_theme_stylebox_override("hover", UiKit.flat(col, Color(0.9, 0.97, 1.0), 2, 0))
		cb.add_theme_stylebox_override("pressed", UiKit.flat(col, Color(0.9, 0.97, 1.0), 3, 0))
		cb.tooltip_text = "画笔颜色"
		var c2 := ci
		cb.pressed.connect(func() -> void:
			_wish_canvas.brush_color = col
			_wish_sync_color_ui(col)
			for k in color_btns.size():
				color_btns[k].modulate = Color.WHITE if k == c2 else Color(0.72, 0.76, 0.82))
		color_grid.add_child(cb)
		color_btns.append(cb)
	tools.add_child(color_grid)

	# 默认选中：圆头 + 中号橡皮 + 黑
	style_btns[0].modulate = Color.WHITE
	style_btns[1].modulate = Color(0.5, 0.55, 0.62)
	er_btns[1].modulate = Color.WHITE
	er_btns[0].modulate = Color(0.5, 0.55, 0.62)
	er_btns[2].modulate = Color(0.5, 0.55, 0.62)
	for k in color_btns.size():
		color_btns[k].modulate = Color.WHITE if k == 0 else Color(0.72, 0.76, 0.82)
	_wish_sync_color_ui(_wish_canvas.brush_color)

	## 画板编辑行：撤销 / 清空（橡皮与吸管已移到右侧工具栏）
	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 8)
	_wish_undo_btn = UiKit.button("撤销", UiKit.FS_XS)
	_wish_undo_btn.custom_minimum_size = Vector2(96, 36)
	_wish_undo_btn.pressed.connect(func() -> void:
		if _wish_canvas != null:
			_wish_canvas.undo())
	edit_row.add_child(_wish_undo_btn)
	_wish_canvas_clear_btn = UiKit.button("清空画板", UiKit.FS_XS)
	_wish_canvas_clear_btn.custom_minimum_size = Vector2(128, 36)
	_wish_canvas_clear_btn.pressed.connect(func() -> void:
		if _wish_canvas != null:
			_wish_canvas.clear()
			_wish_canvas.tool = "brush"
			_wish_canvas.preview_size = 0.0
			_wish_eraser_btn.button_pressed = false
			if _wish_picker_btn != null:
				_wish_picker_btn.button_pressed = false)
	edit_row.add_child(_wish_canvas_clear_btn)
	v.add_child(edit_row)

	_wish_feedback = UiKit.dim("", UiKit.FS_XS, Color(0.6, 0.85, 1.0))
	_wish_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_wish_feedback)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_wish_confirm_btn = UiKit.button("让 AI 画", UiKit.FS_S, true)
	_wish_confirm_btn.custom_minimum_size = Vector2(0, 44)
	_wish_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wish_confirm_btn.pressed.connect(_confirm_wish)
	row.add_child(_wish_confirm_btn)
	var cancel := UiKit.button("取消", UiKit.FS_S)
	cancel.custom_minimum_size = Vector2(120, 44)
	cancel.pressed.connect(_close_wish_panel)
	row.add_child(cancel)
	v.add_child(row)


func _wish_remaining() -> int:
	if run == null:
		return 0
	var cap := mini(2 + int(run.level_index / 2), 4)
	return maxi(0, cap - run.wish_used)


func _open_wish_panel() -> void:
	_wish_retried = false
	if _wish_panel == null:
		return
	_wish_panel.visible = true
	_wish_panel.size = Vector2(980, 580)
	var vp := get_viewport_rect().size
	_wish_panel.position = (vp - _wish_panel.size) * 0.5
	_wish_panel.move_to_front()
	var cfg := _llm_config()
	_wish_mode_vision = cfg.model_supports_vision()
	var note := ""
	if _wish_mode_vision:
		_wish_confirm_btn.text = "让 AI 看画创作"
		note = "在右侧画板画出你想造的东西——AI 纯看图创作，画得越具体，还原越高。"
	else:
		_wish_confirm_btn.text = "让 AI 看画创作"
		note = "当前模型不支持看图——换一个视觉模型再来许愿吧。"
	_wish_canvas.visible = true
	_wish_canvas_clear_btn.visible = true
	_wish_undo_btn.visible = true
	_wish_eraser_btn.visible = true
	_wish_hint_label.text = note
	_wish_feedback.text = "剩余许愿：%d 次" % _wish_remaining()
	if _wish_mode_vision:
		_wish_canvas.grab_focus()


## 滑杆拖动时的尺寸预览（0.8s 后自动消失）
func _wish_show_size_preview(v: float) -> void:
	if _wish_canvas == null:
		return
	_wish_size_preview_gen += 1
	var gen := _wish_size_preview_gen
	_wish_canvas.preview_size = v
	var t := get_tree().create_timer(0.8, true, false, true)
	t.timeout.connect(func() -> void:
		if gen == _wish_size_preview_gen and _wish_canvas != null:
			_wish_canvas.preview_size = 0.0)


## 重绘饱和度/明度方块（跟随当前色相）
func _wish_refresh_sv() -> void:
	if _wish_sv_rect == null:
		return
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var sat := float(x) / float(n - 1)
			var val := 1.0 - float(y) / float(n - 1)
			img.set_pixel(x, y, Color.from_hsv(_wish_hue, sat, val))
	_wish_sv_rect.texture = ImageTexture.create_from_image(img)


func _on_sv_gui_input(event: InputEvent) -> void:
	var dragging := event is InputEventMouseMotion 			and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	var clicking := event is InputEventMouseButton 			and (event as InputEventMouseButton).pressed
	if not (dragging or clicking):
		return
	var local := _wish_sv_rect.get_local_mouse_position()
	_wish_sat = clampf(local.x / maxf(1.0, _wish_sv_rect.size.x), 0.0, 1.0)
	_wish_val = 1.0 - clampf(local.y / maxf(1.0, _wish_sv_rect.size.y), 0.0, 1.0)
	_wish_apply_sv_color()


func _wish_apply_sv_color() -> void:
	var col := Color.from_hsv(_wish_hue, _wish_sat, _wish_val)
	if _wish_canvas != null:
		_wish_canvas.brush_color = col
	_wish_update_swatch(col)


## 由已有颜色反推 HSV 并同步 UI（吸管/快捷色用）
func _wish_sync_color_ui(col: Color) -> void:
	_wish_hue = col.h
	_wish_sat = col.s
	_wish_val = col.v
	if _wish_hue_slider != null:
		_wish_hue_slider.set_value_no_signal(_wish_hue * 360.0)
	_wish_refresh_sv()
	_wish_update_swatch(col)


func _wish_update_swatch(col: Color) -> void:
	if _wish_color_swatch != null:
		_wish_color_swatch.add_theme_stylebox_override("panel",
				UiKit.flat(col, Color(0.9, 0.97, 1.0), 1, 0))


func _close_wish_panel() -> void:
	if _wish_panel != null:
		_wish_panel.visible = false
	_clear_prefetch()


## ── 许愿预取（圆桌延迟规则 #5，方案 B 2026-11-06）──────────────
## 抬笔后 1.5s 静默发一次请求；玩家点「发送」时若画布+文字没变，直接用预取结果，
## **零等待**。每个面板会话最多预取 2 次（防烧 token）；确认时若预取还在路上，就正常发。
const PREFETCH_DEBOUNCE := 1.5
const PREFETCH_MAX := 6
var _prefetch_busy := false
var _prefetch_result: Dictionary = {}
var _prefetch_done_hash := ""      ## 已完成预取对应的 画布+文字 hash
var _prefetch_sent_hash := ""      ## 已发出的请求 hash（防重复发）
var _prefetch_count := 0


func _wish_prefetch_hash() -> String:
	var uri := _wish_canvas.export_data_uri() if _wish_canvas != null else ""
	return uri.sha256_text()


func _on_wish_stroke_finished() -> void:
	if not _wish_panel.visible or not _wish_mode_vision:
		return
	if _prefetch_busy or _prefetch_count >= PREFETCH_MAX:
		return
	var t := get_tree().create_timer(PREFETCH_DEBOUNCE, true, false, true)
	t.timeout.connect(_do_wish_prefetch)


func _do_wish_prefetch() -> void:
	if not _wish_panel.visible or not _wish_mode_vision:
		return
	if _prefetch_busy or _prefetch_count >= PREFETCH_MAX:
		return
	var h := _wish_prefetch_hash()
	if h == _prefetch_sent_hash or h == _prefetch_done_hash:
		return
	var uri := _wish_canvas.export_data_uri()
	if uri.is_empty():
		return
	_prefetch_busy = true
	_prefetch_count += 1
	_prefetch_sent_hash = h
	_llm_client().request("event", [
		{"role": "system", "content": WishCardFactory.active_prompt()},
		{"role": "user", "content": [
			{"type": "text", "text": "这是我画的涂鸦，请照它造一张卡。"},
			{"type": "image_url", "image_url": {"url": uri}},
		]},
	], _on_wish_prefetch_done, {
		"max_tokens": WishCardFactory.WISH_MAX_TOKENS,
		"timeout_s": LLMConfig.wish_timeout_for(_llm_config().model),
	})


func _on_wish_prefetch_done(r: Dictionary) -> void:
	_prefetch_busy = false
	if bool(r.get("ok", false)):
		_prefetch_result = r
		_prefetch_done_hash = _prefetch_sent_hash
	else:
		_prefetch_done_hash = ""


func _clear_prefetch() -> void:
	_prefetch_busy = false
	_prefetch_result = {}
	_prefetch_done_hash = ""
	_prefetch_sent_hash = ""
	_prefetch_count = 0


func _unhandled_input(event: InputEvent) -> void:
	## Esc 关闭许愿面板（2026-11-05 主人要求画图 GUI 可关闭）
	if _wish_panel != null and _wish_panel.visible 			and event.is_action_pressed("ui_cancel"):
		_close_wish_panel()
		get_viewport().set_input_as_handled()


## 确认许愿：造卡（像素草图先顶上）→ 异步生图 → 成图替换
func _confirm_wish() -> void:
	if run == null:
		return
	if not _wish_mode_vision:
		_wish_feedback.text = "当前模型不支持看图——换一个视觉模型再来许愿吧。"
		return
	if _wish_canvas == null or _wish_canvas.is_empty():
		_wish_feedback.text = "先在白板上画点什么（比如一只蘑菇或一只猫）。"
		return
	if _wish_remaining() <= 0:
		_wish_feedback.text = "本局许愿次数用完了（每 2 关 +1，上限 4）。"
		return
	_request_vision_card(_llm_config())


## 涂鸦/文字造卡：发给**通用大模型**，模型用自己的绘图能力返回 SVG
## （游戏内 ThorVG 渲染成卡面）+ 卡牌 JSON（本地钳制数值）。不用专门的生图模型。
## 视觉模型带涂鸦输入；纯文本模型只发文字（它按描述画 SVG）。
func _request_vision_card(cfg: LLMConfig, is_retry: bool = false) -> void:
	## 预取命中：画布+文字没变 → 直接用预取结果，等待时间≈0
	if _wish_mode_vision and not _prefetch_busy and not _prefetch_result.is_empty() \
			and _wish_prefetch_hash() == _prefetch_done_hash:
		var hit := _prefetch_result
		_clear_prefetch()
		run.wish_used += 1
		_on_vision_card_done(hit)
		return
	_clear_prefetch()
	var messages: Array = []
	var uri := _wish_canvas.export_data_uri()
	if uri.is_empty():
		_wish_feedback.text = "画板导出失败，重画一次试试。"
		run.wish_used -= 1
		return
	## 2026-11-07 主人定稿：去掉文字输入，AI 纯看图创作
	messages = [
		{"role": "system", "content": WishCardFactory.active_prompt()
				+ WishCardFactory.quality_hint(Affection.quality_tier())},
		{"role": "user", "content": [
			{"type": "text", "text": "这是我画的涂鸦，请照它造一张卡。"},
			{"type": "image_url", "image_url": {"url": uri}},
		]},
	]
	run.wish_used += 1
	_wish_feedback.text = "AI 正在创作…（大模型绘图约 30~60 秒）"
	_wish_confirm_btn.disabled = true
	if _status_label != null:
		_status_label.text = "✏ AI 正在创作：你的涂鸦"
	var opts := {
		## 含思考链余量：4096 时推理模型会把额度全花在 reasoning，SVG 被截断
		"max_tokens": WishCardFactory.max_tokens_for(Affection.level()) if is_retry \
			else WishCardFactory.WISH_MAX_TOKENS_RETRY,
		## 超时按模型分档：grok 通道实测 109–123s，统一 90s 会截断
		"timeout_s": LLMConfig.wish_timeout_for(cfg.model),
	}
	_llm_client().request("event", messages, _on_vision_card_done, opts)


func _on_vision_card_done(r: Dictionary) -> void:
	_wish_confirm_btn.disabled = false
	## 截断修复：SVG 有头无尾 = 被 max_tokens 截断，重试一次给更大预算
	var raw := String(r.get("text", ""))
	if not _wish_retried and bool(r.get("ok", false)) 			and raw.contains("<svg") and not raw.contains("</svg>"):
		_wish_retried = true
		_wish_feedback.text = "上一次被截断了，正在用更大预算重画…"
		_request_vision_card(_llm_config(), true)
		return
	_wish_retried = false
	if not bool(r.get("ok", false)):
		_wish_feedback.text = "创作失败（%s）：稍后再试或换个描述。" % String(r.get("reason", "?"))
		return
	var text := String(r.get("text", ""))
	var svg := String(r.get("svg", ""))
	var bitmap := String(r.get("image", ""))
	if svg.is_empty() and not bitmap.is_empty():
		svg = "BITMAP:" + bitmap          ## 模型直接回了位图，走位图路径
	## 卡牌机制：AI 的 JSON；没给就用文字词表折算兜底
	var def := WishCardFactory.parse_ai_card(text)
	var card: StsCard
	if def.is_empty():
		card = WishCardFactory.make("涂鸦造物", run.level_index)
	else:
		card = WishCardFactory.make_from_ai(def, run.level_index, Affection.level())
	## 效果层：竞技禁用（p95 超限）——查缓存命中，禁用卡不发放
	var pr_now := EffectPricing.price_cached(card, run.level_index,
			EffectPricing.SAMPLES, false)
	if bool(pr_now.get("banned", false)):
		run.wish_used = maxi(0, run.wish_used - 1)
		_toast("这张卡被判「竞技禁用」（p95 超限），暂不发放，许愿额度已退回")
		_close_wish_panel()
		return
	## 效果层：高费卡限量（试玩档「限获取」）——超过上限则退回许愿额度
	if not run.can_acquire(card):
		run.wish_used = maxi(0, run.wish_used - 1)
		_toast("这张卡超模且已达持有上限（cost 3 最多 %d 张），许愿额度已退回"
				% RunState.MAX_TIER3)
		_close_wish_panel()
		return
	run.deck.append(card)
	## 组合审计预热：200ms 限时，算不完下次继续（缓存累积），不卡界面（2026-11-10）
	run.prewarm_combo_audit()
	## 当前战斗立刻到手牌（手牌未满时）——画完就能看见、就能打；
	## 手牌已满则进抽牌堆（下一抽即得）。两种都同步牌堆数字。
	var got_in_hand := false
	if combat != null and combat.over == StsCombat.Result.RUNNING:
		if combat.hand.size() < combat.hand_size():
			combat.hand.append(card)
			_rebuild_hand()
			got_in_hand = true
		else:
			combat.draw_pile.append(card)
		_update_pile_counts()
	_wish_pending_card = card
	_wish_pending_name = StsCardPool.card_name(card.id)
	_close_wish_panel()
	SfxNode.play("ui_click")
	_toast("🖍 新卡已入手：%s（%s）" % [_wish_pending_name,
			"已到手牌" if got_in_hand else "已进抽牌堆，下一抽即得"])
	## 卡面四路：face token（程序化）> SVG > 位图 > 像素草图兜底
	var face := WishCardFactory.parse_ai_face(def)
	if not face.is_empty():
		var fpath := ImageGenClient.CACHE_DIR.path_join(
				"wish_face_%s.png" % _wish_pending_card.id.sha256_text().substr(0, 12))
		if not CardFace.render_png(face, fpath).is_empty():
			_wish_pending_card.art_path = fpath
			_toast("🎨 AI 画好了：%s" % _wish_pending_name)
		else:
			_fallback_sketch()
	elif svg.begins_with("BITMAP:"):
		_set_card_bitmap(_wish_pending_card, svg.substr(7))
	elif not svg.is_empty():
		var out := ImageGenClient.CACHE_DIR.path_join(
				"wish_svg_%s.png" % _wish_pending_card.id.sha256_text().substr(0, 12))
		if WishCardFactory.render_svg_png(svg, out):
			_wish_pending_card.art_path = out
			_toast("🎨 AI 画好了：%s" % _wish_pending_name)
		else:
			_fallback_sketch()
	else:
		_fallback_sketch()
	if _status_label != null:
		_status_label.text = "🎨 卡牌创作完成：%s（已进牌组）" % _wish_pending_name
	_wish_pending_card = null


func _set_card_bitmap(card: StsCard, uri: String) -> void:
	## 模型直接返回位图（data URI）：解码存盘挂卡面
	var png_path := ImageGenClient.CACHE_DIR.path_join(
			"wish_bm_%s.png" % card.id.sha256_text().substr(0, 12))
	if uri.begins_with("data:") and uri.contains("base64,"):
		var bin := Marshalls.base64_to_raw(uri.substr(uri.find("base64,") + 7))
		var img := Image.new()
		if img.load_png_from_buffer(bin) == OK:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ImageGenClient.CACHE_DIR))
			if img.save_png(png_path) == OK:
				card.art_path = png_path
				_toast("🎨 AI 画好了：%s" % _wish_pending_name)
				return
	_fallback_sketch()


func _fallback_sketch() -> void:
	## AI 没画出可用的图：像素草图兜底（玩家的卡不落空）
	if _wish_pending_card == null:
		return
	var ph := WishCardFactory.placeholder_png(_wish_pending_name, _wish_pending_card.id)
	if not ph.is_empty():
		_wish_pending_card.art_path = ph
	_float_text(Vector2(size.x * 0.5, 180.0),
			"AI 没画出图，先用像素草图顶上", Color(1.0, 0.8, 0.5), UiKit.FS_XS)


func _on_wish_image_done(ok: bool, path: String, reason: String) -> void:
	if ok and not path.is_empty() and _wish_pending_card != null:
		_wish_pending_card.art_path = path     ## 无缝替换成 AI 图
		_float_text(Vector2(size.x * 0.5, 150.0),
				"愿望已绘制：%s" % _wish_pending_name, Color(0.6, 0.95, 1.0), UiKit.FS_S)
		if _status_label != null:
			_status_label.text = "🎨 愿望已绘制：%s（已进牌组）" % _wish_pending_name
		SfxNode.play("fx_ult_ready")
	elif not ok:
		_float_text(Vector2(size.x * 0.5, 180.0),
				"AI 没画成（%s），像素草图先顶上" % reason,
				Color(1.0, 0.75, 0.5), UiKit.FS_XS)
		if _status_label != null:
			_status_label.text = "✏ AI 没画成（%s），用像素草图顶上" % reason
	_wish_pending_card = null


## 终结技「深度思考」入口（左下角，牌堆图标上方）：
## 得意鲸鱼脸当按钮贴图——充能不满灰暗，满了亮起脉冲；下挂充能条。
func _build_ult_ui() -> void:
	_ult_btn = TextureButton.new()
	_ult_btn.name = "UltButton"
	_ult_btn.ignore_texture_size = true
	_ult_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_ult_btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if ResourceLoader.exists("res://assets/art/ult-dafish.png"):
		_ult_btn.texture_normal = load("res://assets/art/ult-dafish.png")
	_ult_btn.custom_minimum_size = Vector2(56, 56)
	_ult_btn.size = Vector2(56, 56)
	_ult_btn.tooltip_text = "深度思考（充能 %d/%d，满了点我）" % [0, StsCombat.ULT_MAX]
	_ult_btn.modulate = Color(0.42, 0.46, 0.55, 0.8)     # 未充能：灰暗
	_ult_btn.disabled = true
	_ult_btn.pressed.connect(_cast_ult)
	add_child(_ult_btn)

	_ult_bar_bg = ColorRect.new()
	_ult_bar_bg.color = UiKit.LINE.darkened(0.45)
	_ult_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ult_bar_bg)
	_ult_bar = ColorRect.new()
	_ult_bar.color = Color(0.45, 0.88, 1.0)
	_ult_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ult_bar)
	_ult_label = UiKit.label("", UiKit.FS_XS, UiKit.TEXT_DIM)
	_ult_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ult_label)


func _update_ult_ui() -> void:
	if _ult_btn == null or combat == null:
		return
	var ready := combat.can_cast_ult()
	var pct := clampf(float(combat.ult_charge) / float(StsCombat.ULT_MAX), 0.0, 1.0)
	_ult_bar_bg.size = Vector2(56, 5)
	_ult_bar.size = Vector2(56.0 * pct, 5)
	_ult_label.text = "%d%%" % roundi(pct * 100.0)
	_ult_btn.disabled = not ready or _ult_playing
	if ready and not _ult_playing:
		_ult_btn.modulate = Color.WHITE
		_ult_btn.tooltip_text = "深度思考！点我释放（无视格挡 %d）" % StsCombat.ULT_DAMAGE
		if _ult_btn.get_meta("pulsing", false) == false:
			_ult_btn.set_meta("pulsing", true)
			var tw := _ult_btn.create_tween().set_loops()
			tw.tween_property(_ult_btn, "modulate", Color(1.35, 1.35, 1.15), 0.4)
			tw.tween_property(_ult_btn, "modulate", Color.WHITE, 0.4)
	else:
		_ult_btn.set_meta("pulsing", false)
		_ult_btn.modulate = Color(0.42, 0.46, 0.55, 0.8)
		_ult_btn.tooltip_text = "深度思考（充能 %d/%d）" % [combat.ult_charge, StsCombat.ULT_MAX]


## 终结技充满的瞬间：一声提示 + 按钮亮起脉冲
func _on_ult_ready(ready: bool) -> void:
	if ready:
		SfxNode.play("fx_ult_ready")
	_update_ult_ui()


## 释放终结技：锁操作 → 全屏演出 → hit_moment 时结算 + 震屏 → 收尾衔接。
func _cast_ult() -> void:
	if _ult_playing or _busy or combat == null or not combat.can_cast_ult():
		return
	_ult_playing = true
	_update_ult_ui()
	_send_btn.disabled = true
	_end_turn_button.disabled = true
	var cine := UltCinematic.new()
	cine.name = "UltCinematic"
	add_child(cine)
	cine.hit_moment.connect(func() -> void:
		var dealt := combat.cast_ult()
		# 受击演出：红闪 + 纵向抖动 + 大额飘字（与普攻同款，主人钦定的手感）
		if _enemy_sprite != null and _fx_enabled:
			var tw := _enemy_sprite.create_tween()
			tw.tween_property(_enemy_sprite, "modulate", Color(1.6, 1.6, 2.2), 0.06)
			tw.tween_property(_enemy_sprite, "modulate", Color(2.2, 0.8, 0.8), 0.08)
			tw.tween_property(_enemy_sprite, "modulate", Color.WHITE, 0.2)
			_enemy_shake_vertical(6, 16.0)
		_float_text(_enemy_root.position + Vector2(_enemy_root.size.x * 0.5, 24.0),
				"推理 %d" % dealt, Color(0.55, 0.9, 1.0), UiKit.FS_L)
		_refresh_hud()
		_shake(10.0, 0.3))
	cine.finished.connect(func() -> void:
		_ult_playing = false
		_update_ult_ui()
		if combat.over == StsCombat.Result.WIN:
			await get_tree().create_timer(0.3).timeout
			_finish_battle(true)
		elif combat.over == StsCombat.Result.RUNNING:
			_send_btn.disabled = false
			_end_turn_button.disabled = false)


## 牌堆/弃牌堆图标（左下角，竖排：上牌堆下弃牌）+ 查看面板（卡牌网格，置顶）
func _build_pile_ui() -> void:
	for cfg in [{"mode": 0, "tex": "res://assets/art/icon-pile-draw.png", "name": "PileDrawIcon"},
			{"mode": 1, "tex": "res://assets/art/icon-pile-discard.png", "name": "PileDiscardIcon"}]:
		var icon := TextureRect.new()
		icon.name = String(cfg["name"])
		if ResourceLoader.exists(String(cfg["tex"])):
			icon.texture = load(String(cfg["tex"]))
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.custom_minimum_size = Vector2(56, 56)
		icon.size = Vector2(56, 56)
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		var mode := int(cfg["mode"])
		icon.gui_input.connect(_on_pile_icon_input.bind(mode))
		icon.mouse_entered.connect(func() -> void:
			icon.modulate = Color(1.25, 1.25, 1.25)
			if _status_label != null:
				_status_label.text = "点开看%s里有哪些牌" % ("抽牌堆" if mode == 0 else "弃牌堆"))
		icon.mouse_exited.connect(func() -> void:
			icon.modulate = Color.WHITE)
		add_child(icon)
		if mode == 0:
			_pile_draw_icon = icon
		else:
			_pile_discard_icon = icon
		var cnt := UiKit.label("0", UiKit.FS_XS, UiKit.TEXT_DIM)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cnt)
		if mode == 0:
			_pile_draw_count = cnt
		else:
			_pile_discard_count = cnt

	# 查看面板：只显示卡牌（StsCardView 网格 3 列，滚轮翻看），打开时置顶
	_pile_panel = PanelContainer.new()
	_pile_panel.name = "PilePanel"
	_pile_panel.add_theme_stylebox_override("panel",
			UiKit.flat(UiKit.PANEL_2, UiKit.ACCENT, 2, UiKit.SP_3, UiKit.EL_2))
	_pile_panel.visible = false
	_pile_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_pile_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pile_panel.add_child(scroll)

	var grid := GridContainer.new()
	grid.name = "PileGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UiKit.SP_2)
	grid.add_theme_constant_override("v_separation", UiKit.SP_2)
	scroll.add_child(grid)


func _on_pile_icon_input(event: InputEvent, mode: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed 			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_toggle_pile_panel(mode)
		accept_event()


## 打开/关闭牌堆查看面板（mode：0 抽牌堆 ｜ 1 弃牌堆 ｜ -1 关闭）
func _toggle_pile_panel(mode: int) -> void:
	if _pile_panel == null or combat == null:
		return
	if _pile_panel_mode == mode or mode < 0:
		_pile_panel.visible = false
		_pile_panel_mode = -1
		return
	_pile_panel_mode = mode
	var pile := combat.draw_pile if mode == 0 else combat.discard_pile
	## grid 挂在 ScrollContainer 里（滚轮翻看），不能 get_node 直接子级——会 Nil 闪退
	var grid := _pile_panel.find_child("PileGrid", true, false) as GridContainer
	if grid == null:
		return
	for c in grid.get_children():
		c.queue_free()
	var sorted := pile.duplicate()
	sorted.sort_custom(func(a: StsCard, b: StsCard) -> bool:
		if a.kind != b.kind:
			return a.kind < b.kind
		return a.id < b.id)
	for c in sorted:
		var view := StsCardView.new()
		view.setup(c)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.set_playable(true)
		grid.add_child(view)
	_pile_panel.move_to_front()
	_pile_panel.z_index = 100
	_pile_panel.visible = true
	SfxNode.play("ui_click")


## 图标计数 + 面板开着时实时刷新
func _update_pile_counts() -> void:
	if combat == null:
		return
	if _pile_draw_count != null:
		_pile_draw_count.text = str(combat.draw_pile.size())
	if _pile_discard_count != null:
		_pile_discard_count.text = str(combat.discard_pile.size())
	if _pile_panel != null and _pile_panel.visible:
		_toggle_pile_panel(_pile_panel_mode)   ## 重开 = 重建卡牌网格


## AI 娘脉冲：运作一下（缩放弹动 + 青光闪）——指令到达的反馈
func _companion_pulse() -> void:
	if _companion == null or not is_instance_valid(_companion):
		return
	_companion.pulse()


## 指令投递：一枚发光指令球从对话框飞向 AI 娘（主人钦定：攻/防都经她中转）
func _maid_relay() -> void:
	if not _fx_enabled or _companion == null:
		return
	var orb := TextureRect.new()
	orb.texture = _glow_circle_texture(Color(0.31, 0.76, 0.97, 0.95))
	orb.size = Vector2(34, 34)
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dlg := get_node_or_null("ActionDialog") as Control
	var from := (dlg.position + Vector2(dlg.size.x * 0.35, dlg.size.y * 0.4)) 			if dlg != null else size * 0.5
	var to := _companion.position + Vector2(_companion.size.x * 0.44, _companion.size.y * 0.35)
	orb.position = from - Vector2(17, 17)
	_fx_root.add_child(orb)
	SfxNode.play("deal")
	var tw := orb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "position", to - Vector2(17, 17), 0.26) 			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(orb, "scale", Vector2(0.6, 0.6), 0.26)
	await tw.finished
	orb.queue_free()
	_companion_pulse()


## AI 娘头顶「运作中…」小气泡（0.5s 自毁）
func _maid_working_bubble() -> void:
	if not _fx_enabled or _companion == null:
		return
	var l := UiKit.label("… 运作中", UiKit.FS_XS, Color(0.31, 0.76, 0.97))
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.position = _companion.position + Vector2(_companion.size.x * 0.44 - 30, _companion.size.y * 0.18)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_root.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 26.0, 0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(func() -> void: l.queue_free())


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
	if _token_label:
		_token_label.position = Vector2(AI_X + 8.0, H - 378.0)
		_token_label.size = Vector2(W - AI_X - PAD - 8.0, 24.0)
	if _player_status_label:
		_player_status_label.position = Vector2(AI_X + 8.0, H - 402.0)
		_player_status_label.size = Vector2(W - AI_X - PAD - 8.0, 22.0)
	# 牌堆/弃牌堆图标：左侧栏底部空档（主人 2026-11-01 圈选位置），上牌堆下弃牌
	if _pile_draw_icon != null:
		_pile_draw_icon.position = Vector2(36.0, H - 150.0)
		_pile_draw_icon.size = Vector2(56, 56)
		_pile_discard_icon.position = Vector2(36.0, H - 76.0)
		_pile_discard_icon.size = Vector2(56, 56)
		_pile_draw_count.position = Vector2(98.0, H - 134.0)
		_pile_discard_count.position = Vector2(98.0, H - 60.0)
	# 终结技按钮：牌堆图标上方（充能条在按钮下沿、百分比在右侧）
	if _ult_btn != null:
		_ult_btn.position = Vector2(36.0, H - 228.0)
		_ult_btn.size = Vector2(56, 56)
		_ult_bar_bg.position = Vector2(36.0, H - 168.0)
		_ult_bar.position = Vector2(36.0, H - 168.0)
		_ult_label.position = Vector2(98.0, H - 174.0)
	# 许愿卡按钮：终结技按钮上方
	if _wish_btn != null:
		_wish_btn.position = Vector2(36.0, H - 306.0)
		_wish_btn.size = Vector2(56, 56)
	if _wish_panel != null:
		# 用当前画布尺寸居中（不要用固定 1600 基准：隐藏桌面/DPI 下 size 会变）
		_wish_panel.position = (size - _wish_panel.size) * 0.5
	if _pile_panel != null:
		## 用逻辑视口居中（高 DPI 下 size 可能是物理像素，固定基准会让面板跑出屏幕）
		_pile_panel.size = Vector2(580, 660)
		var vp_pile := get_viewport_rect().size
		_pile_panel.position = (vp_pile - _pile_panel.size) * 0.5

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
	## 组合审计标记（2026-11-10 主人拍板：**判 block 不拦，只标记**）——
	## 越界组合照打，只在开战时提示一次，处置权留给后面调平衡。
	_show_combo_mark()
	combat.set_refill(StsCombat.refill_for(run.ai.id))
	combat.set_ai_id(run.ai.id)
	if not combat.ult_ready_changed.is_connected(_on_ult_ready):
		combat.ult_ready_changed.connect(_on_ult_ready)
	_update_ult_ui()
	# AI 事件引擎 CHAIN_HEAD：本场首张牌从第 2 阶起步（标记只在 run meta，读后清）
	var chain_head := LLMEventEngine.chain_head_pending(run)
	if chain_head > 0:
		combat.seq_streak = 1
		run.set_meta(&"llm_event_chain_head", 0)

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
		# 精英怪（15%）：红光光环 + 脚下宝箱角标，打倒掉道具
		if combat.is_elite:
			var aura := TextureRect.new()
			aura.name = "EliteAura"
			aura.texture = _glow_circle_texture(Color(0.9, 0.15, 0.15, 0.45))
			aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
			aura.position = _enemy_sprite.position - Vector2(34, 30)
			aura.size = _enemy_sprite.size + Vector2(68, 60)
			_enemy_root.add_child(aura)
			_enemy_root.move_child(aura, 0)
			var pulse := aura.create_tween().set_loops()
			pulse.tween_property(aura, "modulate:a", 0.45, 0.8) 					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			pulse.tween_property(aura, "modulate:a", 1.0, 0.8) 					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			var chest := TextureRect.new()
			chest.name = "EliteChest"
			chest.texture = load("res://assets/art/chest.png")
			chest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chest.size = Vector2(52, 52)
			chest.position = Vector2(90.0 - 26.0, 140.0 - 10.0)
			_enemy_root.add_child(chest)

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
	_refresh_llm_config()
	_refresh_item_lists()      ## 道具耐久每场开战扣 1，侧栏同步
	_setup_banter()

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
	## 卡面改版后（2026-11-06）：正面就是立绘本身，大图预览直接放大立绘
	if _card_tex_cache.has(card.id):
		return _card_tex_cache[card.id]
	var img: Image = null
	if card.art_path != "" and ResourceLoader.exists(card.art_path):
		var at: Resource = load(card.art_path)
		if at is Texture2D:
			img = (at as Texture2D).get_image()
	if img == null:
		img = Image.create_empty(750, 1130, false, Image.FORMAT_RGBA8)
		img.fill(UiKit.PANEL)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.resize(750, 1130, Image.INTERPOLATE_LANCZOS)
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


## 状态徽章底色（圆角 + 半透明，让状态条看起来像徽章而不是裸文字）
func _status_badge_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 7.0
	sb.content_margin_right = 7.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	return sb


## 状态条文本：「降智2 · 中毒3」；永久状态（回合数 ≥90）不带数字
func _status_text(box: Dictionary) -> String:
	if box.is_empty():
		return ""
	var parts: Array[String] = []
	for id in box.keys():
		var st: Dictionary = box[id]
		var label := String(EffectSpec.STATUSES.get(String(id), {}).get("label", String(id)))
		var turns := int(st.get("turns", 0))
		if turns >= 90:
			parts.append(label)
		else:
			parts.append("%s%d" % [label, turns])
	return " · ".join(parts)


func _refresh_hud() -> void:
	if combat == null:
		return
	_enemy_hp_label.text = "故障强度 %d/%d" % [combat.enemy_hp, combat.enemy_max_hp]
	var er := clampf(float(combat.enemy_hp) / float(maxi(1, combat.enemy_max_hp)), 0.0, 1.0)
	_enemy_fill.size = Vector2(ENEMY_W * er, 10.0)
	_enemy_block_label.text = "格挡 %d" % combat.enemy_block if combat.enemy_block > 0 else ""
	if _enemy_status_label != null:
		_enemy_status_label.text = _status_text(combat.e_status)
	if _player_status_label != null:
		_player_status_label.text = _status_text(combat.p_status)
	_intent_label.text = "⚡%d/%d ｜ %s" % [combat.energy, StsCombat.ENERGY_PER_TURN,
			_intent_text()]
	var piles := get_node_or_null("BottomSide/PileCounts") as Label
	if piles != null:
		piles.text = "抽 %d ｜ 弃 %d" % [combat.draw_pile.size(), combat.discard_pile.size()]
	_update_pile_counts()
	_update_ult_ui()
	if _token_label != null and run != null:
		_token_label.text = "Token 额度 %dK/%dK" % [run.hp, RunState.MAX_HP]


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
		if not _can_discard():
			_status_label.text = "本回合弃牌次数用完（上限 %d 张），先结束回合。" \
					% _discard_limit()
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
	## 能量不足就停下：剩下的牌留在手里，下回合再打
	while not combat.hand.is_empty() and combat.over == StsCombat.Result.RUNNING \
			and combat.can_play(combat.hand[0]):
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
		# AI 娘连段喝彩：每张牌结算恰调一次（AIBanter 内部按 ≥3 阶/2 次/隔 2 回合过滤）
		if kind == "attack" and _banter != null:
			_banter.on_streak(int(ev.get("streak", 1)), combat.turn)
		if kind == "rice":
			_float_text(Vector2(size.x * 0.5, size.y - CARD_H - 90.0),
					"吃掉白米饭 %d/%d" % [int(ev.get("value", 0)), StsCombat.RICE_AWAKE],
					Color(1.0, 0.9, 0.55), UiKit.FS_M)
			SfxNode.play("fx_eat")
			# 吃饭演出：女仆切「吃饭立绘」，嚼 1 秒后切回（主人钦定）
			if _companion != null:
				_companion.set_stage("eat")
			get_tree().create_timer(1.1).timeout.connect(func() -> void:
				if is_instance_valid(_companion):
					_update_rice_hud())
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
			# 指令投递给 AI 娘 → 她运作 → 消耗额度输出（主人钦定中转演出）
			await _maid_relay()
			_maid_working_bubble()
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
			# 隔离指令投递给 AI 娘 → 她撑起隔离罩（防止故障恶化）
			await _maid_relay()
			_maid_working_bubble()
			if _companion != null:
				_spawn_fx("res://assets/art/fx-shield.png",
						_companion.position + Vector2(_companion.size.x * 0.44 - 110,
						_companion.size.y * 0.3 - 110),
						Vector2(220, 220), 0.0, "pop", Color.WHITE, 0.8)
			_float_text(Vector2(size.x * 0.5, size.y - CARD_H - 90.0),
					"隔离 +%d" % int(ev.get("value", 0)), Color(0.31, 0.64, 0.88), UiKit.FS_M)
			SfxNode.play("fx_block")
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
			_rice_label.text = "白米饭 %d/%d ｜ 好感 Lv.%d" % [combat.rice_eaten,
				StsCombat.RICE_AWAKE, Affection.level()]
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
## 战斗特效贴图：生成 → 入场动画 → 自毁（2026-11-01 主人钦定的特效系统）
## shape: "slash"（斩击扫过）｜"pop"（弹出+脉冲）｜"fade"（淡入停留淡出）
func _spawn_fx(path: String, pos: Vector2, fx_size: Vector2, rot_deg: float,
			shape: String, tint: Color = Color.WHITE, dur := 0.5) -> void:
	if not _fx_enabled or not ResourceLoader.exists(path):
		return
	var fx := TextureRect.new()
	fx.texture = load(path)
	fx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fx.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.position = pos
	fx.size = fx_size
	fx.pivot_offset = fx_size * 0.5
	fx.rotation_degrees = rot_deg
	fx.modulate = tint
	_fx_root.add_child(fx)
	var tw := fx.create_tween()
	match shape:
		"slash":
			fx.scale = Vector2(1.7, 1.7)
			fx.modulate.a = 0.0
			tw.set_parallel(true)
			tw.tween_property(fx, "scale", Vector2(0.95, 0.95), dur * 0.6) 					.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(fx, "modulate:a", 1.0, dur * 0.25)
			tw.tween_property(fx, "modulate:a", 0.0, dur * 0.4).set_delay(dur * 0.5)
		"pop":
			fx.scale = Vector2(0.5, 0.5)
			fx.modulate.a = 0.0
			tw.set_parallel(true)
			tw.tween_property(fx, "scale", Vector2.ONE, dur * 0.35) 					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(fx, "modulate:a", 1.0, dur * 0.2)
			tw.tween_property(fx, "modulate:a", 0.0, dur * 0.35).set_delay(dur * 0.55)
		"fade":
			fx.modulate.a = 0.0
			tw.set_parallel(true)
			tw.tween_property(fx, "modulate:a", 1.0, dur * 0.25)
			tw.tween_property(fx, "modulate:a", 0.0, dur * 0.4).set_delay(dur * 0.55)
	tw.chain().tween_callback(func() -> void: fx.queue_free())


## 敌人受击：上下抖动（主人钦定）——纵向为主的抖动
func _enemy_shake_vertical(times := 4, amp := 12.0) -> void:
	if _enemy_sprite == null:
		return
	var base := Vector2(90.0 - _enemy_sprite.size.x * 0.5, 150.0 - _enemy_sprite.size.y)
	var tw := _enemy_sprite.create_tween()
	for i in times:
		var off := base + Vector2(0.0, randf_range(-amp, amp) * (1.0 - float(i) / float(times)))
		tw.tween_property(_enemy_sprite, "position", off, 0.045)
	tw.tween_property(_enemy_sprite, "position", base, 0.05)
func _enemy_hit_fx(dmg: int, tag: String = "") -> void:
	if _enemy_sprite == null:
		return
	_flash(Color(1.0, 0.45, 0.45), 0.16)
	# 斩击特效：斜向扫过敌人（每次随机角度，不重样）
	var slash_pos := _enemy_root.position + _enemy_root.size * 0.5 			- Vector2(120, 120) + Vector2(randf_range(-14, 14), randf_range(-14, 14))
	_spawn_fx("res://assets/art/fx-slash.png", slash_pos, Vector2(240, 240),
			randf_range(-24, 24), "slash", Color.WHITE, 0.4)
	SfxNode.play("fx_slash")
	var tw := _enemy_sprite.create_tween()
	tw.tween_property(_enemy_sprite, "modulate", Color(2.2, 0.8, 0.8), 0.05)
	tw.tween_property(_enemy_sprite, "modulate", Color.WHITE, 0.18)
	# 上下抖动（主人钦定：受击纵向抖）
	_enemy_shake_vertical(4, 12.0)
	SfxNode.play("fx_ehit")
	var txt := "-%d" % dmg
	if not tag.is_empty():
		txt = "%s %s" % [tag, dmg]
	_float_text(_enemy_root.position + Vector2(_enemy_root.size.x * 0.5, 24.0),
			txt, Color(1.0, 0.42, 0.42), UiKit.FS_L)


## 敌人受击：上下抖动（主人钦定）——纵向为主的抖动
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
	_discards_left = _discard_limit()   ## 新回合弃牌次数回满
	_update_discard_btn()
	if _fx_enabled:
		await get_tree().create_timer(0.25).timeout

	var events: Array[Dictionary]
	if _ai_enemy_enabled():
		# AI 对手：LLM 先出词，超时/解析烂 → apply_ai_action 内部 local_choose 兜底
		events = await _ai_enemy_turn()
	else:
		events = combat.end_turn()
	for e in events:
		var kind := String(e.get("kind", ""))
		if kind == "enemy_attack":
			if _fx_enabled:
				# 红爪击特效砸在玩家对话框上（敌方攻击演出）
				var dlg := get_node_or_null("ActionDialog") as Control
				if dlg != null:
					_spawn_fx("res://assets/art/fx-claw.png",
							dlg.position + dlg.size * 0.5 - Vector2(130, 130),
							Vector2(260, 260), randf_range(-12, 12), "slash",
							Color.WHITE, 0.45)
					SfxNode.play("fx_slash")
				await _enemy_attack_fx(int(e.get("value", 0)), int(e.get("dealt", 0)),
						int(e.get("blocked", 0)))
		elif kind == "enemy_defend":
			if _fx_enabled:
				# 蓝色调盾框在敌人身上展开（敌方防御演出）
				_spawn_fx("res://assets/art/fx-shield.png",
						_enemy_root.position + _enemy_root.size * 0.5 - Vector2(120, 120),
						Vector2(240, 240), 0.0, "pop",
						Color(0.55, 0.75, 1.0), 0.7)
				SfxNode.play("fx_edef")
				_float_text(_enemy_root.position + Vector2(_enemy_root.size.x * 0.5, 44.0),
						"+%d 防" % int(e.get("value", 0)), Color(0.31, 0.64, 0.88), UiKit.FS_M)
				await get_tree().create_timer(0.3).timeout
		elif kind == "enemy_charge":
			if _fx_enabled:
				# 紫色蓄力光环（不动原防御/攻击演出节奏，只加同族特效）
				_spawn_fx("res://assets/art/fx-shield.png",
						_enemy_root.position + _enemy_root.size * 0.5 - Vector2(110, 110),
						Vector2(220, 220), 0.0, "pop", Color(0.80, 0.58, 1.0), 0.6)
				SfxNode.play("fx_edef")
				_float_text(_enemy_root.position + Vector2(_enemy_root.size.x * 0.5, 44.0),
						"+%d 蓄力" % int(e.get("value", 0)), Color(0.80, 0.58, 1.0), UiKit.FS_M)
				await get_tree().create_timer(0.3).timeout
		elif kind == "enemy_mark":
			if _fx_enabled:
				var mode := String(e.get("mark_mode", ""))
				SfxNode.play("hand_small")
				_float_text(_enemy_root.position + Vector2(_enemy_root.size.x * 0.5, 44.0),
						"标记 %s" % mode, Color(1.0, 0.55, 0.32), UiKit.FS_M)
				await get_tree().create_timer(0.3).timeout
			if _banter != null:
				_banter.notify_enemy_line(_enemy_line_of(e))
		elif kind == "enemy_taunt":
			if _fx_enabled:
				SfxNode.play("hand_big")
				_float_text(_enemy_root.position + Vector2(_enemy_root.size.x * 0.5, 44.0),
						"首位加成吞噬！", Color(0.85, 0.55, 1.0), UiKit.FS_M)
				await get_tree().create_timer(0.3).timeout
			if _banter != null:
				_banter.notify_enemy_line(_enemy_line_of(e))

	# AI 娘：受击后看一眼额度（AIBanter 内部去重，首次 <30% 只播一次）
	if _banter != null and combat.over == StsCombat.Result.RUNNING:
		_banter.on_hp_changed(combat.hp, combat.max_hp)

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
	if _banter != null:
		_banter.stop_battle()
	## 组合审计续算：趁玩家看结算画面的空档把剩余组补算完（2026-11-10）
	run.prewarm_combo_audit()
	if win:
		SfxNode.play("win")
		var gain := run.win_battle(combat, level)
		if combat.is_elite:
			var it := run.grant_elite_chest()
			if it != null:
				_refresh_item_lists()   ## 宝箱道具按 Skill/MCP 进侧栏
				_overlay_body.text += "
📦 精英宝箱：获得【%s】！" % it.display_name
		_overlay_title.text = "胜利"
		_overlay_body.text = "问题【%s】已解决！\n本战输出 %d 伤害额度 ｜ 剩余额度 %dK（恢复 %dK）\n算力 +%d ｜ 金币 +%d ｜ Deep Sick 好感 +%d\n下一步：往卡组里加一张牌。" % [
			level.enemy_name, combat.damage_dealt, run.hp,
			StsCombat.HEAL_ON_WIN, gain, run.last_gold_gain, int(run.last_affection_gain)]
		_pop_overlay()
		level_cleared.emit(run.score)
	else:
		SfxNode.play("lose")
		run.lose_battle(combat)
		_overlay_title.text = "战败"
		_overlay_body.text = "额度耗尽，被【%s】压制（剩余故障强度 %d/%d）。\n金币 +%d ｜ Deep Sick 好感 +%d（饭没白喂）\n提示：熔断保护能隔离故障、防止额度流失——\n看准敌人的「攻击 N」意图再开防。" % [
			level.enemy_name, combat.hp, combat.max_hp, run.last_gold_gain, int(run.last_affection_gain)]
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
	if _fx_enabled and combat != null and combat.over == StsCombat.Result.WIN:
		await _victory_exit()
	advance_requested.emit()


## 胜利谢幕（2026-11-01 主人钦定）：侧边栏向左平滑滑出、对话框向下平滑滑出、
## 然后全屏压黑——黑幕接主控的裂隙转场，露出奖励界面。
func _victory_exit() -> void:
	_busy = true
	_send_btn.disabled = true
	_end_turn_button.disabled = true
	var rail := get_node_or_null("HudLeft") as Control
	var dlg := get_node_or_null("ActionDialog") as Control
	var tw := create_tween()
	tw.set_parallel(true)
	if rail != null:
		tw.tween_property(rail, "position:x", rail.position.x - rail.size.x - 60.0, 0.5) 				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if dlg != null:
		tw.tween_property(dlg, "position:y", size.y + 60.0, 0.5) 				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var black := ColorRect.new()
	black.color = Color(0.012, 0.02, 0.04, 0.0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	tw.tween_property(black, "color:a", 1.0, 0.4).set_delay(0.2)
	await tw.finished
	black.color.a = 1.0


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
## 精英红光圈贴图：两档 alpha 实心圆（像素风无渐变）
func _glow_circle_texture(col: Color) -> ImageTexture:
	var d := 128
	var img := Image.create_empty(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d * 0.5, d * 0.5)
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(c) / (d * 0.5)
			if dist <= 1.0:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a if dist > 0.55 else col.a * 1.6))
	return ImageTexture.create_from_image(img)


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
func debug_open_wish_panel() -> void:
	## 视觉验收（--shot=wishpanel）：直接打开许愿画布（纯看图 + 代码雨背景）
	_open_wish_panel()


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
## 沙盒：秒杀当前敌人 → 走完整胜利链（谢幕→裂隙→奖励→门）
func debug_win_battle() -> void:
	if combat == null or combat.over != StsCombat.Result.RUNNING:
		return
	combat.enemy_hp = 0
	combat.over = StsCombat.Result.WIN
	_finish_battle(true)


## 沙盒：特效演示（斩击打敌人 / 盾框上对话框 / 爪击砸对话框）
func debug_fx_demo(kind: String) -> void:
	var dlg := get_node_or_null("ActionDialog") as Control
	match kind:
		"slash":
			if _enemy_sprite != null:
				_enemy_hit_fx(9, "体验")
		"shield":
			if dlg != null:
				_spawn_fx("res://assets/art/fx-shield.png",
						dlg.position + dlg.size * 0.5 - Vector2(110, 110),
						Vector2(220, 220), 0.0, "pop", Color.WHITE, 0.8)
				SfxNode.play("fx_block")
		"claw":
			if dlg != null:
				_spawn_fx("res://assets/art/fx-claw.png",
						dlg.position + dlg.size * 0.5 - Vector2(130, 130),
						Vector2(260, 260), randf_range(-12, 12), "slash",
						Color.WHITE, 0.5)
				SfxNode.play("fx_slash")


## 沙盒 F1：直接充满并释放终结技（免攒能量，反复看演出）
func debug_ult_demo() -> void:
	if combat == null or _ult_playing or combat.over != StsCombat.Result.RUNNING:
		return
	combat.ult_charge = StsCombat.ULT_MAX
	_update_ult_ui()
	_cast_ult()


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


## 效果层状态条（玩家|敌人），供冒烟断言
func debug_effect_status_text() -> String:
	var p := _player_status_label.text if _player_status_label != null else ""
	var e := _enemy_status_label.text if _enemy_status_label != null else ""
	return "%s|%s" % [p, e]


func debug_console_log() -> String:
	return _observer_note


# ─────────────────────────────────────────────────────────
#  LLM 接入：AI 对手 + AI 娘小鲸（battle-integration · 2026-11-03）
# ─────────────────────────────────────────────────────────
func _refresh_llm_config() -> LLMConfig:
	_llm_cfg = LLMConfig.load_from_disk()
	if _llm != null:
		_llm.setup(_llm_cfg)
	return _llm_cfg


func _llm_config() -> LLMConfig:
	if _llm_cfg == null:
		_llm_cfg = LLMConfig.load_from_disk()
	return _llm_cfg


func _llm_client() -> LLMClient:
	if _llm != null:
		return _llm
	_llm = LLMClient.new()
	_llm.name = "LLMClient"
	add_child(_llm)
	_llm.setup(_llm_config())
	return _llm


## AI 对手只在「AI 开启 + 普通战斗」生效；精英/Boss/关闭时完全走原 end_turn。
func _ai_enemy_enabled() -> bool:
	if combat == null or combat.over != StsCombat.Result.RUNNING:
		return false
	if _elite or (level != null and level.is_boss):
		return false
	var cfg := _llm_config()
	if not cfg.ai_opponent:
		return false          ## 主人 2026-11-05：敌人默认走本地规则，省 token
	return cfg.is_enabled()


## 一场战斗内稳定的 resolve_id：同槽位 + 同候选池哈希 → 迟到结果下回合直接复用。
func _ai_resolve_id() -> int:
	var li := 0 if run == null else int(run.level_index)
	return 17000 + li * 100


## AI 娘：挂 AIBanter（锚点=右侧 AI 娘），每场开一次。
func _setup_banter() -> void:
	if _banter == null:
		_banter = AIBanter.new()
		_banter.name = "AIBanter"
		add_child(_banter)
	_banter.setup(_companion, _banter_provider)
	_banter.battle_started()


## AI 娘台词 provider：必须立刻返回；异步 reply(text)。
## 失败/未接 AI → reply("")，AIBanter 播本地兜底，不阻塞演出。
func _banter_provider(job: Dictionary, reply: Callable) -> void:
	if not _llm_config().is_enabled():
		reply.call("")
		return
	var messages := [
		{"role": "system", "content": LLMPrompts.for_scene("dialog")},
		{"role": "user", "content": _banter_context_text(job)},
	]
	_llm_client().request("dialog", messages, func(r: Dictionary) -> void:
		if bool(r.get("ok", false)):
			reply.call(LLMParse.parse_dialogue(String(r.get("text", "")), AIBanter.MAX_CHARS))
		else:
			reply.call("")
	, {"timeout_s": ai_timeout})


func _banter_context_text(job: Dictionary) -> String:
	var hook := String(job.get("hook", ""))
	var ctx: Dictionary = job.get("context", {})
	match hook:
		AIBanter.H_OPENING:
			return "战斗刚开始，说一句开场。"
		AIBanter.H_CHEER:
			return "玩家刚打出 %d 阶连段（第 %d 回合），夸他一句。" % [
					int(ctx.get("streak", 0)), int(ctx.get("turn", 0))]
		AIBanter.H_DANGER:
			return "玩家 HP %d/%d，跌破 30%%，关心一句。" % [
					int(ctx.get("hp", 0)), int(ctx.get("max_hp", 0))]
		AIBanter.H_RETORT:
			return "敌人刚刚说：「%s」。回怼它。" % String(ctx.get("enemy_line", ""))
	return "说一句短台词。"


## 一次 AI 敌方决策：请求 + 思考气泡 + 3s 计时（当帧起算），先到者接演。
## apply_ai_action 内部自走完整敌方回合（含 start_turn），这里不再调 end_turn。
func _ai_enemy_turn() -> Array[Dictionary]:
	var legal := LLMOpponentPool.legal_actions(combat)
	var pool_hash := ",".join(_packed(legal))
	var snap := combat.ai_state_snapshot()
	var messages := [
		{"role": "system", "content": LLMPrompts.for_scene("observer")},
		{"role": "user", "content": _observer_snapshot_text(snap, legal)},
	]
	_ai_done = false
	_ai_action = ""
	_ai_reason = ""
	_ai_source = ""
	_show_ai_thinking(true)
	_llm_client().request("observer", messages, _on_ai_observer_done, {
		"resolve_id": _ai_resolve_id(),
		"pool_hash": pool_hash,
		"timeout_s": ai_timeout,
	})
	# 3s 预算：请求发出当帧起算；ignore_time_scale 防 hitstop 拖表
	var timer := get_tree().create_timer(ai_timeout, true, false, true)
	timer.timeout.connect(_on_ai_deadline)
	if not _ai_done:
		await ai_decision_ready
	_show_ai_thinking(false)
	if not _ai_reason.is_empty():
		_enemy_speak(_ai_reason)
	# 空/非法动作由 apply_ai_action 静默落 local_choose，台词照播
	return combat.apply_ai_action(_ai_action, _ai_reason)


func _on_ai_observer_done(r: Dictionary) -> void:
	if _ai_done:
		return
	_ai_done = true
	if bool(r.get("ok", false)):
		var parsed := LLMParse.parse_action(String(r.get("text", "")))
		_ai_action = String(parsed.get("action", ""))
		_ai_reason = String(parsed.get("line", ""))
		_ai_source = String(parsed.get("source", "null"))
	else:
		_ai_action = ""
		_ai_reason = ""
		_ai_source = String(r.get("reason", "fail"))
	ai_decision_ready.emit()


func _on_ai_deadline() -> void:
	if _ai_done:
		return
	_ai_done = true
	_ai_action = ""
	_ai_reason = ""
	_ai_source = "timeout"
	ai_decision_ready.emit()


func _observer_snapshot_text(snap: Dictionary, legal: Array) -> String:
	var mark := ""
	if bool(snap.get("mark_active", false)):
		mark = " 标记%s剩%d回合" % [
				String(snap.get("mark_mode", "")), int(snap.get("mark_turns_left", 0))]
	return "敌HP %d/%d 玩家HP %d/%d 回合%d 上回合 攻击×%d 发育×%d 连段阶%d%s 可用 %s" % [
		int(snap.get("enemy_hp", 0)), int(snap.get("enemy_max_hp", 1)),
		int(snap.get("player_hp", 0)), int(snap.get("player_max_hp", 1)),
		int(snap.get("turn", 0)),
		int(snap.get("attacks_last_turn", 0)), int(snap.get("grows_last_turn", 0)),
		int(snap.get("max_streak_last_turn", 0)), mark,
		", ".join(_packed(legal))]


func _packed(arr: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for v in arr:
		out.append(String(v))
	return out


## 敌人头顶「思考中…」气泡：纯演出，不锁输入。
func _show_ai_thinking(on: bool) -> void:
	if not _fx_enabled or _enemy_root == null or _fx_root == null:
		return
	if _ai_think == null:
		_ai_think = UiKit.label("观察者 · 思考中…", UiKit.FS_XS, Color(1.0, 0.78, 0.45))
		_ai_think.add_theme_constant_override("outline_size", 4)
		_ai_think.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_ai_think.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ai_think.visible = false
		_fx_root.add_child(_ai_think)
	if on:
		_ai_think.position = _enemy_root.position \
				+ Vector2(_enemy_root.size.x * 0.5 - 72.0, -16.0)
	_ai_think.visible = on


## 敌人台词飘字（≤26 字，不弹窗不锁输入）
func _enemy_speak(line: String) -> void:
	var text := line.strip_edges()
	if text.is_empty() or _enemy_root == null:
		return
	if text.length() > 26:
		text = text.substr(0, 26)
	_float_text(_enemy_root.position + Vector2(_enemy_root.size.x * 0.5 - 90.0, -8.0),
			text, Color(1.0, 0.72, 0.38), UiKit.FS_M)


func _enemy_line_of(e: Dictionary) -> String:
	var line := String(e.get("reason", "")).strip_edges()
	if line.is_empty():
		line = LLMOpponentPool.action_ui_name(String(e.get("ai_action", "")))
	return line


func _exit_tree() -> void:
	if _llm != null:
		_llm.shutdown()


# ── 测试用（battle-integration 验收）──────────────────────
func debug_ai_enabled() -> bool:
	return _ai_enemy_enabled()


func debug_ai_last() -> Dictionary:
	return {"action": _ai_action, "reason": _ai_reason, "source": _ai_source}


func debug_llm_client() -> LLMClient:
	return _llm_client()


func debug_banter() -> AIBanter:
	return _banter


## 测试/后续 GUI 热切换用：直接注入配置与假后端（不改盘上文件）
func debug_set_llm(cfg: LLMConfig, backend = null) -> void:
	_llm_cfg = cfg
	var c := _llm_client()
	c.setup(cfg)
	if backend != null:
		c.set_backend(backend)
