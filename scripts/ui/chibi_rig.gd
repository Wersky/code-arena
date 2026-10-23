class_name ChibiRig
extends Node2D
## Q 版像素角色的「切件骨架 + 动作循环」。
##
## 切件契约（wf-art 产出）：
##   res://assets/art/rig/<角色>/rig.json
##   {"canvas":[192,256], "parts":{"torso":{"pivot":[96,150],"z":0}, ...}}
##   res://assets/art/rig/<角色>/parts/<name>.png  —— 每张都是整幅 192×256 透明图
##
## 骨架构法：每个部件一个 Node2D（放在 pivot 上），Sprite2D 作为子节点并设置
## offset = canvas/2 - pivot。于是 Sprite 画出来的整幅图正好落在 (0,0) 处，
## 而旋转 Node2D 就是「绕 pivot 旋转」。
##
## 对外接口只有三个：setup / play / set_speed。
## （另有一个 debug_seek_walk，仅供截图钩子逐帧定格用，集成时别调。）

## walk 帧率：4 帧（两步）循环
const WALK_FPS := 8.0
const WALK_FRAME_DUR := 1.0 / WALK_FPS
const WALK_FRAMES := 4

## ── walk 参数表（角度 deg / 位移 canvas px；真实切件是 48×64 的 4 倍放大，
##    所以 1「美术像素」= 4 canvas px）─────────────────────────────
## 帧序：
##   f0 抬左腿（右腿踩实，身体上浮）
##   f1 双脚着地：左腿张开 7 踩实 / 右腿内收 3 且踮脚 4  → 承重在左
##   f2 抬右腿（左腿踩实，身体上浮）
##   f3 双脚着地：右腿张开 7 踩实 / 左腿内收 3 且踮脚 4  → 承重在右
## 腿的 x 是跨步：支撑期脚相对身体往后（+x）扫，摆动期再跳回前方，这样不打滑。
## 只有摆动那一帧抬 y，抬 12 → 摆动脚脚底 y=269，仍露在裙摆下缘之外。
const W_LEG_LIFT := 12.0    ## 摆动腿抬起（3 美术像素，脚底 281→269）
const W_LEG_X := 7.0        ## 跨步幅度：着地帧里"在前"那条腿往外张 7
const W_LEG_X_IN := 3.0     ## 着地帧里"在后"那条腿往内收 3（两帧姿态差 = 10px/腿）
const W_LEG_PASS_X := 2.0   ## 摆动腿过中线时再往前 2（f0/f2 的摆动相位）
const W_LEG_TOE := 4.0      ## 着地帧后脚踮脚（1 美术像素；没有踝关节，只能整只脚抬）
## 上半身 bob：只作用在 torso/head/arm/skirt/tail，root 与腿都不动。
## 上下各半（抬腿帧 -4 / 着地帧 +6），总幅 10 —— 全往上抬的话头顶会顶出画布上沿。
const W_BOB_UP := 4.0       ## 抬腿帧（f0/f2）身体上浮
const W_BOB_DN := 6.0       ## 着地帧（f1/f3）身体下沉，合计 10
const W_HEAD_NOD := 1.5     ## 头点头，相位比躯干滞后 1 帧
const W_TORSO_TILT := 2.0   ## 躯干左右倾
const W_ARM := 6.0          ## 手臂摆幅：实测 6° 肩部无豁口，7° 就漏 1px（见 note 的角度扫描）
const W_SKIRT_A := 5.0      ## 裙摆前后甩（follow-through）
const W_SKIRT_X := 3.0      ## 裙摆横摆
const W_SKIRT_BOB := 4.0    ## 裙摆 bob（按躯干 6:10 缩到 ±2/4）
const W_TAIL_A := 7.0       ## 尾巴甩（follow-through，比裙摆更滞后）
const W_TAIL_BOB := 4.0     ## 尾巴 bob
## 地面影子（不进 rig.json，纯引擎侧）
const SHADOW_W := 88        ## 椭圆宽（只包住脚下一小圈，太宽像块黑斑）
const SHADOW_H := 15        ## 椭圆高
const SHADOW_Y := 252.0     ## 画布坐标里影子的中心 y（脚底在 256，影子略偏上）

