extends Node
## 屏幕路由：主菜单 → 关卡 → 奖励 → （商店）→ 下一关 ……
##
## 流程是**线性**的，没有关卡选择界面：按顺序闯 L1~L10。
## 每一关的洗牌种子不同（run_state.start_level 里按关卡 id 派生）。

const ArenaScene := preload("res://scripts/ui/arena.gd")
const RewardScene := preload("res://scripts/ui/reward.gd")
const MenuScene := preload("res://scripts/ui/main_menu.gd")
const AiSelectScene := preload("res://scripts/ui/ai_select.gd")
const ResultScene := preload("res://scripts/ui/result_screen.gd")
const MapScene := preload("res://scripts/ui/map_screen.gd")
const EventScene := preload("res://scripts/ui/event_screen.gd")
const RiftScene := preload("res://scripts/ui/rift_transition.gd")
const BurnoutScene := preload("res://scripts/ui/burnout_screen.gd")
const SandboxPanelScene := preload("res://scripts/ui/sandbox_panel.gd")
const ChibiRigScene := preload("res://scripts/ui/chibi_rig.gd")
const LLMDemoScene := preload("res://scripts/ui/llm_demo_screen.gd")
const PatchDemoScene := preload("res://scripts/ui/patch_demo_screen.gd")

var run := RunState.new()
var _current: Control = null
var _pending_level: LevelData = null
var _pending_elite := false
## 体验沙盒（F1）：面板 + 强制门类型
var _sandbox: Control = null
var _force_special := ""
## 视觉验收直达标记（命令行）
var _patch_demo_direct := false
var _wish_demo_direct := false
var _last_passed: bool = false
var _levels: Array[LevelData] = []

# ── LLM 接入（2026-11-03）──────────────────────────────
## 玩家自填配置 + 唯一网络出口；未启用时全部走原有本地逻辑。
var _llm_cfg: LLMConfig = null
var _llm_client: LLMClient = null
var _llm_event_rid := 0
var _llm_panel: Control = null


func _ready() -> void:
	## 命令行参数：--mute 静音 ｜ --patch-demo 直达更新演示
	## （Godot 惯例：-- 之后的才是 user args；这里两个来源都收，避免启动器漏 --）
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--mute":
			AudioServer.set_bus_mute(0, true)
		## 视觉验收直达：--patch-demo / --wish-panel 跳过主流程直开目标屏
		if a == "--patch-demo":
			_patch_demo_direct = true
	_levels = LevelPool.all_levels()
	_build_sandbox()
	get_window().title = "代码擂台 Code Arena"
	PixelTheme.install(self)
	GameSettings.load_from_disk()
	## 好感度跨局持久化（2026-11-18 修）：Affection.load() 之前**没有任何地方调用**，
	## 导致每次启动 points 都是内存初值 0，界面上永远显示 Lv.0（存档里写了也不读）。
	Affection.load()
	# LLM 接入：配置与网络客户端常驻（AI 关闭时 request 直接短路，零网络）
	_llm_cfg = LLMConfig.load_from_disk()
	_llm_client = LLMClient.new()
	_llm_client.name = "LLMClient"
	add_child(_llm_client)
	_llm_client.setup(_llm_cfg)
	# 实测调参器（Dev 工具，不进玩法）：F1 开关面板，F5 存 docs/ui-tune.json
	var tuner := UiTuner.new()
	add_child(tuner)
	for a in OS.get_cmdline_user_args():
		if a == "--tune":
			tuner.open()
	_show_menu()
	_maybe_capture()


func _swap(screen: Control) -> void:
	if _current != null:
		_current.queue_free()
	_current = screen
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	_themify(screen)


## ⚠ 给 Control 装主题（2026-11-18 修中文方框，必须每处都过它）
##
## 根因（真实窗口探针实测）：
##   Main 是纯 Node，界面/弹窗都 add_child 到它下面。而 Godot 的 theme
##   只在 **Control 树**里继承 —— Window.theme 和 Node 父级都**不传播**。
##   于是这些界面里的 Label 调 get_theme_font("font") 拿到的是
##   **引擎内置主题**里那个没有 CJK 的字体 → 中文全渲染成方框
##   （拉丁字母有系统 fallback，看着还行，所以容易被误判成"编码错误"）。
##
##   实测证据：
##     theme.get_font("font","Label") = FontFile#...615430   ← 我们设的中文字体（对）
##     leaf.theme = <Object#null>                            ← 没继承
##     leaf.get_theme_font("font") = FontFile#...5201702     ← 内置字体（错）
##     has_char("中") = false   has_char("A") = true
##
##   对照：LaunchScreen 每个 Label 都显式 add_theme_font_override → 中文一直正常。
##
## 所以：凡是要 add_child 到 Main 下的 Control，都调这个函数。
func _themify(c: Control) -> void:
	if c != null and c.theme == null:
		c.theme = PixelTheme.build()


# ── 界面 ─────────────────────────────────────────────
func _show_menu() -> void:
	# 主人 2026-10-30：启动界面重做为「初始化 → Agent 对话框」流程（旧菜单 --oldmenu 保留）
	if not OS.get_cmdline_user_args().has("--oldmenu"):
		if _patch_demo_direct:
			_show_patch_demo.call_deferred()
			return
		if _wish_demo_direct:
			run.set_ai(AiPool.get_ai("deepdeek"))
			_show_level.call_deferred(_levels[0], false)
			return
		_show_launch()
		return
	var menu := MenuScene.new()
	menu.start_run.connect(_on_start_run)
	menu.quit_game.connect(func() -> void: get_tree().quit())
	menu.open_ai_settings.connect(_show_llm_panel)
	_swap(menu)


func _show_level(level: LevelData, elite: bool = false) -> void:
	_pending_elite = elite
	_pending_level = level
	_last_passed = false
	# 正常流程由选人界面设定；调试/直跳路径兜底给初始伙伴
	if run.ai == null:
		run.set_ai(AiPool.get_ai("deepdeek"))
	var arena := ArenaScene.new()
	arena.setup(run, level, _pending_elite)
	arena.level_cleared.connect(_on_level_cleared)
	arena.level_failed.connect(_on_level_failed)
	arena.advance_requested.connect(_on_advance)
	_swap(arena)


func _show_reward() -> void:
	var r := RewardScene.new()
	r.setup(run)
	r.chosen.connect(_after_reward)
	_swap(r)
	# 裂隙转场（2026-11-01 主人钦定）：黑幕→中央裂纹向上下张开→左右分开露出奖励
	if DisplayServer.get_name() != "headless":
		r.add_child(RiftScene.new())


func _show_result(win: bool) -> void:
	if win:
		var rs := ResultScreen.new()
		rs.setup("全部战斗胜利", "你带着 %d 张卡（%d 件 AI 道具）闯完了 10 场战斗。
累计伤害 %d ｜ 剩余算力 %d" % [
			run.deck.size(), run.items.size(), run.score, run.compute
		], [
			{"text": "再来一局", "id": "menu", "accent": true},
		])
		rs.retry.connect(_on_retry)
		rs.to_menu.connect(_show_menu)
		_swap(rs)
	else:
		# 燃尽画面（2026-11-01 主人钦定）：额度耗尽 → 黑屏跪姿 → 「燃尽了」→ 回主界面
		var bo := BurnoutScene.new()
		bo.retry_requested.connect(_on_retry)
		bo.menu_requested.connect(_show_menu)
		_swap(bo)


# ── 事件 ─────────────────────────────────────────────
func _on_start_run() -> void:
	run.reset_run()
	_show_ai_select()


## 选 AI 娘：她会被画在**每一张牌的中间**，并给一套被动
func _show_ai_select() -> void:
	# 主人要求的新版选角：楼梯秀场（demo）。默认走旧界面，--stairs 切新版
	if OS.get_cmdline_user_args().has("--stairs"):
		_show_stairs()
		return
	var sel := AiSelectScene.new()
	sel.setup(AiPool.ai_list_for_select(run.level_index))
	sel.ai_chosen.connect(_on_ai_chosen)
	sel.cancelled.connect(_show_menu)
	_swap(sel)


## 新启动流程（2026-11-09 主人改版）：
##   黑屏「初始化」 → Agent 对话框（无模型选择）→ 发送（可空输入）
##   → 全屏马赛克糊掉 → 选角界面（4 角色 + 专属转场切换）→ 开始游戏 → 进第一关
## 发送后带回的 ai_id 只作为选角的**默认高亮位**（对话框不再选模型）。
func _show_launch() -> void:
	var sc := LaunchScreen.new()
	sc.launched.connect(func(ai_id: String) -> void:
		_goto_character_select(ai_id))
	_swap(sc)
	sc.ai_settings_requested.connect(_show_llm_panel)
	sc.demo_requested.connect(_show_llm_demo)
	sc.patch_demo_requested.connect(_show_patch_demo)


## 启动页 → 选角（2026-11-09 主人要求接入主界面面板动画）：
##   ① 面板退出动画：侧栏向上收 + 下框收窄右移 → 蓄力 → 顶飞（LaunchMorphExit）
##   ② 两者都飞出去后，整屏马赛克化 → 换界面 → 从马赛克里清晰出来
## 注意顺序：**先播面板动画再马赛克**。反过来马赛克会先把面板糊掉，
## 观众看不到收缩过程（主人反馈「框框没动」就是没接上这一步）。
func _goto_character_select(default_ai_id: String) -> void:
	var mosaic := ScreenMosaic.new()
	mosaic.name = "ScreenMosaic"
	add_child(mosaic)
	_themify(mosaic)
	mosaic.move_to_front()
	# ① 面板退出动画（约 1.24s）：两框收缩 → 蓄力 → 顶飞。
	#    此时遮罩**不可见**（grab 只备图不显示），动画全程可见。
	var sc_cur := _current as LaunchScreen
	if sc_cur != null:
		await sc_cur.play_exit_morph()
	# ② 面板飞走后再抓帧：抓的是「空背景」，这才是该被马赛克化的画面
	await mosaic.grab()
	# ③ 逐渐马赛克化（停在能看清方块颗粒的 PEAK_BLOCKS）
	await mosaic.cover(0.5)
	var sel := CharacterSelectScreen.new()
	sel.setup(AiPool.all_ais())
	var first := 0
	for i in AiPool.all_ais().size():
		if AiPool.all_ais()[i].id == default_ai_id:
			first = i
			break
	sel.select_by_index(first)
	sel.started.connect(func(ai_id: String) -> void: _on_character_chosen(ai_id))
	sel.back_requested.connect(_show_launch)
	_swap(sel)
	mosaic.move_to_front()
	# 关键：重新抓新界面的帧再消退，否则消退出来的是启动页的残影
	await mosaic.recapture()
	await mosaic.reveal(0.5)
	mosaic.queue_free()


