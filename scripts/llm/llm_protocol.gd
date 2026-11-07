class_name LLMProtocol
extends RefCounted
## 四家 LLM 协议的纯构造层：URL / Header / Body / 返回解析。
## 静态类，不联网、不持有状态、不引 UI。
##
## 支持：anthropic / responses / chat_completions（2026-11-04 主人钦定三协议制）
## 关键归一（踩坑点）：
##   - base URL 去尾斜杠、去重复 /v1（防 /v1/v1/chat/completions）；
##   - Gemini 走 query key（?key=），Anthropic 走 x-api-key + anthropic-version + max_tokens；
##   - /models 解析兼容 data[].id 与 models[].name（Gemini 的 name 带 models/ 前缀自动剥）；
##   - Anthropic 无模型列表端点，models_url 返回空串。

const ANTHROPIC_VERSION := "2023-06-01"
const DEFAULT_MAX_TOKENS := 512
const DEFAULT_TIMEOUT_S := 3.0

## 协议别名归一
## 协议三选一（2026-11-04 主人钦定）：anthropic / responses / chat_completions。
## 旧配置里的 openai/deepseek/gemini 是模型名，全部归并 chat_completions。
const PROTOCOL_ALIASES := {
	"openai": "chat_completions", "openai_compatible": "chat_completions",
	"compatible": "chat_completions", "deepseek": "chat_completions",
	"deepseek_r1": "chat_completions",
	"gemini": "chat_completions", "google": "chat_completions",
	"gemini_openai": "chat_completions",
	"anthropic": "anthropic", "claude": "anthropic",
	"responses": "responses", "responses_api": "responses",
	"chat_completions": "chat_completions",
}


# ══ 归一 ══════════════════════════════════════════════
static func normalize_protocol(p: String) -> String:
	var k := String(p).strip_edges().to_lower()
	return String(PROTOCOL_ALIASES.get(k, "chat_completions"))


## 去尾斜杠 + 去重复版本段。结果不含 /v1、/v1beta。
static func normalize_base(protocol: String, raw_base: String) -> String:
	var p := normalize_protocol(protocol)
	var b := String(raw_base).strip_edges()
	if b.is_empty():
		b = String(LLMConfig.DEFAULT_BASE.get(p, ""))
	while b.ends_with("/"):
		b = b.substr(0, b.length() - 1)
	if b.ends_with("/v1"):
		b = b.substr(0, b.length() - 3)
	while b.ends_with("/"):
		b = b.substr(0, b.length() - 1)
	return b


static func trim_model(model: String) -> String:
	var m := String(model).strip_edges()
	if m.begins_with("models/"):
		m = m.substr(7)
	return m


# ══ URL ═══════════════════════════════════════════════
static func chat_url(protocol: String, base: String, model: String, api_key: String = "") -> String:
	var p := normalize_protocol(protocol)
	var b := normalize_base(p, base)
	var m := trim_model(model)
	match p:
		"anthropic":
			if b.ends_with("/messages"):
				return b
			return b + "/v1/messages"
		"responses":
			if b.ends_with("/responses"):
				return b
			return b + "/v1/responses"
		_:
			if b.ends_with("/chat/completions"):
				return b
			return b + "/v1/chat/completions"


## 模型列表端点；Anthropic 无此端点返回空串（GUI 走手填）。
static func models_url(protocol: String, base: String, api_key: String = "") -> String:
	var p := normalize_protocol(protocol)
	var b := normalize_base(p, base)
	match p:
		"anthropic":
			return ""       ## Anthropic 无公开模型列表端点，GUI 走手填
		_:
			if b.ends_with("/models"):
				return b
			return b + "/v1/models"


# ══ Header ════════════════════════════════════════════
static func headers(protocol: String, api_key: String) -> PackedStringArray:
	var p := normalize_protocol(protocol)
	var h := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	match p:
		"anthropic":
			h.append("x-api-key: " + String(api_key))
			h.append("anthropic-version: " + ANTHROPIC_VERSION)
		_:
			if not String(api_key).is_empty():
				h.append("Authorization: Bearer " + String(api_key))
	return h


