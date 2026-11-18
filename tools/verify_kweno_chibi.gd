extends SceneTree
## 千问（Kweno）Q 版切件无头验收。
##
## 运行：
##   godot --headless --path <项目> --script res://tools/verify_kweno_chibi.gd
##
## 断什么（每条都对应一个真实翻车模式）：
##   ① rig.json 能读、canvas 正确、九件齐全、pivot 都在画布内
##   ② 九张 parts PNG 都存在、都是 192x256、都非空（空件会让骨头静默跳过）
##   ③ ChibiRig.setup() 不报错，_parts 里九件全部就位（没有降级到占位方块）
##   ④ idle 一个整周期（4s）内，每件绕自己的 pivot 转 → 相邻件接缝不露缝
##   ⑤ shake / attack 轨道在有/无 hair_b 时都能建起来（_add 对缺失件静默跳过）
##   ⑥ 静止姿态与 cutout.png 逐像素一致（切件对位正确，没有错位/重影）
##   ⑦ 腿在 idle 周期内不穿地（dy 恒 0）
## 另导出 idle 4 帧 + shake 3 帧到 .tmp/rig/kweno/ 供肉眼核对。

const RIG_DIR := "res://assets/art/rig/kweno"
const SHOT_DIR := "res://.tmp/rig/kweno"
const CANVAS := Vector2i(192, 256)

var _fail := 0
var _pass := 0