## 真实 rig.json 不存在时的占位数据（彩色方块，先把流程跑通）
const FALLBACK_RIG := {
	"canvas": [192, 256],
	"parts": {
		"tail": {"pivot": [146, 198], "z": 0},
		"leg_l": {"pivot": [80, 212], "z": 1},
		"leg_r": {"pivot": [112, 212], "z": 1},
		"skirt": {"pivot": [96, 192], "z": 2},
		"torso": {"pivot": [96, 190], "z": 3},
		"arm_l": {"pivot": [62, 148], "z": 4},
		"arm_r": {"pivot": [130, 148], "z": 4},
		"head": {"pivot": [96, 134], "z": 5},
	},
}

var _root: Node2D = null
var _anim: AnimationPlayer = null
var _shadow: Sprite2D = null
var _parts: Dictionary = {}
var _pivot_y: Dictionary = {}
var _canvas := Vector2i(192, 256)
var _speed := 1.0
var _anim_name := ""
var _oneshot_active := false
var _ph_cache: Dictionary = {}


# ── 对外接口 ──────────────────────────────────────────
## 读取 rig.json + 各部件 PNG 并搭好骨架。目录读不到时退化为占位方块，不报错不崩。
## setup 完成后自动播 idle。
func setup(dir: String) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_parts.clear()
	_pivot_y.clear()
	_ph_cache.clear()
	_oneshot_active = false
	_shadow = null

	var data := _load_rig(dir)
	var cv: Array = data.get("canvas", [192, 256])
	_canvas = Vector2i(int(cv[0]), int(cv[1]))

	_root = Node2D.new()
	_root.name = "Root"
	add_child(_root)

	# 影子：不进 rig.json（那是美术的契约），纯引擎侧生成。
	# 注意 z_index 用 0 而不是负数——负数会被任何 z=0 的背景板整块盖住（本项目的背景
	# 都是 z=0 的 ColorRect）。这里靠在所有部件之前 add_child，靠树序垫在最底下。
	_shadow = Sprite2D.new()
	_shadow.name = "Shadow"
	_shadow.texture = _shadow_texture()
	_shadow.position = Vector2(_canvas.x * 0.5, SHADOW_Y)
	_shadow.z_index = 0
	_shadow.modulate = Color(1, 1, 1, 0.38)
	_root.add_child(_shadow)

	var parts: Dictionary = data.get("parts", {})
	for nm in parts.keys():
		var info: Dictionary = parts[nm]
		var pv: Array = info.get("pivot", [0, 0])
		var pivot := Vector2(float(pv[0]), float(pv[1]))
		var part := Node2D.new()
		part.name = String(nm).validate_node_name()
		part.position = pivot
		part.z_index = int(info.get("z", 0))
		var spr := Sprite2D.new()
		spr.texture = _part_texture(dir, String(nm))
		# sprite 中心挪到画布中心 → 整幅图与画布对齐，旋转 Node2D 即绕 pivot 转
		spr.offset = Vector2(_canvas) * 0.5 - pivot
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		part.add_child(spr)
		_root.add_child(part)
		_parts[String(nm)] = part
		_pivot_y[String(nm)] = pivot.y

	_build_animations()
	play("idle")

## 播放动作：walk / idle / shake / attack。未知动作忽略（不崩）。
## shake / attack 是一次性动作，播完自动回到 idle（一次性动作期间再 play 会被忽略，
## 避免悬停连触发把动作打断成抽搐）。
func play(anim: String) -> void:
	if _anim == null or not _anim.has_animation(anim):
		return
	if _oneshot_active:
		return
	_anim_name = anim
	if anim == "shake" or anim == "attack":
		_oneshot_active = true
	_anim.speed_scale = _speed
	_anim.play(anim)


## 播放倍速（0 = 定格）。
func set_speed(f: float) -> void:
	_speed = maxf(0.0, f)
	if _anim != null:
		_anim.speed_scale = _speed


