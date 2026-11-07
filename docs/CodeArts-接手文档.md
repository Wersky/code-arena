# CodeArts 接手文档 · 代码擂台 Code Arena

> 面向：第一次接触本项目的 CodeArts Agent（或任何接手代理）
> 校准时间：2026-11-03
> 项目路径：`D:\zcode-work\godot\projects\prompt-arena`
> 引擎：Godot 4.7.2 stable（`gl_compatibility`）
> 分支：`feat/ai-ui-kit`（远程 `origin` 同名分支）
> 回归基线：`smoke_test.gd` **336 项检查，0 项失败**
>
> **本文档 + 根目录 `AGENTS.md` 是当前状态的唯一真值。**
> `docs/00~04` 是德州扑克时代的设计存档，里面的牌型 / 筹码 / 倍率 / 花色 / 能量都已作废，只作历史参考。

---

## 0. 把这段作为第一条消息发给 CodeArts

```text
你是接手《代码擂台 Code Arena》的工程代理。工作目录：
D:\zcode-work\godot\projects\prompt-arena

开工顺序：
1. 读 AGENTS.md（常驻规则）
2. 读 docs/CodeArts-接手文档.md（完整现状）
3. 需要 Godot 领域知识时，按 docs/CodeArts-技能索引.md 查技能，只读对应的 SKILL.md
4. 跑基线：
   GODOT="D:/zcode-work/godot/engine/Godot_v4.7.2-stable_win64_console.exe"
   cd /d/zcode-work/godot/projects/prompt-arena
   "$GODOT" --headless --path . --import
   "$GODOT" --headless --path . --script res://tests/smoke_test.gd
   期望 336 项检查 0 项失败。

在基线跑绿、文档读完之前，不要改任何代码。
绝对不要启动游戏窗口（主人可能在玩）；所有验证都用 --headless。
打包前先查 code-arena.exe 进程，有进程就跳过导出。
```

---

## 1. 三十秒看懂

**《代码擂台 Code Arena》是一款 Godot 4.7.2 的 2D 肉鸽卡牌游戏。**

玩家选一位 AI 娘（DeepDeek / Kweno / ChatPPT / Grock），她负责执行你排好的「程序」：

1. 每回合手牌 4 张（可被道具加到 5）。
2. 你**只能按从左到右的顺序出牌**，但真正的杠杆是**排列顺序**。
3. 点「发送」= 跑一次程序：整手牌按队列顺序结算，然后自动进敌方回合。
4. 同类卡连续出会叠**连段阶梯**；第一张吃「初始化」加成，最后一张吃「收尾」加成。
5. 白米饭是「注释行」，不参与连段，但会推进 AI 娘的成长：0–1 碗睡觉、2–4 碗翻身、5 碗完全觉醒。
6. 打赢 10 关。每关之间进「门」：40% 战斗、30% 事件、10% 奖励、20% 精英。

世界观包装：

- 玩家 HP = **Token 额度**（1 HP = 1K Token，纯显示层换算）。
- 敌人 HP = **故障强度**。
- 攻击卡 = 加快解决问题；防御卡 = 隔离故障、防止问题扩大。
- HP 归零 = 额度耗尽 → 「燃尽了」跪姿画面。

---

## 2. 当前玩法（可玩版本的真值）

### 2.1 一局流程

```text
启动终端（只播一次）
  → 选 AI 娘
  → 门界面（战斗门常驻 + 特殊门按概率）
      ├─ 战斗门 → 普通战斗 → 胜利谢幕 → 裂隙转场 → 奖励 → 门
      ├─ 事件门 → 5 选 1 事件 → 门（进入冷却）
      ├─ 奖励门 → 宝箱 → 随机道具 → 门
      └─ 精英门 → 强制精英战斗 → 必掉宝箱 → 奖励 → 门
  → 通关 L10 → 结算
  → HP 归零 → 燃尽画面（重试本关 / 回主界面）
```

### 2.2 战斗循环：一回合 = 一次程序运行

- 手牌基础 **4 张**（`REFILL_BY_AI["deepdeek"] = 4`；其他 AI 默认 4）。
- 没有能量费用，只有顺序限制：**只有最左边那张能打**。
- 点「发送」后，`arena.gd` 按队列顺序逐张调用 `StsCombat.play_card()`，播完演出后 `end_send()` 关闭本次序列，再 `end_turn()` 让敌人行动。
- 回合补牌是**全牌堆采样**：弃牌堆全部并回抽牌堆 → 洗混 → 抽 4。不是只从刚打出的牌里补，避免每回合几张牌无限循环。
- 主动弃牌每回合 **3 次**（`DISCARD_LIMIT_PER_TURN`），弃 1 张抽 1 张；「子代理零件」+1 次。

### 2.3 数值公式（`scripts/core/sts_combat.gd`）

常量：

```gdscript
STREAK_STEP = 3
LEAD_BONUS = 2
FINISH_BONUS = 2
RICE_STIR = 2
RICE_AWAKE = 5
RICE_BUFF = 1.2
```

单张卡的结算值：

```text
值 = 基础值
   + 3 × (连段阶数 - 1)
   + 首位加成 2（第一张）
   + 末位加成 2（最后一张）
   + 道具攻击加成（提示词优化器）
然后：若已完全觉醒（≥5 碗），值 = round(值 × 1.2)
```

连段规则：

