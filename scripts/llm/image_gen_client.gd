class_name ImageGenClient
extends Node
## 许愿卡生图客户端（2026-11-04 圆桌定稿）：
## - 独立 image 配置（模型/端点），Key 复用文本配置；
## - 异步 POST {base}/v1/images/generations → b64 → user://ai_cache/<sha256>.png；
## - 哈希缓存去重（同 prompt 二次许愿不再计费）；失败重试 1 次后放弃，由调用方给像素占位；
## - 默认关：image_enabled=false 时 start() 直接返回 image_disabled，不建 HTTPRequest
##   （smoke 基线不受影响）。

signal finished(ok: bool, path: String, reason: String)

const CACHE_DIR := "user://ai_cache"
const TIMEOUT_S := 180.0
const MAX_RETRY := 1
const SIZE := "1024x1024"

var _http: HTTPRequest = null
var _task := {}
var _busy := false
var _retries := 0


## 缓存路径（同 prompt + 同模型 → 同文件）
static func cache_path_for(prompt: String, model: String) -> String:
	return CACHE_DIR.path_join(prompt.sha256_text().substr(0, 32) + ".png")


func is_busy() -> bool:
	return _busy


## 发起一次生图。返回 {ok, cached, path, reason}：
## ok=false 表示不可用（未启用/忙）；cached=true 表示缓存命中，path 可直接用；
## cached=false 表示已受理，结果走 finished 信号。
func start(prompt: String, cfg: LLMConfig) -> Dictionary:
	return _start_common(prompt, cfg, "gen", "")


## 图生图精修：把玩家涂鸦作为参考图传给 edits 端点——AI「看图」后按 prompt
## 精修再创作，**不需要文本模型支持视觉**（生图模型天然理解参考图）。
func edit(prompt: String, image_path: String, cfg: LLMConfig) -> Dictionary:
	return _start_common(prompt, cfg, "edit", image_path)


func _start_common(prompt: String, cfg: LLMConfig, kind: String,
		image_path: String) -> Dictionary:
	## 返回 {ok, cached, path, reason}：
	## ok=false 表示不可用（未启用/忙）；cached=true 表示缓存命中，path 可直接用；
	## cached=false 表示已受理，结果走 finished 信号。
	if _busy:
		return {"ok": false, "reason": "busy", "cached": false, "path": ""}
	if cfg == null or not cfg.image_ready():
		return {"ok": false, "reason": "image_disabled", "cached": false, "path": ""}
	if kind == "edit" and (image_path.is_empty()
			or not FileAccess.file_exists(image_path)):
		return {"ok": false, "reason": "no_ref_image", "cached": false, "path": ""}
	var model := cfg.image_model.strip_edges()
	var path := cache_path_for(prompt + kind + image_path, model)
	if FileAccess.file_exists(path):
		return {"ok": true, "cached": true, "path": path, "reason": "cache"}
	_busy = true
	_retries = 0
	_task = {"prompt": prompt, "model": model, "cfg": cfg, "path": path,
			"kind": kind, "image_path": image_path}
	_send()
	return {"ok": true, "cached": false, "path": "", "reason": ""}


func _send() -> void:
	await get_tree().process_frame          # HTTPRequest 需 _ready 后才可 request
	if not is_inside_tree() or _task.is_empty():
		return
	if _http == null:
		_http = HTTPRequest.new()
		_http.name = "ImageHttp"
		_http.timeout = TIMEOUT_S
		## 同 llm_client：Web 版经 Worker 转发后 gzip 解不开，必须关掉
		if OS.has_feature("web"):
			_http.accept_gzip = false
		add_child(_http)
		_http.request_completed.connect(_on_done)
	var cfg: LLMConfig = _task["cfg"]
	var base := cfg.effective_image_base().trim_suffix("/")
	var headers := PackedStringArray()
	if cfg.effective_image_key() != "":
		headers.append("Authorization: Bearer " + cfg.effective_image_key())
	var body: PackedByteArray = PackedByteArray()
	var url := ""
	var err := OK
	if String(_task.get("kind", "gen")) == "edit":
		## 图生图精修：JSON + base64 data URI（实测网关支持，绕开 multipart）
		url = base + "/v1/images/edits"
		headers.append("Content-Type: application/json")
		var bin := FileAccess.get_file_as_bytes(String(_task["image_path"]))
		var data_uri := "data:image/png;base64," + Marshalls.raw_to_base64(bin)
		var jbody := JSON.stringify({
			"model": String(_task["model"]),
			"prompt": String(_task["prompt"]),
			"image": data_uri,
			"size": SIZE,
		})
		err = _http.request(LLMProtocol.absolutize(url), headers, HTTPClient.METHOD_POST, jbody)
	else:
		url = base + "/v1/images/generations"
		headers.append("Content-Type: application/json")
		var jbody := JSON.stringify({
			"model": String(_task["model"]),
			"prompt": String(_task["prompt"]),
			"size": SIZE,
		})
		err = _http.request(LLMProtocol.absolutize(url), headers, HTTPClient.METHOD_POST, jbody)
	if err != OK:
		_fail("request_error")


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("http_%d" % code)
		return
	var j = JSON.parse_string(body.get_string_from_utf8())
	if not (j is Dictionary):
		_fail("bad_json")
		return
	var data = (j as Dictionary).get("data", [])
	if not (data is Array) or (data as Array).is_empty():
		_fail("no_data")
		return
	var b64 := String(((data as Array)[0] as Dictionary).get("b64_json", ""))
	if b64.is_empty():
		_fail("no_b64")
		return
	var img := Image.new()
	if img.load_png_from_buffer(Marshalls.base64_to_raw(b64)) != OK:
		_fail("bad_png")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var path := String(_task["path"])
	if img.save_png(path) != OK:
		_fail("save_failed")
		return
	_busy = false
	_task = {}
	finished.emit(true, path, "ok")


func _fail(reason: String) -> void:
	if _retries < MAX_RETRY:
		_retries += 1
		_send()
		return
	_busy = false
	_task = {}
	finished.emit(false, "", reason)
