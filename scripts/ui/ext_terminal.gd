class_name ExtTerminal
extends Node
## 真实系统终端进场（Windows）：真的弹出一个**最大化**的终端窗口跑整套演出。
##
## 流程：生成脚本 → cmd 的 start 打开终端 → 开机行 → 逐块敲角色代码（速度取自开始界面）
##   → 停 1 秒 → 清屏 → ASCII 胸像**三档亮度叠印淡入** → 停留 2 秒 → 窗口自关 + 写哨兵
##   → 游戏侧黑幕淡出、手牌弹入（见 arena._play_intro）。
## 任意时刻按 **Ctrl** 快进（全局轮询 VK_CONTROL，不要求终端有焦点）。

signal finished

## 脚本与哨兵放系统临时目录：路径无空格无中文，Windows Terminal 传参才不会被拆错
const SCRIPT_NAME := "arena_term_intro.ps1"
const SENTINEL_NAME := "arena_term_intro.done"
const ART_ROWS := 46            ## 终端里画多少行（全屏后行数充足，行数决定 DeepSeek 的大小）
const ART_MAX_COLS := 120       ## 列数留余量：超过窗口宽会折行，字符画会被拆坏
const HOLD_MS := 1000           ## 代码打完停留（主人指定 1 秒）
const ART_HOLD_MS := 2000       ## 字符画停留 2 秒后融回游戏（主人指定）
const TIMEOUT := 45.0

var _on_done := Callable()
var _done := false
var _t := 0.0


func play(ai_id: String, ai_name: String, art_tex: Texture2D, on_done: Callable) -> bool:
	_on_done = on_done
	var script_abs := _script_path()
	var sentinel := _sentinel_path()
	if FileAccess.file_exists(sentinel):
		DirAccess.remove_absolute(sentinel)

	var art := AsciiArt.build(art_tex, ART_ROWS, ART_MAX_COLS)
	var code := IntroScript.code_for(ai_id, ai_name)
	var script := _compose(ai_name, code, art)

	var f := FileAccess.open(script_abs, FileAccess.WRITE)
	if f == null:
		push_warning("[ExtTerminal] 脚本写不进去：%s" % script_abs)
		return false
	f.store_string(script)
	f.close()

	var pid := _launch(script_abs, sentinel)
	if pid <= 0:
		push_warning("[ExtTerminal] 终端启动失败")
		return false
	set_process(true)
	return true


## 脚本/哨兵落在系统临时目录（无空格路径）
func _script_path() -> String:
	return OS.get_temp_dir().path_join(SCRIPT_NAME)


func _sentinel_path() -> String:
	return OS.get_temp_dir().path_join(SENTINEL_NAME)


## 启动终端：
##   ① 有 Windows Terminal → 用它的 `-M`（最大化）开一个**铺满屏幕的窗口**。
##      注意别用 `-F`（那是真全屏，主人要的是「窗口铺满」而不是全屏）。
##      wt 的窗口也不响应 ShowWindow/SetConsoleDisplayMode，只能靠它自己的参数。
##   ② 没有 wt → conhost.exe + ShowWindow(SW_MAXIMIZE) 最大化。
func _launch(script_abs: String, sentinel: String) -> int:
	var wt := _find_wt()
	if wt != "":
		# 主人偏好：默认「铺满屏幕」（-M 最大化窗口）；切成全屏才用 -F
		var mode_flag := "-F" if GameSettings.term_fullscreen else "-M"
		var ok_pid := OS.create_process(wt, [
			mode_flag, "-w", "-1", "--title", "arena_os", "powershell",
			"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_abs, sentinel])
		if ok_pid > 0:
			return ok_pid
		push_warning("[ExtTerminal] wt 启动失败，回退 conhost")
	return OS.create_process("conhost.exe", [
		"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_abs, sentinel])


## 找 Windows Terminal（商店版固定路径，不扫盘）
func _find_wt() -> String:
	var home := OS.get_environment("LOCALAPPDATA")
	if home != "":
		var p := home.path_join("Microsoft/WindowsApps/wt.exe")
		if FileAccess.file_exists(p):
			return p
	return ""


func _process(delta: float) -> void:
	_t += delta
	if FileAccess.file_exists(_sentinel_path()):
		DirAccess.remove_absolute(_sentinel_path())
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
	# 标题先行：找窗口句柄要用它兜底
	ps += "$title='arena_os :: %s'\n" % _esc(ai_name)
	ps += "$Host.UI.RawUI.WindowTitle=$title\n"
	# Win32 签名：全局 Ctrl 轮询 + 经典控制台全屏
	ps += "$sig='[DllImport(\"user32.dll\")] public static extern short GetAsyncKeyState(int v);" \
		+ "[DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr h,int n);" \
		+ "[DllImport(\"kernel32.dll\")] public static extern IntPtr GetStdHandle(int n);" \
		+ "[DllImport(\"kernel32.dll\")] public static extern bool SetConsoleDisplayMode(IntPtr h,uint f,IntPtr d);'\n"
	ps += "$W = Add-Type -MemberDefinition $sig -Name 'W' -PassThru\n"
	ps += "function Fast(){ return (($W::GetAsyncKeyState(0x11) -band 0x8000) -ne 0) }\n"
	# 窗口铺满屏幕（不是全屏）：
	#   · 在 Windows Terminal 里（WT_SESSION 存在）→ 已由启动参数 wt -M 最大化，这里不做任何事
	#     （wt 不响应 ShowWindow/SetConsoleDisplayMode，硬调会被它忽略甚至踢出最大化）
	#   · 经典 conhost → ShowWindow(SW_MAXIMIZE) 最大化窗口（**不**用 SetConsoleDisplayMode，那是真全屏）
	ps += "if(-not $env:WT_SESSION){" \
		+ "try{$h=(Get-Process -Id $PID).MainWindowHandle;" \
		+ "if($h -ne 0){$W::ShowWindow($h,3)|Out-Null}}catch{} }\n"
	# conhost 下再把缓冲区/窗口拉到物理上限，字符画才吃满屏（wt 里改了无效，跳过）
	ps += "if(-not $env:WT_SESSION){ try{$mp=$Host.UI.RawUI.MaxPhysicalWindowSize;" \
		+ "$b=$Host.UI.RawUI.BufferSize;$b.Width=[Math]::Max(120,$mp.Width);$b.Height=999;" \
		+ "$Host.UI.RawUI.BufferSize=$b;" \
		+ "$w=$Host.UI.RawUI.WindowSize;$w.Width=$mp.Width;$w.Height=$mp.Height;" \
		+ "$Host.UI.RawUI.WindowSize=$w}catch{} }\n"
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
