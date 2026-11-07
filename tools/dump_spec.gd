extends SceneTree
## 把 EffectSpec.to_dict() 落盘成 dsl_spec.json（交付物）。
##
## 运行：godot --headless --path <项目> --script res://tools/dump_spec.gd
##
## 用途：外部工具、AI 提示词生成、版本对比都读这份 JSON；
## 代码里的 EffectSpec 是唯一真相，JSON 是它的导出快照。
## 改规格表后必须重跑本脚本，否则两边的 version 会不一致（smoke 会断言）。

const OUT_PATH := "res://scripts/core/dsl_spec.json"


func _init() -> void:
	var data := EffectSpec.to_dict()
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		print("写入失败：%s" % OUT_PATH)
		quit(1)
		return
	f.store_string(JSON.stringify(data, "  ", false))
	f.close()
	print("wrote %s（version=%d, ops=%d, triggers=%d）" % [
		OUT_PATH, int(data["version"]),
		(EffectSpec.OPS as Dictionary).size(),
		(EffectSpec.TRIGGERS as Dictionary).size()])
	quit()
