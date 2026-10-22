class_name CardView
extends Control
## 单张**扑克牌**（像素风：全硬边）。
##
## 牌面由三层叠成（三层都是 150×226，1:1 对齐，不做几何换算）：
##   ① 白纸 + 圆角墨边   ← 本脚本用 StyleBoxFlat 画
##   ② 角色层 `card-<suit>-<rank>.png`   ← tools/make_card_assets.py 从样张抠出来
##   ③ 角标层 `pips-<suit>-<rank>.png`   ← 同上，四角角标位置与样张像素级一致
##
## 为什么不把角标和纸面烘进一张图：角标要能在不同屏幕缩放下保持硬边，
## 纸面/边框要在引擎里统一（选中、变暗、悬停都只动引擎图层）。
## 三层叠回去与 `docs/shots/` 样张逐像素一致（只差清掉的卡边 8px）。
##
## 卡片坐标由 Arena 的 card_layer 统一管理（不进容器），
## 手牌弧线排布靠 Tween 补间。
##
## 资源：assets/art/card-<suit>-<rank>.png / pips-<suit>-<rank>.png（4 花色 × 13 点数）
## 缺图时降级成纯色纸面 + 大号点数，不报错。

signal clicked(view: CardView)

const CARD_SIZE := Vector2(150, 226)
const RADIUS := 6                     ## 圆角半径（样张 4x 量到 21px ≈ 1x 5.25，按文档规格取 6）
const PAPER_INSET := 1.0              ## 纸面距控件边缘
const PAPER := Color(1.0, 1.0, 1.0)
const INK := Color(0.094, 0.133, 0.243)   ## #18223E，与样张墨线一致

## 牌数据
var card: PokerCard = null
## 牌面上画哪位 AI 娘（**现在只用于老卡图降级**：新卡面形象由花色决定）
var ai_id: String = "deepdeek"
var interactive: bool = true
var dimmed: bool = false
## 选中：牌在 _layout_hand 里抬起来，并画一圈金色描边
var selected: bool = false

var hover_scale: float = 1.16

var _hover_scale: float = 1.0
var _hover_tween: Tween = null

## 待机浮动：整手牌轻轻呼吸（整数像素位移，不破像素网格）
var _idle_t := 0.0
var _bob_y := 0
## 选中瞬间的金色闪边（0~1 衰减）
var _sel_flash := 0.0
var _flash_box: StyleBoxFlat = null

var _paper_box: StyleBoxFlat = null
var _shadow_box: StyleBoxFlat = null
var _ring_box: StyleBoxFlat = null
var _dim_box: StyleBoxFlat = null


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = CARD_SIZE * 0.5

	_paper_box = StyleBoxFlat.new()
	_paper_box.bg_color = PAPER
	_paper_box.border_color = INK
	_paper_box.set_border_width_all(1)
	_paper_box.set_corner_radius_all(RADIUS)
	_paper_box.anti_aliasing = false          # 像素风：圆角也不做抗锯齿

	_shadow_box = StyleBoxFlat.new()
	_shadow_box.bg_color = UiKit.SHADOW
	_shadow_box.set_corner_radius_all(RADIUS)
	_shadow_box.anti_aliasing = false

	_ring_box = StyleBoxFlat.new()
	_ring_box.bg_color = Color(0, 0, 0, 0)
	_ring_box.border_color = UiKit.GOLD
	_ring_box.set_border_width_all(2)
	_ring_box.set_corner_radius_all(RADIUS + 2)
	_ring_box.anti_aliasing = false

	_flash_box = StyleBoxFlat.new()
	_flash_box.bg_color = Color(0, 0, 0, 0)
	_flash_box.border_color = UiKit.GOLD
	_flash_box.set_border_width_all(2)
	_flash_box.set_corner_radius_all(RADIUS + 2)
	_flash_box.anti_aliasing = false

	_dim_box = StyleBoxFlat.new()
	_dim_box.bg_color = Color(0.04, 0.05, 0.08, 0.55)
	_dim_box.set_corner_radius_all(RADIUS)
	_dim_box.anti_aliasing = false


