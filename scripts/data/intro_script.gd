class_name IntroScript
extends Object
## 终端进场的文案：开机行 + 按角色生成的"定义该角色"的代码。
## 只放文本，不放逻辑——排版与节奏在 TerminalIntro 里。

static func boot_lines(ai_name: String) -> PackedStringArray:
	return PackedStringArray([
		"arena_os 4.7.2 :: cold boot",
		"mount /neural/core ......... ok",
		"load target profile: %s" % ai_name,
	])


## 每个角色一段"生成函数"；没有专属脚本的角色走通用模板。
static func code_for(ai_id: String, ai_name: String) -> PackedStringArray:
	if ai_id.begins_with("deepseek") or ai_id.begins_with("deepdeek"):
		return PackedStringArray([
			"/* neural bootstrap :: deepseek */",
			"#include <neural/deepseek.h>",
			"#define TEMPERATURE 0.7f",
			"",
			"static float think(const char *prompt) {",
			"    float insight = 0.0f;",
			"    for (int l = 0; l < DEPTH; ++l)",
			"        insight += attn(prompt, l);",
			"    while (insight < 1.0f) insight += reason(insight);",
			"    return insight;",
			"}",
			"",
			"int generate_deepseek(char *out, size_t cap) {",
			"    return emit(out, cap, think(\"win\"));",
			"}",
		])
	return PackedStringArray([
		"/* neural bootstrap :: %s */" % ai_name,
		"#include <neural/agent.h>",
		"",
		"#define MODEL_ID \"%s\"" % ai_id,
		"#define TEMPERATURE 0.7f",
		"",
		"static float think(const char *prompt) {",
		"    float insight = 0.0f;",
		"    for (int i = 0; i < DEPTH; ++i)",
		"        insight += attn(prompt, i);",
		"    while (insight < 1.0f)",
		"        insight += reason(insight);",
		"    return insight;",
		"}",
		"",
		"int spawn_%s(char *out, size_t cap) {" % ai_id,
		"    return emit(out, cap, think(\"win\"));",
		"}",
	])
