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
## 终端代码打字速度倍率（2026-11-18 主人要求做成滑杆，连续可调）。
## 1.0 = 基准（≈2.4s 总时长）；>1 更快，<1 更慢。范围 0.25x ~ 4.0x。
const TERM_SPEED_MULT_MIN := 0.25
const TERM_SPEED_MULT_MAX := 4.0
static var term_speed_mult := 1.0
## 新手引导（2026-11-18 主人要求）：三步高亮教学（卡牌 → 弃牌模式 → 愿）。
## tutorial_done = 已经完整看过一次，之后不再自动弹。
## tutorial_always = 「恒定新手模式」：每次都弹（高级选项里的开关，用于测试）。
static var tutorial_done := false
static var tutorial_always := false
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
const BREATH_AMP_DEF := 0.02    ## 位移幅度（UV 单位）。0.02 在 900 高画面上约 18px，肉眼可见
const BREATH_PERIOD_DEF := 4.0  ## 周期（秒）
const BREATH_PHASE_DEF := 0.0   ## 基准相位（0~1，1 = 一个整周期）
const BREATH_MODE_DEF := 0      ## 0=上下起伏 1=左右起伏 2=整图缩放 3=关闭

static var breath_amp := BREATH_AMP_DEF
static var breath_period := BREATH_PERIOD_DEF
static var breath_phase := BREATH_PHASE_DEF
static var breath_mode := BREATH_MODE_DEF

## 呼吸引擎（2026-11-10 V4 引入）：0=UV(V3)  1=Mesh(V4 网格顶点形变)
## 默认 V4 —— 它才能做胸腔横向外扩与头发随高度连续滞后，
## V3 的 UV 平移在数学上是刚体位移，做不出左右反向扩张。
const BREATH_ENGINE_UV := 0
const BREATH_ENGINE_MESH := 1
const BREATH_ENGINE_DEF := BREATH_ENGINE_MESH
static var breath_engine := BREATH_ENGINE_DEF

## 横向位移总开关（2026-11-10 主人反馈「像旋转」）：关掉 = 纯上下呼吸。
## 横向是「胸腔左右外扩」，纵向是「上提回落」；两者同时做强时观感偏转。
## 默认关 —— 主人明确要「上下、左右」分开，默认只做上下最稳。
static var breath_use_horiz := false

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
## 2026-11-10 V3：头发拆成 5 段各自飘动（主人口述「不同层的头发应当不同分」）。
## 每角色 8 层 × (gain, phase) = 16 个参数。
## 预设的相位设计是「从上到下依次滞后」，形成一波往下传的飘动层次：
##   h1 呆毛头顶  领先最多（最轻最灵）
##   h2/h3 左右鬓 稍领先
##   h4 长垂发    略滞后（主体，惯性大）
##   h5 末端发梢  滞后最多（被带着走）
##   face 基准 / body 滞后 / wing 最滞后
const BREATH_PRESETS := {
	"deepdeek": {
		"h1_gain": 1.15, "h2_gain": 1.00, "h3_gain": 1.00, "h4_gain": 0.80, "h5_gain": 0.60,
		"h1_phase": 0.10, "h2_phase": 0.05, "h3_phase": 0.05, "h4_phase": -0.03, "h5_phase": -0.12,
		"face_gain": 0.60, "body_gain": 0.32, "wing_gain": 0.0,
		"face_phase": 0.00, "body_phase": -0.07, "wing_phase": -0.16},
	"kweno": {
		"h1_gain": 1.15, "h2_gain": 1.05, "h3_gain": 1.05, "h4_gain": 0.85, "h5_gain": 0.65,
		"h1_phase": 0.11, "h2_phase": 0.06, "h3_phase": 0.06, "h4_phase": -0.02, "h5_phase": -0.13,
		"face_gain": 0.58, "body_gain": 0.28, "wing_gain": 0.0,
		"face_phase": 0.00, "body_phase": -0.08, "wing_phase": -0.16},
	"chatppt": {
		"h1_gain": 1.10, "h2_gain": 0.95, "h3_gain": 0.95, "h4_gain": 0.75, "h5_gain": 0.55,
		"h1_phase": 0.09, "h2_phase": 0.05, "h3_phase": 0.05, "h4_phase": -0.03, "h5_phase": -0.11,
		"face_gain": 0.70, "body_gain": 0.42, "wing_gain": 0.22,
		"face_phase": 0.00, "body_phase": -0.05, "wing_phase": -0.16},
	"grock": {
		"h1_gain": 1.20, "h2_gain": 1.05, "h3_gain": 1.05, "h4_gain": 0.82, "h5_gain": 0.62,
		"h1_phase": 0.12, "h2_phase": 0.06, "h3_phase": 0.06, "h4_phase": -0.02, "h5_phase": -0.12,
		"face_gain": 0.62, "body_gain": 0.35, "wing_gain": 0.0,
		"face_phase": 0.00, "body_phase": -0.07, "wing_phase": -0.16},
}
## 分层滑杆范围（gain 与 phase 共用一套，面板直接引用）
const BREATH_GAIN_MIN := 0.0
const BREATH_GAIN_MAX := 1.5
const BREATH_LAYER_PHASE_MIN := -0.35
const BREATH_LAYER_PHASE_MAX := 0.35
## 16 个键：5 段头发 + 脸 + 身体 + 翅膀，各带 gain 与 phase
const BREATH_LAYER_KEYS := [
	"h1_gain", "h2_gain", "h3_gain", "h4_gain", "h5_gain",
	"face_gain", "body_gain", "wing_gain",
	"h1_phase", "h2_phase", "h3_phase", "h4_phase", "h5_phase",
	"face_phase", "body_phase", "wing_phase",
]
## 面板显示用的中文短标签（顺序与 BREATH_LAYER_KEYS 一致）
const BREATH_LAYER_LABELS := [
	"呆毛顶", "左鬓", "右鬓", "长垂发", "发梢",
	"脸", "身体", "翅膀",
	"呆毛相", "左鬓相", "右鬓相", "长垂相", "发梢相",
	"脸相", "身相", "翅相",
]

