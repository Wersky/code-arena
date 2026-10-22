---
name: gd-action-combat-2d
description: "Expert patterns for 2D side-scrolling action combat (Hollow Knight / Castlevania style): layered state machine for player attacks, input buffering, hitbox/hurtbox damage pipeline with i-frames, knockback by damage source direction, hitstop/screen-shake/hurt-flash game feel, enemy and boss AI organization, multi-stage boss battles. Use when building 2D action platformers or metroidvanias with real-time melee/ranged combat. Trigger keywords: action combat, hollow knight, metroidvania combat, hitbox, hurtbox, i-frames, invincibility frames, knockback, hitstop, screen shake, hurt flash, boss stage, attack state machine, input buffer, 横版动作, 类空洞骑士, 打击感."
metadata:
  engine-version: "4.7"
  source: "godot 工作区横版动作实例深读（bread-adventure 4.5 / toziuha-night-oota）"
  license: "MIT"
---

# 2D 横版动作战斗（类空洞骑士）

实时动作战斗的落地模式。**与 `gd-combat-system` 的分工**：那个给通用伤害管线（DamageData/HealthComponent/hitbox 架构），这个给"横版动作专有"的部分——玩家攻击状态机、输入缓冲、无敌帧门、击退方向、打击感三件套、Boss 阶段推进。

来源：两个开源实例的源码级深读（结论均可回溯，见 `D:/zcode-work/godot/docs/20-横版动作实例深读笔记.md`）。

- `wheafun/bread-adventure`（69★ Apache-2.0，Godot 4.5）← 主要模式来源，代码是现代 Godot 4 写法
- `dannygaray60/toziuha-night-oota`（141★ MIT，Godot 3.x）← 完整恶魔城成品，多段命中去重/持续伤害

## NEVER Do

- **NEVER 把输入检测和动作执行写在同一层**——攻击键如果在"移动状态"里被消费，同时又在"攻击状态"里被判一次，一次按键会触发两刀。用**层级状态机 + 只在最内层消费输入**（见 §1）。
- **NEVER 用布尔 `is_invincible` 手写无敌帧**——直接 `hurtbox.disabled = true` + 一个一次性 Timer，超时再开。布尔标志会漏掉"多段碰撞同帧命中"，关碰撞体是物理层的真门。
- **NEVER 让无敌帧和闪白用两个计时器**——共用一个 `hurt_timer`：计时器没停就闪白，停了就恢复（`_process` 里 `if hurt_timer.is_stopped(): return`）。
- **NEVER 硬编码 `Engine.time_scale = 1.0` 恢复慢镜**——用户可能设了 0.8 倍速。存一个 `Config.game_speed` 作为"基准"，临时慢镜结束后恢复到基准而不是 1.0。
- **NEVER 在 `_physics_process` 里直接改 CollisionShape2D.disabled**——用 `set_deferred("disabled", ...)`，物理帧内改会报错。
- **NEVER 让 hitbox 常开**——攻击状态 `enter` 开、`exit` 关；敌人死亡时 hitbox/hurtbox/CollisionShape 三关。
- **NEVER 把敌人 AI 写成 `_physics_process` 里的 if-else 长链**——受击打断、招式计数、阶段推进都会失控。用行为树或状态机（§5）。
- **NEVER 用位置对比算击退方向**——用伤害来源的 `location.x` 与自身 `global_position.x` 比较，**同一次受击既扣血又转向**，否则击退方向会反。
- **NEVER 用 `free()` 删敌人**——`queue_free()`；且死亡时若在屏幕外可直接删（不必等飞出）。
- **NEVER 用字符串做伤害类型/状态名**——`@export_flags` 位域（伤害类型）与 `StringName`（状态名），见 `gd-combat-system` 的同款纪律。

## 1. 层级状态机：攻击中不被重复触发

**结构**（bread-adventure 实测）：

```
StateMachine          initial_state = AttackSubFSM
└─ AttackSubFSM       initial_state = ActionSubFSM          ← 战斗分层
   └─ ActionSubFSM    Idle / Run / Fall / Dash / Attack...  ← 只有这里消费攻击键
```

