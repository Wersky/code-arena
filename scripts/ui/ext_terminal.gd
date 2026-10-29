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
const ANSI_COLS := 96          ## 真彩渲染的横向格数（96 格 ≈ 192 像素宽）
const ART_ROWS := 52            ## 终端里画多少行（行数决定大小；34 行约占屏幕高度六成）
const ART_MAX_COLS := 200
## 终端字体格子「高:宽」比例档位：运行时按实测挑最接近的一套，避免人像被横挤成竖条
const ASPECTS := [3.0]       ## 列数留余量：超过窗口宽会折行，字符画会被拆坏
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

	# 导出包里的 res:// 是打包资源，外部终端读不到 → 先落一张临时 PNG
	var img_path := OS.get_temp_dir().path_join("arena_term_img.png")
	if art_tex != null:
		var im := art_tex.get_image()
		if im != null:
			im.save_png(img_path)
	# 预渲染 ANSI 真彩文本（两档亮度做淡入）
	_emit_ansi(art_tex, OS.get_temp_dir().path_join("arena_term_ansi.txt"), 1.0)
	_emit_ansi(art_tex, OS.get_temp_dir().path_join("arena_term_ansi_dim.txt"), 0.45)
	var variants: Array = []
	for a in ASPECTS:
		variants.append(AsciiArt.build(art_tex, ART_ROWS, ART_MAX_COLS, float(a)))
	var code := IntroScript.code_for(ai_id, ai_name)
	var script := _compose(ai_name, code, variants, img_path)

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


