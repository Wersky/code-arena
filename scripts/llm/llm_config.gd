class_name LLMConfig
extends RefCounted
## LLM 接入配置：读写 user://llm_config.cfg + API Key 轻混淆（XOR + base64）。
##
## 设计口径（圆桌终案）：
##   - 配置离线可读，ConfigFile 明文 section/value，方便主人手改；
##   - Key 只做「防围观」级混淆（XOR 循环密钥 + base64），**不防解包**，明示；
##   - 协议三选一（2026-11-04 主人钦定）：anthropic / responses / chat_completions；
##     （旧配置里的 openai / deepseek / gemini 是模型名不是协议，加载时归并到 chat_completions）
##   - 温度按 scene_tag 分治：observer 0.3 / event 0.5 / dialog 0.8（第 3 轮定稿）；
##   - 本类不联网、不引 UI/战斗，headless 可独立加载。
##
## 典型用法：
##   var cfg := LLMConfig.load_from_disk()
##   print(cfg.is_enabled(), cfg.temp_for("observer"))
##   cfg.save()

const CONFIG_PATH := "user://llm_config.cfg"
const SECTION := "llm"
const TEMP_SECTION := "temperature"

const PROTOCOLS := ["anthropic", "responses", "chat_completions"]
## 下拉显示名（机器名 → 主人看到的文案）
const PROTOCOL_LABELS := {
	"anthropic": "Anthropic",
	"responses": "Responses",
	"chat_completions": "Chat Completions",
}
## 各家默认 Base URL（GUI 切协议时预填；不含 /v1，由 LLMProtocol 归一）
const DEFAULT_BASE := {
	"anthropic": "https://api.anthropic.com",
	"responses": "https://api.openai.com",
	"chat_completions": "https://api.openai.com",
}
## 旧配置协议名 → 新协议（openai/deepseek 本就是 chat completions 同构；
## gemini 端点结构不同但主人不用，归并后走 chat_completions）
const LEGACY_PROTOCOL_MAP := {
	"openai": "chat_completions", "openai_compatible": "chat_completions",
	"compatible": "chat_completions", "deepseek": "chat_completions",
	"gemini": "chat_completions", "google": "chat_completions",
	"claude": "anthropic", "anthropic-messages": "anthropic",
	"responses_api": "responses",
}


static func normalize_protocol_name(p: String) -> String:
	var k := String(p).strip_edges().to_lower()
	return String(LEGACY_PROTOCOL_MAP.get(k, k))
## 温度分治默认值（圆桌第 3 轮：observer 0.3 / event 0.5 / dialog 0.8）
const DEFAULT_TEMPS := {"observer": 0.3, "event": 0.5, "dialog": 0.8}
const TEMP_MIN := 0.0
const TEMP_MAX := 2.0

## ── 运行时字段（GUI 直接读写）────────────────────────────
var enabled := false
var base_url := ""
## 明文 Key（只在内存里）；落盘时走 obfuscate()
var api_key := ""
var protocol := "anthropic"
var model := ""
## {"observer": float, "event": float, "dialog": float}
var temperatures := {"observer": 0.3, "event": 0.5, "dialog": 0.8}

## ── 生图（许愿卡，2026-11-04 圆桌定稿）：独立开关/模型/端点/每局次数 ──
## 文本 key 常无生图权限，所以 base/model 都可独立覆盖；key 复用 api_key。
const IMAGE_SECTION := "image"
var image_enabled := false
var image_model := ""
var image_base := ""          ## 空则复用 base_url
var image_key := ""           ## 空则复用 api_key（生图与文本常是不同 Key）
var image_max_per_run := 2    ## 每局许愿次数上限（可被关卡进度回补，见 wish 逻辑）
const IMAGE_MAX_CAP := 4

## 许愿卡超时按模型分档（2026-11-05）：grok 通道实测 109–123s，统一 90s 会截断。
## 默认 90s；命中慢通道关键词给 180s。宁可多等，也不要让玩家白画一张。
const WISH_TIMEOUT_DEFAULT := 90.0
const WISH_TIMEOUT_SLOW := 180.0
const SLOW_MODEL_HINTS := ["grok"]
const WISH_TIMEOUT_TIERS := {
	"default": WISH_TIMEOUT_DEFAULT,
	"slow": WISH_TIMEOUT_SLOW,
}


## 按模型名取许愿超时（大小写不敏感；未知模型走默认档）
static func wish_timeout_for(model_name: String) -> float:
	var m := String(model_name).to_lower()
	for hint in SLOW_MODEL_HINTS:
		if m.contains(hint):
			return WISH_TIMEOUT_SLOW
	return WISH_TIMEOUT_DEFAULT
