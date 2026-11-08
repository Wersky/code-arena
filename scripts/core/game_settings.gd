class_name GameSettings
extends Object
## 玩家设置（存 user://arena_settings.cfg）。
##
## 目前只有一项：终端进场的打字速度（开始界面可切）。
## 为什么放这里：终端脚本是外部宿主跑的，参数得由游戏算好后传进去。

const PATH := "user://arena_settings.cfg"
## 配置版本。**改默认值时必须 +1**，否则主人本地存的旧值会盖掉新默认（迁移见 load_from_disk）。
const CFG_VERSION := 2

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


static func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var ver := int(cfg.get_value("meta", "version", 1))
	term_speed = clampi(int(cfg.get_value("term", "speed", 0)), 0, 2)
	term_fullscreen = bool(cfg.get_value("term", "fullscreen", true))
	ripple_swap_time = clampf(float(cfg.get_value("ripple", "swap_time", 0.7)), 0.15, 10.0)
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
	cfg.save(PATH)


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
