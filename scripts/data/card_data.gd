class_name CardData
extends Resource
## 提示词组件卡。
##
## 一张卡 = 提示词里的一个组件。kind 决定颜色与牌型归属；
## risky 是跨类型的正交标记（臆造/跳过验证），命中会吃惩罚但倍率更高。

enum Kind { PERSONA, TASK, KNOWLEDGE, FORMAT, EXAMPLE, CONSTRAINT }

const KIND_NAMES := {
	Kind.PERSONA: "角色",
	Kind.TASK: "任务",
	Kind.KNOWLEDGE: "素材",
	Kind.FORMAT: "格式",
	Kind.EXAMPLE: "范例",
	Kind.CONSTRAINT: "约束",
}

const KIND_COLORS := {
	Kind.PERSONA: Color(0.31, 0.79, 0.69),
	Kind.TASK: Color(0.91, 0.77, 0.35),
	Kind.KNOWLEDGE: Color(0.35, 0.66, 0.90),
	Kind.FORMAT: Color(0.71, 0.55, 0.88),
	Kind.EXAMPLE: Color(0.91, 0.57, 0.35),
	Kind.CONSTRAINT: Color(0.49, 0.78, 0.35),
}

## 规范顺序：预览面板按这个顺序把打出的卡重排成最终提示词
const KIND_ORDER := [
	Kind.PERSONA, Kind.TASK, Kind.KNOWLEDGE, Kind.FORMAT, Kind.EXAMPLE, Kind.CONSTRAINT,
]

@export var title: String = ""
@export var kind: Kind = Kind.TASK
@export var base_score: int = 10
@export var token_cost: int = 1
@export var risky: bool = false
@export var body: String = ""
@export var upgraded: bool = false

# ── 命令行片段（新版提示词机制）──────────────────────
## 这张卡对应的命令行参数名，由 kind 唯一决定
@export var cli_arg: String = ""
## 这张卡对应的命令行参数值（默认等于卡标题）
@export var cli_token: String = ""


static func kind_name(k: int) -> String:
	return KIND_NAMES.get(k, "?")


## 类型对应的美术资源名（card-<slug>.png）
static func kind_slug(k: int) -> String:
	match k:
		Kind.PERSONA:
			return "persona"
		Kind.TASK:
			return "task"
		Kind.KNOWLEDGE:
			return "knowledge"
		Kind.FORMAT:
			return "format"
		Kind.EXAMPLE:
			return "example"
		Kind.CONSTRAINT:
			return "constraint"
	return "task"


static func kind_color(k: int) -> Color:
	return KIND_COLORS.get(k, Color(0.6, 0.6, 0.6))


## 生成一张强化后的副本（+基础分、-Token），用于奖励与商店。
func upgraded_copy() -> CardData:
	var c := CardData.new()
	c.title = title
	c.kind = kind
	c.base_score = base_score + 6
	c.token_cost = maxi(1, token_cost - 1)
	c.risky = risky
	c.body = body
	c.upgraded = true
	c.cli_arg = cli_arg
	c.cli_token = cli_token
	return c


func display_score() -> int:
	return base_score + (3 if upgraded else 0)


## 某个卡类型对应的参数名
static func cli_arg_for_kind(k: int) -> String:
	match k:
		Kind.PERSONA:
			return "--role"
		Kind.TASK:
			return "--task"
		Kind.KNOWLEDGE:
			return "--knowledge"
		Kind.FORMAT:
			return "--format"
		Kind.EXAMPLE:
			return "--example"
		Kind.CONSTRAINT:
			return "--constraint"
	return ""


## 这张卡合成出的命令行片段，形如 `--role "资深工程师"`
func cli_fragment() -> String:
	return "%s \"%s\"" % [cli_arg, cli_token.replace("\"", "\\\"")]


## cli_token 是否合法（长度 ≤ 20 且非空）
func is_cli_token_valid() -> bool:
	return cli_token != "" and cli_token.length() <= 20
