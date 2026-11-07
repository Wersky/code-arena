class_name LLMParse
extends RefCounted
## LLM 输出四层容错解析（圆桌终案：小模型花括号配不齐，别指望严格 JSON）。
##
## 四层顺序（命中即返回）：
##   ① JSON：剥围栏后能解析出结构化字段；
##   ② 动作词行：某行以白名单动作词开头（可带「动作：」前缀/Markdown 装饰）；
##   ③ 关键词正则：正文里出现 ATTACK/攻击/防御/蓄力… 按出现位置取最早；
##   ④ null：动作给空串（调用方走本地兜底动作），台词照播不丢。
##
## 事件协议是另一条轨：{"pick": int, "reason": str} 三关严格校验
##   （JSON 可解析 / pick 是 int / pick ∈ [1, pool_size]），任一失败静默落本地默认。
##
## 所有函数静态、纯字符串处理，不联网、不引 UI。

## 五动作白名单 v1.1（观察者只出词，数值全在本地常量表）
const ACTIONS := ["ATTACK", "DEFEND", "CHARGE", "MARK", "TAUNT"]

const ACTION_CN := {
	"ATTACK": ["攻击", "出手", "直伤", "撞", "冲击", "铁头"],
	"DEFEND": ["防御", "格挡", "护盾", "架盾", "挡住"],
	"CHARGE": ["蓄力", "充能", "蓄能", "攒力", "憋"],
	"MARK": ["标记", "针对", "记恨", "锁定", "记账"],
	"TAUNT": ["嘲讽", "挑衅", "嘴臭", "吞掉", "吞下"],
}
## 认知链前缀（只剥行首，正文里的不动）
static var COT_PREFIX := RegEx.create_from_string(
	"^(思考|分析|推理|思路|内心|判断|根据局面|局面分析|Thinking|Reasoning|Thought|Let me|We need|The user|First,|好的[，,：:]|OK[，,：:])")


# ══ 公共：清噪 ════════════════════════════════════════
## 剥 ```json 围栏 / BOM / 零宽字符；多段围栏取第一段内容。
static func strip_noise(raw: String) -> String:
	var s := String(raw)
	s = s.replace("\ufeff", "").replace("\u200b", "").replace("\u200c", "").replace("\u200d", "")
	s = s.replace("\r\n", "\n").replace("\r", "\n")
	var open := s.find("```")
	if open >= 0:
		var head := s.substr(open + 3)
		# 跳过语言标记（json / JSON / json5）
		var nl := head.find("\n")
		if nl >= 0:
			var tag := head.substr(0, nl).strip_edges().to_lower()
			if tag == "json" or tag == "json5" or tag.is_empty():
				head = head.substr(nl + 1)
		var close := head.find("```")
		if close >= 0:
			head = head.substr(0, close)
		s = head
	return s.strip_edges()


## 去行首思维链前缀（连续剥，最多 4 行）；空行不剥。
static func strip_cot(raw: String) -> String:
	var lines := raw.split("\n")
	var i := 0
	var stripped := 0
	while i < lines.size() and stripped < 4:
		var line := String(lines[i]).strip_edges()
		if line.is_empty():
			i += 1
			continue
		var hit := (COT_PREFIX.search(line) != null
				and (line.length() <= 60 or line.ends_with(":"))
				and i + 1 < lines.size())
		if hit:
			i += 1
			stripped += 1
			continue
		break
	if i == 0:
		return raw
	return "\n".join(lines.slice(i)).strip_edges()


