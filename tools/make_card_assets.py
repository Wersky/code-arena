#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""把 docs/shots/ 的 52 张卡面样张拆成游戏用的两层素材。

样张是 **600×904**，正好是游戏卡面 **150×226 的 4 倍**，所以 ÷4 用最近邻是无损的
（每个 4×4 块还原成 1 个像素），不是"缩图"。

拆成两层（CardView 负责叠成一张牌）：

1. `card-<suit>-<rank>.png` —— **只有角色**，150×226 透明画布，位置与样张完全一致
   （不重新居中：样张的居中是已定稿的版式）。
   处理：纸面内部撒种子做近白洪泛 → 白纸透明；清外圈 6px（卡边框）；
   再按**连通块**摘掉四角角标（不用固定矩形，因为 JQK 的字母会伸进角标区）。
2. `pips-<suit>-<rank>.png` —— **角标层**：150×226 透明画布，四角只留角标块，
   位置与样张像素级一致。CardView 直接 1:1 叠上去，不做任何定位计算
   （样张里右下角标比镜像位置高 3px，是刻意的，按坐标画就会差几像素）。

为什么要按连通块而不是固定矩形：`clubs/J` 的字母 J 会延伸到右下角标区，
固定矩形一清就会把角色切掉一块（实测踩到）。

两层是**互补**的：同一张抠好的图，摘掉角标块 = 角色层，摘掉角色块 = 角标层。
所以两张图叠回去（去掉白纸）和样张逐像素一致。

用法：
    python tools/make_card_assets.py                # 全量 52 张
    python tools/make_card_assets.py --suit spade   # 只做一种花色（调试用）
    python tools/make_card_assets.py --check-only   # 只校验样张，不写文件
