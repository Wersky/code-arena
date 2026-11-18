# -*- coding: utf-8 -*-
"""Web 版 pck 凭据校验器（部署前最后一道闸门）。

背景（2026-11-18 实测确认）：llm_config.gd 里 BUILTIN_KEY_OBF /
BUILTIN_IMG_KEY_OBF 是 const，即使运行时走 OS.has_feature("web") 的
代理分支，这两个常量 + XOR 掩码仍会被编进 game.pck。
Godot 4 用 **zstd** 压缩 pck 内部块（不是 zlib），解压后能直接还原出
真实 key。所以 Web 导出前必须清空这些常量（见 tools/export_web.bat）。

这个脚本真的会：
  1. 扫明文（pck 原始字节）；
  2. 遍历所有 zstd frame 解压，在解压内容里扫；
  3. 对每个 b64: 块尝试用掩码反混淆，能还原出 sk-/user_ 形态即判失败。

用法：
    python tools/verify_web_pack.py build/web/game.pck
退出码：0=干净，1=发现凭据或异常
"""

import base64
import os
import re
import sys

try:
    import zstandard as zstd
except ImportError:
    print("[ERROR] 需要 zstandard：pip install zstandard")
    sys.exit(1)

ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"

# ── 绝对不允许出现在 Web 包里的明文片段 ────────────────────
# 说明：具体 key 前缀刻意不写进仓库（这是公开仓库，写前缀等于泄露一半）。
# 真正的把关靠下面两条「结构性」判据，它们不依赖任何具体密钥值：
#   ① KEY_BLOB_RE      — 包里不该存在任何 b64: 混淆块
#   ② SECRET_SHAPE_RE  — 解包后不该出现 sk-xxx / user_xxx 形态的长串
# 若你想额外盯某几个已知前缀，用环境变量 VERIFY_EXTRA_NEEDLES 注入
# （逗号分隔），不必改这个文件。
FORBIDDEN_PLAIN = [
    n.encode() for n in os.environ.get("VERIFY_EXTRA_NEEDLES", "").split(",") if n.strip()
]

# 网关域名与 XOR 掩码：不是密钥，但出现在 Web 包里说明内置凭据逻辑还在。
# 只作提示（WARN），不判失败——桌面版代码同源，清空 key 后这些常量无害。
SOFT_HINTS = [
    b"api.commandcode.ai",
    b"kuaipao.pro",
    b"prompt-arena-llm-v1",
]

KEY_BLOB_RE = re.compile(rb"b64:[A-Za-z0-9+/=]{16,}")
SECRET_SHAPE_RE = re.compile(rb"(sk-[A-Za-z0-9]{20,}|user_[A-Za-z0-9]{20,})")
XOR_MASK = b"prompt-arena-llm-v1"


def xor_deobf(body: bytes) -> bytes:
    raw = base64.b64decode(body, validate=False)
    return bytes(b ^ XOR_MASK[i % len(XOR_MASK)] for i, b in enumerate(raw))


def zstd_chunks(data: bytes):
    """遍历所有 zstd frame 并解压（每个 frame 从 magic 开始）。"""
    out = []
    pos = 0
    while True:
        i = data.find(ZSTD_MAGIC, pos)
        if i < 0:
            break
        try:
            dctx = zstd.ZstdDecompressor()
            # 只解这一个 frame，不吞后面的
            dobj = dctx.decompressobj()
            raw = dobj.decompress(data[i:])
            if raw:
                out.append(raw)
        except Exception:
            pass
        pos = i + 4
    return out


def scan(label: str, blob: bytes, failures: list, warns: list):
    for needle in FORBIDDEN_PLAIN:
        if needle in blob:
            failures.append(f"{label}: 明文命中真实密钥前缀 {needle.decode('latin1')}")

    for needle in SOFT_HINTS:
        if needle in blob:
            warns.append(f"{label}: 内置凭据相关常量仍在（{needle.decode('latin1')}）— 无害但可清理")

    for m in KEY_BLOB_RE.finditer(blob):
        tok = m.group(0)
        failures.append(f"{label}: 发现 b64: 密钥块（{len(tok)}B，前 24：{tok[:24].decode('latin1')}…）")
        try:
            plain = xor_deobf(tok[4:])
            hit = SECRET_SHAPE_RE.search(plain)
            if hit:
                failures.append(
                    f"{label}: ⚠ 反混淆成功 → 真实密钥 {hit.group(0)[:14].decode('latin1')}… 可被直接提取"
                )
        except Exception:
            pass

    for m in SECRET_SHAPE_RE.finditer(blob):
        failures.append(f"{label}: 发现密钥形态字符串 {m.group(0)[:14].decode('latin1')}…")


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: python tools/verify_web_pack.py <game.pck>")
        return 1

    path = sys.argv[1]
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        print(f"[ERROR] 读不到 {path}: {e}")
        return 1

    if data[:4] != b"GDPC":
        print(f"[ERROR] {path} 不是 Godot pck（magic={data[:4]!r}）")
        return 1

    print(f"[1/3] 扫描 {path}  ({len(data) / 1048576:.2f} MB) 原始字节 ...")
    failures: list[str] = []
    warns: list[str] = []
    scan("pck", data, failures, warns)

    print("[2/3] 遍历 zstd frame 解压后再扫 ...")
    chunks = zstd_chunks(data)
    total = sum(len(c) for c in chunks)
    print(f"      解出 {len(chunks)} 个 frame，共 {total / 1048576:.2f} MB")
    if len(chunks) == 0:
        print("      ⚠ 一个 frame 都没解出来 —— 这个校验结果不可信，按失败处理")
        failures.append("pck: 无法解出任何 zstd frame（校验器可能不匹配该 pck 格式）")
    for idx, ch in enumerate(chunks):
        scan(f"zstd#{idx}", ch, failures, warns)

    print("[3/3] 判定 ...")
    if failures:
        uniq = list(dict.fromkeys(failures))
        print(f"\n[FAIL] 发现 {len(uniq)} 处问题：")
        for f_ in uniq[:25]:
            print("       - " + f_)
        if len(uniq) > 25:
            print(f"       ... 还有 {len(uniq) - 25} 条")
        print("\n[结论] 这个 pck 不能部署到公网。")
        print("       请用 tools\\export_web.bat 重新导出（它会先剥掉内置凭据）。")
        return 1

    uniq_warns = list(dict.fromkeys(warns))
    if uniq_warns:
        print(f"\n[WARN] {len(uniq_warns)} 条提示（不影响部署）：")
        for w in uniq_warns[:10]:
            print("       - " + w)

    print("\n[PASS] 未发现任何凭据残留，可以部署。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