- 第一张同类卡 = 第 1 阶（+0）。
- 第二张同类 = 第 2 阶（+3）。
- 第三张同类 = 第 3 阶（+6）。
- 换类型 → 断连，回到第 1 阶。
- 复读机让下一张卡执行两次：第二遍**从下一阶起步**（连段算两阶）。

首尾槽位：

- 队列第一张 = 「初始化」+2。
- 队列最后一张 = 「收尾」+2。
- 极端情况只有一张牌时，同时吃 +2/+2。

### 2.4 白米饭与三段成长

米饭是「注释行」：

- 不参与连段，不推进连段阶数。
- 每吃 1 碗 `rice_eaten += 1`；复读机对米饭生效，一次吃 **2 碗**。
- 0–1 碗：睡眠（躺姿）。
- 2–4 碗：翻身（坐起，仍睡）。
- 5 碗：完全觉醒（站立），**所有后续数值 ×1.2（四舍五入）**。
- 觉醒瞬间：把「全核超频」和「并行洪流」各 1 张塞进弃牌堆，随循环进手牌。
- 觉醒是**跨回合持续**的；米饭本身也计入观察者的「发育」统计。

### 2.5 指令卡

| 卡 | 效果 | 细节 |
|---|---|---|
| 复读机 | 下一张非米饭卡执行两次 | 米饭不消费它；一次吃 2 碗；序列收尾时未消费就作废 |
| 并行 | 本次序列换类型不断连 | 只保本序列，`end_send()` 解锁；不是永久 buff |

### 2.6 敌人观察者

`end_turn()` 时看**整个序列**：

- 本序列攻击卡 ≥2 张 → 敌人下回合改为**防御**（`enemy_def + OBS_BRACE`，当前 `OBS_BRACE=0`）。
- 本序列发育卡（米饭 + 防御）≥2 张 → 敌人下回合改为**攻击 +3**（`enemy_atk + OBS_CHARGE`）。
- 两个条件都满足时，防御优先（先判断攻击数）。
- 统计每回合清零；复读执行两次算两张。

设计意图：不能无脑全攻，也不能只顾发育；敌人会针对你的程序结构。

### 2.7 卡池（9 张）

| id | 卡名 | 类型 | 基础值 | 描述 |
|---|---|---|---|---|
| `fish_ram` | 急速收敛 | 攻击 | 6 | 冲击问题，解决进度 +6。 |
| `taunt` | 熔断保护 | 技能/防御 | 5 | 隔离故障，护盾 +5。 |
| `rice` | 白米饭 | 成长 | — | 神奇的白米饭。 |
| `loop` | 复读机 | 指令 | — | 下一张卡执行两次。 |
| `parallel` | 并行 | 指令 | — | 本次运行换类型不断连段。 |
| `cannon` | 全核超频 | 攻击 | 12 | 冲击问题 +12，**无视故障隔离（格挡）**。 |
| `rage` | 并行洪流 | 攻击 | 5 | 冲击问题 +5，**执行两次**。 |
| `cp_format` | 格式化输出 | 攻击 | 6 | ChatPPT 专属：按模板输出，解决进度 +6。 |
| `cp_template` | 模板套用 | 技能/防御 | 5 | ChatPPT 专属：套用模板，护盾 +5。 |

起始卡组 10 张：3 攻 + 2 防 + 3 白米饭 + 1 复读机 + 1 并行。
- 通用：3 急速收敛 + 2 熔断保护。
- ChatPPT：3 格式化输出 + 2 模板套用。

`cannon` / `rage` 只能靠觉醒赠卡获得。

**ChatPPT 被动「模板对齐」**：每回合第一张非指令行卡（攻/防）额外 +2；米饭/复读/并行不消耗该次数，换回合重置。`preview_sequence()` 同步计算，预览不撒谎。

### 2.8 道具（4 件）

| id | 名称 | 效果 |
|---|---|---|
| `prompt_opt` | 提示词优化器 | 所有攻击牌伤害 +2（本局永久） |
| `subagent` | 子代理零件 | 每回合弃牌次数 +1（3 → 4） |
| `compress` | 上下文压缩 | 手牌上限 +1；耐久 3 场战斗，用完本局损坏，下一局自动修好 |
| `muyu` | 电子木鱼 | 每场战斗开始时先回 5 HP，再开战 |

获取渠道：奖励界面第 4 槽随机道具、精英宝箱、事件「显卡炼丹炉」。

### 2.9 门、事件、奖励、精英

**门概率**（`RunState.pick_special`）：

```text
roll < 0.20        → 精英门（20%）
roll < 0.50        → 事件门（30%）
roll < 0.60        → 奖励门（10%）
否则               → 纯战斗（40%）
```

- 战斗门**永远存在且可点**；特殊门只在掷到时出现。
- 点任意一扇门后，两扇门同时锁定（`chosen_guard`），一访一选。
- 事件冷却：事件门默认可用；进过 1 次后 `events_since_battle` 变 1，事件门灰掉；打完下一场战斗（`_on_level_cleared`）重置为 0，重新开放。
- 精英门 = 强制精英战斗。**精英不额外加数值**，只是同一关卡的强制战斗；胜利必掉一个随机道具宝箱，视觉上有红光脉动 + 脚下宝箱角标。

**5 则事件**（`scripts/ui/event_screen.gd`）：

