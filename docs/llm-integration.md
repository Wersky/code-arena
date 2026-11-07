# LLM 接入层接口 · scripts/llm/（llm-core 交付）

> 归属：任务 `llm-core`（agent-1）。只新建 `scripts/llm/` 四个模块，**不改任何现有文件**。
> 下游（battle-integration / gui-integration / event-engine / banter / regression）按本文签名接线。
> 圆桌终案口径见 `圆桌纪要/LLM接入代码擂台.md`；本文件只写「怎么调」。

## 0. 模块总览

| 文件 | class_name | 基类 | 职责 |
|---|---|---|---|
| `scripts/llm/llm_config.gd` | `LLMConfig` | RefCounted | 配置读写 `user://llm_config.cfg`、Key XOR+base64 轻混淆、温度分治 |
| `scripts/llm/llm_protocol.gd` | `LLMProtocol` | RefCounted（全静态） | 四家 URL/Header/Body 构造、`/models` 与回复解析 |
| `scripts/llm/llm_parse.gd` | `LLMParse` | RefCounted（全静态） | 动作四层容错、事件 JSON 三关、台词清洗 |
| `scripts/llm/llm_client.gd` | `LLMClient` | **Node** | 唯一网络出口：并发 2 / 重试 1 / 熔断 / 迟到缓存 / Mock 注入 |

不依赖 UI / 战斗 / autoload；headless 可独立加载。`LLMClient` 是 Node，**用前 add_child（或放 root）**；不在树里时会自动挂到 `Engine.get_main_loop().root` 兜底。

## 1. LLMConfig

```gdscript
const CONFIG_PATH := "user://llm_config.cfg"
const PROTOCOLS := ["openai", "deepseek", "gemini", "anthropic"]
const DEFAULT_TEMPS := {"observer": 0.3, "event": 0.5, "dialog": 0.8}

var enabled: bool
var base_url: String
var api_key: String          # 内存明文；落盘自动混淆
var protocol: String         # openai / deepseek / gemini / anthropic
var model: String
var temperatures: Dictionary # {"observer": float, "event": float, "dialog": float}

static func load_from_disk(path: String = CONFIG_PATH) -> LLMConfig
func read(path: String = CONFIG_PATH) -> void
func save(path: String = CONFIG_PATH) -> Error

func is_enabled() -> bool        # enabled && base_url 非空 && model 非空（Key 可空，供 localhost）
func has_key() -> bool
func temp_for(scene_tag: String) -> float   # observer/event/dialog 及别名；未知 tag → 0.5
func default_base_for(p: String) -> String
func effective_base() -> String              # base 空时用协议默认值（GUI 预填）

func to_dict() -> Dictionary
func apply_dict(d: Dictionary) -> void       # 键：enabled/base_url/api_key/protocol/model/temperature_observer|event|dialog

static func obfuscate(plain: String) -> String   # "b64:" + XOR(base64)
static func deobfuscate(blob: String) -> String  # 无 b64: 前缀按旧明文兼容
```

配置文件结构（离线可读、可手改）：

```ini
[llm]
enabled=true
base_url="https://api.deepseek.com"
api_key="b64:...."
protocol="deepseek"
model="deepseek-chat"

[temperature]
observer=0.3
event=0.5
dialog=0.8
```

Key 混淆是**防围观级**，不防解包（圆桌明示）。

## 2. LLMProtocol（全静态）

```gdscript
const ANTHROPIC_VERSION := "2023-06-01"
const DEFAULT_MAX_TOKENS := 512

static func normalize_protocol(p: String) -> String
static func normalize_base(protocol: String, raw_base: String) -> String
    # 去尾斜杠；openai/deepseek/anthropic 去重复 /v1；gemini 去 /v1beta 或 /v1
static func trim_model(m: String) -> String          # 剥 "models/" 前缀

static func chat_url(protocol, base, model, api_key := "") -> String
static func models_url(protocol, base, api_key := "") -> String  # anthropic 返回 ""（无列表端点）
static func headers(protocol, api_key) -> PackedStringArray
static func build_body(protocol, model, messages: Array, temperature: float,
        max_tokens := DEFAULT_MAX_TOKENS) -> String
static func build_chat_request(cfg: LLMConfig, messages: Array, temperature := -1.0,
        opts := {}) -> Dictionary
    # → {ok, reason, url, headers, body, method}；temperature < 0 时按 opts.scene_tag 查 cfg
    # opts.candidates: Array 非空 → 追加一条 system 消息列出候选槽位编号

static func extract_text(protocol, json_text) -> String     # 失败 ""
static func extract_error(protocol, json_text) -> String    # 4xx 可读原因
static func parse_models(protocol, json_text) -> Array      # data[].id / models[].name / 字符串数组
static func supports_model_list(protocol) -> bool
```