## 选角确认 → 真正开 Run 进第一关（终端进场照旧触发）
func _on_character_chosen(ai_id: String) -> void:
	run.reset_run()
	var ai := AiPool.get_ai(ai_id)
	if ai == null:
		ai = AiPool.get_ai("deepdeek")
	run.set_ai(ai)
	_show_level(_levels[0])


## 本次改动 Demo 页：一键直进为主（2026-11-04 主人钦定），技术细节折叠在下方。
func _show_patch_demo() -> void:
	var demo := PatchDemoScene.new()
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--tab="):
			demo.initial_tab = int(a.get_slice("=", 1))
	demo.back_requested.connect(_show_launch)
	_swap(demo)


func _show_llm_demo() -> void:
	var demo := LLMDemoScene.new()
	demo.back_requested.connect(_show_launch)
	demo.start_ai_battle.connect(_demo_enter_battle)
	demo.start_ai_event.connect(_demo_enter_event)
	_swap(demo)


## Demo 一键直进：像平常战斗那样开局（AI 用已保存配置，配置没开就自动开）
func _demo_enter_battle() -> void:
	_demo_prep_run()
	_show_level(_levels[0])


func _demo_enter_event() -> void:
	_demo_prep_run()
	_show_event(randi() % 5)


func _demo_prep_run() -> void:
	if run == null:
		run = RunState.new()
	run.reset_run()
	run.set_ai(AiPool.get_ai("deepdeek"))


## 楼梯选角 demo：3D 楼梯 + 仰视相机，四位 AI 娘分立两侧待选。
## 确认后仍然走原来的 _on_ai_chosen 流程，不影响后续进场/战斗。
func _show_stairs() -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	var sc := SelectStairs.new()
	sc.selected.connect(func(ai_id: String) -> void:
		sc.queue_free()
		_on_ai_chosen(AiPool.get_ai(ai_id)))
	add_child(sc)


func _on_ai_chosen(ai: AiData) -> void:
	run.set_ai(ai)
	_show_level(_levels[0])


## 关卡结算完成（战斗界面自己弹结果窗，这里只记账，不切屏）
func _on_level_cleared(_final_score: int) -> void:
	run.level_index += 1
	run.events_since_battle = 0   ## 事件门冷却重置
	if _pending_level != null:
		run.chapter = _pending_level.chapter
	_last_passed = true


func _on_level_failed(_final_score: int) -> void:
	_last_passed = false


## 玩家在结算弹窗点了「继续」
func _on_advance() -> void:
	if _last_passed:
		_show_reward()
	else:
		_show_result(false)


func _after_reward() -> void:
	_show_map()


## 选关界面（战斗 / 事件节点）
## 选关界面（门选制）：每次到达掷一次遭遇——40% 战斗 / 30% 事件 / 10% 奖励 / 20% 精英
## 战斗门常驻；事件门、奖励门、精英门按概率出现（主人 2026-11-01 概率表 v2）
func _show_map() -> void:
	if run.level_index >= _levels.size():
		_show_result(true)
		return
	## 沙盒强制门只作用于「下一门」：消费一次后回到随机
	var special := RunState.pick_special(run.rng.randf(), _force_special)
	_force_special = ""
	var m := MapScene.new()
	m.setup(run, special)
	m.battle_entered.connect(_on_battle_door)
	m.event_entered.connect(_on_event_door)
	m.bonus_entered.connect(_show_bonus)
	m.shop_entered.connect(_show_shop)
	m.elite_entered.connect(_on_elite_door)
	_swap(m)


## 精英门：强制精英战斗（必掉宝箱）
func _on_elite_door() -> void:
	_show_level(_levels[run.level_index], true)


## 奖励关：开宝箱得一件道具
func _show_bonus() -> void:
	var b := BonusScreen.new()
	b.setup(run)
	b.finished.connect(_show_map)
	_swap(b)


func _on_battle_door() -> void:
	_show_level(_levels[run.level_index])


func _on_event_door() -> void:
	_start_event_flow()


## AI 事件流：本地预筛候选 → LLM 池内 pick → 本地掷数值并写 run。
## AI 关闭 / 候选池空 / 超时 / 解析失败 / 非法 pick 全部静默回退原 5 则事件。
func _start_event_flow() -> void:
	if _llm_cfg == null or not _llm_cfg.is_enabled():
		_show_event(0)
		return
	var candidates := LLMEventEngine.build_candidates(run, run.rng)
	if candidates.is_empty():
		_show_event(0)
		return

	var e := EventScene.new()
	e.setup_ai_loading(run)
	e.finished.connect(_on_event_finished)
	_swap(e)

	# 事件协议：system 用 LLMPrompts 的 EVENT_V2 全文；user 带局面 + 候选池快照。
	var msgs: Array[Dictionary] = []
	msgs.append({"role": "system", "content": LLMPrompts.for_scene("event")})
	var base := LLMEventEngine.build_messages(run, candidates)
	msgs.append({"role": "user", "content": String(base[1].get("content", ""))})
	_llm_event_rid += 1
	var rid := _llm_event_rid
	_llm_client.request("event", msgs, _on_event_llm_done.bind(candidates, rid), {
		"resolve_id": rid,
		"pool_hash": _event_pool_hash(candidates),
		"timeout_s": 3.0,
	})


## LLM 回调：三关校验（LLMParse）→ 本地应用。迟到/切换界面后的回调直接丢弃。
func _on_event_llm_done(result: Dictionary, candidates: Array, _rid: int) -> void:
	var e := _current as EventScreen
	if e == null:
		return
	if not bool(result.get("ok", false)):
		_show_event(0)
		return
	var parsed := LLMParse.parse_event(String(result.get("text", "")), candidates.size())
	var res := LLMEventEngine.apply_pick(run, candidates, int(parsed.get("pick", 0)))
	if not bool(res.get("ok", false)):
		_show_event(0)
		return
	var reason := String(parsed.get("reason", ""))
	if not bool(parsed.get("ok", false)):
		reason = ""
	if _current != e:
		return
	e.apply_ai_event(res, reason)


func _event_pool_hash(candidates: Array) -> String:
	var parts: Array[String] = []
	for c in candidates:
		parts.append("%s:%d:%d" % [String(c.get("id", "")),
				int(c.get("net_min", 0)), int(c.get("net_max", 0))])
	return "|".join(parts)


## 事件节点（原 5 则热梗池；AI 关闭时完全不变）
func _show_event(event_index: int) -> void:
	var e := EventScene.new()
	e.setup(run, event_index)
	e.finished.connect(_on_event_finished)
	_swap(e)


func _on_event_finished() -> void:
	run.events_since_battle += 1
	_show_map()


func _show_shop() -> void:
	var sh := ShopScreen.new()
	sh.setup(run)
	sh.closed.connect(_show_map)
	_swap(sh)


func _after_shop() -> void:
	_go_next_level()


func _go_next_level() -> void:
	if run.level_index >= _levels.size():
		_show_result(true)
		return
	_show_level(_levels[run.level_index])


func _on_retry() -> void:
	if _pending_level != null:
		_show_level(_pending_level)


# ─────────────────────────────────────────────────────────
#  开发用截图钩子（仅命令行带参时生效）：
##   godot --path <项目> -- --shot=arena --shotout=<绝对路径>.png
##   可选 screen：menu / arena / reward / result / flow
##                 flip / slot / hover / typing / typebreak / runresult / syntax
# ─────────────────────────────────────────────────────────
## 体验沙盒（F1 开关）：按钮直达全部内容（2026-11-01 主人钦定）
func _build_sandbox() -> void:
	_sandbox = SandboxPanelScene.new()
	_sandbox.name = "SandboxPanel"
	_sandbox.visible = false
	add_child(_sandbox)
	_sandbox.build(_sandbox_actions())


## 正式版权限（2026-11-18 主人要求）：
##   · F1 体验沙盒**已禁用**（强制下一门/加钱等调试项，正式包不该让玩家按到）
##   · F2 AI 接入设置保留（玩家要能配自己的模型）
const SANDBOX_ENABLED := false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		if SANDBOX_ENABLED:
			_toggle_sandbox()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_show_llm_panel()


# ── AI 接入设置面板 ───────────────────────────────────
func _show_llm_panel() -> void:
	if _llm_panel != null and is_instance_valid(_llm_panel):
		_llm_panel.move_to_front()
		_llm_panel.visible = true
		return
	if _llm_cfg == null:
		_llm_cfg = LLMConfig.load_from_disk()
	var panel := MenuScene.LLMSettingsPanel.new()
	panel.name = "LLMSettingsPanel"
	panel.setup(_llm_cfg)
	panel.saved.connect(_on_llm_config_saved)
	panel.closed.connect(func() -> void: _llm_panel = null)
	_llm_panel = panel
	add_child(panel)
	_themify(panel)
	## 关键修复（2026-11-18）：Main 是纯 Node（没有 rect），往它下面挂 Control 时
	## 光靠 set_anchors_preset(FULL_RECT) 算不出尺寸 —— 实测面板 size=(0,0)，
	## 于是"看不见、点了也像没反应"。必须显式把尺寸同步到视口大小。
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.size = get_viewport().get_visible_rect().size
	panel.position = Vector2.ZERO
	panel.visible = true
	panel.z_index = 500        ## 压在一切之上
	print("[LLMPanel] 新建面板 size=", panel.size, " 视口=", get_viewport().get_visible_rect().size)


func _on_llm_config_saved() -> void:
	if _llm_client != null and _llm_cfg != null:
		_llm_client.setup(_llm_cfg)
		_llm_client.reset_circuit()


func _toggle_sandbox() -> void:
	if _sandbox == null:
		return
	_sandbox.visible = not _sandbox.visible
	if _sandbox.visible:
		_sandbox.move_to_front()
		_sandbox.build(_sandbox_actions())


func _arena() -> ArenaScreen:
	return _current as ArenaScreen


