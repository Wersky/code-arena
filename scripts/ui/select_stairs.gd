class_name SelectStairs
extends Node3D
## 选角楼梯秀场：相机放在台阶底部往上仰，四位 AI 娘分立两侧台阶上待选。
##
## 素材是 2D 立绘，所以楼梯/灯光/雾是真 3D（透视与景深由引擎给出），
## 角色用 Sprite3D 贴片 + billboard（永远面向相机），不必建模。
##
## 交互：←/→ 或 ↑/↓ 切换，Enter/Space 确认，点击角色直接选中，再点一次确认。
## 确认后发出 selected(ai_id)，由 main.gd 接管进入战斗。

signal selected(ai_id: String)

const STEP_H := 0.30          ## 每级台阶高度
const STEP_D := 1.05          ## 每级台阶进深
const STEP_W := 3.4           ## 台阶宽
const CHAR_H := 2.05          ## 角色身高（世界单位）

## id / 名字 / 一句人设 / 图 / 左右(-1左 1右) / 站第几级台阶
const ROSTER := [
	["deepseek", "DeepSeek", "蓝发女仆 · 鲸鱼围裙 · 傲娇嘴硬", "deepseek", -1, 3],
	["qwen", "Qwen", "千问 · 阿里家的元气大小姐 · 手持折扇", "qwen", 1, 6],
	["gpt", "GPT", "OpenAI 大小姐 · 白龙长裙 · 硅谷顶流千金", "gpt", -1, 10],
	["grok", "Grok", "马斯克家的毒舌千金 · 金发黄毛雌小鬼", "grok", 1, 14],
]

var _chars: Array[Dictionary] = []
var _sel := 0
var _ring: MeshInstance3D
var _cam: Camera3D
var _title: Label
var _hint: Label
var _tagline: Label
var _t := 0.0


func _ready() -> void:
	_build_env()
	_build_stairs()
	_build_roster()
	_build_ui()
	_select(0)


func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.035, 0.05, 0.10)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.55, 0.80)
	e.ambient_light_energy = 0.75
	# 雾让远处的台阶自然没入黑暗，仰视的纵深感就出来了
	e.fog_enabled = true
	e.fog_light_color = Color(0.05, 0.07, 0.14)
	e.fog_depth_begin = 6.0
	e.fog_depth_end = 26.0
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.light_color = Color(0.85, 0.9, 1.0)
	key.light_energy = 1.1
	key.rotation_degrees = Vector3(-32.0, 24.0, 0.0)
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.45, 0.65, 1.0)
	rim.light_energy = 0.8
	rim.rotation_degrees = Vector3(40.0, -150.0, 0.0)
	add_child(rim)

	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.position = Vector3(0.0, 0.95, -3.2)
	add_child(_cam)
	# look_at 必须在入树之后调，否则 Godot 报 "!is_inside_tree()"
	_cam.look_at(Vector3(0.0, 3.6, 8.5), Vector3.UP)
	_cam.current = true


func _build_stairs() -> void:
	var mat_a := _mat(Color(0.17, 0.21, 0.32))
	var mat_b := _mat(Color(0.13, 0.16, 0.26))
	for i in 22:
		var s := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(STEP_W, STEP_H, STEP_D)
		s.mesh = box
		s.material_override = mat_a if i % 2 == 0 else mat_b
		s.position = Vector3(0.0, float(i) * STEP_H - STEP_H * 0.5, float(i) * STEP_D)
		add_child(s)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.92
	return m


func _build_roster() -> void:
	for i in ROSTER.size():
		var d: Array = ROSTER[i]
		var tex := load("res://assets/art/select/%s.png" % d[3]) as Texture2D
		var sp := Sprite3D.new()
		sp.texture = tex
		sp.pixel_size = CHAR_H / float(maxi(1, tex.get_height()))
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sp.shaded = false
		var root := Node3D.new()
		root.position = Vector3(float(d[4]) * 2.05, float(d[5]) * STEP_H, float(d[5]) * STEP_D)
		add_child(root)
		root.add_child(sp)
		sp.position.y = CHAR_H * 0.5

		var name_label := Label3D.new()
		name_label.text = d[1]
		name_label.font_size = 48
		name_label.pixel_size = 0.0055
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = true
		name_label.modulate = Color(0.78, 0.88, 1.0)
		name_label.outline_size = 12
		name_label.outline_modulate = Color(0.02, 0.04, 0.08)
		name_label.position = Vector3(0.0, CHAR_H + 0.22, 0.0)
		root.add_child(name_label)

		# 点击热区：跟着角色走的盒子
		var area := Area3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.3, CHAR_H, 0.6)
		col.shape = shape
		col.position.y = CHAR_H * 0.5
		area.add_child(col)
		root.add_child(area)
		area.input_event.connect(_on_char_click.bind(i))

		_chars.append({
			"id": d[0], "name": d[1], "tag": d[2], "root": root,
			"sprite": sp, "base_y": float(d[5]) * STEP_H, "side": float(d[4]),
		})

	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.80
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.35, 0.75, 1.0)
	rm.emission_enabled = true
	rm.emission = Color(0.25, 0.6, 1.0)
	rm.emission_energy_multiplier = 2.2
	_ring.material_override = rm
	add_child(_ring)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_title = _label("选 择 你 的 对 手", 30, Vector2(0, 40))
	_hint = _label("← → 切换    Enter 确认    点击角色直接选中", 18, Vector2(0, -46))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.position.y = -46
	_tagline = _label("", 22, Vector2(0, -96))
	_tagline.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_tagline.position.y = -96
	for l in [_title, _hint, _tagline]:
		layer.add_child(l)


func _label(text: String, px: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0))
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	l.position = pos
	return l


func _process(delta: float) -> void:
	_t += delta
	_cam.position.x = sin(_t * 0.35) * 0.06
	for i in _chars.size():
		var c: Dictionary = _chars[i]
		var r: Node3D = c["root"]
		r.position.y = float(c["base_y"]) + sin(_t * 1.6 + float(i) * 1.3) * 0.035
		var want := 1.06 if i == _sel else 1.0
		r.scale = r.scale.lerp(Vector3.ONE * want, delta * 8.0)
	_ring.position.y = _ring.position.y + sin(_t * 3.0) * 0.002
	if _ring != null:
		_ring.rotation.y = _t * 0.8


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_select(_sel - 1)
			KEY_RIGHT, KEY_D:
				_select(_sel + 1)
			KEY_UP, KEY_W:
				_select(_sel - 2)
			KEY_DOWN, KEY_S:
				_select(_sel + 2)
			KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
				_confirm()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()


func _select(i: int) -> void:
	_sel = posmod(i, _chars.size())
	var c: Dictionary = _chars[_sel]
	_ring.position = Vector3(c["root"].position.x, float(c["base_y"]) + 0.03, c["root"].position.z)
	_tagline.text = "%s   ·   %s" % [c["name"], c["tag"]]
	_tagline.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))


func _confirm() -> void:
	selected.emit(String(_chars[_sel]["id"]))


func _on_char_click(cam: Node, event: InputEvent, pos: Vector3, normal: Vector3, shape: int, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if idx == _sel:
			_confirm()
		else:
			_select(idx)
