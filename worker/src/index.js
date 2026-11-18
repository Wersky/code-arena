/**
 * Code Arena 门禁 + API 代理 Worker（Cloudflare Workers，免 R2 版）
 *
 * 安全模型（2026-11-18 主人要求「严格保证不被绕过」）：
 *   ① 门禁在**服务端**校验，前端改 JS 无效
 *   ② 游戏资源（game.html / *.pck / *.wasm / *.js）**必须持有效会话才可下载**
 *      —— 这是关键：不然直接敲 /game.html 或 /game.pck 就绕过了门禁
 *   ③ API key 只在 Worker 环境变量里，前端 pck 不含任何密钥
 *   ④ 游戏内 LLM/生图请求走 /proxy/*，由 Worker 加 key 转发
 *
 * ⚠ 为什么要「分片拼接」（2026-11-18 实测）：
 *   Workers 静态资源**单文件**上限 25 MiB，而 game.pck 有 44 MB。
 *   （R2 能存大文件，但当前账号未启用 R2，且开通可能要绑支付方式。）
 *   静态资源**总量**无上限 → 把 pck 切成 game-part1/p2/p3，Worker 按 Range
 *   请求把它们拼成一条流返回，浏览器（Godot 的 Emscripten loader）完全无感。
 *
 *   Godot web loader 用 Range 分块拉取（chunk 1 MiB，见 game.js 里的
 *   `hasByteServing`/`Accept-Ranges`），所以我们必须正确实现 206 语义。
 *
 * 路由：
 *   GET  /                    门禁页（未登录）或重定向到 /game（已登录）
 *   POST /api/gate            提交测试码 → 下发 HttpOnly 签名 Cookie
 *   GET  /api/session         查会话
 *   GET  /game                游戏页（需会话）
 *   GET  /game.pck            分片拼接返回（需会话）
 *   ALL  /proxy/llm/*         转发 LLM（需会话）
 *   ALL  /proxy/img/*         转发生图（需会话）
 */

const COOKIE_NAME = "ca_session";
const SESSION_TTL = 60 * 60 * 6; // 6 小时
const MAX_FAILS = 8;
const FAIL_WINDOW = 60 * 15; // 15 分钟

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".json": "application/json",
};

/** 必须登录才能访问的资源（正则） */
const PROTECTED = [
  /^\/game(\.html)?$/i,
  /^\/game\.(pck|wasm|js|audio\.worklet\.js|audio\.position\.worklet\.js)$/i,
  /^\/game\.png$/i,
  /^\/game\.icon\.png$/i,
  /^\/game\.apple-touch-icon\.png$/i,
  // ⚠ 分片文件本身也必须受保护：否则直接请求 /game-part1.pck 就能绕过
  //   /game.pck 的门禁把资源全下走
  /^\/game-part\d+\.(pck|wasm)$/i,
];

/** 完全公开的白名单（其余一律要求登录） */
const PUBLIC_EXACT = new Set(["/", "/index.html", "/login.html"]);

/**
 * 分片清单：逻辑路径 → 物理文件列表
 * pck/wasm 超过 Workers 静态资源 25 MiB 单文件上限，由 tools/split_pck.py
 * 切成多片，Worker 这里按 Range 拼成一条流返回（浏览器无感）。
 */
const CHUNKED = {
  "/game.pck": ["game-part1.pck", "game-part2.pck"],
  "/game.wasm": ["game-part1.wasm", "game-part2.wasm"],
};

