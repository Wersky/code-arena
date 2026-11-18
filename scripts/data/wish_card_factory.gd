class_name WishCardFactory
extends RefCounted
## 许愿卡（2026-11-04 圆桌定稿）：**AI 生图只当外观，数值全本地**。
## 词表三档折算：
##   档1 具象词（铁/火/风/猫…）     → 伤害 8
##   档2 意象词（龙/星/鲸/机械…）   → 伤害 12
##   档3 超限词（神/无敌/最强…）    → 伤害 0，但抽 1 张（外观专属梗卡）
## 只取命中的最高档，不叠加；伤害再受关卡预算钳制（8 + 关卡序号×2）。

const TIER1_WORDS := ["铁", "火", "风", "水", "冰", "石", "齿轮", "刀", "箭",
		"盾", "锤", "斧", "猫", "蘑菇", "碗", "饭", "纸", "笔", "书", "灯"]
const TIER2_WORDS := ["龙", "星", "渊", "影", "光", "雷", "凤凰", "鲸", "月",
		"日", "机械", "数据", "量子", "深渊", "星辰", "代码", "幻"]
const TIER3_WORDS := ["神", "无敌", "最强", "秒杀", "毁灭", "宇宙", "终极", "至高", "全知"]

const TIER_VALUES := [8, 12, 0]      ## 档1 / 档2 / 档3
const DRAW_ON_PLAY_T3 := 1           ## 超限档的补偿：抽 1 张
const WISH_CARD_NAME_MAX := 10
## 许愿请求的输出上限（2026-11-06 修）：推理模型会把思考链也算进 max_tokens，
## 实测 4096 时 2809 花在 reasoning，SVG 被截断、JSON 丢失（卡面退化成草稿纸）。
## 8192 下 finish_reason=stop，思考 2650 + 正文 3330 能完整落盘。
## 许愿输出预算（2026-11-06 主人定：画图不用省 token）。
## 推理模型的思考链也吃这个额度，8192 实测会被截断，给足 16384。
## 网关实测 8192/16384/32768 均返回 200，没有上限问题。
const WISH_MAX_TOKENS := 16384
## 截断重试档：真的被 length 截断时再给一次更大预算（每张卡最多重试一次）
const WISH_MAX_TOKENS_RETRY := 32768


## 命中最高档（未收录词保底档 1）
static func tier_for_text(text: String) -> int:
	for w in TIER3_WORDS:
		if text.contains(w):
			return 3
	for w in TIER2_WORDS:
		if text.contains(w):
			return 2
	return 1


## 折算伤害（已过关卡预算钳制）；超限档返回 0
static func damage_for_text(text: String, level_index: int) -> int:
	var tier := tier_for_text(text)
	var base: int = TIER_VALUES[tier - 1]
	if base <= 0:
		return 0
	var cap := 8 + maxi(0, level_index) * 2
	return mini(base, cap)


## 造一张许愿卡（卡面 art_path 先留空 → 由调用方挂 AI 图或像素草图）
static func make(text: String, level_index: int) -> StsCard:
	var t := text.strip_edges()
	var tier := tier_for_text(t)
	var dmg := damage_for_text(t, level_index)
	var card_id := "wish_%s" % t.sha256_text().substr(0, 10)
	var kind := StsCard.Kind.ATTACK if dmg > 0 else StsCard.Kind.SKILL
	var c := StsCard.make(card_id, kind, 1, dmg, 0, "")
	c.draw = DRAW_ON_PLAY_T3 if tier == 3 else 0
	var cname := t.substr(0, WISH_CARD_NAME_MAX)
	StsCardPool.register_wish_meta(card_id, cname, _desc_for(tier, dmg))
	return c


static func _desc_for(tier: int, dmg: int) -> String:
	match tier:
		3:
			return "许愿造物（外观专属）：造成 0 点伤害，抽 1 张牌。\n名字越狂，数值越守规矩。"
		2:
			return "许愿造物：造成 %d 点伤害。" % dmg
		_:
			return "许愿造物：造成 %d 点伤害。" % dmg


## 图生图精修提示词：保留涂鸦的构图与元素，重绘成正式卡面
const REFINE_PROMPT_TPL := """把这张手绘涂鸦精修重绘成一张游戏卡牌立绘。
要求：
1. 完整保留涂鸦的构图、元素、姿态与性格——涂鸦画的是什么，成品就是什么，不要换成别的东西。
2. 补全细节与明暗，重绘为干净的 16-bit 像素风格，轮廓清晰，颜色统一。
3. 主题：<THEME>。
4. 背景用纯深蓝色（#0B0F1A），主体居中占画面约 80%，不要文字、不要边框。"""


