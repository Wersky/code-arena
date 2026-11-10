class_name PortraitBreathMesh
extends MeshInstance2D
## 立绘呼吸 V4（2026-11-10）：**网格顶点形变**，替代 V1~V3 的 UV 平移。
##
## ── V3 的 UV 平移为什么不够 ────────────────────────────────────────────
## UV 位移在数学上是「整幅图沿同一向量平移」，是刚体运动：
##   · 做不出胸廓横向扩张（那需要左右两侧朝**相反**方向走）
##   · 「上提」和「外扩」只能二选一
##   · 幅度一大图层边界就露缝，所以只能给极小值，观感 = 图在抖
## 商业方案（Live2D warp deformer / Spine 蒙皮）都是顶点级形变，本类即该思路的
## Godot 原生化实现：立绘细分网格 + 顶点色权重场 + 顶点着色器位移。
##
## ── 用法 ──────────────────────────────────────────────────────────────
##   var b := PortraitBreathMesh.new()
##   b.setup(portrait_tex, face_mask, body_mask, hair_mask)
##   b.position = ...; b.size = 全屏
##   add_child(b)
##   # 每帧（或用 Tween 推进）
##   b.set_phase(rad)
##
## 权重烘焙规则（用遮罩当权重场，烘进顶点色 RGBA）：
##   R = 胸腔 ← body 遮罩（躯干主体，起伏最明显）
##   G = 腹部 ← body 遮罩**向下偏移采样**（同一件衣服下半，靠 shader 相位滞后区分）
##   B = 头颈 ← face 遮罩（只做垂直，避免五官被拉扯）
##   A = 头发 ← hair 遮罩（横向飘动，相位随高度连续滞后 → 一波往下传）
## 头发从躯干权重里**扣除**：避免胸口和长发同区域叠加出双倍位移。
##
## 网格密度：32x18 = 576 顶点 / 1056 三角面。
## 为什么不更高：呼吸位移是低频平滑场，32 列已经足够平滑；
## 过高会让每个顶点拿到的权重差异变小、反而出现阶梯感（实测 48 列以上无收益）。

const SHADER := preload("res://assets/shaders/portrait_breath_v4.gdshader")
const COLS := 32
const ROWS := 18

var _mat: ShaderMaterial = null
var _built := false
var _phase := 0.0


func _ready() -> void:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		material = _mat


## 建立网格并烘焙权重。三层遮罩都应是同尺寸灰度图（任意分辨率，内部按 UV 采样）
func setup(portrait: Texture2D, face_mask: Texture2D, body_mask: Texture2D,
		hair_mask: Texture2D = null) -> void:
	if portrait == null:
		return
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		material = _mat
	# 显式写入全部 uniform：不写的话 get_shader_parameter 返回 null，
	# 且后续面板改参数时没有基线可对照（实测踩到）
	# 幅度按「画面高的百分比」定：商业 Live2D 常见 0.8~1.5%，
	# 原先 4.5px 只有 0.5%，主人反馈看不出动静，统一提到约 1.2%（900 高 -> 11px）。
	_mat.set_shader_parameter("amp", 1.0)
	_mat.set_shader_parameter("chest_x", 10.5)
	_mat.set_shader_parameter("chest_y", 8.5)
	_mat.set_shader_parameter("belly_x", 6.0)
	_mat.set_shader_parameter("belly_y", 3.2)
	_mat.set_shader_parameter("head_y", 4.5)
	_mat.set_shader_parameter("hair_x", 11.0)
	_mat.set_shader_parameter("hair_y", 4.0)
	_mat.set_shader_parameter("belly_lag_deg", 55.0)
	_mat.set_shader_parameter("head_lag_deg", 100.0)
	_mat.set_shader_parameter("hair_lag_per_height", 240.0)
	_mat.set_shader_parameter("lock_bottom", 0.12)
	# 横竖分离：横向相位滞后 + 纵向偏移 + 横向总开关
	_mat.set_shader_parameter("x_lag_deg", 0.0)
	_mat.set_shader_parameter("y_bias", 0.35)
	_mat.set_shader_parameter("use_horiz", true)
	texture = portrait
	mesh = _build_mesh(portrait, face_mask, body_mask, hair_mask)
	_built = true


