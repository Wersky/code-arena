class_name LLMClient
extends Node
## LLM 唯一网络出口：队列 / 并发上限 / 重试 / 熔断 / 迟到缓存 / Mock 注入。
##
## 圆桌终案口径：
##   - 每次请求 new HTTPRequest 子节点，回调里立刻 queue_free（防并发信号串线）；
##   - 并发上限 2（MAX_CONCURRENCY），多余请求排队；
##   - 网络层重试 ≤1，只重试 5xx 与传输超时；4xx 永不重试；
##   - 401 / 402 / 429 → session 级熔断，后续请求直接短路（防烧余额）；
##   - 单请求 3s 截止（从真正发出当帧算），到时回调 reason="timeout"；
##   - 迟到结果不丢：入 _late_results，下次同 resolve_id + 同 pool_hash 直接复用；
##   - set_backend(mock) 注入假后端，无头测试零真网络。
##
## 用法：
##   var client := LLMClient.new()
##   add_child(client)
##   client.setup(LLMConfig.load_from_disk())
##   var rid := client.request("observer", messages, func(r): print(r))
##
## 回调 result 字典字段：
##   ok: bool | text: String | reason: String | resolve_id: int | scene_tag: String
##   status: int | from_cache: bool | late: bool | detail: String
##
## 失败 reason 枚举：disabled / circuit_open / timeout / network / empty /
##   http_401 / http_402 / http_429 / http_4xx / http_5xx / no_model / no_config / no_host

signal resolved(result: Dictionary)
signal circuit_tripped(status: int)

const MAX_CONCURRENCY := 2
const MAX_RETRIES := 1
const DEFAULT_TIMEOUT_S := 3.0
const CIRCUIT_STATUSES := [401, 402, 429]
const LATE_TTL_S := 60.0
const LATE_MAX := 16

var config: LLMConfig = null

## 可注入的假后端；null = 走真 HTTP。见下方 class MockBackend。
var _backend = null

var _jobs: Dictionary = {}       ## rid -> job dict
var _pending: Array = []         ## 排队中的 rid（FIFO）
var _active: Array = []          ## 在飞 rid（≤ MAX_CONCURRENCY）
var _late_results: Dictionary = {}  ## "rid|pool_hash" -> {"text": String, "at": float}
var _next_rid := 1
var _circuit_open := false
var _circuit_status := 0

# 观测计数（测试/日志用）
var peak_active := 0
var total_requests := 0
var total_errors := 0
var total_cache_hits := 0


# ══ 装配 ══════════════════════════════════════════════
func setup(cfg: LLMConfig) -> void:
	config = cfg


func set_config(cfg: LLMConfig) -> void:
	config = cfg


## 注入假后端（MockBackend / 自定义对象 / Callable）；传 null 恢复真网络。
func set_backend(backend) -> void:
	_backend = backend


func get_backend():
	return _backend


# ══ 请求 ══════════════════════════════════════════════
## 返回 resolve_id。on_done(result: Dictionary) 总是异步触发一次。
## opts: {
##   resolve_id: int（复用给迟到缓存；缺省自增）,
##   pool_hash: String（候选池哈希，迟到缓存复用键；空 = 不缓存）,
##   temperature: float（缺省按 scene_tag 查表）,
##   max_tokens: int,
##   timeout_s: float（缺省 3.0）,
##   candidates: Array（附给事件引擎的候选池编号表）
## }
func request(scene_tag: String, messages: Array, on_done: Callable, opts: Dictionary = {}) -> int:
	var rid := int(opts.get("resolve_id", 0))
	if rid <= 0:
		rid = _alloc_rid()
	else:
		_next_rid = maxi(_next_rid, rid + 1)

	var job := {
		"rid": rid,
		"scene_tag": String(scene_tag),
		"messages": _normalize_messages(messages),
		"opts": opts,
		"cb": on_done,
		"timeout_s": maxf(0.05, float(opts.get("timeout_s", DEFAULT_TIMEOUT_S))),
		"pool_hash": String(opts.get("pool_hash", "")),
		"attempt": 0,
		"done": false,
		"timed_out": false,
		"late_pending": false,
		"launch_at": 0.0,
		"deadline": 0.0,
		"http": null,
	}
	_jobs[rid] = job

	# 闸 1：总开关 / 必填项不全 → 短路走规则表
	if config == null or not config.is_enabled():
		job["done"] = true
		_deliver_async(job, _res(job, false, "", "disabled"))
		return rid

	# 闸 2：session 级熔断
	if _circuit_open:
		job["done"] = true
		_deliver_async(job, _res(job, false, "", "circuit_open"))
		return rid

	# 闸 3：迟到缓存复用（同 resolve_id + 同 pool_hash）
	if not String(job["pool_hash"]).is_empty():
		var cached := take_late_result(rid, String(job["pool_hash"]))
		if not cached.is_empty():
			job["done"] = true
			total_cache_hits += 1
			var r := _res(job, true, String(cached.get("text", "")), "")
			r["from_cache"] = true
			_deliver_async(job, r)
			return rid

	if _active.size() < MAX_CONCURRENCY:
		_launch(rid)
	else:
		_pending.append(rid)
	return rid


