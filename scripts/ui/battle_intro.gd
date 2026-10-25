class_name BattleIntro
extends SubViewportContainer
## 战斗进场转场：2D → 真 3D → 2D（2026-10-26 主人钦定）。
##
## 演出（约 2.4 秒，点任意处跳过）：
##   ① 全屏暗幕淡入（2D 战斗 UI 已就位但手牌/敌人未现身）
##   ② 手牌变成 3D 贴片卡在镜头前翻飞散开；敌人贴图从深处加速冲向镜头
##   ③ 3D 层整体淡出，交给 arena 在 2D 里弹出真手牌、砸落敌人
##
## 实现：SubViewportContainer + SubViewport(3D, transparent_bg) 叠在战斗界面上，
## 卡面纹理由 arena 预合成（框+立绘）传入；材质 UN_SHADED 保持像素硬边。

signal finished

const DUR_DARKEN := 0.30        # ① 暗幕
const DUR_FLY := 0.95           # ② 3D 翻飞
const DUR_ENEMY := 1.05         # ② 敌人冲刺（与翻飞重叠）
const DUR_FADE := 0.35          # ③ 收拢淡出
const CARD_W3 := 1.5
const CARD_H3 := 2.26
const ENEMY_W3 := 2.3
const ENEMY_H3 := 2.68

var _vp: SubViewport = null
var _root3d: Node3D = null
var _cam: Camera3D = null
var _tw: Tween = null
var _done := false
var _on_done: Callable = Callable()


## card_textures：预合成的整卡贴图（框+立绘）；enemy_tex：敌人像素贴图
func play(card_textures: Array, enemy_tex: Texture2D, on_done: Callable) -> void:
	_on_done = on_done
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_stretch_to_self()

	_root3d = Node3D.new()
	_vp.add_child(_root3d)

	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.position = Vector3(0, 0, 0)
	_root3d.add_child(_cam)

	# ① 暗幕
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.color = Color(0.012, 0.02, 0.04, 0.0)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	_tw = create_tween()
	_tw.tween_property(veil, "color:a", 0.68, DUR_DARKEN)

	# ② 手牌 3D 翻飞
	var n := card_textures.size()
	for i in n:
		var quad := _make_quad(card_textures[i], Vector2(CARD_W3, CARD_H3))
		var spread_x := (float(i) - float(n - 1) * 0.5) * 0.92
		quad.position = Vector3(randf_range(-3.2, 3.2), randf_range(-1.8, 1.8), -7.5)
		quad.rotation = Vector3(randf_range(-0.7, 0.7), randf_range(-0.9, 0.9), randf_range(-0.4, 0.4))
		_root3d.add_child(quad)
		var fly := quad.create_tween()
		fly.set_parallel(true)
		fly.tween_property(quad, "position",
				Vector3(spread_x, -0.25, -3.6), DUR_FLY).set_delay(DUR_DARKEN + i * 0.05) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		fly.tween_property(quad, "rotation",
				Vector3(0.0, spread_x * 0.22, 0.0), DUR_FLY).set_delay(DUR_DARKEN + i * 0.05) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 敌人从深处冲脸
	if enemy_tex != null:
		var foe := _make_quad(enemy_tex, Vector2(ENEMY_W3, ENEMY_H3))
		foe.position = Vector3(1.6, -0.1, -14.0)
		foe.rotation = Vector3(0.0, -0.7, 0.0)
		_root3d.add_child(foe)
		var rush := foe.create_tween()
		rush.set_parallel(true)
		rush.tween_property(foe, "position", Vector3(0.35, -0.35, -5.6), DUR_ENEMY) \
			.set_delay(DUR_DARKEN + 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		rush.tween_property(foe, "rotation", Vector3(0.0, 0.12, 0.0), DUR_ENEMY) \
			.set_delay(DUR_DARKEN + 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 相机：FOV 张开（"突然转 3D"的纵深感）再回一点
	_tw.tween_property(_cam, "fov", 52.0, 0.5).set_delay(DUR_DARKEN) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_cam, "fov", 46.0, DUR_ENEMY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# ③ 收拢：3D 对象整体拉近放大冲出画面 + 容器淡出
	for c in _root3d.get_children():
		if c is MeshInstance3D and c != _cam:
			var pull := (c as Node3D).create_tween()
			pull.tween_property(c, "position:z", -1.4, DUR_FADE).set_delay(DUR_DARKEN + DUR_ENEMY - 0.15) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var total := DUR_DARKEN + DUR_ENEMY + DUR_FADE
	_tw.tween_property(self, "modulate:a", 0.0, DUR_FADE).set_delay(total - DUR_FADE)
	_tw.tween_callback(_finish).set_delay(total)

	gui_input.connect(_on_gui)


func _stretch_to_self() -> void:
	if _vp != null:
		_vp.size = size
	resized.connect(func() -> void:
		if _vp != null and is_instance_valid(_vp):
			_vp.size = size)


func _make_quad(tex: Texture2D, quad_size: Vector2) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = quad_size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _on_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		skip()


## 跳过：立刻走完收尾回调（queue_free 会顺带停掉所有子节点 tween）
func skip() -> void:
	if _done:
		return
	if _tw != null and _tw.is_valid():
		_tw.kill()
	modulate.a = 0.0
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	if _on_done.is_valid():
		_on_done.call()
	queue_free()


## 测试钩子：是否已结束
func debug_done() -> bool:
	return _done
