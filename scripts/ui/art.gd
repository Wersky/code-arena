class_name Art
extends RefCounted
## 美术资源中枢。
##
## 所有贴图都从 res://assets/art/ 懒加载并缓存。
## 生成脚本：D:/zcode-work/pictures/gen_arena_assets.py

const DIR := "res://assets/art/"
const EXTS := [".png", ".jpg"]

static var _cache: Dictionary = {}
static var _missing: Dictionary = {}


## 找到资源的实际路径（先 png 后 jpg）。没有就返回空串。
static func path_of(name: String) -> String:
	if name.is_empty():
		return ""
	for ext in EXTS:
		var p: String = DIR + name + str(ext)
		if ResourceLoader.exists(p):
			return p
	return ""


## 按名字取贴图（不含扩展名）。没有就返回 null，调用方负责降级。
static func tex(name: String) -> Texture2D:
	if name.is_empty():
		return null
	if _cache.has(name):
		return _cache[name]
	if _missing.has(name):
		return null
	var path := path_of(name)
	if path.is_empty():
		_missing[name] = true
		push_warning("缺少美术资源：%s" % (DIR + name + ".png"))
		return null
	var t: Texture2D = load(path)
	_cache[name] = t
	return t


## 资源是否存在（不触发缺图警告）
static func has(name: String) -> bool:
	return not path_of(name).is_empty()


## AI 道具贴图：模型道具用 item-<id>，技术道具用 tech-<id>
static func item_tex(item_id: String) -> Texture2D:
	if has("item-" + item_id):
		return tex("item-" + item_id)
	if has("tech-" + item_id):
		return tex("tech-" + item_id)
	return null


## AI 道具贴图名（供 UI 拼 texture 资源名）
static func item_art_name(item_id: String) -> String:
	if has("item-" + item_id):
		return "item-" + item_id
	if has("tech-" + item_id):
		return "tech-" + item_id
	return ""


## AI 道具的半身像贴图名（横向头像位用，预裁好的头肩带）
static func item_bust_name(item_id: String) -> String:
	if has("item-" + item_id + "-bust"):
		return "item-" + item_id + "-bust"
	return item_art_name(item_id)


## 卡面类型插画
static func card_tex(kind: int) -> Texture2D:
	return tex("card-" + CardData.kind_slug(kind))


## HUD 像素铭牌（96×24 透明底）：hud-token / hud-compute / hud-level / hud-ai
## 缺图时返回 null，由调用方降级成纯文字，不报错。
static func hud_tex(kind: String) -> Texture2D:
	var name := "hud-" + kind
	if not has(name):
		return null
	return tex(name)


## 把贴图按目标尺寸画进矩形（保持比例，居中裁切/留白）
static func draw_fit(ci: CanvasItem, texture: Texture2D, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	if texture == null:
		return
	var ts := texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var scale := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var draw_size := ts * scale
	var pos := rect.position + (rect.size - draw_size) * 0.5
	ci.draw_texture_rect(texture, Rect2(pos, draw_size), false, modulate)


## 铺满整个矩形（背景用，允许拉伸）
static func draw_stretch(ci: CanvasItem, texture: Texture2D, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	if texture == null:
		return
	ci.draw_texture_rect(texture, rect, false, modulate)


## 把贴图裁成居中的方形区域（头像用：只取上半身）
static func draw_avatar(ci: CanvasItem, texture: Texture2D, rect: Rect2, head_ratio: float = 0.62,
		modulate: Color = Color.WHITE) -> void:
	if texture == null:
		return
	var ts := texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	# 从上往下裁 head_ratio 高度，再居中裁方形
	var crop_h := ts.y * head_ratio
	var crop_w := minf(ts.x, crop_h)
	var src := Rect2((ts.x - crop_w) * 0.5, 0.0, crop_w, crop_h)
	var scale := maxf(rect.size.x / crop_w, rect.size.y / crop_h)
	var dst := Rect2(rect.position, rect.size)
	ci.draw_texture_rect_region(texture, dst, src, modulate)


## 生成一个带贴图的 TextureRect（UI 里用）
static func make_rect(name: String, expand: bool = true) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex(name)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE if expand else TextureRect.EXPAND_KEEP_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func make_avatar(name: String, size: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex(name)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.custom_minimum_size = size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr
