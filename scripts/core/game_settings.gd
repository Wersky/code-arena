class_name GameSettings
extends Object
## 玩家设置（存 user://arena_settings.cfg）。
##
## 目前只有一项：终端进场的打字速度（开始界面可切）。
## 为什么放这里：终端脚本是外部宿主跑的，参数得由游戏算好后传进去。

const PATH := "user://arena_settings.cfg"
## 配置版本。**改默认值时必须 +1**，否则主人本地存的旧值会盖掉新默认（迁移见 load_from_disk）。
const CFG_VERSION := 3

## 三档速度：名字 / 该档的**目标总时长**(ms)
## 为什么用「目标总时长」而不是每字间隔：文案会加长，而主人要求「行数加长但总耗时不变」。
## 具体怎么摊到每一拍，由终端脚本运行时自校准（见 ExtTerminal 的打字段）。
const SPEED_NAMES := ["慢", "中", "快"]
const SPEED_TOTAL_MS := [6800, 2400, 900]

static var term_speed: int = 0        ## 0=慢（默认） 1=中 2=快
## 终端窗口模式：true = 真全屏（**默认**）；false = 最大化（铺满但不隐藏任务栏）
static var term_fullscreen: bool = true
## 水波转场速度（2026-11-08 主人要求可调）：一次 swap 的总时长（秒）。
## demo 页滑杆拖完即存盘——主人调好的数值跨启动记住。
static var ripple_swap_time := 0.7

## ── 选角界面一人一款转场的**独立**速度（2026-11-09 主人要求每款单独可调）──
## 键名对应 RippleSwapPortrait.Style：ripple / fan / slash / hex
## 默认值就是之前统一的 0.85s；主人在左下角调参器改了就以此为准，跨启动记住。
static var select_swap_time := {
	"ripple": 0.85,
	"fan": 0.85,
	"slash": 0.85,
	"hex": 0.85,
}
## 调参器允许范围（秒）
const SELECT_SWAP_MIN := 0.20
const SELECT_SWAP_MAX := 3.00

## ── 选角大立绘「呼吸」参数（2026-11-09，F1 呼吸调试面板 BreathDebugPanel）──
## 四人共用这一组基线；各自错相由 CharacterSelectScreen 按角色下标叠加，不在这里存。
## mode: 0 = UV 微起伏（默认）｜1 = 仅整图缩放｜2 = 关闭
## 注意：这是**新增**键，不是改默认值 —— 缺项时 get_value 会回落默认，
## 所以 CFG_VERSION 保持 3 不变（若 +1 会触发下面 v2 迁移把 term_fullscreen 重置成 true，
## 反而把主人选过的「铺满屏幕」冲掉）。
## 默认值单独立成常量：load 时的 fallback 必须用**常量**，不能用 static var 自己
## （否则内存里被改脏过就再也回不到出厂值了，实测踩过）。
const BREATH_AMP_DEF := 0.008   ## 位移幅度（UV 单位，0.008 = 0.8%）
const BREATH_PERIOD_DEF := 4.0  ## 周期（秒）
const BREATH_PHASE_DEF := 0.0   ## 基准相位（0~1，1 = 一个整周期）
const BREATH_MODE_DEF := 0      ## 0=上下起伏 1=左右起伏 2=整图缩放 3=关闭

static var breath_amp := BREATH_AMP_DEF
static var breath_period := BREATH_PERIOD_DEF
static var breath_phase := BREATH_PHASE_DEF
static var breath_mode := BREATH_MODE_DEF

## 面板滑杆的取值范围（唯一真相，BreathDebugPanel 直接引用）
const BREATH_AMP_MIN := 0.0
const BREATH_AMP_MAX := 0.08   ## 上限抬到 0.08（主人 2026-11-10 反馈 0.008 完全看不到，留足调试余量）
const BREATH_PERIOD_MIN := 1.0
const BREATH_PERIOD_MAX := 8.0
const BREATH_PHASE_MIN := 0.0
const BREATH_PHASE_MAX := 1.0
const BREATH_MODE_MAX := 3

