class_name Affection
extends RefCounted
## Deep Sick 的好感度（2026-11-07）：跨局持久的**元进度**，不属于单局 Run。
##
## 设计（主人钦定）：
##   - 好感点无上限；对外表现的「等级」按**对数**增长 —— K·ln(1 + points/P)，
##     前期一点顶一点，后期越涨越慢，永不封顶。
##   - 来源：战斗里喂白米饭（每碗 +RICE_POINTS）、商店买好感度礼物。
##   - 去向：许愿卡品质 —— 伤害预算 / 状态档位 / 机制数量 随等级抬升（见 WishCardFactory）。
##
## 持久化：user://affection.cfg（跨局保留，卸档重开不清空）。

const SAVE_PATH := "user://affection.cfg"
const SECTION := "affection"

## 等级曲线：level = K · ln(1 + points / P)
const LEVEL_K := 5.0
const LEVEL_P := 12.0
## 每碗白米饭的好感点（战斗里吃下就算喂到）
const RICE_POINTS := 2.0

static var points := 0.0


static func level() -> int:
	return int(floor(LEVEL_K * log(1.0 + points / LEVEL_P)))


## 距下一级还差多少点（UI 进度用）
static func level_progress() -> float:
	var lv := float(level())
	var lo := (exp(float(lv) / LEVEL_K) - 1.0) * LEVEL_P
	var hi := (exp(float(lv + 1) / LEVEL_K) - 1.0) * LEVEL_P
	return clampf((points - lo) / maxf(0.0001, hi - lo), 0.0, 1.0)


## 加好感；返回加完后的等级（ arena / 商店拿它做提示）
static func add(pts: float) -> int:
	points = maxf(0.0, points + pts)
	save()
	return level()


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "points", points)
	cf.save(SAVE_PATH)


static func load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	points = float(cf.get_value(SECTION, "points", 0.0))


## 机制预算：好感越高，许愿卡允许的 op 数越多（1 → 2 → 3 封顶）
static func feature_ops() -> int:
	var lv := level()
	var ops := 1
	if lv >= 12:
		ops += 1
	if lv >= 28:
		ops += 1
	return mini(ops, 3)


## 状态档位加成：lv≥10 +1 档、lv≥25 再 +1（上限仍是规格里的 3 档）
static func tier_boost() -> int:
	var lv := level()
	var b := 0
	if lv >= 10:
		b += 1
	if lv >= 25:
		b += 1
	return b


## 数值加成：伤害/格挡预算的额外上限
static func damage_bonus() -> int:
	return mini(level(), 12)


## 画质：lv≥8 起把「精修」要求写进提示词，lv≥15 给更大的输出预算
static func quality_tier() -> int:
	var lv := level()
	if lv >= 15:
		return 2
	if lv >= 8:
		return 1
	return 0