# ══ Body ══════════════════════════════════════════════
## messages: [{"role": "system"/"user"/"assistant", "content": String}, ...]
static func build_body(protocol: String, model: String, messages: Array,
		temperature: float, max_tokens: int = DEFAULT_MAX_TOKENS) -> String:
	var p := normalize_protocol(protocol)
	var m := trim_model(model)
	var t := clampf(float(temperature), 0.0, 2.0)
	var body: Dictionary = {}
	match p:
		"anthropic":
			body = _anthropic_body(m, messages, t, max_tokens)
		"responses":
			body = _responses_body(m, messages, t, max_tokens)
		_:
			body = {"model": m, "messages": _openai_messages(messages),
					"temperature": t, "stream": false}
			if max_tokens > 0:
				body["max_tokens"] = max_tokens
	return JSON.stringify(body)


## 一次调用所需全部要素（LLMClient 直接消费）
## 返回 {"ok": bool, "reason": String, "url": String, "headers": PackedStringArray,
##       "body": String, "method": int}
static func build_chat_request(cfg: LLMConfig, messages: Array, temperature: float = -1.0,
		opts: Dictionary = {}) -> Dictionary:
	if cfg == null:
		return {"ok": false, "reason": "no_config"}
	var p := normalize_protocol(cfg.protocol)
	var model := trim_model(cfg.model)
	if model.is_empty():
		return {"ok": false, "reason": "no_model"}
	var url := chat_url(p, cfg.effective_base(), model, cfg.api_key)
	if url.is_empty():
		return {"ok": false, "reason": "no_model"}
	var t := temperature
	if t < 0.0:
		t = float(opts.get("temperature", cfg.temp_for(String(opts.get("scene_tag", "")))))
	var max_tokens := int(opts.get("max_tokens", DEFAULT_MAX_TOKENS))
	var msgs := _with_candidates(messages, opts.get("candidates", []))
	return {
		"ok": true,
		"reason": "",
		"url": url,
		"headers": headers(p, cfg.api_key),
		"body": build_body(p, model, msgs, t, max_tokens),
		"method": HTTPClient.METHOD_POST,
	}


## candidates 非空时补一条系统消息（事件引擎的「特赦名单」，仅编号+ID，不进数值）
static func _with_candidates(messages: Array, candidates) -> Array:
	var out: Array = []
	for m in messages:
		out.append(m)
	if typeof(candidates) != TYPE_ARRAY or (candidates as Array).is_empty():
		return out
	var lines := PackedStringArray()
	var i := 1
	for c in candidates:
		lines.append("%d. %s" % [i, str(c)])
		i += 1
	out.append({"role": "system",
			"content": "只能从下列候选槽位中选一个编号返回（禁止池外答案）：\n" + "\n".join(lines)})
	return out


static func _openai_messages(messages: Array) -> Array:
	var out: Array = []
	for m in messages:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var role := String(m.get("role", "user"))
		if role != "system" and role != "assistant":
			role = "user"
		var content = m.get("content", "")
		if typeof(content) == TYPE_ARRAY:
			out.append({"role": role, "content": content})   ## 多模态：原样透传
		else:
			out.append({"role": role, "content": _content_text(content)})
	return out