static func refine_prompt(text: String) -> String:
	return String(REFINE_PROMPT_TPL).replace("<THEME>", text.strip_edges())


## 造卡提示词（2026-11-04 主人钦定：**用通用大模型自己的绘图能力**）：
## 模型返回 SVG 代码（游戏内 ThorVG 渲染）+ 卡牌 JSON（本地钳制数值），
## **不使用专门的生图模型**。视觉模型能看涂鸦输入；纯文本模型按文字画。
const VISION_PROMPT := """你在卡牌游戏《代码擂台》里，把玩家的**手绘草图**变成一张卡。

你收到的就是玩家亲手画的涂鸦（多模态图片），或玩家写的一句描述。

【第一步·看懂它】
先只描述**形状**，不要先猜题材：轮廓是什么轮廓？几条线？尖角还是圆角？比例与朝向？有几个部件？有没有眼睛/腿/把手/翅膀这类细节？
把看到的形状特征写清楚之后，再判断它像什么。以你**真实看到的线条**为准，不要按常见题材猜，不要套用任何预设风格。

【第二步·忠实重绘】
把涂鸦重绘成一张干净的插画 SVG（viewBox="0 0 512 512"）：
- **必须保留涂鸦的整体形状、构图、姿态与所有特征**——涂鸦画的是什么，成品就是什么。
- 只做清理线条、补齐细节、上色。不要换成别的物体，不要改成别的物种，不要添加涂鸦里没有的主体。
- 风格、配色、背景全部由你根据画的内容自己决定（只要看起来像一张卡牌立绘、方形画布）。
- 如果涂鸦确实难以辨认，就把它原本的线条收拾干净、美化上色，保持原样。

【第四步·写生图提示词（给生图模型看的）】
另外给出一段 `art_prompt`——这是**交给专门的生图模型**的英文提示词。它要能独立描述出一张卡牌立绘：
- 主体是什么（用你识别出的具体物件，不要写"涂鸦""手绘"这类词）
- 姿态/朝向/构图（例如 centered, three-quarter view, full body）
- 风格与配色（例如 clean illustration, soft ink outlines, warm palette）
- 背景（例如 simple radial background, no text）
- **结尾固定加**：`no text, no watermark, no frame, square composition`
- 长度 40-90 个英文单词，只写画面，不要写玩法/数值/卡名。

【第三步·命名与机制】
卡名必须来自你识别出的**具体物件**（你看到什么就叫什么，不要起空泛的名字，也不要借用别的题材）。
机制：像攻击生物/武器 → kind=attack 给 damage；像护盾/建筑/防御/容器 → kind=skill 给 block；
不好判断时按你的理解给，draw 可用于「抽牌」类效果。

【第四步·效果程序（可选但强烈建议）】
除了数值，你可以给这张卡写一小段**效果程序**，让它做出数值之外的机制。只能用下面这套语法：
- 触发器 when：`on_play`（打出时）｜`on_draw`（抽到时）｜`on_turn_start`（回合开始）｜`on_turn_end`（回合结束）｜`on_kill`（击杀时）｜`on_damage_dealt`（造成伤害后）｜`on_damage_taken`（受伤后）｜`on_seq_end`（序列结束时）
- 操作 do：
  - `damage`：{"do":"damage","amount":0-20}
  - `damage_scaled`：{"do":"damage_scaled","amount":0-20,"per":"same_kind_streak|cards_played_this_turn|hand_size|enemy_status_count|turn_number|hp_missing_pct|block","step":1-5}
  - `apply_status`：{"do":"apply_status","status":"weak|vulnerable|poison|strength|thorns","tier":1-3,"target":"enemy|self"}
  - `heal`：{"do":"heal","amount":1-10}
  - `draw`：{"do":"draw","amount":1-2}
  - `discard_random`：{"do":"discard_random","amount":1-2}
  - `multiply_next`：{"do":"multiply_next","factor":2-3}
  - `block`：{"do":"block","amount":0-20}
  - `duplicate_next`：{"do":"duplicate_next"}
  - `modify_intent`：{"do":"modify_intent","delta":-10到10}
- 可选条件 if：{"counter":"hand_size|same_kind_streak|cards_played_this_turn|enemy_status_count|turn_number|hp_missing_pct|block","gte":数字}
- **program 只能有 1 个操作**（一张卡只加一个新特色；超出会被本地截断）
- 基础伤害/格挡写进 `damage`/`block` 字段，**不要在 program 里再写一次**（会双倍结算）。
- 新特色二选一：要么"成长"（damage_scaled），要么"附加状态"（apply_status）——
  **不要两个都加**，那会让一张卡顶掉一整套组合。
- 卡名里出现「每次 / 每当 / 越…越 / 抽到 / 击杀时」时，通常该用 `on_*` 触发器而不是 `on_play`。
第二个例子（三 op 组合 + 条件）：
"program":[{"when":"on_play","if":{"counter":"hand_size","gte":3},"then":[{"do":"damage","amount":5},{"do":"damage_scaled","per":"hand_size","step":2},{"do":"draw","amount":1}]}]
示例（同类型牌越打越疼 + 附降智）：
"program":[{"when":"on_play","then":[{"do":"damage","amount":6},{"do":"damage_scaled","per":"same_kind_streak","step":2},{"do":"apply_status","status":"weak","tier":1,"target":"enemy"}]}]
不要用未列出的 op 或 status。没有合适机制就省略 program。

【输出顺序】
先输出 SVG 代码：<svg viewBox="0 0 512 512">…</svg>
再空一行，输出一行 JSON：
{"name":"≤8字卡名","kind":"attack或skill","damage":0-20,"block":0-20,"draw":0-2,"desc":"≤30字效果描述","program":[],"art_prompt":"英文生图提示词（40-90词，只描述画面）","seen":"你看到的具体形状特征（先说清你认出了什么）"}
不要 Markdown 围栏，不要解释。"""

