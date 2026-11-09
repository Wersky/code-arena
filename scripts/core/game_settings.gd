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
