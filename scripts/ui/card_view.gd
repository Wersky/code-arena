class_name CardView
extends Control
## 单张**扑克牌**（像素风：全硬边）。
##
## 牌面 = 满幅卡图（AI 娘按花色换主题）+ 四角的花色符号与点数。
##   左上：花色符号 + 点数
##   右下：同款，旋转 180°
##   中下：一条半透明底衬，写 点数 / 颜色效果，保证信息永远读得清
##
## 卡图资源：assets/art/poker-<ai_id>-<suit>.png（150×226，一比一直接贴）。
## 缺图时降级成纯色块 + 大号点数，不报错。
##
## 卡片坐标由 Arena 的 card_layer 统一管理（不进容器），
## 手牌↔命令行之间可以做平滑补间。

signal clicked(view: CardView)

const CARD_SIZE := Vector2(150, 226)

## 牌数据
var card: PokerCard = null
## 牌面上画哪位 AI 娘
var ai_id: String = "deepdeek"
var interactive: bool = true
var dimmed: bool = false
## 选中：牌在 _layout_hand 里抬起来，并画一圈亮边
var selected: bool = false

var _hover_scale: float = 1.0
var _hover_tween: Tween = null


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = CARD_SIZE * 0.5


func setup(c: PokerCard, who: String = "deepdeek") -> void:
	card = c
	ai_id = who
	queue_redraw()


var hover_scale: float = 1.16


func _ready() -> void:
	mouse_entered.connect(set_hovered.bind(true))
	mouse_exited.connect(set_hovered.bind(false))
	_apply_transform()


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
	var font := get_theme_default_font()
	var accent := PokerCard.suit_color(card.suit)
	var red := PokerCard.is_red(card.suit)

	# 硬边投影
	draw_rect(Rect2(Vector2(3, 4), CARD_SIZE), Color(0, 0, 0, 0.5))

	var tex := Art.tex(card.art_name(ai_id))
	if tex != null:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, CARD_SIZE), false,
				Color(1, 1, 1, 0.55 if dimmed else 1.0))
	else:
		draw_rect(Rect2(Vector2.ZERO, CARD_SIZE), UiKit.PANEL_2.lerp(accent, 0.16))
		# 缺图时把点数画大，保证还是一张能玩的牌
		draw_string(font, Vector2(CARD_SIZE.x * 0.5 - 26, CARD_SIZE.y * 0.5 + 18),
				str(card.rank), HORIZONTAL_ALIGNMENT_LEFT, -1, 60, accent)

	if dimmed:
		draw_rect(Rect2(Vector2.ZERO, CARD_SIZE), Color(0.04, 0.05, 0.08, 0.55))

	# 四角：花色 + 点数
	_draw_corner(font, Vector2(7, 26), accent, 0.0)
	_draw_corner(font, Vector2(CARD_SIZE.x - 7, CARD_SIZE.y - 8), accent, PI)

	# 底部信息条：点数 ｜ 红=倍率 黑=筹码
	var foot_h := 26.0
	var fy := CARD_SIZE.y - foot_h
	draw_rect(Rect2(Vector2(0, fy), Vector2(CARD_SIZE.x, foot_h)), Color(0.04, 0.055, 0.09, 0.86))
	draw_rect(Rect2(Vector2(0, fy), Vector2(CARD_SIZE.x, 1)), accent, false, 1.0)
	draw_string(font, Vector2(8, fy + 18), "点数 %d" % card.rank,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.TEXT)
	var tag := "+3 倍率" if red else "+25 筹码"
	draw_string(font, Vector2(CARD_SIZE.x - 62, fy + 18), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, accent)

	# 外框：红牌暖色、黑牌冷色；选中时亮白粗边
	if selected:
		draw_rect(Rect2(Vector2.ZERO, CARD_SIZE), Color(1, 1, 1, 0.92), false, 3.0)
		draw_rect(Rect2(Vector2(3, 3), CARD_SIZE - Vector2(6, 6)), accent, false, 1.0)
	else:
		draw_rect(Rect2(Vector2.ZERO, CARD_SIZE), accent, false, 2.0)


## 画一个角标：花色符号 + 点数（rotate = PI 时倒过来画）
func _draw_corner(font: Font, base: Vector2, color: Color, rot: float) -> void:
	var sym := PokerCard.suit_symbol(card.suit)
	var num := str(card.rank)
	if is_zero_approx(rot):
		draw_string(font, base + Vector2(-1, 0), sym, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		draw_string(font, base + Vector2(-1, 16), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)
	else:
		# 右下角：同款内容倒排（像素卡牌的传统做法，不用旋转矩阵）
		draw_string(font, base + Vector2(-1, -16), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)
		draw_string(font, base + Vector2(-1, 0), sym, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
