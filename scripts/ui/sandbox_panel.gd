class_name SandboxPanel
extends PanelContainer
## 体验沙盒面板（F1 开关，2026-11-01 主人钦定）：
## 一个按钮直达一项内容——形态/战斗/遭遇/道具/演出全覆盖。
## main 注入 actions 字典（键 → Callable），面板只负责排版与触发。

var _grid: VBoxContainer = null


func _init() -> void:
	custom_minimum_size = Vector2(250, 0)
	add_theme_stylebox_override("panel",
			UiKit.flat(Color(0.02, 0.03, 0.05, 0.93), UiKit.ACCENT, 2, UiKit.SP_3, UiKit.EL_2))
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("sandbox")


func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiKit.SP_2)
	add_child(v)

	var head := UiKit.title("体验沙盒 · F1", UiKit.FS_XS)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(230, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	_grid = VBoxContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("separation", UiKit.SP_1)
	scroll.add_child(_grid)


func build(actions: Dictionary) -> void:
	for c in _grid.get_children():
		c.queue_free()
	var groups := [
		["形态", [
			["翻身 · 2碗", "stir"],
			["完全觉醒 · 5碗", "awake"],
			["睡回去", "sleep"],
		]],
		["战斗", [
			["秒杀敌人 · 胜利全流程", "win"],
			["精英战 · 必掉宝箱", "elite"],
			["满血恢复", "heal"],
		]],
		["遭遇（事件①-⑤）", [
			["事件① 服务器着火", "ev0"],
			["事件② AI取代人类", "ev1"],
			["事件③ 温度旋钮", "ev2"],
			["事件④ 显卡炼丹炉", "ev3"],
			["事件⑤ 大V对线", "ev4"],
		]],
		["门界面（强制）", [
			["下一门 = 事件门", "door_event"],
			["下一门 = 奖励门", "door_bonus"],
			["下一门 = 精英门", "door_elite"],
			["下一门 = 恢复随机", "door_none"],
		]],
		["道具", [
			["提示词优化器", "item_opt"],
			["子代理零件", "item_parts"],
			["上下文压缩", "item_compress"],
		]],
		["演出", [
			["终结技 · 深度思考", "ult"],
			["斩击特效", "fx_slash"],
			["盾框特效", "fx_shield"],
			["爪击特效", "fx_claw"],
			["燃尽画面", "burnout"],
		]],
	]
	for g in groups:
		var gl := UiKit.label(String(g[0]), UiKit.FS_XS, UiKit.GOLD)
		_grid.add_child(gl)
		for item in g[1]:
			var btn := UiKit.button(String(item[0]), UiKit.FS_XS)
			btn.custom_minimum_size = Vector2(0, 30)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var key := String(item[1])
			if actions.has(key):
				btn.pressed.connect(func() -> void:
					SfxNode.play("ui_click")
					actions[key].call())
			else:
				btn.disabled = true
			_grid.add_child(btn)
