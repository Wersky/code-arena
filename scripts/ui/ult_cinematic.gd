class_name UltCinematic
extends Control
## 终结技「深度思考」全屏演出 v2（2026-11-04 主人钦定顺序）：
##
##   ① 黑幕+代码雨 → ② 中央出现一条裂痕（此时什么都看不见，裂痕自上而下延伸）
##   → ③ **裂痕撕开**（封印黑幕像纸一样被撕成两片移开）
##   → ④ **大女仆从裂痕里显现**（她一直站在裂痕后面，撕开才看得见）+ 光柱
##   → ⑤ 女仆绷紧，她自己的立绘像纸片从中间撕开
##   → ⑥ **大肥鱼得意脸**带星芒闪亮登场 → ⑦ 爆发特效 + 大字结算。
##
## 素材：ult-paper-left/right（封印黑纸，撕缝贴主人手绘稿）、ult-ds-full（完整立绘）、
## ult-ds-left/right（立绘撕裂两半）、ult-dafish（得意鲸鱼脸）。
## 伤害结算时机由 `hit_moment` 通知（arena 在此时机 cast_ult + 震屏）。

signal hit_moment
signal finished

const W := 1600.0
const H := 900.0
const SCALE := 0.8                       # 素材显示缩放（统一 0.8）
const PAPER_W := 720.0                   # 900×880 ×0.8
const PAPER_H := 704.0
const ART_W := 608.0                     # 760×820 ×0.8（立绘撕开画布）
const ART_H := 656.0
const MAID_W := 441.0                    # 551×780 ×0.8（完整立绘）
const MAID_H := 624.0
const FISH_W := 320.0
const FISH_H := 300.0
const PAPER_DX := 320.0                  # 黑纸撕开的稳态位移
const PAPER_OVER := 360.0                # 黑纸过冲
const TEAR_DX := 150.0                   # 立绘撕开稳态
const TEAR_OVER := 196.0                 # 立绘过冲
const TEAR_SQUEEZE := 12.0
const TEAR_ROT := 0.10
const CYAN := Color(0.45, 0.88, 1.0)
const CYAN_HOT := Color(0.78, 0.95, 1.0)

var _dim: ColorRect
var _rain: CodeRain
var _grid: AttentionGrid
var _maid: TextureRect                   # 完整立绘（裂痕后面）
var _paper_l: TextureRect                # 封印黑纸两半（盖住女仆）
var _paper_r: TextureRect
var _paper_crack: CrackLine              # 黑纸上的裂痕
var _body_crack: CrackLine               # 立绘上的裂痕（第二段）
var _left: TextureRect                   # 立绘撕裂两半
var _right: TextureRect
var _fish: TextureRect
var _star: Starburst
var _burst: CPUParticles2D
var _flash: ColorRect
var _title: Label
var _sub: Label

var _cx := W * 0.5
var _cy := H * 0.46


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layers()
	_run_sequence()