## OpenAI Responses API：system → instructions，对话走 input[]（content 用纯文本串，
## 兼容度最好）；max_output_tokens 是该协议的官方字段名。
static func _responses_body(model: String, messages: Array, t: float, max_tokens: int) -> Dictionary:
	var sys_parts := PackedStringArray()
	var input: Array = []
	for m in messages:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var role := String(m.get("role", "user"))
		var text := _content_text(m.get("content", ""))
		if role == "system":
			if not text.is_empty():
				sys_parts.append(text)
			continue
		input.append({"role": "assistant" if role == "assistant" else "user", "content": text})
	if input.is_empty():
		input.append({"role": "user", "content": ""})
	var body := {
		"model": model,
		"input": input,
		"stream": false,
		"max_output_tokens": max_tokens if max_tokens > 0 else DEFAULT_MAX_TOKENS,
	}
	if t >= 0.0:
		body["temperature"] = t
	if not sys_parts.is_empty():
		body["instructions"] = "\n".join(sys_parts)
	return body


static func _anthropic_body(model: String, messages: Array, t: float, max_tokens: int) -> Dictionary:
	var sys_parts := PackedStringArray()
	var msgs: Array = []
	for m in messages:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var role := String(m.get("role", "user"))
		var text := _content_text(m.get("content", ""))
		if role == "system":
			if not text.is_empty():
				sys_parts.append(text)
			continue
		var content = m.get("content", "")
		var out_content = _anthropic_content(content) 				if typeof(content) == TYPE_ARRAY else text
		msgs.append({"role": "assistant" if role == "assistant" else "user",
				"content": out_content})
	if msgs.is_empty():
		msgs.append({"role": "user", "content": ""})
	var body := {
		"model": model,
		"max_tokens": max_tokens if max_tokens > 0 else DEFAULT_MAX_TOKENS,
		"temperature": t,
		"messages": msgs,
	}
	if not sys_parts.is_empty():
		body["system"] = "\n".join(sys_parts)
	return body


## OpenAI 多模态 content 数组 → Anthropic 格式（image_url data URI → image base64）
static func _anthropic_content(blocks: Array) -> Array:
	var out: Array = []
	for b in blocks:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var t := String((b as Dictionary).get("type", ""))
		if t == "image_url":
			var url := String(((b as Dictionary).get("image_url", {}) as Dictionary).get("url", ""))
			var mt := "image/png"
			var data := url
			if url.begins_with("data:"):
				var comma := url.find(",")
				var head := url.substr(5, comma - 5)
				mt = head.split(";")[0]
				data = url.substr(comma + 1)
			out.append({"type": "image",
					"source": {"type": "base64", "media_type": mt, "data": data}})
		elif t == "text":
			out.append({"type": "text", "text": String((b as Dictionary).get("text", ""))})
	return out


static func _content_text(content) -> String:
	match typeof(content):
		TYPE_STRING:
			return content
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for p in content:
				if typeof(p) == TYPE_DICTIONARY and p.has("text"):
					parts.append(str(p["text"]))
				elif typeof(p) == TYPE_STRING:
					parts.append(p)
			return "".join(parts)
		TYPE_NIL:
			return ""
	return str(content)


# ══ 返回解析 ══════════════════════════════════════════
## 静默 JSON 解析（失败返回 null，不刷引擎 ERROR）
static func _json(text: String):
	var j := JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data


## 从 chat 响应里抽正文；失败返回空串。
static func extract_text(protocol: String, json_text: String) -> String:
	var j = _json(json_text)
	if typeof(j) != TYPE_DICTIONARY:
		return ""
	var p := normalize_protocol(protocol)
	match p:
		"anthropic":
			return _content_text(j.get("content", []))
		"responses":
			## 正常响应：output[].content[] 里 type=output_text 的 text；
			## 某些网关直接给聚合字段 output_text
			var agg: Variant = j.get("output_text", "")
			if typeof(agg) == TYPE_STRING and not (agg as String).is_empty():
				return agg
			var outs = j.get("output", [])
			if typeof(outs) == TYPE_ARRAY:
				var parts := PackedStringArray()
				for o in outs:
					if typeof(o) != TYPE_DICTIONARY:
						continue
					var c = o.get("content", null)
					if typeof(c) == TYPE_ARRAY:
						for seg in c:
							if typeof(seg) == TYPE_DICTIONARY 									and String(seg.get("type", "")) == "output_text":
								parts.append(str(seg.get("text", "")))
							elif typeof(seg) == TYPE_STRING:
								parts.append(seg)
				return "".join(parts)
			return ""
		_:
			var choices = j.get("choices", [])
			if typeof(choices) != TYPE_ARRAY or (choices as Array).is_empty():
				return ""
			var ch = choices[0]
			if typeof(ch) != TYPE_DICTIONARY:
				return ""
			var msg = ch.get("message", {})
			if typeof(msg) == TYPE_DICTIONARY:
				return _content_text(msg.get("content", ""))
			return _content_text(ch.get("text", ""))
	return ""


