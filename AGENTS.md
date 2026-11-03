# AGENTS.md · 代码擂台 Code Arena

> CodeArts Agent（以及任何接手代理）的**常驻规则**。完整现状读 `docs/CodeArts-接手文档.md`。
> 校准：2026-11-02 ｜ 引擎：Godot 4.7.2 ｜ 基线：smoke **224 项 0 失败**

## 项目一句话

Godot 4.7.2 的 2D 肉鸽卡牌。玩家选一位 AI 娘，每回合排 4 张卡的**执行序列**，点发送后按顺序跑完，再自动进敌方回合；靠连段、首尾槽位、白米饭成长打赢 10 关。

**它不是德州扑克。** 扑克牌型 / 筹码 / 倍率 / 花色那一套已经整体退役。旧文档里出现这些词，一律当历史存档，不要照着实现。

## 开工先读

1. `docs/CodeArts-接手文档.md` —— 当前玩法、架构、命令、缺口，唯一现状真值
2. `docs/CodeArts-技能索引.md` —— 154 个 Godot 技能，按任务挑着读；源目录 `.zcode/skills`（随仓库分发）
3. `docs/踩坑手册.md` 最近 10 条 —— 真实踩过的坑

`docs/00-设计方案.md`、`01-新机制设计.md`、`02-前沿方案.md`、`02-梗卡机制设计.md`、`04-基础玩法.md` 是扑克时代存档，只作历史参考。

## 硬规则（违反 = 返工）

1. **绝不启动游戏窗口。** 主人在玩时，任何不带 `--headless` 的 `godot --path .` 都不许跑。验证一律无头。
2. **打包前先查进程**：`tasklist //FI "IMAGENAME eq code-arena.exe"`。有进程就跳过导出并告诉主人，不要杀进程。
3. 改过 `class_name` 或新增脚本 → 先跑 `--import`，否则 headless 测试会“假绿”。
4. 旧机制存档代码与测试（`code_cards.gd`、`meme_cards.gd`、`verify_c4.gd`、`_meme_selftest.gd`）**不要删**，它们必须一直绿。
5. 不把任何 API key / token 写进仓库。生图 key 在 `D:\zcode-work\pictures\gen.py`；Tavily key 在 CodeArts 用户级 `mcp.json`。
6. 只改任务相关文件。提交信息用 `<feat|fix|docs|art|balance|test>: <一句话>`。
7. 分支 `feat/ai-ui-kit`，远程 `origin` 同名分支。未经主人指示不要新建、合并或强推分支。
8. 结果照实说：没跑就写“未执行”，不要编造哈希、偏移、构建或测试结果。

## 环境

- 项目：`D:\zcode-work\godot\projects\prompt-arena`
- 引擎：`D:\zcode-work\godot\engine\Godot_v4.7.2-stable_win64_console.exe`
- 渲染：`gl_compatibility`；窗口 1600×900；纯鼠标
- 主场景：`scenes/main.tscn` → `scripts/main.gd` 路由
- MCP：Tavily（联网检索）+ bilibili（热梗采集）+ godot-flash（无头脚本/场景校验）+ godot-ai（编辑器调试，需开编辑器），配置见 `docs/mcp-setup.md`（key 只在本地，不入库）
- 技能：`.zcode/skills`（154 个，随仓库分发）；CodeArts 自动发现入口 `.github/skills`（junction，跨机器跑 `tools/link_skills.bat`）

## 多 agent 协作

- 常驻规则只有这一份 `AGENTS.md`；状态真值只有 `docs/CodeArts-接手文档.md`。任何 agent（CodeArts / ZCode / Claude Code）先读这两份。
- 技能库 `.zcode/skills` 随仓库分发；CodeArts 走 `.github/skills` 链接自动发现，ZCode 原生读 `.zcode/skills`，其他 agent 可把 `.claude/skills` 链到同一目录。
- MCP 按机器本地配置（key 不入库），步骤见 `docs/mcp-setup.md`。
- 多 agent 同时开发按文件认领（core/data 谁改谁负责、ui 改完目检、`docs/进度交接.md` 每轮收尾更新）；提交前先 `git pull --rebase`。

## 必跑命令

```bash
GODOT="D:/zcode-work/godot/engine/Godot_v4.7.2-stable_win64_console.exe"
cd /d/zcode-work/godot/projects/prompt-arena

"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script res://tests/smoke_test.gd   # 224 项 0 失败
"$GODOT" --headless --path . --script res://tools/sts_sim.gd      # 改数值后必跑
tools/export_win.bat                                              # 导出（先查进程）
```

## 架构速查

- `scripts/core/sts_combat.gd` —— 纯逻辑状态机（无 UI、无 SceneTree）：队列、连段、槽位、米饭三段、复读/并行、观察者、敌我结算。
- `scripts/core/run_state.gd` —— 跨关状态：卡组、HP、道具、门概率 `pick_special`、事件冷却、精英宝箱。
- `scripts/ui/arena.gd` —— 战斗界面与演出（约 1600 行，改前先定位相关函数）。
- `scripts/main.gd` —— 屏幕路由 + F1 体验沙盒。
- `scripts/ui/map_screen.gd` / `event_screen.gd` / `reward.gd` / `bonus_screen.gd` / `burnout_screen.gd` —— 门、事件、奖励、宝箱、燃尽。
- `scripts/data/sts_card_pool.gd`（7 卡）、`sts_item_pool.gd`（4 道具）、`level_pool.gd`（10 关）。

## 验收

- smoke **224 项 0 失败**；数字少了就是假绿，先 `--import`。
- 改数值 → `sts_sim.gd` 重跑：排序收益 ≥15%、总胜率 40~65%、L10 ≥25%。
- 改 UI → 无头截图或请主人目检；不要自己弹窗。
- 每个新功能至少补一条 smoke 断言；修 bug 先补回归再修。
