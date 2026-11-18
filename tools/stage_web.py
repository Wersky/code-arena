# -*- coding: utf-8 -*-
"""把 Web 构建产物整理成"可部署目录"：只放分片，不放大原文件。

为什么需要（2026-11-18 实测）：
    Workers 静态资源绑定 [assets] 会把 directory 下的**所有**文件上传，
    遇到 >25 MiB 的文件直接 ERROR Asset too large 整个 deploy 失败。
    而 build/web 里的 game.pck / game.wasm 是原始大文件（44/37 MB），
    分片 game-part1/p2 才是真正要上桌的。

做法：
    build/web            ← Godot 导出（含原始大文件 + 分片）
    worker/public        ← 只有能上传的文件（分片 + html/js/图标）
    wrangler.toml 的 [assets] directory 指向 worker/public

用法：
    python tools/stage_web.py
退出码：0=成功
"""

import os
import shutil
import sys

SRC = os.path.join("build", "web")
DST = os.path.join("worker", "public")

# 超过 Workers 单文件上限、必须靠分片提供的原始文件（不上传）
SKIP_EXACT = {"game.pck", "game.wasm"}
MIB = 1024 * 1024
LIMIT = 25 * MIB


def main() -> int:
    if not os.path.isdir(SRC):
        print(f"[ERROR] 找不到 {SRC}，先导出 Web 版：tools\\export_web.bat")
        return 1

    if os.path.isdir(DST):
        shutil.rmtree(DST)
    os.makedirs(DST, exist_ok=True)

    copied, skipped = [], []
    for name in sorted(os.listdir(SRC)):
        src = os.path.join(SRC, name)
        if not os.path.isfile(src):
            continue
        if name in SKIP_EXACT:
            skipped.append((name, os.path.getsize(src)))
            continue
        size = os.path.getsize(src)
        if size > LIMIT:
            skipped.append((name, size))
            print(f"  [SKIP] {name}  {size / MIB:.2f} MB 超过 25 MiB，且没有对应分片！")
            continue
        shutil.copy2(src, os.path.join(DST, name))
        copied.append((name, size))

    print(f"\n[1/2] 复制 {len(copied)} 个文件到 {DST}/")
    for n, s in copied:
        print(f"       {s / 1024:9.1f} KB  {n}")

    if skipped:
        print(f"\n[2/2] 跳过 {len(skipped)} 个原始大文件（用分片代替）：")
        for n, s in skipped:
            print(f"       {s / MIB:6.2f} MB  {n}")

    # 校验分片齐全
    need = {
        "game.pck": ["game-part1.pck", "game-part2.pck"],
        "game.wasm": ["game-part1.wasm", "game-part2.wasm"],
    }
    missing = []
    for logical, parts in need.items():
        for p in parts:
            if not os.path.isfile(os.path.join(DST, p)):
                missing.append(p)
    if missing:
        print(f"\n[ERROR] 缺少分片：{', '.join(missing)}")
        print("        先跑：python tools\\split_pck.py build/web --target game.pck")
        print("              python tools\\split_pck.py build/web --target game.wasm")
        return 1

    total = sum(s for _, s in copied)
    print(f"\n[OK] 部署目录就绪：{len(copied)} 个文件，共 {total / MIB:.2f} MB")
    print(f"     下一步：cd worker && wrangler deploy")
    return 0


if __name__ == "__main__":
    sys.exit(main())
