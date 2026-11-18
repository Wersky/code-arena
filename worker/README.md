# 把游戏放到网上（Cloudflare Worker，免 R2 / 免绑卡）

> 目标：面试官打开网址 → 输访问码 `<ACCESS_CODE>` → 玩网页版；**你的 API key 全程在服务端**。

---

## 你只需要跑 4 条命令

```powershell
cd D:\zcode-work\godot\projects\prompt-arena

# ① 打包（剥离 key → 导出 → 校验 → 分片 → 整理部署目录）
tools\export_web.bat

# ② 设服务端密钥（只需一次，值不会进仓库）
cd worker
wrangler secret put ACCESS_CODE        # 输 <ACCESS_CODE>
wrangler secret put SESSION_SECRET     # 随便一串随机字符
wrangler secret put LLM_BASE           # https://api.commandcode.ai/provider/v1
wrangler secret put LLM_KEY            # 你的 commandcode key
wrangler secret put IMG_BASE           # https://kuaipao.pro
wrangler secret put IMG_KEY            # 你的 kuaipao key

# ③ 部署
wrangler deploy

# ④ 验证（无痕窗口）
#   <你的网址>/game.pck   → 必须 403
#   <你的网址>/           → 看到门禁页，输 <ACCESS_CODE> 进游戏
```

部署成功会打印 `https://code-arena-gate.<你的账号>.workers.dev`。

---

## 为什么不用 R2（2026-11-18 实测）

一开始想用 R2 存 44MB 的 pck，但 `wrangler r2 bucket create` 报：

```
Please enable R2 through the Cloudflare Dashboard. [code: 10042]
```

R2 要在控制台开通，**可能要绑支付方式**。为了不让你绑卡，改走这条：

- Workers 静态资源**单文件**上限 25 MiB
- 但**总量无上限**
- 所以把 `game.pck`(44MB) / `game.wasm`(37.7MB) 各切成 2 片（各 ≤24 MiB）
- Worker 在 `/game.pck` 处按 Range 把它们**拼成一条流**返回
- 浏览器和 Godot 完全无感（它以为在下一个完整文件）

实测：SHA256 完全一致（`b943088…` / `fc7467…`），跨片 Range 也正确。

---

## ⚠ 三个必须知道的安全要点

### 1. Web 版 pck 绝不能带内置 key

`llm_config.gd` 的 `BUILTIN_KEY_OBF` / `BUILTIN_IMG_KEY_OBF` 是 `const`，
即使运行时走 `OS.has_feature("web")` 的代理分支，它们**照样被编进 pck**。
Godot 4 的 pck 内部块是 **zstd** 压缩（不是 zlib），解压后配合
`_MASK = "prompt-arena-llm-v1"` 做 XOR 就能还原出真实 key：

```
实测解出 → user_XXXX…XXXX  ← commandcode key
实测解出 → sk-XXXX…XXXX  ← kuaipao key
```

所以 `tools\export_web.bat` 会在导出前**物理清空**这两个常量，导出后立刻还原。
`tools\verify_web_pack.py` 会遍历所有 zstd frame 真解真试反混淆，解出就判失败。

**永远不要直接 `godot --export-release Web`。**

### 2. `run_worker_first = true` 必须开

默认 `false` 时，凡是能匹配静态资源的请求（`/game-part1.pck`、`/game.js`、
`/game.html`）会**绕过 Worker 直接由 CDN 返回** —— 门禁形同虚设。
`wrangler.toml` 里已经设了 `true`，别改回去。

同时 `[assets]` 必须写 `binding = "ASSETS"`，否则 Worker 拿不到 `env.ASSETS`。

### 3. 分片文件本身也要受保护

`/game-part1.pck` 如果不管，直接请求就能把资源全下走。
`src/index.js` 的 `PROTECTED` 里已包含 `/^\/game-part\d+\.(pck|wasm)$/i`，
且**默认分支 fail-closed**（只有两个小图标公开）。

---

## 这轮踩到并修掉的 4 个真 bug

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 「测试连接」报 `Error parsing URL: '/proxy/llm/v1/chat/completions'` | Godot 的 `HTTPRequest` **只接受绝对 URL**，而 Web 版 base 是同源相对路径 | `llm_protocol.gd` 加 `absolutize()`，用 `JavaScriptBridge` 取 `location.origin` 补全 |
| 2 | 代理 `200` 但游戏报 `stream_peer_gzip.cpp:117 FAILED` | `HTTPRequest.accept_gzip` 默认 `true`，经 Worker+边缘压缩后解不开 | 客户端 Web 版 `http.accept_gzip = false`；Worker 侧剔除 `accept-encoding` 请求头 |
| 3 | 上游 `404` | base `.../provider/v1` 已带 `/v1`，游戏又拼 `/v1/chat/completions` → 双 `/v1` | Worker 转发时去重复版本段 |
| 4 | `env.ASSETS.fetch()` 传 Range 无效，还拿不到 Content-Length | 实测静态资源绑定的 fetch **不认 Range** | 改成整片读进内存再自己切片（pck 44MB，128MB 内存够） |

