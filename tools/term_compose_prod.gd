extends SceneTree
## 用生产 ExtTerminal._compose 合成正式 term_intro.ps1（无任何测试注入），
## 供无头环境做同步运行验证（桌面锁定时开不了新窗口，但脚本语法/流程可验证）。
##
##   godot --headless --path . --script res://tools/term_compose_prod.gd

func _initialize() -> void:
	var t := ExtTerminal.new()
	root.add_child(t)
	var tex: Texture2D = load("res://assets/art/ai-deepdeek-sleep.png")
	var art := AsciiArt.build(tex, ExtTerminal.ART_ROWS, 150)
	var code := IntroScript.code_for("deepdeek", "DeepDeek")
	var ps := t._compose("DeepDeek", code, art)
	var f := FileAccess.open(ExtTerminal.SCRIPT_PATH, FileAccess.WRITE)
	f.store_string(ps)
	f.close()
	print("[compose] 生产 term_intro.ps1 已合成（%d 字节）" % ps.length())
	quit()