func cancel(rid: int) -> void:
	var job = _jobs.get(rid)
	if job == null:
		return
	if not job["done"]:
		job["done"] = true
		_free_http(job)
		_remove_active(rid)
		_deliver_async(job, _res(job, false, "", "cancelled"))
	_pump()


func _alloc_rid() -> int:
	var rid := _next_rid
	_next_rid += 1
	return rid


func _normalize_messages(messages: Array) -> Array:
	var out: Array = []
	for m in messages:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var content = m.get("content", "")
		if typeof(content) == TYPE_ARRAY:
			## 多模态：content 是 [{type,text},{type,image_url,...}] 数组，
			## **必须原样保留**——用 str() 拍平会把图片变成 base64 乱码文本，
			## 模型看不到图只能瞎猜（2026-11-05 修：箭头/房子/S 被认成蘑菇/小兽的根因）
			out.append({"role": String(m.get("role", "user")), "content": content})
		else:
			out.append({"role": String(m.get("role", "user")),
					"content": _text_of(content)})
	return out


func _text_of(v) -> String:
	if typeof(v) == TYPE_STRING:
		return v
	return str(v)


# ══ 调度 ══════════════════════════════════════════════
func _launch(rid: int) -> void:
	var job = _jobs.get(rid)
	if job == null or job["done"]:
		return
	job["attempt"] = int(job["attempt"]) + 1
	job["launch_at"] = _now()
	job["deadline"] = float(job["launch_at"]) + float(job["timeout_s"])
	_active.append(rid)
	peak_active = maxi(peak_active, _active.size())
	total_requests += 1
	if _backend != null:
		call_deferred("_launch_mock", rid)
	else:
		_launch_http(rid)
	_arm_timeout(rid, int(job["attempt"]), float(job["timeout_s"]))


func _launch_http(rid: int) -> void:
	var job = _jobs.get(rid)
	if job == null or job["done"]:
		return
	var opts: Dictionary = (job["opts"] as Dictionary).duplicate()
	opts["scene_tag"] = job["scene_tag"]
	var req := LLMProtocol.build_chat_request(config, job["messages"], -1.0, opts)
	if not bool(req.get("ok", false)):
		_fail(rid, job, String(req.get("reason", "no_config")), 0)
		return
	var host := _host()
	if host == null:
		_fail(rid, job, "no_host", 0)
		return
	var http := HTTPRequest.new()
	http.name = "LLMHttp_%d" % rid
	http.timeout = float(job["timeout_s"])
	http.max_redirects = 3
	host.add_child(http)
	job["http"] = http
	http.request_completed.connect(_on_http.bind(rid, int(job["attempt"])))
	var err := http.request(String(req["url"]), req["headers"], int(req["method"]), String(req["body"]))
	if err != OK:
		_free_http(job)
		_fail(rid, job, "network", 0)