- `State` 基类：`signal change(target)` + `enter()/exit()/tick(delta)`。
- `SubStateMachine extends State` —— 所以子状态机能当状态用，天然支持嵌套。
- **状态就是子节点名**，`change_state("Attack")` 内部 `get_node_or_null(target)`，场景树即状态表，编辑器里能直接看层级。
- **子状态机 `enter()` 时重设 `current_state`**（按是否在地面选 Idle/Run/Fall）——受击/攻击结束后自然回到移动，而不是回到上一次的攻击状态。
- 见 `scripts/layered_state_machine.gd`（含 State / SubStateMachine / 三层装配示例）。

**输入消费的优先级写法**（`ActionSubFSM.tick`）：

```gdscript
func tick(delta: float) -> void:
    if (character.status.attack > 0
        and character.control_manager.control_request("attack")
        and character.attack_cd_timer.is_stopped()):
        change_to("Attack")
        return                      # ★ 同帧不再判后续动作
    if character.control_manager.control_request("shoot"):
        ...
        change_to("Shoot"); return
```

每个动作 = `buffer 请求` + `CD 就绪` + `前置条件` 三个门，**命中即 return**。

## 2. 输入缓冲：ControlManager

0.1s 一次性 Timer × 每个动作（jump/dash/attack/shoot/throw）：

```gdscript
# _physics_process 里
if InputManager.is_action_just_pressed(key):
    control_buffer_timer[key].start()
# 自动攻击（可选，按住即连发）
if Config.auto_attack and key in ["attack", "shoot"]:
    if InputManager.is_action_pressed(key): control_buffer_timer[key].start()

func control_request(action: String) -> bool:
    return not control_buffer_timer.get(action).is_stopped()
```

**关键点**：
- Timer 用 `Timer.new()` 代码创建（别在场景里堆 5 个 Timer 节点）。
- **buffer 与 CD 是两套东西**：buffer 管"这刀能不能接上"，CD 管"能不能打出伤害"。`Attack.exit()` 里 `attack_cd_timer.start()`。
- **"本次滞空是否已用"用布尔门而非 CD**：`dashed` / `double_jumped` / `threw_jelly`，落地时由 Jump 状态重置——状态轴比时间轴准。
- `valid_dash_request()` = `control_request("dash") and not dashed and dash_cd.is_stopped()`。
- 见 `scripts/input_buffer.gd`。

## 3. 伤害管线：Hitbox 统一信号

```gdscript
class_name Hitbox extends Area2D
signal collided(source: CollideSource, damage: int, location: Vector2)
enum CollideSource { ENVIRONMENT, PLAYER, ENEMY, BULLET }
```

- `_on_area_entered`：按 `area.owner` 归类来源（`is Player` → PLAYER；`is_in_group("enemy"/"boss")` → ENEMY；`is_in_group("bullet")` → BULLET）。
- `_on_body_entered`：`is TileMapLayer` → ENVIRONMENT（damage 0，专用于触发撞墙反馈）；`is Player` → PLAYER（敌人身体撞玩家）。
- `disabled` 是 `@export` 带 setter，赋值即遍历子节点 `set_deferred("disabled", v)`。
- **角色侧只回答三个问题**：我被打到了吗（signal）、多少伤害、从哪来（location）。
- 见 `scripts/hitbox_source.gd`。

**受击处理骨架（player 侧，含减伤/方向/无敌帧）**：

```gdscript
func _on_hurtbox_collided(source, damage, location) -> void:
    if state_machine.state_name() == "Hurt":   # 重入保护看状态名
        return
    var desire_damage := damage
    # 冲刺免疫正面伤害（类空洞骑士"冲刺无敌"，但更有策略性）
    if (Status.has("dash_shield") and attack_fsm.state_name() == "Dash"
        and source != Hitbox.CollideSource.ENVIRONMENT
        and ((face_direction == RIGHT and location.x > global_position.x)
          or (face_direction == LEFT  and location.x < global_position.x))):
        desire_damage = 0; state_machine.change_state("DashShield"); return
    match source:
        ENVIRONMENT:   # 地形伤害独立分支：关碰撞体 + 回安全点
            desire_damage = 1
            collision_shape_2d.set_deferred("disabled", true)
            back_safe_spot_timer.start()
        ENEMY, BULLET: # 朝向 = 伤害来源方向
            if location.x > global_position.x: face_direction = RIGHT
            elif location.x < global_position.x: face_direction = LEFT
    status.health -= desire_damage
    if status.health <= 0: dead.emit(); state_machine.change_state("Die")
    else: state_machine.change_state("Hurt")
```

**安全点（掉落重生）必须是"稳定站立且无危险"的位置**：`is_on_floor()` + 多个地面射线都在 + 尖刺检测器无重叠 + 非受伤中，才更新 `safe_spot`。

