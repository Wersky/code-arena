class_name HurtState extends State
## 受击状态：无敌帧 + 慢镜 + 震屏 + 击退 + 闪白，全在这一个状态里。
## 装配：挂在 AttackSubFSM 下，名 "Hurt"。
## 依赖角色节点上有：hurtbox / hurt_timer / hurt_slow_timer / hurt_particle /
##                  game_camera / face_direction / velocity / move()
## 以及一个"游戏速度基准"（如 Config.game_speed，默认 1.0）——恢复慢镜时回到它，不是硬编码 1.0。

@export var knockback_horizontal: float = 40.0
@export var knockback_vertical: float = -60.0
@export var hurt_time: float = 0.8            ## 无敌帧时长
@export var slow_scale: float = 0.5           ## 慢镜倍率
@export var slow_duration: float = 0.15       ## 慢镜持续

func enter() -> void:
	SoundManager.play_sfx("PlayerHit")
	character.hurt_particle.restart()
	character.animation_play("hurt")

	# ① 无敌帧 = 关 hurtbox（物理层的真门，不是布尔标志）
	character.hurtbox.disabled = true
	character.hurt_timer.start(hurt_time)
	character.set_process(true)               # 开始闪白

	# ② 击退：方向由"伤害来源"决定，face_direction 已在受击回调里转向来源侧
	character.velocity.x = -character.face_direction * knockback_horizontal
	character.velocity.y = knockback_vertical

	# ③ 打击感：震屏 + 顿帧
	character.game_camera.shake(2.0, 0.3)
	Engine.time_scale = slow_scale
	character.hurt_slow_timer.start(slow_duration)

func exit() -> void:
	# 兜底：若计时器还没跑完就退出状态，保证速度基准恢复
	if not character.hurt_slow_timer.is_stopped():
		character.hurt_slow_timer.stop()
		Engine.time_scale = character.game_speed

func tick(delta: float) -> void:
	# 结束条件：落地 或 无敌帧结束（取先到）
	if character.is_on_floor() or character.hurt_timer.is_stopped():
		if character.is_on_floor():
			character.velocity.x = 0.0
		change_to("AttackSubFSM")             # 回到"战斗"分层（其 enter 会归位到移动层）
		return
	character.move(delta,
		-character.face_direction,
		knockback_horizontal,
		knockback_horizontal * 8.0,
		character.gravity)