## 敌人 AI 决策开关（2026-11-05 主人钦定：默认关，敌人走本地规则，省 token）
var ai_opponent := false
## 视觉输入（2026-11-05 主人钦定）：**主流大模型默认全按多模态处理**——
## DeepSeek / GPT / Qwen / MiniMax / Claude / 混元 / GLM / Kimi / MiMo 都能看能画，
## 不做模型名启发式。只有显式 vision_override=0 才关（真·纯文本模型兜底用）。
var vision_override := 1

## Key 混淆密钥（改它 = 旧配置全部解不开，别动）
const _MASK := "prompt-arena-llm-v1"
const _PREFIX := "b64:"


# ══ 读写 ══════════════════════════════════════════════
static func load_from_disk(path: String = CONFIG_PATH) -> LLMConfig:
	var cfg := LLMConfig.new()
	cfg.read(path)
	return cfg


func read(path: String = CONFIG_PATH) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		_apply_defaults()
		return
	enabled = bool(cf.get_value(SECTION, "enabled", false))
	base_url = String(cf.get_value(SECTION, "base_url", ""))
	protocol = normalize_protocol_name(String(cf.get_value(SECTION, "protocol", "anthropic")))
	model = String(cf.get_value(SECTION, "model", ""))
	api_key = deobfuscate(String(cf.get_value(SECTION, "api_key", "")))
	if not PROTOCOLS.has(protocol):
		protocol = "anthropic"
	for tag in DEFAULT_TEMPS.keys():
		temperatures[tag] = clampf(
				float(cf.get_value(TEMP_SECTION, tag, DEFAULT_TEMPS[tag])),
				TEMP_MIN, TEMP_MAX)
	image_enabled = bool(cf.get_value(IMAGE_SECTION, "enabled", false))
	image_model = String(cf.get_value(IMAGE_SECTION, "model", ""))
	image_base = String(cf.get_value(IMAGE_SECTION, "base_url", ""))
	image_key = deobfuscate(String(cf.get_value(IMAGE_SECTION, "api_key", "")))
	image_max_per_run = clampi(
			int(cf.get_value(IMAGE_SECTION, "max_per_run", 2)), 0, IMAGE_MAX_CAP)
	vision_override = clampi(int(cf.get_value(IMAGE_SECTION, "vision_override", 1)), -1, 1)
	ai_opponent = bool(cf.get_value(IMAGE_SECTION, "ai_opponent", false))


func save(path: String = CONFIG_PATH) -> Error:
	protocol = normalize_protocol_name(protocol)   ## 旧名落盘前归一（openai → chat_completions）
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "enabled", enabled)
	cf.set_value(SECTION, "base_url", base_url.strip_edges())
	cf.set_value(SECTION, "api_key", obfuscate(api_key))
	cf.set_value(SECTION, "protocol", protocol if PROTOCOLS.has(protocol) else "anthropic")
	cf.set_value(SECTION, "model", model.strip_edges())
	for tag in DEFAULT_TEMPS.keys():
		cf.set_value(TEMP_SECTION, tag, clampf(
				float(temperatures.get(tag, DEFAULT_TEMPS[tag])), TEMP_MIN, TEMP_MAX))
	cf.set_value(IMAGE_SECTION, "enabled", image_enabled)
	cf.set_value(IMAGE_SECTION, "model", image_model.strip_edges())
	cf.set_value(IMAGE_SECTION, "base_url", image_base.strip_edges())
	cf.set_value(IMAGE_SECTION, "api_key", obfuscate(image_key))
	cf.set_value(IMAGE_SECTION, "max_per_run", clampi(image_max_per_run, 0, IMAGE_MAX_CAP))
	cf.set_value(IMAGE_SECTION, "vision_override", clampi(vision_override, -1, 1))
	cf.set_value(IMAGE_SECTION, "ai_opponent", ai_opponent)
	return cf.save(path)


# ══ 查询 ══════════════════════════════════════════════
## 总开关 + 必要字段齐了才算可用；Key 可空（localhost 本地模型免 key）
func is_enabled() -> bool:
	return enabled and not base_url.strip_edges().is_empty() and not model.strip_edges().is_empty()


func has_key() -> bool:
	return not api_key.is_empty()


## 视觉输入判定：默认 true（主流模型都能看能画）；vision_override=0 才关
func model_supports_vision() -> bool:
	return vision_override != 0


## 生图 Key：独立字段优先，空则回退文本 Key
func effective_image_key() -> String:
	return image_key.strip_edges() if not image_key.strip_edges().is_empty() 			else api_key.strip_edges()