func _sandbox_actions() -> Dictionary:
	return {
		"stir": func() -> void:
			if _arena() != null and _arena().combat != null:
				_arena().combat.rice_eaten = 2
				_arena()._update_rice_hud(),
		"awake": func() -> void:
			if _arena() != null and _arena().combat != null:
				_arena().combat.rice_eaten = StsCombat.RICE_AWAKE
				_arena()._update_rice_hud(),
		"sleep": func() -> void:
			if _arena() != null and _arena().combat != null:
				_arena().combat.rice_eaten = 0
				_arena()._update_rice_hud(),
		"win": func() -> void:
			if _arena() != null:
				_arena().debug_win_battle(),
		"elite": func() -> void:
			if run.level_index < _levels.size():
				_show_level(_levels[run.level_index], true),
		"heal": func() -> void:
			run.hp = RunState.MAX_HP
			if _arena() != null:
				_arena()._refresh_hud(),
		"ev0": func() -> void: _show_event(0),
		"ev1": func() -> void: _show_event(1),
		"ev2": func() -> void: _show_event(2),
		"ev3": func() -> void: _show_event(3),
		"ev4": func() -> void: _show_event(4),
		"door_event": func() -> void: _force_special = "event"; _show_map(),
		"door_bonus": func() -> void: _force_special = "bonus"; _show_map(),
		"door_shop": func() -> void: _force_special = "shop"; _show_map(),
		"door_elite": func() -> void: _force_special = "elite"; _show_map(),
		"door_none": func() -> void: _force_special = ""; _show_map(),
		"item_opt": func() -> void: _grant_item("prompt_opt"),
		"item_parts": func() -> void: _grant_item("subagent"),
		"item_compress": func() -> void: _grant_item("compress"),
		"ult": func() -> void:
			if _arena() != null:
				_arena().debug_ult_demo(),
		"fx_slash": func() -> void:
			if _arena() != null:
				_arena().debug_fx_demo("slash"),
		"fx_shield": func() -> void:
			if _arena() != null:
				_arena().debug_fx_demo("shield"),
		"fx_claw": func() -> void:
			if _arena() != null:
				_arena().debug_fx_demo("claw"),
		"burnout": func() -> void:
			if _pending_level == null and run.level_index < _levels.size():
				_pending_level = _levels[run.level_index]
			_show_result(false),
	}


func _grant_item(item_id: String) -> void:
	var it := StsItemPool.make(item_id)
	if it != null:
		run.add_item(it)