messages 统一格式：`[{"role": "system"|"user"|"assistant", "content": String}]`。

四家要点：
- openai / deepseek：`POST {base}/v1/chat/completions`，`Authorization: Bearer`；
- gemini：`POST {base}/v1beta/models/{model}:generateContent?key=...`，system 走 `systemInstruction`，assistant→`model`；
- anthropic：`POST {base}/v1/messages`，`x-api-key` + `anthropic-version` + **max_tokens 必填**，system 抽成顶层字段。

## 3. LLMParse（全静态）

动作白名单：`["ATTACK", "DEFEND", "CHARGE", "MARK", "TAUNT"]`。

```gdscript
static func strip_noise(raw) -> String    # 剥 ```json 围栏 / BOM / 零宽字符
static func strip_cot(raw) -> String      # 剥行首思维链前缀（思考：/分析：/Let me…）

## 四层：JSON → 动作词行 → 关键词正则 → null
static func parse_action(raw: String) -> Dictionary
#   {"ok": bool, "action": String, "line": String, "source": "json"|"line"|"regex"|"null"}
#   ok=false：action=""（调用方用本地兜底动作），line 仍带清理后的原文 —— 台词照播

## 三关：JSON 可解析 / pick 是 int / pick ∈ [1, pool_size]
static func parse_event(raw: String, pool_size: int) -> Dictionary
#   {"ok": bool, "pick": int, "reason": String, "source": "json"|"null"}
#   ok=false：pick=0，调用方静默落本地默认候选（不重试不道歉）
#   容忍 "2" / 2.0；reason 压平换行并截到 40 字

static func parse_dialogue(raw: String, max_len := 120) -> String
#   剥围栏/思维链/包裹引号，压成单行；无内容返回 ""
```

## 4. LLMClient

```gdscript
signal resolved(result: Dictionary)
signal circuit_tripped(status: int)

const MAX_CONCURRENCY := 2
const MAX_RETRIES := 1
const DEFAULT_TIMEOUT_S := 3.0
const CIRCUIT_STATUSES := [401, 402, 429]

var config: LLMConfig

func setup(cfg: LLMConfig) -> void
func set_config(cfg: LLMConfig) -> void
func set_backend(backend) -> void        # MockBackend / 自定义对象 / Callable；null = 真网络

func request(scene_tag: String, messages: Array, on_done: Callable, opts := {}) -> int
func cancel(rid: int) -> void
func shutdown() -> void

func is_circuit_open() -> bool
func circuit_status() -> int
func reset_circuit() -> void

func take_late_result(rid: int, pool_hash: String) -> Dictionary  # 取回并消费，无则 {}
func has_late_result(rid: int, pool_hash: String) -> bool
func clear_late_results() -> void
func late_result_count() -> int

func pending_count() -> int
func active_count() -> int
func inflight_count() -> int
# 观测：peak_active / total_requests / total_errors / total_cache_hits
```

`opts`：
| 键 | 类型 | 说明 |
|---|---|---|
| `resolve_id` | int | 复用给迟到缓存；缺省自增 |
| `pool_hash` | String | 候选池哈希（事件引擎用）；空 = 不缓存迟到结果 |
| `temperature` | float | 缺省按 `scene_tag` 查 `cfg.temp_for()` |
| `max_tokens` | int | 缺省 512（anthropic 必填） |
| `timeout_s` | float | 缺省 3.0；从**真正发出当帧**起算 |
| `candidates` | Array | 事件引擎的候选槽位表，自动补 system 消息 |

**`on_done(result)` 一定异步触发且只触发一次**（成功/失败/超时/短路都算）：

```gdscript
{
  "ok": bool,
  "text": String,          # 原始模型输出（未解析；解析交给 LLMParse）
  "reason": String,        # 失败原因，见下表；成功为空串
  "resolve_id": int,
  "scene_tag": String,
  "status": int,           # HTTP 状态码（mock 同）
  "from_cache": bool,      # 迟到缓存复用
  "late": bool,
  "detail": String,        # 4xx 错误正文摘要
}
```

`reason` 枚举：`disabled`（总开关关/配置不全）、`circuit_open`（session 熔断）、`timeout`、
`network`、`empty`（2xx 但正文空）、`http_401`/`http_402`/`http_429`、`http_4xx`、`http_5xx`、
`no_model`/`no_config`/`no_host`、`cancelled`。

行为契约：
- **并发≤2**：超出排队 FIFO；一个请求结束立刻 pump 下一个；
- **重试≤1**：只重试 5xx 与传输超时，且必须还有剩余预算（真超时已烧完预算 → 不重试）；4xx 永不重试；
- **熔断**：401/402/429 一次即 session 级熔断，后续请求直接回 `circuit_open`，不再打后端；战后 `reset_circuit()`；
- **超时**：每请求独立 `SceneTreeTimer`（`ignore_time_scale=true`），到点必回调 `timeout`，不拖演出；
- **迟到缓存**：超时后后端才回来的 2xx 正文存入 `_late_results`，下次**同 resolve_id + 同 pool_hash** 直接复用（`from_cache=true`，不再发请求）；TTL 60s / 上限 16 条；池哈希变了自然不命中。

### 4.1 接线骨架（battle / gui 通用）

```gdscript
var llm_cfg := LLMConfig.load_from_disk()
var llm := LLMClient.new()
add_child(llm)                  # Node：必须进树（或让它自动挂 root）
llm.setup(llm_cfg)