# ── 仅供截图钩子：把 walk 定格在第 frame 帧（0..3，可传小数做亚帧检查）并回显姿态 ──
func debug_seek_walk(frame: float) -> Dictionary:
	if _anim == null or not _anim.has_animation("walk"):
		return {}
	_anim.play("walk")
	_anim.speed_scale = 0.0
	_anim.seek(fposmod(frame, float(WALK_FRAMES)) * WALK_FRAME_DUR, true)
	var pose := {"root_y": snappedf(_root.position.y, 0.01)}
	for nm in _parts:
		var p: Node2D = _parts[nm]
		pose[nm] = snappedf(rad_to_deg(p.rotation), 0.01)
		# dy = 该件相对 pivot 的纵向偏移（正 = 往下）；腿的 dy 决定脚是否离地
		pose["dy_" + nm] = snappedf(p.position.y - _pivot_y[nm], 0.01)
	return pose


# ── 数据加载 ──────────────────────────────────────────
func _load_rig(dir: String) -> Dictionary:
	var json_path := dir.path_join("rig.json")
	if not FileAccess.file_exists(json_path):
		push_warning("[ChibiRig] 没有 rig.json，用占位骨架：%s" % json_path)
		return FALLBACK_RIG.duplicate(true)
	var txt := FileAccess.get_file_as_string(json_path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("parts"):
		push_warning("[ChibiRig] rig.json 解析失败，用占位骨架：%s" % json_path)
		return FALLBACK_RIG.duplicate(true)
	var data: Dictionary = parsed
	if not data.has("canvas"):
		data["canvas"] = [192, 256]
	return data


## 影子贴图：近黑椭圆 + 一圈更透的边。像素风不做羽化，2 档 alpha 就够。
func _shadow_texture() -> Texture2D:
	var img := Image.create_empty(SHADOW_W, SHADOW_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(SHADOW_W) * 0.5
	var cy := float(SHADOW_H) * 0.5
	for y in SHADOW_H:
		for x in SHADOW_W:
			var dx := (float(x) + 0.5 - cx) / (cx - 1.0)
			var dy := (float(y) + 0.5 - cy) / (cy - 1.0)
			var d := dx * dx + dy * dy
			if d <= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0.5 if d > 0.62 else 1.0))
	return ImageTexture.create_from_image(img)


func _part_texture(dir: String, part_name: String) -> Texture2D:
	var p := dir.path_join("parts").path_join(part_name + ".png")
	if ResourceLoader.exists(p):
		var t: Resource = load(p)
		if t is Texture2D:
			return t as Texture2D
	return _placeholder(part_name)


# ── 占位部件（彩色方块，只在真实切件缺失时用）──────────
func _placeholder(part_name: String) -> Texture2D:
	if _ph_cache.has(part_name):
		return _ph_cache[part_name]
	var img := Image.create_empty(_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark := Color("#1B2246")
	match part_name:
		"head":
			_disc(img, Vector2i(96, 96), 42, Color("#E9EEFF"), dark)
			_blob(img, Rect2i(76, 86, 9, 12), Color("#1B2246"))
			_blob(img, Rect2i(106, 86, 9, 12), Color("#1B2246"))
			_blob(img, Rect2i(90, 108, 12, 4), Color("#8FA0D8"))
		"torso":
			_blob(img, Rect2i(68, 134, 56, 58), Color("#4D6BFE"), dark)
		"arm_l":
			_blob(img, Rect2i(55, 148, 14, 54), Color("#3C55D8"), dark)
		"arm_r":
			_blob(img, Rect2i(123, 148, 14, 54), Color("#3C55D8"), dark)
		"skirt":
			for y in range(192, 224):
				var w := 58 + int((y - 192) * 0.85)
				_blob(img, Rect2i(96 - w / 2, y, w, 1), Color("#2E3A8C"), dark, false)
			_blob(img, Rect2i(96 - 42, 222, 84, 3), Color("#232C6B"))
		"leg_l":
			_blob(img, Rect2i(74, 212, 13, 30), Color("#22305E"), dark)
			_blob(img, Rect2i(68, 236, 19, 7), Color("#111A3A"))
		"leg_r":
			_blob(img, Rect2i(105, 212, 13, 30), Color("#22305E"), dark)
			_blob(img, Rect2i(105, 236, 19, 7), Color("#111A3A"))
		"tail":
			_blob(img, Rect2i(146, 188, 10, 10), Color("#7FA0FF"), dark)
			_blob(img, Rect2i(154, 178, 9, 9), Color("#7FA0FF"), dark)
			_blob(img, Rect2i(162, 168, 8, 8), Color("#A9C0FF"), dark)
		_:
			# 未知部件：给个小方块，别让集成阶段直接崩
			_blob(img, Rect2i(88, 120, 16, 16), Color("#FF5C8A"), dark)
	var tex := ImageTexture.create_from_image(img)
	_ph_cache[part_name] = tex
	return tex


func _blob(img: Image, r: Rect2i, col: Color, outline: Color = Color(0, 0, 0, 0),
		do_outline: bool = true) -> void:
	img.fill_rect(r, col)
	if not do_outline or outline.a <= 0.0:
		return
	if r.size.x > 2:
		img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 1), outline)
		img.fill_rect(Rect2i(r.position.x, r.position.y + r.size.y - 1, r.size.x, 1), outline)
	if r.size.y > 2:
		img.fill_rect(Rect2i(r.position.x, r.position.y, 1, r.size.y), outline)
		img.fill_rect(Rect2i(r.position.x + r.size.x - 1, r.position.y, 1, r.size.y), outline)