func _build_layers() -> void:
	_rain = CodeRain.new()
	_rain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rain)

	_grid = AttentionGrid.new()
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.modulate.a = 0.0
	add_child(_grid)

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.008, 0.012, 0.025, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	# ④ 裂痕后面的女仆（初始不可见——黑纸盖着她）
	_maid = _rect_sprite("res://assets/art/ult-ds-full.png",
			Vector2(MAID_W, MAID_H), Vector2(_cx - MAID_W * 0.5, _cy - MAID_H * 0.5))
	_maid.modulate.a = 0.0

	# ③ 封印黑纸两半（撕缝贴主人手绘稿：上段波浪下段锯齿）
	var px := _cx - PAPER_W * 0.5
	var py := _cy - PAPER_H * 0.5
	_paper_l = _rect_sprite("res://assets/art/ult-paper-left.png",
			Vector2(PAPER_W, PAPER_H), Vector2(px, py))
	_paper_r = _rect_sprite("res://assets/art/ult-paper-right.png",
			Vector2(PAPER_W, PAPER_H), Vector2(px, py))
	_paper_l.pivot_offset = Vector2(PAPER_W, PAPER_H * 0.5)
	_paper_r.pivot_offset = Vector2(0.0, PAPER_H * 0.5)

	# ② 黑纸上的裂痕（先于撕开出现）
	_paper_crack = CrackLine.new()
	_paper_crack.setup(_load_path("res://assets/art/ult-paper-path.json"))
	_paper_crack.position = Vector2(px, py)
	_paper_crack.modulate.a = 0.0
	add_child(_paper_crack)

	# ⑤ 立绘撕裂两半（初始藏起，切进来时与 full 视觉无缝）
	_left = _rect_sprite("res://assets/art/ult-ds-left.png",
			Vector2(ART_W, ART_H), Vector2(_cx - ART_W * 0.5, _cy - ART_H * 0.5))
	_right = _rect_sprite("res://assets/art/ult-ds-right.png",
			Vector2(ART_W, ART_H), Vector2(_cx - ART_W * 0.5, _cy - ART_H * 0.5))
	_left.visible = false
	_right.visible = false
	_left.pivot_offset = Vector2(ART_W, ART_H * 0.5)
	_right.pivot_offset = Vector2(0.0, ART_H * 0.5)
	_body_crack = CrackLine.new()
	_body_crack.setup(_load_path("res://assets/art/ult-tear-path.json"))
	_body_crack.position = Vector2(_cx - ART_W * 0.5, _cy - ART_H * 0.5)
	_body_crack.modulate.a = 0.0
	add_child(_body_crack)

	# ⑥ 星芒 + 大肥鱼
	_star = Starburst.new()
	_star.size = Vector2(FISH_W * 2.1, FISH_H * 2.1)
	_star.position = Vector2(_cx - _star.size.x * 0.5, _cy - _star.size.y * 0.5)
	_star.modulate.a = 0.0
	_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_star)

	_fish = TextureRect.new()
	_fish.texture = _tex("res://assets/art/ult-dafish.png")
	_fish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fish.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fish.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fish.size = Vector2(FISH_W, FISH_H)
	_fish.position = Vector2(_cx - FISH_W * 0.5, _cy - FISH_H * 0.52)
	_fish.pivot_offset = Vector2(FISH_W * 0.5, FISH_H * 0.55)
	_fish.scale = Vector2(0.06, 0.06)
	_fish.visible = false
	_fish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fish)

	_burst = CPUParticles2D.new()
	_burst.position = Vector2(_cx, _cy)
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 150
	_burst.lifetime = 0.9
	_burst.explosiveness = 0.95
	_burst.spread = 180.0
	_burst.gravity = Vector2(0, 60)
	_burst.initial_velocity_min = 260.0
	_burst.initial_velocity_max = 680.0
	_burst.scale_amount_min = 2.0
	_burst.scale_amount_max = 5.0
	_burst.color = CYAN
	add_child(_burst)

	_title = _big_label("深度思考 · 推理完成", 46, CYAN_HOT, _cy - 300.0)
	_sub = _big_label("—— 新角色：大肥鱼，参上！ ——", 20, Color(0.6, 0.85, 1.0), _cy - 244.0)
	for l in [_title, _sub]:
		l.visible = false
		add_child(l)

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)


