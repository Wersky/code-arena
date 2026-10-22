---
name: gd-project-scaffold
description: "Standard Godot 4.x project scaffold discipline for this workspace: project.godot input maps, directory layout, the three-piece doc set (handover/pitfall-log/smoke-test), D-drive rules, and the --editor launch pitfall. Use when creating a new Godot project in this workspace, onboarding an existing project, or setting up project conventions. Trigger keywords: project.godot, scaffold, 新项目, 三件套, input map, gl_compatibility, directory layout."
metadata:
  engine-version: "4.7"
  source: "godot 工作区三项目实战"
  license: "MIT"
---

# 新项目脚手架纪律（本工作区标准）

## 建项目步骤

1. 目录：`D:/zcode-work/godot/projects/<小写连字符名>/`
2. `project.godot` 手写最小集（参考 projects/dodge-the-creeps）：
   - `config/name` + `run/main_scene="res://main.tscn"` + `config/features=PackedStringArray("4.7")`
   - 输入映射用 `physical_keycode`（WASD=87/65/83/68、方向键 4194319-4194322、Space=32、Enter=4194309）
   - 渲染 `gl_compatibility`（兼容性最好，桌面 2D/轻 3D 够用）
   - 窗口：2D 竖版 480x720 + `stretch/mode="canvas_items"`；横版 1152x648
3. 目录结构（官方 demo 同款，场景自包含）：`scenes 按系统分目录`、场景与脚本同名成对、跨目录只靠 preload/实例化
4. **三件套**（工作区铁律）：`进度交接.md`（状态/架构/接手流程）+ `踩坑手册.md`（按类别累积、注明实测日期）+ `smoke_test.gd`（headless 冒烟，用 gd-headless-testing 技能）
5. `.gitignore`：`.godot/` 与 `*.uid`

## 导入与验证

```bash
# 新项目先导入资源（生成 .godot 缓存）
D:/zcode-work/godot/engine/Godot_v4.7.2-stable_win64_console.exe --headless --path <项目> --import
# 冒烟
D:/zcode-work/godot/engine/Godot_v4.7.2-stable_win64_console.exe --headless --path <项目> --script smoke_test.gd
```

## autoload 决策树（docs/14 三范式结论）

- 常驻系统（资产库/联机房间/键位绑定）→ 管理器式 autoload，一个职责一个（tabletop-club 式，7 个自解释管理器）
- 跨场景事件 → Events 事件总线 autoload，信号按域分组、begin/end 成对声明（GDQuest space-game 式，仅 2 个 autoload）
- 单局制游戏（RTS/卡牌/肉鸽）→ 双层信号域：全局 Signals 与单局 MatchSignals 分开，换局只清单局层（open-rts 式）
- 纯配置常量 → 只读 autoload（Constants/FeatureFlags）
- 对象查找 → ObjectRegistry 注册表，不用全局 get_node 链

## 实测铁律

1. **开编辑器必须 `--editor`**：console exe 加 `--path` 不带 `-e` 是直接运行游戏（窗口标题带 "(DEBUG)"）——编辑器插件（如 godot_ai）只在 `--editor` 模式加载，漏参数会"插件不启动"且零报错（2026-09-10 实测踩坑，详见 docs/07）。
2. 引擎全局 self-contained（`engine/._sc_`）：编辑器配置/缓存落 `engine/editor_data/`，user:// 落 `engine/userdata_redirect/`（junction），**不要在项目里另配路径**。
3. 手写 `.tscn` 不写 `uid` 字段完全可行，Godot 按路径解析并自动补 `.uid` 伴随文件。
4. 素材优先用官方 demo（MIT/CC0，`D:/zcode-work/_repos/godot-demo-projects/`）或 `D:/zcode-data/game-assets/`（全 CC0），入库时登记许可。

## 参考项目

- projects/dodge-the-creeps（2D Area2D 模式 + mod loader）
- projects/platformer-jump（2D CharacterBody2D + 多关卡）
- projects/3d-roller（3D RigidBody3D + 相机独立跟随）
