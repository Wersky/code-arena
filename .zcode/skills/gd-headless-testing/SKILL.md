---
name: gd-headless-testing
description: "Deterministic headless smoke testing for Godot 4.x projects: SceneTree test scripts with physics_frame-counted assertions, manually-triggered callbacks instead of real-time waits, RigidBody3D teleportation inputs. Use when writing automated tests for Godot games, verifying game logic without opening the editor, or setting up CI-runnable smoke tests. Trigger keywords: smoke_test, headless, SceneTree, physics_frame, deterministic testing, --script, --headless, game testing."
metadata:
  engine-version: "4.7"
  source: "godot 工作区三项目实战（dodge-the-creeps / platformer-jump / 3d-roller）"
  license: "MIT"
---

# Headless 确定性测试方法论

对 Godot 游戏逻辑做 CI 可跑、结果可复现的冒烟测试。**确定性 > 拟真**：不依赖真实时钟、不依赖渲染。

## 标准骨架

```gdscript
# smoke_test.gd —— 放项目根，命令行跑：
# godot_console.exe --headless --path <项目> --script smoke_test.gd
extends SceneTree

var frames := 0
var main

func _initialize():
    main = load("res://main.tscn").instantiate()
    root.add_child(main)
    physics_frame.connect(_tick)   # 断言驱动连物理步，不数渲染帧

func _tick():
    frames += 1
    if frames == 2:
        main.new_game()            # 等首帧入树后再操作节点
    elif frames == 302:
        # 断言区：score / HUD 文本 / 节点组人数 …
        if main.score != 2:
            print("smoke: FAIL"); quit(1); return true
    elif frames == 362:
        print("smoke: PASS"); quit(0); return true
    return false
```

## 五条实测铁律（2026-09-10，三个项目踩坑验证）

1. **`_initialize` 里不能立即调节点方法**——`add_child` 后节点未完成入树，`get_tree()` 为 null（报 `data.tree is null`）。一切操作等 `_process`/`physics_frame` 首帧之后。
2. **headless 帧率与真实时间脱钩**——等 Timer 自然超时不可靠（300 帧跑不满 2 秒 Timer）。**手动调用 Timer 的超时回调**（如 `main._on_score_timer_timeout()`）再做断言。
3. **断言驱动必须连 `physics_frame` 信号按物理步计数**——渲染帧远快于物理步（60Hz），数渲染帧会漏物理事件。
4. **物理输入用瞬移/冲量**：`player.global_position = <目标>` + `linear_velocity = Vector3.ZERO`，下一个物理步 Area3D 检测即触发；移动断言用 `apply_central_impulse` 推 N 物理步后验证位移。
5. **Area3D 出生重叠陷阱**：贴地 Area 的 `body_entered` 会抓到地板 StaticBody（开局即误触发）——测试断言初始 score 前先确认碰撞层隔离（玩家 layer 独立、Area mask 只含玩家层）。

## 参考实现

- `projects/dodge-the-creeps/smoke_test.gd`（2D，手动触发回调流派）
- `projects/platformer-jump/smoke_test.gd`（2D，physics_frame 计数 + 物理位移断言）
- `projects/3d-roller/smoke_test.gd`（3D，瞬移吃收集物 + 掉落重生断言）

## 退出约定

`smoke: PASS`（quit 0）/ `smoke: FAIL - 原因`（quit 1）。quit() 前场景未正常释放会报 ObjectDB 泄漏 warning，属测试脚本常态噪音，不据此判失败。
