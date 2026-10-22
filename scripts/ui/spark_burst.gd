class_name SparkBurst
extends Control
## 出牌命中时的**硬边像素方块爆散**。
##
## 像素风纪律（踩坑手册 22）：只用实心方块，不贴纹理、不做模糊、不做渐变光晕。
## 每块是一个 3~5px 的方片，带初速 + 重力，生命周期内线性淡出，结束自毁。

const LIFE := 0.46
const GRAVITY := 980.0

var _pos: Array[Vector2] = []
var _vel: Array[Vector2] = []
var _size: Array[float] = []
var _color: Color = Color.WHITE
var _t := 0.0


## 在 parent 的坐标 (at) 处炸一簇方块。返回实例（调用方一般不用管，自己会 free）
static func burst(parent: Node, at: Vector2, color: Color, count: int = 16,
		speed: float = 260.0) -> SparkBurst:
	var b := SparkBurst.new()
	b.name = "SparkBurst"
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b._color = color
	for i in count:
		var ang := randf_range(-PI, 0.0)          # 主要往上炸
		var sp := speed * randf_range(0.45, 1.0)
		b._pos.append(at)
		b._vel.append(Vector2(cos(ang), sin(ang)) * sp + Vector2(randf_range(-40, 40), 0))
		b._size.append(randf_range(3.0, 6.0))
	parent.add_child(b)
	return b


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	for i in _pos.size():
		_vel[i].y += GRAVITY * delta
		_pos[i] += _vel[i] * delta
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - _t / LIFE
	var a := clampf(k * 1.6, 0.0, 1.0)
	for i in _pos.size():
		var s := _size[i] * (0.4 + 0.6 * k)
		draw_rect(Rect2(_pos[i] - Vector2(s, s) * 0.5, Vector2(s, s)),
				Color(_color.r, _color.g, _color.b, a))