| id | 标题 | 选项 A | 选项 B |
|---|---|---|---|
| `fire` | 服务器着火了 | 灭火器：+15 HP | 泼水：下一战敌人 -20 HP，自己 -5 HP |
| `interview` | 街头采访：AI 会取代人类吗 | 「会」：本局攻击 +1 | 「不会」：+18 HP |
| `temperature` | 温度旋钮：0 还是 2 | 0：下一战手牌 +1 | 2：随机一张牌入库（急速收敛/熔断保护/白米饭） |
| `alchemy` | 显卡炼丹炉 | 随机道具 | 电子木鱼 |
| `feud` | 百万大 V 求对线 | 应战：下一战敌人 -15 HP | 拉黑：+12 HP |

**奖励界面**（`reward.gd`）固定 4 选 1：

1. 急速收敛
2. 熔断保护
3. 系统重启：+14K Token
4. 随机道具

**伤害/回复**：战斗胜利后 `HEAL_ON_WIN = 6`（在战斗内 HP 基础上回 6，封顶 80）。

### 2.10 Token 世界观与燃尽

- 玩家 HP 80 → 显示「Token 额度 80K/80K」。
- 敌人 HP 显示「故障强度」。
- 攻击/防御时女仆做**中转演出**：指令球从对话框飞向 AI 娘 → 她「运作中…」脉冲 → 效果落地。
- HP 归零 → `BurnoutScreen`：全屏黑 + 跪姿失落立绘 + 「燃尽了」烧焦大字 + 余烬粒子 + 下坠音效 → 「重整旗鼓·重试本关」/「回到主界面」。

### 2.11 胜利链与体验沙盒

胜利链：侧栏左滑 + 对话框下滑 → 全屏黑 → 中央锯齿裂隙向上下张开 → 奖励 → 门。

**F1 体验沙盒**（`scripts/ui/sandbox_panel.gd` + `main.gd`）：

- 形态：翻身 2 碗 / 完全觉醒 5 碗 / 睡回去。
- 战斗：秒杀敌人走完整胜利链 / 精英战 / 满血。
- 遭遇：事件①–⑤直达。
- 门界面强制：下一门 = 事件 / 奖励 / 精英 / 恢复随机（**一次性**，用后即恢复随机）。
- 道具：三件套一键领取。
- 演出：斩击 / 盾框 / 爪击演示；燃尽画面直达。

沙盒面板在 group `"sandbox"` 里，`debug_screen_count()` 会排除它，不影响界面数断言。

### 2.12 平衡基线（记录值，改数值后必须重跑）

`tools/sts_sim.gd` 是独立复刻的蒙特卡洛模拟器（不加载运行时 `StsCombat`），只模拟**战斗**：

- L1–L10 × 200 局。
- 乱序 bot vs 择优 bot。
- 验收：排序收益 ≥15%、总胜率 40–65%、L10 择优 ≥25%。
- 最近记录：排序收益约 77.5%、总胜率约 70%、L10 约 46%。

注意：

- 这个模拟器**不模拟道具、事件、门概率**，所以它是“纯战斗基线”，不是整局胜率。
- 模拟器头部注释里的“手牌 3 张”是旧注释；真实常量是 `HAND_REFILL = 4`，以常量为准。
- 改任何卡牌数值 / 米饭阈值 / 连段规则，必须同步改模拟器里的快照常量，再重跑。
- **AGGRO 1.6 万场矩阵（2026-11-03）**：见 `docs/balance-aggro.md`。3/4 PASS——总胜率 61.2%、L10 34.0%、AGGRO 槽降 90.8%；**MARK 胜率差 −3.3pp 未达 +5pp（FAIL）**。建议 AGGRO 槽权重 0.5→**0.7~0.8**（或 ECONOMY 模式分 `grw*3`→`grw*2`）后复测，并平滑 L7→L8 攻击底线断崖。

### 2.13 LLM 接入（2026-11-03 落地，可整体关闭）

**开关**：主菜单「AI 接入」按钮或快捷键 **F2** 打开设置面板；配置存 `user://llm_config.cfg`，总开关关闭后所有请求短路，游戏与旧版零差异。API Key 只做 XOR+base64 轻混淆（防围观不防解包）。

**模块**（接口全文 `docs/llm-integration.md`）：

| 文件 | 类 | 职责 |
|---|---|---|
| `scripts/llm/llm_config.gd` | `LLMConfig` | 配置读写、Key 混淆、温度分治（observer 0.3 / event 0.5 / dialog 0.8） |
| `scripts/llm/llm_client.gd` | `LLMClient`(Node) | 唯一网络出口：并发≤2、重试≤1（仅 5xx/超时）、401/402/429 熔断、3s 预算、迟到缓存、MockBackend |
| `scripts/llm/llm_protocol.gd` | `LLMProtocol` | openai/deepseek/gemini/anthropic 的 URL/Header/Body 与 `/models` 解析 |
| `scripts/llm/llm_parse.gd` | `LLMParse` | 动作四层容错、事件 JSON 三关、台词清洗 |
| `scripts/data/llm_opponent_pool.gd` | `LLMOpponentPool` | 五动作白名单/合法性/本地兜底 |
| `scripts/core/llm_event_engine.gd` + `scripts/data/llm_event_slots.gd` | `LLMEventEngine`/`LLMEventSlots` | 8 机械槽位、本地预筛 2~3 候选、预算（每局≤2、净值 [−8,+6]、单局 ≥−10、L1-2 无负面） |
| `scripts/data/llm_prompts.gd` | `LLMPrompts` | 观察者 v2 / 事件 v2 / 小鲸 v1.1 三份 prompt |
| `scripts/ui/ai_banter.gd` | `AIBanter` | AI 娘 4 钩子气泡（开场/连段/濒危/回怼），3s 超时落本地台词，不 await |