## ── 2026-11-10 主人要求：呼吸参数按**角色**独立，且每层可单独调 ──────────
## 每角色一套：amp / period / phase / mode + 三层各自的 gain / phase 偏移。
## 四个角色的默认值不是随便填的，按各自画面里头发/身体的实际占比反推：
##   Qwen  头发占比最大(23%) → 头发出彩、身体收敛
##   GPT   头发仅 4%、身体 9% → 反向补偿，让可见部分动得明显
##   Grok  双马尾弹性大 → 头发领先更多
##   DeepSeek 长卷发居中
const BREATH_CHARS := ["deepdeek", "kweno", "chatppt", "grock"]
## 每角色的出厂预设：{layer_gain, layer_phase} × 3 层
const BREATH_PRESETS := {
	"deepdeek": {"hair_gain": 1.00, "face_gain": 0.60, "body_gain": 0.32,
			"hair_phase": 0.06, "face_phase": 0.00, "body_phase": -0.07},
	"kweno": {"hair_gain": 1.00, "face_gain": 0.58, "body_gain": 0.28,
			"hair_phase": 0.07, "face_phase": 0.00, "body_phase": -0.08},
	"chatppt": {"hair_gain": 0.85, "face_gain": 0.70, "body_gain": 0.42,
			"hair_phase": 0.04, "face_phase": 0.00, "body_phase": -0.05},
	"grock": {"hair_gain": 1.05, "face_gain": 0.62, "body_gain": 0.35,
			"hair_phase": 0.06, "face_phase": 0.00, "body_phase": -0.07},
}
## 分层滑杆范围（gain 与 phase 共用一套，面板直接引用）
const BREATH_GAIN_MIN := 0.0
const BREATH_GAIN_MAX := 1.5
const BREATH_LAYER_PHASE_MIN := -0.35
const BREATH_LAYER_PHASE_MAX := 0.35
const BREATH_LAYER_KEYS := ["hair_gain", "face_gain", "body_gain",
		"hair_phase", "face_phase", "body_phase"]

## 四个角色各自的分层参数（运行时唯一真相），初始 = 出厂预设
static var breath_layers := {}


static func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var ver := int(cfg.get_value("meta", "version", 1))
	term_speed = clampi(int(cfg.get_value("term", "speed", 0)), 0, 2)
	term_fullscreen = bool(cfg.get_value("term", "fullscreen", true))
	ripple_swap_time = clampf(float(cfg.get_value("ripple", "swap_time", 0.7)), 0.15, 10.0)
	# 选角转场速度（v3 起）：缺项沿用默认 0.85
	for k in select_swap_time.keys():
		var v := float(cfg.get_value("select_swap", String(k), float(select_swap_time[k])))
		select_swap_time[k] = clampf(v, SELECT_SWAP_MIN, SELECT_SWAP_MAX)
	# 立绘呼吸参数（独立 section；本项**新增**，老配置取不到就回落常量默认，无需迁移）
	breath_amp = clampf(float(cfg.get_value("breath", "amp", BREATH_AMP_DEF)),
			BREATH_AMP_MIN, BREATH_AMP_MAX)
	breath_period = clampf(float(cfg.get_value("breath", "period", BREATH_PERIOD_DEF)),
			BREATH_PERIOD_MIN, BREATH_PERIOD_MAX)
	breath_phase = clampf(float(cfg.get_value("breath", "phase", BREATH_PHASE_DEF)),
			BREATH_PHASE_MIN, BREATH_PHASE_MAX)
	breath_mode = clampi(int(cfg.get_value("breath", "mode", BREATH_MODE_DEF)),
			0, BREATH_MODE_MAX)
	# 四角色各自的分层参数：新键优先，缺项回落出厂预设（旧存档无这些键 → 全走出厂值）
	breath_layers = {}
	for cid in BREATH_CHARS:
		var preset: Dictionary = BREATH_PRESETS[cid]
		var d := {}
		for k in BREATH_LAYER_KEYS:
			var sect := "breath_%s" % cid
			var lo := BREATH_GAIN_MIN if String(k).ends_with("gain") else BREATH_LAYER_PHASE_MIN
			var hi := BREATH_GAIN_MAX if String(k).ends_with("gain") else BREATH_LAYER_PHASE_MAX
			d[k] = clampf(float(cfg.get_value(sect, k, float(preset[k]))), lo, hi)
		breath_layers[cid] = d
	if ver < CFG_VERSION:
		# v2：窗口模式默认改成真全屏。老配置只迁移这一次，之后主人自己切就尊重设置。
		term_fullscreen = true
		save_to_disk()