## 像素图 → ANSI 真彩半块文本（一个字符格 = 上下 2 像素）
## 为什么在游戏里算：终端侧跑 System.Drawing / 采样容易受环境影响（安全策略、宿主差异），
## 算好之后终端只需原样打印，几乎是零失败率。
func _emit_ansi(tex: Texture2D, path: String, brightness: float) -> void:
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return
	var cols := ANSI_COLS
	var rows := maxi(2, int(round(float(cols) * float(h) / float(w) / 2.0)))
	var lines := PackedStringArray()
	for r in rows:
		var sb := ""
		var y0 := int(float(r * 2) / float(rows * 2) * h)
		var y1 := int(float(r * 2 + 1) / float(rows * 2) * h)
		for c in cols:
			var x := int(float(c) / float(cols) * w)
			var p0 := img.get_pixel(x, y0)
			var p1 := img.get_pixel(x, clampi(y1, 0, h - 1))
			if p0.a < 0.35 and p1.a < 0.35:
				sb += " "
				continue
			sb += "\u001b[38;2;%d;%d;%dm\u001b[48;2;%d;%d;%dm▀" % [
				int(p0.r * 255.0 * brightness), int(p0.g * 255.0 * brightness),
				int(p0.b * 255.0 * brightness), int(p1.r * 255.0 * brightness),
				int(p1.g * 255.0 * brightness), int(p1.b * 255.0 * brightness)]
		lines.append(sb + "\u001b[0m")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("\n".join(lines))
	f.close()


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
func _compose(ai_name: String, code: PackedStringArray, art_variants: Array,
		img_path: String = "") -> String:
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
	# ── 尺寸：居中与采样都靠它（宿主可能把像素当字符数返回，做合法性钳制）──
	ps += "$cwv=0;$chv=0\n"
	ps += "try{$cwv=[Console]::WindowWidth}catch{}\n"
	ps += "try{$chv=[Console]::WindowHeight}catch{}\n"
	ps += "if($cwv -lt 20 -or $cwv -gt 400){try{$cwv=$Host.UI.RawUI.WindowSize.Width}catch{}}\n"
	ps += "if($chv -lt 10 -or $chv -gt 200){try{$chv=$Host.UI.RawUI.WindowSize.Height}catch{}}\n"
	ps += "if($cwv -lt 20 -or $cwv -gt 400){$cwv=160}\n"
	ps += "if($chv -lt 10 -or $chv -gt 200){$chv=50}\n"
	ps += "try{ 'cols={0} rows={1}' -f $cwv,$chv | " \
		+ "Set-Content -Path (Join-Path $env:TEMP 'arena_term_debug.txt') -Encoding UTF8 }catch{}\n"
	# ── 主路径：真彩半块渲染 —— 一个字符格 = 上下 2 个像素（▀ + 24 位色）──
	# 这样终端里显示的就是**原图本身**，精度只受窗口字符网格限制，不再受 ASCII 梯度拖累。
	# ── 主路径：打印游戏侧预渲染好的 ANSI 真彩文本（终端只负责原样输出）──
	# 之前让终端自己读图渲染，会受安全策略 / 宿主差异影响（白屏就是那次失败）。
	ps += "$fOn=Join-Path $env:TEMP 'arena_term_ansi.txt'\n"
	ps += "$fDim=Join-Path $env:TEMP 'arena_term_ansi_dim.txt'\n"
	ps += "if(Test-Path $fOn){\n"
	ps += "$artOn=@(Get-Content -Path $fOn -Encoding UTF8)\n"
	ps += "$artDim=@(Get-Content -Path $fDim -Encoding UTF8)\n"
	ps += "$padx=[Math]::Max(0,[int](($cwv-%d)/2))\n" % ANSI_COLS
	ps += "$pady=[Math]::Max(0,[int](($chv-$artOn.Count)/2))\n"
	ps += "$sp=' '*$padx\n"
	ps += "for($i=0;$i -lt $pady;$i++){ Write-Host '' }\n"
	ps += "$top=[Console]::CursorTop\n"
	ps += "foreach($set in @($artDim,$artOn)){\n"
	ps += "[Console]::SetCursorPosition(0,$top)\n"
	ps += "foreach($l in $set){ [Console]::Write($sp); [Console]::Write($l); [Console]::Write([Environment]::NewLine) }\n"
	ps += "if(Fast){break}\n"
	ps += "Start-Sleep -Milliseconds 260\n"
	ps += "}\n"
	ps += "} else {\n"
	ps += "} else {\n"
	# ── 兜底：System.Drawing 不可用时退回 ASCII 字符画（按格子比例选套）──
	# 为什么：终端字体格子不一定是 1:2，实测某些机器是 1:3.5，硬用 1:2 会把人横着挤成竖条。
	for i in art_variants.size():
		ps += "$art%d = @'\n%s\n'@ -split \"`n\"\n" % [i, "\n".join(art_variants[i])]
	ps += "$ratios=@(%s)\n" % ", ".join(ASPECTS.map(func(f): return "%.2f" % f))
	ps += "$ratio=0.0\n"
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
	ps += "$wmax=0; foreach($l in $art){ if($l.Length -gt $wmax){$wmax=$l.Length} }\n"
	ps += "$padx=[Math]::Max(0,[int](($cwv - $wmax)/2))\n"
	ps += "$pady=[Math]::Max(0,[int](($chv - $art.Count)/2))\n"
	ps += "for($i=0;$i -lt $pady;$i++){ Write-Host '' }\n"
	ps += "$sp=' ' * $padx\n"
	ps += "$top=[Console]::CursorTop\n"
	ps += "foreach($lv in @('DarkGray','Gray','White')){" \
		+ "[Console]::SetCursorPosition(0,$top);" \
		+ "foreach($l in $art){ Write-Host ($sp+$l) -ForegroundColor $lv };" \
		+ "if(Fast){break}; Start-Sleep -Milliseconds 220}\n"
	ps += "[Console]::SetCursorPosition(0,$top)\n"
	ps += "foreach($l in $art){ Write-Host ($sp+$l) -ForegroundColor White }\n"
	ps += "}\n"
	ps += "Wait %d\n" % ART_HOLD_MS
	ps += "New-Item -ItemType File -Path $Sentinel -Force | Out-Null\n"
	ps += "Start-Sleep -Milliseconds 100\n"
	ps += "exit\n"
	return ps


## 单引号字符串转义（宿主里 '' 表示一个单引号）
func _esc(s: String) -> String:
	return s.replace("'", "''")
