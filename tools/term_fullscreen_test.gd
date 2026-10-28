extends SceneTree
## 实测工具：合成终端进场 ps1，末尾注入窗口矩形上报，跑完后由 bash 校验
## 窗口是否真的盖满整屏（强制全屏 2026-10-28 主人钦定）。
##
##   godot --headless --path . --script res://tools/term_fullscreen_test.gd

func _initialize() -> void:
	var t := ExtTerminal.new()
	root.add_child(t)
	var tex: Texture2D = load("res://assets/art/ai-deepdeek-sleep.png")
	var art := AsciiArt.build(tex, ExtTerminal.ART_ROWS, 150)
	var code := IntroScript.code_for("deepdeek", "DeepDeek")
	var ps := t._compose("DeepDeek", code, art)
	# 注入矩形上报：GetWindowRect 写临时文件（替掉最后的 exit 前执行）
	var dump := """
$e=''
try{ $src=@'
using System;using System.Runtime.InteropServices;
public class WR2{
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 public struct RECT{public int L;public int T;public int R;public int B;}
}
'@; Add-Type -TypeDefinition $src -ErrorAction Stop; $e+='A' }catch{ $e+='a['+$_.Exception.Message+']' }
try{ $r=New-Object 'WR2+RECT' -ErrorAction Stop; $e+='N' }catch{ $e+='n['+$_.Exception.Message+']' }
try{ [void][WR2]::GetWindowRect($h,[ref]$r); $e+='G' }catch{ $e+='g['+$_.Exception.Message+']' }
try{ "$e|h=$h|rect=$($r.L),$($r.T),$($r.R),$($r.B)" | Set-Content -Path ($Sentinel+'.rect') }catch{ 'E2' | Set-Content -Path ($Sentinel+'.rect') }
exit
"""
	ps = ps.replace("$h=[IntPtr]::Zero
", "'FS0' | Set-Content -Path ($Sentinel+'.fs0')
$h=[IntPtr]::Zero
")
	ps = ps.replace("{$h=$W::FindWindowW($null,$title)} }
", "{$h=$W::FindWindowW($null,$title)} }
'FS1='+$h | Set-Content -Path ($Sentinel+'.fs1')
")
	ps = ps.replace("$st=$st -band (-bnot 0x00CF0000);", "$st=$st -band (-bnot 0x00CF0000);
'FS2' | Set-Content -Path ($Sentinel+'.fs2')
")
	ps = ps.replace("$W::SetWindowLongW($h,-16,$st)|Out-Null;", "$W::SetWindowLongW($h,-16,$st)|Out-Null;
'FS3' | Set-Content -Path ($Sentinel+'.fs3')
")
	ps = ps.replace("0x0060)|Out-Null }}catch{}", "0x0060)|Out-Null;'FS4' | Set-Content -Path ($Sentinel+'.fs4') }}catch{ $_.Exception.Message | Set-Content -Path ($Sentinel+'.fserr') }")
	ps = ps.replace("exit\n", dump)
	var out := ProjectSettings.globalize_path("user://term_fs_test.ps1")
	var f := FileAccess.open("user://term_fs_test.ps1", FileAccess.WRITE)
	f.store_string(ps)
	f.close()
	print("[compose] %s（%d 字节）" % [out, ps.length()])
	quit()
