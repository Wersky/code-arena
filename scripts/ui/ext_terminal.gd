class_name ExtTerminal
extends Node
## 真实系统终端进场（Windows）：真的弹出一个**最大化**的终端窗口跑整套演出。
##
## 流程：生成脚本 → 打开终端 → 开机行 → 逐块敲角色代码（速度取自开始界面）
##   → 停 1 秒 → 清屏 → ASCII 符号画**三档亮度叠印淡入** → 停留 2 秒 → 窗口自关 + 写哨兵
##   → 游戏侧黑幕淡出、手牌弹入（见 arena._play_intro）。
## 任意时刻按 **Ctrl** 快进（全局轮询 VK_CONTROL，不要求终端有焦点）。
##
## 排版三条铁律（都踩过坑）：
##  ① 画必须**明显小于**窗口（行数留 6 行以上余量），否则一次换行就滚动、叠印错位。
##  ② padx/pady 一律钳制到不会触发行/列溢出的范围。
##  ③ 叠印淡入前先验证起始行，不安全就直接单次打印，绝不让画面消失。

signal finished

## 脚本与哨兵放系统临时目录：路径无空格无中文，Windows Terminal 传参才不会被拆错
const SCRIPT_NAME := "arena_term_intro.ps1"
const SENTINEL_NAME := "arena_term_intro.done"
## 终端把自己「把字符画摆在哪」写回这个文件，Godot 侧据此把立绘放进同一个矩形。
## 这是位置严格对齐的唯一依据——两边各算各的必然有偏差（画布 16:9 vs 屏幕 16:10）。
const GEOM_NAME := "arena_term_geom.txt"
const ART_ROWS := 50            ## 字符画行数（终端约 54 行 → 占屏高约 93%，上下仍各留 2 行余量）
const ART_MAX_COLS := 120       ## 宽度上限（终端约 179 列，留足留白）
## 终端字符格「高:宽」——实测 14.3 x 28.1 px。横向比例必须按它算，否则人物被拉成鸡蛋。
const CELL_ASPECT := 1.965
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
	for p in [sentinel, _geom_path()]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

	var art := AsciiArt.build(art_tex, ART_ROWS, ART_MAX_COLS, CELL_ASPECT)
	if art.is_empty():
		push_warning("[ExtTerminal] 字符画生成失败，跳过终端")
		return false

	var script := _compose(ai_name, IntroScript.code_for(ai_id, ai_name), art)
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


func _geom_path() -> String:
	return OS.get_temp_dir().path_join(GEOM_NAME)


## 清掉上一次的排版。走游戏内兜底终端时没人为它写新值，
## 不清就会读到上次外部终端留下的矩形，立绘位置会错。
static func clear_geometry() -> void:
	var path := OS.get_temp_dir().path_join(GEOM_NAME)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 读回终端画字符画的排版（全整数，避开本地化小数点：某些区域设置会写 "0,24"）。
## 返回空字典 = 这次没走外部终端（比如退了游戏内兜底版），调用方按居中兜底。
static func read_geometry() -> Dictionary:
	var path := OS.get_temp_dir().path_join(GEOM_NAME)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var out: Dictionary = {}
	# 逗号和换行都当分隔符：写的是单行逗号分隔，但换行也认（手工调试改过文件时更稳）
	var text := f.get_as_text().replace("\r", "").replace("\n", ",")
	f.close()
	for kv in text.split(",", false):
		var pair := kv.split("=")
		if pair.size() == 2:
			var key := pair[0].strip_edges()
			var val := pair[1].strip_edges()
			if val.is_valid_int():
				out[key] = int(val)
	for k in ["cols", "rows", "padx", "pady", "artw", "arth"]:
		if int(out.get(k, 0)) <= 0:
			return {}
	return out