var rid := 1000 + turn * 10 + slot_index
llm.request("observer", messages, _on_observer_done, {
    "resolve_id": rid,
    "pool_hash": candidate_pool_hash,
    "timeout_s": 3.0,
})

func _on_observer_done(r: Dictionary) -> void:
    if not r["ok"]:
        _fallback_to_rules(String(r["reason"]))   # 静默，不弹窗
        return
    var parsed := LLMParse.parse_action(String(r["text"]))
    # parsed.ok=false 也要用 parsed.line 播台词，动作走本地兜底
```

### 4.2 MockBackend（无头验收三剧本）

```gdscript
var mock := LLMClient.MockBackend.new("normal")   # normal / garbage / hang / status / sequence
client.set_backend(mock)

mock.reply          # normal 回复文本
mock.garbage        # garbage 剧本输出
mock.status_code    # status 剧本状态码（如 401 / 500）
mock.delay_s        # 每个请求延迟（秒）
mock.scripts = [{"mode":"status","status":500}, {"mode":"normal","text":"OK"}]  # 顺序剧本
mock.requests       # 已收请求数
mock.last_scene_tag / last_messages / last_opts
```

- `hang`：永不回调，靠 `LLMClient` 超时计时器兜底 → 验证「3s 内规则表接管」；
- `status`：验 401 熔断 / 5xx 重试；
- 也支持 `client.set_backend(Callable)`，签名 `func(scene_tag, messages, opts, cb)`，`cb.call({ok,text,status,reason})` 或直接返回同结构 Dictionary。

## 5. 下游约定（照抄即可）

| 下游任务 | 用到的接口 |
|---|---|
| `battle-integration` | `LLMClient.request("observer", …)` + `LLMParse.parse_action`；resolve_id 建议 `关卡*1000 + 回合*10 + 槽位`；超时 3s 且 `pool_hash` 用本回合候选池哈希 |
| `event-engine` | `LLMParse.parse_event(text, pool_size)` 三关；`opts.candidates` 传预筛槽位；失败 pick=0 落本地默认 |
| `banter` | `LLMClient.request("dialog", …)` + `LLMParse.parse_dialogue`；纯台词，不进数值管线 |
| `gui-integration` | `LLMConfig.load_from_disk/save`、`apply_dict`、`default_base_for`、`temp_for`；模型列表 `LLMProtocol.models_url` + `parse_models`（anthropic 走手填） |
| `regression` | `MockBackend` 三剧本 + 本文第 4 节行为契约 |

## 6. 验证记录（llm-core 自测）

- 四模块 `--check-only`：全通过；
- `.tmp/swarm-llm-core/selftest.gd`（跑完已删）：**91 项检查，0 失败**，覆盖
  配置往返/混淆/温度、四家 URL+header+body、models 两种结构、动作四层、事件三关、台词清洗、
  并发峰值==2、挂起超时、5xx 重试 1 次、401 熔断短路、迟到缓存复用、总开关短路、Callable 后端；
- `tests/smoke_test.gd`：**242 项，0 失败**（基线 224，其余为同伴本轮新增断言），本任务未改任何现有文件。
