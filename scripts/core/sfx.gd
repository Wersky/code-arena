class_name SfxNode
extends Node
## 音效单例。**调用入口一律用类名静态方法**：`SfxNode.play("card_select")`。
##
## 为什么是「class_name + 静态转发」而不是直接引用 autoload：
##   `--headless --script` 跑测试时 Godot **不注册 autoload**，
##   全局标识符 Sfx 在测试脚本里直接编译失败（踩坑实录：169 项回归炸成 162）。
##   走真实类名 + `static var I` 转发，游戏里有节点就出声、测试里没有就空操作。
##
## 用法：
##   SfxNode.play("card_select")      # 音效（SFX 总线 + 播放器池）
##   SfxNode.music("bgm_main")        # BGM（同名不重头播）
##   SfxNode.set_music_volume_db(-12)
##
## 同时仍是 autoload（project.godot 里注册为 Sfx）——真实运行时靠它把自己挂上。

const SFX_DIR := "res://assets/audio/sfx"
const MUSIC_DIR := "res://assets/audio/music"
const POOL_SIZE := 12

## 当前实例（autoload _ready 时赋值；测试/工具进程里保持 null）
static var I: SfxNode = null

var _pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer = null
var _streams: Dictionary = {}
var _music_name := ""
var _music_volume_db := 0.0


func _ready() -> void:
	I = self
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)


# ── 静态入口（写代码只调这两个 + 音量） ───────────────
static func play(sfx_name: String, vol_db := 0.0) -> void:
	if I != null:
		I._play(sfx_name, vol_db)


static func music(music_name: String) -> void:
	if I != null:
		I._music(music_name)


static func stop_music() -> void:
	if I != null:
		I._music_stop()


static func set_music_volume_db(db: float) -> void:
	if I != null:
		I._music_volume_db = db
		I._music_player.volume_db = db


# ── 实例实现 ─────────────────────────────────────────
func _play(sfx_name: String, vol_db: float) -> void:
	var st := _stream(sfx_name, SFX_DIR)
	if st == null:
		return
	# 找空闲播放器；全忙就抢播放进度最深的那只（短音效场景够用）
	var victim := _pool[0]
	for p in _pool:
		if not p.playing:
			victim = p
			break
		elif p.get_playback_position() > victim.get_playback_position():
			victim = p
	victim.stream = st
	victim.volume_db = vol_db
	victim.play()


func _music(music_name: String) -> void:
	if music_name == _music_name and _music_player.playing:
		return
	var st := _stream(music_name, MUSIC_DIR)
	if st == null:
		return
	if st is AudioStreamWAV:
		# wav 默认不循环；16-bit 单声道帧数 = 字节数 / 2
		var wav := st as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 2
	elif st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true
	_music_player.stream = st
	_music_player.volume_db = _music_volume_db
	_music_player.play()
	_music_name = music_name


func _music_stop() -> void:
	_music_player.stop()
	_music_name = ""


func _stream(name: String, dir: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	# 同名优先 wav，没有再试 mp3（BGM 现在是 mp3，音效仍是 wav）
	var st: AudioStream = null
	for ext in [".wav", ".mp3"]:
		var path := "%s/%s%s" % [dir, name, ext]
		if ResourceLoader.exists(path):
			st = load(path) as AudioStream
			if st != null:
				_streams[name] = st
			break
	if st == null:
		push_warning("SfxNode：找不到音频 %s/%s.(wav|mp3)" % [dir, name])
	return st
