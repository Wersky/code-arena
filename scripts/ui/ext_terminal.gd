class_name ExtTerminal
extends Node
## 真实系统终端进场（Windows）：真的弹出一个**最大化**的终端窗口跑整套演出。
##
## 流程：生成脚本 → cmd 的 start 打开终端 → 开机行 → 逐块敲角色代码（速度取自开始界面）
##   → 停 1 秒 → 清屏 → ASCII 胸像**三档亮度叠印淡入** → 停留 2 秒 → 窗口自关 + 写哨兵
##   → 游戏侧黑幕淡出、手牌弹入（见 arena._play_intro）。
## 任意时刻按 **Ctrl** 快进（全局轮询 VK_CONTROL，不要求终端有焦点）。

signal finished

const SCRIPT_PATH := "user://term_intro.ps1"
const SENTINEL := "user://term_intro.done"
const ART_ROWS := 40            ## 终端里画多少行（最大化后够放）
const HOLD_MS := 1000           ## 代码打完停留（主人指定 1 秒）
const ART_HOLD_MS := 2000       ## 字符画停留 2 秒后融回游戏（主人指定）
const TIMEOUT := 45.0

var _on_done := Callable()
var _done := false
var _t := 0.0


func play(ai_id: String, ai_name: String, art_tex: Texture2D, on_done: Callable) -> bool:
	_on_done = on_done
	var sentinel := ProjectSettings.globalize_path(SENTINEL)
	if FileAccess.file_exists(SENTINEL):
		DirAccess.remove_absolute(sentinel)

	var art := AsciiArt.build(art_tex, ART_ROWS, 150)
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
	var delay := GameSettings.type_delay()
	var chunk := GameSettings.type_chunk()
	var ps := ""
	ps += "param([string]$Sentinel)\n"
	ps += "$ErrorActionPreference='SilentlyContinue'\n"
	# Win32：最大化窗口 + 全局 Ctrl 轮询（快进）
	ps += "$sig='[DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr h,int n);" \
		+ "[DllImport(\"user32.dll\")] public static extern short GetAsyncKeyState(int v);'\n"
	ps += "$W = Add-Type -MemberDefinition $sig -Name 'W' -PassThru\n"
	ps += "function Fast(){ return (($W::GetAsyncKeyState(0x11) -band 0x8000) -ne 0) }\n"
	# 先按物理上限放大缓冲区/窗口，再交给系统最大化
	ps += "try{$mp=$Host.UI.RawUI.MaxPhysicalWindowSize;" \
		+ "$b=$Host.UI.RawUI.BufferSize;$b.Width=[Math]::Max(120,$mp.Width);$b.Height=999;" \
		+ "$Host.UI.RawUI.BufferSize=$b;" \
		+ "$w=$Host.UI.RawUI.WindowSize;$w.Width=$mp.Width;$w.Height=$mp.Height;" \
		+ "$Host.UI.RawUI.WindowSize=$w}catch{}\n"
	ps += "try{$h=(Get-Process -Id $PID).MainWindowHandle;" \
		+ "if($h -ne 0){ $W::ShowWindow($h,3) | Out-Null }}catch{}\n"
	ps += "$Host.UI.RawUI.WindowTitle='arena_os :: %s'\n" % _esc(ai_name)
	ps += "Clear-Host\n"
	# 打字：分块写；扫到 Ctrl 就把本行剩余一次吐出
	ps += "function T([string]$s,[int]$chunk,[int]$d){" \
		+ "for($i=0;$i -lt $s.Length;$i+=$chunk){" \
		+ "if(Fast){[Console]::Write($s.Substring($i));return}" \
		+ "[Console]::Write($s.Substring($i,[Math]::Min($chunk,$s.Length-$i)));" \
		+ "Start-Sleep -Milliseconds $d}}\n"
	# 等待：Ctrl 可提前结束
	ps += "function Wait([int]$ms){$t=0;while($t -lt $ms){if(Fast){return};" \
		+ "Start-Sleep -Milliseconds 40;$t+=40}}\n"
	for l in IntroScript.boot_lines(ai_name):
		ps += "Write-Host '%s' -ForegroundColor DarkGreen\n" % _esc(l)
		ps += "Wait 120\n"
	ps += "Wait 150\n"
	ps += "$code = @'\n" + "\n".join(code) + "\n'@ -split \"`n\"\n"
	ps += "foreach($l in $code){ T $l %d %d; [Console]::WriteLine() }\n" % [chunk, delay]
	ps += "Wait %d\n" % HOLD_MS
	ps += "Clear-Host\n"
	# 字符画：三档亮度叠印 → 视觉上的淡入
	ps += "$art = @'\n" + "\n".join(art) + "\n'@ -split \"`n\"\n"
	ps += "$top=[Console]::CursorTop\n"
	ps += "foreach($lv in @('DarkGray','Gray','White')){" \
		+ "[Console]::SetCursorPosition(0,$top);" \
		+ "foreach($l in $art){ Write-Host $l -ForegroundColor $lv };" \
		+ "if(Fast){break}; Start-Sleep -Milliseconds 220}\n"
	ps += "[Console]::SetCursorPosition(0,$top)\n"
	ps += "foreach($l in $art){ Write-Host $l -ForegroundColor White }\n"
	ps += "Wait %d\n" % ART_HOLD_MS
	ps += "New-Item -ItemType File -Path $Sentinel -Force | Out-Null\n"
	ps += "Start-Sleep -Milliseconds 100\n"
	ps += "exit\n"
	return ps


## 单引号字符串转义（宿主里 '' 表示一个单引号）
func _esc(s: String) -> String:
	return s.replace("'", "''")