// ── 会话签名 ────────────────────────────────────────────
async function hmac(secret, data) {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const b64url = (s) =>
  btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const unb64url = (s) => {
  const pad = s.length % 4 ? "=".repeat(4 - (s.length % 4)) : "";
  return atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
};

async function makeToken(secret, ttl = SESSION_TTL) {
  if (!secret) throw new Error("SESSION_SECRET missing");
  const exp = Math.floor(Date.now() / 1000) + ttl;
  const payload = b64url(JSON.stringify({ exp, n: crypto.randomUUID() }));
  return `${payload}.${await hmac(secret, payload)}`;
}

async function verifyToken(secret, token) {
  // ⚠ 缺 secret 必须 fail-closed：否则 HMAC 会用字符串 "undefined" 当密钥，
  //   任何人都能自己签一个有效 Cookie 绕过门禁
  if (!secret || !token || !token.includes(".")) return false;
  const [payload, sig] = token.split(".");
  const expect = await hmac(secret, payload);
  if (!sig || sig.length !== expect.length) return false;
  let diff = 0;
  for (let i = 0; i < sig.length; i++) diff |= sig.charCodeAt(i) ^ expect.charCodeAt(i);
  if (diff !== 0) return false;
  try {
    const { exp } = JSON.parse(unb64url(payload));
    return typeof exp === "number" && exp > Math.floor(Date.now() / 1000);
  } catch {
    return false;
  }
}

function getCookie(req, name) {
  const raw = req.headers.get("Cookie") || "";
  for (const part of raw.split(";")) {
    const [k, ...v] = part.trim().split("=");
    if (k === name) return v.join("=");
  }
  return null;
}

// ── 失败限流 ────────────────────────────────────────────
const failMap = new Map();
function bumpFail(ip) {
  const now = Date.now();
  const rec = failMap.get(ip) || { n: 0, at: now };
  if (now - rec.at > FAIL_WINDOW * 1000) { rec.n = 0; rec.at = now; }
  rec.n += 1;
  failMap.set(ip, rec);
  return rec.n;
}
function isBlocked(ip) {
  const rec = failMap.get(ip);
  if (!rec) return false;
  if (Date.now() - rec.at > FAIL_WINDOW * 1000) { failMap.delete(ip); return false; }
  return rec.n >= MAX_FAILS;
}

// ── 响应工具 ────────────────────────────────────────────
const json = (obj, status = 200, extra = {}) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extra,
    },
  });

const sessionCookie = (token) =>
  `${COOKIE_NAME}=${token}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${SESSION_TTL}`;

// ── Range 解析 ──────────────────────────────────────────
/** 返回 {offset, length} / "unsatisfiable" / null（不认，走全量） */
function parseRange(header, total) {
  if (!header) return null;
  const m = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!m) return null;
  const hasStart = m[1] !== "";
  const hasEnd = m[2] !== "";
  if (!hasStart && !hasEnd) return null;

  let start, end;
  if (hasStart) {
    start = parseInt(m[1], 10);
    end = hasEnd ? parseInt(m[2], 10) : total - 1;
  } else {
    // bytes=-N：最后 N 字节
    const n = parseInt(m[2], 10);
    if (n === 0) return "unsatisfiable";
    start = Math.max(0, total - n);
    end = total - 1;
  }
  if (start >= total || end < start) return "unsatisfiable";
  end = Math.min(end, total - 1);
  return { offset: start, length: end - start + 1 };
}

const unsatisfiable = () =>
  new Response("Range Not Satisfiable", {
    status: 416,
    headers: { "Content-Range": "bytes */*", "Accept-Ranges": "bytes" },
  });

// ── 静态资源：交给绑定，它自己不认 Range（见 serveChunked 注释）──
async function fetchAsset(env, name) {
  const url = new URL("https://assets.local/" + name);
  return env.ASSETS.fetch(new Request(url));
}

function mimeOf(name) {
  const ext = name.includes(".") ? "." + name.split(".").pop().toLowerCase() : "";
  return MIME[ext] || "application/octet-stream";
}

// ── 分片拼接：把多个物理文件当成一个逻辑文件返回 ────────
/**
 * ⚠ 关键实测（2026-11-18）：`env.ASSETS.fetch()` **不认 Range 头**
 *   —— 传 `Range: bytes=0-99` 回来仍是 200 + 完整 25MB；
 *   本地 dev 下甚至不给 `Content-Length`（导致早期版本误判"Unknown size" 500）。
 *   所以这里改成：把分片完整读进内存 → 自己按字节切片 → 返回。
 *
 *   内存开销：整个逻辑文件（pck 44MB / wasm 37MB）会短暂驻留。
 *   Workers 免费版 128MB/isolate，单请求可承受；不要并发大文件。
 *
 *   另外**不返回 `Accept-Ranges`**：Godot 的 Emscripten loader 只有在看到
 *   `Accept-Ranges: bytes` 时才切成 1MiB 分块请求
 *   （见 game.js 里的 `hasByteServing`）；不给它，它就一次拉完，
 *   我们只需正确拼一次，省掉 44 次重复读盘。
 */