## 生图路线提示词（2026-11-18 主人三条路径的 A 路径）：
## 有生图模型时，默认模型**不画 SVG**，只做两件事：
##   ① 看懂涂鸦（视觉分析）
##   ② 产出「生图提示词 + 卡牌属性」
## 生图提示词必须带尺寸与构图约束，交给专门的生图模型出图。
const PALETTE_PROMPT := """你在卡牌游戏《代码擂台》里，把玩家的**手绘草图**变成一张卡。

你收到的就是玩家亲手画的涂鸦（多模态图片）。

【第一步·看懂它】
先只描述**形状**：轮廓是什么轮廓？几条线？尖角还是圆角？比例与朝向？有几个部件？有没有眼睛/腿/把手/翅膀？
写清形状特征之后，再判断它像什么。以你**真实看到的线条**为准，不要按常见题材猜。

【第二步·写生图提示词（重点，交给生图模型）】
输出 `art_prompt`：一段英文提示词，让专门的生图模型画出这张卡的**插画**。要求：
- 主体：用你识别出的**具体物件**（不要写 "doodle"、"sketch"、"player drawing" 这类词）
- 构图：`centered subject, three-quarter view, full body in frame, balanced composition`
- 风格：`clean card game illustration, soft ink outlines, gentle cel shading, subtle texture`
- 配色：按你看到的内容选一套协调色调（如 `warm ochre and deep teal palette`）
- 背景：`simple radial gradient background, no scenery`
- **结尾必须原样包含**：`no text, no watermark, no border, no signature, square composition, 1024x1024`
- 长度 60-110 个英文单词。只写画面，**不要写玩法、数值、卡名**。

【第三步·命名与机制】
卡名来自你识别出的**具体物件**（看到什么叫什么，不要空泛）。
机制：像攻击生物/武器 → kind=attack 给 damage；像护盾/建筑/防御 → kind=skill 给 block。

【第四步·效果程序（可选）】
可以用 program 给一个小特色，只能用这些 op：
damage / damage_scaled / apply_status / heal / draw / discard_random / multiply_next / block / duplicate_next / modify_intent
**program 最多 1 个操作**。基础伤害写 damage 字段，不要在 program 里重复。

【输出格式】
只输出一行 JSON，不要 SVG，不要 Markdown 围栏，不要解释：
{"name":"≤8字卡名","kind":"attack或skill","damage":0-20,"block":0-20,"draw":0-2,"desc":"≤30字效果描述","program":[],"art_prompt":"英文生图提示词（含尺寸约束）","seen":"你看到的具体形状特征"}"""


## 卡面通道开关（2026-11-05 圆桌：砍 SVG 改 card_face.json）。
## **默认 false**：主人此前钦定「通用大模型用自己的绘图能力输出 SVG」，改成程序化卡面
## 属于架构变更，需主人拍板后才把这里翻成 true。
static var use_face_mode := false


