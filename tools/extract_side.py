#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""extract_side.py — 从三视图设定图里抠出「侧面」角色（v2）。

v2 修正：
  * 白底去除改为「从画布边缘泛洪」——只删与外界连通的近白像素，
    角色内部的白色（帽纱/围裙/脸部高光）保留；
  * 鞋下的地面椭圆阴影按「灰蓝 + 贴地」特征剔除；
  * 只保留最大连通块（甩掉文字碎片）。

输出:  .tmp/siderig/side-raw.png   透明底整身（紧包围盒）
       .tmp/siderig/side-grid.png  20px 网格调参图
       .tmp/siderig/side-rows.png  行墨水剖面
"""
import os
from collections import deque

import numpy as np
from PIL import Image

SRC = "D:/zcode-work/companion/gallery/蓝白鲸纹女仆像素角色设定图.png"
OUT = "D:/zcode-work/godot/projects/prompt-arena/.tmp/siderig"
os.makedirs(OUT, exist_ok=True)

im = Image.open(SRC).convert("RGB")
W, H = im.size
a = np.asarray(im).astype(np.int16)

# 近白 = 背景候选（角色内部白也在此列，但泛洪只从边缘进）
near_white = (a[:, :, 0] > 232) & (a[:, :, 1] > 232) & (a[:, :, 2] > 232)

bg = np.zeros((H, W), dtype=bool)
q = deque()
for x in range(W):
    for y in (0, H - 1):
        if near_white[y, x] and not bg[y, x]:
            bg[y, x] = True
            q.append((y, x))
for y in range(H):
    for x in (0, W - 1):
        if near_white[y, x] and not bg[y, x]:
            bg[y, x] = True
            q.append((y, x))
while q:
    y, x = q.popleft()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ny, nx = y + dy, x + dx
        if 0 <= ny < H and 0 <= nx < W and near_white[ny, nx] and not bg[ny, nx]:
            bg[ny, nx] = True
            q.append((ny, nx))

char = ~bg  # 角色 = 非背景（内部白保留）

# ── 剔除地面阴影：灰蓝、低饱和、中高亮度，且在画面下沿 ──
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
mx = a.max(axis=2)
mn = a.min(axis=2)
sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
shadow_like = (b > r) & (b - r < 60) & (r > 150) & (r < 235) & (sat < 0.16)
shadow_like &= char
# 只在「鞋底以下及附近」生效：找每列的最低墨水行，向下 14px 内的 shadow_like 删掉
col_ink = char
bottom = np.full(W, -1)
for x in range(W):
    ys = np.where(col_ink[:, x])[0]
    if len(ys):
        bottom[x] = ys.max()
for x in range(W):
    if bottom[x] < 0:
        continue
    lo = max(0, bottom[x] - 6)
    hi = min(H, bottom[x] + 15)
    zone = slice(lo, hi)
    char[zone, x] &= ~shadow_like[zone, x]

# ── 侧窗内取最大连通块，甩掉文字碎片 ──
## 窗口右界必须是 685：侧面垂发实际延伸到 x≈670，之前用 620 把背侧切出了直边缺口；
## 680..700 是侧面与背面两图之间的空白间隙
x0w, x1w = 360, 685
win = char[:, x0w:x1w]
seen = np.zeros_like(win, dtype=bool)
best = None
ys, xs = np.where(win)
for sy, sx in zip(ys, xs):
    if seen[sy, sx]:
        continue
    qq = deque([(sy, sx)])
    seen[sy, sx] = True
    comp = []
    while qq:
        y, x = qq.popleft()
        comp.append((y, x))
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < win.shape[0] and 0 <= nx < win.shape[1] \
                    and win[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                qq.append((ny, nx))
    if best is None or len(comp) > len(best):
        best = comp

comp = np.array(best)
cy, cx = comp[:, 0], comp[:, 1]
by0, by1 = cy.min(), cy.max() + 1
bx0, bx1 = cx.min() + x0w, cx.max() + 1 + x0w
print(f"侧面包围盒: x {bx0}..{bx1}, y {by0}..{by1}  （{bx1-bx0}x{by1-by0}）")

rgba = np.zeros((H, W, 4), dtype=np.uint8)
rgba[:, :, :3] = a
rgba[:, :, 3] = char.astype(np.uint8) * 255
out = rgba[by0:by1, bx0:bx1]
# 边缘去毛刺：alpha 硬阈值
out[out[:, :, 3] < 128, 3] = 0
out[out[:, :, 3] >= 128, 3] = 255
Image.fromarray(out).save(f"{OUT}/side-raw.png")
print(f"已存 side-raw.png {out.shape[1]}x{out.shape[0]}")

# 调参图
gimg = out.copy()
gh, gw = gimg.shape[:2]
for gy in range(0, gh, 20):
    gimg[gy, :, 0] = 255
for gx in range(0, gw, 20):
    gimg[:, gx, 0] = 255
Image.fromarray(gimg).save(f"{OUT}/side-grid.png")
ink = (out[:, :, 3] > 0).sum(axis=1)
prof = np.zeros((gh, 70, 4), dtype=np.uint8)
prof[:, :, :3] = 30
mxv = max(int(ink.max()), 1)
for y in range(gh):
    wpx = int(ink[y] / mxv * 66)
    prof[y, 2:2 + wpx, :3] = (120, 200, 255)
    prof[y, 2:2 + wpx, 3] = 255
    # 每 20 行标个刻度
    if y % 40 == 0:
        prof[y, :2, :3] = (255, 80, 80)
        prof[y, :2, 3] = 255
Image.fromarray(prof).save(f"{OUT}/side-rows.png")
print("已存 side-grid.png / side-rows.png")
