# Godot 技能库（随仓库分发）

`.zcode/skills/` 下有 **154 个 Godot 相关技能**（每个是 `SKILL.md` + 参考文件 / 脚本）。
这是 ZCode（小萤）在 Godot 上积累的全部可复用知识。

## 怎么用

- **在 ZCode 里工作**：技能会自动被发现（`.zcode/skills/` 是约定目录），
  直接说「用 gd-genre-platformer 这个 skill」或让它自己匹配。
- **不是 ZCode**：直接读 `.zcode/skills/<名字>/SKILL.md`，正文就是可执行的做法。

## 本项目最常用的 9 个

| 技能 | 什么时候看 |
|---|---|
| `gd-gdscript-mastery` | GDScript 高级写法、类型系统、坑 |
| `gd-godot-testing` / `gd-headless-testing` | 无头测试、`--script` 跑断言 |
| `gd-scene-management` | 界面路由、切屏、生命周期 |
| `gd-state-machine` / `gd-state-machine-advanced` | 状态机骨架 |
| `gd-resource-data-patterns` | Resource 当数据表（本项目的牌/关卡就是这么做的） |
| `gd-performance-optimization` | 掉帧、draw call、对象池 |
| `gd-save-load-systems` | 存档 |
| `gd-export-builds` / `gd-export-selfcontained` | 打包成 exe |
| `gd-genre-*` | 各品类玩法骨架（卡牌/肉鸽/塔防…） |

## 硬约定

1. **先读技能再动手**，不要凭印象写 Godot 4 代码（3 和 4 的 API 差别很大）。
2. 技能里的代码是「可直接抄的解法」，不是散文——照抄后按本项目命名调整。
3. 发现技能里写错/过时，**顺手改掉并提交**，这是共享资产。
