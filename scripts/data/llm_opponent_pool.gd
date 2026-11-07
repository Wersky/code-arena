class_name LLMOpponentPool
extends RefCounted
## AI 观察者对手的本地规则池（LLM 接入 · 圆桌终案 v1.1，2026-11-03）。
##
## 职责边界：
##   - 五动作枚举 / 合法性校验 / 本地兜底 / UI 名称；
##   - 所有数值真值在 StsCombat 常量表（本文件只引用，不改写）；
##   - 不引网络、不引 UI，headless 可独立加载。
##
## 用法（battle-integration）：
##   var legal := LLMOpponentPool.legal_actions(combat)                      # StsCombat 实例
##   var legal2 := LLMOpponentPool.legal_actions(combat.ai_state_snapshot()) # 快照字典
##   var act := LLMOpponentPool.local_choose(combat)                         # 超时兜底
##   var ui := LLMOpponentPool.action_ui_name(act)                           # 口播/日志
##
## 快照字典字段以 StsCombat.ai_state_snapshot() 为准：
##   attacks_last_turn / grow_streak / mark_active / mark_mode /
##   defend_ready / charge_ready / mark_ready / taunt_ready / taunt_unlocked …

const ACTION_ATTACK := StsCombat.AI_ATTACK
const ACTION_DEFEND := StsCombat.AI_DEFEND
const ACTION_CHARGE := StsCombat.AI_CHARGE
const ACTION_MARK := StsCombat.AI_MARK
const ACTION_TAUNT := StsCombat.AI_TAUNT
const ACTIONS := [
	StsCombat.AI_ATTACK, StsCombat.AI_DEFEND, StsCombat.AI_CHARGE,
	StsCombat.AI_MARK, StsCombat.AI_TAUNT,
]
const MARK_AGGRO := StsCombat.MARK_AGGRO
const MARK_ECONOMY := StsCombat.MARK_ECONOMY
const MARK_CHAIN := StsCombat.MARK_CHAIN
const MARK_MODES := [StsCombat.MARK_AGGRO, StsCombat.MARK_ECONOMY, StsCombat.MARK_CHAIN]

const ACTION_ALIASES := {
	"攻击": "ATTACK", "防御": "DEFEND", "蓄力": "CHARGE",
	"标记": "MARK", "针对标记": "MARK", "嘲讽": "TAUNT", "嘲讽吞噬": "TAUNT",
}
const MODE_ALIASES := {
	"连攻": "AGGRO", "攻击": "AGGRO", "发育": "ECONOMY",
	"经济": "ECONOMY", "连段": "CHAIN",
}


## 五动作枚举（白名单顺序）。
static func all_actions() -> Array[String]:
	var out: Array[String] = []
	for a in ACTIONS:
		out.append(String(a))
	return out


## 合法性校验：state 可传 StsCombat 实例或 ai_state_snapshot() 字典。
## action 支持 "MARK" 与 "MARK:AGGRO/ECONOMY/CHAIN"。
static func is_legal(action: String, state = null) -> bool:
	var act := normalize_action(action)
	if act.begins_with("MARK:"):
		if not MARK_MODES.has(act.substr(5)):
			return false
		act = ACTION_MARK
	return legal_actions(state).has(act)


## 当前合法动作列表（白名单顺序：ATTACK/DEFEND/CHARGE/MARK/TAUNT）。
## state 可传 StsCombat 实例（权威状态）或 ai_state_snapshot() 字典。
static func legal_actions(state = null) -> Array[String]:
	if _is_combat(state):
		return state.legal_actions()
	var d := _as_dict(state)
	var out: Array[String] = [ACTION_ATTACK]
	var mark_active := bool(d.get("mark_active", false))
	var mark_mode := String(d.get("mark_mode", "")).to_upper()
	var attacks := int(d.get("attacks_last_turn", 0))
	if bool(d.get("defend_ready", false)) and attacks >= 2 \
			and not (mark_active and mark_mode == MARK_AGGRO):
		out.append(ACTION_DEFEND)
	if bool(d.get("charge_ready", false)):
		out.append(ACTION_CHARGE)
	if bool(d.get("mark_ready", false)):
		out.append(ACTION_MARK)
	if bool(d.get("taunt_ready", false)) and bool(d.get("taunt_unlocked", false)):
		out.append(ACTION_TAUNT)
	return out


## 本地兜底：保留旧观察者行为——玩家上回合 ≥2 攻 → 防御；连续 2 回合 ≥2 发育 → 蓄力。
static func local_choose(state = null) -> String:
	if _is_combat(state):
		return state.local_choose()
	var d := _as_dict(state)
	var legal := legal_actions(d)
	if int(d.get("attacks_last_turn", 0)) >= 2 and legal.has(ACTION_DEFEND):
		return ACTION_DEFEND
	if int(d.get("grow_streak", 0)) >= 2 and legal.has(ACTION_CHARGE):
		return ACTION_CHARGE
	return ACTION_ATTACK


## 标记模式本地兜底（快照字典路径；实例路径委托 StsCombat.pick_mark_mode）。
static func pick_mark_mode(state = null) -> String:
	if _is_combat(state):
		return state.pick_mark_mode()
	var d := _as_dict(state)
	var atk := int(d.get("attacks_last_turn", 0))
	var grw := int(d.get("grows_last_turn", 0))
	var st := int(d.get("max_streak_last_turn", 0))
	if st >= 3 and st >= atk and st >= grw:
		return MARK_CHAIN
	if atk >= 2 and atk >= grw:
		return MARK_AGGRO
	if grw >= 2:
		return MARK_ECONOMY
	if st >= 2:
		return MARK_CHAIN
	return MARK_AGGRO


## 动作枚举 → UI 名（含中文别名与 MARK 模式）。
static func action_ui_name(action: String) -> String:
	return StsCombat.ai_action_ui_name(action)


## 容错归一：大小写/空白/中文别名/MARK:模式；无法识别时原样返回（交由合法性校验兜底）。
static func normalize_action(raw: String) -> String:
	var s := String(raw).strip_edges().to_upper()
	for prefix in ["ACTION:", "ACTION：", "动作:", "动作："]:
		if s.begins_with(prefix):
			s = s.substr(prefix.length()).strip_edges()
			break
	if ACTION_ALIASES.has(s):
		return String(ACTION_ALIASES[s])
	if s.begins_with("MARK:"):
		var m := s.substr(5).strip_edges()
		if MODE_ALIASES.has(m):
			m = String(MODE_ALIASES[m])
		return "MARK:" + m
	return s


## 数值常量快照（balance / 文档 / prompt 引用同一真值）。
static func constants() -> Dictionary:
	return {
		"OBS_ATK": StsCombat.OBS_ATK,
		"OBS_ATK_PER_LEVEL": StsCombat.OBS_ATK_PER_LEVEL,
		"OBS_DEF": StsCombat.OBS_DEF,
		"OBS_CHARGE_STEP": StsCombat.OBS_CHARGE_STEP,
		"OBS_ATK_CAP": StsCombat.OBS_ATK_CAP,
		"DEFEND_CD": StsCombat.DEFEND_CD,
		"MARK_CD": StsCombat.MARK_CD,
		"MARK_DURATION": StsCombat.MARK_DURATION,
		"TAUNT_CD": StsCombat.TAUNT_CD,
		"TAUNT_HP_RATIO": StsCombat.TAUNT_HP_RATIO,
	}


static func _is_combat(state) -> bool:
	return state != null and state is Object and state.has_method("legal_actions")


static func _as_dict(state) -> Dictionary:
	if state is Dictionary:
		return state
	return {}