# ══ 观察者：动作 + 台词 ════════════════════════════════
## 返回 {"ok": bool, "action": String, "line": String, "source": "json"|"line"|"regex"|"null"}
## ok=false 时 action 为空、line 仍带清理后的原文（台词照播，数值用本地兜底动作）。
static func parse_action(raw: String) -> Dictionary:
	var text := strip_cot(strip_noise(raw))
	if text.is_empty():
		return {"ok": false, "action": "", "line": "", "source": "null"}

	# ① JSON
	var j = _try_json(text)
	if typeof(j) == TYPE_DICTIONARY:
		var word := ""
		for k in ["action", "act", "move", "skill", "choice", "action_word", "动作"]:
			if j.has(k):
				word = _norm_action_word(str(j[k]))
				if not word.is_empty():
					break
		if not word.is_empty():
			var dl := ""
			for k in ["line", "say", "dialog", "dialogue", "text", "reason", "台词"]:
				if j.has(k):
					dl = String(j[k]).strip_edges()
					break
			return {"ok": true, "action": word, "line": dl, "source": "json"}

	# ② 动作词行
	var lines := text.split("\n")
	for i in lines.size():
		var hit := _action_in_line(String(lines[i]))
		if hit.is_empty():
			continue
		var rest := String(lines[i])
		var pos := rest.to_upper().find(hit)
		if pos >= 0:
			rest = rest.substr(pos + hit.length())
		rest = rest.strip_edges().trim_prefix("：").trim_prefix(":").trim_prefix("—").strip_edges()
		var tail := PackedStringArray()
		if not rest.is_empty():
			tail.append(rest)
		for k in range(i + 1, lines.size()):
			tail.append(String(lines[k]))
		return {"ok": true, "action": hit, "line": "\n".join(tail).strip_edges(), "source": "line"}

	# ③ 关键词正则（按最早出现位置取一个）
	var best_pos := -1
	var best_action := ""
	for a in ACTIONS:
		var p := _first_index(text, a)
		if p >= 0 and (best_pos < 0 or p < best_pos):
			best_pos = p
			best_action = a
	for a in ACTIONS:
		for cn in ACTION_CN[a]:
			var p := text.find(cn)
			if p >= 0 and (best_pos < 0 or p < best_pos):
				best_pos = p
				best_action = a
	if not best_action.is_empty():
		return {"ok": true, "action": best_action, "line": text, "source": "regex"}

	# ④ null：台词照播
	return {"ok": false, "action": "", "line": text, "source": "null"}


# ══ 事件引擎：{"pick": int, "reason": str} 三关 ════════
## 返回 {"ok": bool, "pick": int, "reason": String, "source": "json"|"null"}
## ok=false 时 pick=0，调用方静默落本地默认候选（不重试、不道歉）。
static func parse_event(raw: String, pool_size: int) -> Dictionary:
	var fail := {"ok": false, "pick": 0, "reason": "", "source": "null"}
	if pool_size < 1:
		return fail
	var text := strip_cot(strip_noise(raw))
	if text.is_empty():
		return fail
	var j = _try_json(text)
	if typeof(j) != TYPE_DICTIONARY:
		return fail
	# 关 2：pick 必须是整数（容忍 "3" / 3.0 / 3 号）
	var raw_pick = null
	for k in ["pick", "index", "choice", "slot", "槽位", "选择"]:
		if j.has(k):
			raw_pick = j[k]
			break
	if raw_pick == null:
		return fail
	var pick := _as_int(raw_pick)
	if pick <= 0:
		return fail
	# 关 3：池内范围
	if pick > pool_size:
		return fail
	# reason：字符串，压平换行，长文截断（协议 ≤20 字，宽容到 40 不硬拒）
	var reason := ""
	for k in ["reason", "why", "reason_text", "text", "叙事", "理由"]:
		if j.has(k):
			reason = _squash(str(j[k]))
			break
	if reason.length() > 40:
		reason = reason.substr(0, 40)
	return {"ok": true, "pick": pick, "reason": reason, "source": "json"}


# ══ AI 娘：纯台词 ═════════════════════════════════════
## 返回清理后的单行台词；无内容返回 ""。max_len<=0 不截断。
static func parse_dialogue(raw: String, max_len: int = 120) -> String:
	var text := strip_cot(strip_noise(raw))
	if text.is_empty():
		return ""
	var j = _try_json(text)
	if typeof(j) == TYPE_DICTIONARY:
		for k in ["line", "say", "dialog", "dialogue", "text", "reason", "台词"]:
			if j.has(k):
				text = str(j[k])
				break
	text = _squash(text)
	# 去包裹引号
	for pair in [["「", "」"], ["“", "”"], ["\"", "\""], ["'", "'"], ["『", "』"]]:
		if text.begins_with(pair[0]) and text.ends_with(pair[1]) and text.length() > 2:
			text = text.substr(1, text.length() - 2).strip_edges()
	if max_len > 0 and text.length() > max_len:
		text = text.substr(0, max_len)
	return text