## 生图可用：开关 + 模型名 + Key（本地网关可免 key）
func image_ready() -> bool:
	return image_enabled and not image_model.strip_edges().is_empty() 			and (not effective_image_key().is_empty()
					or effective_image_base().begins_with("http://"))


## 生图端点：独立 base 优先，空则复用文本 base
func effective_image_base() -> String:
	var b := image_base.strip_edges()
	return b if not b.is_empty() else base_url.strip_edges()


## scene_tag → 温度；未知 tag 回落 0.5（事件档）
func temp_for(scene_tag: String) -> float:
	var tag := String(scene_tag).to_lower()
	match tag:
		"observer", "opponent", "enemy", "ai_opponent":
			return clampf(float(temperatures.get("observer", DEFAULT_TEMPS["observer"])), TEMP_MIN, TEMP_MAX)
		"event", "event_engine", "event_engine_core":
			return clampf(float(temperatures.get("event", DEFAULT_TEMPS["event"])), TEMP_MIN, TEMP_MAX)
		"dialog", "dialogue", "banter", "companion", "ai_banter":
			return clampf(float(temperatures.get("dialog", DEFAULT_TEMPS["dialog"])), TEMP_MIN, TEMP_MAX)
	return 0.5


func default_base_for(p: String) -> String:
	return String(DEFAULT_BASE.get(p, DEFAULT_BASE["anthropic"]))


func effective_base() -> String:
	## 空 base 时用当前协议默认值（GUI 预填用；不落盘）
	var b := base_url.strip_edges()
	return b if not b.is_empty() else default_base_for(protocol)


# ══ 字典互转（GUI / 测试）════════════════════════════
func to_dict() -> Dictionary:
	return {
		"enabled": enabled,
		"base_url": base_url,
		"api_key": api_key,
		"protocol": protocol,
		"model": model,
		"temperature_observer": temp_for("observer"),
		"temperature_event": temp_for("event"),
		"temperature_dialog": temp_for("dialog"),
		"image_enabled": image_enabled,
		"image_model": image_model,
		"image_base": image_base,
		"image_key": image_key,
		"image_max_per_run": image_max_per_run,
		"vision_override": vision_override,
		"ai_opponent": ai_opponent,
	}


func apply_dict(d: Dictionary) -> void:
	if d.has("enabled"):
		enabled = bool(d["enabled"])
	if d.has("base_url"):
		base_url = String(d["base_url"]).strip_edges()
	if d.has("api_key"):
		api_key = String(d["api_key"])
	if d.has("protocol"):
		var p := String(d["protocol"])
		protocol = normalize_protocol_name(p)
	protocol = protocol if PROTOCOLS.has(protocol) else "anthropic"
	if d.has("model"):
		model = String(d["model"]).strip_edges()
	for tag in DEFAULT_TEMPS.keys():
		var key: String = "temperature_" + str(tag)
		if d.has(key):
			temperatures[tag] = clampf(float(d[key]), TEMP_MIN, TEMP_MAX)
	if d.has("image_enabled"):
		image_enabled = bool(d["image_enabled"])
	if d.has("image_model"):
		image_model = String(d["image_model"]).strip_edges()
	if d.has("image_base"):
		image_base = String(d["image_base"]).strip_edges()
	if d.has("image_key"):
		image_key = String(d["image_key"])
	if d.has("image_max_per_run"):
		image_max_per_run = clampi(int(d["image_max_per_run"]), 0, IMAGE_MAX_CAP)
	if d.has("vision_override"):
		vision_override = clampi(int(d["vision_override"]), -1, 1)
	if d.has("ai_opponent"):
		ai_opponent = bool(d["ai_opponent"])


# ══ Key 轻混淆 ════════════════════════════════════════
## XOR 循环密钥 + base64，前缀 b64: 标记；空串原样返回。
static func obfuscate(plain: String) -> String:
	if plain.is_empty():
		return ""
	var raw: PackedByteArray = plain.to_utf8_buffer()
	var key: PackedByteArray = _MASK.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(raw.size())
	for i in raw.size():
		out[i] = raw[i] ^ key[i % key.size()]
	return _PREFIX + Marshalls.raw_to_base64(out)


## 兼容旧配置：无非 b64: 前缀的按明文原样返回；解不开返回空串。
static func deobfuscate(blob: String) -> String:
	if blob.is_empty():
		return ""
	if not blob.begins_with(_PREFIX):
		return blob
	var raw: PackedByteArray = Marshalls.base64_to_raw(blob.substr(_PREFIX.length()))
	if raw.is_empty():
		return ""
	var key: PackedByteArray = _MASK.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(raw.size())
	for i in raw.size():
		out[i] = raw[i] ^ key[i % key.size()]
	return out.get_string_from_utf8()