**行为边界**：AI 对手只进**普通战斗**；精英/Boss 锁规则版。LLM 只出「白名单动作词」或「槽位编号 + ≤20 字理由」，数值全部本地表/本地掷。事件流回退：未接 AI、预算耗尽、候选池为空或解析失败 → 原 5 则热梗事件。AI 娘钩子：开场 1 次/场、连段 ≥3 阶 2 次/场（隔 ≥2 回合）、HP 首次 <30% 1 次/场、回怼敌 MARK/TAUNT 2 次/场。

---

## 3. 代码架构

### 3.1 路由（`scripts/main.gd`）

```text
_show_menu → _show_launch（终端进场）→ 选人 → _show_level
  → arena（战斗）
  → level_cleared → _show_reward → _after_reward → _show_map
  → _show_map（门）→ battle / event / bonus / elite
  → L10 通关 → _show_result(true)
  → 战斗失败 → _show_result(false) → BurnoutScreen
```

关键信号：

- `arena.level_cleared` / `level_failed` / `advance_requested`
- `map_screen.battle_entered` / `event_entered` / `bonus_entered` / `elite_entered`
- `event_screen.finished`
- `reward.finished`
- `bonus_screen.finished`
- `burnout_screen.retry_requested` / `menu_requested`

### 3.2 核心逻辑

**`scripts/core/sts_combat.gd`** —— 纯逻辑状态机，`RefCounted`，不依赖 SceneTree：

- `setup(deck, enemy_name, enemy_hp, pattern, start_hp, seed, hand_refill)`
- `play_card(card, auto_refill, is_lead, is_finish)`
- `end_send()`：关闭本次程序运行，清连段/并行锁/复读缓冲
- `end_turn()`：敌人行动 → 换意图 → 新回合
- `preview_sequence()`：影子执行，给 UI 算「这张会打多少」，不改真实状态
- `refill_from_deck()`：全牌堆采样补牌
- `is_stir()` / `is_awake()` / `_grant_awake_cards()`

**`scripts/core/run_state.gd`** —— 跨关状态：

- `deck` / `items` / `hp` / `compute` / `level_index` / `run_seed`
- `start_battle(level, elite)`：注入道具、事件预扣血、手牌加成、精英标记
- `win_battle()` / `lose_battle()`
- `pick_special(roll, force)`：门概率（静态，可测试）
- `grant_elite_chest()`：随机道具
- `events_since_battle`：事件门冷却

### 3.3 UI 层

| 文件 | 职责 |
|---|---|
| `scripts/ui/arena.gd` | 战斗界面、队列、卡牌、HUD、全部战斗演出（约 1600 行） |
| `scripts/ui/ai_companion.gd` | 右侧 AI 娘：睡眠/翻身/站立/吃饭四态、呼吸、脉冲 |
| `scripts/ui/sts_card_view.gd` | 单张卡面：边框、名字条、立绘、描述、首尾槽位框 |
| `scripts/ui/map_screen.gd` | 双门界面：战斗/事件/奖励/精英，悬停发光、一选锁双门 |
| `scripts/ui/event_screen.gd` | 5 则事件 + 选项效果结算 |
| `scripts/ui/reward.gd` | 4 选 1 奖励 |
| `scripts/ui/bonus_screen.gd` | 宝箱关：开箱得随机道具 |
| `scripts/ui/burnout_screen.gd` | 燃尽画面 |
| `scripts/ui/rift_transition.gd` / `rift_half.gd` | 裂隙转场 |
| `scripts/ui/sandbox_panel.gd` | F1 体验沙盒 |
| `scripts/ui/main_menu.gd` / `launch_screen.gd` / `ai_select.gd` | 主菜单 / 终端进场 / 选人 |
| `scripts/ui/ui_kit.gd` / `pixel_theme.gd` / `art.gd` | 统一 UI 工厂、像素主题、贴图加载 |

### 3.4 数据层

| 文件 | 内容 |
|---|---|
| `scripts/data/sts_card_pool.gd` | 7 张卡 + 起始卡组 10 张 |
| `scripts/data/sts_item_pool.gd` | 4 件道具 |
| `scripts/data/level_pool.gd` | 10 关：名称、敌人、HP/攻/防、章节、Boss 标记 |
| `scripts/data/ai_pool.gd` | 4 位 AI 娘（DeepDeek/Kweno/ChatPPT/Grock） |
| `scripts/data/ai_item_data.gd` | 道具运行时数据：art_path、charges、broken |
| `scripts/data/intro_script.gd` | 终端进场台词 |

### 3.5 资产

- 目录：`assets/art/`（PNG）、`assets/audio/sfx/`（WAV）、`assets/audio/music/`（BGM）。
- 角色立绘：`ai-deepdeek-sleep.png`（睡）、`ai-deepdeek-awake.png`（翻身坐起）、`ai-deepdeek-awake-stand.png`（觉醒站立）、`deepseek-kneel.png`（燃尽跪姿）。
- 敌人立绘：目前只有 `enemy-L1.png`；L2–L10 没有立绘，`arena._start_battle()` 会回退到程序化形状 + 关卡色调。
- 卡面立绘：`sts-art-fish_ram.png` / `sts-art-taunt.png` / `sts-art-rice.png` / `sts-art-loop.png` / `sts-art-parallel.png` / `sts-art-cannon.png` / `sts-art-rage.png`。
- 门：`door-battle.png` / `door-event.png` / `door-elite.png`；宝箱 `chest.png`。
- 事件：`event-0.png` ~ `event-4.png`。
- 特效：`fx-slash.png` / `fx-shield.png` / `fx-claw.png`。
- 道具：`item-prompt-opt.png` / `item-subagent.png` / `item-compress.png` / `item-muyu.png`。
- 牌堆图标：`icon-pile-draw.png` / `icon-pile-discard.png`。
- 燃尽标题：`title-burnout.png`。