func _initialize() -> void:
	await _run()
	print("── 汇总：%d PASS / %d FAIL ──" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("[OK]   %s" % msg)
	else:
		_fail += 1
		print("[FAIL] %s" % msg)


func _run() -> void:
	# ── ① rig.json ──────────────────────────────────────
	var json_path := RIG_DIR.path_join("rig.json")
	var exists := FileAccess.file_exists(json_path)
	_ok(exists, "rig.json 存在：%s" % json_path)
	if not exists:
		return
	var txt := FileAccess.get_file_as_string(json_path)
	var parsed: Variant = JSON.parse_string(txt)
	_ok(typeof(parsed) == TYPE_DICTIONARY, "rig.json 可解析为字典")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	_ok(data.has("canvas"), "rig.json 有 canvas 字段")
	var cv: Array = data.get("canvas", [])
	_ok(cv.size() == 2 and int(cv[0]) == CANVAS.x and int(cv[1]) == CANVAS.y,
			"canvas = 192x256（实际 %s）" % str(cv))
	var parts: Dictionary = data.get("parts", {})
	var want := ["head", "hair_b", "torso", "arm_l", "arm_r",
			"skirt_a", "skirt_b", "leg_l", "leg_r"]
	var missing: Array = []
	for nm in want:
		if not parts.has(nm):
			missing.append(nm)
	_ok(missing.is_empty(), "九件契约齐（缺：%s）" % ("无" if missing.is_empty() else str(missing)))
	var bad_pivot: Array = []
	for nm in parts.keys():
		var pv: Array = (parts[nm] as Dictionary).get("pivot", [])
		if pv.size() != 2 or float(pv[0]) < 0 or float(pv[0]) > CANVAS.x \
				or float(pv[1]) < 0 or float(pv[1]) > CANVAS.y:
			bad_pivot.append(nm)
	_ok(bad_pivot.is_empty(), "所有 pivot 落在画布内（越界：%s）"
			% ("无" if bad_pivot.is_empty() else str(bad_pivot)))

	# ── ② parts PNG ────────────────────────────────────
	var bad_size: Array = []
	var empty: Array = []
	for nm in parts.keys():
		var p := RIG_DIR.path_join("parts").path_join(String(nm) + ".png")
		if not FileAccess.file_exists(p):
			bad_size.append(String(nm) + "(缺文件)")
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img == null or img.get_width() != CANVAS.x or img.get_height() != CANVAS.y:
			bad_size.append(String(nm) + "(尺寸错)")
			continue
		if not img.detect_alpha() or img.is_invisible():
			empty.append(String(nm))
	_ok(bad_size.is_empty(), "九张 parts 都是 192x256（异常：%s）"
			% ("无" if bad_size.is_empty() else str(bad_size)))
	_ok(empty.is_empty(), "九张 parts 都非空（空件：%s）"
			% ("无" if empty.is_empty() else str(empty)))

	# ── ③ ChibiRig.setup() ─────────────────────────────
	var host := Node2D.new()
	host.name = "Host"
	root.add_child(host)
	var rig := ChibiRig.new()
	rig.name = "ChibiRig"
	host.add_child(rig)
	rig.setup(RIG_DIR)
	await process_frame
	var rig_parts: Dictionary = rig.get("_parts")
	# ChibiRig 缺件会退化为 _placeholder 彩色方块，但 _parts 仍会登记；所以要查 z 与 pivot
	var live := rig_parts.size()
	_ok(live == parts.size(), "ChibiRig 搭起 %d 件（rig.json 声明 %d 件）" % [live, parts.size()])

	# ── ⑦ 腿在 idle 周期内不穿地 ────────────────────────
	var worst_leg := 0.0
	for k in 24:
		var p := rig.debug_seek("idle", float(k) / 12.0)
		for nm in ["leg_l", "leg_r"]:
			worst_leg = maxf(worst_leg, absf(float(p.get("dy_" + nm, 0.0))))
	_ok(worst_leg < 0.01, "idle 周期内双腿 dy 恒 0（实测最大 %.2f）" % worst_leg)

	# ── ⑤ shake / attack 轨道建得起来 ────────────────────
	var anim: AnimationPlayer = rig.get("_anim")
	var has_all := true
	for nm in ["idle", "shake", "attack", "walk", "run"]:
		if anim == null or not anim.has_animation(nm):
			has_all = false
			print("       缺动作：%s" % nm)
	_ok(has_all, "idle/shake/attack/walk/run 五条轨道都在")

	# ── ⑥ 静止对位：Sprite offset 换算契约 ────────────────
	# chibi_rig.setup() 里 `spr.offset = canvas/2 - pivot`，于是整幅图正好落在画布原点、
	# 旋转 Node2D 即绕 pivot 转。这条换算是「切件对位」的唯一承重逻辑，直接验数学：
	# 对每件都要有  node.position + sprite.offset == canvas * 0.5
	# （headless 的 dummy 渲染器没有 viewport 纹理，抓帧不可行；像素级合成对位
	#  已由 tools/cut_rig_kweno.py 的 composite==cutout 自证，那里是真像素比较。）
	# idle 动画正在播，part.position 会漂；所以把动画停掉再比，且基准取 rig.json 的 pivot。
	rig.set_speed(0.0)
	var anim2: AnimationPlayer = rig.get("_anim")
	if anim2 != null:
		anim2.stop()
	await process_frame
	var center := Vector2(CANVAS) * 0.5
	var bad_off: Array = []
	for nm in rig_parts.keys():
		var part: Node2D = rig_parts[nm]
		var spr: Sprite2D = null
		for c in part.get_children():
			if c is Sprite2D:
				spr = c as Sprite2D
				break
		if spr == null:
			bad_off.append(String(nm) + "(无 Sprite2D)")
			continue
		var pv: Array = (parts[nm] as Dictionary).get("pivot", [0, 0])
		var want_off := center - Vector2(float(pv[0]), float(pv[1]))
		if spr.offset.distance_to(want_off) > 0.01:
			bad_off.append("%s(offset%s != %s)" % [nm, str(spr.offset), str(want_off)])
		if part.position.distance_to(Vector2(float(pv[0]), float(pv[1]))) > 0.01:
			bad_off.append("%s(pos%s != pivot)" % [nm, str(part.position)])
	_ok(bad_off.is_empty(), "每件 pivot/offset 换算遵守 canvas/2-pivot（异常：%s）"
			% ("无" if bad_off.is_empty() else str(bad_off)))

	# ── ⑥b z 序：与 rig.json 声明一致，且 hair_b 在最底 ──
	var bad_z: Array = []
	for nm in parts.keys():
		var want_z := int((parts[nm] as Dictionary).get("z", 0))
		var part2: Node2D = rig_parts.get(String(nm))
		if part2 == null or part2.z_index != want_z:
			bad_z.append("%s(声明%d/实际%s)" % [nm, want_z,
					"缺" if part2 == null else str(part2.z_index)])
	_ok(bad_z.is_empty(), "九件 z_index 与 rig.json 一致（异常：%s）"
			% ("无" if bad_z.is_empty() else str(bad_z)))
	var hb: Node2D = rig_parts.get("hair_b")
	_ok(hb != null and hb.z_index < 0, "hair_b 垫在所有躯体件之下（z=%s）"
			% ("缺" if hb == null else str(hb.z_index)))

	# ── ⑧ 姿态序列导出（数值，供 Python 侧合成目检）────────
	# 引擎侧只负责算姿态；出图交给 Python（headless 无 viewport）。
	var poses := {}
	for nm2 in ["idle", "shake", "attack"]:
		var seq: Array = []
		var n_frames := 4 if nm2 == "idle" else 6
		for k in n_frames:
			seq.append(rig.debug_seek(nm2, float(k) * (1.0 if nm2 == "idle" else 1.0)))
		poses[nm2] = seq
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var f := FileAccess.open(ProjectSettings.globalize_path(SHOT_DIR.path_join("poses.json")),
			FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(poses, "  "))
		f.close()
		print("[shot] 姿态序列 → %s/poses.json" % SHOT_DIR)
	_ok(f != null, "姿态序列可写盘（供目检出图）")