"""

import argparse
import os
import sys
from collections import deque

from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SHOTS = os.path.join(PROJECT, "docs", "shots")
DST = os.path.join(PROJECT, "assets", "art")

CARD_W, CARD_H = 150, 226
SCALE = 4                       # 样张 / 卡面
SRC_W, SRC_H = CARD_W * SCALE, CARD_H * SCALE

SUITS = [("spades", "spade"), ("hearts", "heart"),
         ("diamonds", "diamond"), ("clubs", "club")]
RANKS = [("A", 1)] + [("2", 2), ("3", 3), ("4", 4), ("5", 5), ("6", 6), ("7", 7),
                      ("8", 8), ("9", 9), ("10", 10)] + [("J", 11), ("Q", 12), ("K", 13)]

INK_MAX = 200        # "墨色像素"阈值
FRAME_CLEAR = 6      # 卡片墨边 2px + 余量，整圈清掉
MIN_BLOB = 3         # 小于这个面积的碎点直接丢

## 纸面判定：**只认纯白 255**。
## 实测（clubs/5）纸面 = (255,255,255)，而角色的淡紫柔光 = (249,246,250)/(253,253,253)，
## 白身体 = 带蓝紫的浅色。用 238 这种宽松阈值洪泛会顺着柔光漏进身体，把白裙挖穿
## （第一版就这么翻的车，2026-10-22 记进踩坑手册）。
PAPER_MIN = 254

# 角标可能占的最大矩形（卡面坐标系 1x）。样张里所有角标都落在里面：
#   左上实测 (7,9)-(20,42)，"10" 宽到 27、A 高到 39
#   右下实测 (129,180)-(142,213)，"10" 左到 122
# 只有**完全落在窗口内**的连通块才算角标。用窗口而不是"角标区"是因为
# clubs/9、clubs/Q 的角色碎片（翼 / 尾巴）会伸到角上，按区域判断会误判。
TL_WIN = (5, 7, 34, 46)
BR_WIN = (CARD_W - 34, CARD_H - 46, CARD_W - 5, CARD_H - 7)


def inside(box, win):
    return box[0] >= win[0] and box[1] >= win[1] and box[2] <= win[2] and box[3] <= win[3]


def near_white(c):
    """纸面像素：三个通道都 ≥254。柔光最亮到 253，所以不会误吃。"""
    return c[0] >= PAPER_MIN and c[1] >= PAPER_MIN and c[2] >= PAPER_MIN


def is_ink(c):
    return c[3] > 200 and (c[0] < INK_MAX or c[1] < INK_MAX or c[2] < INK_MAX)


def load_card(path):
    im = Image.open(path).convert("RGBA")
    if im.size != (SRC_W, SRC_H):
        raise SystemExit("样张尺寸不对：%s 是 %s，期望 %s"
                         % (path, im.size, (SRC_W, SRC_H)))
    return im.resize((CARD_W, CARD_H), Image.NEAREST)


def cutout_paper(card):
    """抠角色：白纸 → 透明。

    **不能靠颜色**：白发角色的身体本身就是纯白 255，跟纸面同一个色值（实测 clubs/5），
    按"近白"洪泛一定把白裙挖穿（第一版就这么翻的，见踩坑手册）。

    改成按**形状**取轮廓：
      ① 非纸像素（任何通道 <254）当"墨迹"；
      ② 闭运算（先膨胀后收缩）把柔光轮廓上的 1~2px 缺口接起来；
      ③ 从卡外洪泛，**进不去的区域就是角色**（含被包住的白身体）；
      ④ alpha 按轮廓给、颜色用样张原值——白身体恢复成纯白，叠在白纸上无缝。
    """
    src = card.load()
    mask = Image.new("L", (CARD_W, CARD_H), 0)
    mpx = mask.load()
    for y in range(CARD_H):
        for x in range(CARD_W):
            if not near_white(src[x, y]):
                mpx[x, y] = 255
    # 卡边是**闭合的墨线环**，不清掉它的话纸面从卡外洪泛不进去，
    # 整张卡会被当成"角色"连成一块（spades/A 第一版就这么翻的）
    for y in range(CARD_H):
        for x in range(CARD_W):
            if x < FRAME_CLEAR or y < FRAME_CLEAR \
                    or x >= CARD_W - FRAME_CLEAR or y >= CARD_H - FRAME_CLEAR:
                mpx[x, y] = 0
    mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    mpx = mask.load()

    outside = [[False] * CARD_W for _ in range(CARD_H)]
    q = deque()
    for x in range(CARD_W):
        for y in (0, CARD_H - 1):
            if mpx[x, y] == 0 and not outside[y][x]:
                outside[y][x] = True
                q.append((x, y))
    for y in range(CARD_H):
        for x in (0, CARD_W - 1):
            if mpx[x, y] == 0 and not outside[y][x]:
                outside[y][x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < CARD_W and 0 <= ny < CARD_H and not outside[ny][nx] \
                    and mpx[nx, ny] == 0:
                outside[ny][nx] = True
                q.append((nx, ny))

    im = Image.new("RGBA", (CARD_W, CARD_H), (255, 255, 255, 0))
    out = im.load()
    for y in range(CARD_H):
        for x in range(CARD_W):
            if not outside[y][x]:
                out[x, y] = src[x, y]
    return im


def clear_frame(im):
    px = im.load()
    for y in range(CARD_H):
        for x in range(CARD_W):
            if x < FRAME_CLEAR or y < FRAME_CLEAR \
                    or x >= CARD_W - FRAME_CLEAR or y >= CARD_H - FRAME_CLEAR:
                px[x, y] = (255, 255, 255, 0)


def fill_holes(im, orig):
    """补洞：被角色包住、又跟卡外不连通的透明像素，按原图恢复。

    洪泛只认纯白，正常情况下不会漏；这一步是保险——一旦某张卡的柔光和纸面之间
    有开口，身体会被挖出一个洞，这里把它补回去（补的是原图颜色，不是死白）。
    """
    px = im.load()
    opx = orig.load()
    seen = [[False] * CARD_W for _ in range(CARD_H)]
    q = deque()
    for x in range(CARD_W):
        for y in (0, CARD_H - 1):
            if px[x, y][3] == 0 and not seen[y][x]:
                seen[y][x] = True
                q.append((x, y))
    for y in range(CARD_H):
        for x in (0, CARD_W - 1):
            if px[x, y][3] == 0 and not seen[y][x]:
                seen[y][x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < CARD_W and 0 <= ny < CARD_H and not seen[ny][nx] \
                    and px[nx, ny][3] == 0:
                seen[ny][nx] = True
                q.append((nx, ny))
    filled = 0
    for y in range(CARD_H):
        for x in range(CARD_W):
            if px[x, y][3] == 0 and not seen[y][x]:
                px[x, y] = opx[x, y]
                filled += 1
    return filled


def blobs(im):
    """不透明像素的连通块（4 邻接），返回 [{'px': [...], 'box': (l,t,r,b)}]。"""
    px = im.load()
    seen = [[False] * CARD_W for _ in range(CARD_H)]
    out = []
    for y0 in range(CARD_H):
        for x0 in range(CARD_W):
            if seen[y0][x0] or px[x0, y0][3] == 0:
                continue
            q = deque([(x0, y0)])
            seen[y0][x0] = True
            pts = []
            l, t, r, b = x0, y0, x0, y0
            while q:
                x, y = q.popleft()
                pts.append((x, y))
                l, t = min(l, x), min(t, y)
                r, b = max(r, x), max(b, y)
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < CARD_W and 0 <= ny < CARD_H and not seen[ny][nx] \
                            and px[nx, ny][3] != 0:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            out.append({"px": pts, "box": (l, t, r, b)})
    return out


def in_corner(box):
    """块是否是角标：必须整个落在左上 / 右下角标窗口内。"""
    return inside(box, TL_WIN) or inside(box, BR_WIN)


def process(suit_dir, slug, rank_label, rank_num, check_only):
    src = os.path.join(SHOTS, suit_dir, "%s.png" % rank_label)
    if not os.path.exists(src):
        raise SystemExit("缺样张：%s" % src)

    card = load_card(src)
    char = cutout_paper(card)
    clear_frame(char)
    filled = fill_holes(char, card)

    parts = blobs(char)
    marks, keep = [], []
    for p in parts:
        area = len(p["px"])
        if area < MIN_BLOB:
            continue
        if in_corner(p["box"]):
            marks.append(p)
        else:
            keep.append(p)

    tl = [m for m in marks if inside(m["box"], TL_WIN)]
    br = [m for m in marks if inside(m["box"], BR_WIN)]
    if not tl or not br:
        raise SystemExit("%s/%s 角标块识别失败（左上 %d 块 / 右下 %d 块）"
                         % (suit_dir, rank_label, len(tl), len(br)))

    l = min(m["box"][0] for m in tl)
    t = min(m["box"][1] for m in tl)
    r = max(m["box"][2] for m in tl)
    b = max(m["box"][3] for m in tl)
    bl = min(m["box"][0] for m in br)
    bt = min(m["box"][1] for m in br)
    br_r = max(m["box"][2] for m in br)
    bb = max(m["box"][3] for m in br)

    info = {
        "corner_size": (r - l + 1, b - t + 1),
        "tl_box": (l, t, r, b),
        "br_box": (bl, bt, br_r, bb),
        "kept": len(keep),
        "marks": len(marks),
        "filled": filled,
    }

    if check_only:
        return info

    # 两张图互补：角色层摘掉角标块，角标层摘掉角色块
    char_out = char.copy()
    pips_out = char.copy()
    cpx = char_out.load()
    ppx = pips_out.load()
    for m in marks:
        for x, y in m["px"]:
            cpx[x, y] = (255, 255, 255, 0)
    for m in keep:
        for x, y in m["px"]:
            ppx[x, y] = (255, 255, 255, 0)

    char_out.save(os.path.join(DST, "card-%s-%d.png" % (slug, rank_num)))
    pips_out.save(os.path.join(DST, "pips-%s-%d.png" % (slug, rank_num)))
    return info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--suit", default="", help="只处理一种花色：spade/heart/diamond/club")
    ap.add_argument("--check-only", action="store_true", help="只校验样张，不写文件")
    args = ap.parse_args()

    os.makedirs(DST, exist_ok=True)
    targets = [s for s in SUITS if not args.suit or s[1] == args.suit]
    if not targets:
        raise SystemExit("未知花色：%s" % args.suit)

    total, odd = 0, []
    for suit_dir, slug in targets:
        for rank_label, rank_num in RANKS:
            info = process(suit_dir, slug, rank_label, rank_num, args.check_only)
            total += 1
            if info["corner_size"][0] > 28 or info["corner_size"][1] > 40:
                odd.append("%s/%s" % (slug, rank_label))
            print("[ok] %-8s %-2s 角标 %sx%s  左上框=%s  右下框=%s  角色块=%d"
                  % (slug, rank_label, info["corner_size"][0], info["corner_size"][1],
                     info["tl_box"], info["br_box"], info["kept"]))

    print("\n合计 %d 张%s" % (total, "（只校验，未写文件）" if args.check_only else ""))
    if odd:
        print("⚠ 需要注意的 %d 张：%s" % (len(odd), ", ".join(odd)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
