#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""按点数生成某个花色的卡面角色图（A 之外的 12 张）。

每个点数用一种能直接读出数字的手势：
  2~4  竖 2/3/4 根手指；5 一只手张开五指
  6~9  五指 + 另一只手竖 1/2/3/4 根
  10   两只手都张开
  J/Q/K 抱住一个巨大的字母

用法：
    python tools/gen_rank_arts.py --suit heart --sheet <设定图.png> --look "<角色描写>" --out heart
"""

import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

GEN = r"D:\zcode-work\pictures\gen.py"
GEN_OUT = r"D:\zcode-work\pictures\output"

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


def newest(name, since=0.0):
    """只接受 since 之后生成的文件——否则会拿上一次的旧图冒充本次结果。"""
    hits = sorted(glob.glob(os.path.join(GEN_OUT, "*-%s.png" % name)),
                  key=os.path.getmtime, reverse=True)
    for h in hits:
        if os.path.getmtime(h) >= since:
            return h
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--suit", required=True)
    ap.add_argument("--sheet", required=True)
    ap.add_argument("--look", required=True)
    ap.add_argument("--out", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--workers", type=int, default=2)
    args = ap.parse_args()

    out_dir = os.path.join(tempfile.gettempdir(), "%s_ranks_raw" % (args.out or args.suit))
    os.makedirs(out_dir, exist_ok=True)
    jobs = [r for r in ORDER if not args.only or args.only == r]
    print("共 %d 张 → %s（并发 %d）" % (len(jobs), out_dir, args.workers))

    def run_one(rank):
        name = "%s_%s" % (args.suit, rank)
        cmd = [
            sys.executable, GEN,
            "--name", name,
            "--style", "pixel-art",
            "--model", "gpt-image-2.5-1k",
            "--ar", "2:3",
            "--ref", args.sheet,
            "--subject", args.look,
            "--action", POSES[rank],
            "--composition", ("one single SMALL character centered on a plain empty pure "
                              "white background, occupying only the middle of the canvas, "
                              "huge empty margins on all sides, no frame, no border, no stripes"),
            "--environment", "plain flat pure white background, nothing else",
            "--lighting", "soft even light",
            "--materials", ("crisp pixel art, hard pixel clusters, no extra text"),
        ]
        for attempt in range(3):
            started = time.time() - 1.0
            r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                               errors="replace", timeout=600)
            if r.returncode == 0:
                src = newest(name, started)
                if src:
                    shutil.move(src, os.path.join(out_dir, "%s.png" % rank))
                    print("[OK]   %s_%s" % (args.suit, rank))
                    return (rank, True)
            print("  retry %s (%d/3)" % (rank, attempt + 1))
        print("[FAIL] %s_%s" % (args.suit, rank))
        return (rank, False)

    fails = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for rank, ok in ex.map(run_one, jobs):
            if not ok:
                fails.append(rank)
    print("\n完成 %d/%d" % (len(jobs) - len(fails), len(jobs)))
    if fails:
        print("失败：" + ", ".join(fails))


if __name__ == "__main__":
    main()
