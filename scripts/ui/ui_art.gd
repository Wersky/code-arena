class_name UiArt
extends RefCounted
## 生图 UI 资产的取用中枢。
##
## 资产由 `tools/make_ui_assets.py` 加工：裁到内容 → NEAREST 整数降采样 → alpha 二值化。
## 产物都在 `res://assets/art/ui/`，源图在 `D:/zcode-work/pictures/output/`。
##
## **尺寸纪律**：所有资产在游戏里按 **×2 整数放大** 显示。
## 非整数缩放会让像素格大小不均（有的像素 2px、有的 3px），一眼就脏。
## 需要更大就改 `tools/make_ui_assets.py` 里的目标尺寸重跑，别在这里硬拉。

## 统一放大倍数
const SCALE := 2

const NAME_PANEL := "panel"
const NAME_PLAQUE := "plaque"
const NAME_BTN := "btn"
const NAME_HUD := "hudstrip"
const NAME_DIVIDER := "divider"

## 九宫格边距（单位=控件像素，= 源图金边厚度 × SCALE）。
## 数值由 `tools/make_ui_assets.py` 打印，改了资产要同步这里。
const MARGIN_PANEL := Vector4i(54, 52, 52, 54)
const MARGIN_PLAQUE := Vector4i(86, 86, 52, 52)
const MARGIN_HUD := Vector4i(68, 68, 68, 68)

## 资源原始像素尺寸（×SCALE 后才是推荐显示尺寸）
const NATIVE := {
	"panel": Vector2(541, 328),
	"plaque": Vector2(382, 119),
	"btn": Vector2(275, 85),
	"hudstrip": Vector2(559, 84),
	"divider": Vector2(377, 51),
}

## 霓虹配色（比 UiKit.GOLD 更"AI 控制台"）
const NEON := Color(0.216, 0.847, 0.941)      # #37D8F0 青
const VIOLET := Color(0.643, 0.424, 1.0)      # #A46CFF 紫
const MAGENTA := Color(1.0, 0.373, 0.659)     # #FF5FA8 品红


static func tex(name: String) -> Texture2D:
	return Art.tex("ui/ui-" + name)


static func has(name: String) -> bool:
	return Art.has("ui/ui-" + name)


## 推荐显示尺寸（原生 ×2）
static func display_size(name: String) -> Vector2:
	var n: Vector2 = NATIVE.get(name, Vector2.ZERO)
	return n * SCALE


## 九宫格面板。传 Vector2.ZERO 表示用推荐尺寸。
static func nine(name: String, m: Vector4i, px_size: Vector2 = Vector2.ZERO) -> NinePatchRect:
	var t := tex(name)
	if t == null:
		return null
	var n := NinePatchRect.new()
	n.texture = t
	n.patch_margin_left = m.x
	n.patch_margin_top = m.y
	n.patch_margin_right = m.z
	n.patch_margin_bottom = m.w
	n.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	n.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := px_size if px_size != Vector2.ZERO else display_size(name)
	n.size = s
	n.custom_minimum_size = s
	return n


static func panel(px_size: Vector2 = Vector2.ZERO) -> NinePatchRect:
	return nine("panel", MARGIN_PANEL, px_size)


static func plaque_plate(px_size: Vector2 = Vector2.ZERO) -> NinePatchRect:
	return nine("plaque", MARGIN_PLAQUE, px_size)


static func hud_strip(px_size: Vector2 = Vector2.ZERO) -> NinePatchRect:
	return nine("hudstrip", MARGIN_HUD, px_size)


## 装饰分隔线（居中，按宽度缩放；高度按比例）
static func divider(width: float) -> TextureRect:
	var t := tex("divider")
	if t == null:
		return null
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := display_size("divider")
	var h := base.y * (width / base.x)
	r.custom_minimum_size = Vector2(width, h)
	r.size = Vector2(width, h)
	return r


## 图标。px 是显示边长（会按 SCALE 的整数倍向上取整，避免半像素）
static func icon(name: String, px: float = 64.0) -> TextureRect:
	var t := tex("icon-" + name)
	if t == null:
		return null
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.custom_minimum_size = Vector2(px, px)
	r.size = Vector2(px, px)
	return r
