extends State
## 攻击状态。hitbox 的开关由状态生命周期管，不由动画轨道管。
##
## 装配：挂在 AttackSubFSM（或 ActionSubFSM）下，名 "Attack"。
## 依赖角色节点上有：animation_player / hitbox / attack_cd_timer / control_manager / move()

## 攻击冷却：防连点。与"输入缓冲"是两套——buffer 管能否接指令，CD 管能否打出伤害
@export var attack_cd: float = 0.2

func enter() -> void:
	character.animation_play("attack")
	# 消费掉本次缓冲，避免动画播完立刻被同一次按键再触发一次
	character.control_manager.control_buffer_timer.get("attack").stop()
	character.hitbox.disabled = false
	SoundManager.play_sfx("PlayerAttack")

func exit() -> void:
	character.hitbox.disabled = true            # ★ 关判定
	character.attack_cd_timer.start(attack_cd)  # ★ 起 CD

func tick(delta: float) -> void:
	# 动画播完即回移动层
	if character.animation_player.current_animation != "attack":
		change_to("ActionSubFSM")
		return
	# 攻击中仍受控制（可微调位置），但速度用常值
	character.refresh_control_direction()
	character.move(delta,
		character.control_direction,
		character.move_speed,
		character.move_speed * character.acceleration_multiplier,
		character.gravity)