func _maybe_capture() -> void:
	var args := OS.get_cmdline_user_args()
	var screen := ""
	var out_path := ""
	for a in args:
		if a.begins_with("--shot="):
			screen = a.substr(7)
		elif a.begins_with("--shotout="):
			out_path = a.substr(10)
	if out_path.is_empty():
		return
	if screen == "tutorshot":
		await _capture_tutorial(out_path)
		return
	if screen == "wishshot":
		await _capture_wish(out_path)
		return
	if screen in ["menu", "arena", "battle", "intro", "introcard", "reward", "result",
			"menuhover", "rig", "rigwalk", "loadrun", "card", "cardtext", "cardcost", "terminal", "termgif",
			"termdump", "hero", "stairs", "launch", "launch2", "arenalayout", "sendtest", "ricetest",
			"patchdemo", "wishpanel", "ripple", "morph", "select", "mosaic", "flow", "exitmorph", "fandbg",
			"breath"]:
		run.reset_run()
		if screen == "launch" or screen == "launch2":
			var sc := _current as LaunchScreen
			if sc == null:
				sc = LaunchScreen.new()
				_swap(sc)
			if screen == "launch2":
				sc.expand()
			await get_tree().create_timer(1.0).timeout
			get_viewport().get_texture().get_image().save_png(out_path)
			print("[shot=%s] 已存 → %s" % [screen, out_path])
			get_tree().quit()
			return
		if screen == "stairs":
			await _capture_stairs(out_path)
			return
		if screen == "hero":
			# 只验「终端 → Godot 立绘」这一段：假造终端排版，抓 4 帧看马赛克收敛与对齐。
			# 配套参数：--nointro（跳过真实进场）
			await _capture_hero_mosaic(out_path)
			return
		if screen == "termdump":
			# 只生成 .ps1 + 字符画文本，**不启动终端**：给宿主侧做语法/尺寸自检
			_capture_term_dump(out_path)
			return
		if screen == "rig":
			# 目检：Q 版角色 walk 的第 0/1/2/3 帧 → 2×2 拼图
			await _capture_rig(out_path)
			return
		if screen == "rigwalk":
			# 动图：真实播放 walk，24fps 采样 → .tmp/riggif/ 48 张 PNG（ffmpeg 拼 GIF 用）
			await _capture_rig_walk(out_path)
			return
		if screen == "loadrun":
			# 演示：进入游戏进度条 + Q 版角色跟着填充边缘跑 → .tmp/loadrun/ PNG 序列
			await _capture_loadrun(out_path)
			return
		if screen == "ricetest":
			# 验收白米饭成长：喂满 2 碗 → 伙伴换成「有点睡醒」+ HUD 显示增益
			_show_ai_select()
			if _current != null:
				_current.queue_free()
				_current = null
			_show_level(_levels[0])
			await get_tree().create_timer(1.2).timeout
			var arr := _current as ArenaScreen
			if arr != null:
				arr.debug_feed_rice(2)
				await get_tree().create_timer(1.2).timeout
				print("[shot=ricetest] 白米饭=%d 醒=%s" % [
					arr.combat.rice_eaten, str(arr.combat.is_awake())])
			_shot(out_path)
			print("[shot=ricetest] 已存 → %s" % out_path)
			get_tree().quit()
			return
		if screen == "sendtest":
			# 验收「点发送后手牌尺寸」：打一整手 → 补牌 → 再截图，牌应与开局同样大
			_show_ai_select()
			if _current != null:
				_current.queue_free()
				_current = null
			_show_level(_levels[0])
			await get_tree().create_timer(1.2).timeout
			var ar := _current as ArenaScreen
			if ar != null:
				ar._on_send_pressed()
				await get_tree().create_timer(2.4).timeout
				var sc0 := ar.debug_hand_scale()
				print("[shot=sendtest] 补牌后首张 scale=%s 手牌=%d" % [
					str(sc0), ar.debug_hand_count()])
			_shot(out_path)
			print("[shot=sendtest] 已存 → %s" % out_path)
			get_tree().quit()
			return
		if screen == "aiselect" or screen == "arenalayout":
			# arenalayout：验收战斗区新布局（侧边栏拉满 + 底部对话框 + AI 娘右端）
			_show_ai_select()
			if screen == "arenalayout":
				if _current != null:
					_current.queue_free()
					_current = null
				_show_level(_levels[0])
				await get_tree().create_timer(1.4).timeout
				var ar := _current as ArenaScreen
				if ar != null:
					print("[shot=arenalayout] %s" % ar.debug_layout_rects())
				_shot(out_path)
				print("[shot=arenalayout] 已存 → %s" % out_path)
				get_tree().quit()
		elif screen == "reward":
			_show_reward()
		elif screen == "result":
			_show_result(true)
		elif screen == "termgif":
			# 动图采帧：12fps 抓 5.8 秒 → .tmp/termgif/*.png（ffmpeg 拼 GIF）
			_show_level(_levels[0])
			DirAccess.make_dir_recursive_absolute("res://.tmp/termgif")
			var fps := 12
			for i in int(5.8 * fps):
				var img := get_viewport().get_texture().get_image()
				img.save_png("res://.tmp/termgif/f%03d.png" % i)
				await get_tree().create_timer(1.0 / float(fps)).timeout
			print("[shot=termgif] 采帧完成")
		elif screen == "terminal":
			# 终端进场三相：代码打字中 / 字符画扫描中 / 完成
			_show_level(_levels[0])
			for st in [1.1, 3.0, 4.3]:
				await get_tree().create_timer(st - (0.0 if st == 1.1 else (1.1 if st == 3.0 else 3.0))).timeout
				get_viewport().get_texture().get_image().save_png(
						_outname(out_path, "terminal", "t%d" % int(st * 10)))
		elif screen in ["card", "cardtext", "cardcost"]:
			# 验收钩子：两张卡画在**已知坐标**（40,40）/（240,40），便于像素级量文字墨迹中心。
			# 布局框居中 ≠ 字形居中（描边上下不对称），肉眼验收容易放过，这里给个可量的靶。
			var probe := Control.new()
			probe.set_anchors_preset(Control.PRESET_FULL_RECT)
			var pbg := ColorRect.new()
			pbg.color = Color("#0b0f18")
			pbg.set_anchors_preset(Control.PRESET_FULL_RECT)
			probe.add_child(pbg)
			var ids := ["fish_ram", "taunt"]
			var text_only := screen == "cardtext" or screen == "cardcost"
			var backs: Array[StsCardView] = []
			for i in ids.size():
				var cv := StsCardView.new()
				cv.setup(StsCardPool.card(ids[i]))
				cv.position = Vector2(40 + i * 200, 40)
				# 第二排：同样的两张卡翻到背面（2026-11-07 正面名牌+费用球 / 背面描述）
				var cb := StsCardView.new()
				cb.setup(StsCardPool.card(ids[i]))
				cb.position = Vector2(40 + i * 200, 300)
				backs.append(cb)
				if text_only:
					# 只留文字层：藏掉框与立绘，墨迹测量不受污染（层级 11-07 起嵌套，递归找）
					for ch in cv.find_children("*", "TextureRect", true, false):
						(ch as TextureRect).visible = false
					if screen == "cardcost":
						for lb in cv.find_children("*", "Label", true, false):
							if (lb as Label).name != "CostOrb":
								(lb as Label).visible = false
				probe.add_child(cv)
				probe.add_child(cb)
			_swap(probe)
			for cb in backs:
				cb.flip()
			# 翻面动画 ~0.31s，等它落定再拍
			await get_tree().create_timer(0.6).timeout
		elif screen == "intro":
			# 实测转场：中段（3D 翻飞中）存一张 -mid，结尾（落回 2D）存主文件
			_show_level(_levels[0])
			await get_tree().create_timer(0.85).timeout
			var mid := get_viewport().get_texture().get_image()
			mid.save_png(_outname(out_path, "intro", "mid"))
			await get_tree().create_timer(1.6).timeout
		elif screen == "battle":
			# 目检：进战斗打一张牌，看敌人受击特效与战斗日志
			_show_level(_levels[0])
			await get_tree().process_frame
			var arena_shot := _current as ArenaScreen
			if arena_shot != null:
				arena_shot.debug_play_card(0)
				await get_tree().create_timer(0.6).timeout
		elif screen == "arena":
			# 战斗背景验收（2026-11-07 代码雨）：配合 --nointro 用，落 1s 雨再拍
			_show_level(_levels[0])
			await get_tree().create_timer(1.0).timeout
		elif screen == "wishpanel":
			# 许愿画布验收（2026-11-07）：纯看图（无文字输入框）+ 代码雨背景
			_show_level(_levels[0])
			# 等进场转场走完（终端进场 ~4s），再开面板
			await get_tree().create_timer(4.5).timeout
			var ar_wish := _current as ArenaScreen
			if ar_wish != null:
				ar_wish.debug_open_wish_panel()
				# 再等 0.8s：代码雨落下几帧，画面不是空的
				await get_tree().create_timer(0.8).timeout
		elif screen == "morph":
			# 面板伸缩逐帧验收（2026-11-09）：6 个进度点各存一帧
			var morph := PanelMorphDemo.new()
			morph.size = Vector2(1600, 900)
			_swap(morph)
			await get_tree().process_frame
			# 采样点覆盖全程：起手 / 收缩中 / 左框已停 / 蓄力下沉 / 接触瞬间 / 顶出中 / 全出画
			var mts := [0.0, 0.18, 0.28, 0.31, 0.34, 0.55, 0.75, 1.0]
			for i in mts.size():
				morph.debug_set_morph(float(mts[i]))
				await get_tree().process_frame
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(
						"%s-f%02d.png" % [out_path, i])
			print("[shot=morph] 已存 %d 帧 → %s-fNN.png" % [mts.size(), out_path])
		elif screen == "flow":
			# 端到端流程验收（2026-11-09）：面板动画 → 抓帧 → 马赛克 → 选角
			# 注意：隐藏桌面实时抓帧会拿过期缓冲，所以分两段：
			#   A 段用定格保证动画帧可信；B 段用真实流程验证顺序与马赛克
			await get_tree().create_timer(0.5).timeout
			var lc2 := _current as LaunchScreen
			if lc2 == null:
				lc2 = LaunchScreen.new()
				_swap(lc2)
				await get_tree().process_frame
			lc2.expand()
			await get_tree().create_timer(0.8).timeout
			get_viewport().get_texture().get_image().save_png("%s-f00.png" % out_path)
			# A 段：面板动画定格（f01~f06）
			var ex := LaunchMorphExit.new(lc2._sidebar, lc2._dialog, lc2)
			var steps := [0.18, 0.36, 0.52, 0.70, 0.88, 1.0]
			for i in steps.size():
				ex.debug_set_progress(float(steps[i]))
				await get_tree().process_frame
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(
						"%s-f%02d.png" % [out_path, i + 1])
			# B 段：真实流程（复位后点发送，验证「动画 → 马赛克」的顺序）
			ex.restore_layout()
			await get_tree().process_frame
			await get_tree().process_frame
			lc2._input.text = ""
			lc2._send()
			# 面板动画 1.24s → 抓帧 ~2 帧 → 马赛克 0.5s → 切界面 → reveal 0.5s
			var log := FileAccess.open("res://.tmp/flow_seq.txt", FileAccess.WRITE)
			for i in 8:
				await get_tree().create_timer(0.22).timeout
				get_viewport().get_texture().get_image().save_png(
						"%s-b%02d.png" % [out_path, i])
				if log != null:
					var cur := _current
					log.store_line("b%02d scene=%s" % [i, cur.get_class() if cur != null else "null"])
			if log != null:
				log.close()
			await get_tree().create_timer(1.2).timeout
			get_viewport().get_texture().get_image().save_png("%s-b08.png" % out_path)
			print("[shot=flow] 已存 A:7 + B:9 帧 → %s-f%02d / %s-b%02d" % [out_path, 0, out_path, 0])
		elif screen == "exitmorph":
			# 主界面退出动画逐帧验收（2026-11-09）：真实 LaunchScreen 面板 + debug 定格
			var lc3 := LaunchScreen.new()
			_swap(lc3)
			await get_tree().process_frame
			lc3.expand()
			await get_tree().create_timer(0.9).timeout
			var ex := LaunchMorphExit.new(lc3._sidebar, lc3._dialog, lc3)
			for i in 7:
				ex.debug_set_progress([0.0, 0.18, 0.36, 0.45, 0.52, 0.72, 1.0][i])
				await get_tree().process_frame
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(
						"%s-f%02d.png" % [out_path, i])
			print("[shot=exitmorph] 已存 7 帧 → %s-fNN.png" % out_path)
		elif screen == "mosaic":
			# 马赛克逐档定格验收（2026-11-09）：每档等两帧再抓，避开过期缓冲
			var sc2 := LaunchScreen.new()
			_swap(sc2)
			await get_tree().process_frame
			sc2.expand()
			await get_tree().create_timer(1.0).timeout
			var mz := ScreenMosaic.new()
			add_child(mz)
			_themify(mz)
			mz.move_to_front()
			await mz.grab()
			var steps := [400, 200, 120, 72, 48]
			for i in steps.size():
				mz.debug_set_blocks(int(steps[i]))
				await get_tree().process_frame
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(
						"%s-f%02d.png" % [out_path, i])
			print("[shot=mosaic] 已存 %d 档 → %s-fNN.png" % [steps.size(), out_path])
		elif screen == "breath":
			# 呼吸验收（2026-11-10）：对每个角色取「谷值 p=0.75」与「峰值 p=0.25」两帧，
			# 差值就是该角色这一层的最大位移，用来证明头发真的在动。
			var sel_b := CharacterSelectScreen.new()
			sel_b.setup(AiPool.all_ais())
			_swap(sel_b)
			await get_tree().process_frame
			# 引擎按 --engine=mesh|uv 选（V4 网格 / V3 UV）。默认 mesh。
			# 注：早前这里先无条件 set_engine(false) 再切回，注释误写成「V4 不支持定格」——
			# 实际 debug_set_breath → _apply() → mesh.set_phase() 链路两个引擎都通，
			# 那行强制 V3 只会把 V4 的真实验收遮掉（2026-11-10 修正）。
			var eng := "mesh"
			var boost := false
			# --v4only=hair|head：只开单一通道，用来验证「眼睛归属」
			# （只开头发时眼睛必须一动不动；只开头颈时眼睛必须动）
			var only := ""
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--engine="):
					eng = a.substr(9)
				elif a == "--v4boost":
					boost = true
				elif a.begins_with("--v4only="):
					only = a.substr(9)
			if only != "":
				boost = true
			if sel_b._breath != null:
				sel_b._breath.set_engine(eng == "mesh")
			await get_tree().process_frame
			await get_tree().process_frame
			for ci in sel_b._ais.size():
				sel_b.select_by_index(ci)
				# 等转场收尾（各角色转场时长不同，统一等最长 + 余量）
				await get_tree().create_timer(3.2).timeout
				# 采样相位：默认 0.75/0.25 是给 V3 的 sin 设计的峰谷。
				# 采样相位必须跟着**要测的通道**选，两者对不上就会得到「两帧完全相同」：
				#   · 横向走 cos：cos(2π·0.25)=cos(2π·0.75)=0 → 测横扩要用 0.0 / 0.5
				#   · 纵向走 sin：sin(2π·0)=sin(2π·0.5)=0     → 测纵向要用 0.25 / 0.75
				# 2026-11-10 两次都踩过：先拿 0.75/0.25 测横扩（0 差异），
				# 后拿 0.0/0.5 测头纵（也 0 差异）。
				var phases: Array = [0.75, 0.25]
				if only == "hair" or only == "chest":
					phases = [0.0, 0.5]        # 横向（cos）峰谷
				elif only == "head":
					phases = [0.25, 0.75]      # 纵向（sin）峰谷
				elif boost and only == "":
					phases = [0.0, 0.5]        # 默认 boost 是胸腔横扩
				for pp in phases:
					# --v4boost：只留胸腔横扩、amp 拉满，证明 V4 的左右反向扩张
					# （V3 的 UV 平移在数学上做不到左右反向，这是两代方案的本质差别）。
					# **每帧重设**：转场收尾/面板 set_character 会按角色存档把 uniform 覆盖回去，
					# 只在循环外设一次会被冲掉（实测 chest_x 又变回 10.5）。
					if boost and sel_b._breath != null:
						var mesh_b: PortraitBreathMesh = sel_b._breath.get_mesh_layer()
						if mesh_b != null:
							# 基础：全关，amp 拉满
							var p4 := {
								"amp": 3.0, "chest_x": 0.0, "chest_y": 0.0,
								"belly_x": 0.0, "belly_y": 0.0, "head_y": 0.0,
								"hair_x": 0.0, "hair_y": 0.0,
								"belly_lag_deg": 0.0, "head_lag_deg": 0.0,
								"hair_lag_per_height": 0.0,
								# 底锁取该角色自己的值：deepseek 0.04 / kweno 0.10 / gpt 0.18
								"lock_bottom": GameSettings.breath_v4_get(
										String(sel_b._ais[ci].id), "lock_bottom"),
								"x_lag_deg": 0.0, "y_bias": 0.0}
							# 按 --v4only 只点亮一个通道
							if only == "hair":
								p4["hair_x"] = 40.0
								p4["hair_y"] = 40.0
							elif only == "head":
								p4["head_y"] = 30.0
							else:
								p4["chest_x"] = 30.0      # 默认 boost = 胸腔横扩
							mesh_b.apply_v4_params(p4)
							mesh_b.set_horiz(true)
					sel_b.debug_set_breath(float(pp))
					# debug_set_breath 内部会 _apply()，但 boost 是之后才改 uniform，
					# 再 _apply 一次把 phase 按当前参数重新推一遍
					if boost and sel_b._breath != null:
						sel_b._breath.debug_set_breath(float(pp))
					await get_tree().process_frame
					await get_tree().process_frame
					# 取证：截图前把实际生效的 uniform 打进日志。
					# 曾经反复出现「boost 设了但画面没变」，根因是转场结束回调
					# _sync_breath_char → 面板 set_character 会按角色存档覆盖 uniform。
					# 有了这行日志就能一眼分辨「参数没进去」还是「参数进去了但效果不对」。
					if boost and sel_b._breath != null:
						var dbg_mesh: PortraitBreathMesh = sel_b._breath.get_mesh_layer()
						if dbg_mesh != null:
							var d4 := dbg_mesh.get_v4_params()
							print("  [shot] c%d p%.2f amp=%.1f chest=(%.1f,%.1f) head=%.1f hair=(%.1f,%.1f) lock=%.2f" % [
								ci, pp, float(d4.get("amp",0)), float(d4.get("chest_x",0)),
								float(d4.get("chest_y",0)), float(d4.get("head_y",0)),
								float(d4.get("hair_x",0)), float(d4.get("hair_y",0)),
								float(d4.get("lock_bottom",0))])
					get_viewport().get_texture().get_image().save_png(
							"%s-%s-c%d-p%02d.png" % [out_path, eng, ci, int(pp * 100)])
			print("[shot=breath] engine=%s boost=%s 已存 %d 帧 → %s-<eng>-cN-pNN.png" % [
				eng, boost, sel_b._ais.size() * 2, out_path])
		elif screen == "introcard":
			# 角色介绍面板验收（2026-11-11 主人给了 4 张红框位置图）：
			#   --introstage=slide|expand|final 定格在三段式的某一拍
			#   产物 <out>-c0..c3.png，四位角色各一张
			# ⚠ 分支名不能叫 "intro"：那个名字已被「终端进场」占用两处。
			var stage := "final"
			for a4 in OS.get_cmdline_user_args():
				if a4.begins_with("--introstage="):
					stage = a4.substr(13)
			var seli := CharacterSelectScreen.new()
			seli.setup(AiPool.all_ais())
			_swap(seli)
			await get_tree().process_frame
			await get_tree().process_frame
			# 验收介绍面板时必须关掉两块调试面板：它们按 F3 常驻右上，
			# 正好压在 deepseek/chatppt/grock 的最终位置上盖住介绍内容。
			seli.toggle_debug_panels(false)
			var ids := ["deepdeek", "kweno", "chatppt", "grock"]
			for ci in 4:
				# 只有真的换了角色才会起转场、才会发 swap_finished。
				# 首次循环 index 已是 0 时 select_by_index 是空操作，
				# 直接等信号会永久挂住 → 先判一下。
				if seli.current_index() != ci:
					seli.select_by_index(ci)
					await seli._bg_layer.swap_finished
				else:
					seli.select_by_index(ci)
					await get_tree().process_frame
				await get_tree().process_frame
				# 直接定格到终态，不依赖动画时序
				seli.debug_show_intro(ids[ci])
				var ip = seli._intro_panel
				if ip == null:
					printerr("[shot=introcard] 没有介绍面板")
					break
				if stage == "slide":
					# 滑入段：真实播放时内容还是透明的（present 里 _body.a=0，
					# 要到展开结束才淡入）。钩子必须一并复刻这个状态，
					# 否则截出来是「整块面板 + 全部文字」，看不出「一条边」的形态。
					ip._body.modulate.a = 0.0
					ip._set_slide(0.62)
				elif stage == "expand":
					ip._body.modulate.a = 0.0
					ip._set_slide(1.0)
					ip._set_expand(0.45)
				elif stage == "folded":
					# 折叠态：收进对应侧，只留一条 + 箭头把手
					ip.set_folded(true)
					ip._kill()
					ip._cur = ip._fold_rect()
					ip._apply_cur()
					ip._body.modulate.a = 0.0
				var rr: Rect2 = ip.current_rect()
				print("[shot=intro] %s stage=%s rect=(%.0f,%.0f %.0fx%.0f) body_a=%.1f"
						% [ids[ci], stage, rr.position.x, rr.position.y,
						rr.size.x, rr.size.y, ip._body.modulate.a])
				await get_tree().process_frame
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("%s-c%d.png" % [out_path, ci])
				print("[shot=intro] %s (%s) 已存 → %s-c%d.png" % [ids[ci], stage, out_path, ci])
		elif screen == "select":
			# 选角界面验收（2026-11-09 四轮）：
			#   f00 初始布局 / f01..f08 四种转场各取「中段 + 结束」两帧
			var sel := CharacterSelectScreen.new()
			sel.setup(AiPool.all_ais())
			_swap(sel)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s-f00.png" % out_path)
			for i in 4:
				var target: int = (i + 1) % 4
				sel.select_by_index(target)
				# 中段：转场进度约 30%（SWAP_TIME=0.85），各风格差异最明显的时刻
				await get_tree().create_timer(0.26).timeout
				get_viewport().get_texture().get_image().save_png(
						"%s-f%02d.png" % [out_path, i * 2 + 1])
				# 结束态
				await get_tree().create_timer(0.65).timeout
				get_viewport().get_texture().get_image().save_png(
						"%s-f%02d.png" % [out_path, i * 2 + 2])
			print("[shot=select] 已存 9 帧 → %s-fNN.png" % out_path)
		elif screen == "fandbg":
			# 扇子专属隔离验收：全屏 1600x900、只跑 FAN，逐进度定格
			var probe_bg := ColorRect.new()
			probe_bg.color = Color("#101820")
			probe_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
			var holder := Control.new()
			holder.set_anchors_preset(Control.PRESET_FULL_RECT)
			holder.add_child(probe_bg)
			var fp := RippleSwapPortrait.new()
			fp.position = Vector2(0, 50)
			fp.size = Vector2(1600, 900)
			fp.style = RippleSwapPortrait.Style.FAN
			holder.add_child(fp)
			_swap(holder)
			await get_tree().process_frame
			var ta: Texture2D = load("res://assets/art/select/qwen.png")
			var tb: Texture2D = load("res://assets/art/select/gpt.png")
			fp.set_portrait(ta)
			fp.debug_prepare(ta, tb)
			for i in 7:
				var pr: float = [0.10, 0.25, 0.40, 0.55, 0.70, 0.82, 0.94][i]
				fp.debug_set_progress(pr)
				await get_tree().process_frame
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(
						"%s-f%02d.png" % [out_path, i])
			print("[shot=fandbg] 已存 7 帧 → %s-fNN.png" % out_path)
		elif screen == "ripple":
			# 转场逐帧验收（2026-11-08）：--ripstyle=ripple|fan|slash|hex 选风格，
			# 手动推进 shader 进度，8 个采样点各存一帧 <shotout>-fNN.png
			var probe := Control.new()
			probe.set_anchors_preset(Control.PRESET_FULL_RECT)
			var pbg2 := ColorRect.new()
			pbg2.color = Color("#0b0f18")
			pbg2.set_anchors_preset(Control.PRESET_FULL_RECT)
			probe.add_child(pbg2)
			var rp := RippleSwapPortrait.new()
			rp.position = Vector2(608, 194)
			rp.size = Vector2(384, 512)
			probe.add_child(rp)
			_swap(probe)
			var style_name := "ripple"
			for a2 in OS.get_cmdline_user_args():
				if a2.begins_with("--ripstyle="):
					style_name = a2.substr(11)
			rp.style = {
				"ripple": RippleSwapPortrait.Style.RIPPLE,
				"fan": RippleSwapPortrait.Style.FAN,
				"slash": RippleSwapPortrait.Style.SLASH,
				"hex": RippleSwapPortrait.Style.HEX,
				"petal": RippleSwapPortrait.Style.PETAL,
			}.get(style_name, RippleSwapPortrait.Style.RIPPLE)
			var next_tex: Texture2D = load("res://assets/art/ai-%s.png" % style_name \
					if style_name in ["kweno", "grock", "chatppt"] else "res://assets/art/ai-kweno.png")
			rp.debug_prepare(load("res://assets/art/ai-deepdeek.png"), next_tex)
			var dbg_pieces := false
			for a3 in OS.get_cmdline_user_args():
				if a3 == "--ripdebug":
					dbg_pieces = true
			if dbg_pieces:
				(rp._mat as ShaderMaterial).set_shader_parameter("debug_pieces", 1.0)
			var ts := [0.0, 0.05, 0.12, 0.2, 0.28, 0.36, 0.44, 0.52, 0.6, 0.7, 0.8, 0.9, 1.0]
			for i in ts.size():
				rp.debug_set_progress(float(ts[i]))
				await get_tree().process_frame
				await get_tree().process_frame
				var fimg := get_viewport().get_texture().get_image()
				fimg.save_png("%s-f%02d.png" % [out_path, i])
			print("[shot=ripple] style=%s 已存 8 帧 → %s-fNN.png" % [style_name, out_path])
		else:
			_show_menu()
	for _i in 6:
		await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err == OK:
		print("截图已保存：", out_path)
	else:
		printerr("截图失败：", err)
	get_tree().quit()


