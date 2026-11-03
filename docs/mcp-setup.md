# MCP 接入指南 · 多 agent 协作环境

> 目标：任何一台机器 clone 本仓库后，按本文档 5 分钟内配好联网检索与 B 站采集，让 CodeArts / ZCode / 其他 agent 共用同一套工具。
> **安全红线：API key、Cookie、扫码凭证一律不进仓库。** 本文所有 key 均为占位符。

## 1. 工具矩阵

| MCP | 作用 | 必需性 |
|---|---|---|
| `tavily` | 联网搜索 / 抓取 / 研究（查 Godot 文档、AI 热梗、行业资料） | 强烈建议 |
| `bilibili` | 搜 B 站视频 / 扒评论 / 弹幕 / 字幕（热梗素材、玩家反馈采集） | 可选 |

## 2. Tavily · CodeArts 配置

用户级文件：`%APPDATA%\codearts-agent\User\mcp.json`

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

要点：

- CodeArts 用 `{"servers": {...}}` 结构，**不是** Claude 的 `mcpServers`。
- 访问权限默认 `chat.mcp.access = "all"`；工具不出现时先查这一项，再重启。
- 远程备选（不走本地 Node）：

  ```json
  { "servers": { "tavily": { "type": "http", "url": "https://mcp.tavily.com/mcp/?tavilyApiKey=<key>" } } }
  ```

- Key 申请：https://app.tavily.com → API Keys → 复制 `tvly-` 开头的 key。
- 本机已验证：Node `v24.19.0` + `tavily-mcp 0.2.22`，`initialize` 握手通过。

## 3. Tavily · ZCode 配置

`~/.zcode/cli/config.json` 的 `mcp.servers` 下加同样条目（ZCode 用 `mcp.servers`，CodeArts 用 `servers`，注意区分）：

```json
"tavily": {
  "type": "stdio",
  "command": "D:\\nodejs\\npx.cmd",
  "args": ["-y", "tavily-mcp"],
  "env": { "TAVILY_API_KEY": "<key>", "NO_PROXY": "*", "no_proxy": "*" }
}
```

## 4. B 站 MCP（bilibili-mcp）

仓库：https://github.com/adoresever/bilibili-mcp （MIT，27 个工具）

安装（Windows，装在项目外，例如 `D:/zcode-work/mcp/bilibili-mcp`）：

```bash
git clone --depth 1 https://github.com/adoresever/bilibili-mcp.git D:/zcode-work/mcp/bilibili-mcp
cd D:/zcode-work/mcp/bilibili-mcp
python -m venv .venv
.venv/Scripts/python.exe -m pip install -r requirements.txt
.venv/Scripts/python.exe -m pip install "mcp<2.0.0"   # 关键：mcp 2.x 移除了 FastMCP API
```

CodeArts 用户级 `mcp.json` 的 `servers` 里追加：

```json
"bilibili": {
  "type": "stdio",
  "command": "D:/zcode-work/mcp/bilibili-mcp/.venv/Scripts/python.exe",
  "args": ["D:/zcode-work/mcp/bilibili-mcp/mcp_server.py"],
  "env": { "NO_PROXY": "*", "no_proxy": "*" }
}
```

ZCode `config.json` 的 `mcp.servers` 加同样条目。

**首次登录**：重启 agent → 对 agent 说「登录 B 站」→ 调 `bili_login` 生成二维码 → B 站 App 扫码 → `bili_login_check` 确认。凭证保存在本地 `bili_credential.json`，勿提交、勿外传。

常用工具：

| 工具 | 用途 |
|---|---|
| `bili_search` | 关键词搜视频（totalrank / click / pubdate） |
| `bili_comments` | 视频热门评论（含子评论） |
| `bili_danmaku` | 弹幕列表 |
| `bili_subtitle` | AI 字幕 |
| `bili_video_info` | 视频详情 / 播放量 / 评论数 |

本机已验证：`bilibili-mcp 1.30.0`，`tools/list` 返回 27 个工具，扫码登录成功。

## 5. 验证

- Agent 就绪后让它执行 `tavily_search` 搜一个 Godot 问题，返回带 URL 的结果即成功。
- B 站：让它 `bili_search` 搜「大肥鱼」，返回视频列表即成功；再 `bili_comments` 扒一条热评验证。

