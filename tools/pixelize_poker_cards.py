#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""把 16 张扑克卡面原图后处理成像素画，落到 assets/art/poker-*.png。

思路照搬 pixelize_meme_cards.py（三步）：
  1. 面积平均缩到 75×113 像素网格（消锯齿、保留细节）
  2. 量化到 32 色调色板（逼出手绘色阶）
  3. 最近邻 ×2 放大回 150×226（硬边像素块，不糊）

输出 RGB 不透明，保证满幅铺满卡面时没有透明缝。

用法：
    python pixelize_poker_cards.py
    python pixelize_poker_cards.py --only deepdeek
"""

import argparse
import os
import tempfile

from PIL import Image

SRC = os.path.join(tempfile.gettempdir(), "poker_arena_raw")
DST = r"D:\zcode-work\godot\projects\prompt-arena\assets\art"

GRID = (75, 113)
UP = 2
PALETTE = 32

AIS = ["deepdeek", "kweno", "chatppt", "grock"]
SUITS = ["heart", "diamond", "spade", "club"]


def pixelize(path: str, out_path: str) -> None:
    im = Image.open(path).convert("RGB")
    im = im.resize(GRID, Image.LANCZOS)
    im = im.quantize(colors=PALETTE, method=Image.MEDIANCUT).convert("RGB")
    im = im.resize((GRID[0] * UP, GRID[1] * UP), Image.NEAREST)
    im.save(out_path)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    args = ap.parse_args()

    os.makedirs(DST, exist_ok=True)
    done = 0
    missing = []
    for ai in AIS:
        if args.only and args.only != ai:
            continue
        for suit in SUITS:
            src = os.path.join(SRC, f"{ai}-{suit}.png")
            if not os.path.exists(src):
                missing.append(f"{ai}-{suit}")
                continue
            out = os.path.join(DST, f"poker-{ai}-{suit}.png")
            pixelize(src, out)
            print(f"[ok] {out}")
            done += 1
    print(f"\n完成 {done} 张")
    if missing:
        print("缺原图：" + ", ".join(missing))


if __name__ == "__main__":
    main()
