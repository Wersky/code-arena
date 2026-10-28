class_name ExtTerminal
extends Node
## 真实系统终端进场（Windows）：**真的弹出一个终端窗口**跑整套演出。
##
## 流程：生成脚本 → 用 cmd 的 start 打开一个 PowerShell 窗口 →
##   开机行 → 逐字敲角色代码 → 停 1 秒 → 清屏 → 打印 ASCII 字符画 → 窗口自己关掉，
##   同时写一个哨兵文件；本节点轮询到哨兵（或超时）后回调「进场」。
##
## 为什么走外部终端：主人要的是「电脑本体的终端」那股味道，游戏内画的终归是假终端。
## 启动失败（没有 pwsh/powershell、策略禁止）返回 false，由调用方回退到游戏内版本。

signal finished

const SCRIPT_PATH := "user://term_intro.ps1"
const SENTINEL := "user://term_intro.done"
const ART_ROWS := 38            ## 终端里画多少行（窗口拉到 38 行时刚好）
const TYPE_DELAY_MS := 24       ## 每「块」间隔（宿主 sleep 有 ~15ms 下限，逐字符会拖到 7 秒）
const TYPE_CHUNK := 6           ## 每次写入的字符数 → 6 字/34ms ≈ 176 字/秒
const HOLD_MS := 1000           ## 代码打完停留（主人指定 1 秒）
const ART_HOLD_MS := 1200       ## 字符画停留
const TIMEOUT := 20.0

var _on_done := Callable()
var _done := false
var _t := 0.0


## 启动演出；返回 false = 没能启动（调用方回退游戏内终端）
func play(ai_id: String, ai_name: String, art_tex: Texture2D, on_done: Callable) -> bool:
	_on_done = on_done
	var sentinel := ProjectSettings.globalize_path(SENTINEL)
	if FileAccess.file_exists(SENTINEL):
		DirAccess.remove_absolute(sentinel)

	var art := AsciiArt.build(art_tex, ART_ROWS)
	var code := IntroScript.code_for(ai_id, ai_name)
	var script := _compose(ai_name, code, art)

	var f := FileAccess.open(SCRIPT_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[ExtTerminal] 脚本写不进去：%s" % SCRIPT_PATH)
		return false
	f.store_string(script)
	f.close()

	var script_abs := ProjectSettings.globalize_path(SCRIPT_PATH)
	var pid := OS.create_process("cmd.exe", [
		"/c", "start", "\"arena_os\"", "powershell", "-NoProfile",
		"-ExecutionPolicy", "Bypass", "-File", script_abs, sentinel])
	if pid <= 0:
		push_warning("[ExtTerminal] 终端启动失败")
		return false
	set_process(true)
	return true


func _process(delta: float) -> void:
	_t += delta
	if FileAccess.file_exists(SENTINEL):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SENTINEL))
		_finish()
		return
	if _t > TIMEOUT:
		push_warning("[ExtTerminal] 超时，直接进场")
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	finished.emit()
	if _on_done.is_valid():
		_on_done.call()
	queue_free()


# ── 拼脚本正文 ───────────────────────────────
func _compose(ai_name: String, code: PackedStringArray, art: PackedStringArray) -> String:
	var ps := ""
	ps += "param([string]$Sentinel)\n"
	ps += "$ErrorActionPreference='SilentlyContinue'\n"
	# 窗口拉到 110x38：34 行字符画才塞得下（先把缓冲区做大，再改窗口）
	ps += "try{$b=$Host.UI.RawUI.BufferSize;$b.Width=120;$b.Height=600;" \
		+ "$Host.UI.RawUI.BufferSize=$b;$w=$Host.UI.RawUI.WindowSize;" \
		+ "$w.Width=120;$w.Height=44;$Host.UI.RawUI.WindowSize=$w}catch{}\n"
	ps += "$Host.UI.RawUI.WindowTitle='arena_os :: %s'\n" % _esc(ai_name)
	ps += "Clear-Host\n"
	ps += "function T([string]$s,[int]$chunk,[int]$d){for($i=0;$i -lt $s.Length;$i+=$chunk){" \
		+ "[Console]::Write($s.Substring($i,[Math]::Min($chunk,$s.Length-$i)));" \
		+ "Start-Sleep -Milliseconds $d};[Console]::WriteLine()}\n"
	for l in IntroScript.boot_lines(ai_name):
		ps += "Write-Host '%s' -ForegroundColor DarkGreen\n" % _esc(l)
		ps += "Start-Sleep -Milliseconds 90\n"
	ps += "Start-Sleep -Milliseconds 150\n"
	ps += "$code = @'\n" + "\n".join(code) + "\n'@ -split \"`n\"\n"
	ps += "foreach($l in $code){ T $l %d %d }\n" % [TYPE_CHUNK, TYPE_DELAY_MS]
	ps += "Start-Sleep -Milliseconds %d\n" % HOLD_MS
	ps += "Clear-Host\n"
	ps += "$art = @'\n" + "\n".join(art) + "\n'@ -split \"`n\"\n"
	ps += "foreach($l in $art){ Write-Host $l -ForegroundColor Gray }\n"
	ps += "Start-Sleep -Milliseconds %d\n" % ART_HOLD_MS
	ps += "New-Item -ItemType File -Path $Sentinel -Force | Out-Null\n"
	ps += "Start-Sleep -Milliseconds 120\n"
	ps += "exit\n"
	return ps


## 单引号字符串转义（PowerShell 里 '' 表示一个单引号）
func _esc(s: String) -> String:
	return s.replace("'", "''")