# ── Q 版角色骨架目检 ─────────────────────────────────────────
## 出三张图：
##   <shotout>            8 帧横排（循环 4 帧 + 下一循环 4 帧），叠脚底地线
##   <shotout>-sheet      2×2、放大 2 倍（验接缝 / 肩部豁口）
##   <shotout>-legs       只裁腿+裙摆下沿、放大 4 倍、4 帧横排
##   <shotout>-legs-12x   同上但 12 倍（审核要求：证明 f1/f3 真的不同）
## 另外往 .tmp/rig/rig-static.png 存静止姿态，并和 cutout.png 逐像素对比。
const RIG_DIR := "res://assets/art/rig/deepdeek"
const RIG_CUT := "res://assets/art/rig/deepdeek/cutout.png"
const RIG_CANVAS := Vector2i(192, 256)
const RIG_BAND := 26     # 每格上方的帧号条
const RIG_PAD := 6       # 每格左右留白
const RIG_BPAD := 16     # 每格底部留白（影子会画出画布下沿）
const RIG_BG := Color("#232a3a")
const RIG_GROUND := Color("#6b7796")
const RIG_SPLIT := Color("#2e3648")
## 腿部专图的裁剪窗口（画布坐标）：x 62..124、y 206..257 = 审核给的 strip（68..130, 232..283）减去格内偏移
const LEG_RECT := Rect2i(62, 206, 62, 51)
const LEG_RECT4 := Rect2i(52, 216, 84, 52)


