class_name UiKit
extends RefCounted
## 统一视觉工厂 —— 像素风。
##
## 所有值都来自下面几套刻度，不允许随手写数字：
##   · 字号刻度  12 / 24 / 36 / 48 / 60   （像素字体原生 12px 网格 + 整数倍缩放，
##                                          所以字号只能是 12 的整数倍，否则会塌成同一档）
##   · 间距刻度  4 / 8 / 12 / 16 / 24 / 32
##   · 高度刻度  0（平）/ 1（2px 偏移）/ 2（4px 偏移）
##
## 配色限定 16 色以内，TEXT_DIM 已用 WCAG 校验器验过：
##   TEXT_DIM on PANEL_3 = 4.86:1（≥4.5:1 通过）
##
## 【对齐契约（主人的明确不满，整改后唯一入口）】
##   侧栏的"图标 + 标签 + 数值"一律走 icon_row()，三列各占各的位置：
##     · 图标列：左边缘 = 内容区左边缘，宽 ICON_COL_W（16）
##     · 标签列：左边缘统一 = 图标列右边缘 + COL_GAP
##     · 数值列：**独立容器**，右边缘统一钉在「内容区右边缘 − RIGHT_INSET」
##   谁都不许再把数值塞进铭牌控件里（那会让数值左边缘随铭牌长度参差）。

# ── 调色板（16 色）───────────────────────────────────
const BG := Color(0.043, 0.055, 0.086)       # #0b0e16
const PANEL := Color(0.078, 0.094, 0.133)     # #141822
const PANEL_2 := Color(0.114, 0.133, 0.184)   # #1d2230
const PANEL_3 := Color(0.157, 0.180, 0.243)   # #282e3e
const LINE := Color(0.278, 0.318, 0.400)      # #475166
const LINE_HI := Color(0.412, 0.463, 0.576)   # #697693
const SHADOW := Color(0.0, 0.0, 0.0, 0.55)
const TEXT := Color(0.843, 0.878, 0.929)      # #d7e0ee
const TEXT_DIM := Color(0.565, 0.608, 0.706)   # #909bb4  ← 已过 4.5:1
const ACCENT := Color(0.310, 0.757, 0.965)    # #4fc1f6
const GOLD := Color(1.0, 0.820, 0.400)        # #ffd166
const DANGER := Color(0.937, 0.333, 0.333)    # #ef5555
const GOOD := Color(0.478, 0.792, 0.443)      # #7aca71
const PINK := Color(0.937, 0.545, 0.706)      # #ef8bb4
const WHITE := Color(1.0, 1.0, 1.0)

# ── 字号刻度（必须是 12 的整数倍）──────────────────────
const FS_XS := 12
const FS_S := 24
const FS_M := 36
const FS_L := 48
const FS_XL := 60

# ── 间距刻度 ─────────────────────────────────────────
const SP_1 := 4
const SP_2 := 8
const SP_3 := 12
const SP_4 := 16
const SP_5 := 24
const SP_6 := 32

# ── 高度刻度 ─────────────────────────────────────────
const EL_0 := 0
const EL_1 := 2
const EL_2 := 4

# ── 对齐刻度（整改核心）───────────────────────────────
const ICON_COL_W := 16     ## 侧栏图标列宽（16×16 图标）
const VALUE_COL_W := 96    ## 侧栏数值列固定宽（右对齐用）
const COL_GAP := 4         ## 三列之间的间距
const RIGHT_INSET := 12    ## 数值列右边缘距「内容区右边缘」的留白
const LINE_SPACING := 4    ## 全文统一行距
const LOG_LINE_H := 18     ## 控制台日志行高
const PANEL_PAD := 12      ## 面板内边距（统一）