func _disc(img: Image, c: Vector2i, rad: int, col: Color, outline: Color) -> void:
	for y in range(c.y - rad, c.y + rad + 1):
		if y < 0 or y >= img.get_height():
			continue
		for x in range(c.x - rad, c.x + rad + 1):
			if x < 0 or x >= img.get_width():
				continue
			var d := Vector2(float(x - c.x), float(y - c.y)).length()
			if d <= float(rad):
				img.set_pixel(x, y, outline if d > float(rad) - 2.0 else col)


# ── 动画（关键帧插值，不是逐帧贴图）────────────────────
func _build_animations() -> void:
	_anim = AnimationPlayer.new()
	_anim.name = "Anim"
	add_child(_anim)
	var lib := AnimationLibrary.new()
	lib.add_animation("walk", _make_walk())
	lib.add_animation("idle", _make_idle())
	lib.add_animation("shake", _make_shake())
	lib.add_animation("attack", _make_attack())
	_anim.add_animation_library("", lib)
	# 一次性动作播完自动回 idle；caller 若在播 walk，由 caller 自己再 play("walk")
	_anim.animation_finished.connect(_on_anim_finished)


func _on_anim_finished(anim_name: StringName) -> void:
	if _oneshot_active and anim_name in ["shake", "attack"]:
		_oneshot_active = false
		_anim_name = "idle"
		_anim.speed_scale = _speed
		_anim.play("idle")