func _launch_mock(rid: int) -> void:
	var job = _jobs.get(rid)
	if job == null or job["done"]:
		return
	var cb := Callable(self, "_on_mock_done").bind(rid, int(job["attempt"]))
	var ret = null
	if _backend is Callable:
		ret = (_backend as Callable).call(job["scene_tag"], job["messages"], job["opts"], cb)
	elif typeof(_backend) == TYPE_OBJECT and _backend.has_method("request"):
		ret = _backend.request(job["scene_tag"], job["messages"], job["opts"], cb)
	else:
		_fail(rid, job, "bad_backend", 0)
		return
	if typeof(ret) == TYPE_DICTIONARY:
		_on_mock_done(ret, rid, int(job["attempt"]))


func _arm_timeout(rid: int, attempt: int, secs: float) -> void:
	var tree := _tree()
	if tree == null:
		return
	var timer := tree.create_timer(secs, true, false, true)
	timer.timeout.connect(_on_timeout.bind(rid, attempt))


func _on_timeout(rid: int, attempt: int) -> void:
	var job = _jobs.get(rid)
	if job == null or job["done"] or int(job["attempt"]) != attempt:
		return
	job["done"] = true
	job["timed_out"] = true
	job["late_pending"] = true
	_remove_active(rid)
	total_errors += 1
	_finish(job, _res(job, false, "", "timeout"))
	_pump()


func _pump() -> void:
	while _active.size() < MAX_CONCURRENCY and not _pending.is_empty():
		var rid = _pending.pop_front()
		var job = _jobs.get(rid)
		if job == null or job["done"]:
			continue
		_launch(int(rid))


func _remove_active(rid: int) -> void:
	var i := _active.find(rid)
	if i >= 0:
		_active.remove_at(i)


# ══ 真网络回调 ════════════════════════════════════════
func _on_http(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		rid: int, attempt: int) -> void:
	var job = _jobs.get(rid)
	if job == null or int(job["attempt"]) != attempt:
		return
	var body_text := body.get_string_from_utf8()
	var had_http: bool = job["http"] != null
	_free_http(job)

	# 已超时交付过：结果只入迟到缓存，不再二次回调
	if job["done"]:
		if had_http and job["timed_out"]:
			_store_late(job, result, code, body_text)
		_jobs.erase(rid)
		return

	if result != HTTPRequest.RESULT_SUCCESS:
		var reason := "timeout" if result == HTTPRequest.RESULT_TIMEOUT else "network"
		if result == HTTPRequest.RESULT_TIMEOUT and _can_retry(job):
			_retry(rid, job)
			return
		_fail(rid, job, reason, 0)
		return

	if code >= 200 and code < 300:
		var text := LLMProtocol.extract_text(config.protocol, body_text)
		## 大模型绘图：回复里可能带 SVG 代码或位图（如 data URI），与正文并存
		var image := LLMProtocol.extract_image(config.protocol, body_text)
		if text.strip_edges().is_empty() and image.is_empty() 				and LLMProtocol.extract_svg_from_text(text).is_empty():
			_fail(rid, job, "empty", code)
			return
		_succeed(rid, job, text, code, body_text)
		return

	if CIRCUIT_STATUSES.has(code):
		_open_circuit(code)
		_fail(rid, job, "http_%d" % code, code)
		return

	if code >= 500 and code < 600:
		if _can_retry(job):
			_retry(rid, job)
			return
		_fail(rid, job, "http_5xx", code)
		return

	var detail := LLMProtocol.extract_error(config.protocol, body_text)
	_fail(rid, job, "http_4xx", code, detail)


## 重试窗口：≤1 次，且必须还有剩余预算（真超时已把预算烧完 → 不重试）
func _can_retry(job: Dictionary) -> bool:
	if int(job["attempt"]) > MAX_RETRIES:
		return false
	return _now() < float(job["deadline"]) - 0.25


func _retry(rid: int, job: Dictionary) -> void:
	_remove_active(rid)
	_launch(rid)


# ══ Mock 回调 ═════════════════════════════════════════
func _on_mock_done(ret: Dictionary, rid: int, attempt: int) -> void:
	var job = _jobs.get(rid)
	if job == null or int(job["attempt"]) != attempt:
		return
	if job["done"]:
		if job["timed_out"]:
			_store_late_mock(job, ret)
		_jobs.erase(rid)
		return
	var ok := bool(ret.get("ok", false))
	var status := int(ret.get("status", 0))
	if ok:
		_succeed(rid, job, String(ret.get("text", "")), status,
				String(ret.get("text", "")))
		return
	if CIRCUIT_STATUSES.has(status):
		_open_circuit(status)
		_fail(rid, job, "http_%d" % status, status)
		return
	if status >= 500 and status < 600 and _can_retry(job):
		_retry(rid, job)
		return
	_fail(rid, job, String(ret.get("reason", "mock_error")), status)


