class_name AiPool
extends RefCounted
## 4 位 AI 娘的静态池。数据与 AiData 字段严格对应 D.1 总表。
##
## 形象资源路径一律使用**虚构名**（ai-deepdeek / ai-kweno / ai-chatppt / ai-grock），
## 美术产物的真实原型名由 integrate 任务统一重命名后再接入。

## 每位 AI 娘的解锁门槛（累计过关关数）。主人 2026-11-03 钦定：全部无需通关，初始可选。
const UNLOCK_AT := {
	"deepdeek": 0,
	"kweno": 0,
	"chatppt": 0,
	"grock": 0,
}

## 锁定态剪影图（不换资源，由 UI 把形象替换成这张纯黑剪影）
const LOCKED_SILHOUETTE := "res://assets/art/ai-locked.png"

## 选角界面背景用的大立绘（铺满全屏）：按 id 索引。
## 主人后续提供正式全屏大图 → 放进 assets/art/big/ 并改这里即可，
## 缺文件时 CharacterSelectScreen 自动退回小立绘放大，不会报错。
const BIG_PORTRAITS := {
	"deepdeek": "res://assets/art/select/deepseek.png",
	"kweno": "res://assets/art/select/qwen.png",
	"chatppt": "res://assets/art/select/gpt.png",
	"grock": "res://assets/art/select/grok.png",
}

## 4 位 AI 娘，顺序固定：DeepDeek / Kweno / ChatPPT / Grock
static func all_ais() -> Array[AiData]:
	var out: Array[AiData] = []
	out.append(_make(
		"deepdeek", "DeepDeek", "深度思考", Color(0.310, 0.757, 0.965),
		"res://assets/art/ai-deepdeek.png", false,
		PackedStringArray([
			"tas_dd_grounded", "tas_dd_constraint_tail", "tas_dd_reasoning", "tas_dd_strict",
		]),
		"先说清楚需求边界，我再动手。", "初始伙伴", "原型：deepseek"
	))
	out.append(_make(
		"kweno", "Kweno", "中文优化", Color(1.000, 0.820, 0.400),
		"res://assets/art/ai-kweno.png", false,
		PackedStringArray([
			"tas_kw_cjk", "tas_kw_long", "tas_kw_example_pair", "tas_kw_fluent",
		]),
		"中文的事，交给中文的模型。", "初始伙伴", "原型：qwen"
	))
	out.append(_make(
		"chatppt", "ChatPPT", "通用对话", Color(0.937, 0.545, 0.706),
		"res://assets/art/ai-chatppt.png", false,
		PackedStringArray([
			"tas_cp_no_example", "tas_cp_structured", "tas_cp_format", "tas_cp_neat",
		]),
		"没问题，我按你的格式来。", "初始伙伴", "原型：chatgpt"
	))
	out.append(_make(
		"grock", "Grock", "实时联网", Color(0.478, 0.792, 0.443),
		"res://assets/art/ai-grock.png", false,
		PackedStringArray([
			"tas_gr_live", "tas_gr_anchor", "tas_gr_evidence_pair", "tas_gr_fresh",
		]),
		"最新消息我刚抓到了，看看。", "初始伙伴", "原型：grok"
	))
	return out


## 按 id 取；不存在返回 null
static func get_ai(id: String) -> AiData:
	for a in all_ais():
		if a.id == id:
			return a
	return null


## 累计过关 levels_cleared 关时已解锁的 id 列表（按 all_ais 顺序）
static func unlocked_ids(levels_cleared: int) -> PackedStringArray:
	var out := PackedStringArray()
	for a in all_ais():
		if levels_cleared >= int(UNLOCK_AT.get(a.id, 999)):
			out.append(a.id)
	return out


## 给选择界面用：4 位 AI 娘，按已解锁状态设置好 locked 标记与 unlock_hint
static func ai_list_for_select(levels_cleared: int) -> Array[AiData]:
	var out: Array[AiData] = []
	for a in all_ais():
		var unlocked := levels_cleared >= int(UNLOCK_AT.get(a.id, 999))
		a.locked = not unlocked
		a.unlock_hint = _unlock_hint(a.id)
		out.append(a)
	return out


## 形象资源可能尚未就位（美术还没改名）。存在才用，不存在时降级为锁定剪影，绝不报错。
static func portrait_for(ai: AiData) -> String:
	if ai == null:
		return ""
	if ai.portrait_path != "" and ResourceLoader.exists(ai.portrait_path):
		return ai.portrait_path
	if ResourceLoader.exists(LOCKED_SILHOUETTE):
		return LOCKED_SILHOUETTE
	return ""


## 锁定态剪影图路径（资源不存在时返回空串，UI 自行降级）
static func locked_silhouette() -> String:
	if ResourceLoader.exists(LOCKED_SILHOUETTE):
		return LOCKED_SILHOUETTE
	return ""


static func _unlock_hint(id: String) -> String:

	return "初始伙伴"


static func _make(id: String, display_name: String, family: String, tint: Color,
		portrait: String, locked: bool, taste: PackedStringArray,
		intro: String, hint: String, note: String) -> AiData:
	var a := AiData.new()
	a.id = id
	a.display_name = display_name
	a.family = family
	a.tint_color = tint
	a.portrait_path = portrait
	a.locked = locked
	a.taste_rules = taste
	a.intro_line = intro
	a.bust_path = String(BIG_PORTRAITS.get(id, ""))
	a.unlock_hint = hint
	a.prototype_note = note
	return a
