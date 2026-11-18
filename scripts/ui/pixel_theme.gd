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
	# 注意：导出包里 .ttf 源文件被重映射成 .godot/imported/*.fontdata，
	# `FileAccess.file_exists("res://....ttf")` 会判 false（编辑器内却是 true），
	# 所以这里只能用 ResourceLoader 判断 + load()。踩坑 46。
	if not ResourceLoader.exists(FONT_PATH):
		push_warning("像素字体缺失，回退默认字体：%s" % FONT_PATH)
		return null
	var base := load(FONT_PATH) as FontFile
	if base == null:
		push_warning("像素字体加载失败，回退默认字体：%s" % FONT_PATH)
		return null
	# 复制一份再改属性，避免污染 ResourceLoader 缓存里的共享实例
	var f: FontFile = base.duplicate() as FontFile
	if f == null:
		f = base
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
		## ⚠ 光设 default_font 不够（2026-11-18 实测，中文方框的根因）：
		##   `Theme.default_font` 只是**兜底**——它的优先级低于「主题类里显式定义的
		##   font 项」。而 Godot 内置默认 Theme 定义了 Label/Button 等的 `font`，
		##   于是 get_theme_font("font") 拿到的是**内置那个没有中文的字体**，
		##   default_font 根本没被用上。
		##   实测探针（真实窗口，非 headless）：
		##     root.theme.default_font = FontFile#...195615430      ← 我们设的中文字体
		##     leaf.get_theme_font("font") = FontFile#...4155201702  ← 换了一个！
		##     has_char(中) = false    has_char(A) = true
		##   所以必须**逐个控件类型**把 font 项也指向中文字体。
		t.default_font_size = 12
		for cls in ["Label", "Button", "RichTextLabel", "LineEdit",
				"TextEdit", "OptionButton", "CheckBox", "CheckButton",
				"MenuButton", "LinkButton", "SpinBox", "ItemList",
				"Tree", "TabBar", "PopupMenu", "TooltipLabel",
				"ProgressBar", "TreeItem"]:
			for item in ["font", "normal_font"]:
				t.set_font(item, cls, f)
	_theme = t
	return _theme


## 装到场景根上，全局生效
static func install(node: Node) -> void:
	if node == null:
		return
	var t := build()
	if node is Window:
		(node as Window).theme = t
	elif node is Control:
		(node as Control).theme = t
	elif node.get_tree() != null:
		## ⚠ Window.theme 不参与 Control 的继承链（2026-11-18 实测，中文方框根因）：
		##   把 theme 设到 get_tree().root（Window）上，子 Control 的 `theme` 仍是 null，
		##   get_theme_font("font") 拿到**引擎内置主题**里那个没有中文的字体。
		##   实测探针（真实窗口）：
		##     theme.get_font("font","Label") = FontFile#...195615430  ← 我们设的（对）
		##     leaf.theme = <Object#null>                              ← 没继承（错）
		##     leaf.get_theme_font("font") = FontFile#...4155201702    ← 内置字体
		##     has_char(中)=false  has_char(A)=true
		##   对照：LaunchScreen 每个 Label 都显式 add_theme_font_override → 中文正常。
		##   所以除了 root，还要沿 Node 树给每个 Control 挂一份（见下）。
		node.get_tree().root.theme = t
		_attach_to_controls(node.get_tree().root, t)
		## 运行时新增的界面（LLM 面板、选角介绍面板等）在 add_child 之后才出现，
		## 这里挂一个监听：每次树结构变化就补挂，避免"新窗口没字体"。
		_watch_new_controls(node.get_tree().root, t)


## 沿 Node 树给每个 Control 挂 theme（Control 内部靠继承链，不递归）
static func _attach_to_controls(n: Node, t: Theme) -> void:
	for c in n.get_children():
		if c is Control:
			if (c as Control).theme == null:
				(c as Control).theme = t
		else:
			_attach_to_controls(c, t)


## 树结构变化时补挂（只挂顶层 Control，避免每帧遍历整棵树）
static func _watch_new_controls(root: Window, t: Theme) -> void:
	if root.has_meta("_pixel_theme_watch"):
		return
	root.set_meta("_pixel_theme_watch", true)
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is Control:
			var c := n as Control
			if c.theme == null:
				c.theme = t
	)
