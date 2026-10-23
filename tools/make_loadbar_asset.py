#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_loadbar_asset.py — 把生图的进度条加工成游戏资产。

输入:  D:/zcode-work/pictures/output/2026-10-23-ui-loadbar-v1.png（1248x832，
       背景是被烘进图里的棋盘格假透明）
输出:  assets/art/ui/loadbar-track.png（×2 显示，NEAREST 整数降采样）
打印:  画布尺寸、棋盘格剔除数、内槽（fill inset）边距——照抄进 load_bar.gd
"""
import os

import numpy as np
from PIL import Image

SRC = r"D:/zcode-work/pictures/output/2026-10-23-ui-loadbar-v1.png"
ROOT = r"D:/zcode-work/godot/projects/prompt-arena"
DST = os.path.join(ROOT, "assets", "art", "ui", "loadbar-track.png")
DISPLAY_SCALE = 2

im = Image.open(SRC).convert("RGBA")
a = np.asarray(im).astype(np.int16)
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]

# ── 棋盘格剔除：两种浅灰方格都是 r≈g≈b 的高亮灰；条上没有中性灰
#    （青/紫/深蓝都有明显色偏，淡薄荷高光 #D8FBFF 的 r-g=35 不会被误伤）──
gray = (np.abs(r - g) < 7) & (np.abs(g - b) < 7) & (r > 185)
alpha = a[:, :, 3].copy()
alpha[gray] = 0
print(f"棋盘格剔除 {int(gray.sum())} px")
a[:, :, 3] = alpha

# ── 只留最大连通块（甩掉噪点/残渣）──
from collections import deque
solid = alpha > 8
seen = np.zeros_like(solid, dtype=bool)
best = []
Hh, Ww = solid.shape
ys0, xs0 = np.where(solid)
for sy, sx in zip(ys0, xs0):
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
            if 0 <= ny < Hh and 0 <= nx < Ww and solid[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    if len(comp) > len(best):
        best = comp
keep = np.zeros_like(solid)
if best:
    cy = np.array(best)
    keep[cy[:, 0], cy[:, 1]] = True
print(f"连通块: 最大 {len(best)} px，总实心 {int(solid.sum())} px，丢弃 {int(solid.sum()) - len(best)} px")
alpha = alpha * keep.astype(np.uint8) * 255 // 255 * keep  # 仅保留最大块
alpha[~keep] = 0
a[:, :, 3] = alpha

out = Image.fromarray(a.astype(np.uint8))
bb = out.getbbox()
out = out.crop(bb)
w, h = out.size
print(f"裁剪后包围盒: {w}x{h}")

# ── 整数 NEAREST 降采样：因子 3（美术像素 ~5-6px 源，÷3 后 1-2px）──
FACTOR = 3
nw, nh = w // FACTOR, h // FACTOR
out = out.resize((nw, nh), Image.NEAREST)
# alpha 硬化
al = out.getchannel("A").point(lambda v: 255 if v >= 110 else 0)
out.putalpha(al)
os.makedirs(os.path.dirname(DST), exist_ok=True)
out.save(DST)
print(f"资产: {nw}x{nh} → 游戏内 {nw*DISPLAY_SCALE}x{nh*DISPLAY_SCALE}（×{DISPLAY_SCALE} 显示）")

# ── 量内槽：扫中间一行，从左/右找「深蓝内槽」的起止（rim 是亮青，内槽是暗蓝）──
mid = np.asarray(out)[:, nh // 2, :3].astype(np.int16)
dark = (mid[:, 0] < 90) & (mid[:, 2] > 40)   # 深蓝：r 低 b 中高
xs = np.where(dark)[0]
inset_l, inset_r = (int(xs.min()), int(nw - 1 - xs.max())) if len(xs) else (0, 0)
# 上下：扫中间一列
midc = np.asarray(out)[:, nw // 2, :3].astype(np.int16)
darkc = (midc[:, 0] < 90) & (midc[:, 2] > 40)
ys = np.where(darkc)[0]
inset_t, inset_b = (int(ys.min()), int(nh - 1 - ys.max())) if len(ys) else (0, 0)
print(f"内槽 inset（资产 px，×2 = 显示 px）: 左{inset_l} 右{inset_r} 上{inset_t} 下{inset_b}")
print(f"  → 显示: 左{inset_l*DISPLAY_SCALE} 右{inset_r*DISPLAY_SCALE} 上{inset_t*DISPLAY_SCALE} 下{inset_b*DISPLAY_SCALE}")

# 预览
pv = Image.new("RGB", (nw * 3, nh * 3), (16, 20, 31))
big = out.resize((nw * 3, nh * 3), Image.NEAREST)
pv.paste(big, (0, 0), big)
pv.save(r"D:/tmp/loadbar-asset-preview.png")
print("预览: D:/tmp/loadbar-asset-preview.png")
