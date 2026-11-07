class_name CardFace
extends RefCounted
## 卡面程序化渲染（圆桌第 3 轮：砍 SVG 改 card_face.json 的落地实现）。
##
## 输入是**语义 token**，不是图形代码：
##   {"bg":"#0B0F1A","primary":"#C84C4C","accent":"#FFD166",
##    "silhouette":"creature|shield|weapon|void|machine|orb","density":0.5}
##
## 为什么改成 token：SVG 是 token 大户（实测一张卡 ~3000 token），而卡面只需要
## "什么颜色的什么形状的什么氛围"。客户端按主题映射即可，模型输出降到几百 token。
##
## 注意：这条通道是**可选**的。主人此前钦定"通用大模型用自己的绘图能力输出 SVG"
## （见 godot-svg-runtime-render 记忆），所以默认仍走 SVG；本类提供第二条路，
## 模型返回 face 字段时优先用它。

const SIZE := 256          ## 内部渲染分辨率（再放大到 512，省一半以上像素循环）
const DEFAULT_BG := "#0B0F1A"
const DEFAULT_PRIMARY := "#4FA3E0"
const DEFAULT_ACCENT := "#FFD166"
const SILHOUETTES := ["creature", "shield", "weapon", "void", "machine", "orb"]


static func parse_face(raw) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var sil := String(raw.get("silhouette", "orb")).strip_edges().to_lower()
	if not SILHOUETTES.has(sil):
		sil = "orb"
	return {
		"bg": _color(raw.get("bg"), DEFAULT_BG),
		"primary": _color(raw.get("primary"), DEFAULT_PRIMARY),
		"accent": _color(raw.get("accent"), DEFAULT_ACCENT),
		"silhouette": sil,
		"density": clampf(float(raw.get("density", 0.5)), 0.0, 1.0),
	}


static func _color(v, fallback: String) -> Color:
	## 幂等：已经解析成 Color 的（parse_face 的输出再喂回来）直接返回
	if v is Color:
		return v
	var s := str(v).strip_edges()
	if s.is_valid_html_color():
		return Color(s)
	return Color(fallback)


## 渲染成 Image（默认 512×512，铺底色）
static func render(face: Dictionary, target := 512) -> Image:
	var f := parse_face(face)
	var bg: Color = f["bg"]
	var pri: Color = f["primary"]
	var acc: Color = f["accent"]
	var sil := String(f["silhouette"])
	var dens := float(f["density"])

	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var cx := SIZE * 0.5
	var cy := SIZE * 0.5
	var R := SIZE * 0.40
	for y in SIZE:
		for x in SIZE:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy) / R
			## 背景 + 中心辉光
			var c := bg
			var glow := clampf(1.0 - d, 0.0, 1.0)
			c = c.lerp(pri, glow * glow * 0.55)
			## 剪影（按 token 走不同距离函数）
			var inside := false
			match sil:
				"creature":
					var lobe := 1.0 + 0.18 * sin(atan2(dy, dx) * 3.0 + 1.2)
					inside = d < 0.62 * lobe
				"shield":
					inside = d < 0.70 and dy < 0.35 * R and abs(dx) < (0.72 - 0.45 * (dy / R)) * R
				"weapon":
					inside = abs(dx * 0.7 + dy * 0.7) < R * 0.13 and d < 0.85
				"void":
					inside = d < 0.72 and d > 0.42
				"machine":
					var ax: float = absf(dx) / R
					var ay: float = absf(dy) / R
					inside = (ax + ay * 0.58) < 0.78
				_:
					inside = d < 0.55
			if inside:
				c = c.lerp(pri, 0.78)
				## 内部高光
				var hi := clampf(1.0 - abs(d - 0.32) * 3.2, 0.0, 1.0)
				c = c.lerp(acc, hi * 0.22)
			## 点缀：按 density 数量撒小点（确定性，不用随机）
			var n := int(6.0 + dens * 10.0)
			for k in n:
				var ang := float(k) * 2.39996
				var rad := (0.30 + 0.55 * fmod(float(k) * 0.37, 1.0)) * R
				var px := cx + cos(ang) * rad
				var py := cy + sin(ang) * rad
				if (float(x) - px) * (float(x) - px) + (float(y) - py) * (float(y) - py) < 2.2:
					c = c.lerp(acc, 0.85)
			img.set_pixel(x, y, c)
	if target != SIZE:
		img.resize(target, target, Image.INTERPOLATE_LANCZOS)
	return img


## 渲染并存盘；成功返回路径，失败返回空串
static func render_png(face: Dictionary, out_path: String, target := 512) -> String:
	var img := render(face, target)
	if img == null or img.get_width() <= 0:
		return ""
	var dir := out_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return out_path if img.save_png(out_path) == OK else ""