# ══ 终态 ══════════════════════════════════════════════
func _succeed(rid: int, job: Dictionary, text: String, code: int,
		raw_text: String = "") -> void:
	job["done"] = true
	_remove_active(rid)
	var r := _res(job, true, text, "", code)
	var src := raw_text if not raw_text.is_empty() else text
	r["image"] = LLMProtocol.extract_image(config.protocol, src)
	r["svg"] = LLMProtocol.extract_svg_from_text(text)
	_finish(job, r)
	_pump()


func _fail(rid: int, job: Dictionary, reason: String, code: int, detail: String = "") -> void:
	job["done"] = true
	_remove_active(rid)
	total_errors += 1
	var r := _res(job, false, "", reason, code)
	r["detail"] = detail
	_finish(job, r)
	_pump()


func _finish(job: Dictionary, result: Dictionary) -> void:
	var cb: Callable = job["cb"]
	if cb.is_valid():
		cb.call(result)
	resolved.emit(result)
	# 超时后仍等后端迟到回包的 job 先留着（late_pending），否则当场清掉
	if job["http"] == null and not bool(job.get("late_pending", false)):
		_jobs.erase(int(job["rid"]))


func _deliver_async(job: Dictionary, result: Dictionary) -> void:
	call_deferred("_deliver_deferred", job, result)


func _deliver_deferred(job: Dictionary, result: Dictionary) -> void:
	if job == null:
		return
	var cb: Callable = job["cb"]
	if cb.is_valid():
		cb.call(result)
	resolved.emit(result)
	if int(job["rid"]) > 0:
		_jobs.erase(int(job["rid"]))


func _res(job: Dictionary, ok: bool, text: String, reason: String, status: int = 0) -> Dictionary:
	return {
		"ok": ok,
		"text": text,
		"reason": reason,
		"resolve_id": int(job["rid"]),
		"scene_tag": String(job["scene_tag"]),
		"status": status,
		"from_cache": false,
		"late": false,
		"detail": "",
	}


# ══ 迟到结果缓存 ══════════════════════════════════════
func _late_key(rid: int, pool_hash: String) -> String:
	return "%d|%s" % [rid, pool_hash]


func has_late_result(rid: int, pool_hash: String) -> bool:
	var v = _late_results.get(_late_key(rid, pool_hash))
	if v == null:
		return false
	return _now() - float(v.get("at", 0.0)) <= LATE_TTL_S


## 取回并消费；无/过期/池哈希不符返回 {}。
func take_late_result(rid: int, pool_hash: String) -> Dictionary:
	if pool_hash.is_empty():
		return {}
	var key := _late_key(rid, pool_hash)
	var v = _late_results.get(key)
	if v == null:
		return {}
	_late_results.erase(key)
	if _now() - float(v.get("at", 0.0)) > LATE_TTL_S:
		return {}
	var out := {"text": String(v.get("text", "")), "at": float(v.get("at", 0.0))}
	return out


func clear_late_results() -> void:
	_late_results.clear()


func late_result_count() -> int:
	return _late_results.size()


func _store_late(job: Dictionary, result: int, code: int, body_text: String) -> void:
	if String(job["pool_hash"]).is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return
	var text := LLMProtocol.extract_text(config.protocol, body_text)
	if text.strip_edges().is_empty():
		return
	_put_late(job, text)


func _store_late_mock(job: Dictionary, ret: Dictionary) -> void:
	if String(job["pool_hash"]).is_empty():
		return
	if not bool(ret.get("ok", false)):
		return
	var text := String(ret.get("text", ""))
	if text.strip_edges().is_empty():
		return
	_put_late(job, text)


