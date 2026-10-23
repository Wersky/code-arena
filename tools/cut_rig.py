#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cut_rig.py — 把一张带背景的 Q 版像素立绘拆成可动画的部件（可重跑）。

用法（在项目根目录）：
    python tools/cut_rig.py

输入：
    assets/art/ai-deepdeek.png        # 192x256，带深蓝星空背景
输出：
    assets/art/rig/deepdeek/cutout.png        # 192x256 透明底整幅
    assets/art/rig/deepdeek/parts/*.png      # 每个部件都是 192x256 整幅透明图
    assets/art/rig/deepdeek/composite.png    # 部件按原坐标叠回
    assets/art/rig/deepdeek/parts-debug.png  # 各部件染色 + 错开
    assets/art/rig/deepdeek/rig.json         # canvas / parts / pivot / z

流程：
    1) 自动识别“逻辑像素”放大倍数（本图是 48x64 的 4 倍最近邻放大）。
    2) 抠背景：32 色调色板里背景是纯蓝族（R≈0），角色带红分量（R>=19）。
       用 R 通道直方图最大空隙自动定阈值，不写死颜色。
    3) 取最大连通块 = 角色，填掉被角色包围的背景洞（防止把裙子挖穿）。
    4) 清星云残条：与画布边框同色、且本身是 1 逻辑像素高的水平薄片 → 判为背景。
    5) 硬边 alpha（0/255），按原倍数放大回 192x256。
    6) 切件：head / torso / arm_l / arm_r / leg_l / leg_r / skirt / tail，全部整幅输出。
    7) 自证：叠回 composite 与原 cutout 逐像素比对；另出 parts-debug。
"""

import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "assets", "art", "ai-deepdeek.png")
OUTDIR = os.path.join(ROOT, "assets", "art", "rig", "deepdeek")
PARTSDIR = os.path.join(OUTDIR, "parts")

# ---------------------------------------------------------------------------
# 切件地标（单位：逻辑像素，坐标系 48x64，y 向下）
# 语义：*_CORE 是"只属于该部件"的区域，用来从 torso 里挖掉；
#       *_PAINT 是该部件实际输出的范围，比 core 多 1~2 像素，故意和 torso 重叠，
#       这样部件旋转时不会在接缝处露洞（重叠像素颜色本来就一样，叠合后无差异）。
HEAD_BOTTOM = 17      # 头 core: y<=17（头/兜帽本体，脖子线在 y=18）
HEAD_PAINT_BOTTOM = 19  # 头输出: y<=19，向下多带 2 行衣领，头和躯干在脖子处重叠
ARM_TOP = 18          # 肩线
ARM_BOTTOM = 37       # 腰线
ARM_L_CORE_X = 12     # 左臂 core: x<=12
ARM_L_PAINT_X = 14    # 左臂输出: x<=14（向躯干内多 2 列）
ARM_R_CORE_X = 32     # 右臂 core: 32<=x<=37（x>=38 是尾鳍，归躯干）
ARM_R_PAINT_X = 30
ARM_R_MAX_X = 37
LEG_TOP = 55          # 腿输出 y>=55（与躯干重叠 1 行）
LEG_CORE_TOP = 56     # 腿 core y>=56
LEG_X_MIN = 17
LEG_X_MAX = 26
LEG_SPLIT_X = 22      # x<=22 左腿，x>=23 右腿

# 裙摆：胯线以下、腿部以上的整块三角裙体。
# torso 一直管到 SKIRT_PAINT_TOP-1，裙摆从 SKIRT_PAINT_TOP 起也有像素 —— 这 6 行是
# 故意和 torso 重复的重叠区，旋转时腰缝不会露洞。可见分界落在 SKIRT_CORE_TOP。
SKIRT_CORE_TOP = 40
SKIRT_PAINT_TOP = 34
SKIRT_CORE_BOTTOM = 55   # 55 是裙摆下沿，56 起是腿

# 鲸鱼尾：右侧翘起来那根，尖在 (43,24)，根部在 y38-42 才和裙体合并。
# 躯干右缘在 y22-37 一带有起伏（最右到 x35），所以 x 起点按行给，避免把躯干右缘切走。
TAIL_BOTTOM = 42
TAIL_XT = [  # (y_start, y_end, x_min)
    (22, 28, 36),
    (29, 32, 33),
    (33, 37, 35),
    (38, 42, 36),
]
TAIL_GROW = 2         # 根部向外膨胀 2 逻辑像素，与 torso/skirt 形成重叠区

HOLE_MAX_AREA = 3     # 只填 <=3 px 的封闭抖动洞，透空缝不填
NEBULA_BAND_Y = 55    # 裙摆以下：该区域的星云色小横条一律当背景清掉

# pivot：该部件绕之旋转的画布像素坐标（192x256 坐标系）
# z 从下往上：tail 0 < 腿 1 < skirt 2 < torso 3 < 臂 4 < 头 5
RIG = {
    "canvas": [192, 256],
    "parts": {
        "tail":  {"pivot": [154, 160], "z": 0},
        "leg_l": {"pivot": [82, 224],  "z": 1},
        "leg_r": {"pivot": [98, 224],  "z": 1},
        "skirt": {"pivot": [96, 152],  "z": 2},
        "torso": {"pivot": [96, 216],  "z": 3},
        "arm_l": {"pivot": [52, 76],   "z": 4},
        "arm_r": {"pivot": [128, 76],  "z": 4},
        "head":  {"pivot": [96, 72],   "z": 5},
    },
}
DEBUG_COLORS = {
    "head":  (255, 64, 64),
    "torso": (64, 160, 255),
    "arm_l": (255, 208, 0),
    "arm_r": (255, 120, 0),
    "leg_l": (64, 224, 96),
    "leg_r": (0, 200, 200),
    "skirt": (170, 90, 255),
    "tail":  (255, 90, 200),
}


# ---------------------------------------------------------------------------
def detect_scale(rgb):
    """若图像是整数倍最近邻放大，返回倍数（1 表示原生）。"""
    h, w, _ = rgb.shape
    for s in (8, 6, 5, 4, 3, 2):
        if h % s or w % s:
            continue
        blocks = rgb.reshape(h // s, s, w // s, s, 3)
        if np.all(blocks == blocks[:, :1, :, :1, :]):
            return s
    return 1


def downscale(rgb, s):
    return rgb[::s, ::s]


def bg_threshold(rgb):
    """背景判据：纯蓝族，红分量相对蓝分量极低。

    用 r = R / (B+1) 的升序分布，取**第一个**足够大的空隙做分界。
    本图背景 r <= 0.022，角色 r >= 0.126，空隙 0.104；再往后的空隙是角色内部明暗差，
    所以要取“第一个”，不能取“最大”。
    """
    r = rgb[:, :, 0].astype(float)
    b = rgb[:, :, 2].astype(float)
    ratio = r / (b + 1.0)
    vals = np.unique(np.round(ratio, 4))
    vals = vals[vals <= 0.75]
    for i in range(len(vals) - 1):
        if vals[i + 1] - vals[i] >= 0.05:
            return float((vals[i] + vals[i + 1]) / 2)
    return 0.10


def largest_component(mask, conn8=True):
    """取最大连通块。

    用 8 邻接：像素风描边常见 1px 斜线（本图帽檐左上角 (16,2)/(15,3)），
    4 邻接会把这种斜线切成孤立小点丢掉，导致轮廓出现缺口。
    """
    h, w = mask.shape
    nb = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    if conn8:
        nb += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    lab = np.full((h, w), -1, int)
    best, best_n = -1, 0
    cur = 0
    for y0 in range(h):
        for x0 in range(w):
            if not mask[y0, x0] or lab[y0, x0] >= 0:
                continue
            q = deque([(y0, x0)])
            lab[y0, x0] = cur
            n = 0
            while q:
                cy, cx = q.popleft()
                n += 1
                for dy, dx in nb:
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and lab[ny, nx] < 0:
                        lab[ny, nx] = cur
                        q.append((ny, nx))
            if n > best_n:
                best_n, best = n, cur
            cur += 1
    return lab == best, cur, best_n


def fill_holes(mask, max_area=3):
    """填掉被角色包住的背景小洞。

    只填面积极小的抖动人眼孔（本图 <= 3 px）：裙摆/披风被挖穿的典型表现就是这种
    1~2 px 的暗点。面积极大的封闭区域是「透空缝」（例如两条腿之间那条 1px 宽、
    5px 高的缝），那本来就该透出背景，不能填，否则两条腿会被糊成一坨。
    """
    h, w = mask.shape
    outside = ~mask
    lab = np.full((h, w), -1, int)
    areas = {}
    cur = 0
    for y0 in range(h):
        for x0 in range(w):
            if not outside[y0, x0] or lab[y0, x0] >= 0:
                continue
            q = deque([(y0, x0)])
            lab[y0, x0] = cur
            n = 0
            touch_border = False
            while q:
                cy, cx = q.popleft()
                n += 1
                if cy in (0, h - 1) or cx in (0, w - 1):
                    touch_border = True
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and outside[ny, nx] and lab[ny, nx] < 0:
                        lab[ny, nx] = cur
                        q.append((ny, nx))
            areas[cur] = (n, touch_border)
            cur += 1

    holes = np.zeros((h, w), bool)
    for k, (n, touch) in areas.items():
        if not touch and n <= max_area:
            holes |= (lab == k)
    out = mask | holes
    return out, int(holes.sum()), holes, len(areas)


def recolor_holes(mask, rgb, holes):
    """洞内像素没有原色，取最近的前景像素颜色补上。"""
    if not holes.any():
        return rgb
    out = rgb.copy()
    h, w = mask.shape
    ys, xs = np.nonzero(holes)
    for y, x in zip(ys, xs):
        found = False
        for d in range(1, max(h, w)):
            for ny, nx in ((y, x - d), (y, x + d)):
                if 0 <= nx < w and mask[ny, nx]:
                    out[y, x] = rgb[ny, nx]
                    found = True
                    break
            if found:
                break
            for ny, nx in ((y - d, x), (y + d, x)):
                if 0 <= ny < h and mask[ny, nx]:
                    out[y, x] = rgb[ny, nx]
                    found = True
                    break
            if found:
                break
    return out


def nebula_color_set(rgb):
    """与画布边框同色、且本身属于前景色谱的颜色 = 星云/星星调色。"""
    border = np.concatenate([
        rgb[0, :], rgb[-1, :], rgb[:, 0], rgb[:, -1],
    ])
    return {tuple(map(int, c)) for c in border}


def remove_nebula_whiskers(mask, rgb, nebula, band_y=None):
    """清掉星云残条（背景里那些 1 逻辑像素高的浅蓝小横条）。

    判据：一段"连续同色（星云调色）"的水平游程，满足下面任一条件就整段删掉
      A) 整段都是 1px 高的薄片（上下都是背景）；
      B) 位于 band_y 以下（裙摆以下只可能是腿，那里出现的星云色小横条一律是背景）。
    条件 A 用"整段"而不是"任一像素"，是为了不误伤角色轮廓上 1px 宽的斜描边
    （例如左侧发梢 y=31 的那一小段）。

    画布底边视为"非背景"，避免把脚底/腿尖当薄片误删。
    """
    h, w = mask.shape
    up = np.zeros_like(mask)
    dn = np.zeros_like(mask)
    up[1:] = mask[:-1]
    dn[:-1] = mask[1:]
    dn[h - 1] = True
    thin = mask & ~up & ~dn

    key = (rgb[:, :, 0].astype(int) * 65536 + rgb[:, :, 1].astype(int) * 256
           + rgb[:, :, 2].astype(int))
    neb_key = {r * 65536 + g * 256 + b for (r, g, b) in nebula}

    removed = np.zeros_like(mask)
    for y in range(h):
        x = 0
        while x < w:
            if mask[y, x] and key[y, x] in neb_key:
                s = x
                while x + 1 < w and mask[y, x + 1] and key[y, x + 1] == key[y, s]:
                    x += 1
                run = slice(s, x + 1)
                length = x + 1 - s
                cond_a = thin[y, run].all()
                cond_b = (band_y is not None and y >= band_y
                          and length >= 2 and thin[y, run].any())
                if (cond_a and length >= 2) or cond_b:
                    removed[y, run] = True
            x += 1
    return mask & ~removed, int(removed.sum())


def dilate(m, r):
    """方形膨胀 r 像素（用于给部件做出接缝重叠区）。"""
    if r <= 0:
        return m.copy()
    pad = np.zeros((m.shape[0] + 2 * r, m.shape[1] + 2 * r), bool)
    pad[r:r + m.shape[0], r:r + m.shape[1]] = m
    out = np.zeros_like(m)
    h, w = m.shape
    for dy in range(2 * r + 1):
        for dx in range(2 * r + 1):
            out |= pad[dy:dy + h, dx:dx + w]
    return out


def build_parts(mask):
    """按地标把掩码切成六个部件。返回 {name: mask}。"""
    h, w = mask.shape
    ys = np.arange(h)[:, None]
    xs = np.arange(w)[None, :]

    head_core = mask & (ys <= HEAD_BOTTOM)
    arm_l_core = mask & (ys >= ARM_TOP) & (ys <= ARM_BOTTOM) & (xs <= ARM_L_CORE_X)
    arm_r_core = (mask & (ys >= ARM_TOP) & (ys <= ARM_BOTTOM)
                  & (xs >= ARM_R_CORE_X) & (xs <= ARM_R_MAX_X))
    leg_l_core = mask & (ys >= LEG_CORE_TOP) & (xs >= LEG_X_MIN) & (xs <= LEG_SPLIT_X)
    leg_r_core = (mask & (ys >= LEG_CORE_TOP) & (xs > LEG_SPLIT_X) & (xs <= LEG_X_MAX))

    tail_core = np.zeros((h, w), bool)
    for y0, y1, xt in TAIL_XT:
        tail_core |= mask & (ys >= y0) & (ys <= y1) & (xs >= xt)
    skirt_core = (mask & (ys >= SKIRT_CORE_TOP) & (ys <= SKIRT_CORE_BOTTOM)
                  & ~tail_core)

    torso = mask & ~(head_core | arm_l_core | arm_r_core | leg_l_core | leg_r_core
                     | skirt_core | tail_core)

    head = mask & (ys <= HEAD_PAINT_BOTTOM)
    arm_l = mask & (ys >= ARM_TOP) & (ys <= ARM_BOTTOM) & (xs <= ARM_L_PAINT_X)
    arm_r = (mask & (ys >= ARM_TOP) & (ys <= ARM_BOTTOM)
             & (xs >= ARM_R_PAINT_X) & (xs <= ARM_R_MAX_X))
    leg_l = mask & (ys >= LEG_TOP) & (xs >= LEG_X_MIN) & (xs <= LEG_SPLIT_X)
    leg_r = mask & (ys >= LEG_TOP) & (xs > LEG_SPLIT_X) & (xs <= LEG_X_MAX)
    skirt = (mask & (ys >= SKIRT_PAINT_TOP) & (ys <= SKIRT_CORE_BOTTOM)
             & ~tail_core & ~arm_l_core & ~arm_r_core)
    tail = dilate(tail_core, TAIL_GROW) & mask      # 根部膨胀出的重叠区

    return {
        "tail": tail, "leg_l": leg_l, "leg_r": leg_r, "skirt": skirt,
        "torso": torso, "arm_l": arm_l, "arm_r": arm_r, "head": head,
    }


def composite(parts, rgb, order, size):
    """按 z 顺序把部件叠回，返回 RGBA。"""
    canvas = np.zeros((size[1], size[0], 4), np.uint8)
    for name in order:
        m = parts[name]
        sub = np.zeros_like(canvas)
        sub[m, :3] = rgb[m]
        sub[m, 3] = 255
        canvas = Image.alpha_composite(Image.fromarray(canvas), Image.fromarray(sub))
        canvas = np.array(canvas)
    return canvas


def main():
    if not os.path.exists(SRC):
        sys.exit("找不到输入：%s" % SRC)
    os.makedirs(PARTSDIR, exist_ok=True)

    src = np.array(Image.open(SRC).convert("RGB")).astype(np.uint8)
    H, W, _ = src.shape
    s = detect_scale(src)
    base = downscale(src, s)
    bh, bw, _ = base.shape
    print(f"[1] 输入 {W}x{H}，识别为 {bw}x{bh} 逻辑像素的 {s}x 放大")

    # --- 抠背景 -----------------------------------------------------------
    thr = bg_threshold(base)
    ratio = base[:, :, 0].astype(float) / (base[:, :, 2].astype(float) + 1.0)
    bg = ratio < thr
    fg = ~bg
    print(f"[2] 背景判据 R/(B+1) < {thr:.4f}；背景实测 max={ratio[bg].max():.4f}，"
          f"角色实测 min={ratio[fg].min():.4f}（分离干净）")
    print(f"    前景 {fg.sum()} / {bw * bh} 逻辑像素")

    main_cc, ncomp, npx = largest_component(fg)
    print(f"[3] 连通块 {ncomp} 个（8 邻接），最大块 {npx} px（=角色），其余按小连通块丢弃")

    filled, nhole, holes, nreg = fill_holes(main_cc, HOLE_MAX_AREA)
    print(f"[4] 填掉 {nhole} px 的封闭小洞（<= {HOLE_MAX_AREA} px 的抖动暗点）"
          f"；透空缝保留（共 {nreg} 个背景区块）")
    base2 = recolor_holes(filled, base, holes)

    nebula = nebula_color_set(base)
    cleaned, nrm = remove_nebula_whiskers(filled, base2, nebula, band_y=NEBULA_BAND_Y)
    print(f"[5] 清星云残条 {nrm} px（星云色：{[c for c in nebula if c[0] >= 8]}）")

    # 抠图后不应有孤立的 1~2 px 碎块
    keep, _, _ = largest_component(cleaned)
    if keep.sum() != cleaned.sum():
        print(f"    -> 再丢孤立碎片 {int(cleaned.sum() - keep.sum())} px")
    mask = keep
    print(f"[6] 前景最终 {int(mask.sum())} 逻辑像素，bbox y={np.nonzero(mask)[0].min()}..{np.nonzero(mask)[0].max()}")

    # --- 放大回画布尺寸，硬边 alpha --------------------------------------
    alpha_big = np.kron(mask.astype(np.uint8), np.ones((s, s), np.uint8)) * 255
    rgb_big = np.kron(base2, np.ones((s, s, 1), np.uint8))
    assert rgb_big.shape[:2] == (H, W) == (RIG["canvas"][1], RIG["canvas"][0])
    rgb_big = rgb_big.copy()
    rgb_big[alpha_big == 0] = 0            # 全透明处统一抹成 0，便于逐像素比对
    cutout = np.dstack([rgb_big, alpha_big])
    Image.fromarray(cutout, "RGBA").save(os.path.join(OUTDIR, "cutout.png"))
    print(f"[7] 写出 cutout.png {W}x{H}，透明像素 {int((alpha_big == 0).sum())}")

    # --- 切件 -------------------------------------------------------------
    parts_small = build_parts(mask)
    parts_big = {}
    for name, m in parts_small.items():
        a = np.kron(m.astype(np.uint8), np.ones((s, s), np.uint8)) * 255
        parts_big[name] = np.dstack([rgb_big, a])
        Image.fromarray(parts_big[name], "RGBA").save(
            os.path.join(PARTSDIR, name + ".png"))
        print(f"[8] parts/{name}.png  {int(m.sum())} 逻辑像素")

    # --- 自证 1：叠回必须逐像素等于 cutout -------------------------------
    order = sorted(parts_small, key=lambda n: RIG["parts"][n]["z"])
    comp = composite(parts_small, base2, order, (bw, bh))
    comp_big = np.kron(comp, np.ones((s, s, 1), np.uint8))
    Image.fromarray(comp_big, "RGBA").save(os.path.join(OUTDIR, "composite.png"))
    diff = np.abs(comp_big.astype(int) - cutout.astype(int))
    ndiff = int((diff != 0).any(axis=2).sum())
    print(f"[9] composite 与 cutout 像素差 = {ndiff}")
    if ndiff != 0:
        print("    !! 切件丢像素了，请检查 build_parts 覆盖关系")

    # --- 自证 2：三联调试图（原图 / 分区染色 / 错开）---------------------
    # 偏移单位 = 逻辑像素（会乘 scale）
    offsets = {
        "torso": (0, 0), "leg_l": (-3, 3), "leg_r": (3, 3),
        "arm_l": (-5, 0), "arm_r": (5, 0), "head": (0, -5),
        "skirt": (0, 7), "tail": (4, 0),
    }
    GAP = 12 * s // 4
    panel_w, panel_h = W, H
    dbg = np.zeros((panel_h, panel_w * 3 + GAP * 2, 4), np.uint8)
    dbg[..., :3] = (26, 28, 34)
    dbg[..., 3] = 255

    def blit(panel_idx, mask_small, color=None, src=None, off=(0, 0)):
        """把 base 分辨率的掩码按 scale 放大后画到第 panel_idx 个面板。"""
        x0 = panel_idx * (panel_w + GAP)
        m = np.kron(mask_small.astype(np.uint8), np.ones((s, s), np.uint8)).astype(bool)
        sy, sx = np.nonzero(m)                      # 画布坐标（未偏移）
        ty = sy + off[1] * s
        tx = sx + off[0] * s
        ok = (ty >= 0) & (ty < panel_h) & (tx >= 0) & (tx < panel_w)
        sy, sx, ty, tx = sy[ok], sx[ok], ty[ok], tx[ok]
        if color is not None:
            dbg[ty, tx + x0, :3] = color
        else:
            dbg[ty, tx + x0, :3] = src[sy, sx, :3]
        dbg[ty, tx + x0, 3] = 255

    # 面板 0：切件前的 cutout
    rgb_big_dbg = np.kron(base2, np.ones((s, s, 1), np.uint8))
    for name in order:
        blit(0, parts_small[name], src=rgb_big_dbg)
    # 面板 1：分区染色（不偏移）+ pivot 十字
    for name in order:
        blit(1, parts_small[name], color=DEBUG_COLORS[name])
    x0 = panel_w + GAP
    for name in order:
        px, py = RIG["parts"][name]["pivot"]
        dbg[py, max(0, px - 4) + x0:min(panel_w, px + 5) + x0, :3] = (255, 255, 255)
        dbg[py - 4:py + 5, x0 + px, :3] = (255, 255, 255)
        dbg[py, x0 + px, :3] = DEBUG_COLORS[name]
    # 面板 2：分区染色 + 错开
    for name in order:
        blit(2, parts_small[name], color=DEBUG_COLORS[name], off=offsets[name])

    Image.fromarray(dbg, "RGBA").save(os.path.join(OUTDIR, "parts-debug.png"))
    print(f"[10] 写出 parts-debug.png（{dbg.shape[1]}x{dbg.shape[0]}，左=原图 中=分区+pivot 右=错开）")

    # --- rig.json ---------------------------------------------------------
    with open(os.path.join(OUTDIR, "rig.json"), "w", encoding="utf-8") as f:
        json.dump(RIG, f, ensure_ascii=False, indent=2)
    print("[11] 写出 rig.json")

    return 0


if __name__ == "__main__":
    sys.exit(main())