## walk：4 帧 / 两步。f0 抬左（右支撑）→ f1 双脚着地（左前右后）→ f2 抬右（左支撑）
## → f3 双脚着地（右前左后）。四个帧两两不同。
##
## 分工：
##   · 腿：x 走跨步（支撑期扫 -x，摆动期跳过前方），摆动那一帧抬 12。支撑腿 y 恒 0，
##     只有摆动腿会离地 → 脚永远踩在地线上，且不穿地（腿轨必须 LINEAR，见 _add）。
##   · 上半身：bob 只加在 torso / head / arm（同幅，避免脖子脱开）/ skirt / tail，
##     root 与腿完全不动。
##   · follow-through：躯干 → 裙摆（滞后 1 帧）→ 尾巴（再滞后 1 帧）。
##   · 影子：位置钉死在地面，只随 bob 缩放 + 变淡（抬起 = 小且淡，着地 = 大且实）。
func _make_walk() -> Animation:
	var a := Animation.new()
	a.length = WALK_FRAME_DUR * float(WALK_FRAMES)
	a.loop_mode = Animation.LOOP_LINEAR
	var d := WALK_FRAME_DUR
	var lin := Animation.INTERPOLATION_LINEAR
	# ① 腿：跨步 x + 摆动帧抬 y。支撑期 x 单调往 +x 扫 → 不打滑的方向是对的。
	#    着地帧（f1/f3）：一条腿张开踩实（±6），另一条腿收在身体下方踮脚（3 内收 / 抬 4）。
	#    于是 f1 的承重落在左脚、f3 落在右脚，两帧差 9px/腿。
	_add(a, "leg_l", "position:x", [-W_LEG_PASS_X, -W_LEG_X, -W_LEG_PASS_X, W_LEG_X_IN, -W_LEG_PASS_X], d, lin)
	_add(a, "leg_l", "position:y", [-W_LEG_LIFT, 0, 0, -W_LEG_TOE, -W_LEG_LIFT], d, lin)
	_add(a, "leg_r", "position:x", [W_LEG_PASS_X, -W_LEG_X_IN, W_LEG_PASS_X, W_LEG_X, W_LEG_PASS_X], d, lin)
	_add(a, "leg_r", "position:y", [0, -W_LEG_TOE, -W_LEG_LIFT, 0, 0], d, lin)
	# ② 躯干：抬腿帧上浮 / 着地帧下沉（一拍一次），左右倾一整周期一次
	_add(a, "torso", "position:y", [-W_BOB_UP, W_BOB_DN, -W_BOB_UP, W_BOB_DN, -W_BOB_UP], d)
	_add(a, "torso", "rotation", [0, W_TORSO_TILT, 0, -W_TORSO_TILT, 0], d)
	# ③ 头：与躯干同相位同幅度（不同幅就会把脖子拉出缝），点头滞后 1 帧
	_add(a, "head", "position:y", [-W_BOB_UP, W_BOB_DN, -W_BOB_UP, W_BOB_DN, -W_BOB_UP], d)
	_add(a, "head", "rotation", [-W_HEAD_NOD, 0, W_HEAD_NOD, 0, -W_HEAD_NOD], d)
	# ④ 手臂（= 两侧头发条带）：跟躯干 bob，9° 拖尾，相位滞后躯干 1 帧
	_add(a, "arm_l", "position:y", [-W_BOB_UP, W_BOB_DN, -W_BOB_UP, W_BOB_DN, -W_BOB_UP], d)
	_add(a, "arm_r", "position:y", [-W_BOB_UP, W_BOB_DN, -W_BOB_UP, W_BOB_DN, -W_BOB_UP], d)
	_add(a, "arm_l", "rotation", [-W_ARM, 0, W_ARM, 0, -W_ARM], d)
	_add(a, "arm_r", "rotation", [W_ARM, 0, -W_ARM, 0, W_ARM], d)
	# ⑤ 裙摆：bob 按 6:10 缩，摆动/横摆滞后躯干 1 帧
	_add(a, "skirt", "position:y", [-W_SKIRT_BOB * 0.5, W_SKIRT_BOB, -W_SKIRT_BOB * 0.5, W_SKIRT_BOB, -W_SKIRT_BOB * 0.5], d)
	_add(a, "skirt", "position:x", [-W_SKIRT_X, 0, W_SKIRT_X, 0, -W_SKIRT_X], d)
	_add(a, "skirt", "rotation", [-W_SKIRT_A, 0, W_SKIRT_A, 0, -W_SKIRT_A], d)
	# ⑥ 尾巴：比裙摆再滞后 1 帧（甩尾）
	_add(a, "tail", "position:y", [-W_TAIL_BOB * 0.5, W_TAIL_BOB, -W_TAIL_BOB * 0.5, W_TAIL_BOB, -W_TAIL_BOB * 0.5], d)
	_add(a, "tail", "rotation", [W_TAIL_A, 0, -W_TAIL_A, 0, W_TAIL_A], d)
	# ⑦ 影子：位置固定在 SHADOW_Y，只有缩放和透明度随上下起伏变
	_add(a, "shadow", "scale:x", [0.85, 1.0, 0.85, 1.0, 0.85], d)
	_add(a, "shadow", "scale:y", [0.85, 1.0, 0.85, 1.0, 0.85], d)
	_add(a, "shadow", "modulate:a", [0.55, 0.75, 0.55, 0.75, 0.55], d)
	return a


