#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_spin_frames.py — 8 视角舞蹈转面表 → 游戏用旋转序列帧。

输入: D:/zcode-work/pictures/output/2026-10-23-deepdeek-spin-sheet.png
      （1248x832，一行 8 格，每格 156 宽，品红底）
输出: assets/art/rig/deepdeek-spin/s0.png .. s7.png
      每帧 192x256 画布、统一缩放（全局取最大身高）、脚底对齐、水平居中
打印: 缩放系数与每帧包围盒（对不上就是切格偏了，肉眼可查）
"""
import os

import numpy as np
from PIL import Image

SRC = r"D:/zcode-work/pictures/output/2026-10-23-deepdeek-spin-sheet.png"
ROOT = r"D:/zcode-work/godot/projects/prompt-arena"
OUT = os.path.join(ROOT, "assets", "art", "rig", "deepdeek-spin")
CELLS = 8
CANVAS = (192, 256)
TARGET_H = 240          ## 角色在画布里的目标高度（脚下留 8px 余量）
FEET_PAD = 8

os.makedirs(OUT, exist_ok=True)
im = Image.open(SRC).convert("RGBA")
a = np.asarray(im).astype(np.int16)
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
# 品红底：R/B 高、G 低；边缘抗锯齿像素按距离放宽
magenta = (r > 150) & (b > 150) & (g < 130) & (np.abs(r - b) < 90)
alpha = np.where(magenta, 0, 255).astype(np.uint8)
a[:, :, 3] = alpha
sheet = Image.fromarray(a.astype(np.uint8))

cw = im.width // CELLS
cells = [sheet.crop((i * cw, 0, (i + 1) * cw, im.height)) for i in range(CELLS)]

# 每格只留最大连通块：相邻格的手臂/头发可能越过格线被切进来，必须甩掉
from collections import deque
def keep_largest(cell: Image.Image) -> Image.Image:
    arr = np.asarray(cell).copy()
    solid = arr[:, :, 3] > 8
    h, w = solid.shape
    seen = np.zeros_like(solid, dtype=bool)
    best = []
    ys, xs = np.where(solid)
    for sy, sx in zip(ys, xs):
        if seen[sy, sx]:
            continue
        q = deque([(sy, sx)])
        seen[sy, sx] = True
        comp = []
        while q:
            y, x = q.popleft()
            comp.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and solid[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        if len(comp) > len(best):
            best = comp
    keep = np.zeros_like(solid)
    if best:
        cy = np.array(best)
        keep[cy[:, 0], cy[:, 1]] = True
    dropped = int(solid.sum()) - len(best)
    arr[:, :, 3] = np.where(keep, arr[:, :, 3], 0)
    print(f"  连通块过滤：保留 {len(best)} px，丢弃 {dropped} px")
    return Image.fromarray(arr)

cells = [keep_largest(c) for c in cells]
bbs = [c.getbbox() for c in cells]
print("每格包围盒:", bbs)
if any(bb is None for bb in bbs):
    raise SystemExit("有空格子，切格或抠色失败")

max_h = max(bb[3] - bb[1] for bb in bbs)
scale = TARGET_H / max_h
print(f"统一缩放: {scale:.4f}（最高 {max_h}px → {TARGET_H}px）")

for i, (cell, bb) in enumerate(zip(cells, bbs)):
    crop = cell.crop(bb)
    w2 = max(1, round(crop.width * scale))
    h2 = max(1, round(crop.height * scale))
    im2 = crop.resize((w2, h2), Image.BOX)
    al = im2.getchannel("A").point(lambda v: 255 if v >= 110 else 0)
    im2.putalpha(al)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    x = (CANVAS[0] - w2) // 2
    y = CANVAS[1] - FEET_PAD - h2
    canvas.paste(im2, (x, y), im2)
    canvas.save(os.path.join(OUT, f"s{i}.png"))
    print(f"s{i}.png  {w2}x{h2}  → canvas ({x},{y})")

# 横排预览
pv = Image.new("RGB", (CANVAS[0] * CELLS, CANVAS[1]), (16, 20, 31))
for i in range(CELLS):
    f = Image.open(os.path.join(OUT, f"s{i}.png"))
    pv.paste(f, (i * CANVAS[0], 0), f)
pv.resize((CANVAS[0] * CELLS // 2, CANVAS[1] // 2), Image.NEAREST).save(r"D:/tmp/spin-frames-preview.png")
print("预览: D:/tmp/spin-frames-preview.png")