## 当前该用哪套提示词
static func active_prompt(has_image_gen: bool = false) -> String:
	if use_face_mode:
		return FACE_PROMPT
	## A 路径（有生图模型）：不画 SVG，只产 art_prompt + 卡牌属性
	return PALETTE_PROMPT if has_image_gen else VISION_PROMPT


## 好感度 → 画质要求（写给模型看；数值/机制加成在本地钳制层）
static func quality_hint(tier: int) -> String:
	match tier:
		2:
			return "
【品质要求】这张卡来自与你好感极深的创作者：请把 SVG 画到精修级——更多细节层次、渐变与高光、华丽的构图与装饰边框。"
		1:
			return "
【品质要求】这位创作者与你已有交情：请把 SVG 画得比平时更精致（补足细节与高光）。"
		_:
			return ""


## 好感度 → 输出预算（lv≥15 给 32k，写作画到尽兴）
static func max_tokens_for(affection_lv: int = -1) -> int:
	var lv := affection_lv if affection_lv >= 0 else Affection.level()
	return WISH_MAX_TOKENS_RETRY if lv >= 15 else WISH_MAX_TOKENS


## card_face.json 通道：不画 SVG，只给语义 token，客户端程序化渲染。
## 输出 token 从 ~3000 降到几百，模型耗时相应下降。
const FACE_PROMPT := """你在卡牌游戏《代码擂台》里，把玩家的**手绘草图**变成一张卡。

你收到的就是玩家亲手画的涂鸦（多模态图片），或玩家写的一句描述。

【第一步·看懂它】
先只描述**形状**：轮廓是什么轮廓？几条线？尖角还是圆角？有几个部件？有没有眼睛/腿/把手/翅膀？
以你真实看到的线条为准，不要按常见题材猜。

【第二步·卡面 token（不画图）】
不要输出 SVG，也不要输出图片。只输出一组**语义 token**，客户端会按 token 程序化绘制卡面：
- bg：背景色，十六进制，深色为主（如 #0B0F1A、#121A2B）
- primary：主体色（如 #C84C4C 红 / #4FA3E0 蓝 / #7ED957 绿 / #B47ED9 紫）
- accent：点缀色（高亮，如 #FFD166 / #7BE0D6）
- silhouette：主体剪影，只能从这六个里选：creature（生物）/ shield（护盾）/ weapon（武器）/ void（空洞）/ machine（机械）/ orb（圆球）
- density：点缀密度 0.0–1.0

【第三步·命名与机制】
卡名必须来自你识别出的**具体物件**（你看到什么就叫什么，不要起空泛的名字）。
像攻击生物/武器 → kind=attack 给 damage；像护盾/建筑/容器 → kind=skill 给 block。

【第四步·效果程序（可选但强烈建议）】
除了数值，你可以给这张卡写一小段**效果程序**。只能用下面这套语法：
- 触发器 when：`on_play`（打出时）｜`on_draw`（抽到时）｜`on_turn_start`（回合开始）｜`on_turn_end`（回合结束）｜`on_kill`（击杀时）｜`on_damage_dealt`（造成伤害后）｜`on_damage_taken`（受伤后）｜`on_seq_end`（序列结束时）
- 操作 do：
  - `damage`：{"do":"damage","amount":0-20}
  - `damage_scaled`：{"do":"damage_scaled","amount":0-20,"per":"same_kind_streak|cards_played_this_turn|hand_size|enemy_status_count|turn_number|hp_missing_pct|block","step":1-5}
  - `apply_status`：{"do":"apply_status","status":"weak|vulnerable|poison|strength|thorns","tier":1-3,"target":"enemy|self"}
  - `heal`：{"do":"heal","amount":1-10}
  - `draw`：{"do":"draw","amount":1-2}
  - `discard_random`：{"do":"discard_random","amount":1-2}
  - `multiply_next`：{"do":"multiply_next","factor":2-3}
  - `block`：{"do":"block","amount":0-20}
  - `duplicate_next`：{"do":"duplicate_next"}
  - `modify_intent`：{"do":"modify_intent","delta":-10到10}
- 可选条件 if：{"counter":"hand_size|same_kind_streak|cards_played_this_turn|enemy_status_count|turn_number|hp_missing_pct|block","gte":数字}
- **program 只能有 1 个操作**（一张卡只加一个新特色；超出会被本地截断）
- 基础伤害/格挡写进 `damage`/`block` 字段，**不要在 program 里再写一次**（会双倍结算）。
- 新特色二选一：要么"成长"（damage_scaled），要么"附加状态"（apply_status）——
  **不要两个都加**，那会让一张卡顶掉一整套组合。
没有合适机制就省略 program。

【输出】
只输出一行 JSON，不要 Markdown 围栏，不要解释：
{"name":"≤8字卡名","kind":"attack或skill","damage":0-20,"block":0-20,"draw":0-2,"desc":"≤30字效果描述","program":[],"face":{"bg":"#0B0F1A","primary":"#C84C4C","accent":"#FFD166","silhouette":"creature","density":0.6},"seen":"你看到的具体形状特征"}"""


