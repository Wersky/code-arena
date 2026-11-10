#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""把每个角色的 hair 遮罩按位置切成 5 段 + GPT 从 body 切出翅膀。

核心约束（整个方案的基石）：
    5 段之和 严格等于 原 hair 遮罩
用软权重归一化实现：每个像素按「离各段引力区的软距离」分权重，权重和恒为 1，
所以 sum(seg_i) == hair 逐像素成立，呼吸时不会出现缝隙或双推。

修正记录（2026-11-10 第一版三个错误）：
  1. np.maximum 传三个参数是 numpy 已废弃用法，结果非预期 → 改成两次 np.maximum
  2. 翅膀引力区过大，把 body 整个吃掉 → 收窄到翼膜实际位置
  3. 分段占比读数用了错误口径 → 统一按「该段占原 hair 面积的百分比」统计
"""
import os
import sys

import numpy as np
from PIL import Image

SEL = "assets/art/select"

# ── 5 段的空间引力区（归一化 0~1）──
# 来源：主人四张图上的红框定位。框里还混着脸和衣服，所以这里只是「这段头发在哪」的
# 引力中心，真正的像素由 hair 遮罩本身决定（hair 层已经排除了脸和衣服）。
SEGMENTS = {
    # 引力区按**实测 hair 分布**设计（2026-11-10 第一版失败原因：
    # GPT 的 hair 只在上半 x0.37-0.65，旧区设到 x0.92 完全在头发之外 → 分不到像素）
    "deepseek": {   # hair: x 0.00-0.49, y 0.00-0.99（左侧长卷发铺满全高）
        1: [(0.12, 0.00, 0.36, 0.16)],   # 呆毛 + 头顶
        2: [(0.05, 0.10, 0.30, 0.45)],   # 左侧鬓发
        3: [(0.30, 0.18, 0.49, 0.55)],   # 贴脸那一侧刘海
        4: [(0.00, 0.38, 0.35, 0.76)],   # 背后长垂发
        5: [(0.00, 0.70, 0.40, 1.00)],   # 末端发梢
    },
    "qwen": {       # hair: x 0.42-1.00, y 0.00-0.99（下半更密）
        1: [(0.42, 0.00, 0.75, 0.20)],   # 头顶 + 发饰
        2: [(0.42, 0.15, 0.65, 0.50)],   # 左侧垂发
        3: [(0.62, 0.15, 0.85, 0.50)],   # 右侧垂发
        4: [(0.55, 0.45, 1.00, 0.80)],   # 背后长发主体
        5: [(0.50, 0.75, 1.00, 1.00)],   # 末端发梢
    },
    "gpt": {        # hair: x 0.37-0.65, y 0.00-0.51（只在画面上半，范围很窄）
        1: [(0.37, 0.00, 0.66, 0.15)],   # 头顶
        2: [(0.37, 0.10, 0.51, 0.28)],   # 左侧短垂发
        3: [(0.50, 0.10, 0.66, 0.28)],   # 右侧短垂发
        4: [(0.37, 0.25, 0.66, 0.42)],   # 中段垂发
        5: [(0.37, 0.38, 0.66, 0.52)],   # 发梢（画面中高位置）
    },
    "grok": {       # hair: x 0.17-0.84, y 0.00-0.78（双马尾 + 背后长发）
        1: [(0.30, 0.00, 0.66, 0.15)],   # 头顶
        2: [(0.15, 0.05, 0.36, 0.55)],   # 左双马尾
        3: [(0.50, 0.05, 0.73, 0.55)],   # 右双马尾
        4: [(0.45, 0.36, 0.86, 0.62)],   # 背后长发
        5: [(0.38, 0.58, 0.90, 0.78)],   # 发梢（hair 实际只到 y0.78）
    },
}

SOFT = 0.16          # 软过渡半径
WING_SOFT = 0.07     # 翅膀软过渡（比头发小，避免吃掉周围）


def _box_dist(px, py, rect):
    """点到矩形的归一化距离（矩形内为 0）。分两次 np.maximum，避开已废弃的三参用法。"""
    x1, y1, x2, y2 = rect
    dx = np.maximum(np.maximum(x1 - px, px - x2), 0.0)
    dy = np.maximum(np.maximum(y1 - py, py - y2), 0.0)
    return np.hypot(dx, dy)


def _weights(h, w, rects, soft):
    ys, xs = np.mgrid[0:h, 0:w]
    px = (xs + 0.5) / w
    py = (ys + 0.5) / h
    d = np.full((h, w), 1e9, dtype=np.float32)
    for r in rects:
        d = np.minimum(d, _box_dist(px, py, r)).astype(np.float32)
    return np.exp(-(d / soft) ** 2).astype(np.float32)


def split_hair(cid):
    hp = os.path.join(SEL, f"layer-{cid}-hair.png")
    if not os.path.exists(hp):
        print(f"  [跳过] {cid}: 没有 {hp}")
        return True
    hair = np.array(Image.open(hp).convert("L")).astype(np.float32) / 255.0
    h, w = hair.shape
    hair_area = float((hair > 0.5).sum())
    if hair_area < 100:
        print(f"  [跳过] {cid}: hair 层几乎为空")
        return True

    rects = SEGMENTS[cid]
    # 2026-11-10 第二版修正：先硬归属、再窄边柔化。
    # 第一版用五路高斯归一化，权重被摊薄到没人超过 0.5，等于五段一起轻动、失去分段意义。
    # 现在每个像素明确归给「离哪个段的引力区最近」的那一段，只在等距交界带做窄过渡。
    ys, xs = np.mgrid[0:h, 0:w]
    px = (xs + 0.5) / w
    py = (ys + 0.5) / h
    D = np.stack([np.min(np.stack([_box_dist(px, py, r) for r in rects[i]], axis=0), axis=0)
                  for i in range(1, 6)], axis=0)
    order = np.argsort(D, axis=0)
    d1 = np.take_along_axis(D, order[0:1], axis=0)[0]
    d2 = np.take_along_axis(D, order[1:2], axis=0)[0]
    owner = order[0]
    # 交界带：次近与最近的距离差越小，越接近等距线
    band = np.clip(1.0 - (d2 - d1) / max(SOFT, 1e-6), 0.0, 1.0)
    W = np.zeros((5, h, w), dtype=np.float32)
    for i in range(5):
        W[i] = (owner == i).astype(np.float32) * (1.0 - 0.5 * band)
    # 归一到每像素和为 1（交界带两侧各拿一半，和仍为 1）
    ssum = W.sum(axis=0)
    ssum[ssum < 1e-6] = 1.0
    W = W / ssum

    segs = []
    for i in range(5):
        seg = hair * W[i]
        segs.append(seg)
        Image.fromarray(np.clip(seg * 255.0, 0, 255).astype(np.uint8), "L").save(
            os.path.join(SEL, f"hair5-{cid}-seg{i + 1}.png"))

    # 自证 1：五段和 == 原 hair
    err = float(np.abs(np.sum(segs, axis=0) - hair).max())
    # 自证 2：五段互不重复覆盖（同一像素不该被两段都判成 >0.5）
    strong = np.stack([(s > 0.5) for s in segs], axis=0).sum(axis=0)
    dup = int((strong > 1).sum())
    # 占比：各段「明确属于它」的像素 / 原 hair 像素
    # 自证 3：每段都必须有足够「实体」像素，否则该段视觉上等于没有（第一版踩过）
    # 用能量占比，不用 >0.5 阈值 —— 软权重下像素会被分散，阈值法会误判成 0
    tot = float(hair.sum())
    shares = [float(s_.sum()) / max(tot, 1e-6) * 100.0 for s_ in segs]
    strong = [int((s_ > 0.5).sum()) for s_ in segs]
    thin = [i + 1 for i, v in enumerate(shares) if v < 4.0]
    print(f"  {cid:9s} 和误差={err:.6f} 双覆盖={dup}px")
    print(f"            能量占比 " + "/".join(f"{x:.0f}%" for x in shares)
          + f"  合计={sum(shares):.1f}%")
    print(f"            强实体 px " + "/".join(str(x) for x in strong)
          + (f"  [太薄: seg{thin}]" if thin else ""))
    return err < 1e-5 and dup == 0 and not thin


def split_gpt_wing():
    bp = os.path.join(SEL, "layer-gpt-body.png")
    if not os.path.exists(bp):
        print("  [跳过] GPT 翅膀: 没有 body 遮罩")
        return True
    body = np.array(Image.open(bp).convert("L")).astype(np.float32) / 255.0
    h, w = body.shape
    body_area = float((body > 0.5).sum())
    if body_area < 100:
        print("  [跳过] GPT 翅膀: body 层几乎为空")
        return True

    # 翼膜位置：从 GPT 立绘目检定（左右两片，中间留出躯干不碰）
    wing_rects = [(0.10, 0.30, 0.34, 0.52), (0.66, 0.30, 0.90, 0.54)]
    ww = _weights(h, w, wing_rects, WING_SOFT)
    wing = body * ww
    body2 = body - wing

    Image.fromarray(np.clip(wing * 255.0, 0, 255).astype(np.uint8), "L").save(
        os.path.join(SEL, "layer-gpt-wing.png"))
    Image.fromarray(np.clip(body2 * 255.0, 0, 255).astype(np.uint8), "L").save(
        os.path.join(SEL, "layer-gpt-body2.png"))

    wing_area = float((wing > 0.5).sum())
    b2_area = float((body2 > 0.5).sum())
    dup = int(((wing > 0.5) & (body2 > 0.5)).sum())
    err = float(np.abs(wing + body2 - body).max())
    print(f"  gpt-wing  翅膀={wing_area / body_area * 100:.1f}% of body  "
          f"剩余body={b2_area / body_area * 100:.1f}%  和误差={err:.6f}  双覆盖={dup}px")
    return err < 1e-5 and dup == 0 and wing_area > 100 and b2_area > 100


if __name__ == "__main__":
    ok = True
    for cid in ["deepseek", "qwen", "gpt", "grok"]:
        ok = split_hair(cid) and ok
    ok = split_gpt_wing() and ok
    print("OK" if ok else "有失败项")
    sys.exit(0 if ok else 1)
