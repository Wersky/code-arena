---
name: gd-export-selfcontained
description: "D-drive green export pipeline for Godot 4.7 on this machine: self-contained mode (._sc_), export templates location, headless --export-release commands, and the three-layer junction layout. Use when exporting a Godot game to exe, installing/updating export templates, or troubleshooting 'template not installed' / C-drive pollution. Trigger keywords: export-release, export templates, self-contained, ._sc_, headless export, dist, pck."
metadata:
  engine-version: "4.7"
  source: "godot 工作区导出流水线实战（docs/06）"
  license: "MIT"
---

# D 盘绿色导出流水线

## 三层布局（全部实测，2026-09-10）

| 写入面 | 机制 | 位置 |
|---|---|---|
| 引擎本体 | 绿色 zip | `D:/zcode-work/godot/engine/` |
| 编辑器配置/文档缓存/导出模板 | `._sc_` self-contained（内容 `config_dir="editor_data"`） | `engine/editor_data/`（模板在 `editor_data/export_templates/4.7.2.stable/`，**目录名点号分隔**） |
| 游戏运行期 user://（日志/存档/shader缓存） | junction `%APPDATA%\Godot` → `engine/userdata_redirect/Godot/` | 物理落 D 盘 |

注意：`._sc_` 的 `user_data_dir` 键不存在（Windows 官方禁用 `GODOT_AI_CAPABILITY_DIR` 类覆盖见 docs/07）——user:// 重定向只能靠 junction。

## 导出步骤

1. 模板：官方 release `Godot_v4.7.2-stable_export_templates.tpz`（1.28GB，用 `unzip -t` 验完整性——GitHub 断流常见截断），解压到 `engine/editor_data/export_templates/<版本目录>/`。
2. 项目写 `export_presets.cfg`（Windows Desktop preset），参考 `projects/dodge-the-creeps/export_presets.cfg`。
3. headless 导出：
```bash
D:/zcode-work/godot/engine/Godot_v4.7.2-stable_win64_console.exe --headless --path <项目> --export-release "Windows Desktop" <项目>/dist/游戏名.exe
```
产物 = exe + pck。4.7 headless 不生成 console wrapper，属正常。
4. 验证：启动 dist 下 exe → sleep 几秒 → `tasklist` 确认进程存活 → `taskkill` 收尾。

## 坑位速查（详见 docs/06 与各踩坑手册）

- 模板版本目录名是点号格式 `4.7.2.stable`，不是下划线
- 导出的独立 exe 运行期 user:// 仍写 `%APPDATA%\Godot\app_userdata\<游戏名>`——已由全局 junction 接管，物理落 D 盘
- self-contained 只认 `._sc_` 所在目录，编辑器 exe 与 console exe 均须同目录（本机已满足）