async function serveChunked(env, request, parts, contentType) {
  if (!env.ASSETS) return new Response("Storage not configured", { status: 503 });

  // ① 把各分片读进内存（拿真实字节数，不依赖 Content-Length）
  const bufs = [];
  for (const p of parts) {
    const resp = await fetchAsset(env, p);
    if (!resp.ok) {
      return new Response(`Missing asset: ${p}`, { status: 404 });
    }
    const buf = new Uint8Array(await resp.arrayBuffer());
    if (!buf.byteLength) {
      return new Response(`Empty asset: ${p}`, { status: 500 });
    }
    bufs.push(buf);
  }
  const total = bufs.reduce((a, b) => a + b.byteLength, 0);

  // ② 解析 Range
  const parsed = parseRange(request.headers.get("Range"), total);
  if (parsed === "unsatisfiable") return unsatisfiable();

  // ③ 拼接（或按 Range 切出子区间）
  const offset = parsed ? parsed.offset : 0;
  const length = parsed ? parsed.length : total;
  const out = new Uint8Array(length);

  let written = 0;
  let cursor = 0; // 逻辑文件内的当前偏移
  for (const buf of bufs) {
    const partStart = cursor;
    const partEnd = cursor + buf.byteLength; // 开区间
    cursor = partEnd;

    const segStart = Math.max(offset, partStart);
    const segEnd = Math.min(offset + length, partEnd);
    if (segEnd <= segStart) continue; // 这段不在范围内

    out.set(buf.subarray(segStart - partStart, segEnd - partStart), written);
    written += segEnd - segStart;
  }

  const headers = new Headers({
    "Content-Type": contentType || mimeOf(parts[0]),
    "Content-Length": String(length),
    "Cache-Control": "private, max-age=3600",
  });
  if (parsed) {
    headers.set("Content-Range", `bytes ${offset}-${offset + length - 1}/${total}`);
    // 只有客户端明确要 Range 时才声明支持，避免 Godot 拆成 44 次 1MiB 请求
    headers.set("Accept-Ranges", "bytes");
  }

  return new Response(out, {
    status: parsed ? 206 : 200,
    headers,
  });
}

// ── 门禁页（内联，不依赖外部文件，无法被单独绕过）────────
const LOGIN_HTML = `<!DOCTYPE html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>代码擂台 Code Arena · 访问验证</title>
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
    background: #0a0d14;
    background-image:
      radial-gradient(circle at 20% 20%, rgba(79,193,246,.10), transparent 55%),
      radial-gradient(circle at 80% 75%, rgba(120,90,200,.10), transparent 55%);
    font-family: -apple-system, "Segoe UI", "Microsoft YaHei", sans-serif;
    color: #e8eef8;
  }
  .card {
    width: min(92vw, 420px); padding: 40px 36px 32px;
    background: rgba(18,24,36,.92); border: 1px solid rgba(79,193,246,.28);
    border-radius: 14px; box-shadow: 0 18px 60px rgba(0,0,0,.55);
    text-align: center;
  }
  h1 { margin: 0 0 6px; font-size: 21px; letter-spacing: .5px; font-weight: 600; }
  .sub { margin: 0 0 26px; font-size: 12.5px; color: #7d8ba3; line-height: 1.7; }
  input {
    width: 100%; padding: 13px 16px; font-size: 15px; letter-spacing: 3px;
    background: #0d121b; border: 1px solid #2b3648; border-radius: 9px;
    color: #e8eef8; outline: none; transition: border-color .18s, box-shadow .18s;
  }
  input:focus { border-color: #4fc1f6; box-shadow: 0 0 0 3px rgba(79,193,246,.15); }
  button {
    width: 100%; margin-top: 14px; padding: 13px;
    font-size: 15px; font-weight: 600; letter-spacing: 1px;
    background: linear-gradient(135deg, #4fc1f6, #3a9bd8);
    border: 0; border-radius: 9px; color: #06121c; cursor: pointer;
    transition: filter .18s, transform .1s;
  }
  button:hover:not(:disabled) { filter: brightness(1.08); }
  button:active:not(:disabled) { transform: translateY(1px); }
  button:disabled { opacity: .55; cursor: not-allowed; }
  .msg { margin-top: 16px; font-size: 13px; min-height: 20px; color: #ff7b72; }
  .msg.ok { color: #58d68d; }
  .foot { margin-top: 26px; font-size: 11px; color: #4c5a70; }
</style>
</head><body>
  <div class="card">
    <h1>代码擂台 Code Arena</h1>
    <p class="sub">这是私人在线演示。<br>请输入访问码以继续。</p>
    <input id="code" type="password" placeholder="访问码" autocomplete="off" autofocus>
    <button id="go">进入</button>
    <div class="msg" id="msg"></div>
    <div class="foot">Godot 4.7.2 · 2D 肉鸽卡牌</div>
  </div>
<script>
(function () {
  var input = document.getElementById('code');
  var btn = document.getElementById('go');
  var msg = document.getElementById('msg');

  function setMsg(t, ok) {
    msg.textContent = t || '';
    msg.className = 'msg' + (ok ? ' ok' : '');
  }

  async function submit() {
    var code = input.value.trim();
    if (!code) { setMsg('请输入访问码'); return; }
    btn.disabled = true; setMsg('验证中…', true);
    try {
      var r = await fetch('/api/gate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin',
        body: JSON.stringify({ code: code }),
      });
      var j = await r.json().catch(function () { return {}; });
      if (r.ok && j.ok) {
        setMsg('验证通过，正在进入…', true);
        setTimeout(function () { location.replace('/game'); }, 260);
        return;
      }
      setMsg(j.error || ('验证失败（' + r.status + '）'));
    } catch (e) {
      setMsg('网络错误，请重试');
    }
    btn.disabled = false;
  }

  btn.addEventListener('click', submit);
  input.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') { e.preventDefault(); submit(); }
  });
}());
</script>
</body></html>`;