## 楼梯选角 demo 截图验收：
##   godot --path <项目> -- --shot=stairs --shotout=<绝对路径>.png
## 截图钩子：真实走一遍许愿流程（画剑 → LLM 分析 → 生图），等卡面挂上后截图。
## 用途：虚拟桌面/无头环境下验证「生图真的生出了卡面」。
## 截图钩子：进战斗并播新手引导，截第一步（卡牌高亮）。
## 截图钩子：进战斗播新手引导，逐步截 3 张（_1/_2/_3 后缀）。
## 截图钩子：**走真实流程**（含终端转场）播新手引导，逐步截 3 张。
## 注意：不设 run.intro_played=true —— 必须验证"转场播完才弹引导"。
func _capture_tutorial(out_path: String) -> void:
	run.set_ai(AiPool.get_ai("deepdeek"))
	_show_level(_levels[0], false)
	## 转场约 4s（终端敲代码），再等手牌入场动画 0.65s，留足余量
	## 轮询等：① arena 建好 ② 手牌出来 ③ 转场结束（_busy=false）
	var waited := 0.0
	var a: ArenaScreen = null
	while waited < 30.0:
		a = _current as ArenaScreen
		if a != null and not a._busy and a._hand_views.size() > 0:
			break
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	print("[shot=tutorshot] 就绪，等了 ", waited, "s  hand=",
		a._hand_views.size() if a != null else -1)
	if a == null:
		print("[shot=tutorshot] ✗ 不在 arena")
		get_tree().quit(); return
	print("[shot=tutorshot] 当前状态: busy=", a._busy,
		" hand=", a._hand_views.size(),
		" tutorial=", (a._tutorial != null and is_instance_valid(a._tutorial)))
	if a._hand_views.is_empty():
		print("[shot=tutorshot] ✗ 没有手牌")
		get_tree().quit(); return
	## 如果没自动弹（可能已 done），强制播
	if a._tutorial == null or not is_instance_valid(a._tutorial):
		GameSettings.tutorial_always = true
		a._start_tutorial()
		await get_tree().create_timer(1.2).timeout
	var base := out_path.get_basename()
	for step in 3:
		for i in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var p := "%s_%d.png" % [base, step + 1]
		get_viewport().get_texture().get_image().save_png(p)
		## 记录洞的位置，便于核验
		if a._tutorial != null and is_instance_valid(a._tutorial):
			print("[shot=tutorshot] step%d 洞=%s → %s" % [step+1, str(a._tutorial._hole), p])
			a._tutorial.next_step()
			await get_tree().create_timer(0.4).timeout
		else:
			print("[shot=tutorshot] step%d → %s（无 overlay）" % [step+1, p])
	print("[shot=tutorshot] 完成")
	get_tree().quit()
func _capture_wish(out_path: String) -> void:
	run.set_ai(AiPool.get_ai("deepdeek"))
	_show_level(_levels[0], false)
	## 进场有终端转场（约 4s），必须等它走完，否则截到的是黑幕
	await get_tree().create_timer(5.0).timeout
	var a := _current as ArenaScreen
	if a == null:
		print("[shot=wishshot] ✗ 不在 arena")
		get_tree().quit(); return
	## 造"剑"涂鸦
	a._wish_canvas = WishCanvas.new()
	a.add_child(a._wish_canvas)
	await get_tree().process_frame
	var blade := PackedVector2Array()
	for i in 22: blade.append(Vector2(160, 70 + i * 12))
	a._wish_canvas._strokes.append({"pts": blade, "size": 14.0, "style": "round",
			"color": Color(0.08, 0.08, 0.1)})
	a._wish_canvas._strokes.append({"pts": PackedVector2Array(
			[Vector2(105, 195), Vector2(215, 195)]), "size": 13.0, "style": "round",
			"color": Color(0.08, 0.08, 0.1)})
	a._wish_canvas._strokes.append({"pts": PackedVector2Array(
			[Vector2(160, 195), Vector2(160, 255)]), "size": 17.0, "style": "round",
			"color": Color(0.08, 0.08, 0.1)})
	await get_tree().process_frame
	print("[shot=wishshot] 涂鸦就绪，路径 = ", a._wish_path())
	## 真实走流程
	a._request_vision_card(a._llm_config(), false)
	print("[shot=wishshot] 已发请求，等生图…")
	var got := ""
	for i in 360:
		await get_tree().create_timer(0.5).timeout
		for c in run.deck:
			if c.art_path != "" and c.art_path.contains("ai_cache"):
				got = c.art_path
				break
		if got != "":
			break
		if i % 20 == 0:
			print("[shot=wishshot]   %d s" % (i / 2))
	if got.is_empty():
		print("[shot=wishshot] ✗ 180s 内没生成卡面")
		get_tree().quit(); return
	print("[shot=wishshot] ✅ 卡面 = ", got)
	## 把手牌换成这张有图的卡，便于截图
	for c in run.deck:
		if c.art_path == got and a.combat != null:
			a.combat.hand.append(c)
			a._rebuild_hand()
			break
	## 涂鸦画布只是数据容器，别让它挡画面
	if a._wish_canvas != null:
		a._wish_canvas.visible = false
	for i in 30: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[shot=wishshot] 已存 → ", out_path)
	get_tree().quit()


func _capture_stairs(out_path: String) -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	var sc := SelectStairs.new()
	add_child(sc)
	await get_tree().create_timer(0.9).timeout
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[shot=stairs] 已存 → %s" % out_path)
	get_tree().quit()


## 定点验收「终端 → Godot 立绘」：假造一份终端排版（全屏 179x56 格、50 行字符画、居中），
## 然后抓 4 帧看马赛克是否收敛、矩形是否落在预期位置。配套 --nointro。
##   godot --path <项目> -w --resolution 1600x1000 -- --shot=hero --nointro --shotout=<绝对路径>.png
func _capture_hero_mosaic(out_path: String) -> void:
	var geom := "cols=179,rows=56,padx=49,pady=6,artw=80,arth=44,capx=81,capy=51"
	var gf := FileAccess.open(OS.get_temp_dir().path_join("arena_term_geom.txt"), FileAccess.WRITE)
	if gf == null:
		print("[shot=hero] 几何文件写不进去")
		get_tree().quit(1)
		return
	gf.store_string(geom)
	gf.close()

	_show_level(_levels[0])
	await get_tree().process_frame
	await get_tree().process_frame
	var arena := _current as ArenaScreen
	if arena == null:
		print("[shot=hero] 没拿到 ArenaScreen")
		get_tree().quit(1)
		return
	var tex := load("res://assets/art/rig/deepdeek-front/front-hi.png") as Texture2D
	if tex == null:
		print("[shot=hero] 立绘没读到")
		get_tree().quit(1)
		return
	arena._show_hero_portrait(tex, func() -> void: pass)
	# 立刻停住：不然后续每一帧都会推进，拍不到首帧
	if arena._hero_tween != null:
		arena._hero_tween.pause()
	await get_tree().process_frame      ## 这一帧把着色器编译掉（tween 已停，画面不变）
	var dbg := arena.get_node_or_null("HeroPortrait") as TextureRect
	var sym := arena.get_node_or_null("HeroSymbol") as SymbolFrame
	print("[shot=hero] 节点检查: portrait=%s symbol=%s" % [dbg != null, sym != null])
	if dbg != null:
		var dm := dbg.material as ShaderMaterial
		print("[shot=hero] 首帧 block=%.2f alpha=%.2f size=%s" % [
			float(dm.get_shader_parameter("block")), float(dm.get_shader_parameter("alpha")),
			str(dbg.size)])
	get_viewport().get_texture().get_image().save_png(_outname(out_path, "hero", "f0"))
	# 解冻，每 0.45s 一张：0.35 保留 → 0.35~1.25 解码 → 1.25~3.45 上色 → 3.45~4.85 收细
	arena._hero_tween.play()
	for i in range(1, 12):
		await get_tree().create_timer(0.45, true, false, true).timeout
		get_viewport().get_texture().get_image().save_png(
				_outname(out_path, "hero", "f%d" % i))
		if dbg != null:
			var m2 := dbg.material as ShaderMaterial
			print("  f%d t=%.2fs block=%.2f alpha=%.2f 解码=%.2f" % [i, i * 0.45,
				float(m2.get_shader_parameter("block")),
				float(m2.get_shader_parameter("alpha")),
				sym._shuffle if sym != null else -1.0])
	print("[shot=hero] 12 帧已存（首帧为纯符号帧）几何=%s" % geom)
	get_tree().quit()


## 只把终端脚本 + 字符画落盘（不启动终端），给宿主侧做语法与尺寸自检：
##   godot --path <项目> --headless -- --shot=termdump --shotout=<绝对路径>.txt
func _capture_term_dump(out_path: String) -> void:
	var ai_id := "deepdeek"
	var ai_name := "DeepDeek"
	if run != null and run.ai != null:
		ai_id = run.ai.id
		ai_name = run.ai.display_name
	var tex := load("res://assets/art/rig/%s-front/front-hi.png" % ai_id) as Texture2D
	var art := AsciiArt.build(tex, ExtTerminal.ART_ROWS, ExtTerminal.ART_MAX_COLS,
			ExtTerminal.CELL_ASPECT)
	if art.is_empty():
		print("[shot=termdump] 字符画为空：图没读到？")
		get_tree().quit(1)
		return
	var wmax := 0
	for l in art:
		wmax = maxi(wmax, l.length())
	var et := ExtTerminal.new()
	var body := et._compose(ai_name, IntroScript.code_for(ai_id, ai_name), art)
	et.free()
	var base := out_path.get_basename()
	# .ps1 必须带 UTF-8 BOM（和生产路径 ExtTerminal.play 一致），
	# 否则 PS 5.1 按系统 ANSI 解码，中文注释全变乱码——自检也就白验了
	for pair in [[base + ".txt", "\n".join(art) + "\n", false], [base + ".ps1", body, true]]:
		var f := FileAccess.open(pair[0], FileAccess.WRITE)
		if f != null:
			if bool(pair[2]):
				f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
			f.store_string(pair[1])
			f.close()
	print("[shot=termdump] %d 行 / 最宽 %d 列 → %s.ps1" % [art.size(), wmax, base])
	get_tree().quit()