## 从 chat 响应里抽**模型生成的图片**（data URI 或 http URL）；没有返回 ""。
## 兼容多种主流返回形态（2026-11-04 通用大模型绘图）：
## 1. choices[].message.images[]（OpenAI 新式：字符串或 {image_url:{url}}）
## 2. choices[].message.content 数组里的 image_url / output_image 块
## 3. content 字符串里的 markdown 图片或裸 data URI / http 图片链接
## 4. Gemini 风格 candidates[].content.parts[].inlineData{mimeType,data}
## 5. 生图端点风格 data[].b64_json / data[].url（兜底）
static func extract_image(protocol: String, json_text: String) -> String:
	var j = _json(json_text)
	if typeof(j) != TYPE_DICTIONARY:
		return ""
	var p := normalize_protocol(protocol)
	var img := ""
	var msg: Dictionary = {}
	var choices = j.get("choices", [])
	if typeof(choices) == TYPE_ARRAY and not (choices as Array).is_empty():
		var ch = choices[0]
		if typeof(ch) == TYPE_DICTIONARY:
			msg = (ch as Dictionary).get("message", {})
	# ① message.images[]
	var imgs = msg.get("images", [])
	if typeof(imgs) == TYPE_ARRAY:
		for im in imgs:
			img = _as_image_uri(im)
			if not img.is_empty():
				return img
	# ② content 数组里的图片块
	var content = msg.get("content", null)
	if typeof(content) == TYPE_ARRAY:
		for blk in content:
			if typeof(blk) != TYPE_DICTIONARY:
				continue
			var t := String((blk as Dictionary).get("type", ""))
			if t == "image_url" or t == "output_image" or t == "image":
				var src = (blk as Dictionary).get("image_url", (blk as Dictionary).get("source", null))
				if typeof(src) == TYPE_DICTIONARY:
					img = String((src as Dictionary).get("url", (src as Dictionary).get("data", "")))
				elif typeof(src) == TYPE_STRING:
					img = src
				elif (blk as Dictionary).has("b64_json"):
					img = "data:image/png;base64," + String((blk as Dictionary).get("b64_json", ""))
				if not img.is_empty():
					return img
	# ③ content 字符串里的 markdown 图 / 裸 data URI / http 图链
	if typeof(content) == TYPE_STRING:
		img = _first_image_in_text(content)
		if not img.is_empty():
			return img
	# ④ Gemini inlineData
	if p == "chat_completions" or true:
		var cands = j.get("candidates", [])
		if typeof(cands) == TYPE_ARRAY and not (cands as Array).is_empty():
			var c0 = cands[0]
			if typeof(c0) == TYPE_DICTIONARY:
				var parts = ((c0 as Dictionary).get("content", {}) as Dictionary).get("parts", [])
				if typeof(parts) == TYPE_ARRAY:
					for pa in parts:
						if typeof(pa) == TYPE_DICTIONARY and (pa as Dictionary).has("inlineData"):
							var inl = (pa as Dictionary).get("inlineData", {})
							if typeof(inl) == TYPE_DICTIONARY:
								var mt := String((inl as Dictionary).get("mimeType", "image/png"))
								img = "data:%s;base64,%s" % [mt, String((inl as Dictionary).get("data", ""))]
								if not img.is_empty():
									return img
	# ⑤ 生图端点风格兜底
	var data = j.get("data", [])
	if typeof(data) == TYPE_ARRAY and not (data as Array).is_empty():
		var d0 = data[0]
		if typeof(d0) == TYPE_DICTIONARY:
			if (d0 as Dictionary).has("b64_json"):
				return "data:image/png;base64," + String((d0 as Dictionary).get("b64_json", ""))
			if (d0 as Dictionary).has("url"):
				return String((d0 as Dictionary).get("url", ""))
	return ""


