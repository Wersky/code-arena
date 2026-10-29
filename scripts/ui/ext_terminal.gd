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
const ART_ROWS := 46            ## 终端里画多少行（行数决定大小；34 行约占屏幕高度六成）
const ART_MAX_COLS := 180
## 终端字体格子「高:宽」比例档位：运行时按实测挑最接近的一套，避免人像被横挤成竖条
const ASPECTS := [1.8, 2.4, 3.0]       ## 列数留余量：超过窗口宽会折行，字符画会被拆坏
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

	var variants: Array = []
	for a in ASPECTS:
		variants.append(AsciiArt.build(art_tex, ART_ROWS, ART_MAX_COLS, float(a)))
	var code := IntroScript.code_for(ai_id, ai_name)
	var script := _compose(ai_name, code, variants)

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
func _compose(ai_name: String, code: PackedStringArray, art_variants: Array) -> String:
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
		+ "[DllImport(\"kernel32.dll\")] public static extern bool SetConsoleDisplayMode(IntPtr h,uint f,IntPtr d);" \
		+ "[DllImport(\"kernel32.dll\")] public static extern IntPtr GetConsoleWindow();" \
		+ "[DllImport(\"user32.dll\")] public static extern bool GetClientRect(IntPtr h,IntPtr r);" \
		+ "[DllImport(\"user32.dll\",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string c,string t);'\n"
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
	# ── 字符画：按终端字体格子比例预生成多套，运行时量出来挑最接近的 ──
	# 为什么：终端字体格子不一定是 1:2，实测某些机器是 1:3.5，硬用 1:2 会把人横着挤成竖条。
	for i in art_variants.size():
		ps += "$art%d = @'\n%s\n'@ -split \"`n\"\n" % [i, "\n".join(art_variants[i])]
	ps += "$ratios=@(%s)\n" % ", ".join(ASPECTS.map(func(f): return "%.2f" % f))
	# 量客户区像素 / 字符数 = 真实格子比例；窗口字符宽高要稳（[Console] 在 wt 里可能取不到）
	ps += "$ratio=0.0\n"
	ps += "$cwv=0;$chv=0\n"
	ps += "try{$cwv=[Console]::WindowWidth}catch{}\n"
	ps += "try{$chv=[Console]::WindowHeight}catch{}\n"
	ps += "if($cwv -lt 10 -or $cwv -gt 400){try{$cwv=$Host.UI.RawUI.WindowSize.Width}catch{}}\n"
	ps += "if($chv -lt 5 -or $chv -gt 200){try{$chv=$Host.UI.RawUI.WindowSize.Height}catch{}}\n"
	# 有些宿主把「像素」当字符数返回（实测 2544x97）→ 超出合理范围就退回常见值，
	# 否则 padx 会被算成上千个空格、字符画被推到一边
	ps += "if($cwv -lt 20 -or $cwv -gt 400){$cwv=160}\n"
	ps += "if($chv -lt 10 -or $chv -gt 200){$chv=50}\n"
	ps += "try{$buf=[Runtime.InteropServices.Marshal]::AllocHGlobal(16);" \
		+ "$hc=[W]::FindWindowW($null,$title); if($hc -eq [IntPtr]::Zero){$hc=[W]::GetConsoleWindow()};" \
		+ "$W::GetClientRect($hc,$buf)|Out-Null;" \
		+ "$pw=[Runtime.InteropServices.Marshal]::ReadInt32($buf,8)-[Runtime.InteropServices.Marshal]::ReadInt32($buf,0);" \
		+ "$ph=[Runtime.InteropServices.Marshal]::ReadInt32($buf,12)-[Runtime.InteropServices.Marshal]::ReadInt32($buf,4);" \
		+ "if($pw -gt 0 -and $ph -gt 0){$ratio=($ph/$chv)/($pw/$cwv)}}catch{}\n"
	ps += "$best=($ratios.Count-1)\n" \
		+ "if($ratio -gt 0){ $bd=99; for($i=0;$i -lt $ratios.Count;$i++){" \
		+ "$dd=[Math]::Abs($ratios[$i]-$ratio); if($dd -lt $bd){$bd=$dd;$best=$i}} }\n"
	ps += "$all=@($art0"
	for i in range(1, art_variants.size()):
		ps += ",$art%d" % i
	ps += ")\n"
	ps += "$art=@($all[$best])\n"
	# 双轴居中：水平按最长行补空格，垂直按窗口高度补空行
	ps += "$wmax=0; foreach($l in $art){ if($l.Length -gt $wmax){$wmax=$l.Length} }\n"
	ps += "$padx=[Math]::Max(0,[int](($cwv - $wmax)/2))\n"
	ps += "$pady=[Math]::Max(0,[int](($chv - $art.Count)/2))\n"
	# 调试落盘：便于核对实际取到的尺寸（不进游戏界面）
	ps += "try{ 'ratio={0:N2} best={1} cols={2} rows={3} padx={4} pady={5} art={6} wmax={7}' -f " \
		+ "$ratio,$best,$cwv,$chv,$padx,$pady,$art.Count,$wmax | " \
		+ "Set-Content -Path (Join-Path $env:TEMP 'arena_term_debug.txt') -Encoding UTF8 }catch{}\n"
	ps += "for($i=0;$i -lt $pady;$i++){ Write-Host '' }\n"
	ps += "$sp=' ' * $padx\n"
	ps += "$top=[Console]::CursorTop\n"
	# 三档亮度叠印 = 淡入；每遍都带水平缩进
	ps += "foreach($lv in @('DarkGray','Gray','White')){" \
		+ "[Console]::SetCursorPosition(0,$top);" \
		+ "foreach($l in $art){ Write-Host ($sp+$l) -ForegroundColor $lv };" \
		+ "if(Fast){break}; Start-Sleep -Milliseconds 220}\n"
	ps += "[Console]::SetCursorPosition(0,$top)\n"
	ps += "foreach($l in $art){ Write-Host ($sp+$l) -ForegroundColor White }\n"
	ps += "Wait %d\n" % ART_HOLD_MS
	ps += "New-Item -ItemType File -Path $Sentinel -Force | Out-Null\n"
	ps += "Start-Sleep -Milliseconds 100\n"
	ps += "exit\n"
	return ps


## 单引号字符串转义（宿主里 '' 表示一个单引号）
func _esc(s: String) -> String:
	return s.replace("'", "''")
