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
## 字符画行数。为什么不是 50：终端网格铺满**整块屏幕**（约 56 行），而 Godot 画布是 16:9，
## 在 16:10 屏上上下各 80px 信箱黑边，画布只装得下约 50 行。50 行时字符画正好占满画布，
## 下面那行字幕会掉进黑边里被裁掉。44 行留出余量，两边都放得下。
const ART_ROWS := 44
const ART_MAX_COLS := 120       ## 宽度上限（终端约 179 列，留足留白）
## 终端字符格「高:宽」——实测 14.3 x 28.1 px。横向比例必须按它算，否则人物被拉成鸡蛋。
const CELL_ASPECT := 1.965
const HOLD_MS := 1000           ## 代码打完停留（主人指定 1 秒）
## 乱码 → 归一：各帧的「归位比例」，1.0 那一帧由成品自己承担（见 _compose）
const CHAOS_KEEP := [0.0, 0.20, 0.42, 0.65, 0.85]
const CHAOS_STEP_MS := 170      ## 每帧停留（宿主逐行回写，比这更快也看不出来）
const ART_HOLD_MS := 1600       ## 归一完成后停留，然后窗口自关、交给 Godot
const TIMEOUT := 45.0

var _on_done := Callable()
var _done := false
var _t := 0.0