## 4. 无敌帧 = 关 hurtbox + 一次性 Timer

```gdscript
func enter():                                    # Hurt 状态
    character.hurtbox.disabled = true            # ★ 无敌帧
    character.hurt_timer.start(Constant.HURT_TIME)   # 0.8s，道具可延长到 1.2s
    character.set_process(true)                  # 开始闪白
    character.velocity.x = -face_direction * KNOCKBACK_H
    character.velocity.y = KNOCKBACK_V
    camera.shake(2, 0.3)                         # 震屏
    Engine.time_scale = 0.5; hurt_slow_timer.start()   # 顿帧/慢镜

func _on_hurt_timer_timeout():                   # 超时恢复
    if alive: hurtbox.disabled = false
    set_process(false); reset_flash.call_deferred()
```

- **受击状态结束条件**：落地 **或** 无敌帧结束（取先到）；落地时清横向速度防滑。
- **敌人/Boss 的 hurtbox 按伤害量分级恢复**：`damage >= 50 ? hurt_timer.start(0.6) : 0.2`——重击硬直更久，是打击感回报的关键。
- **敌人受击要重置 AI**：`behavior_tree.child_nodes[0].reset()`（打断当前动作）。
- 死亡：`alive = false` + 关 hitbox/hurtbox/CollisionShape + 掉宝 + 屏幕外直接 `queue_free()`。

## 5. 敌人与 Boss 的 AI 组织

**三种方案，按复杂度选**：

| 方案 | 适用 | 本地资源 |
|---|---|---|
| 状态机（自研） | < 5 个状态的小怪 | `gd-state-machine-advanced` |
| **行为树（自研 Node 树）** | 多招式、需要随机/打断/计数 | 本技能 §5.1（bread-adventure 模式，约 400 行可自建） |
| 行为树插件 | 想要可视化调试器 | `gd-beehave`（GDScript 轻量）/ `gd-limboai`（C++ 重型，带 HSM） |

### 5.1 自研行为树最小集（bread-adventure 的节点清单）

- 基类 `BehaviorTreeNode`：`enum BTState {RUNNING, SUCCESS, FAILURE}` + `_enter()/exit()/tick(delta)/reset()`；`child_nodes` 在 `_ready` 收集。
- 控制节点：`Selector`（OR，可 `is_random` 随机分支）、`Sequence`（AND）、`Parallel`（AND/OR 模式）。
  **关键细节：Selector/Sequence 要"从上次的子节点继续执行"（`running_child_index`）而非每次重头**，否则 RUNNING 语义会错。
- 装饰器：`Inverter`、`Failer`、`Succeeder`、`Waiter`（等待 N 秒）、`Delayer`、`TimeLimiter`、**`TimesLimiter`（限制子节点执行次数，做"这招最多连放 N 次"）**、`Monitor`（等信号）。
- ⚠️ **`TimesLimiter` 的两个陷阱（本技能 headless 实测确认）**：① **要限次必须设 `ignore_child = true`**——默认 false 时子节点结果直接透传给父节点，计数恒为 0，完全没有限次效果（这是最容易踩的一个）；② 计数在 `_enter()` 时重置，父节点每次重新进入它 = 一个新的连放窗口。见 `scripts/bt_times_limiter.gd` 注释与 `scripts/bt_smoke_test.gd` 的实测断言。
- 叶子 `Action` 子类：**每个招式一个脚本**，只回答"怎么打"（发子弹/算抛物线/播动画），不回答"什么时候打"（后者归树）。
- `reset()` 必须在控制节点里正确 `_exit()` 正在运行的子节点，否则受击打断会残留状态。
- **验证方式**：`scripts/bt_smoke_test.gd` 是可直接跑的 headless 断言（Sequence/Selector 的 RUNNING 语义、TimesLimiter 限次与重置、reset 中断），新建行为树后先跑它确认语义没写歪。
- **Boss 战 = 一棵树 + 阶段计数器**：

```
BehaviorTree (RootNode)
└─ Parallel (AND)
   ├─ ChangeStage          ← 装饰器：监听 stage_change 信号 → 切分支
   └─ Selector
      └─ Sequence(阶段1)
         ├─ IsStageChange → PlayHurt → WaitFall → Idle → Waiter → WaitCharge
         │  → JumpToFar → WaitFall2 → Idle2 → WaitReady → Waiter3 → PlayAttackAnim → PushStageChange
         └─ Inverter → TimesLimiter → Sequence(阶段2 的招式序列)
```

