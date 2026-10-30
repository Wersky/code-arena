class_name IntroScript
extends Object
## 终端进场的文案：开机行 + 按角色生成的「定义该角色」的代码。
## 只放文本，不放逻辑——排版与节奏在 ExtTerminal / TerminalIntro 里。
##
## 文案要求（主人 2026-10-30）：中文注释只留一两句，收尾一行固定标「正在生成 AI 娘中」。
## 注意：这些中文最终会写进 .ps1 由外部宿主执行，脚本必须带 UTF-8 BOM，
## 否则 PS 5.1 会按系统 ANSI 解码，中文全变乱码（见 ExtTerminal.play）。

## 终端和 Godot 两边都要显示的同一句话（1:1 复刻：同字、同格、同位置）
const CAPTION := "正在生成 AI 娘中"


static func boot_lines(ai_name: String) -> PackedStringArray:
	return PackedStringArray([
		"arena_os 4.7.2 :: cold boot",
		"mount /neural/core ......... ok",
		"load target profile: %s" % ai_name,
	])


## 这句话在终端里占多少**格**（中文占 2 格）。
## 两边都用这个数算居中，不然中文宽度算错就错位。
static func caption_cells() -> int:
	var w := 0
	for i in CAPTION.length():
		w += 2 if _is_wide(CAPTION[i]) else 1
	return w


static func _is_wide(ch: String) -> bool:
	var cp := ch.unicode_at(0)
	return (cp >= 0x2E80 and cp <= 0xA4CF) \
		or (cp >= 0xAC00 and cp <= 0xD7A3) \
		or (cp >= 0xF900 and cp <= 0xFAFF) \
		or (cp >= 0xFE30 and cp <= 0xFE6F) \
		or (cp >= 0xFF00 and cp <= 0xFF60) \
		or (cp >= 0xFFE0 and cp <= 0xFFE6)


## 每个角色一段"生成函数"：注释只留两句，最后一行标明「正在生成 AI 娘中」。
static func code_for(ai_id: String, ai_name: String) -> PackedStringArray:
	var fn := ai_id.replace("-", "_").replace(".", "_")
	return PackedStringArray([
		"/* ===== code_arena :: %s ===== */" % ai_name,
		"#include <neural/core.h>",
		"#define DEPTH 32",
		"#define MODEL_ID \"%s\"" % fn,
		"",
		"// 先搭架构、定样式，再写性格与台词。",
		"typedef struct { float *w; int n; } Layer;",
		"static Layer stack[DEPTH];",
		"static void style_init(Style *s) { s->hair = HAIR_BLUE; s->dress = MAID_WHITE; s->eye = EYE_CYAN; }",
		"static void soul_init(Soul *p) { p->curious = 0.92f; p->tsundere = 0.61f; p->loyalty = 1.00f; }",
		"static float think(const char *p) { float v = 0.0f; for (int l = 0; l < DEPTH; ++l) v += attn(p, l); return v; }",
		"",
		"// 正在生成 AI 娘中……",
		"int generate_%s(char *out, size_t cap) {" % fn,
		"    style_init(&style); soul_init(&soul);",
		"    return emit(out, cap, think(\"win\"));",
		"}",
	])
