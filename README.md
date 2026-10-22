# 代码擂台 Code Arena

> Godot 4.7.2 · 2D 肉鸽卡牌 · 纯鼠标操作
> 玩家选一位 AI 娘，她画在每张牌中间；把牌凑成德州扑克牌型打出去，`筹码 × 倍率` 得分。

**私密仓库，由 ZCode（小萤）与 wb 共同维护。**

---

## 接手前必读（按顺序）

| # | 文档 | 作用 |
|---|---|---|
| 1 | [`docs/进度交接.md`](docs/进度交接.md) | **项目状态唯一真值**：做到哪了、下一步从哪开始 |
| 2 | [`docs/05-交接与协作.md`](docs/05-交接与协作.md) | 两个人怎么不打架：认领、分支、交接纪律 |
| 3 | [`docs/踩坑手册.md`](docs/踩坑手册.md) | 40 条真实踩坑，动手前扫一眼 |
| 4 | [`docs/04-基础玩法.md`](docs/04-基础玩法.md) | 玩法规格：牌型表 / 计分 / 关卡 |

---

## 快速开始

```bash
GODOT="D:/zcode-work/godot/engine/Godot_v4.7.2-stable_win64_console.exe"

"$GODOT" --path .                                   # 游玩
"$GODOT" --headless --path . --script res://tests/smoke_test.gd     # 169 项回归
"$GODOT" --headless --path . --script res://tests/_meme_selftest.gd # 219 项存档回归
"$GODOT" --headless --path . --script res://tests/verify_c4.gd      # 旧机制算例 4 项
```

---

## 一句话状态

**玩法可玩、52 张卡面已画完，但新卡面还没接进游戏。**
具体见 [`docs/进度交接.md`](docs/进度交接.md) §2.3「账实不符」。
