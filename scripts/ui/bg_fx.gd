class_name BgFx
extends Control
## 背景环境动效：**漂浮像素尘埃 + 缓慢扫描线 + 鼠标视差**。
##
## 像素风纪律（踩坑手册 22）：只用 1~2px 的实心方块与横线，不贴纹理、
## 不做模糊 / 光晕 / 渐变。整体极低调（alpha ≤ 0.35），作用是"画面在呼吸"，
## 不能抢卡牌和数字的注意力。
##
## 用法（叠在背景图与压暗层之上、HUD 之下）：
##     var fx := BgFx.new()
##     add_child(fx)
##     fx.setup(size)
## 尺寸变化时重新 setup() 即可（内部会按比例重铺尘埃）。

const MOTE_COUNT := 34
const SCAN_LINES := 3
const PARALLAX := 5.0          ## 视差最大位移（像素，整数保证不糊）
const MOTE_COLORS := [
	Color(0.31, 0.76, 0.97),   # ACCENT
	Color(1.0, 0.82, 0.40),    # GOLD
	Color(0.56, 0.61, 0.71),   # TEXT_DIM
]

var _motes: Array[Dictionary] = []
var _scan: Array[Dictionary] = []
var _t := 0.0
var _par := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


## 按当前尺寸重铺尘埃与扫描线
func setup(area: Vector2) -> void:
	_motes.clear()
	for i in MOTE_COUNT:
		_motes.append(_new_mote(area, true))
	_scan.clear()
	for i in SCAN_LINES:
		_scan.append({
			"y": (float(i) + 0.5) / float(SCAN_LINES) * area.y,
			"speed": 6.0 + float(i) * 3.0,
			"alpha": 0.05 + float(i) * 0.012,
		})
	queue_redraw()


func _new_mote(area: Vector2, anywhere: bool) -> Dictionary:
	return {
		"pos": Vector2(randf() * area.x,
				randf() * area.y if anywhere else area.y + randf() * 40.0),
		"vel": Vector2(randf_range(-4.0, 4.0), randf_range(-14.0, -4.0)),
		"size": 1.0 if randf() < 0.65 else 2.0,
		"color": MOTE_COLORS[randi() % MOTE_COLORS.size()],
		"phase": randf() * TAU,
		"alpha": randf_range(0.10, 0.32),
	}


func _process(delta: float) -> void:
	_t += delta
	var area := size

	# 尘埃：缓慢上浮，出顶后从底部重生
	for i in _motes.size():
		var m: Dictionary = _motes[i]
		var p: Vector2 = m["pos"] + (m["vel"] as Vector2) * delta
		if p.y < -8.0 or p.x < -8.0 or p.x > area.x + 8.0:
			_motes[i] = _new_mote(area, false)
			continue
		m["pos"] = p

	# 扫描线：匀速下移，出底回顶
	for s in _scan:
		s["y"] = float(s["y"]) + float(s["speed"]) * delta
		if float(s["y"]) > area.y:
			s["y"] = -2.0

	# 视差：鼠标偏离屏幕中心的量 → 整数像素偏移（像素风不做亚像素）
	var target := Vector2.ZERO
	if area.x > 1.0 and area.y > 1.0:
		var mid := area * 0.5
		var d := (get_local_mouse_position() - mid) / mid
		target = Vector2(roundf(clampf(d.x, -1.0, 1.0) * PARALLAX),
				roundf(clampf(d.y, -1.0, 1.0) * PARALLAX))
	_par = _par.lerp(target, minf(1.0, delta * 3.0))
	_par = Vector2(roundf(_par.x), roundf(_par.y))
	position = _par * 0.5

	queue_redraw()


func _draw() -> void:
	var area := size

	# 扫描线（先画，压在尘埃下面）
	for s in _scan:
		draw_rect(Rect2(Vector2(0, roundf(float(s["y"]))), Vector2(area.x, 1)),
				Color(0.31, 0.76, 0.97, float(s["alpha"])))

	# 漂浮尘埃：亮度按正弦呼吸，像远处在闪的数据点
	for m in _motes:
		var tw := 0.72 + 0.28 * sin(_t * 1.7 + float(m["phase"]))
		var a := float(m["alpha"]) * tw
		var s2 := float(m["size"])
		var p: Vector2 = m["pos"]
		draw_rect(Rect2(Vector2(roundf(p.x), roundf(p.y)), Vector2(s2, s2)),
				Color((m["color"] as Color).r, (m["color"] as Color).g,
						(m["color"] as Color).b, a))