## idle：呼吸 + 极轻浮动（4 秒一轮）
func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = 4.0
	a.loop_mode = Animation.LOOP_LINEAR
	_add(a, "root", "position:y", [0, -1, 0, -1, 0], 1.0)
	_add(a, "torso", "rotation", [0, 0.6, 0, -0.6, 0], 1.0)
	_add(a, "head", "position:y", [0, 0.8, 0, 0.8, 0], 1.0)
	_add(a, "head", "rotation", [0, 1.2, 0, -1.2, 0], 1.0)
	_add(a, "arm_l", "rotation", [0, 1.2, 0, -1.2, 0], 1.0)
	_add(a, "arm_r", "rotation", [0, -1.2, 0, 1.2, 0], 1.0)
	_add(a, "tail", "rotation", [0, 4, 0, -4, 0], 1.0)
	return a


## shake：摇头（0.6 秒一次性）。头绕脖子 pivot 左右甩，躯干/尾巴做反向小配重。
## 头的 pivot 在脖子上（[96,72]），纯旋转不会把脸甩出画布。
func _make_shake() -> Animation:
	var a := Animation.new()
	a.length = 0.6
	var d := 0.1
	_add(a, "head", "rotation", [0, 9, -9, 9, -9, 4, 0], d)
	_add(a, "torso", "rotation", [0, 2, -2, 2, -2, 1, 0], d)
	_add(a, "tail", "rotation", [0, -5, 5, -5, 5, -2, 0], d)
	return a


## attack：前扑（0.5 秒一次性）。面向镜头的 Q 版没有"前方"，
## 用「后仰蓄力 → 向镜头逼近（root 放大 + 下沉）→ 手臂上挥 → 收回」三段演出。
## 影子是 root 的子节点，会跟着一起放大——扑向镜头时影子变大变近，方向感是对的。
func _make_attack() -> Animation:
	var a := Animation.new()
	a.length = 0.5
	var d := 0.1
	_add(a, "root", "position:y", [0, -2, 6, 3, 0, 0], d)
	_add(a, "root", "scale:x", [1, 0.98, 1.06, 1.02, 1, 1], d)
	_add(a, "root", "scale:y", [1, 0.98, 1.06, 1.02, 1, 1], d)
	_add(a, "arm_l", "rotation", [0, 8, -24, -10, 0, 0], d)
	_add(a, "arm_r", "rotation", [0, -8, 24, 10, 0, 0], d)
	_add(a, "torso", "rotation", [0, -2, 3, 1, 0, 0], d)
	_add(a, "head", "rotation", [0, -3, 5, 2, 0, 0], d)
	_add(a, "tail", "rotation", [0, 6, -10, -4, 0, 0], d)
	return a


## 加一条数值轨道；rotation 传角度，position:* 传「相对 pivot 的位移」，其余传原值。
## 部件不存在就静默跳过。
## interp 默认 CUBIC（上半身要顺）；腿必须用 LINEAR——cubic 在两条相同的 0 关键帧
## 之间会过冲，把支撑脚压到地线以下。
func _add(a: Animation, part: String, prop: String, vals: Array, step: float,
		interp := Animation.INTERPOLATION_CUBIC) -> void:
	var node: Node = _shadow if part == "shadow" else (_root if part == "root" else _parts.get(part, null))
	if node == null:
		return
	var idx := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(idx, NodePath(str(get_path_to(node)) + ":" + prop))
	a.track_set_interpolation_type(idx, interp)
	a.value_track_set_update_mode(idx, Animation.UPDATE_CONTINUOUS)
	# position 轨是绝对坐标，得把 pivot 本来的位置加回去，否则部件会被拉回原点
	var is_pos := prop.begins_with("position")
	var base: Vector2 = (node as Node2D).position
	var t := 0.0
	for v in vals:
		var fv := float(v)
		if prop == "rotation":
			fv = deg_to_rad(fv)
		elif is_pos:
			fv += base.x if prop.ends_with("x") else base.y
		a.track_insert_key(idx, t, fv)
		t += step
