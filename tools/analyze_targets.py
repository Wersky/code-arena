#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""离线目标分分析器：从平衡模拟落盘的得分矩阵反推目标分。

用法:
    python tools/analyze_targets.py docs/balance_syntax_424242.json [more.json ...]

为什么需要它:
    模拟器一次跑完 10 关，但"每关通过率 / 整局通关率"是**耦合**的
    (整局通关率 = 10 关全部过的概率)。
    想试不同的目标分组合，就不必重跑几十分钟的模拟 —— 得分矩阵落盘后离线算就行。

输出:
    每关的 q01/q05/q08/q10/q20/中位/均值，
    以及"若目标分取 q10"的每关通过率与整局通关率。
"""
import json
import sys
from pathlib import Path

LEVELS = [
    ("L1", 3, 9), ("L2", 4, 11), ("L3", 4, 13), ("L4", 5, 12), ("L5", 5, 13),
    ("L6", 5, 15), ("L7", 5, 17), ("L8", 6, 17), ("L9", 6, 19), ("L10", 6, 21),
]


def quantile(sorted_vals, q):
    """与 balance_sim2.gd 的 _quantile 同口径：线性插值。"""
    if not sorted_vals:
        return 0
    if len(sorted_vals) == 1:
        return float(sorted_vals[0])
    pos = q * (len(sorted_vals) - 1)
    lo = int(pos)
    hi = min(lo + 1, len(sorted_vals) - 1)
    frac = pos - lo
    return sorted_vals[lo] * (1 - frac) + sorted_vals[hi] * frac


def report_targets(per_level, targets, label="候选目标分"):
    """给定目标分列表，算每关通过率与整局通关率。"""
    print("\n  %s: %s" % (label, targets))
    reach = 1.0
    flags = []
    for li, (lid, _t, _b) in enumerate(LEVELS):
        scores = per_level[li]
        tgt = targets[li]
        passed = sum(1 for s in scores if s >= tgt)
        pr = passed / len(scores)
        q05 = quantile(scores, 0.05)
        flag = ""
        if pr < 0.82:
            flag += " 难"
        if pr > 0.98:
            flag += " 易"
        if tgt <= q05:
            flag += " 保过"
        if flag:
            flags.append(lid + flag)
        print("    %-4s 目标=%4d 通过率=%5.1f%%  q05=%4d%s" % (lid, tgt, pr * 100, q05, flag))
        reach *= pr
    print("  整局通关率 = %.1f%%" % (reach * 100))
    mono = all(targets[i] < targets[i + 1] for i in range(len(targets) - 1))
    print("  逐关递增: %s" % ("是" if mono else "**否**"))
    print("  判定: %s" % ("全部 OK" if not flags and mono else "问题：" + ", ".join(flags or ["单调性"])))
    print()
    return reach


def analyze(path, candidate=None):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    rows = data["rows"]
    n = len(rows)
    print("=" * 78)
    print("%s ｜ %d 局 × %d 关" % (Path(path).name, n, len(rows[0])))
    print("=" * 78)

    per_level = []
    for li, (lid, turns, budget) in enumerate(LEVELS):
        scores = sorted(int(r[li]) for r in rows)
        q01 = quantile(scores, 0.01)
        q05 = quantile(scores, 0.05)
        q08 = quantile(scores, 0.08)
        q10 = quantile(scores, 0.10)
        q20 = quantile(scores, 0.20)
        med = quantile(scores, 0.50)
        mean = sum(scores) / len(scores)
        per_level.append(scores)
        print("  %-4s q01=%4d q05=%4d q08=%4d q10=%4d q20=%4d 中位=%4d 均值=%4d"
              % (lid, q01, q05, q08, q10, q20, med, mean))

    # 目标分取 q10 时的每关通过率与整局通关率
    targets = [int(round(quantile(s, 0.10))) for s in per_level]
    report_targets(per_level, targets, "目标分取 q10")
    if candidate:
        report_targets(per_level, candidate, "候选目标分")
    return targets


if __name__ == "__main__":
    args = sys.argv[1:]
    cand = None
    files = []
    for a in args:
        if a.startswith("--targets="):
            cand = [int(x) for x in a[len("--targets="):].split(",") if x.strip()]
        else:
            files.append(a)
    if not files:
        print(__doc__)
        sys.exit(1)
    for p in files:
        analyze(p, cand)
