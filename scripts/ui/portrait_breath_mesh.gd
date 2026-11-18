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
## 头颈（face）优先于头发：眼睛区域强制不拿头发权重（见 _build_mesh 的 face_gate）。
##
## ── 第 5 通道：翅膀（2026-11-11，t4-gpt-wing-breath）────────────────────
## 顶点色 RGBA 四个通道已占满（R 胸 / G 腹 / B 头 / A 发），而翅膀需要**独立呼吸
## 节奏**（不能和胸/腹/头/发同相，否则翅膀只是跟着身体一起晃，看不出「它在呼吸」）。
## 所以翅膀权重不进顶点色，改走 **Mesh.ARRAY_CUSTOM0**（顶点自定义属性，R_FLOAT
## = 每顶点 1 个 float）。着色器里 `CUSTOM0.x` 直接读。
##
## 为什么是 CUSTOM0 而不是另外两条候选路线：
##   · 「并进某个通道、用不同相位」→ 会削掉原通道精度。四通道已经全部有主，任何并入
##     都要按比例分蛋糕：翅占 0.3 就意味着胸的幅度少 30%，是肉眼可见的退化。
##   · 「单独烘一张 wing mask 在 fragment 采样」→ **不可行**。本项目是
##     gl_compatibility，实测**顶点着色器里的 texture() 采样不生效**（历史坑，见
##     portrait_breath_v4.gdshader 里的记录）；而位移必须发生在 vertex()，fragment
##     拿到权重时顶点早就算完了。这条路根本走不通。
##   · CUSTOM0 → 原生顶点属性，vertex() 直接可用，精度独立、零额外采样、零额外 draw call。
##
## ⚠ 声明格式必须走 SurfaceTool.set_custom_format()，不能用 add_surface_from_arrays：
##   后者要求 arrays.size() == ARRAY_MAX (13)，多塞一个 ARRAY_FORMAT 槽位会被
##   直接拒绝（实测 "Condition p_arrays.size() != ARRAY_MAX is true"），表面建不出来。
##   而 SurfaceTool 会把 CUSTOM0 的格式位正确写进 surface_get_format()。
##
## 三个没有翅膀的角色 wing=null → 权重全 0，CUSTOM0 依然存在（额外 9417 个 float，
## 约 37KB，可忽略）但恒为 0，位移项乘 0 = 完全无影响，优雅降级。

const SHADER := preload("res://assets/shaders/portrait_breath_v4.gdshader")
## 网格密度：128x72。
##
## 为什么从 32x18 一路提到 128x72（2026-11-10 主人反馈「头纵带动右眼、发纵发横带动左眼」）：
## 32x18 时**整张脸只跨 1.8~2.6 格**——脸上只有 2~3 个顶点，眼睛和压在眼睛上的
## 刘海共用同一批顶点，权重插值必然互相渗透。
## 128x72 时脸跨 7~15 格（四个人物实测），眼睛能独立落在多个顶点上。
## 实测 192x108 效果并不比 128x72 更好（脸芯中位位移早已是 0，只剩边缘羽化带），
## 但烘焙耗时从 ~0.8s 涨到 1.26s，不值得。
## 注：早前记录的「48 列以上无收益」是针对**纯低频呼吸**；现在要的是**局部精细分区**，
## 结论不适用，别拿旧结论来反驳。
const COLS := 128
const ROWS := 72

var _mat: ShaderMaterial = null
var _built := false
var _phase := 0.0
## 环境（背景）层权重（2026-11-10 主人反馈「有些地方动得过了」）：
## 让未被任何遮罩覆盖的区域也有极轻位移，避免「人物贴纸在动、背景是照片」。
## 但背景跟着动会显得画面整体在晃 → 下调到 0.05，并开放成面板参数（0 = 背景完全静止）。
## 注意：权重烘在顶点色里，改动需要重建网格（见 set_env_weight）。
var env_weight := 0.0
## 上次 setup 的纹理（重建网格时要用）
var _tex_ref: Texture2D = null
var _face_ref: Texture2D = null
var _body_ref: Texture2D = null
var _hair_ref: Texture2D = null
## 翅膀遮罩（2026-11-11 第 5 通道）：只有 chatppt 有，其余为 null。
## 参与 CUSTOM0 烘焙，所以重建网格时必须一起带上。
var _wing_ref: Texture2D = null


func _ready() -> void:
	_ensure_mat()


## 建材质并**只在第一次**写出厂默认。setup() 与 _ready() 都走这里，
## 谁先跑都不会漏掉默认值，也都不会在切角色时重复重置。
func _ensure_mat() -> void:
	if _mat != null:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	_reset_to_defaults()