## 最近一次写进终端的字符画。Godot 侧要 1:1 复刻同一份，**不能重算**——
## AsciiArt.build 要扫百万像素，重算一次等于在衔接点上卡一秒。
static var last_art: PackedStringArray = PackedStringArray()


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
	last_art = art

	var script := _compose(ai_name, IntroScript.code_for(ai_id, ai_name), art)
	var f := FileAccess.open(script_abs, FileAccess.WRITE)
	if f == null:
		push_warning("[ExtTerminal] 脚本写不进去：%s" % script_abs)
		return false
	# 必须写 UTF-8 BOM：PS 5.1 读**无 BOM** 的脚本按系统 ANSI 解码，
	# 代码里的中文注释会整片变成乱码。
	f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
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
## [param code] 的节奏全在脚本里自校准（见下方打字段），这里只传文案与字符画。
func _compose(ai_name: String, code: PackedStringArray, art: PackedStringArray) -> String:
	# 乱码帧：同一批符号、位置先乱后齐。最后一帧不在这里，用成品 $art 本身收尾。
	var chaos: Array = []
	for k in CHAOS_KEEP.size():
		chaos.append(AsciiArt.scramble(art, float(CHAOS_KEEP[k]), 9001 + k * 131))
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
	# 等待：Ctrl 可提前结束
	ps += "function Wait([int]$ms){$t=0;while($t -lt $ms){if(Fast){return};" \
		+ "Start-Sleep -Milliseconds 40;$t+=40}}\n"
	for l in IntroScript.boot_lines(ai_name):
		ps += "Write-Host '%s' -ForegroundColor DarkGreen\n" % _esc(l)
		ps += "Wait 120\n"
	ps += "Wait 150\n"
	ps += "$code = @'\n" + "\n".join(code) + "\n'@ -split \"`n\" | ForEach-Object { $_.TrimEnd(\"`r\") }\n"
	# 打字节奏 = **绝对时间表**，不是「每块 sleep 固定毫秒」。
	# 为什么：Windows 定时器粒度不稳，实测 sleep(16) 在这台机器上实际要 30ms，
	# 按毫秒硬算总时长会超一倍。这里先量一次粒度（$unit），再按 $n*$unit 的时间表推进，
	# 漂移不累积——实测 141 拍预计 2333ms、实测 2348ms。
	# 每拍吐多少字由总字数摊：$ticks = 目标时长/$unit，$chunk = 字数/$ticks。
	# 所以文案加长不会变慢，只会滚得更快。
	ps += "$tp=[System.Diagnostics.Stopwatch]::StartNew();Start-Sleep -Milliseconds 1;$tp.Stop()\n"
	ps += "$unit=[Math]::Max(2.0,$tp.Elapsed.TotalMilliseconds)\n"
	ps += "$chars=0;foreach($l in $code){$chars+=$l.Length}\n"
	ps += "$ticks=[Math]::Max(1,[int][Math]::Floor(%d/$unit))\n" % GameSettings.type_total_ms()
	ps += "$chunk=[Math]::Max(1,[int][Math]::Ceiling($chars/[double]$ticks))\n"
	ps += "$cs=[System.Diagnostics.Stopwatch]::StartNew();$n=0\n"
	ps += "foreach($l in $code){" \
		+ "if($l.Length -gt 0){" \
		+ "for($p=0;$p -lt $l.Length;$p+=$chunk){" \
		+ "[Console]::Write($l.Substring($p,[Math]::Min($chunk,$l.Length-$p)));" \
		+ "$n++;$goal=$n*$unit;" \
		+ "while($cs.Elapsed.TotalMilliseconds -lt $goal){if(Fast){break};" \
		+ "Start-Sleep -Milliseconds 1}}}" \
		+ "[Console]::Write(\"`r`n\")}\n"
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
	# 乱码帧：同一批符号、位置先乱后齐（见 AsciiArt.scramble）。最后一帧就是 $art 本身。
	for i in chaos.size():
		ps += "$c%d = @'\n%s\n'@ -split \"`n\" | ForEach-Object { $_.TrimEnd(\"`r\") }\n" \
			% [i, "\n".join(chaos[i])]
	ps += "$wmax=0; foreach($l in $art){ if($l.Length -gt $wmax){$wmax=$l.Length} }\n"
	ps += "$padx=[Math]::Max(0,[int](($cwv - $wmax)/2))\n"
	ps += "$pady=[Math]::Max(0,[int](($chv - $art.Count)/2))\n"
	# 铁律①②：横向绝不越界（越界会折行→多占一行→滚动→整幅错位）
	ps += "if($padx -gt 0 -and ($padx + $wmax) -ge $cwv){ $padx=0 }\n"
	# 比原来多留 2 行：字符画下面还要放一行字幕
	ps += "$maxpady=$chv - $art.Count - 3; if($maxpady -lt 0){$maxpady=0}\n"
	ps += "if($pady -gt $maxpady){ $pady=$maxpady }\n"
	# 字幕行：紧跟字符画下方空一行，水平居中于字符画
	ps += "$capx=$padx+[Math]::Max(0,[int](($wmax-%d)/2));$capy=$pady+$art.Count+1\n" \
		% IntroScript.caption_cells()
	# 把排版写回给 Godot：立绘/字幕要落在**和字符画完全同一套格子里**。
	# 三处刻意选择，都是踩出来的：
	#   · 单条插值字符串，**不要**写 @('k='+$a,'k2='+$b) —— 宿主会解析成
	#     'k=' + ($a,'k2=') + $b，数组被 $OFS（空格）拼成一个串，分隔符全丢
	#   · 逗号分隔、单行写出 —— 不依赖换行（宿主对换行的处理不保证）
	#   · Ascii 编码 —— 宿主 PS 5.1 的 UTF8 会加 BOM，第一行的键会变成 "\ufeffcols"
	ps += "$geo=\"cols=$cwv,rows=$chv,padx=$padx,pady=$pady," \
		+ "artw=$wmax,arth=$($art.Count),capx=$capx,capy=$capy\"\n"
	ps += "try{ $geo | Set-Content -NoNewline " \
		+ "-Path (Join-Path $env:TEMP 'arena_term_geom.txt') -Encoding Ascii }catch{}\n"
	ps += "$sp=' ' * $padx\n"
	ps += "for($i=0;$i -lt $pady;$i++){ Write-Host '' }\n"
	ps += "$top=-1; try{$top=[Console]::CursorTop}catch{}\n"
	# 铁律③：叠印靠 SetCursorPosition 回写同一块区域，回不去就会「打多份并滚动」。
	# 探测方法：**先移到 $top+1，再移回 $top**——否则「光标本来就在 $top」会让探测假通过。
	ps += "$canfade=$false\n"
	ps += "if($top -ge 0 -and $wmax -lt $cwv -and ($capy) -le ($chv - 1)){try{" \
		+ "[Console]::SetCursorPosition(0,$top+1);$a=([Console]::CursorTop -eq ($top+1));" \
		+ "[Console]::SetCursorPosition(0,$top);$b=([Console]::CursorTop -eq $top);" \
		+ "$canfade=($a -and $b)}catch{$canfade=$false}}\n"
	# 字幕先落一次：它不在字符画的回写区域里（在下面一行），之后重绘碰不到它
	ps += "if($canfade){try{[Console]::SetCursorPosition($capx,$capy);" \
		+ "Write-Host '%s' -ForegroundColor DarkGray}catch{}}\n" % IntroScript.CAPTION
	# 乱码 → 归一：逐帧回写同一块区域，越往后越亮。最后一帧是成品。
	ps += "$frames=@(%s)\n" % ",".join(_frame_names(chaos.size()))
	# 每行 PadRight 到 $wmax 再打：**回写必须整块覆盖**。
	# 不补齐的话，上一帧撒在右侧的符号、下一帧对应位置是空的 -> 只覆盖有字的位置，
	# 空出来的格子就残留在屏幕上（实测成品右侧挂着一串乱码）。
	ps += "if($canfade){$ci=0; foreach($fr in $frames){" \
		+ "[Console]::SetCursorPosition(0,$top);" \
		+ "$col='DarkGray'; if($ci -ge 2){$col='Gray'};" \
		+ "foreach($l in $fr){ Write-Host ($sp+$l.PadRight($wmax)) -ForegroundColor $col };" \
		+ "if(Fast){break}; Start-Sleep -Milliseconds %d; $ci++}}\n" % CHAOS_STEP_MS
	ps += "if($canfade){[Console]::SetCursorPosition(0,$top)}\n"
	ps += "foreach($l in $art){ Write-Host ($sp+$l.PadRight($wmax)) -ForegroundColor White }\n"
	# 落定后把字幕提亮
	# 落定后把字幕提亮（注意：GDScript 里 % 的优先级高于 +，必须先拼好再用，否则只格式化最后一段）
	var cap_white := "Write-Host '%s' -ForegroundColor White" % IntroScript.CAPTION
	ps += ("if($canfade){try{[Console]::SetCursorPosition($capx,$capy);%s}catch{}} else {" % cap_white) \
		+ ("Write-Host ''; %s }\n" % cap_white)
	ps += "Wait %d\n" % ART_HOLD_MS
	ps += "New-Item -ItemType File -Path $Sentinel -Force | Out-Null\n"
	ps += "Start-Sleep -Milliseconds 100\n"
	ps += "exit\n"
	return ps


## 乱码帧的变量名序列（$c0,$c1,…），拼进宿主脚本的 $frames 数组
func _frame_names(n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in n:
		out.append("$c%d" % i)
	return out


## 单引号字符串转义（宿主里 '' 表示一个单引号）
func _esc(s: String) -> String:
	return s.replace("'", "''")