func setup(c: PokerCard, who: String = "deepdeek") -> void:
	card = c
	ai_id = who
	queue_redraw()


func _ready() -> void:
	mouse_entered.connect(set_hovered.bind(true))
	mouse_exited.connect(set_hovered.bind(false))
	_apply_transform()
	_idle_t = randf() * TAU
	set_process(true)


func _process(delta: float) -> void:
	# 待机浮动：选中/变暗的牌不动（它在"出手"状态，别抢戏）
	if selected or dimmed:
		if _bob_y != 0:
			_bob_y = 0
			queue_redraw()
	else:
		_idle_t += delta * 1.7
		var want := int(round(sin(_idle_t) * 1.6))
		if want != _bob_y:
			_bob_y = want
			queue_redraw()

	if _sel_flash > 0.0:
		_sel_flash = maxf(0.0, _sel_flash - delta * 4.0)
		queue_redraw()


## 选中瞬间：金色描边闪一下（配合 ArenaScreen 的抬起补间）
func flash() -> void:
	_sel_flash = 1.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			clicked.emit(self)
			accept_event()


# ── 悬停 ─────────────────────────────────────────────
func set_hovered(entered: bool) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	var target := hover_scale if entered else 1.0
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "_hover_scale", target, 0.12)
	_hover_tween.tween_callback(_apply_transform)


func _apply_transform() -> void:
	scale = Vector2(_hover_scale, _hover_scale)
	queue_redraw()


# ── 绘制 ─────────────────────────────────────────────
func _draw() -> void:
	if card == null:
		return

	# 待机浮动用绘制位移实现（不动节点 position，避免和 Arena 的排布补间打架）
	draw_set_transform(Vector2(0, float(_bob_y)), 0.0, Vector2.ONE)

	var paper_rect := Rect2(Vector2(PAPER_INSET, PAPER_INSET),
			CARD_SIZE - Vector2(PAPER_INSET, PAPER_INSET) * 2.0)

	# ① 硬边投影 + 白纸
	draw_style_box(_shadow_box, Rect2(paper_rect.position + Vector2(2, 3), paper_rect.size))
	draw_style_box(_paper_box, paper_rect)

	# ②③ 角色层 + 角标层（都是整卡尺寸，位置由资源本身决定）
	var face := Art.tex(card.face_name())
	if face != null:
		draw_texture_rect(face, Rect2(Vector2.ZERO, CARD_SIZE), false)
		var pips := Art.tex(card.pips_name())
		if pips != null:
			draw_texture_rect(pips, Rect2(Vector2.ZERO, CARD_SIZE), false)
	else:
		# 缺图降级：白纸上直接画大号点数与花色，保证还是一张能玩的牌
		_draw_fallback()

	if dimmed:
		draw_style_box(_dim_box, paper_rect)

	# 选中：金色描边（白纸上白描边看不见，改用金）
	if selected:
		draw_style_box(_ring_box, Rect2(Vector2.ZERO, CARD_SIZE))
		if _sel_flash > 0.0:
			_flash_box.border_color = Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b,
					_sel_flash)
			draw_style_box(_flash_box, Rect2(Vector2(-2, -2), CARD_SIZE + Vector2(4, 4)))


## 缺图降级：纯色纸面 + 大号点数 + 花色符号。**不静默**——Art.tex 已 push_warning。
func _draw_fallback() -> void:
	var font := get_theme_default_font()
	var accent := PokerCard.suit_color(card.suit)
	var num := _rank_label()
	draw_string(font, Vector2(CARD_SIZE.x * 0.5 - 20, CARD_SIZE.y * 0.5 + 10),
			num, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, INK)
	draw_string(font, Vector2(CARD_SIZE.x * 0.5 - 20, CARD_SIZE.y * 0.5 + 52),
			PokerCard.suit_symbol(card.suit), HORIZONTAL_ALIGNMENT_LEFT, -1, 36, accent)


func _rank_label() -> String:
	return {1: "A", 11: "J", 12: "Q", 13: "K"}.get(card.rank, str(card.rank))
