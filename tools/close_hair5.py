#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""五段发缕闭合处理：把生图出来的 5 段与 hair 母集对齐，保证严格无缝。

## 为什么需要这一步

生图出来的 5 段是**独立生成**的，它们：
  · 可能互相重叠（两段都覆盖了同一块头发）
  · 可能漏掉一些头发（模型没画到的边缘）
  · 可能画到头发外面（衣服、背景）

如果直接拿去用，呼吸时重叠加倍推、漏掉的地方留静态残影、画到外面的一起动 → 全是破绽。

## 闭合方案（主人要求「必须无缝」）

三步，全部是纯程序，不再花一分钱：

  ① 受限：seg_i ← seg_i × hair        （只保留确实是头发的像素，画到衣服上的全砍掉）
  ② 归一：每个像素按 5 段的相对强度分权重，权重和 = 1
     （重叠的地方自动变成"各占一部分"，不会双推）
  ③ 补漏：hair 里没有被任何一段覆盖到的像素，按**最近段的距离**补给它
     （保证 5 段加起来 = hair，一个像素不漏）

最终数学保证：sum(seg_i) == hair 逐像素成立。

## 输出

  assets/art/select/hair5c-<角色>-seg{1..5}.png   （c = closed，与旧的程序切分产物区分）
"""
import os
import sys

import numpy as np
from PIL import Image

SEL = "assets/art/select"
CIDS = ["deepseek", "gpt", "grok", "qwen"]


def load_l(path):
    return np.array(Image.open(path).convert("L")).astype(np.float32) / 255.0


def close_segments(cid):
    hair_p = os.path.join(SEL, f"layer-{cid}-hair.png")
    if not os.path.exists(hair_p):
        print(f"  [跳过] {cid}: 无 hair 母集")
        return True

    segs = []
    for i in range(1, 6):
        p = os.path.join(SEL, f"hairgen-{cid}-seg{i}.png")
        if not os.path.exists(p):
            print(f"  [跳过] {cid}: 缺 seg{i}")
            return True
        segs.append(load_l(p))

    hair = load_l(hair_p)
    h, w = hair.shape

    # ── ① 受限：只保留落在 hair 内的部分 ──
    clipped = [np.clip(s * hair, 0.0, 1.0) for s in segs]

    # ── ② 归一：每个像素按五段相对强度分权重（和恒为 1）──
    stack = np.stack(clipped, axis=0)                      # (5,h,w)
    tot = stack.sum(axis=0)
    covered = tot > 1e-4
    W = np.zeros_like(stack)
    # 覆盖到的像素：按强度比例分
    np.divide(stack, tot[None, :, :], out=W, where=covered[None, :, :])

    # ── ③ 补漏：hair 里没被任何一段覆盖的，补给最近的段 ──
    # 用「每段的重心距离场」做近似，比自己实现 geodesic 快且够用
    holes = (hair > 0.02) & (~covered)
    n_holes = int(holes.sum())
    if n_holes > 0:
        ys, xs = np.nonzero(holes)
        cys, cxs = [], []
        for i in range(5):
            yy, xx = np.nonzero(W[i] > 0.5)
            if len(yy) == 0:
                cys.append(h / 2.0)
                cxs.append(w / 2.0)
            else:
                cys.append(float(yy.mean()))
                cxs.append(float(xx.mean()))
        # 每个漏掉的像素，归给重心最近的那一段
        cy_arr = np.array(cys, dtype=np.float32)[:, None]
        cx_arr = np.array(cxs, dtype=np.float32)[:, None]
        d = (ys[None, :] - cy_arr) ** 2 + (xs[None, :] - cx_arr) ** 2
        owner = np.argmin(d, axis=0)
        for i in range(5):
            m = owner == i
            if m.any():
                W[i, ys[m], xs[m]] = 1.0

    # ── 落盘 + 自证 ──
    out = W * hair[None, :, :]
    for i in range(5):
        Image.fromarray(np.clip(out[i] * 255.0, 0, 255).astype(np.uint8), "L").save(
            os.path.join(SEL, f"hair5c-{cid}-seg{i + 1}.png"))

    total = out.sum(axis=0)
    err = float(np.abs(total - hair).max())
    # 双覆盖：同一像素被两段都判成 >0.5 的个数（归一化后应恒为 0）
    strong = (out > 0.5).sum(axis=0)
    dup = int((strong > 1).sum())
    # 每段实体量
    solids = [int((out[i] > 0.5).sum()) for i in range(5)]
    shares = [float(out[i].sum()) / max(float(hair.sum()), 1e-6) * 100.0 for i in range(5)]

    print(f"  {cid:9s} 补漏={n_holes:6d}px  和误差={err:.6f}  双覆盖={dup}px")
    print(f"            能量占比 " + "/".join(f"{x:.0f}%" for x in shares)
          + f"  合计={sum(shares):.1f}%")
    print(f"            实体像素 " + "/".join(str(x) for x in solids))
    return err < 1e-5 and dup == 0


def main():
    ok = True
    for cid in CIDS:
        ok = close_segments(cid) and ok
    print("OK" if ok else "有失败项")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