## 建立网格并烘焙权重。四层遮罩都应是同尺寸灰度图（任意分辨率，内部按 UV 采样）
## wing_mask 为第 5 通道（2026-11-11）：写进 CUSTOM0，不进顶点色。
## 传 null = 该角色没有翅膀，权重全 0（不影响其余四通道）。
## **不重置参数**：uniform 只在首次建材质时写出厂默认，之后一律由
## GameSettings 的分角色存档经 apply_v4_params() 灌入。
## （2026-11-10 踩过：原先每次 setup 都硬写 15 个 uniform，切角色把面板调好的值全冲掉。）
func setup(portrait: Texture2D, face_mask: Texture2D, body_mask: Texture2D,
		hair_mask: Texture2D = null, wing_mask: Texture2D = null) -> void:
	if portrait == null:
		return
	_ensure_mat()
	texture = portrait
	_tex_ref = portrait
	_face_ref = face_mask
	_body_ref = body_mask
	_hair_ref = hair_mask
	_wing_ref = wing_mask
	mesh = _build_mesh(portrait, face_mask, body_mask, hair_mask, wing_mask)
	_built = true


## 写出厂默认（只在材质刚建出来时调一次，防止 get_shader_parameter 返回 null）
## 各角色的真实出厂值是**不同**的，由 GameSettings.BREATH_V4_PRESETS 管；
## 这里只写通用兜底，随后 CharacterSelectScreen 会用当前角色的预设覆盖。
func _reset_to_defaults() -> void:
	for k in GameSettings.BREATH_V4_KEYS:
		_mat.set_shader_parameter(k, float(GameSettings.BREATH_V4_DEFAULTS[k]))
	_mat.set_shader_parameter("use_horiz", GameSettings.breath_use_horiz)


## 把一整套 V4 参数灌进材质（切角色 / 面板回填都走这条）
## env_weight 特殊：它烘进顶点色、不是 uniform，必须走 set_env_weight 重建网格。
func apply_v4_params(d: Dictionary) -> void:
	if _mat == null:
		return
	for k in GameSettings.BREATH_V4_KEYS:
		if not d.has(k):
			continue
		if String(k) == "env_weight":
			set_env_weight(float(d[k]))
		else:
			_mat.set_shader_parameter(k, float(d[k]))