static func _as_image_uri(im) -> String:
	if typeof(im) == TYPE_STRING:
		var sv := String(im)
		if sv.begins_with("data:") or sv.begins_with("http"):
			return sv
		return "data:image/png;base64," + sv
	if typeof(im) == TYPE_DICTIONARY:
		var d := im as Dictionary
		if d.has("image_url"):
			var iu = d.get("image_url", {})
			if typeof(iu) == TYPE_DICTIONARY:
				return String((iu as Dictionary).get("url", ""))
			if typeof(iu) == TYPE_STRING:
				return iu
		if d.has("b64_json"):
			return "data:image/png;base64," + String(d.get("b64_json", ""))
	return ""


static func _first_image_in_text(text: String) -> String:
	## markdown ![alt](url)
	var pos := text.find("](")
	while pos >= 0:
		var open := text.rfind("![", pos)
		var close := text.find(")", pos)
		if open >= 0 and close > pos:
			var url := text.substr(pos + 2, close - pos - 2)
			if url.begins_with("data:image") or url.begins_with("http"):
				return url
		pos = text.find("](", pos + 2)
	# 裸 data URI
	var di := text.find("data:image/")
	if di >= 0:
		var end = -1
		for stop in ["\")", "\" ]", ")", "]", " ", "
"]:
			var e := text.find(stop, di)
			if e > di and (end < 0 or e < end):
				end = e
		return text.substr(di, end - di) if end > di else text.substr(di)
	return ""


## 从模型输出里抠 SVG 代码（<svg ...>…</svg>）；没有返回 ""。
## 通用大模型的"绘图"= 返回 SVG/绘图代码，Godot 内置 ThorVG 可运行时渲染。
static func extract_svg_from_text(text: String) -> String:
	var i := text.find("<svg")
	if i < 0:
		return ""
	var j := text.rfind("</svg>")
	if j < i:
		return ""
	return text.substr(i, j - i + 6)


## 错误响应里的可读原因（4xx 提示用），无则空串。
static func extract_error(protocol: String, json_text: String) -> String:
	var j = _json(json_text)
	if typeof(j) != TYPE_DICTIONARY:
		return ""
	var err = j.get("error", null)
	if typeof(err) == TYPE_DICTIONARY:
		return String(err.get("message", err.get("type", "")))
	if typeof(err) == TYPE_STRING:
		return err
	return String(j.get("message", ""))


## /models 解析：兼容 {"data":[{"id":..}]} 与 {"models":[{"name":..}]}，
## 也兼容 data 直接是字符串数组；去重保序。
static func parse_models(protocol: String, json_text: String) -> Array:
	var out: Array = []
	var j = _json(json_text)
	if typeof(j) != TYPE_DICTIONARY:
		return out
	var arr = null
	if j.has("data"):
		arr = j["data"]
	elif j.has("models"):
		arr = j["models"]
	if typeof(arr) != TYPE_ARRAY:
		return out
	for it in arr:
		var name := ""
		if typeof(it) == TYPE_STRING:
			name = it
		elif typeof(it) == TYPE_DICTIONARY:
			name = String(it.get("id", it.get("name", it.get("model", ""))))
		name = trim_model(name)
		if name.is_empty() or out.has(name):
			continue
		out.append(name)
	return out


static func supports_model_list(protocol: String) -> bool:
	return normalize_protocol(protocol) != "anthropic"