# ── 装饰贴图名（art-ui 产出）──────────────────────────
const TEX_BUTTON := "ui-button"
const TEX_TITLEBAR := "ui-titlebar"
const TEX_RIBBON := "ui-ribbon"
const TEX_AI_FRAME := "ui-ai-frame"
const TEX_ICON_LEVEL := "ui-icon-level"
const TEX_ICON_TOKEN := "ui-icon-token"
const TEX_ICON_COMPUTE := "ui-icon-compute"
const TEX_ICON_AI := "ui-icon-ai"

# 九宫格边距（素材自带的设计线）
const M_BUTTON := 8
const M_AI_FRAME := 5
const M_TITLEBAR_L := 16
const M_TITLEBAR_R := 20
const M_RIBBON_L := 26
const M_RIBBON_R := 26


## 硬边面板样式。shadow 用高度刻度，不要随手写别的数。
static func flat(bg: Color, border: Color = Color.TRANSPARENT,
		border_w: int = 0, pad: int = SP_3, elevation: int = EL_0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_content_margin_all(pad)
	if elevation > 0:
		sb.shadow_size = elevation
		sb.shadow_color = SHADOW
		sb.shadow_offset = Vector2(elevation, elevation)
	return sb


## 九宫格样式（按钮 / 面板装饰用）。margin 是素材的九宫格线（源像素）。
static func nine_style(tex_name: String, margin: int, tint: Color = Color.WHITE,
		content_margin: int = SP_2) -> StyleBoxTexture:
	var st := StyleBoxTexture.new()
	st.texture = Art.tex(tex_name)
	st.texture_margin_left = margin
	st.texture_margin_right = margin
	st.texture_margin_top = margin
	st.texture_margin_bottom = margin
	st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	st.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	st.content_margin_left = content_margin
	st.content_margin_right = content_margin
	st.content_margin_top = content_margin
	st.content_margin_bottom = content_margin
	st.modulate_color = tint
	return st


## 九宫格装饰节点（标题条 / 绶带 / 立绘边框用）。
static func nine_node(tex_name: String, ml: int, mr: int, mt: int, mb: int) -> NinePatchRect:
	var np := NinePatchRect.new()
	np.texture = Art.tex(tex_name)
	np.patch_margin_left = ml
	np.patch_margin_right = mr
	np.patch_margin_top = mt
	np.patch_margin_bottom = mb
	np.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	np.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np


## 贴图（装饰件统一入口）
static func tex(name: String) -> Texture2D:
	return Art.tex(name)


static func label(text: String, size: int = FS_XS, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", LINE_SPACING)
	return l


static func title(text: String, size: int = FS_S) -> Label:
	return label(text, size, TEXT)


static func dim(text: String, size: int = FS_XS, color: Color = TEXT_DIM) -> Label:
	return label(text, size, color)


## 分节标题：一条硬线 + 小字
static func section(text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", SP_2)
	h.add_child(dim(text, FS_XS, TEXT_DIM))
	var line := ColorRect.new()
	line.color = LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(line)
	return h


## 按钮。外观走 ui-button.png 九宫格（中央纯色，拉伸不畸变），
## 文字仍由 Button 自己绘制 → 永远压在九宫格之上。
static func button(text: String, size: int = FS_XS, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", TEXT_DIM)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM.darkened(0.3))
	var tint := ACCENT if accent else Color.WHITE
	b.add_theme_stylebox_override("normal", nine_style(TEX_BUTTON, M_BUTTON, tint, SP_2))
	b.add_theme_stylebox_override("hover", nine_style(TEX_BUTTON, M_BUTTON, tint.lightened(0.22), SP_2))
	b.add_theme_stylebox_override("pressed", nine_style(TEX_BUTTON, M_BUTTON, tint.darkened(0.3), SP_2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", nine_style(TEX_BUTTON, M_BUTTON,
			Color(0.55, 0.55, 0.62, 0.75), SP_2))
	b.focus_mode = Control.FOCUS_NONE
	return b


static func accent_button(text: String, size: int = FS_XS) -> Button:
	var b := button(text, size, true)
	b.add_theme_color_override("font_color", Color(0.93, 0.98, 1.0))
	return b


static func panel_box(bg: Color = PANEL, border: Color = LINE, pad: int = PANEL_PAD) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(bg, border, 2, pad))
	return p


static func spacer(h: int = SP_2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func hsep(w: int = SP_2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c


static func rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = LINE
	r.custom_minimum_size = Vector2(0, 1)
	return r


## ─────────────────────────────────────────────────────────
##  对齐行工厂（唯一入口，别再散着写 add_theme_font_size_override）
## ─────────────────────────────────────────────────────────

## 「图标 + 标签 + 数值」三列行。
##   · 图标列：左边缘 = 内容区左边缘（宽 ICON_COL_W）
##   · 标签列：左边缘统一 = 图标列右边缘 + COL_GAP
##   · 数值列：独立容器，右边缘 = 内容区右边缘 − RIGHT_INSET
## 返回的 HBox 里子节点名为 Icon / Key / Value / RightPad，
## 外部改数值统一用 row.get_node("Value")。
static func icon_row(icon_name: String, key: String, value: String,
		value_color: Color = TEXT, size: int = FS_XS) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COL_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ic := TextureRect.new()
	ic.name = "Icon"
	ic.texture = tex(icon_name)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(ICON_COL_W, ICON_COL_W)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)

	var k := label(key, size, TEXT_DIM)
	k.name = "Key"
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(k)

	var v := label(value, size, value_color)
	v.name = "Value"
	v.custom_minimum_size = Vector2(VALUE_COL_W, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)

	# 末列留白：把数值列右边缘顶到「内容区右边缘 − RIGHT_INSET」
	var pad := Control.new()
	pad.name = "RightPad"
	pad.custom_minimum_size = Vector2(RIGHT_INSET - COL_GAP, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)
	return row


## 「标签 + 数值」两列行（没有图标时用，数值列规则完全一致）。
static func kv_row(key: String, value: String, value_color: Color = TEXT,
		key_size: int = FS_XS, value_size: int = FS_XS) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COL_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var k := label(key, key_size, TEXT_DIM)
	k.name = "Key"
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(k)

	var v := label(value, value_size, value_color)
	v.name = "Value"
	v.custom_minimum_size = Vector2(VALUE_COL_W, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)

	var pad := Control.new()
	pad.name = "RightPad"
	pad.custom_minimum_size = Vector2(RIGHT_INSET - COL_GAP, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)
	return row


## 面板标题条：ui-titlebar.png 装饰 + 标题文字叠在装饰条的凹槽里。
static func title_bar(text: String, min_width: float = 0.0,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, color: Color = TEXT) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(min_width, 24)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var np := nine_node(TEX_TITLEBAR, M_TITLEBAR_L, M_TITLEBAR_R, 0, 0)
	np.set_anchors_preset(Control.PRESET_FULL_RECT)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(np)

	var l := label(text, FS_XS, color)
	l.name = "Text"
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_left = 20
	l.offset_right = -24
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(l)
	return holder


## 数值跳动：数字变化时弹一下并闪色，游戏感的关键细节。
static func pop(node: Control, to_scale: float = 1.22, dur: float = 0.26) -> void:
	if node == null or not node.is_inside_tree():
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector2.ONE * to_scale, dur * 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, dur * 0.65) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 文字闪一下（配合 pop 用）
static func flash_text(node: Label, color: Color = Color.WHITE, dur: float = 0.3) -> void:
	if node == null or not node.is_inside_tree():
		return
	var base := node.get_theme_color("font_color", "Label")
	var t := node.create_tween()
	t.tween_method(func(v: float) -> void:
		node.add_theme_color_override("font_color", base.lerp(color, v)), 1.0, 0.0, dur * 0.3)
	t.tween_method(func(v: float) -> void:
		node.add_theme_color_override("font_color", base.lerp(color, v)), 1.0, 1.0, dur * 0.7)
