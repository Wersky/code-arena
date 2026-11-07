class_name EffectSpec
extends RefCounted
## 效果 DSL 的规格表（v1）——**唯一真相**。
##
## 圆桌定稿（2026-11-05）：AI 不挑"成品效果菜单"，而是用「触发器 × 条件 × 操作 ×
## 计数变量」自己写程序；本表只定义语法原语与数值档位，程序由 AI 产出、本地校验。
##
## 三条硬约束（圆桌第 1 轮）：
##   1. 静态 ≤4 clause / ≤6 op（本表 LIMITS）
##   2. 运行期全局 op 预算 64（防链式放大）
##   3. 触发深度 1（效果不再触发效果）
##
## 改本表必须同时 +1 VERSION：许愿卡会长期躺在牌组里，语义漂移会让老卡行为变样。

const VERSION := 1

const LIMITS := {
	"max_clauses": 4,
	"max_ops": 1,
	"op_budget": 64,
	"trigger_depth": 1,
}

## 触发器 → 说明
const TRIGGERS := {
	"on_play": "打出时",
	"on_draw": "抽到时",
	"on_turn_start": "回合开始时",
	"on_turn_end": "回合结束时",
	"on_kill": "击杀时",
	"on_damage_dealt": "造成伤害后",
	"on_damage_taken": "受到伤害后",
	"on_seq_end": "序列结束时",
}

## 计数变量（damage_scaled 的燃料 / 条件判断）
const COUNTERS := {
	"same_kind_streak": "本序列同类连击阶数",
	"cards_played_this_turn": "本回合已出牌数",
	"hand_size": "当前手牌数",
	"enemy_status_count": "敌人身上状态数",
	"turn_number": "当前回合数",
	"hp_missing_pct": "已损失生命百分比",
	"block": "当前格挡",
}

## 操作：label / args / writes（写集维度）
##   target 出现在 args 里的 op 由 AI 指定；writes 供写集签名与组合检测用。
const OPS := {
	"damage": {
		"label": "伤害",
		"args": {
			"amount": {"type": "int", "min": 0, "max": 20, "default": 4},
		},
		"writes": ["enemy_hp"],
	},
	"damage_scaled": {
		"label": "按计数成长伤害",
		"args": {
			"amount": {"type": "int", "min": 0, "max": 20, "default": 0},
			"per": {"type": "enum", "values": ["same_kind_streak", "cards_played_this_turn",
					"hand_size", "enemy_status_count", "turn_number", "hp_missing_pct",
					"block"], "default": "same_kind_streak"},
			"step": {"type": "int", "min": 1, "max": 5, "default": 2},
		},
		"writes": ["enemy_hp"],
	},
	"apply_status": {
		"label": "施加状态",
		"args": {
			"status": {"type": "enum", "values": ["weak", "vulnerable", "poison",
					"strength", "thorns"], "default": "weak"},
			"tier": {"type": "int", "min": 1, "max": 3, "default": 1},
			"target": {"type": "enum", "values": ["enemy", "self"], "default": "enemy"},
		},
		"writes": ["enemy_status", "player_status"],
	},
	"heal": {
		"label": "回复生命",
		"args": {
			"amount": {"type": "int", "min": 1, "max": 10, "default": 3},
		},
		"writes": ["player_hp"],
	},
	"draw": {
		"label": "抽牌",
		"args": {
			"amount": {"type": "int", "min": 1, "max": 2, "default": 1},
		},
		"writes": ["deck_order"],
	},
	"discard_random": {
		"label": "随机弃牌",
		"args": {
			"amount": {"type": "int", "min": 1, "max": 2, "default": 1},
		},
		"writes": ["deck_order"],
	},
	"multiply_next": {
		"label": "下一张增幅",
		"args": {
			"factor": {"type": "int", "min": 2, "max": 3, "default": 2},
		},
		"writes": ["resource"],
	},
	"block": {
		"label": "获得格挡",
		"args": {
			"amount": {"type": "int", "min": 0, "max": 20, "default": 5},
		},
		"writes": ["player_block"],
	},
	"duplicate_next": {
		"label": "下一张执行两次",
		"args": {},
		"writes": ["resource"],
	},
	"modify_intent": {
		"label": "改写敌人意图",
		"args": {
			"delta": {"type": "int", "min": -10, "max": 10, "default": -3},
		},
		"writes": ["enemy_intent"],
	},
}

## 状态定义：tiers 是 1/2/3 档的「数值」（turns 固定见 turns）
const STATUSES := {
	"weak": {
		"label": "降智", "desc": "造成的伤害 −25%",
		"turns": [1, 2, 2], "dmg_out_mult": 0.75, "dim": "global_counter",
	},
	"vulnerable": {
		"label": "上下文污染", "desc": "受到的伤害 +25%",
		"turns": [1, 2, 2], "dmg_in_mult": 1.25, "dim": "global_counter",
	},
	"poison": {
		"label": "内存泄漏", "desc": "每回合结束掉血（无视护盾）",
		"turns": [3, 3, 3], "dot": [2, 4, 6], "dim": "persistent",
	},
	"strength": {
		"label": "算力注入", "desc": "攻击牌伤害 +N",
		"turns": [99, 99, 99], "atk_bonus": [1, 2, 3], "dim": "persistent",
	},
	"thorns": {
		"label": "防火墙", "desc": "被攻击时反伤 N",
		"turns": [3, 3, 3], "reflect": [2, 4, 6], "dim": "global_counter",
	},
}

## 写集维度（组合检测用；v1 只做签名，不做并集判定）
const DIMENSIONS := ["enemy_hp", "player_hp", "enemy_block", "player_block",
		"enemy_status", "player_status", "deck_order", "resource"]


static func status_value(status: String, tier: int, field: String) -> int:
	var s: Dictionary = STATUSES.get(status, {})
	var arr = s.get(field, [])
	if arr is Array and arr.size() >= clampi(tier, 1, 3):
		return int(arr[clampi(tier, 1, 3) - 1])
	return 0


static func status_turns(status: String, tier: int) -> int:
	return status_value(status, tier, "turns")


## 规格表导出（交付物 dsl_spec.json 的内容，可写盘供外部工具/AI 提示词使用）
static func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"limits": LIMITS,
		"triggers": TRIGGERS,
		"counters": COUNTERS,
		"ops": OPS,
		"statuses": STATUSES,
		"dimensions": DIMENSIONS,
	}