func _build_mesh(portrait: Texture2D, face_mask: Texture2D, body_mask: Texture2D,
		hair_mask: Texture2D = null, wing_mask: Texture2D = null) -> ArrayMesh:
	var sz := Vector2(portrait.get_size())
	# 网格顶点用「以中心为原点」的局部坐标：这样 sign(VERTEX.x) 才是可靠的左右判据
	var half := sz * 0.5

	# 遮罩像素（用于烘焙权重）。取不到就退化为全零权重（等于不呼吸，不会崩）
	var body_img := _to_gray_image(body_mask)
	var face_img := _to_gray_image(face_mask)
	var hair_img := _to_gray_image(hair_mask)
	# 翅膀（第 5 通道）：null → 全 0，其它角色不受影响
	var wing_img := _to_gray_image(wing_mask)
	# 头部区域：face 遮罩只圈「脸」本身（三个人物实测只占画面 0.5~3.5%），
	# 直接拿它当 head_y 权重会让「头纵只带动脸心一小块，头顶/脖子不动」。
	# 用多轮模糊把脸扩张成「整颗头 + 颈」，头纵才有该有的影响范围。
	# 注意 face_img 保持原样给 face_gate 用（闸门必须精确到脸，不能扩张，
	# 否则会把压在脸边的头发也一起锁死）。
	var head_img := _dilate_mask(face_img)

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	## 第 5 权重（翅膀）：单独一条平行数组，最后烘进 CUSTOM0。
	## 为什么不用 PackedFloat32Array + SurfaceTool.set_custom：SurfaceTool 会把顶点
	## 重新排列（index() 去重），拿它当唯一构建路径就丢了「顶点顺序 = 行列扫描序」
	## 这个不变量。这里保持原来逐顶点 append 的写法，索引也手写，
	## 只是最后多用 SurfaceTool 走一遍（它才能正确声明 CUSTOM0 的格式位）。
	var wings := PackedFloat32Array()
	var indices := PackedInt32Array()

	for row in ROWS + 1:
		for col in COLS + 1:
			var u := float(col) / float(COLS)
			var v := float(row) / float(ROWS)
			# 局部坐标：中心原点，像素单位
			verts.append(Vector3((u - 0.5) * sz.x, (v - 0.5) * sz.y, 0.0))
			uvs.append(Vector2(u, v))
			# 权重采样（R=胸 G=腹 B=头 A=发）
			var w_body := _sample_gray(body_img, u, v)
			# 腹部取同一遮罩向下偏一点的位置：同一件衣服的下半，相位靠相位滞后区分
			var w_belly := _sample_gray(body_img, u, minf(v + 0.06, 1.0))
			var w_face := _sample_gray(face_img, u, v)
			var w_head := _sample_gray(head_img, u, v)
			var w_hair := _sample_gray(hair_img, u, v)
			# 翅膀权重（第 5 通道）。null 遮罩 → _sample_gray 返回 0 → 全 0，优雅降级。
			# 略微收紧（smoothstep）把遮罩羽化带压薄一点：翅膀是硬质羽毛，边缘太软
			# 会让「翅根跟着翅膀摆」的过渡带糊到身体上。
			var w_wing: float = smoothstep(0.0, 0.55, _sample_gray(wing_img, u, v))

			# ── 头部遮罩绝对优先（2026-11-10 主人反馈）────────────────────
			# 问题：刘海压在眼睛上，脸部 bbox 内 20~30% 的像素被 hair 遮罩判成白。
			#       这些像素同时拿头发权重和脸权重 → 发横/发纵一摆，眼睛跟着走。
			# 要求：**仅头纵影响双眼，头发完全不碰眼睛**。
			# 做法：face_gate 是「这是脸的内部（不是脸边）」的软闸门，它把该处的
			#       头发权重按比例压掉，并把被压掉的部分还给头颈通道。
			#       smoothstep(0.20, 0.50) 让脸边缘（羽化带）仍可与头发过渡，
			#       脸的实心内部（遮罩值 ≥ 0.5）则完全切断头发。
			#       门槛比上一版（0.25/0.60）更靠外：实测 kweno 还留了 1 个 0.059 的残余顶点，
			#       收紧到 0.5 后脸内彻底为 0。
			var face_gate: float = smoothstep(0.20, 0.50, w_face)
			var hair_kept: float = w_hair * (1.0 - face_gate)
			var hair_removed: float = w_hair - hair_kept
			w_hair = hair_kept
			# 头颈通道用**扩张后的头部区域**（脸 + 头顶 + 脖子），不是只有脸心：
			# 取 max(脸, 头部) 保证脸上永远是满权重，头部外圈由扩张层平滑收边。
			w_face = clampf(maxf(w_face, w_head * 0.85) + hair_removed * 0.65, 0.0, 1.0)

			# 环境层：三层遮罩都没盖住的区域（巨鲸、背景书廊等），给极轻权重。
			# 为什么需要：主体之外的大片区域若完全静止，视觉上像「人物贴纸在动、背景是照片」，
			# 商业立绘里连背景都有 1~2px 的呼吸感。权重压到主体 1/10 以下。
			var w_any: float = maxf(maxf(w_body, w_face), maxf(w_hair, w_wing))
			var w_env: float = clampf(1.0 - w_any * 1.6, 0.0, 1.0) * env_weight
			# 头发区域从躯干权重里扣除，避免同一像素既被胸口推又被头发拉。
			# 注意这里**不要**再乘一整套 inv_hair：脸已经被 face_gate 保住了，
			# 再拿头发去削脸会把「仅头纵影响双眼」这个要求又破坏掉。
			var inv_hair: float = 1.0 - w_hair * 0.85
			w_body *= inv_hair
			w_belly *= inv_hair
			# 翅膀（第 5 通道）同理从躯干里扣除：翅膀要的是**独立节奏**，
			# 若它还同时拿胸腔权重，画面里就是「胸的相位 + 翅膀的相位」叠加，
			# 合成出来的运动既不是胸也不是翅膀，看起来只是乱抖。
			# 实测 gpt：wing 遮罩与 body 遮罩重叠 84%（翅膀底下压着身体），
			# 且重叠区 body 权重均值 0.57 —— 不扣的话翅膀区域一半位移来自胸腔。
			var inv_wing: float = 1.0 - w_wing
			w_body *= inv_wing
			w_belly *= inv_wing
			# 环境权重并进「胸腔」通道的极小分量（复用同一条位移曲线，不额外加 cost）
			w_body = maxf(w_body, w_env)
			# 腹部与胸腔是同一区域的上下两半，避免叠加过猛 → 腹部权重压到 0.55
			colors.append(Color(w_body, w_belly * 0.55, w_face, w_hair))
			wings.append(w_wing)

	for row in ROWS:
		for col in COLS:
			var i := row * (COLS + 1) + col
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + COLS + 1)
			indices.append(i + 1)
			indices.append(i + COLS + 2)
			indices.append(i + COLS + 1)

	# ── 组装 ─────────────────────────────────────────────────────────────
	# 用 SurfaceTool 而不是 add_surface_from_arrays：只有 SurfaceTool 的
	# set_custom_format() 能把 CUSTOM0 的**格式位**写进 surface（add_surface_from_arrays
	# 要求 arrays.size() == ARRAY_MAX，多一个 ARRAY_FORMAT 槽位就被拒，实测建不出面）。
	# 用 add_vertex + add_index（不用 index()）：索引自己给，顶点顺序与数量原样保留，
	# 这样 weight_stats / 测试里「第 i 个顶点 ↔ 第 i 个 UV」的关系不变。
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_R_FLOAT)
	for i in verts.size():
		st.set_uv(uvs[i])
		st.set_color(colors[i])
		# CUSTOM0 是 R_FLOAT：只有 .x 有效，其余通道留 0
		st.set_custom(0, Color(wings[i], 0.0, 0.0, 0.0))
		st.add_vertex(verts[i])
	for k in indices:
		st.add_index(k)
	return st.commit()


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