### 3.6 旧机制存档（不要删）

这些是历史实现，已退出主流程，但代码和回归测试必须保留：

- `scripts/data/card_data.gd` / `card_pool.gd` / `meme_cards.gd`
- `scripts/core/scoring.gd` / `ai_taste.gd`

`smoke_test.gd` 只跑当前主流程；旧机制已无独立测试文件（历史上的 `tests/_meme_selftest.gd`（旧记 219 项）与 `tests/verify_c4.gd`（旧记 4 项）**不在本仓库**，不要再写这些命令或数字）。

### 3.7 设计约束

- 战斗逻辑与 UI **严格分离**：`StsCombat` 不 import 任何 UI，所有表现通过返回的事件字典驱动。
- 界面几乎全部代码构建，`scenes/` 只有 `main.tscn`；不要新增大量手写 `.tscn`。
- 卡面文字/边框/槽位由引擎渲染，生图只出**角色本体**。
- 单帧立绘 + 引擎 Tween 做动效；不要序列帧图集。

---

## 4. 开发环境与命令

### 4.1 路径

```bash
PROJ="D:/zcode-work/godot/projects/prompt-arena"
GODOT="D:/zcode-work/godot/engine/Godot_v4.7.2-stable_win64_console.exe"
```

### 4.2 常用命令

```bash
cd /d/zcode-work/godot/projects/prompt-arena

# 刷新 class_name / 资产导入缓存（改过 class_name 或新增脚本后必跑）
"$GODOT" --headless --path . --import

# 当前主流程回归（期望 336 项，0 失败）
"$GODOT" --headless --path . --script res://tests/smoke_test.gd

# 战斗平衡模拟（改数值后必跑；输出 stdout + .godot/sim_report*.txt）
"$GODOT" --headless --path . --script res://tools/sts_sim.gd

# 导出 Windows（先查进程！）
tools/export_win.bat
# 产物：D:/zcode-work/godot/dist/code-arena/code-arena.exe
```

### 4.3 硬约束

1. **不要启动游戏窗口**。主人在玩时，任何不带 `--headless` 的 `godot --path .` 都不许跑；截图/目检也不行。
2. **打包前查进程**：
   ```bash
   tasklist //FI "IMAGENAME eq code-arena.exe"
   ```
   有进程就跳过导出并汇报，不要 kill。
3. 改过 `class_name` / 新增脚本 → 先 `--import`，否则测试可能静默跳过断言，出现“假绿”。
4. 批量脚本改 `.gd` 时：任何一批 assert 失败都要**整批重放**，不要留下半批改动；改完必须 `--check-only` + smoke。
5. 不要提交 `dist/`、`.godot/`、`.tmp/`、密钥。
6. 提交前确认 `git status` 只包含本次相关文件。

---

## 5. 美术与音效管线

### 5.1 角色形象的唯一真相

DeepSeek 娘（DeepDeek）的形象基准：

```text
D:\zcode-work\companion\gallery\蓝白鲸纹女仆像素角色设定图.png
```

任何新造型 / 重绘 / 动作，都必须以这张图为**身份参考**走图生图（`/v1/images/edits`），保：

- 深蓝渐变长卷发 + 大卷呆毛
- 白色荷叶边女仆头饰 + 蓝色侧边缎带
- 深蓝女仆裙 + 白色围裙 + 小蓝鲸印花
- 金色胸针

**禁止**按文字设定图脑补，也**禁止**程序化自绘人物当主形象。

### 5.2 生图脚本

```bash
python D:/zcode-work/pictures/gen.py --name <主题> \
  --subject "..." --action "..." --composition "..." \
  --environment "..." --lighting "..." --materials "..."
```

- 母模板：`D:\zcode-work\pictures\gen-templates\master-gpt-image-2.5.txt`
- 风格库：`D:\zcode-work\pictures\gen-styles\`（默认 `aigc.txt`）
- 模型：`gpt-image-2.5-1k` / `2k` / `4k`；复杂长提示词优先 **2k**（1k 通道在长 prompt 下容易撞 145 秒网关超时）
- 参考图：`--ref <png>` 走图生图
- 产物：`D:\zcode-work\pictures\output\日期-主题.png`
- API key 在 `gen.py` 内部；**不要把 key 复制进仓库或文档**

### 5.3 透明背景

两条路：

1. 请求里带 `background=transparent`（gpt-image-2.5-2k 实测可用）。
2. 品红背景 `#FF00FF` 生成后用 PIL chroma-key 抠图（像素画最稳）。

