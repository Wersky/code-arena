class_name PixelTheme
extends RefCounted
## 像素风主题：加载中文像素字体（方舟像素字体 Ark Pixel Font，OFL-1.1），
## 关掉抗锯齿与 hinting，让字形边缘是硬的。
##
## 字体文件：assets/fonts/ark-pixel-12px.ttf
## 许可：SIL Open Font License 1.1，可商用、可嵌入游戏。

const FONT_PATH := "res://assets/fonts/ark-pixel-12px.ttf"

static var _font: FontFile = null
static var _theme: Theme = null


static func font() -> FontFile:
	if _font != null:
		return _font
	if not FileAccess.file_exists(FONT_PATH):
		push_warning("像素字体缺失，回退默认字体：%s" % FONT_PATH)
		return null
	var f := FontFile.new()
	var err := f.load_dynamic_font(FONT_PATH)
	if err != OK:
		push_warning("像素字体加载失败（%d），回退默认字体" % err)
		return null
	# 像素风三件套：不抗锯齿、不 hinting、不做子像素定位
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.multichannel_signed_distance_field = false
	# 按 12px 原生网格渲染，放大时保持整数倍 → 真正的像素字
	f.fixed_size = 12
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	_font = f
	return _font


static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var f := font()
	if f != null:
		t.default_font = f
	t.default_font_size = 12
	_theme = t
	return t


## 装到场景根上，全局生效
static func install(node: Node) -> void:
	if node == null:
		return
	var t := build()
	if node is Window:
		(node as Window).theme = t
	elif node is Control:
		(node as Control).theme = t
	else:
		node.get_tree().root.theme = t