## ── V4 网格形变的参数（2026-11-10）：**每角色一套**，独立于上面 V3 的 16 键 ──
## V3 的 gain/phase 是「UV 平移层」的概念；V4 是顶点位移，参数是「像素幅度 + 滞后角」，
## 两套模型不兼容，所以各存各的，互不覆盖（V3 降级回去时仍有自己那套值）。
## 键与 shader uniform 名一一对应，面板直接按 uniform 名读写。
const BREATH_V4_KEYS := [
	"amp", "chest_x", "chest_y", "belly_x", "belly_y", "head_y",
	"hair_x", "hair_y", "belly_lag_deg", "head_lag_deg",
	"hair_lag_per_height", "lock_bottom", "x_lag_deg", "y_bias",
	"env_weight",
]
## 出厂默认（**兜底**：某角色没有自己那套时才用它）
const BREATH_V4_DEFAULTS := {
	"amp": 1.0,
	"chest_x": 10.5, "chest_y": 8.5,
	"belly_x": 6.0, "belly_y": 3.2,
	"head_y": 4.5,
	"hair_x": 11.0, "hair_y": 4.0,
	"belly_lag_deg": 55.0, "head_lag_deg": 100.0,
	"hair_lag_per_height": 240.0,
	"lock_bottom": 0.12,
	"x_lag_deg": 0.0, "y_bias": 0.35,
	# 环境（背景）层：人物遮罩之外那片区域的极轻位移。
	# 0 = 背景完全静止（主人 2026-11-10 反馈「有些角色动得过了」后从 0.10 下调）。
	"env_weight": 0.0,
}
## 每角色的出厂参数（2026-11-10 主人在调试面板里逐个调好后钦定，是这三个角色的唯一真相）。
## 设计取向（主人原话归纳）：
##   deepseek 长发侧脸 → 发横/发纵拉很大（14/13.5）做飘发，胸腔几乎不横扩（0），
##              上提靠胸纵 6.5，横相滞 77° 让横竖错开避免旋转感，发高滞 645° 波浪下传。
##   kweno    正面大脸 → 各向均衡（胸横 7 / 头纵 6.5 是三人里最大），发高滞只有 55°（发短）。
##   chatppt  坐姿+大翅膀 → 幅度整体收敛（胸横 2 / 腹 1），发纵 8 做垂发，纵偏移 0.22 偏上提。
##   grock    双马尾+火焰构图 → 头纵 6.5 最大（带动整颗头），发横只 2（双马尾是硬质捆扎，
##            大幅横摆会像甩鞭），发纵 4.5 做轻微垂坠；五个滞后/偏移全 0（不要相位错开）。
const BREATH_V4_PRESETS := {
	"deepdeek": {
		"amp": 1.0, "chest_x": 0.0, "chest_y": 6.5,
		"belly_x": 4.5, "belly_y": 0.0, "head_y": 0.0,
		"hair_x": 14.0, "hair_y": 13.5,
		"belly_lag_deg": 0.0, "head_lag_deg": 47.0,
		"hair_lag_per_height": 645.0,
		"lock_bottom": 0.04,
		"x_lag_deg": 77.0, "y_bias": 0.0,
		"env_weight": 0.0,
	},
	"kweno": {
		"amp": 1.0, "chest_x": 7.0, "chest_y": 3.5,
		"belly_x": 5.5, "belly_y": 5.0, "head_y": 6.5,
		"hair_x": 6.0, "hair_y": 8.0,
		"belly_lag_deg": 50.0, "head_lag_deg": 17.0,
		"hair_lag_per_height": 55.0,
		"lock_bottom": 0.10,
		"x_lag_deg": 14.0, "y_bias": 0.12,
		"env_weight": 0.0,
	},
	"chatppt": {
		"amp": 1.0, "chest_x": 2.0, "chest_y": 6.5,
		"belly_x": 1.0, "belly_y": 1.0, "head_y": 2.5,
		"hair_x": 4.0, "hair_y": 8.0,
		"belly_lag_deg": 17.0, "head_lag_deg": 19.0,
		"hair_lag_per_height": 75.0,
		"lock_bottom": 0.18,
		"x_lag_deg": 5.0, "y_bias": 0.22,
		"env_weight": 0.0,
	},
	"grock": {
		"amp": 1.0, "chest_x": 4.0, "chest_y": 4.0,
		"belly_x": 3.0, "belly_y": 2.5, "head_y": 6.5,
		"hair_x": 2.0, "hair_y": 4.5,
		"belly_lag_deg": 0.0, "head_lag_deg": 0.0,
		"hair_lag_per_height": 0.0,
		"lock_bottom": 0.17,
		"x_lag_deg": 0.0, "y_bias": 0.0,
		"env_weight": 0.0,
	},
}
## 取某角色的出厂参数（无专属预设则回落通用默认）
static func breath_v4_preset(cid: String) -> Dictionary:
	if BREATH_V4_PRESETS.has(cid):
		return BREATH_V4_PRESETS[cid]
	return BREATH_V4_DEFAULTS