## 从卡 JSON 里取 face token；没有或非法返回 {}
static func parse_ai_face(def: Dictionary) -> Dictionary:
	if def.is_empty() or not def.has("face"):
		return {}
	return CardFace.parse_face(def.get("face", {}))


## SVG → PNG（ThorVG 运行时渲染，铺深蓝底）；失败返回 false
static func render_svg_png(svg_text: String, out_path: String, target := 512) -> bool:
	var img := Image.new()
	var err := img.load_svg_from_string(svg_text, 1.0)
	if err != OK or img.get_width() <= 0:
		return false
	if img.get_width() != target or img.get_height() != target:
		img.resize(target, target, Image.INTERPOLATE_LANCZOS)
	var out := Image.create_empty(target, target, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.043, 0.059, 0.102))     ## #0B0F1A 与卡面底色一致
	out.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ImageGenClient.CACHE_DIR))
	return out.save_png(out_path) == OK


## ── 涂鸦识卡（视觉模型）：AI 出卡名/描述/机制，本地钳制数值 ──
## 铁律：AI 可以决定"这是什么"，但 damage/block/draw 必须过本地钳制——
## 上限 = 关卡预算（8 + 关卡序号×2），draw ≤2，描述截断。

static func parse_ai_card(text: String) -> Dictionary:
	## 从模型输出里抠 JSON（容忍 Markdown 围栏与前后废话）
	var i := text.find("{")
	var j := text.rfind("}")
	if i < 0 or j <= i:
		return {}
	var parsed = JSON.parse_string(text.substr(i, j - i + 1))
	if not (parsed is Dictionary):
		return {}
	return parsed


static func clamp_ai_card(def: Dictionary, level_index: int,
		affection_lv: int = -1) -> Dictionary:
	## affection_lv < 0 = 读全局好感；显式传 0 供测试隔离
	var alv := affection_lv if affection_lv >= 0 else Affection.level()
	var cap := 8 + maxi(0, level_index) * 2 + mini(alv, 12)
	var nm := String(def.get("name", "")).strip_edges().substr(0, WISH_CARD_NAME_MAX)
	if nm.is_empty():
		nm = "涂鸦造物"
	var kind := String(def.get("kind", "attack")).to_lower()
	if kind != "skill":
		kind = "attack"
	var desc := String(def.get("desc", "")).strip_edges().substr(0, 40)
	var seen := String(def.get("seen", "")).strip_edges().substr(0, 40)
	## 效果程序：先剔除"重复基础数值"的操作（damage/block 已在字段里，程序再写就是双倍），
	## 再本地编译 + 静默丢弃非法项（不重试，避免延迟翻倍）
	var filtered: Array = []
	var raw_prog = def.get("program", [])
	if raw_prog is Array:
		var base_dmg := int(def.get("damage", 0))
		var base_blk := int(def.get("block", 0))
		for c in raw_prog:
			if not (c is Dictionary):
				continue
			var kept: Array = []
			for op in c.get("then", []):
				if not (op is Dictionary):
					continue
				var do_key := String(op.get("do", ""))
				if do_key == "damage" and base_dmg > 0:
					continue
				if do_key == "block" and base_blk > 0:
					continue
				kept.append(op)
			if not kept.is_empty():
				var nc: Dictionary = (c as Dictionary).duplicate()
				nc["then"] = kept
				filtered.append(nc)
	var tier_boost := (1 if alv >= 10 else 0) + (1 if alv >= 25 else 0)
	for c in filtered:
		for op in c.get("then", []):
			if String(op.get("do", "")) == "apply_status":
				op["tier"] = clampi(int(op.get("tier", 1)) + tier_boost, 1, 3)
	var compiled := EffectDSL.compile(filtered, Affection.feature_ops() if alv > 0 else 1)
	var clauses: Array = compiled["clauses"]
	var effect_text := EffectDSL.describe(clauses)
	## 卡面文本以**引擎反渲染**为准：AI 写的 desc 只当风味，避免"写 5 点实际 50 点"
	if effect_text != "":
		desc = effect_text.substr(0, 60)
	if desc.is_empty():
		desc = "涂鸦造物：%s。" % ("造成 %d 点伤害" % int(def.get("damage", 8)))
	return {
		"name": nm,
		"kind": kind,
		"damage": clampi(int(def.get("damage", 8)), 0, cap),
		"block": clampi(int(def.get("block", 0)), 0, cap),
		"draw": clampi(int(def.get("draw", 0)), 0, 2),
		"desc": desc,
		"seen": seen,
		"program": clauses,
		"dsl_version": EffectSpec.VERSION if not clauses.is_empty() else 0,
		"dropped": int(compiled["dropped"]),
	}