## 启动终端：
##   ① 有 Windows Terminal → 用它的 `-M`（最大化）开一个**铺满屏幕的窗口**。
##      注意别用 `-F`（那是真全屏，主人要的是「窗口铺满」而不是全屏）。
##      wt 的窗口也不响应 ShowWindow/SetConsoleDisplayMode，只能靠它自己的参数。
##   ② 没有 wt → conhost.exe + ShowWindow(SW_MAXIMIZE) 最大化。
func _launch(script_abs: String, sentinel: String) -> int:
	var wt := _find_wt()
	if wt != "":
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
	ps += "$title='arena_os :: %s'\n" % _esc(ai_name)
	ps += "$Host.UI.RawUI.WindowTitle=$title\n"
	# Win32 签名：全局 Ctrl 轮询 + 经典控制台最大化
	ps += "$sig='[DllImport(\"user32.dll\")] public static extern short GetAsyncKeyState(int v);" \
		+ "[DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr h,int n);'\n"
	ps += "$W = Add-Type -MemberDefinition $sig -Name 'W' -PassThru\n"
	ps += "function Fast(){ return (($W::GetAsyncKeyState(0x11) -band 0x8000) -ne 0) }\n"
	# 窗口铺满屏幕（不是全屏）：
	#   · Windows Terminal 里（WT_SESSION 存在）→ 已由启动参数 wt -M 最大化，这里不做任何事
	#   · 经典 conhost → ShowWindow(SW_MAXIMIZE) 最大化窗口
	ps += "if(-not $env:WT_SESSION){try{$h=(Get-Process -Id $PID).MainWindowHandle;" \
		+ "if($h -ne 0){$W::ShowWindow($h,3)|Out-Null}}catch{} }\n"
	# conhost 下把缓冲区/窗口拉到物理上限，字符画才吃满屏（wt 里改了无效，跳过）
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
	ps += "$code = @'\n" + "\n".join(code) + "\n'@ -split \"`n\" | ForEach-Object { $_.TrimEnd(\"`r\") }\n"
	# 代码全部走同一个输出通道（[Console]::Write + 显式 "`r`n"）。
	# 别混用 Write-Host：两条通道的写入顺序不保证，会出现两行粘一起。
	ps += "foreach($l in $code){ if($l.Length -gt 0){ T $l %d %d }; [Console]::Write(\"`r`n\") }\n" % [chunk, delay]
	ps += "Wait %d\n" % HOLD_MS
	ps += "Clear-Host\n"

	# ── 尺寸：居中用（宿主可能把像素当字符数返回，做合法性钳制）──
	ps += "$cwv=0;$chv=0\n"
	ps += "try{$cwv=[Console]::WindowWidth}catch{}\n"
	ps += "try{$chv=[Console]::WindowHeight}catch{}\n"
	ps += "if($cwv -lt 20 -or $cwv -gt 400){try{$cwv=$Host.UI.RawUI.WindowSize.Width}catch{}}\n"
	ps += "if($chv -lt 10 -or $chv -gt 200){try{$chv=$Host.UI.RawUI.WindowSize.Height}catch{}}\n"
	ps += "if($cwv -lt 20 -or $cwv -gt 400){$cwv=160}\n"
	ps += "if($chv -lt 10 -or $chv -gt 200){$chv=50}\n"

	# TrimEnd("`r")：宿主偶尔按 CRLF 读回 here-string，每行尾部会多一个 \r，
	# 既让宽度多算 1 列，也会把光标顶回行首导致错位
	ps += "$art = @'\n%s\n'@ -split \"`n\" | ForEach-Object { $_.TrimEnd(\"`r\") }\n" % "\n".join(art)
	ps += "$wmax=0; foreach($l in $art){ if($l.Length -gt $wmax){$wmax=$l.Length} }\n"
	ps += "$padx=[Math]::Max(0,[int](($cwv - $wmax)/2))\n"
	ps += "$pady=[Math]::Max(0,[int](($chv - $art.Count)/2))\n"
	# 铁律①②：横向绝不越界（越界会折行→多占一行→滚动→整幅错位）
	ps += "if($padx -gt 0 -and ($padx + $wmax) -ge $cwv){ $padx=0 }\n"
	ps += "$maxpady=$chv - $art.Count - 2; if($maxpady -lt 0){$maxpady=0}\n"
	ps += "if($pady -gt $maxpady){ $pady=$maxpady }\n"
	# 把排版写回给 Godot：立绘要落在**和字符画完全同一个矩形**里。
	# 三处刻意选择，都是踩出来的：
	#   · 单条插值字符串，**不要**写 @('k='+$a,'k2='+$b) —— PowerShell 会解析成
	#     'k=' + ($a,'k2=') + $b，数组被 $OFS（空格）拼成一个串，分隔符全丢
	#   · 逗号分隔、单行写出 —— 不依赖换行（宿主对换行的处理不保证）
	#   · Ascii 编码 —— PS 5.1 的 UTF8 会加 BOM，第一行的键会变成 "\ufeffcols"
	ps += "$geo=\"cols=$cwv,rows=$chv,padx=$padx,pady=$pady," \
		+ "artw=$wmax,arth=$($art.Count)\"\n"
	ps += "try{ $geo | Set-Content -NoNewline " \
		+ "-Path (Join-Path $env:TEMP 'arena_term_geom.txt') -Encoding Ascii }catch{}\n"
	ps += "$sp=' ' * $padx\n"
	ps += "for($i=0;$i -lt $pady;$i++){ Write-Host '' }\n"
	ps += "$top=-1; try{$top=[Console]::CursorTop}catch{}\n"
	# 铁律③：叠印靠 SetCursorPosition 回写同一块区域，回不去就会「打三份并滚动」。
	# 探测方法：**先移到 $top+1，再移回 $top**——否则「光标本来就在 $top」会让探测假通过。
	ps += "$canfade=$false\n"
	ps += "if($top -ge 0 -and $wmax -lt $cwv -and ($top + $art.Count) -le ($chv - 1)){try{" \
		+ "[Console]::SetCursorPosition(0,$top+1);$a=([Console]::CursorTop -eq ($top+1));" \
		+ "[Console]::SetCursorPosition(0,$top);$b=([Console]::CursorTop -eq $top);" \
		+ "$canfade=($a -and $b)}catch{$canfade=$false}}\n"
	ps += "if($canfade){" \
		+ "foreach($lv in @('DarkGray','Gray','White')){" \
		+ "[Console]::SetCursorPosition(0,$top);" \
		+ "foreach($l in $art){ Write-Host ($sp+$l) -ForegroundColor $lv };" \
		+ "if(Fast){break}; Start-Sleep -Milliseconds 220}" \
		+ "} else {" \
		+ "foreach($l in $art){ Write-Host ($sp+$l) -ForegroundColor White }\n" \
		+ "}\n"
	ps += "Wait %d\n" % ART_HOLD_MS
	ps += "New-Item -ItemType File -Path $Sentinel -Force | Out-Null\n"
	ps += "Start-Sleep -Milliseconds 100\n"
	ps += "exit\n"
	return ps


## 单引号字符串转义（宿主里 '' 表示一个单引号）
func _esc(s: String) -> String:
	return s.replace("'", "''")