func _rect_sprite(path: String, disp: Vector2, pos: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _tex(path)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.size = disp
	r.position = pos
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _load_path(json_path: String) -> PackedVector2Array:
	## 撕缝路径 JSON（素材切割时导出），×SCALE 换算显示坐标
	var pts := PackedVector2Array()
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		pts.append(Vector2.ZERO)
		pts.append(Vector2(0, 700))
		return pts
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for p in data.get("points", []):
		pts.append(Vector2(float(p["x"]) * SCALE, float(p["y"]) * SCALE))
	return pts


func _big_label(text: String, fs: int, col: Color, y: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PixelTheme.font())
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.12))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(W, fs + 14)
	l.position = Vector2(0, y)
	l.pivot_offset = Vector2(W * 0.5, (fs + 14) * 0.5)
	l.scale = Vector2(0.2, 0.2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


## 演出主时序（总约 6s）。arena 侧 await hit_moment 结算伤害 + 震屏。
func _run_sequence() -> void:
	var px0 := _paper_l.position.x      # 黑纸拼合位
	var rx0 := _paper_r.position.x
	var lx0 := _left.position.x         # 立绘拼合位

	# ① t=0 黑幕 + 代码雨 + 充能音
	SfxNode.play("fx_ult_charge")
	_rain.start()
	create_tween().tween_property(_dim, "color:a", 0.9, 0.3)
	await _wait(0.4)

	# ② t≈0.4 裂痕在封印纸上自上而下延伸（张力：越裂越快 + 纸面抖动）
	SfxNode.play("fx_ult_strain")
	_paper_crack.modulate.a = 1.0
	_paper_crack.progress = 0.0
	var strain := create_tween()
	for i in 5:
		var amp := 1.0 + i * 0.5
		strain.tween_property(_paper_l, "scale:x", 1.0 + 0.012 * amp, 0.09)
		strain.parallel().tween_property(_paper_r, "scale:x", 1.0 + 0.012 * amp, 0.09)
		strain.tween_property(_paper_l, "scale:x", 1.0 - 0.008 * amp, 0.07)
		strain.parallel().tween_property(_paper_r, "scale:x", 1.0 - 0.008 * amp, 0.07)
	var crack_tw := create_tween()
	crack_tw.tween_property(_paper_crack, "progress", 1.0, 0.72) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _wait(0.76)

	# ③ t≈1.16 反向挤压 → 第一撕：封印纸猛地裂开
	SfxNode.play("fx_ult_squeeze")
	var sq := create_tween().set_parallel()
	sq.tween_property(_paper_l, "position:x", px0 + 14.0, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	sq.tween_property(_paper_r, "position:x", rx0 - 14.0, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _wait(0.1)

	SfxNode.play("fx_ult_tear")
	var tear := create_tween().set_parallel()
	tear.tween_property(_paper_l, "position:x", px0 - PAPER_OVER, 0.16) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tear.tween_property(_paper_r, "position:x", rx0 + PAPER_OVER, 0.16) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tear.tween_property(_paper_l, "rotation", -0.06, 0.2)
	tear.parallel().tween_property(_paper_r, "rotation", 0.06, 0.2)
	tear.chain().tween_property(_paper_l, "position:x", px0 - PAPER_DX, 0.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tear.parallel().tween_property(_paper_r, "position:x", rx0 + PAPER_DX, 0.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_paper_crack.flash()
	var pop := create_tween()
	pop.tween_property(_flash, "color:a", 0.55, 0.06)
	pop.tween_property(_flash, "color:a", 0.0, 0.24)
	await _wait(0.1)

	# ④ t≈1.5 大女仆从裂痕里显现（她一直站在裂痕后面）
	SfxNode.play("fx_ult_ready")
	var show := create_tween().set_parallel()
	show.tween_property(_maid, "modulate:a", 1.0, 0.35)
	show.tween_property(_maid, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_maid.pivot_offset = Vector2(MAID_W * 0.5, MAID_H * 0.6)
	_maid.scale = Vector2(0.93, 0.93)
	await _wait(0.65)

	# ⑤ t≈2.35 第二段张力：女仆立绘绷紧（切到撕开两半素材 + 裂纹延伸）
	_maid.visible = false
	_left.visible = true
	_right.visible = true
	SfxNode.play("fx_ult_strain")
	_body_crack.modulate.a = 1.0
	_body_crack.progress = 0.0
	var strain2 := create_tween()
	for i in 5:
		var amp2 := 1.0 + i * 0.7
		strain2.tween_property(_left, "scale:x", 1.0 + 0.02 * amp2, 0.08)
		strain2.parallel().tween_property(_right, "scale:x", 1.0 + 0.02 * amp2, 0.08)
		strain2.tween_property(_left, "scale:x", 1.0 - 0.014 * amp2, 0.06)
		strain2.parallel().tween_property(_right, "scale:x", 1.0 - 0.014 * amp2, 0.06)
	var crack2 := create_tween()
	crack2.tween_property(_body_crack, "progress", 1.0, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _wait(0.55)

	# t≈2.95 挤压 → 第二撕
	SfxNode.play("fx_ult_squeeze")
	var sq2 := create_tween().set_parallel()
	sq2.tween_property(_left, "position:x", lx0 + TEAR_SQUEEZE, 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	sq2.tween_property(_right, "position:x", lx0 - TEAR_SQUEEZE, 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _wait(0.09)

	SfxNode.play("fx_ult_tear")
	var tear2 := create_tween().set_parallel()
	tear2.tween_property(_left, "position:x", lx0 - TEAR_OVER, 0.14) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tear2.tween_property(_right, "position:x", lx0 + TEAR_OVER, 0.14) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tear2.tween_property(_left, "rotation", -TEAR_ROT, 0.16)
	tear2.parallel().tween_property(_right, "rotation", TEAR_ROT, 0.16)
	tear2.chain().tween_property(_left, "position:x", lx0 - TEAR_DX, 0.13) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tear2.parallel().tween_property(_right, "position:x", lx0 + TEAR_DX, 0.13) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_body_crack.flash()
	var pop2 := create_tween()
	pop2.tween_property(_flash, "color:a", 0.5, 0.06)
	pop2.tween_property(_flash, "color:a", 0.0, 0.22)
	await _wait(0.28)

	# ⑥ t≈3.5 大肥鱼闪亮登场
	SfxNode.play("fx_ult_fish")
	_star.appear()
	_fish.visible = true
	var fish_tw := create_tween()
	fish_tw.tween_property(_fish, "scale", Vector2(1.22, 1.22), 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	fish_tw.tween_property(_fish, "scale", Vector2.ONE, 0.14)
	await _wait(0.5)

	# 得意贱笑三连晃
	var sway := create_tween()
	sway.tween_property(_fish, "rotation_degrees", 4.0, 0.1)
	sway.tween_property(_fish, "rotation_degrees", -3.0, 0.12)
	sway.tween_property(_fish, "rotation_degrees", 0.0, 0.1)
	await _wait(0.34)

	# ⑦ t≈4.4 爆发：白闪 + 粒子 + 网格 → 伤害结算（arena 震屏）
	SfxNode.play("fx_ult_burst")
	_grid.modulate.a = 1.0
	_burst.restart()
	_burst.emitting = true
	var f_tw := create_tween()
	f_tw.tween_property(_flash, "color:a", 0.85, 0.07)
	f_tw.tween_property(_flash, "color:a", 0.0, 0.3)
	hit_moment.emit()

	# 大字弹入
	_title.visible = true
	_sub.visible = true
	var t_tw := create_tween().set_parallel()
	t_tw.tween_property(_title, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t_tw.tween_property(_sub, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	await _wait(1.1)

	# 收尾淡出
	var out := create_tween().set_parallel()
	out.tween_property(self, "modulate:a", 0.0, 0.55).set_delay(0.1)
	await _wait(0.7)
	finished.emit()
	queue_free()


# ── 内部特效组件 ─────────────────────────────────────────

## 裂纹线：外发光 + 白芯双层 Line2D，progress 自上而下延伸（张力预兆）。
class CrackLine extends Control:
	var _glow: Line2D
	var _core: Line2D
	var _pts: PackedVector2Array
	var progress := 0.0:
		set(v):
			progress = clampf(v, 0.0, 1.0)
			_apply()

	func setup(points: PackedVector2Array) -> void:
		_pts = points
		size = Vector2(760, 900)
		_glow = Line2D.new()
		_glow.width = 12.0
		_glow.default_color = Color(0.31, 0.76, 0.97, 0.45)
		add_child(_glow)
		_core = Line2D.new()
		_core.width = 2.5
		_core.default_color = Color(0.82, 0.96, 1.0)
		add_child(_core)

	func _apply() -> void:
		var n := maxi(2, int(round(_pts.size() * progress)))
		var sub := _pts.slice(0, n)
		_glow.points = sub
		_core.points = sub

	func flash() -> void:
		var tw := create_tween()
		_core.default_color = Color(1, 1, 1)
		_glow.width = 22.0
		tw.tween_interval(0.08)
		tw.tween_property(self, "modulate:a", 0.0, 0.3)   # 撕开后裂纹让位给缝隙

	func _ready() -> void:
		_apply()


## 星芒背板：放射长线交替长短 + 慢旋转 + 呼吸缩放（闪亮登场专用）。
class Starburst extends Control:
	var _t := 0.0

	func appear() -> void:
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 1.0, 0.25)

	func _process(delta: float) -> void:
		if modulate.a <= 0.01:
			return
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r_out := size.x * 0.48
		var col := Color(0.78, 0.95, 1.0, 0.5)
		var col2 := Color(0.45, 0.88, 1.0, 0.35)
		for i in 16:
			var ang := _t * 0.6 + TAU * i / 16.0
			var r := r_out * (1.0 if i % 2 == 0 else 0.62)
			var dir := Vector2(cos(ang), sin(ang))
			var w := 3.0 if i % 2 == 0 else 2.0
			draw_line(c + dir * size.x * 0.12, c + dir * r,
					col if i % 2 == 0 else col2, w)
		draw_circle(c, size.x * (0.045 + 0.008 * sin(_t * 5.0)),
				Color(1, 1, 1, 0.25))


## 代码雨：青色字符列下落（0/1/R1/token/汉字），AI 训练意象。
class CodeRain extends Control:
	const GLYPHS := "01R1token深度思考推理算力<>/{}[]"
	const COLS := 26
	var _cols: Array = []
	var _running := false

	func start() -> void:
		_running = true
		if _cols.is_empty():
			var font := PixelTheme.font()
			for i in COLS:
				var l := Label.new()
				l.add_theme_font_override("font", font)
				l.add_theme_font_size_override("font_size", 16)
				l.add_theme_color_override("font_color",
						Color(0.45, 0.88, 1.0, randf_range(0.14, 0.4)))
				var txt := ""
				for j in randi_range(6, 14):
					txt += GLYPHS[randi() % GLYPHS.length()] + "\n"
				l.text = txt
				l.position = Vector2(randf_range(0, 1560), randf_range(-900, -80))
				add_child(l)
				_cols.append({"node": l, "speed": randf_range(260, 620)})

	func _process(delta: float) -> void:
		if not _running:
			return
		for c in _cols:
			var l: Label = c["node"]
			l.position.y += c["speed"] * delta
			if l.position.y > 940:
				l.position.y = randf_range(-600, -160)
				l.position.x = randf_range(0, 1560)

	func stop() -> void:
		_running = false


## 注意力网格：青色方格 + 呼吸明暗，爆发阶段短暂可见。
class AttentionGrid extends Control:
	var _phase := 0.0

	func _process(delta: float) -> void:
		if modulate.a <= 0.01:
			return
		_phase += delta * 6.0
		queue_redraw()

	func _draw() -> void:
		var a := 0.10 + 0.08 * sin(_phase)
		var col := Color(0.45, 0.88, 1.0, a)
		for x in range(0, 1601, 80):
			draw_line(Vector2(x, 0), Vector2(x, 900), col, 1.0)
		for y in range(0, 901, 80):
			draw_line(Vector2(0, y), Vector2(1600, y), col, 1.0)