## 每键的合法区间（面板滑杆与存盘 clamp 共用，避免两边各写一份范围）
const BREATH_V4_RANGES := {
	"amp": Vector2(0.0, 3.0),
	"chest_x": Vector2(0.0, 30.0), "chest_y": Vector2(0.0, 30.0),
	"belly_x": Vector2(0.0, 30.0), "belly_y": Vector2(0.0, 30.0),
	"head_y": Vector2(0.0, 30.0),
	"hair_x": Vector2(0.0, 40.0), "hair_y": Vector2(0.0, 40.0),
	"belly_lag_deg": Vector2(0.0, 180.0), "head_lag_deg": Vector2(0.0, 180.0),
	"hair_lag_per_height": Vector2(0.0, 720.0),
	"lock_bottom": Vector2(0.0, 0.5),
	"x_lag_deg": Vector2(0.0, 180.0), "y_bias": Vector2(0.0, 1.0),
	"env_weight": Vector2(0.0, 0.5),
}

## 四个角色各自的分层参数（运行时唯一真相），初始 = 出厂预设
static var breath_layers := {}
## 四个角色各自的 V4 网格参数（运行时唯一真相），初始 = 出厂默认
static var breath_v4 := {}


static func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var ver := int(cfg.get_value("meta", "version", 1))
	term_speed = clampi(int(cfg.get_value("term", "speed", 0)), 0, 2)
	term_speed_mult = clampf(float(cfg.get_value("term", "speed_mult", 1.0)),
			TERM_SPEED_MULT_MIN, TERM_SPEED_MULT_MAX)
	tutorial_done = bool(cfg.get_value("tutorial", "done", false))
	tutorial_always = bool(cfg.get_value("tutorial", "always", false))
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
	breath_engine = clampi(int(cfg.get_value("breath", "engine", BREATH_ENGINE_DEF)),
			BREATH_ENGINE_UV, BREATH_ENGINE_MESH)
	breath_use_horiz = bool(cfg.get_value("breath", "use_horiz", false))
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
	# 四角色各自的 V4 网格参数：独立 section [breath_v4_<id>]，缺项回落出厂默认。
	# 与 V3 的 [breath_<id>] 分开存：两套参数模型互不兼容，混在一段里会互相覆盖。
	breath_v4 = {}
	for cid2 in BREATH_CHARS:
		var sect2 := "breath_v4_%s" % cid2
		var preset2: Dictionary = breath_v4_preset(cid2)
		var d2 := {}
		for k2 in BREATH_V4_KEYS:
			var rg: Vector2 = BREATH_V4_RANGES[k2]
			d2[k2] = clampf(float(cfg.get_value(sect2, k2,
					float(preset2[k2]))), rg.x, rg.y)
		breath_v4[cid2] = d2
	if ver < CFG_VERSION:
		# v2：窗口模式默认改成真全屏。老配置只迁移这一次，之后主人自己切就尊重设置。
		term_fullscreen = true
		save_to_disk()