第 4 条附带一个设计决定：**不给 `Accept-Ranges`**（除非客户端主动要 Range）。
因为 Godot 的 Emscripten loader 看到 `Accept-Ranges: bytes` 会切成 44 次 1MiB 请求，
每片拼接都重复读盘 44MB；不给它，一次拉完，快得多。

---

## 安全模型

```
面试官浏览器
    │ ① POST /api/gate {code:"<ACCESS_CODE>"}
    ▼
Cloudflare Worker（服务端）
    │ ② 常量时间比对 ACCESS_CODE
    │    对 → HMAC 签名 Cookie（HttpOnly+Secure+SameSite=Lax，6h）
    │    错 → 401，同 IP 累计 8 次封 15 分钟
    ▼
    │ ③ /game、/game.pck、/game-part1.pck、/proxy/* 全部验 Cookie
    │    无 / 篡改 / 过期 → 403
    ▼
Workers 静态资源（分片）
    │ ④ /game.pck = game-part1.pck + game-part2.pck 按 Range 拼接
    ▼
/proxy/llm/* → 服务端注入 Authorization → commandcode
/proxy/img/* → 服务端注入 Authorization → kuaipao
```

**你的 key 在哪**：只在 Cloudflare Secret 里。
**浏览器能看到什么**：一个 HttpOnly Cookie + 已授权下载的游戏文件（`api_key = ""`）。

### 安全测试：40 项全过

```
门禁      匿名首页 200 / 匿名 pck 403 / 匿名 game.html 403 / 匿名 proxy 401
         错误码 401 / 正确码 200+Cookie / Cookie 三属性齐全
分片      全量拼接正确 / 跨片 Range 206 / 片内 Range / open-ended / suffix
         越界 416 / 反向 416 / wasm 拼接 / Content-Range 与 Length 精确
绕过防护  匿名 game-part1.pck 403 / game-part2.wasm 403
         授权分片可下载 / 匿名未知路径 403 / 匿名不存在分片 403
Cookie    篡改 403 / 伪造 403
代理      注入服务端 key（覆盖客户端） / 剥离 Origin
fail-closed 缺 SESSION_SECRET 未授权 / 缺 ACCESS_CODE 503 / 缺 ASSETS 503
```

---

## 改访问码 / 撤销访问

```powershell
cd worker
wrangler secret put ACCESS_CODE     # 换新码
wrangler deploy
```

旧 Cookie 仍有效（签名密钥没变）。**要立刻让所有人失效**：
```powershell
wrangler secret put SESSION_SECRET  # 换新随机串
wrangler deploy
```

---

## 本地预览

```powershell
cd worker
# .dev.vars 已存在（占位 key，gitignore 排除）；要真测就把 key 填进去
npx wrangler dev --port 8798 --local
# → http://127.0.0.1:8798
```

⚠ 本地 `wrangler dev --local` 会代理到你系统里的 HTTP_PROXY，
真实调用上游时请确认代理设置。

---

## 文件对照

```
worker/
  wrangler.toml       [assets] directory=./public, binding=ASSETS, run_worker_first=true
  src/index.js        门禁 + 签名 Cookie + 分片拼接 + API 代理
  public/             ← tools/stage_web.py 生成（只放分片，不放大原文件）
  .dev.vars           本地开发变量（gitignore）

tools/
  export_web.bat      ★ 唯一正确的 Web 打包入口（7 步全自动）
  strip_builtin_keys.py   清空/检查/还原内置凭据常量
  verify_web_pack.py      解 zstd 真扫密钥，能还原即判失败
  split_pck.py            切 >25 MiB 文件为分片
  stage_web.py            整理出 worker/public 部署目录

build/web/            Godot 导出产物（原始大文件 + 分片，gitignore）
```

---

## 常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| `Asset too large` | 原始 pck/wasm 被上传了 | 跑 `tools\export_web.bat`，它会 stage 成 `worker/public` |
| 打开 503 `Storage not configured` | 缺 `binding = "ASSETS"` | 检查 wrangler.toml 的 `[assets]` |
| 匿名能下 `/game-part1.pck` | `run_worker_first` 没开 | 改成 `true` 重新 deploy |
| 加载卡在 0% | 分片没上传 / 名字不对 | 查 `worker/public` 有没有 `game-part1.pck` |
| 进游戏但 AI 报错 | 见上面 4 个 bug 表 | 确认 worker/客户端都是最新代码 |
| AI 报「后端未配置」503 | secret 没设或被 `[vars]` 覆盖 | 删掉 wrangler.toml 里的 `[vars]`，重设 secret |
| 中文显示成方框 | 仅无头 Chromium 字体缺失 | 真实浏览器正常 |