// ── 主入口 ──────────────────────────────────────────────
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    const path = url.pathname;
    const token = getCookie(request, COOKIE_NAME);
    const authed = await verifyToken(env.SESSION_SECRET, token);

    // ① 门禁接口
    if (path === "/api/gate" && request.method === "POST") {
      // 配置缺失先行 fail-closed：没配访问码/签名密钥就一律 503，
      // 不进入比对逻辑（否则空串/任何码都能过）
      const expect = String(env.ACCESS_CODE || "");
      if (!expect) return json({ ok: false, error: "服务端未配置访问码" }, 503);
      if (!env.SESSION_SECRET) return json({ ok: false, error: "服务端未配置 SESSION_SECRET" }, 503);

      if (isBlocked(ip)) return json({ ok: false, error: "尝试过多，请 15 分钟后再试" }, 429);
      let code = "";
      try { code = String((await request.json())?.code ?? "").trim(); }
      catch { return json({ ok: false, error: "请求格式错误" }, 400); }
      if (!code) return json({ ok: false, error: "请输入访问码" }, 400);

      let diff = expect.length ^ code.length;
      for (let i = 0; i < Math.max(expect.length, code.length); i++) {
        diff |= (expect.charCodeAt(i) || 0) ^ (code.charCodeAt(i) || 0);
      }
      if (diff !== 0) {
        const n = bumpFail(ip);
        return json({ ok: false, error: "访问码不正确", left: Math.max(0, MAX_FAILS - n) }, 401);
      }
      const tk = await makeToken(env.SESSION_SECRET);
      return json({ ok: true }, 200, { "Set-Cookie": sessionCookie(tk) });
    }

    // ② 会话查询
    if (path === "/api/session") return json({ ok: authed });

    // ③ 代理（必须登录）
    if (path.startsWith("/proxy/")) {
      if (!authed) return json({ ok: false, error: "未登录" }, 401);

      let base, key, rest;
      if (path.startsWith("/proxy/llm/")) {
        base = env.LLM_BASE; key = env.LLM_KEY; rest = path.slice("/proxy/llm".length);
      } else if (path.startsWith("/proxy/img/")) {
        base = env.IMG_BASE; key = env.IMG_KEY; rest = path.slice("/proxy/img".length);
      } else {
        return json({ ok: false, error: "未知代理目标" }, 404);
      }
      if (!base || !key) return json({ ok: false, error: "后端未配置" }, 503);

      // ⚠ 去重复版本段（2026-11-18 实测）：
      //   游戏内拼出来的 rest 是 "/v1/chat/completions"，而 LLM_BASE
      //   https://api.commandcode.ai/provider/v1 本身已经以 /v1 结尾 →
      //   直接拼会变成 .../provider/v1/v1/chat/completions → 上游 404。
      //   实测 .../provider/v1/chat/completions 才是 200。
      let trimmedBase = base.replace(/\/+$/, "");
      let cleanRest = rest;
      if (/\/v1$/.test(trimmedBase) && /^\/v1\//.test(cleanRest)) {
        cleanRest = cleanRest.slice(3);   // 去掉 rest 开头的 "/v1"
      }
      const target = trimmedBase + cleanRest + url.search;

      // 复制请求头，剔除会泄露来源/触发 CORS 的，换成服务端密钥
      const headers = new Headers();
      for (const [k, v] of request.headers) {
        const lk = k.toLowerCase();
        if (["host", "origin", "referer", "cookie", "cf-connecting-ip", "cf-ray",
             "cf-visitor", "authorization", "x-forwarded-for", "content-length",
             // ⚠ 必须剔除（2026-11-18 实测）：Godot 的 HTTPRequest 默认发
             //   "Accept-Encoding: gzip"，Cloudflare 边缘看到就压缩响应，
             //   而 Godot 的 StreamPeerGZIP 解不开（header 被改写/分块），
             //   报 core/io/stream_peer_gzip.cpp:117 FAILED，整条响应作废。
             //   去掉它 → 上游回明文 → 边缘不再压 → Godot 正常拿到 JSON。
             "accept-encoding"].includes(lk)) continue;
        headers.set(k, v);
      }
      headers.set("Authorization", `Bearer ${key}`);

      const resp = await fetch(target, {
        method: request.method,
        headers,
        body: ["GET", "HEAD"].includes(request.method) ? undefined : request.body,
      });

      // ⚠ 剔除压缩相关头（2026-11-18 实测）：
      //   上游/边缘可能给出 Content-Encoding: gzip + 已解压的 body（或反之），
      //   Godot 的 HTTPRequest 用 StreamPeerGZIP 硬解，一旦不匹配就报
      //   "Condition "err != 0 && err != 1" is true. Returning: FAILED
      //   （core/io/stream_peer_gzip.cpp:117）而整条响应作废。
      //   这里统一剥掉，让响应保持明文 JSON。
      const out = new Headers(resp.headers);
      out.delete("set-cookie");
      out.delete("content-encoding");
      out.delete("content-length");
      out.delete("transfer-encoding");
      return new Response(resp.body, { status: resp.status, headers: out });
    }

    // ④ 首页：已登录→游戏，未登录→门禁页
    if (path === "/" || path === "/index.html" || path === "/login.html") {
      if (authed && (path === "/" || path === "/index.html")) {
        return Response.redirect(url.origin + "/game", 302);
      }
      return new Response(LOGIN_HTML, {
        status: 200,
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store",
          "X-Frame-Options": "DENY",
          "Referrer-Policy": "no-referrer",
        },
      });
    }

    // ⑤ 游戏页
    if (path === "/game") {
      if (!authed) return Response.redirect(url.origin + "/", 302);
      return serveFromAssets(env, request, "game.html");
    }

    // ⑥ 分片资源（pck / wasm 超过 25 MiB，必须拼）
    if (CHUNKED[path]) {
      if (!authed) return new Response("Forbidden", { status: 403 });
      return serveChunked(env, request, CHUNKED[path], mimeOf(path));
    }

    // ⑦ 受保护资源（单文件，未超限）
    if (PROTECTED.some((re) => re.test(path))) {
      if (!authed) return new Response("Forbidden", { status: 403 });
      return serveFromAssets(env, request, path.replace(/^\/+/, ""));
    }

    // ⑧ 其他一切（图标等）——**默认也要求登录**。
    //    fail-closed：宁可多拦一个图标，也不要漏放一个资源。
    //    只有下面这几个明确无害的小图标公开。
    const PUBLIC_ASSET = /^\/game\.(apple-touch-icon|icon)\.png$/i;
    if (PUBLIC_ASSET.test(path)) {
      return serveFromAssets(env, request, path.replace(/^\/+/, ""));
    }
    if (!authed) return new Response("Forbidden", { status: 403 });
    return serveFromAssets(env, request, path.replace(/^\/+/, ""));
  },
};

/** 单文件静态资源（交给 Workers 静态资源绑定，它自己处理 Range/ETag） */
async function serveFromAssets(env, request, name, extraHeaders = {}) {
  if (!env.ASSETS) return new Response("Storage not configured", { status: 503 });
  const url = new URL("https://assets.local/" + name);
  const resp = await env.ASSETS.fetch(new Request(url, {
    method: request.method,
    headers: request.headers,
  }));
  if (!resp.ok) return resp;
  const headers = new Headers(resp.headers);
  headers.set("Accept-Ranges", "bytes");
  for (const [k, v] of Object.entries(extraHeaders)) headers.set(k, v);
  return new Response(resp.body, { status: resp.status, headers });
}