## 把「脸」遮罩扩成「头部区域」：按脸的 bbox 做**几何扩张**，不是图像模糊。
##
## 为什么不用模糊：实测 face 遮罩只占画面 0.5~3.5%，降采样+多轮 blur 会把它摊到
## 接近零，归一化后形状已经糊没了（头顶权顶点只从 61 涨到 90/5335），而且纯 GDScript
## 三重循环要 1.3 秒，启动明显卡。
##
## 改用几何法：以脸的实心 bbox 为基准，向上/左右各扩一定比例（头顶+鬓角），
## 向下扩得更多（下巴到脖子）。所有比例都相对**脸自身尺寸**，所以能适应
## 四个角色完全不同的构图（deepseek 侧脸在左、qwen 大脸偏右、gpt/grok 小脸偏上）。
##
## 输出是椭圆形的软权重场：中心 1.0，边缘用 smoothstep 收到 0，不会出现硬边。
const HEAD_UP := 1.15      ## 向上扩：脸高的倍数（头顶 + 刘海区）
const HEAD_SIDE := 0.55    ## 左右扩：脸宽的倍数
const HEAD_DOWN := 0.55    ## 向下扩：脸高的倍数（下巴 → 脖子）
## 扩张区的强度上限：0.85 而不是 1.0 —— 外圈比脸心弱一点，
## 避免头纵在发际线外还拉满，把鬓角/耳朵一带拽出硬边。脸本身最后强制回 1.0。
const HEAD_DILATE_GAIN := 0.85

func _dilate_mask(img: Image) -> Image:
	if img == null:
		return null
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return null
	# 1) 找脸的实心 bbox（阈值 0.35：排除羽化边，只要芯）
	var x0 := w; var x1 := -1; var y0 := h; var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).r > 0.35:
				if x < x0: x0 = x
				if x > x1: x1 = x
				if y < y0: y0 = y
				if y > y1: y1 = y
	if x1 < 0:
		return null                       # 这张脸遮罩是空的，退回纯 face
	var fw := float(x1 - x0 + 1)
	var fh := float(y1 - y0 + 1)
	var cx := (float(x0) + float(x1)) * 0.5
	var cy := (float(y0) + float(y1)) * 0.5
	# 2) 扩张后的椭圆半轴（向上比向下多，因为头顶比脖子高）
	var rx: float = fw * (0.5 + HEAD_SIDE)
	var ry_up: float = fh * (0.5 + HEAD_UP)
	var ry_down: float = fh * (0.5 + HEAD_DOWN)
	# 3) 逐像素写椭圆权重（只在扩张框内算，框外全黑，省掉全图遍历）
	var out := Image.create(w, h, false, Image.FORMAT_L8)
	out.fill(Color(0, 0, 0, 1))
	var bx0: int = maxi(0, int(cx - rx) - 1)
	var bx1: int = mini(w - 1, int(cx + rx) + 1)
	var by0: int = maxi(0, int(cy - ry_up) - 1)
	var by1: int = mini(h - 1, int(cy + ry_down) + 1)
	for y2 in range(by0, by1 + 1):
		var ry: float = ry_up if float(y2) < cy else ry_down
		for x2 in range(bx0, bx1 + 1):
			var dx: float = (float(x2) - cx) / maxf(rx, 1.0)
			var dy: float = (float(y2) - cy) / maxf(ry, 1.0)
			var d2: float = dx * dx + dy * dy
			if d2 >= 1.0:
				continue
			# 椭圆内：中心 1，边缘 0；用 1-d² 再 smoothstep 让边更软
			var t: float = 1.0 - d2
			var wt: float = smoothstep(0.0, 1.0, t)
			var v: float = wt * HEAD_DILATE_GAIN
			out.set_pixel(x2, y2, Color(v, v, v, 1.0))
	# 4) 脸上原来的实心区强制回 1.0（扩张层只负责外圈，不能把脸本身打折）
	for y3 in range(y0, y1 + 1):
		for x3 in range(x0, x1 + 1):
			var fv: float = img.get_pixel(x3, y3).r
			if fv > 0.35:
				out.set_pixel(x3, y3, Color(1.0, 1.0, 1.0, 1.0))
	return out


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