## 6. 排错

| 现象 | 处理 |
|---|---|
| MCP 工具列表里没有 | 重启 agent；CodeArts 查 `chat.mcp.access` 是否为 `all` |
| 报 `npx` 找不到 | `command` 用绝对路径 `D:\\nodejs\\npx.cmd` |
| bilibili 报 `No module named 'mcp.server.fastmcp'` | venv 里执行 `pip install "mcp<2.0.0"` |
| B 站工具报未登录 / 401 | 重新 `bili_login` 扫码 |
| 公司代理拦截 | 保留 `NO_PROXY=*` / `no_proxy=*` |
| 第一次启动慢 | `npx -y tavily-mcp` 首次要下载包，之后走缓存 |

## 7. Godot MCP（本机已装两套）

### 7.1 godot-mcp-flash（无头优先）

25 个工具，零插件。本机已全局安装 `npm install -g godot-mcp-flash`（1.0.1）。真正贴合本项目「无头验证」纪律的是：

- `validate_script`：用 Godot 的 headless 语法检查器校验单个 `.gd`
- `get_scene_insights` / `get_node_insights`：纯文本解析 `.tscn` / `.gd`（headless 可用）
- `get_uid` / `update_project_uids`：Godot 4.4+ UID 读取与引用更新
- `list_projects` / `get_project_info` / `list_project_files`：项目结构与文件发现

配置（CodeArts 的 `servers` / ZCode 的 `mcp.servers` 同款字段）：

```json
"godot-mcp-flash": {
  "type": "stdio",
  "command": "D:/npm-global/godot-mcp-flash.cmd",
  "args": [],
  "env": {
    "GODOT_PATH": "D:/zcode-work/godot/engine/Godot_v4.7.2-stable_win64_console.exe"
  }
}
```

也可不全局安装，改成 `command: D:/nodejs/npx.cmd` + `args: ["-y", "godot-mcp-flash"]`。

**约束**：`launch_editor` / `run_project` / `run_scene` / `capture_screenshot` 会开真实窗口，主人在玩时禁用；日常只用 `validate_script(s)` / `get_project_info` / `list_project_files` / `view_log` / `get_scene_insights` 等无头工具。

**验证**：`tools/list` 返回 25 个工具（server name `godot-mcp 1.0.0`）。

### 7.2 Godot AI（编辑器内调试）

48 个工具：编辑器/运行时状态、日志、截图、场景树、脚本与节点编辑、信号、UI/材质/动画/粒子/相机配置。

- Python 包：`uv tool install godot-ai`（4.4.1，可执行在 `C:/Users/33477/.local/bin/godot-ai.exe`，**不在 PATH**）
- 插件：`addons/godot_ai/`（v4.4.1，`project.godot` 的 `[editor_plugins]` 已启用）
- 注意：GitHub Release 里 **`godot-ai-v4-plugin.zip` 才是正式插件**；`godot-ai-plugin.zip` 只是 v3→v4 迁移桥
- MCP 配置（v4 必须用 `attach` 作为 stdio 桥，不能裸起 server）：

```json
"godot-ai": {
  "type": "stdio",
  "command": "C:/Users/33477/.local/bin/godot-ai.exe",
  "args": ["attach"],
  "env": { "GODOT_AI_DISABLE_TELEMETRY": "true" }
}
```

- **前提**：Godot 编辑器必须运行且 Godot AI 插件已启用；首次在编辑器 Godot AI dock 里点 **Configure** 完成客户端授权（v4 走 `godot-ai attach` 认证，裸 HTTP 不行）。
- **更新**：在 dock 点 **Update**，不要用新版本覆盖解压。
- **约束**：会开编辑器窗口，只能在主人明确允许时用。
- **验证**：`tools/list` 返回 48 个工具（server name `Godot AI attach 4.1.3`）。

### 7.3 两个怎么分工

| 场景 | 用哪个 |
|---|---|
| 改完脚本先查语法 | godot-flash `validate_script`（无头） |
| 查 `.tscn`/`.gd` 结构、UID | godot-flash `*_insights` / `get_uid`（无头） |
| 需要看编辑器画面、读运行日志、截图验收 | godot-ai（需开编辑器，主人允许时） |
| 跑完整 smoke / 平衡模拟 | 都不用，直接命令行 `--headless` |