func _apply_defaults() -> void:
	enabled = false
	base_url = ""
	api_key = ""
	protocol = "anthropic"
	model = ""
	temperatures = DEFAULT_TEMPS.duplicate()
	image_enabled = false
	image_model = ""
	image_base = ""
	image_key = ""
	image_max_per_run = 2
	vision_override = 1
	ai_opponent = false


# ══ ZCode provider 导入（goat 分组等，2026-11-03）══════
## 读取 ZCode 的供应商配置（~/.zcode/v2/provider_config.json），
## 把指定 provider（默认 goat-claude）映射成游戏内的 LLM 配置。
## 返回 {ok, provider, base_url, protocol, model, api_key, key_tail, models, error}
static func zcode_provider_path() -> String:
	var home := OS.get_environment("USERPROFILE")
	if home.is_empty():
		home = OS.get_environment("HOME")
	return home.replace("\\", "/") + "/.zcode/v2/provider_config.json"


static func import_zcode_provider(provider_id: String = "", path: String = "") -> Dictionary:
	var p := path if not path.is_empty() else zcode_provider_path()
	if not FileAccess.file_exists(p):
		return {"ok": false, "error": "找不到 ZCode 配置：%s" % p}
	var data = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (data is Dictionary):
		return {"ok": false, "error": "ZCode 配置不是合法 JSON"}
	var cfg_root = data.get("config", {})
	if not (cfg_root is Dictionary):
		return {"ok": false, "error": "ZCode 配置缺少 config"}
	var rules_root = cfg_root.get("providerConfigRules", {})
	if not (rules_root is Dictionary):
		return {"ok": false, "error": "ZCode 配置缺少 providerConfigRules"}
	var rules = rules_root.get("providerRules", [])
	if not (rules is Array):
		return {"ok": false, "error": "ZCode 配置缺少 providerRules"}
	var rule: Dictionary = {}
	if provider_id.is_empty():
		## 主人 2026-11-06：默认渠道走 DeepSeek（不再默认 goat-claude）
		rule = _pick_default_provider_rule(rules)
	else:
		for it in rules:
			if it is Dictionary and String(it.get("providerId", "")) == provider_id:
				rule = it
				break
	if rule.is_empty():
		return {"ok": false, "error": "ZCode 里没有 provider：%s" % (
				provider_id if not provider_id.is_empty() else "（默认 DeepSeek 也未找到）")}
	var pc = rule.get("config", {})
	if not (pc is Dictionary):
		return {"ok": false, "error": "provider 配置为空"}
	var access = pc.get("access", {})
	var api = pc.get("api", {})
	var api_type := String(api.get("type", "") if api is Dictionary else "").to_lower()
	var proto := "chat_completions"
	if api_type.contains("anthropic"):
		proto = "anthropic"
	var models = pc.get("personalModelIds", pc.get("modelOrder", []))
	if not (models is Array):
		models = []
	var model := String(models[0]) if not models.is_empty() else ""
	var key := String(access.get("apiKey", "") if access is Dictionary else "")
	var base := String(api.get("baseUrl", "") if api is Dictionary else "")
	return {
		"ok": true,
		"provider": String(rule.get("providerId", provider_id)),
		"provider_name": String(rule.get("providerName", "")),
		"base_url": base,
		"protocol": proto,
		"model": model,
		"api_key": key,
		"key_tail": ("…" + key.substr(maxi(0, key.length() - 4))) if key.length() > 4 else "",
		"models": models,
	}


## 默认 provider 选择（2026-11-06 主人要求走 DeepSeek）：
##   1. 原生 api.deepseek.com 优先
##   2. 其次 id / 名字 / 域名里含 deepseek 的
##   3. 都没有就退回第一条规则
static func _pick_default_provider_rule(rules: Array) -> Dictionary:
	var fallback: Dictionary = {}
	for it in rules:
		if not (it is Dictionary):
			continue
		if fallback.is_empty():
			fallback = it
		var pc = it.get("config", {})
		if not (pc is Dictionary):
			continue
		var api = pc.get("api", {})
		var base := String(api.get("baseUrl", "") if api is Dictionary else "").to_lower()
		if base.contains("api.deepseek.com"):
			return it
	for it in rules:
		if not (it is Dictionary):
			continue
		var pc = it.get("config", {})
		var api = pc.get("api", {}) if pc is Dictionary else {}
		var base := String(api.get("baseUrl", "") if api is Dictionary else "").to_lower()
		var pid := String(it.get("providerId", "")).to_lower()
		var pname := String(it.get("providerName", "")).to_lower()
		if pid.contains("deepseek") or pname.contains("deepseek") or base.contains("deepseek"):
			return it
	return fallback