func _build_mesh(portrait: Texture2D, face_mask: Texture2D, body_mask: Texture2D,
		hair_mask: Texture2D = null) -> ArrayMesh:
	var sz := Vector2(portrait.get_size())
	# 网格顶点用「以中心为原点」的局部坐标：这样 sign(VERTEX.x) 才是可靠的左右判据
	var half := sz * 0.5

	# 遮罩像素（用于烘焙权重）。取不到就退化为全零权重（等于不呼吸，不会崩）
	var body_img := _to_gray_image(body_mask)
	var face_img := _to_gray_image(face_mask)
	var hair_img := _to_gray_image(hair_mask)

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for row in ROWS + 1:
		for col in COLS + 1:
			var u := float(col) / float(COLS)
			var v := float(row) / float(ROWS)
			# 局部坐标：中心原点，像素单位
			verts.append(Vector3((u - 0.5) * sz.x, (v - 0.5) * sz.y, 0.0))
			uvs.append(Vector2(u, v))
			# 权重采样（R=胸 G=腹 B=头）
			var w_body := _sample_gray(body_img, u, v)
			# 腹部取同一遮罩向下偏一点的位置：同一件衣服的下半，相位靠相位滞后区分
			var w_belly := _sample_gray(body_img, u, minf(v + 0.06, 1.0))
			var w_face := _sample_gray(face_img, u, v)
			var w_hair := _sample_gray(hair_img, u, v)
			# 环境层：三层遮罩都没盖住的区域（巨鲸、背景书廊等），给极轻权重。
			# 为什么需要：主体之外的大片区域若完全静止，视觉上像「人物贴纸在动、背景是照片」，
			# 商业立绘里连背景都有 1~2px 的呼吸感。权重压到主体 1/10 以下。
			var w_any: float = maxf(maxf(w_body, w_face), w_hair)
			var w_env: float = clampf(1.0 - w_any * 1.6, 0.0, 1.0) * 0.10
			# 头发区域从躯干权重里扣除，避免同一像素既被胸口推又被头发拉
			var inv_hair: float = 1.0 - w_hair * 0.85
			w_body *= inv_hair
			w_belly *= inv_hair
			w_face *= inv_hair
			# 环境权重并进「胸腔」通道的极小分量（复用同一条位移曲线，不额外加 cost）
			w_body = maxf(w_body, w_env)
			# 腹部与胸腔是同一区域的上下两半，避免叠加过猛 → 腹部权重压到 0.55
			colors.append(Color(w_body, w_belly * 0.55, w_face, w_hair))

	for row in ROWS:
		for col in COLS:
			var i := row * (COLS + 1) + col
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + COLS + 1)
			indices.append(i + 1)
			indices.append(i + COLS + 2)
			indices.append(i + COLS + 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _to_gray_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_L8)
	return img


## 双线性采样灰度（越界返回 0）
func _sample_gray(img: Image, u: float, v: float) -> float:
	if img == null:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return 0.0
	var x := clampf(u, 0.0, 1.0) * float(w - 1)
	var y := clampf(v, 0.0, 1.0) * float(h - 1)
	var x0 := int(floor(x))
	var y0 := int(floor(y))
	var x1 := mini(x0 + 1, w - 1)
	var y1 := mini(y0 + 1, h - 1)
	var fx := x - float(x0)
	var fy := y - float(y0)
	var a := float(img.get_pixel(x0, y0).r)
	var b := float(img.get_pixel(x1, y0).r)
	var c := float(img.get_pixel(x0, y1).r)
	var d := float(img.get_pixel(x1, y1).r)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## 推进相位（弧度）。调用方负责按周期换算
func set_phase(rad: float) -> void:
	_phase = rad
	if _mat != null:
		_mat.set_shader_parameter("phase", rad)


func is_built() -> bool:
	return _built


## 调参入口（面板用）
func set_amp(v: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("amp", clampf(v, 0.0, 3.0))


func set_split(chest_x: float, chest_y: float, belly_x: float, belly_y: float,
		head_y: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("chest_x", chest_x)
	_mat.set_shader_parameter("chest_y", chest_y)
	_mat.set_shader_parameter("belly_x", belly_x)
	_mat.set_shader_parameter("belly_y", belly_y)
	_mat.set_shader_parameter("head_y", head_y)


func set_hair(hair_x: float, hair_y: float, lag_per_height: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("hair_x", hair_x)
	_mat.set_shader_parameter("hair_y", hair_y)
	_mat.set_shader_parameter("hair_lag_per_height", lag_per_height)


## 横向开关（主人可关掉 → 纯上下呼吸，彻底消除任何旋转观感）
func set_horiz(on: bool) -> void:
	if _mat != null:
		_mat.set_shader_parameter("use_horiz", on)


## 横竖分离参数：横向相对纵向的相位滞后（度）+ 纵向偏移量
func set_axis_split(x_lag_deg: float, y_bias: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("x_lag_deg", x_lag_deg)
	_mat.set_shader_parameter("y_bias", clampf(y_bias, 0.0, 1.0))


## 底部锁定比例
func set_lock_bottom(v: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("lock_bottom", clampf(v, 0.0, 0.5))


## 读回全部 V4 参数（面板回填 / 测试用）
func get_v4_params() -> Dictionary:
	var out := {}
	if _mat == null:
		return out
	for k in ["amp", "chest_x", "chest_y", "belly_x", "belly_y", "head_y",
			"hair_x", "hair_y", "belly_lag_deg", "head_lag_deg",
			"hair_lag_per_height", "lock_bottom", "x_lag_deg", "y_bias", "use_horiz"]:
		var v = _mat.get_shader_parameter(k)
		if v != null:
			out[k] = v
	return out


## 一次性设多个 V4 参数（面板拖动用）
func set_v4_param(key: String, value: float) -> void:
	if _mat == null:
		return
	if key == "use_horiz":
		_mat.set_shader_parameter(key, value > 0.5)
	else:
		_mat.set_shader_parameter(key, value)


func set_lag(belly_deg: float, head_deg: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("belly_lag_deg", belly_deg)
	_mat.set_shader_parameter("head_lag_deg", head_deg)


## 顶点权重统计（测试/调试用）：返回 {max_chest, max_belly, max_head}
func weight_stats() -> Dictionary:
	var m := mesh
	if m == null or m.get_surface_count() == 0:
		return {"max_chest": 0.0, "max_belly": 0.0, "max_head": 0.0}
	var arr := m.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var mc := 0.0
	var mb := 0.0
	var mh := 0.0
	for c in cols:
		mc = maxf(mc, c.r)
		mb = maxf(mb, c.g)
		mh = maxf(mh, c.b)
	return {"max_chest": mc, "max_belly": mb, "max_head": mh}