阶段推进：招式叶子的 `exit()` 里 `stage_change.emit()` → `ChangeStage` 装饰器收到就切下一分支。
**Boss 阶段计数用"命中次数"而非血量阈值**（toziuha 的做法：`received_hits == 10` → 换阶段）——好处是阶段与玩家 DPS 无关，节奏稳定。

**Boss 的三关冻结/解锁**：

```gdscript
func _ready(): hitbox.disabled = true; hurtbox.disabled = true; behavior_tree.disabled = true
func start_battle():   # 由房间演出脚本调用
    hitbox.disabled = false; hurtbox.disabled = false; behavior_tree.disabled = false
    Game.get_player().dead.connect(_win, CONNECT_ONE_SHOT)   # 防同归于尽
func stop_battle():
    behavior_tree.reset(); behavior_tree.disabled = true
    hitbox.disabled = true; hurtbox.disabled = true; hurt_timer.stop()
```

## 6. 打击感三件套（横版动作的命脉）

### 6.1 顿帧 / 慢镜

受击瞬间 `Engine.time_scale = 0.5` + 独立 Timer 恢复。**必须分层**：

```gdscript
# Config.game_speed 是用户设置的基准速度（如 0.8/1.0/1.2）
Engine.time_scale = 0.5               # 临时慢镜
...
Engine.time_scale = Config.game_speed # 恢复到基准，不是 1.0
```

过度动画跳过用 `Engine.time_scale = 4.0`（按住 ui_accept），松开回 1.0。

### 6.2 震屏（两种实现，都验证过）

**A. 噪声补间（bread-adventure，效果更"有形"）**：

```gdscript
@export var shake_noise: FastNoiseLite
var noise_index: float:
    set(v):
        noise_index = v
        offset = Vector2(shake_strength * shake_noise.get_noise_2d(noise_index, 0.0),
                         shake_strength * shake_noise.get_noise_2d(0.0, noise_index))

func shake(strength: float, duration: float) -> void:
    if Config.close_shake: return          # 无障碍开关
    shake_strength = strength
    shake_tween = create_tween(); shake_tween.set_parallel()
    shake_tween.tween_property(self, "noise_index", noise_index + 100 * duration, duration)
    shake_tween.tween_property(self, "shake_strength", 0, duration)
    shake_tween.finished.connect(stop_shake, CONNECT_ONE_SHOT)
```

同时补间"噪声索引"（使轨迹连续）与"强度"（使收敛）。

**B. 创伤值（toziuha，更省事）**：`add_trauma(0.2, true)`——trauma 平方后当强度，自然衰减。`Input.start_joy_vibration(0, 0.1, 0.7, 0.2)` 配手柄震动。

### 6.3 受击闪白（shader）

```glsl
// hurt_flash.gdshader
shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
void fragment() {
    vec4 texture_color = texture(TEXTURE, UV);
    COLOR = mix(texture_color, flash_color, flash_amount * texture_color.a);
}
```

```gdscript
func hurt_flash():   sprite_2d.material.set_shader_parameter("flash_amount",
                        sin(float(Time.get_ticks_msec()) / 40) * 0.5 + 0.5)
func reset_flash():  sprite_2d.material.set_shader_parameter("flash_amount", 0)
# _process: if hurt_timer.is_stopped(): return; hurt_flash()   ← 与无敌帧共用计时器
```

`* texture_color.a` 保证透明像素不变白。

### 6.4 击退与撞墙

- 击退：`velocity = Vector2(-face_direction * KNOCKBACK_H, KNOCKBACK_V)`；玩家与敌人各一套常量（玩家数值更小），敌人可 `@export` 到每个个体。
- 撞墙：攻击时用挂在武器上的 RayCast2D 检测 → 粒子 + 音效 + `hit_recoil()`（反弹玩家），**用布尔标记保证只触发一次**。"打在空气上"与"打在墙上"必须有区别。

### 6.5 攻击动画切换的归位技巧

```gdscript
func animation_play(anim_name: StringName, overwrite_same := false) -> void:
    if animation_player.current_animation == anim_name and not overwrite_same:
        animation_player.play(anim_name); return
    animation_player.play.call_deferred("RESET")      # 先归位
    animation_player.advance.call_deferred(0)
    animation_player.play.call_deferred(anim_name)
    animation_player.advance.call_deferred(0)
```