## 环境层权重（0 = 背景完全不动；改完需要重建网格才生效）
func set_env_weight(w: float) -> void:
	env_weight = clampf(w, 0.0, 0.5)
	# 权重烘在顶点色里，必须重建 mesh
	if _tex_ref != null and _face_ref != null and _body_ref != null:
		mesh = _build_mesh(_tex_ref, _face_ref, _body_ref, _hair_ref, _wing_ref)


## 底部锁定比例
func set_lock_bottom(v: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("lock_bottom", clampf(v, 0.0, 0.5))


## 读回全部 V4 参数（面板回填 / 测试用）
## wing_x/wing_y/wing_lag_deg 是第 5 通道（2026-11-11）：它们的 uniform 一直存在，
## 但只有 chatppt 有翅膀权重，其余角色读到值也不产生任何位移。
func get_v4_params() -> Dictionary:
	var out := {}
	if _mat == null:
		return out
	for k in ["amp", "chest_x", "chest_y", "belly_x", "belly_y", "head_y",
			"hair_x", "hair_y", "belly_lag_deg", "head_lag_deg",
			"hair_lag_per_height", "lock_bottom", "x_lag_deg", "y_bias",
			"use_horiz", "env_weight",
			"wing_x", "wing_y", "wing_lag_deg"]:
		var v = _mat.get_shader_parameter(k)
		if v != null:
			out[k] = v
	# env_weight 不是 uniform（烘在顶点色里），单独补上
	out["env_weight"] = env_weight
	return out


## 一次性设多个 V4 参数（面板拖动用）
func set_v4_param(key: String, value: float) -> void:
	if _mat == null:
		return
	if key == "env_weight":
		set_env_weight(value)
	elif key == "use_horiz":
		_mat.set_shader_parameter(key, value > 0.5)
	else:
		_mat.set_shader_parameter(key, value)


func set_lag(belly_deg: float, head_deg: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("belly_lag_deg", belly_deg)
	_mat.set_shader_parameter("head_lag_deg", head_deg)


## 顶点权重统计（测试/调试用）：返回 {max_chest, max_belly, max_head, max_hair, max_wing}
## max_hair 是顶点色 A 通道（不是 _mask_hair 的存在性）；max_wing 读 CUSTOM0（第 5 通道）。
## 两个都从**建好的 mesh** 读，不是从配置读 —— 断言的是「真正送进 GPU 的东西」。
func weight_stats() -> Dictionary:
	var m := mesh
	if m == null or m.get_surface_count() == 0:
		return {"max_chest": 0.0, "max_belly": 0.0, "max_head": 0.0,
				"max_hair": 0.0, "max_wing": 0.0}
	var arr := m.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var mc := 0.0
	var mb := 0.0
	var mh := 0.0
	var mr := 0.0
	for c in cols:
		mc = maxf(mc, c.r)
		mb = maxf(mb, c.g)
		mh = maxf(mh, c.b)
		mr = maxf(mr, c.a)
	# 第 5 通道可能不存在（旧网格 / 万一 SurfaceTool 没带 format）→ 报 0 而不是崩
	var mw := 0.0
	var cus = arr[Mesh.ARRAY_CUSTOM0]
	if cus != null and cus.size() > 0:
		# R_FLOAT → 每顶点 1 个 float
		var stride: int = cus.size() / maxi(cols.size(), 1)
		if stride >= 1:
			for i in range(0, cus.size(), stride):
				mw = maxf(mw, float(cus[i]))
	return {"max_chest": mc, "max_belly": mb, "max_head": mh,
			"max_hair": mr, "max_wing": mw}