抠完裁 bbox，存 `assets/art/`，原图归档到 `D:\zcode-work\pictures\output\`。

### 5.4 卡面

- 生图只出**角色本体**，不要生成卡框/文字/角标。
- 卡名、描述、类型、首尾槽位框全部由 `sts_card_view.gd` 渲染。
- 高密度像素立绘用 `TEXTURE_FILTER_LINEAR`；低分辨率块状像素才用 `NEAREST`。

### 5.5 音效

```bash
python tools/make_sfx.py
```

合成 8-bit 音效到 `assets/audio/sfx/*.wav`；`SfxNode.play("<name>")` 按文件名加载。
战斗音效：`fx_slash` / `fx_block` / `fx_eat` / `fx_ehit` / `fx_edef` / `fx_burnout`。

---

## 6. MCP 配置（Tavily）

### 6.1 CodeArts 的 MCP 机制

CodeArts Agent 26.10.2 是 VS Code 内核，原生支持 MCP：

- 用户级配置：`%APPDATA%\codearts-agent\User\mcp.json`
- 工作区级配置：`<项目>\.vscode\mcp.json`
- 配置结构是 `{"servers": {...}}`（不是 Claude 的 `mcpServers`）
- 每个 server 支持 `type: "stdio"` + `command`/`args`/`env`，或 `type: "http"` + `url`
- 访问权限默认 `chat.mcp.access = "all"`；如果 MCP 工具不出现，在设置里确认这一项

### 6.2 已经配置好的 Tavily（本机）

文件：`C:\Users\33477\AppData\Roaming\codearts-agent\User\mcp.json`

```json
{
  "servers": {
    "tavily": {
      "type": "stdio",
      "command": "D:\\nodejs\\npx.cmd",
      "args": ["-y", "tavily-mcp"],
      "env": {
        "TAVILY_API_KEY": "<你的 Tavily Key>",
        "NO_PROXY": "*",
        "no_proxy": "*"
      }
    }
  }
}
```

本机已填入真实 key，并做过 `initialize` 握手验证：返回 `tavily-mcp 0.2.22`。
Node 版本：`v24.19.0`（Tavily MCP 要求 Node ≥20）。

### 6.3 验证是否生效

1. 完全退出 CodeArts Agent，再打开（MCP 配置只在启动时读）。
2. 打开项目 `D:\zcode-work\godot\projects\prompt-arena`。
3. 切到 **Agent / 智能体模式**（普通聊天模式可能不加载工具）。
4. 问一句：

   ```text
   用 tavily_search 搜一下 Godot 4.7 的 @export 注解最新语法，给出来源链接。
   ```

5. 能看到工具调用并返回带 URL 的结果 = 成功。
6. 也可以在 MCP 服务器面板里看 `tavily` 是否 running。

Tavily 提供的工具：

| 工具 | 用途 |
|---|---|
| `tavily_search` | 搜索网页 |
| `tavily_extract` | 从 URL 提取正文 |
| `tavily_crawl` | 抓取站点多页 |
| `tavily_map` | 发现站点结构 |
| `tavily_research` | 多来源研究并给详细答案 |

### 6.4 常见故障

| 现象 | 处理 |
|---|---|
| 工具列表里没有 tavily | 确认 `chat.mcp.access` 是 `all`；重启 CodeArts；确认是 Agent 模式 |
| 启动时报 `npx` 找不到 | 把 `command` 改成绝对路径 `D:\\nodejs\\npx.cmd`（已这样做） |
| 报 Node 版本低 | 升级 Node 到 ≥20；本机是 24.19.0 |
| 报 401 / API key 无效 | 去 https://app.tavily.com 重新生成 key，替换 `TAVILY_API_KEY` |
| 公司网络/代理拦截 | 保留 `NO_PROXY=*`；或改用远程 HTTP 模式 |
| 启动很慢 | 第一次 `npx -y tavily-mcp` 要下载包；之后走缓存 |

### 6.5 远程 HTTP 备选

不想走本地 Node 时，把 server 换成：

```json
{
  "servers": {
    "tavily": {
      "type": "http",
      "url": "https://mcp.tavily.com/mcp/?tavilyApiKey=<你的 Tavily Key>"
    }
  }
}
```

远程模式也支持 OAuth；用 OAuth 时 URL 里不需要 key。

### 6.6 怎么申请自己的 Tavily Key（教主人）

1. 打开 https://app.tavily.com
2. 用邮箱 / GitHub 注册或登录
3. 进 **API Keys** 页面
4. 复制 `tvly-` 开头的 key
5. 填到 `%APPDATA%\codearts-agent\User\mcp.json` 的 `TAVILY_API_KEY`
6. 重启 CodeArts Agent

免费额度足够个人开发用；额度/计费以 Tavily 官网为准。

### 6.7 其他可选 MCP

本机 ZCode 还配置了 `drawio`、`context-mode`、`swarmlink`、`platformio`、`stm32-hil` 等，但它们的启动命令依赖 ZCode 的私有路径，**不要直接复制到 CodeArts**。CodeArts 当前只需要 Tavily 做联网检索；需要画图时可直接让 CodeArts 生成 draw.io XML 或用代码画。

---

## 7. Skills（154 个 Godot 技能）

### 7.1 位置与用法

```text
D:\zcode-work\godot\.zcode\skills\<技能名>\SKILL.md
```

- 共 **154** 个，全部是 Godot 4.x 领域技能（每个 1–5 KB）。
- 索引：`docs/CodeArts-技能索引.md`（含“按任务选技能”表和全量描述）。
- 用法：**按任务查索引 → 只读命中的那个 `SKILL.md`**；不要一次全读。
- 技能里的代码/命令是参考实现，落地前在 Godot 4.7.2 上验证。

### 7.2 CodeArts 的原生技能发现

CodeArts 支持从这些目录自动发现 `SKILL.md`：

```text
.github/skills
.agents/skills
.claude/skills
~/.copilot/skills
~/.agents/skills
~/.claude/skills
```

本仓库已建好 `.github/skills` → `.zcode/skills` 的**目录链接（junction）**，CodeArts 打开项目即可自动发现全部 154 个技能，无需复制、不会漂移。

- `.github/skills/` 已加入 `.gitignore`（不重复存储 20MB 技能库）。
- 换机器 clone 后，跑一次 `tools/link_skills.bat` 重建链接（管理员权限）。
- ZCode 原生读 `.zcode/skills`；Claude Code 等可把 `.claude/skills` 链到同一目录。
- 按索引按需读取同样有效：`docs/CodeArts-技能索引.md`。

### 7.3 先读这 12 个

| 技能 | 什么时候读 |
|---|---|
| `gd-headless-testing` | 写 / 改 smoke 测试、CI 验证 |
| `gd-export-selfcontained` | 打包 Windows exe、资源过滤 |
| `gd-monte-carlo-balancer` | 调关卡数值、跑模拟、分位数 |
| `gd-genre-roguelike` | 加节点、奖励、风险收益、重开循环 |
| `gd-godot-ui` | 改布局、容器、分辨率适配 |
| `gd-tween-animation` | 加滑入滑出、抖动、脉冲 |
| `gd-asset-gen` | 生图、抠图、切件、导入设置 |
| `gd-assets-pipeline` | 资产命名、目录、版本管理 |
| `gd-agent-vision` | 无头截图 + 视觉验收 |
| `gd-godot-debugging` | 崩溃、性能、信号问题 |
| `gd-gdscript-mastery` | 类型、生命周期、GDScript 陷阱 |
| `gd-save-load` | 跨局存档、版本迁移 |

---

## 8. 当前缺口与建议下一步

> 按优先级排。每项都写清“从哪开始 / 怎么验收”，接了就能干。

### P0 · 先保证基线

1. **文档真值已建立**：`AGENTS.md` + 本文档 + 技能索引。
2. **已修两个真实 bug**（2026-11-02）：
   - 沙盒「强制下一门」被随机 roll 覆盖 → 抽出 `RunState.pick_special(roll, force)`，force 优先，且用后消费。
   - 电子木鱼回血在 `cb.setup()` 之后才结算，战斗对象拿旧 HP → 改为先回血再开战。
   - 两条都补了回归，smoke 从 217 → **224**。

### P1 · 内容完整度

2. **L2–L10 敌人立绘缺失**：目前只有 `enemy-L1.png`，其余回退程序化形状。
   - 入口：`scripts/ui/arena.gd::_start_battle()` 的 `enemy-%s.png` 约定。
   - 做法：按 `level_pool.gd` 的 10 个敌人各出一张立绘，命名 `enemy-L2.png` … `enemy-L10.png`，透明底。
   - 验收：每关进场能看到对应立绘；smoke 可加“资产存在”断言。
3. **卡池 9 张（7 通用 + ChatPPT 专属 2）**：仍可扩展稀有卡/状态卡/敌人施加的负面卡。
   - 入口：`scripts/data/sts_card_pool.gd`；新卡要同步 `preview_sequence()`、模拟器常量与卡面资产。
   - ChatPPT 已接入专属 `cp_format` / `cp_template` 与被动「模板对齐」（每回合首张数值牌 +2）。
4. **事件只有 5 则、道具只有 4 件**：可继续加，但注意 `EventScreen.EVENTS` 是常量数组，索引按 `event_index % size` 取。
5. **其他 3 位 AI 娘没有三段形态**：`ai_companion.gd` 的睡眠/翻身/站立只对 `deepdeek` 生效，其他 AI 是单张立绘模式。要么补资产，要么在选人界面明确“当前只支持 DeepDeek 三段”。

### P1 · 平衡

6. **模拟器不覆盖道具/事件/门**：当前 70% 总胜率是纯战斗基线，不是整局胜率。
   - 若要评估整局，需要在模拟器里加入：道具增益、事件预扣血/加手牌、门概率带来的战斗次数期望。
   - 入口：`tools/sts_sim.gd`（独立复刻，改机制时两边都要改）。
7. **L10 择优胜率约 46%**：作为 Boss 可以接受，但若主人觉得太难，优先调 `level_pool.gd` 的 L10 HP/攻/防，不要动全局连段公式。

### P2 · 体验与系统

8. **AI 解锁**：已按主人 2026-11-03 要求改为**全部初始可选**（`AiPool.UNLOCK_AT` 全 0，`LaunchScreen.MODELS` 门槛全 0，选人界面不再出现剪影锁）。
   - 跨局持久化仍未做，但已不影响选人；将来若要恢复"通关解锁"，只改 `UNLOCK_AT` 与 `LaunchScreen.MODELS` 第三项即可。
9. **音频**：已有 BGM 文件和战斗音效，但没有统一的音量设置/静音 UI；`--mute` 只是启动参数。
10. **UI 打磨**：卡面/门/奖励的悬停、按下、禁用态可以继续统一；改前读 `gd-godot-ui` 与 `gd-tween-animation`。
11. **旧文档清理**：`docs/00~04` 是扑克时代存档，建议移到 `docs/archive/` 并在 README 标注；不要直接删，主人可能还要查历史。

### P3 · 工程卫生

12. `docs/进度交接.md` 头部还写着 2026-10-23，§0–2.8 是旧玩法；只有 §2.9–2.23 仍有效。建议下一轮做一次“旧章节归档 + 新章节接续”。
13. `README.md` 的一句话状态还是扑克时代，已在本轮更新为当前状态。
14. `project.godot` 的 `config/description` 旧文案已在本轮更新。

---

## 9. 验收清单（Definition of Done）

一次改动完成前，逐条确认：

- [ ] 读了 `AGENTS.md` 和本文档相关章节
- [ ] 改动前基线绿：smoke 336 项 0 失败
- [ ] 改动只涉及任务相关文件
- [ ] 新增/修改的逻辑有 smoke 断言；修 bug 先补回归
- [ ] 改过 `class_name` / 新增脚本 → 跑过 `--import`
- [ ] 改数值 → `sts_sim.gd` 重跑并记录结果
- [ ] 改 UI → 无头截图或请主人目检（没有弹窗）
- [ ] 没有把密钥写进仓库
- [ ] 提交信息符合 `<type>: <一句话>`
- [ ] 更新了 `docs/进度交接.md` 或本文档的“当前状态/缺口”
- [ ] 没有启动游戏窗口、没有杀主人的游戏进程

---

## 10. 文档可信度地图

| 文档 | 状态 | 怎么用 |
|---|---|---|
| `AGENTS.md` | ✅ 当前 | 常驻规则，先读 |
| `docs/CodeArts-接手文档.md` | ✅ 当前 | 本文档，完整现状 |
| `docs/CodeArts-技能索引.md` | ✅ 当前 | 154 个技能索引 |
| `docs/进度交接.md` | ⚠️ 部分 | §2.9–2.23 是当前；§0–2.8 是扑克时代；头部日期旧 |
| `docs/踩坑手册.md` | ⚠️ 部分 | 49 条真实教训仍有效；涉及旧机制的条目只作参考 |
| `docs/05-交接与协作.md` | ⚠️ 部分 | 分支/提交/交接纪律仍有效；回归数字是旧的 |
| `docs/00-设计方案.md` | ❌ 存档 | 扑克时代，不要照着实现 |
| `docs/01-新机制设计.md` | ❌ 存档 | 同上 |
| `docs/02-前沿方案.md` | ❌ 存档 | 同上 |
| `docs/02-梗卡机制设计.md` | ❌ 存档 | 同上 |
| `docs/04-基础玩法.md` | ❌ 存档 | 扑克牌型/计分，已作废 |
| `docs/06-角色动画方案.md` | ⚠️ 部分 | ChibiRig 方案，部分已被单帧立绘 + Tween 取代 |
| `README.md` | ✅ 本轮更新 | 项目入口与快速开始 |

---

## 附录 A · 关键常量速查

```gdscript
# StsCombat
HEAL_ON_WIN = 6
REFILL_BY_AI = {"deepdeek": 4}
RICE_STIR = 2
RICE_AWAKE = 5
RICE_BUFF = 1.2
STREAK_STEP = 3
LEAD_BONUS = 2
FINISH_BONUS = 2
OBS_BRACE = 0
OBS_CHARGE = 3

# RunState
MAX_HP = 80

# Arena
DISCARD_LIMIT_PER_TURN = 3

# Reward
HEAL = 14
```

门概率：

```text
< 0.20 精英
< 0.50 事件
< 0.60 奖励
else   战斗
```

---

## 附录 B · 关键函数入口

| 要改什么 | 去哪 |
|---|---|
| 卡牌数值/描述 | `scripts/data/sts_card_pool.gd` |
| 连段/槽位/米饭/观察者 | `scripts/core/sts_combat.gd` |
| 起始卡组 | `sts_card_pool.gd::starter_deck()` |
| 关卡数值/敌人名 | `scripts/data/level_pool.gd` |
| 道具效果 | `scripts/data/sts_item_pool.gd` + `run_state.start_battle()` |
| 门概率 | `RunState.pick_special()` |
| 门界面 | `scripts/ui/map_screen.gd` |
| 事件内容/效果 | `scripts/ui/event_screen.gd` |
| 奖励选项 | `scripts/ui/reward.gd` |
| 战斗演出 | `scripts/ui/arena.gd`（`_spawn_fx` / `_enemy_hit_fx` / `_maid_relay` / `_run_enemy_turn`） |
| 燃尽画面 | `scripts/ui/burnout_screen.gd` |
| F1 沙盒 | `scripts/ui/sandbox_panel.gd` + `main.gd::_sandbox_actions()` |
| 路由 | `scripts/main.gd` |
| 测试 | `tests/smoke_test.gd` |
| 平衡模拟 | `tools/sts_sim.gd` |

---

## 附录 C · 已知坑（来自本项目实战）

1. **改 class_name 不 `--import`** → headless 测试假绿。
2. **批量脚本补丁中断** → 只改了一半，运行时报“函数不存在”；必须整批重放。
3. **`Dictionary.merge()` 默认不覆盖** → 事件字典拿到旧值；用 `merge(..., true)`。
4. **`_draw()` 在子 TextureRect 下面** → 自绘内容看不见；改用子 Label。
5. **九宫格边距量错** → 要量切角宽度，不是边框厚度。
6. **headless 不能截 viewport** → 截图钩子必须走真实渲染或让主人目检。
7. **像素字体字号会塌** → 用像素字体时按整数倍放大。
8. **容器里手算子节点位置会偏** → 用容器 layout，不要硬编码。
9. **`Array.filter()` 返回值无类型** → `:=` 推断失败，显式标注。
10. **测试断言数比文档少 = 假绿** → 先查 class_name / 脚本解析错误。

更多见 `docs/踩坑手册.md`。
