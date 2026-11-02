# 代码擂台 Code Arena

> Godot 4.7.2 · 2D 肉鸽卡牌 · 纯鼠标操作
> 玩家选一位 AI 娘，每回合排 4 张卡的**执行序列**；靠连段、首尾槽位、白米饭成长，闯 10 关。

**私密仓库，由 ZCode（小萤）与 wb 共同维护。**

---

## 接手前必读（按顺序）

| # | 文档 | 作用 |
|---|---|---|
| 1 | [`AGENTS.md`](AGENTS.md) | 常驻硬规则：不弹窗、无头验证、打包前查进程 |
| 2 | [`docs/CodeArts-接手文档.md`](docs/CodeArts-接手文档.md) | **当前状态唯一真值**：玩法、架构、命令、缺口、MCP/Skills |
| 3 | [`docs/CodeArts-技能索引.md`](docs/CodeArts-技能索引.md) | 154 个 Godot 技能，按任务挑着读 |
| 4 | [`docs/踩坑手册.md`](docs/踩坑手册.md) | 真实踩坑，动手前扫一眼 |
| 5 | [`docs/05-交接与协作.md`](docs/05-交接与协作.md) | 协作/分支/交接纪律（数字部分已旧） |

> `docs/00~04` 是德州扑克时代的设计存档，已作废，不要照着实现。

---

## 快速开始

```bash
GODOT="D:/zcode-work/godot/engine/Godot_v4.7.2-stable_win64_console.exe"

"$GODOT" --headless --path . --import                              # 改过 class_name 后必跑
"$GODOT" --headless --path . --script res://tests/smoke_test.gd     # 224 项当前主流程
"$GODOT" --headless --path . --script res://tests/_meme_selftest.gd # 219 项旧机制存档
"$GODOT" --headless --path . --script res://tests/verify_c4.gd      # 旧机制算例 4 项
"$GODOT" --headless --path . --script res://tools/sts_sim.gd        # 纯战斗平衡模拟
tools/export_win.bat                                               # 导出（先查 code-arena 进程）
```

**不要直接 `--path .` 启动游戏窗口** —— 主人可能在玩；所有验证走 `--headless`。

---

## 一句话状态

**已是一条可玩的纵向切片：10 关、7 张卡、4 件道具、5 则事件、4 类门、三段成长、燃尽画面、F1 体验沙盒。**
主要缺口：L2–L10 敌人立绘、跨局 meta 进度、平衡模拟未覆盖道具/事件。
详见 [`docs/CodeArts-接手文档.md`](docs/CodeArts-接手文档.md) §8。