func _put_late(job: Dictionary, text: String) -> void:
	_late_results[_late_key(int(job["rid"]), String(job["pool_hash"]))] = {
		"text": text, "at": _now(),
	}
	while _late_results.size() > LATE_MAX:
		var oldest_key := ""
		var oldest_at := INF
		for k in _late_results.keys():
			var at := float(_late_results[k].get("at", 0.0))
			if at < oldest_at:
				oldest_at = at
				oldest_key = k
		if oldest_key.is_empty():
			break
		_late_results.erase(oldest_key)
	_jobs.erase(int(job["rid"]))


# ══ 熔断 ══════════════════════════════════════════════
func _open_circuit(status: int) -> void:
	if _circuit_open:
		return
	_circuit_open = true
	_circuit_status = status
	circuit_tripped.emit(status)


func is_circuit_open() -> bool:
	return _circuit_open


func circuit_status() -> int:
	return _circuit_status


## 战后/换会话时手动复位（GUI 提示一次后调用）
func reset_circuit() -> void:
	_circuit_open = false
	_circuit_status = 0


# ══ 查询 / 清理 ═══════════════════════════════════════
func pending_count() -> int:
	return _pending.size()


func active_count() -> int:
	return _active.size()


func inflight_count() -> int:
	return _jobs.size()


func shutdown() -> void:
	for rid in _jobs.keys():
		var job = _jobs[rid]
		_free_http(job)
		job["done"] = true
	_jobs.clear()
	_pending.clear()
	_active.clear()
	_late_results.clear()


func _free_http(job: Dictionary) -> void:
	var http = job.get("http")
	if http != null and is_instance_valid(http):
		http.queue_free()
	job["http"] = null


func _host() -> Node:
	if is_inside_tree():
		return self
	var tree := _tree()
	return tree.root if tree != null else null


func _tree() -> SceneTree:
	if is_inside_tree():
		return get_tree()
	return Engine.get_main_loop() as SceneTree


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ══ MockBackend（无头验收三剧本）══════════════════════
## 用法：
##   var mock := LLMClient.MockBackend.new("normal")
##   client.set_backend(mock)
## 模式：normal（正常回话）/ garbage（垃圾输出，供解析层容错）/ hang（永不回调，验超时）
##       / status（返回指定 HTTP 状态码，验熔断/重试）/ sequence（按 scripts 顺序出牌）
class MockBackend extends RefCounted:
	var mode := "normal"
	var reply := "ATTACK\n\n检测到非法连击，已加入回收队列。"
	var garbage := "```json\n{ 这不是合法 JSON \n```\n好的，我先分析一下局面……"
	var status_code := 500
	var delay_s := 0.0
	## 顺序剧本：每项 {mode? / ok? / text? / status? / delay?}，用完后重复最后一项
	var scripts: Array = []
	var requests := 0
	var last_scene_tag := ""
	var last_messages: Array = []
	var last_opts: Dictionary = {}

	func _init(p_mode: String = "normal") -> void:
		mode = p_mode

	func request(scene_tag: String, messages: Array, opts: Dictionary, cb: Callable) -> void:
		requests += 1
		last_scene_tag = scene_tag
		last_messages = messages
		last_opts = opts
		var spec: Dictionary = {}
		if not scripts.is_empty():
			spec = scripts.pop_front() if scripts.size() > 1 else scripts[0]
		var m := String(spec.get("mode", mode))
		var wait := float(spec.get("delay", delay_s))
		var payload := _payload_for(m, spec)
		if m == "hang":
			return  # 永不回调：靠 LLMClient 的 3s 计时器兜底
		if wait <= 0.0:
			cb.call(payload)
			return
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			cb.call(payload)
			return
		var timer := tree.create_timer(wait, true, false, true)
		timer.timeout.connect(func() -> void: cb.call(payload))

	func _payload_for(m: String, spec: Dictionary) -> Dictionary:
		match m:
			"garbage":
				return {"ok": true, "text": String(spec.get("text", garbage)), "status": 200}
			"hang":
				return {}
			"status":
				var code := int(spec.get("status", status_code))
				return {"ok": code >= 200 and code < 300, "text": "",
						"status": code, "reason": "http_%d" % code}
			"error":
				return {"ok": false, "text": "", "status": 0,
						"reason": String(spec.get("reason", "network"))}
			_:
				return {"ok": true, "text": String(spec.get("text", reply)), "status": 200}