# ══ 内部 ══════════════════════════════════════════════
static func _strip_decor(line: String) -> String:
	var s := line.strip_edges()
	var guard := 0
	while guard < 8 and (s.begins_with("**") or s.begins_with("__") or s.begins_with("-")
			or s.begins_with("*") or s.begins_with(">") or s.begins_with("#") or s.begins_with("`")):
		s = s.substr(1).strip_edges()
		guard += 1
	return s


static func _action_in_line(line: String) -> String:
	var s := _strip_decor(line)
	if s.is_empty():
		return ""
	# 去「动作：」类前缀（剥完前缀可能又露出 Markdown 装饰，再剥一次）
	for pre in ["动作词", "动作", "Action", "ACT", "输出", "回答"]:
		var low: String = s.to_lower()
		var pl: String = String(pre).to_lower()
		if low.begins_with(pl):
			s = s.substr(String(pre).length()).strip_edges()
			s = s.trim_prefix("：").trim_prefix(":").strip_edges()
			s = _strip_decor(s)
			break
	# 取第一个 token
	var cut := -1
	for ch in [" ", "\t", "：", ":", "，", ",", "（", "(", "。", "!", "！"]:
		var p := s.find(ch)
		if p >= 0 and (cut < 0 or p < cut):
			cut = p
	var token := s if cut < 0 else s.substr(0, cut)
	var word := _norm_action_word(token)
	if not word.is_empty():
		return word
	# token 不纯（如 "ATTACK - 嘲讽"），整行做一次严格前缀匹配
	var up := s.to_upper()
	for a in ACTIONS:
		if up.begins_with(a):
			return a
	return ""


static func _norm_action_word(s: String) -> String:
	var t := String(s).strip_edges()
	for junk in ["`", "*", "\"", "'", "「", "」", "“", "”", "。", "！", "!", "，", ",", "：", ":",
			"（", "）", "(", ")", "【", "】", "[", "]"]:
		t = t.replace(junk, "")
	t = t.strip_edges()
	if t.is_empty():
		return ""
	var up := t.to_upper()
	if ACTIONS.has(up):
		return up
	for a in ACTIONS:
		if up.begins_with(a):
			return a
	for a in ACTIONS:
		if up.contains(a) and a.length() >= 4:
			return a
	for a in ACTIONS:
		for cn in ACTION_CN[a]:
			if t.contains(cn):
				return a
	return ""


static func _first_index(text: String, action: String) -> int:
	var re := RegEx.create_from_string("(?i)\\b" + action + "\\b")
	var m := re.search(text)
	return -1 if m == null else m.get_start()


static func _try_json(text: String):
	# 用 JSON 实例 parse()，失败不打印引擎 ERROR（parse_string 会刷错误日志）
	var j := JSON.new()
	if j.parse(text) == OK:
		return j.data
	var a := text.find("{")
	var b := text.rfind("}")
	if a >= 0 and b > a:
		var j2 := JSON.new()
		if j2.parse(text.substr(a, b - a + 1)) == OK:
			return j2.data
	return null


static func _as_int(v) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			var f: float = v
			return int(f) if is_equal_approx(f, roundf(f)) else -1
		TYPE_STRING:
			var s := String(v).strip_edges()
			if s.is_valid_int():
				return s.to_int()
			var re := RegEx.create_from_string("^\\D*?(\\d+)")
			var m := re.search(s)
			if m != null:
				return m.get_string(1).to_int()
	return -1


static func _squash(s: String) -> String:
	var t := String(s).strip_edges()
	while t.find("  ") >= 0:
		t = t.replace("  ", " ")
	t = t.replace("\n", " ").replace("\t", " ")
	return t.strip_edges()