func _capture_rig(out_path: String) -> void:
	var sheet_path := _outname(out_path, "strip", "sheet")
	var legs_path := _outname(out_path, "strip", "legs")
	var legs12_path := _outname(out_path, "strip", "legs-12x")

	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_swap(host)

	var bg := ColorRect.new()
	bg.color = RIG_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	var rig: ChibiRig = ChibiRigScene.new()
	rig.position = Vector2(160, 180)
	host.add_child(rig)
	rig.setup(RIG_DIR)
	rig.set_speed(0.0)

	var tag := Label.new()
	tag.add_theme_font_size_override("font_size", 18)
	tag.add_theme_color_override("font_color", Color("#9fb0d8"))
	host.add_child(tag)

	# ── 静止姿态：和 cutout.png 逐像素对比，确认切件对位 ──
	for _k in 6:
		await get_tree().process_frame
	var still := _grab_viewport()
	print("[shot=rig] 静止对位自检：%s" % _rig_static_check(still, rig.position))
	DirAccess.make_dir_recursive_absolute("res://.tmp/rig")
	_crop(still, rect_of(rig.position, 1)).save_png("res://.tmp/rig/rig-static.png")

	# ── 亚帧检查：帧与帧之间取 32 个采样点，确认腿不会被插值压到地线以下 ──
	# （用 CUBIC 的话这里会读到 dy≈+1.2，支撑脚在中间帧穿地；腿轨已改 LINEAR）
	var worst := 0.0
	for k in 32:
		var p := rig.debug_seek_walk(float(k) / 8.0)
		for nm in ["leg_l", "leg_r"]:
			worst = maxf(worst, float(p.get("dy_" + nm, 0.0)))
	print("[shot=rig] 亚帧检查：腿的最大下沉 dy=%.2f（>0 就是穿地）" % worst)

	# ── ① 8 帧横排（1x）：循环 4 帧 + 下一循环 4 帧 ──
	var cw := RIG_CANVAS.x + RIG_PAD * 2
	var ch := RIG_BAND + RIG_CANVAS.y + RIG_BPAD
	var strip := Image.create_empty(cw * 8, ch, false, Image.FORMAT_RGBA8)
	strip.fill(RIG_BG)
	var cells: Array[Image] = []
	for i in 8:
		tag.text = "f%d" % i
		tag.position = rig.position + Vector2(-RIG_PAD + 6, -RIG_BAND + 2)
		var pose := rig.debug_seek_walk(i)
		for _k in 3:
			await get_tree().process_frame
		var img := _crop(_grab_viewport(), rect_of(rig.position, 1))
		# 拼到第 i 格；seek 内部走 fposmod → 第 4..7 帧就是下一次循环
		strip.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * cw, 0))
		if i < 4:
			cells.append(img)
		print("[shot=rig] f%d %s" % [i, str(pose)])
	# 地线 + 分格线：沿整条图直线画过去，任何一帧脚离地都看得见
	var sole_y := RIG_BAND + RIG_CANVAS.y
	for x in strip.get_width():
		strip.set_pixel(x, sole_y, RIG_GROUND)
		strip.set_pixel(x, sole_y + 1, RIG_GROUND.darkened(0.55))
	for i in range(1, 8):
		for y in ch:
			strip.set_pixel(i * cw, y, RIG_SPLIT)
	strip.save_png(out_path)

	# ── ② 2×2 放大 2 倍（4 帧）：看部件接缝 / 肩部 ──
	rig.scale = Vector2(2, 2)
	rig.position = Vector2(60, 60)
	tag.add_theme_font_size_override("font_size", 22)
	var cw2 := RIG_CANVAS.x * 2 + RIG_PAD * 2
	var ch2 := RIG_BAND + RIG_CANVAS.y * 2 + RIG_BPAD
	var sheet := Image.create_empty(cw2 * 2, ch2 * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(RIG_BG)
	for i in ChibiRigScene.WALK_FRAMES:
		tag.text = "f%d  2x" % i
		tag.position = rig.position + Vector2(-RIG_PAD + 6, -RIG_BAND + 2)
		rig.debug_seek_walk(i)
		for _k in 3:
			await get_tree().process_frame
		var img := _crop(_grab_viewport(), rect_of(rig.position, 2))
		var col := i % 2
		var row := i / 2
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i(col * cw2, row * ch2))
	var sole2 := RIG_BAND + RIG_CANVAS.y * 2
	for i in 4:
		var gx := (i % 2) * cw2
		var gy := (i / 2) * ch2 + sole2
		for x in range(gx, gx + cw2):
			sheet.set_pixel(x, gy, RIG_GROUND)
			sheet.set_pixel(x, gy + 1, RIG_GROUND.darkened(0.55))
	for y in ch2 * 2:
		sheet.set_pixel(cw2, y, RIG_SPLIT)
	for y in ch2:
		sheet.set_pixel(cw2, y, RIG_SPLIT)
	sheet.save_png(sheet_path)

	# ── ③④ 腿部专图（4x / 12x）：证明 f1 与 f3 的腿真的不同 ──
	var m4 := _leg_montage(cells, LEG_RECT4, 4)
	m4.save_png(legs_path)
	var m12 := _leg_montage(cells, LEG_RECT, 12)
	m12.save_png(legs12_path)

	# ── 数字自检（影子关掉再量，别让影子的缩放混进腿部差异）──
	var sh := rig.get_node_or_null("Root/Shadow") as CanvasItem
	if sh != null:
		sh.visible = false
	var plain: Array[Image] = []
	for i in ChibiRigScene.WALK_FRAMES:
		rig.debug_seek_walk(i)
		for _k in 2:
			await get_tree().process_frame
		plain.append(_crop(_grab_viewport(), rect_of(rig.position, 2)))
	if sh != null:
		sh.visible = true
	var leg_rect2 := Rect2i(Vector2i(RIG_PAD + LEG_RECT.position.x * 2, RIG_BAND + LEG_RECT.position.y * 2),
			LEG_RECT.size * 2)
	var pairs := []
	for i in 4:
		for j in range(i + 1, 4):
			pairs.append("f%d/f%d=%d" % [i, j, _xor_px(plain[i], plain[j], leg_rect2)])
	print("[shot=rig] 腿部区域两两 XOR（2x，%d 个采样像素）：%s" % [
		leg_rect2.size.x * leg_rect2.size.y, "  ".join(pairs)])
	var tops := []
	for i in 4:
		tops.append((_top_ink_row(plain[i], RIG_BAND, Vector2i(RIG_PAD + 20, RIG_PAD + 172)) - RIG_BAND) / 2)
	print("[shot=rig] 头顶 y（画布坐标）：%s  极差=%d" % [str(tops), tops.max() - tops.min()])
	print("横排已保存：%s（%dx%d）" % [out_path, strip.get_width(), strip.get_height()])
	print("放大图已保存：%s（%dx%d）" % [sheet_path, sheet.get_width(), sheet.get_height()])
	print("腿部4x已保存：%s（%dx%d）" % [legs_path, m4.get_width(), m4.get_height()])
	print("腿部12x已保存：%s（%dx%d）" % [legs12_path, m12.get_width(), m12.get_height()])
	get_tree().quit()


func _outname(path: String, from_tag: String, to_tag: String) -> String:
	var p := path.replace("-" + from_tag, "-" + to_tag)
	if p == path:
		p = path.get_basename() + "-" + to_tag + ".png"
	return p


## 把一个画布区域的 4 帧裁出来、放大 zoom 倍、横排；每格上方带帧号（从单元格里裁的）。
func _leg_montage(cells: Array, canvas_rect: Rect2i, zoom: int) -> Image:
	var w := canvas_rect.size.x * zoom
	var h := canvas_rect.size.y * zoom
	var gap := 8
	var out := Image.create_empty(gap + cells.size() * (w + gap), 26 + h + gap, false, Image.FORMAT_RGBA8)
	out.fill(RIG_BG)
	var src := Rect2i(canvas_rect.position + Vector2i(RIG_PAD, RIG_BAND), canvas_rect.size)
	var line_y := 26 + (RIG_CANVAS.y - canvas_rect.position.y) * zoom
	for i in cells.size():
		var cell: Image = cells[i]
		var part := cell.get_region(src)
		part.resize(w, h, Image.INTERPOLATE_NEAREST)
		var ox := gap + i * (w + gap)
		out.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(ox, 26))
		var lab := cell.get_region(Rect2i(2, 2, 56, 22))
		out.blit_rect(lab, Rect2i(Vector2i.ZERO, lab.get_size()), Vector2i(ox + 2, 2))
		for x in range(ox - gap, ox):
			for y in out.get_height():
				out.set_pixel(x, y, RIG_SPLIT)
	if line_y >= 0 and line_y < out.get_height():
		for x in out.get_width():
			out.set_pixel(x, line_y, RIG_GROUND)
			if line_y + 1 < out.get_height():
				out.set_pixel(x, line_y + 1, RIG_GROUND.darkened(0.55))
	return out


## ── walk 动图抓帧 ────────────────────────────────────────────
## --shot=rigwalk：真实播放 walk，24fps 采样（walk 8fps × 每帧 3 个亚帧，含插值姿态），
## 抓 2 个循环 = 48 张 PNG 到 res://.tmp/riggif/，交给 ffmpeg 拼成 GIF。
## 姿态走 debug_seek_walk(帧号/3.0) 逐拍定格——和真实播放逐帧等价，但不会漏采样。
func _capture_rig_walk(out_path: String) -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_swap(host)

	var bg := ColorRect.new()
	bg.color = RIG_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	var rig: ChibiRig = ChibiRigScene.new()
	rig.scale = Vector2(2, 2)
	# 2x 画布 384×512，窗口 720 高：top=60 → 脚底 572，影子（到画布 y≈260）不裁
	rig.position = Vector2(200, 60)
	host.add_child(rig)
	rig.setup(RIG_DIR)
	rig.play("walk")

	# 地线垫在角色后面（树序：bg → ground → rig），脚踩在线上看得更清
	var ground_y := int(rig.position.y) + RIG_CANVAS.y * 2
	var ground := ColorRect.new()
	ground.color = RIG_GROUND
	ground.position = Vector2(0, ground_y)
	ground.size = Vector2(4096, 2)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(ground)
	host.move_child(ground, 1)

	var out_dir := "res://.tmp/riggif"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var fps := 24
	var frames := fps * 2   # 2 个循环
	for i in frames:
		rig.debug_seek_walk(float(i) * ChibiRigScene.WALK_FPS / float(fps))
		for _k in 3:
			await get_tree().process_frame
		var crop := Rect2i(Vector2i(rig.position) - Vector2i(20, 16),
				Vector2i(RIG_CANVAS.x * 2 + 40, RIG_CANVAS.y * 2 + 64))
		_crop(_grab_viewport(), crop).save_png("%s/w%03d.png" % [out_dir, i])
	print("[shot=rigwalk] %d 张已保存：%s（fps=%d，时长 %.2f 秒）→ 用 ffmpeg 拼 GIF" % [
		frames, out_dir, fps, float(frames) / fps])