static func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", CFG_VERSION)
	cfg.set_value("term", "speed", term_speed)
	cfg.set_value("term", "fullscreen", term_fullscreen)
	cfg.set_value("ripple", "swap_time", ripple_swap_time)
	for k in select_swap_time.keys():
		cfg.set_value("select_swap", String(k), float(select_swap_time[k]))
	cfg.set_value("breath", "amp", breath_amp)
	cfg.set_value("breath", "period", breath_period)
	cfg.set_value("breath", "phase", breath_phase)
	cfg.set_value("breath", "mode", breath_mode)
	# 四角色分节（每角色一个 [breath_<id>] 段，六个键）
	for cid in BREATH_CHARS:
		if not breath_layers.has(cid):
			continue
		var d2: Dictionary = breath_layers[cid]
		for k in BREATH_LAYER_KEYS:
			cfg.set_value("breath_%s" % cid, k, float(d2.get(k, 0.0)))
	cfg.save(PATH)


## 取某个转场风格在选角界面的时长（秒）
static func select_time_for(style_key: String) -> float:
	if not select_swap_time.has(style_key):
		return 0.85
	return clampf(float(select_swap_time[style_key]), SELECT_SWAP_MIN, SELECT_SWAP_MAX)


## 设置并立刻存盘（调参器滑杆用）
static func set_select_time(style_key: String, sec: float) -> void:
	if not select_swap_time.has(style_key):
		return
	select_swap_time[style_key] = clampf(sec, SELECT_SWAP_MIN, SELECT_SWAP_MAX)
	save_to_disk()


## ── 立绘呼吸参数（F1 面板用；四个值一次写清，避免滑杆连拖时刷 4 次盘）──
## 注意：**不自动存盘**，由调用方决定何时 save_to_disk()（面板在拖动结束时存）。
static func set_breath(p_amp: float, p_period: float, p_phase: float, p_mode: int) -> void:
	breath_amp = clampf(p_amp, BREATH_AMP_MIN, BREATH_AMP_MAX)
	breath_period = clampf(p_period, BREATH_PERIOD_MIN, BREATH_PERIOD_MAX)
	breath_phase = clampf(p_phase, BREATH_PHASE_MIN, BREATH_PHASE_MAX)
	breath_mode = clampi(p_mode, 0, BREATH_MODE_MAX)


## 呼吸参数快照（键名与 BreathDebugPanel.get_params() 一致）
## 取某角色某层的参数（缺项回落出厂预设，永不返回 null）
static func breath_layer(cid: String, key: String) -> float:
	if breath_layers.has(cid):
		var d: Dictionary = breath_layers[cid]
		if d.has(key):
			return float(d[key])
	var preset: Dictionary = BREATH_PRESETS.get(cid, BREATH_PRESETS["deepdeek"])
	return float(preset.get(key, 0.0))


## 取某角色三层参数的完整快照（面板切角色时整体刷新用）
static func breath_layers_of(cid: String) -> Dictionary:
	var out := {}
	for k in BREATH_LAYER_KEYS:
		out[k] = breath_layer(cid, k)
	return out


## 设某角色某层参数（夹到合法范围；**不自动存盘**，由面板松手时统一存）
static func set_breath_layer(cid: String, key: String, v: float) -> void:
	if not BREATH_CHARS.has(cid) or not BREATH_LAYER_KEYS.has(key):
		return
	var lo := BREATH_GAIN_MIN if String(key).ends_with("gain") else BREATH_LAYER_PHASE_MIN
	var hi := BREATH_GAIN_MAX if String(key).ends_with("gain") else BREATH_LAYER_PHASE_MAX
	if not breath_layers.has(cid):
		breath_layers[cid] = breath_layers_of(cid)
	(breath_layers[cid] as Dictionary)[key] = clampf(v, lo, hi)


## 一次性设某角色三层参数（面板回填 / 测试用）
static func set_breath_layers(cid: String, d: Dictionary) -> void:
	for k in BREATH_LAYER_KEYS:
		if d.has(k):
			set_breath_layer(cid, k, float(d[k]))


static func breath_params() -> Dictionary:
	return {
		"amp": breath_amp,
		"period": breath_period,
		"phase": breath_phase,
		"mode": breath_mode,
	}


static func speed_name() -> String:
	return String(SPEED_NAMES[clampi(term_speed, 0, 2)])


## 该档的代码打字**目标总时长**（毫秒）。文案加长不变，只是滚得更快。
static func type_total_ms() -> int:
	return int(SPEED_TOTAL_MS[clampi(term_speed, 0, 2)])


## 下一档（开始界面的按钮用）
static func cycle_speed() -> void:
	term_speed = (clampi(term_speed, 0, 2) + 1) % 3
	save_to_disk()


static func window_mode_name() -> String:
	return "全屏" if term_fullscreen else "铺满屏幕"


## 切换终端窗口模式：铺满屏幕（最大化） ↔ 真全屏
static func toggle_window_mode() -> void:
	term_fullscreen = not term_fullscreen
	save_to_disk()
