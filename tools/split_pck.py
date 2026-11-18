# -*- coding: utf-8 -*-
"""把超过 25 MiB 的 Web 资源切成多片，绕开 Workers 静态资源单文件上限。

背景（2026-11-18 实测）：
    Cloudflare Workers 静态资源**单文件**上限 25 MiB（Free/Paid 相同），
    但**总量无上限**。game.pck 44 MB、game.wasm 37.7 MB 都超限。

做法：
    把 game.pck 切成 game-part1.pck / game-part2.pck / ...（每片 <25 MiB），
    由 Worker 的 serveChunked() 按 Range 拼成一条流返回给浏览器。
    Godot 的 Emscripten loader 用 Range 分块拉（chunk 1 MiB），完全无感。

用法：
    python tools/split_pck.py build/web [--target game.pck] [--chunk-mib 24]
退出码：0=成功
"""

import argparse
import os
import sys

MIB = 1024 * 1024
LIMIT = 25 * MIB              # Workers 静态资源单文件硬上限
SAFE = 24 * MIB               # 留 1 MiB 余量


def split_file(path: str, chunk_size: int) -> list[str]:
    """把 path 切成多片，返回生成的文件名列表。原文件保留（Worker 不用它）。"""
    base, ext = os.path.splitext(path)
    size = os.path.getsize(path)
    parts = []

    with open(path, "rb") as f:
        idx = 1
        remaining = size
        while remaining > 0:
            take = min(chunk_size, remaining)
            out = f"{base}-part{idx}{ext}"
            with open(out, "wb") as g:
                left = take
                while left > 0:
                    buf = f.read(min(1 * MIB, left))
                    if not buf:
                        print(f"[ERROR] {path} 提前读到末尾，文件可能被改动")
                        return parts
                    g.write(buf)
                    left -= len(buf)
            parts.append(os.path.basename(out))
            print(f"  {os.path.basename(out)}  {take / MIB:.2f} MB")
            remaining -= take
            idx += 1

    # 校验拼接能还原
    total = sum(os.path.getsize(os.path.join(os.path.dirname(path), p)) for p in parts)
    if total != size:
        print(f"[ERROR] 分片总大小 {total} != 原文件 {size}")
        return []

    print(f"  合计 {total / MIB:.2f} MB（原 {size / MIB:.2f} MB）")
    return parts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("web_dir", help="build/web 目录")
    ap.add_argument("--target", default="game.pck", help="要切分的文件名（默认 game.pck）")
    ap.add_argument("--chunk-mib", type=int, default=24,
                    help=f"每片大小 MiB（默认 24，必须 < 25）")
    args = ap.parse_args()

    if args.chunk_mib >= 25:
        print("[ERROR] --chunk-mib 必须 < 25（Cloudflare 单文件上限）")
        return 1

    path = os.path.join(args.web_dir, args.target)
    if not os.path.exists(path):
        print(f"[ERROR] 找不到 {path}")
        return 1

    size = os.path.getsize(path)
    print(f"[split] {args.target}  {size / MIB:.2f} MB  →  每片 ≤ {args.chunk_mib} MiB")

    if size <= LIMIT:
        print(f"[SKIP] {size / MIB:.2f} MB 未超过 25 MiB 上限，不需要切分")
        return 0

    parts = split_file(path, args.chunk_mib * MIB)
    if not parts:
        return 1

    print(f"\n[OK] 切成 {len(parts)} 片：{', '.join(parts)}")
    print("     原文件保留但不上传（Worker 只读分片）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