static func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", CFG_VERSION)
	cfg.set_value("term", "speed", term_speed)
	cfg.set_value("term", "speed_mult", float(term_speed_mult))
	cfg.set_value("tutorial", "done", tutorial_done)
	cfg.set_value("tutorial", "always", tutorial_always)
	cfg.set_value("term", "fullscreen", term_fullscreen)
	cfg.set_value("ripple", "swap_time", ripple_swap_time)
	for k in select_swap_time.keys():
		cfg.set_value("select_swap", String(k), float(select_swap_time[k]))
	cfg.set_value("breath", "amp", breath_amp)
	cfg.set_value("breath", "period", breath_period)
	cfg.set_value("breath", "phase", breath_phase)
	cfg.set_value("breath", "mode", breath_mode)
	cfg.set_value("breath", "engine", breath_engine)
	cfg.set_value("breath", "use_horiz", breath_use_horiz)
	# 四角色分节（每角色一个 [breath_<id>] 段，六个键）
	for cid in BREATH_CHARS:
		if not breath_layers.has(cid):
			continue
		var d2: Dictionary = breath_layers[cid]
		for k in BREATH_LAYER_KEYS:
			cfg.set_value("breath_%s" % cid, k, float(d2.get(k, 0.0)))
	# V4 分节（每角色一个 [breath_v4_<id>] 段）
	for cid3 in BREATH_CHARS:
		if not breath_v4.has(cid3):
			continue
		var d3: Dictionary = breath_v4[cid3]
		for k3 in BREATH_V4_KEYS:
			cfg.set_value("breath_v4_%s" % cid3, k3, float(d3.get(k3, 0.0)))
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


# ── V4 网格参数存取（2026-11-10）──────────────────────────────────────
## 取某角色某 V4 参数（缺项回落**该角色**的出厂预设，永不返回 null）
static func breath_v4_get(cid: String, key: String) -> float:
	if breath_v4.has(cid):
		var d: Dictionary = breath_v4[cid]
		if d.has(key):
			return float(d[key])
	return float(breath_v4_preset(cid).get(key, 0.0))


## 取某角色全部 V4 参数（面板切角色 / mesh.setup 恢复用）
static func breath_v4_of(cid: String) -> Dictionary:
	var out := {}
	for k in BREATH_V4_KEYS:
		out[k] = breath_v4_get(cid, k)
	return out


## 设某角色某 V4 参数（夹到合法范围；**不自动存盘**，由面板松手时统一存）
static func set_breath_v4(cid: String, key: String, v: float) -> void:
	if not BREATH_CHARS.has(cid) or not BREATH_V4_KEYS.has(key):
		return
	var rg: Vector2 = BREATH_V4_RANGES[key]
	if not breath_v4.has(cid):
		breath_v4[cid] = breath_v4_of(cid)
	(breath_v4[cid] as Dictionary)[key] = clampf(v, rg.x, rg.y)


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
	## 2026-11-18：改成按**连续倍率**算（基准 2400ms）。三档 int 仍保留兼容旧 UI。
	return maxi(200, int(2400.0 / maxf(TERM_SPEED_MULT_MIN, term_speed_mult)))


## 设置终端速度倍率并落盘（滑杆用）
static func set_term_speed_mult(v: float) -> void:
	term_speed_mult = clampf(v, TERM_SPEED_MULT_MIN, TERM_SPEED_MULT_MAX)
	save_to_disk()


## 倍率 → 人类可读
## 本次进战斗要不要播新手引导
static func should_show_tutorial() -> bool:
	return tutorial_always or not tutorial_done


## 引导播完 → 记下来（恒定模式不记，方便反复测）
static func mark_tutorial_done() -> void:
	if tutorial_always:
		return
	tutorial_done = true
	save_to_disk()


static func set_tutorial_always(v: bool) -> void:
	tutorial_always = v
	save_to_disk()


static func term_speed_label() -> String:
	return "%0.2fx ｜ 约 %0.1fs" % [term_speed_mult, type_total_ms() / 1000.0]


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
