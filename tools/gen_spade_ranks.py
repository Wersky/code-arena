#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""生成黑桃 2~10 / J / Q / K 的卡面角色图（A 已有）。

每个点数用一种**能直接读出数字的手势**：
  2~4  → 竖 2/3/4 根手指
  5    → 一只手张开五指
  6~9  → 五指 + 另一只手竖 1/2/3/4 根
  10   → 两只手都张开（十指）
  J/Q/K→ 抱住一个巨大的字母

角色身份锚：三视图 `dd_glm_sheet`（--ref），保证 13 张是同一个女仆。

用法：
    python tools/gen_spade_ranks.py              # 全部 12 张，并发 2
    python tools/gen_spade_ranks.py --only 8     # 只做某一张
"""

import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

GEN = r"D:\zcode-work\pictures\gen.py"
GEN_OUT = r"D:\zcode-work\pictures\output"
OUT = os.path.join(tempfile.gettempdir(), "spade_ranks_raw")

SHEET = r"D:\zcode-work\pictures\output\2026-10-22-dd_glm_sheet.png"

LOOK = ("a small chibi anime maid with long navy-blue hair fading to bright cyan tips, "
        "big blue eyes, a black-and-white gothic maid outfit: black cat-ear headdress with "
        "white frills, white puff sleeves, black corset, layered black-and-white ruffled skirt, "
        "white gloves, fluffy black-and-white tail, cool tsundere expression")

# 点数 → 手势
POSES = {
    "2": "holding up two fingers of one hand clearly toward the camera",
    "3": "holding up three fingers of one hand clearly toward the camera",
    "4": "holding up four fingers of one hand clearly toward the camera",
    "5": "one hand wide open with all five fingers spread toward the camera",
    "6": "one hand open showing five fingers and the other hand holding up one finger",
    "7": "one hand open showing five fingers and the other hand holding up two fingers",
    "8": "one hand open showing five fingers and the other hand holding up three fingers",
    "9": "one hand open showing five fingers and the other hand holding up four fingers",
    "10": "both hands wide open with all ten fingers spread toward the camera",
    "J": "hugging a huge single capital letter J with both arms, the letter clearly readable",
    "Q": "hugging a huge single capital letter Q with both arms, the letter clearly readable",
    "K": "hugging a huge single capital letter K with both arms, the letter clearly readable",
}

ORDER = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]


def newest(name: str) -> str:
    hits = sorted(glob.glob(os.path.join(GEN_OUT, f"*-{name}.png")),
                  key=os.path.getmtime, reverse=True)
    return hits[0] if hits else ""


def run_one(rank: str) -> tuple:
    name = f"spade_{rank}"
    cmd = [
        sys.executable, GEN,
        "--name", name,
        "--style", "pixel-art",
        "--model", "gpt-image-2.5-1k",
        "--ar", "2:3",
        "--ref", SHEET,
        "--subject", LOOK,
        "--action", POSES[rank],
        "--composition", ("one single SMALL character centered on a plain empty pure white "
                          "background, occupying only the middle of the canvas, huge empty "
                          "margins on all sides, no frame, no border, no stripes"),
        "--environment", "plain flat pure white background, nothing else",
        "--lighting", "soft even light",
        "--materials", ("crisp pixel art, hard pixel clusters, palette of black, white, "
                        "silver and deep navy, no extra text"),
    ]
    for attempt in range(3):
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=600)
        if r.returncode == 0:
            src = newest(name)
            if src:
                shutil.move(src, os.path.join(OUT, f"{name}.png"))
                print(f"[OK]   {name}")
                return (rank, True)
        print(f"  retry {rank} ({attempt + 1}/3)")
    print(f"[FAIL] {name}")
    return (rank, False)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--workers", type=int, default=2)
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    jobs = [r for r in ORDER if not args.only or args.only == r]
    print(f"共 {len(jobs)} 张 → {OUT}（并发 {args.workers}）")
    fails = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for rank, ok in ex.map(run_one, jobs):
            if not ok:
                fails.append(rank)
    print(f"\n完成 {len(jobs) - len(fails)}/{len(jobs)}")
    if fails:
        print("失败：" + ", ".join(fails))


if __name__ == "__main__":
    main()