static func make_from_ai(def: Dictionary, level_index: int,
		affection_lv: int = -1) -> StsCard:
	var c := clamp_ai_card(def, level_index, affection_lv)
	var card_id := "wish_ai_%s" % (String(c["name"]) + str(level_index)).sha256_text().substr(0, 10)
	var kind := StsCard.Kind.SKILL if String(c["kind"]) == "skill" else StsCard.Kind.ATTACK
	var card := StsCard.make(card_id, kind, 1, int(c["damage"]), int(c["block"]), "")
	card.draw = int(c["draw"])
	card.effects = c["program"]
	card.dsl_version = int(c["dsl_version"])
	## 定价：只查离线缓存，**绝不在许愿路径上跑模拟**。
	## 未命中时给保守上界（试玩档），离线批次跑完后下次命中就拿到真价。
	if not card.effects.is_empty():
		card.price_tier = int(EffectPricing.price_cached(
				card, level_index, EffectPricing.SAMPLES, false)["cost"])
	## 定价 → 出牌费用：cost 3 的卡每回合 4 点能量下会明显挤占出牌位
	card.cost = clampi(card.price_tier, 1, 3)
	StsCardPool.register_wish_meta(card_id, String(c["name"]), String(c["desc"]))
	return card


## 15 秒保险丝用的像素草图：**草稿纸**外观——纸色画布 + 铅笔双线框 +
## 中央画笔图标 + 底部虚线，一眼能认出「AI 还没画完，这是草稿」。
static func placeholder_png(text: String, card_id: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ImageGenClient.CACHE_DIR))
	var path := ImageGenClient.CACHE_DIR.path_join("wish_ph_%s.png" %
			card_id.sha256_text().substr(0, 12))
	if FileAccess.file_exists(path):
		return path
	var img := Image.create_empty(160, 160, false, Image.FORMAT_RGBA8)
	var paper := Color(0.93, 0.91, 0.84)          # 纸色
	var pencil := Color(0.30, 0.32, 0.36)         # 铅笔灰
	var accent := Color(0.20, 0.62, 0.85)         # 青色点题
	img.fill(paper)
	# 铅笔双线框（外框深、内框浅），四角留缺口更像手绘
	for x in range(8, 152):
		img.set_pixel(x, 8, pencil)
		img.set_pixel(x, 151, pencil)
	for y in range(8, 152):
		img.set_pixel(8, y, pencil)
		img.set_pixel(151, y, pencil)
	for x in range(12, 148, 3):
		img.set_pixel(x, 12, Color(0.62, 0.62, 0.60))
	for y in range(12, 148, 3):
		img.set_pixel(12, y, Color(0.62, 0.62, 0.60))
	# 中央画笔：斜杆 + 三角笔尖 + 两滴墨点
	for i in range(46):
		var x := 58 + i
		var y := 108 - i
		img.set_pixel(x, y, pencil)
		img.set_pixel(x + 1, y, pencil)
	for i in range(10):
		for j in range(10 - i):
			img.set_pixel(54 + i + j, 112 - j, accent)
	img.set_pixel(120, 62, accent)
	img.set_pixel(124, 56, accent)
	img.set_pixel(116, 70, accent)
	# 底部虚线（写作常用「待填」感）
	for x in range(24, 136, 8):
		for k in range(4):
			img.set_pixel(x + k, 136, pencil)
	if img.save_png(path) != OK:
		return ""
	return path
