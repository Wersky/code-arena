class_name IntroScript
extends Object
## 终端进场的文案：开机行 + 按角色生成的「定义该角色」的代码。
## 只放文本，不放逻辑——排版与节奏在 ExtTerminal / TerminalIntro 里。
##
## 文案要求（主人 2026-10-30）：
##   · 行数拉长、滚屏更快（总时长不变，靠 GameSettings.type_delay_for 反推每字间隔）
##   · 每隔几步插一条中文注释，让人知道这个「加载界面」在生成什么
## 注意：这些中文最终会写进 .ps1 由外部宿主执行，脚本必须带 UTF-8 BOM，
## 否则 PS 5.1 会按系统 ANSI 解码，中文全变乱码（见 ExtTerminal.play）。

static func boot_lines(ai_name: String) -> PackedStringArray:
	return PackedStringArray([
		"arena_os 4.7.2 :: cold boot",
		"mount /neural/core ......... ok",
		"load target profile: %s" % ai_name,
	])


## 每个角色一段"生成函数"。六步走，每步前面一句中文说明在干什么。
static func code_for(ai_id: String, ai_name: String) -> PackedStringArray:
	var fn := ai_id.replace("-", "_").replace(".", "_")
	return PackedStringArray([
		"/* ===== code_arena :: 正在生成 %s ===== */" % ai_name,
		"#include <neural/core.h>",
		"#define DEPTH 32",
		"#define MODEL_ID \"%s\"" % fn,
		"",
		"// [1/6] 生成基础架构：张量层、注意力头、显存分配",
		"typedef struct { float *w; int n; } Layer;",
		"static Layer stack[DEPTH];",
		"static void arch_alloc(void) { for (int i = 0; i < DEPTH; ++i) layer_new(&stack[i]); }",
		"",
		"// [2/6] 生成基本样式：发色、瞳色、服装、Q 版比例",
		"static void style_init(Style *s) { s->hair = HAIR_BLUE; s->dress = MAID_WHITE; s->eye = EYE_CYAN; s->scale = 0.75f; }",
		"// 蓝发双马尾 · 女仆裙荷叶边 · 青瞳 · Q 版比例",
		"",
		"// [3/6] 生成推理核心：逐层注意力 + 自反思回路",
		"static float think(const char *p) {",
		"    float v = 0.0f;",
		"    for (int l = 0; l < DEPTH; ++l) v += attn(p, l);",
		"    while (v < 1.0f) v += reason(v);",
		"    return v;",
		"}",
		"",
		"// [4/6] 生成性格参数：好奇 / 傲娇 / 忠诚",
		"static void soul_init(Soul *p) { p->curious = 0.92f; p->tsundere = 0.61f; p->loyalty = 1.00f; }",
		"// 好奇 0.92 · 傲娇 0.61 · 忠诚 1.00",
		"",
		"// [5/6] 生成战斗台词与出招口癖",
		"static const char *LINES[] = { \"让代码替我说话。\", \"这一步，算过了。\", \"你还没读懂我的意图。\" };",
		"",
		"// [6/6] 正在生成 AI 娘…… 拼装立绘 · 绑定动作 · 写入牌库",
		"int generate_%s(char *out, size_t cap) {" % fn,
		"    arch_alloc();",
		"    style_init(&style);",
		"    soul_init(&soul);",
		"    return emit(out, cap, think(\"win\"));",
		"}",
		"// done: %s 已就绪" % ai_name,
	])