用 RESET 动画强制归位再播，避免切换动作时残留上一段插值姿态。

## 7. 多段命中去重（鞭击/多段斩必需）

```gdscript
# 敌人受击区里：同名 area + 冷却未过 → 忽略
if area.name in ["AreaLvl1","AreaLvl2","AreaLvl3"] \
   and area.name == last_impacted_area_name \
   and $TimerAvoidDuplicate.get_time_left() != 0: return
last_impacted_area_name = area.name; $TimerAvoidDuplicate.start()
```

- **多段斩/鞭类用"同名去重 + 短冷却"**；**玩家受击用"关 hurtbox 整段免疫"**——两者场景不同，不要混用。
- 持续伤害（旋转斩/毒地/魔法场）：用周期 Timer 对"进入的 area 列表"结算，**退出时 erase、节点失效时 `is_instance_valid` 清理**。

## 8. Boss 战演出编排（房间脚本 = 剧本，单位脚本 = 演员）

房间脚本持有 Boss / NPC / 机关引用，用 `await` 串起整场：

```
玩家进入触发区 → storying = true; InputManager.disabled = true
  → 开场电影效果（遮罩）→ NPC 对话
  → 对话回调 "combat"：Boss 血条显示 → boss.show() → start_battle() → 播 Boss BGM → 解禁输入
  → 对话回调 "defeat"：藏血条 → 开门 → wall.queue_free() → 战后演出
  → boss.defeated 信号：stop_battle() → 播死亡动画 → NPC 顶替位置 → 战后对话
```

- **过场期间 `storying` 布尔让玩家按住确认键 4 倍速跳过**。
- **Boss 不持 UI 引用**：血条更新走 `status_changed` 信号 → `UIManager.status_panel.update_boss_health(...)`。
- 战后恢复：`player.status.health = max_health`、`hurtbox.disabled = false`、`InputManager.disabled = false`。

## 9. 世界层（房间/地图/能力门）

用 `KoBeWi/Metroidvania-System`（1565★ MIT，需 4.6+，[wiki](https://github.com/KoBeWi/Metroidvania-System/wiki)）——**不要自己写**：

```gdscript
MetSys.register_object(node)               # 自动生成唯一 ID（按场景路径）
MetSys.store_object(id, data) / check_object(id)   # 物件持久化（宝箱/开关/破墙/收集品）
MetSys.player_position_changed(pos)        # 每帧报位置 → 自动发现房间 + 场景切换请求
MetSys.get_save_data() / set_save_data(d)  # 存档字典 = 地图数据 + 物件 ID
```

**原型期不要引入**；能力门用 `gd-genre-metroidvania` 的 `metroid_game_state.gd` + `ability_unlock_resource.gd`。

## 10. 落地顺序（已验证的路径）

1. **手感先行**：`gd-characterbody-2d` 的 `expert_physics_2d.gd` + 墙跳 + 冲刺，**不加敌人**，先跑通移动。
2. **战斗最小闭环**：一玩家 + 一敌人 + 一 Boss，跑通"攻击→命中→击退→无敌帧→死亡→掉宝"。
3. **打击感三件套**：顿帧 / 震屏 / 闪白（§6）。
4. **AI 行为树**：先做小怪，再照 §5.1 搭 Boss 树。
5. **世界层**：闭环稳定后再接 MetSys。

**验证方式**：伤害/无敌帧/血量这类纯逻辑写 `smoke_test.gd` 确定性断言（`gd-headless-testing`）；手感/演出用 `godot-mcp-playtest` 冻结步进（`run frozen=true` → `godot_game_time step` + `godot_input sequence` 帧级输入）。

## 参考实现

- 源码：`D:/zcode-work/_repos/bread-adventure/`（4.5，Apache-2.0）——`src/unit/{character,common}/` 是全部模式来源
- 源码：`D:/zcode-work/_repos/toziuha-night-oota/`（3.x，MIT）——多段命中/持续伤害/Boss 多阶段
- 框架：`D:/zcode-work/_repos/Metroidvania-System/`（4.6+，MIT）——世界骨架
- 深读笔记：`D:/zcode-work/godot/docs/20-横版动作实例深读笔记.md`（含"抄写映射"表：要做什么功能 → 抄哪个文件）
- 调研指南：`D:/zcode-work/godot/docs/19-横版动作战斗开发指南.md`