## ── 进入游戏进度条 + Q 版跑动 演示 ──────────────────────────
## --shot=loadrun：进度条 0→100%（4 秒），Q 版 DeepSeek 用 run 动作跟着填充边缘跑。
## 24fps 抓 96 张 PNG 到 res://.tmp/loadrun/，ffmpeg 拼 GIF。
## 确定性抓帧：每帧直接 set_value + debug_seek("run", t*RUN_FPS)，和真实播放逐帧等价。
const LOADRUN_BAR := Rect2(280, 590, 720, 80)   ## 进度条位置与尺寸（720x80 = 资产 360x40 ×2）
const LOADRUN_SCALE := 0.6                       ## 角色显示缩放（0.6 = 115×154）
const LOADRUN_FPS := 24
const LOADRUN_SECS := 4.0
const LOADRUN_RIG := "res://assets/art/rig/deepdeek-side"       ## 侧面切件（面朝右）
const LOADRUN_FRONT := "res://assets/art/rig/deepdeek-front/front.png"   ## 正面精灵（备用：平面 twirl 不再用，留给以后多视角方案）
## 跳舞转圈窗口（进度区间）：经过时边前进边自转一圈，期间条继续走
const DANCE_WINDOWS := [Vector2(0.26, 0.48), Vector2(0.60, 0.82)]
## 8 视角旋转序列（turnaround sheet 切片；s0=正面 … s4=背面 … 顺时针 45°/帧）
const SPIN_DIR := "res://assets/art/rig/deepdeek-spin"
const SPIN_FRAMES := 8
## LoadBar 内槽的显示坐标（SLOT 常量 ×2 + bar 位置）
const LOADRUN_SLOT := Rect2(40, 26, 640, 28)     ## 相对 bar 左上角的内槽矩形


func _capture_loadrun(out_path: String) -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_swap(host)

	var bg := ColorRect.new()
	bg.color = Color("#10141f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	# 标题（进度条上方，抬高避开跳舞的角色）
	var title := Label.new()
	title.text = "进入游戏"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#9fb0d8"))
	title.position = Vector2(LOADRUN_BAR.position.x, LOADRUN_BAR.position.y - 116)
	host.add_child(title)

	# 生图进度条（track 框 + 引擎填充）
	var bar := LoadBar.new()
	bar.position = LOADRUN_BAR.position
	host.add_child(bar)

	# Q 版角色：挂在「舞者 wrapper」下，画布中心对齐 wrapper 原点，
	# 这样旋转/缩放/位移全部绕身体中心，跑步与跳舞共用一套定位。
	var rig: ChibiRig = ChibiRigScene.new()
	rig.setup(LOADRUN_RIG)
	rig.play("run")

	# 舞者 wrapper：跳舞时绕「腰轴」做平面内整体旋转（twirl）。
	var dancer := Node2D.new()
	dancer.name = "Dancer"
	host.add_child(dancer)
	rig.position = Vector2(-RIG_CANVAS.x * 0.5, -RIG_CANVAS.y * 0.5)
	dancer.add_child(rig)
	var rig_shadow := rig.get_node_or_null("Root/Shadow") as CanvasItem

	# 自转序列帧精灵（8 视角；只在跳舞窗口显示，替掉 rig）
	var spin_frames: Array[Texture2D] = []
	for k in SPIN_FRAMES:
		spin_frames.append(load("%s/s%d.png" % [SPIN_DIR, k]) as Texture2D)
	var spin := Sprite2D.new()
	spin.name = "Spin"
	spin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 帧画布 192x256、脚底在 y=248 → 节点原点 = 脚底中心
	spin.centered = false
	spin.offset = Vector2(-96, -248)
	spin.scale = Vector2.ONE * LOADRUN_SCALE
	spin.visible = false
	host.add_child(spin)

	var out_dir := "res://.tmp/loadrun"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var frames := int(LOADRUN_FPS * LOADRUN_SECS)
	for i in frames:
		var t := float(i) / float(frames - 1)          ## 0..1
		var v := minf(t * 1.06, 1.0)                   ## 前 94% 走完，结尾停一小拍
		bar.set_value(v)
		var edge := LOADRUN_BAR.position.x + LOADRUN_SLOT.position.x + LOADRUN_SLOT.size.x * v

		# ── 跳舞：8 视角序列帧自转（竖轴旋转，身体始终直立），边前进边转 ──
		#   进度进入窗口 → 用角度帧轮播一整圈（s0 正 → s2 侧 → s4 背 → s6 侧 → 回s0）；
		#   期间进度条不停（边走边转），落地带轻微上下弹。
		var in_dance := false
		var dance_p := 0.0
		for w: Vector2 in DANCE_WINDOWS:
			if v >= w.x and v <= w.y:
				in_dance = true
				dance_p = (v - w.x) / (w.y - w.x)
		if in_dance:
			rig.visible = false
			spin.visible = true
			spin.texture = spin_frames[mini(int(dance_p * SPIN_FRAMES), SPIN_FRAMES - 1)]
			var hop := -absf(sin(dance_p * PI * 4.0)) * 6.0     ## 转圈时的小弹跳
			spin.position = Vector2(edge, LOADRUN_BAR.position.y + hop)
		else:
			rig.visible = true
			spin.visible = false
			dancer.position = Vector2(edge, LOADRUN_BAR.position.y - 126.0 * LOADRUN_SCALE)
			dancer.rotation = 0.0
			dancer.scale = Vector2.ONE * LOADRUN_SCALE
			if rig_shadow != null:
				rig_shadow.visible = true
			rig.debug_seek("run", t * LOADRUN_SECS * ChibiRig.RUN_FPS)
		for _k in 3:
			await get_tree().process_frame
		# 裁剪带：只留角色 + 进度条附近（GIF 体积友好）
		var crop := Rect2i(160, int(LOADRUN_BAR.position.y) - 200, 960, 300)
		_crop(_grab_viewport(), crop).save_png("%s/l%03d.png" % [out_dir, i])
	print("[shot=loadrun] %d 张已保存：%s（fps=%d，时长 %.1f 秒）→ 用 ffmpeg 拼 GIF" % [
		frames, out_dir, LOADRUN_FPS, LOADRUN_SECS])


## 一格在视口里的裁剪矩形：左 pad、上帧号条、右 pad、下 pad。
func rect_of(origin: Vector2, scale_f: int) -> Rect2i:
	return Rect2i(Vector2i(origin) - Vector2i(RIG_PAD, RIG_BAND),
			Vector2i(RIG_CANVAS.x * scale_f + RIG_PAD * 2,
					RIG_BAND + RIG_CANVAS.y * scale_f + RIG_BPAD))


func _grab_viewport() -> Image:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _crop(img: Image, r: Rect2i) -> Image:
	var rr := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	return img.get_region(rr)


## 和底色差得够远 = 有墨（角色）；影子比底色更暗，也算墨，所以量的那次要先把影子关掉。
func _is_ink(c: Color) -> bool:
	return absf(c.r - RIG_BG.r) + absf(c.g - RIG_BG.g) + absf(c.b - RIG_BG.b) > 0.047


func _xor_px(a: Image, b: Image, r: Rect2i) -> int:
	var n := 0
	for y in range(r.position.y, min(r.position.y + r.size.y, a.get_height())):
		for x in range(r.position.x, min(r.position.x + r.size.x, a.get_width())):
			if _is_ink(a.get_pixel(x, y)) != _is_ink(b.get_pixel(x, y)):
				n += 1
	return n


## 从 y0 往下扫，第一行有墨的 y（返回绝对 y）。
func _top_ink_row(img: Image, y0: int, xr: Vector2i) -> int:
	for y in range(y0, min(y0 + 320, img.get_height())):
		for x in range(xr.x, min(xr.y, img.get_width())):
			if _is_ink(img.get_pixel(x, y)):
				return y
	return -1


## 静止姿态 vs cutout.png：把 cutout 按 RIG_BG 底色合成为期望图，逐像素比。
## 全对位 → 差异像素 0；有错位/重影 → 成片差异。
func _rig_static_check(shot: Image, origin: Vector2) -> String:
	if not FileAccess.file_exists(RIG_CUT):
		return "跳过（没有 cutout.png）"
	if not FileAccess.file_exists(RIG_DIR.path_join("rig.json")):
		return "跳过（rig.json 不存在 = 跑的是占位骨架，比原图没有意义）"
	var cut := Image.load_from_file(ProjectSettings.globalize_path(RIG_CUT))
	if cut == null:
		return "跳过（cutout.png 读不出来）"
	cut.convert(Image.FORMAT_RGBA8)
	var cell := _crop(shot, rect_of(origin, 1))
	# 影子也在这个格子里，但它不参与"拼回去像不像原图"，所以只比有影子的那张会误报
	# → 这里比的是 alpha 复合后的颜色，影子在 8 件之外，需要先排除掉
	var got := _crop(cell, Rect2i(Vector2i(RIG_PAD, RIG_BAND), RIG_CANVAS))
	var bad := 0
	var worst := 0
	for y in RIG_CANVAS.y:
		for x in RIG_CANVAS.x:
			var c := cut.get_pixel(x, y)
			var want := Color(
				c.r * c.a + RIG_BG.r * (1.0 - c.a),
				c.g * c.a + RIG_BG.g * (1.0 - c.a),
				c.b * c.a + RIG_BG.b * (1.0 - c.a))
			var g := got.get_pixel(x, y)
			# 原图透明的地方，影子可能盖上来 → 只比原图不透明的位置
			if c.a < 0.5:
				continue
			var d := maxf(absf(want.r - g.r), maxf(absf(want.g - g.g), absf(want.b - g.b)))
			if d > 0.04:
				bad += 1
				worst = maxi(worst, int(d * 255.0))
	return "差异像素 %d（只比原图不透明的像素，最大通道差 %d）%s" % [
		bad, worst, "" if bad == 0 else "  ← 有错位，查一下"]


# ── ★ 梗卡机制实战验收 ─────────────────────────────────
## 三件事必须**亲眼**看到（截图 + 控制台回显），不能只读代码：
##   ① 一对：两张同点数 → 牌型/筹码/倍率正确
##   ② 同花：五张同花色 → 牌型升级
## 运行：godot --path <项目> -- --shot=memeverify --shotout=<绝对路径>.png
func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		print("截图已保存：", path)
	else:
		printerr("截图失败：", err)


# ── 测试/调试接口 ─────────────────────────────────────
## 当前挂载的界面数量。正常情况下任何时刻都应恒为 1——
## 旧界面没被 queue_free 掉就会 >1（界面会互相叠加、内存泄漏）。
func debug_screen_count() -> int:
	var n := 0
	for c in get_children():
		if c is Control and not c.is_in_group("sandbox"):
			n += 1
	return n


## 测试用：直接跳到某个界面
func debug_show(screen: String) -> void:
	match screen:
		"menu":
			_show_menu()
		"map":
			_show_map()
		"event":
			_show_event(0)
		"event_ai":
			_start_event_flow()
		"arena":
			_show_level(_levels[0])
			# 等终端进场转场走完（~4s）再拍，否则是黑屏（2026-11-07 同 wishpanel）
			await get_tree().create_timer(4.5).timeout
		"reward":
			_show_reward()
		"result":
			_show_result(true)
