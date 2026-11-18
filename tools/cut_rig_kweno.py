#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cut_rig_kweno.py — 千问（Kweno）Q 版九件切件（可重跑）。

用法（项目根目录）：
    python tools/cut_rig_kweno.py [--src <透明底 Q 版全身图>]

输入默认：D:/zcode-work/pictures/output/2026-11-17-kweno-chibi-v2.png
输出：
    assets/art/rig/kweno/rig.json              九件契约
    assets/art/rig/kweno/parts/*.png           每件都是整幅 192x256 透明图
    assets/art/rig/kweno/cutout.png            192x256 硬边透明底整幅
    assets/art/rig/kweno/composite.png         九件按 z 叠回（自证 == cutout）
    assets/art/rig/kweno/parts-debug.png       各件染色错开，肉眼查地标

与 deepdeek 同一套像素语言：96x128 逻辑像素 ×2 最近邻放大 = 192x256，硬 alpha。

切件判据用「逐行连通 run」而不是颜色：这张是整幅蓝紫渐变插画，颜色聚类分不开
袖/发/裙（实测 k-means 8 类里 91% 像素落在同族）。逐行 run 顺序是稳定的：
    左发 | 左袖 | 躯干 | 右袖 | 右发
所以「含中心列的 run = 躯干」，其左右相邻 run = 臂，更外侧 = hair_b。

九件与两个难点规避（《千问-施工规格书》4.4）：
  · head   —— **包髻 + 横插簪钗 + 耳珰并入**（单独成件会在 idle 时与头发错位）。
  · hair_b —— 后侧大卷下端，z=-1（垫在所有躯体件之下）。只取躯干轮廓之外的长发，
              既不盖袍子，也不跟着点头转。
  · torso  —— 立领 + 肩 + **袖根** + 胸前茶盏 + 双手。宽袖整块布若独立旋转必开腋下，
              故袖根併进 torso；arm_l/arm_r 只留肘以下那截离体垂袖。
              本 pose 双手捧盏、手与盏贴死，拆手必破盏，故双手并进 torso（Q 版看不出损失）。
  · arm_l / arm_r —— 肘以下离体垂袖，pivot 抬到肘（不是肩，避免整条袖子甩）。
  · skirt_a —— 上裙（腰线→膝）；skirt_b —— 拖地下摆（膝→地），follow-through 主角。
  · leg_l / leg_r —— 长裙遮腿：只在地面露 2-3px 脚尖（鞋为青花瓷配色，合成像素，
              原图长裙拖地、无脚）。裙子在下摆中段挖 4 逻辑像素缺口让脚尖露。
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_SRC = r"D:/zcode-work/pictures/output/2026-11-17-kweno-chibi-v2.png"
OUTDIR = os.path.join(ROOT, "assets", "art", "rig", "kweno")
PARTSDIR = os.path.join(OUTDIR, "parts")

LOG_W, LOG_H = 96, 128
SCALE = 2
CANVAS = (LOG_W * SCALE, LOG_H * SCALE)

ALPHA_CUT = 110
CX = 48                      # 角色中轴（逻辑 x）

# ── 地标（逻辑像素，96x128，y 向下；实测自 .tmp_vis/v2_ruler.png 标尺）──
HEAD_BOTTOM = 50        # 脖子线：y<=50 归头（包髻/簪钗/脸/刘海/耳珰）
HEAD_PAINT = 52         # 头输出多带 2 行（与 torso 在脖子处重叠，防露缝）
WAIST = 80              # 腰线：torso / skirt_a core 分界
KNEE = 112              # 膝线：skirt_a / skirt_b core 分界
ARM_TOP = 86            # 肘线（垂袖起点）：以上是袖根，已併进 torso
ARM_BOT = 113           # 垂袖下缘
LEG_SLOT = (34, 62)     # 下摆缺口 x 范围（挖出来让脚尖露）
LEG_SPLIT = 48          # 左右脚分界
LEG_TOP = 120           # 脚尖顶（下摆底 125，露 5 逻辑像素 = 10 canvas px 的鞋尖）

## ── 接缝重叠带（逻辑 px）─────────────────────────────────────────
## core 是互斥分区（用于覆盖自证）；paint 在 core 的基础上**纵向**外扩，
## 让相邻两件在接缝处重复一段同样像素。理由实测：idle bob ±4 / walk ±6 canvas px，
## 重叠不足就在起伏瞬间露一条黑缝（本 rig 首版只有 2px 重叠，pose 压测直接出线）。
## deepdeek 的 torso/skirt 重叠 24 canvas px，本 rig 取同等量级。
OVL = 6                 # 相邻件上下各让 6 逻辑像素 = 12 canvas px 重叠

# 躯干轮廓半宽（逻辑 px，从 CX=48 起算），按 y 分段线性插值。
# 按逐行 run 实测标定：肩 26..70 / 腰 30..66 / 裙摆 20..76 / 下摆 8..88。
# 落在轮廓之外、且 y>HEAD_BOTTOM 的像素 = 身后长发（hair_b，z=-1 垫底）。
BODY_HW = [(52, 13), (58, 20), (66, 18), (72, 17), (80, 16),
           (88, 22), (96, 26), (106, 27), (112, 26), (126, 40)]

RIG = {
    "canvas": [192, 256],
    "parts": {
        "hair_b":  {"pivot": [96, 112], "z": -1},
        "leg_l":   {"pivot": [88, 244], "z": 1},
        "leg_r":   {"pivot": [104, 244], "z": 1},
        "skirt_b": {"pivot": [96, 208], "z": 2},
        "skirt_a": {"pivot": [96, 160], "z": 2},
        "torso":   {"pivot": [96, 220], "z": 3},
        "arm_l":   {"pivot": [44, 172], "z": 4},
        "arm_r":   {"pivot": [148, 172], "z": 4},
        "head":    {"pivot": [96, 96],  "z": 5},
    },
    "notes": [
        "canvas 192x256；逻辑像素 96x128 ×2 最近邻（与 deepdeek 同一套像素语言，硬 alpha）。",
        "【难点1 宽袖】袖根併进 torso。W_ARM=6.0 是给细长头发条带的余量，整块宽袖绕肩旋转"
        "必开腋下；arm_l/arm_r 只留肘以下离体垂袖，pivot 抬到肘 [44,172]/[148,172]。",
        "【难点1 附带】本 pose 双手捧盏在胸前、手与盏贴死，拆手必破盏，故双手并进 torso。"
        "Q 版看不出损失，省掉整个「袖口/手补洞」返工。",
        "【难点2 长裙遮腿】步态交给裙——skirt_b 做 follow-through（横摆 ±5、旋转 ±6，"
        "复用 W_SKIRT_A 量级）；腿只在地面露 2-3px 脚尖（鞋为合成像素，原图长裙拖地无脚）。",
        "head 已并入包髻 + 横插簪钗 + 耳珰：头饰单独成件会在 idle/shake 时与头发错位。",
        "hair_b z=-1，只取躯干轮廓之外的长发，垫在所有件之下，不随点头转动。",
        "torso pivot 落在脚下 [96,220]，躯干旋转读作「整体身姿摇摆」而不是折腰；"
        "skirt_a 绕腰 [96,160]、skirt_b 绕膝 [96,208]，下摆才是真摆动。",
        "档位：只做 idle（+ shake/attack 由 chibi_rig.gd 现成轨道驱动，无需新帧）。"
        "ai_select.gd 只播 idle、悬停播 shake，walk/run 一次都没被调用。",
    ],
}

DEBUG_COLORS = {
    "hair_b":  (150, 100, 235),
    "leg_l":   (64, 224, 96),
    "leg_r":   (0, 200, 200),
    "skirt_b": (90, 140, 255),
    "skirt_a": (185, 95, 255),
    "torso":   (70, 165, 255),
    "arm_l":   (255, 208, 0),
    "arm_r":   (255, 120, 0),
    "head":    (255, 64, 64),
}
Z_ORDER = ["hair_b", "leg_l", "leg_r", "skirt_b", "skirt_a", "torso", "arm_l", "arm_r", "head"]


# ── 工具 ──────────────────────────────────────────────────────────
def to_logical(src_path):
    """软边 RGBA -> 96x128 硬 alpha 逻辑像素（预乘后 BOX 缩略，再反预乘）。"""
    im = Image.open(src_path).convert("RGBA")
    a = np.array(im)
    a[..., 3] = np.where(a[..., 3] > ALPHA_CUT, 255, 0)
    rgb = a[..., :3].astype(np.float32) * (a[..., 3:4].astype(np.float32) / 255.0)
    pre = np.concatenate([rgb, a[..., 3:4].astype(np.float32)], axis=2)
    small = np.array(Image.fromarray(pre.astype(np.uint8), "RGBA").resize(
        (LOG_W, LOG_H), Image.BOX)).astype(np.float32)
    alpha = small[..., 3]
    out = np.zeros((LOG_H, LOG_W, 4), np.uint8)
    out[..., :3] = np.clip(small[..., :3] / np.maximum(alpha[..., None] / 255.0, 1e-6),
                           0, 255).astype(np.uint8)
    out[..., 3] = np.where(alpha > ALPHA_CUT, 255, 0).astype(np.uint8)
    out[out[..., 3] == 0, :3] = 0
    return out


def hw_at(y):
    """躯干轮廓半宽（逻辑 px），分段线性插值。"""
    pts = BODY_HW
    if y <= pts[0][0]:
        return pts[0][1]
    for i in range(len(pts) - 1):
        y0, w0 = pts[i]
        y1, w1 = pts[i + 1]
        if y0 <= y <= y1:
            t = (y - y0) / float(y1 - y0)
            return w0 + (w1 - w0) * t
    return pts[-1][1]


def runs_of(row):
    """一行前景的连续区间 [(x0, x1), ...]。"""
    xs = np.nonzero(row)[0]
    if len(xs) == 0:
        return []
    out = []
    s = xs[0]
    p = xs[0]
    for v in xs[1:]:
        if v > p + 1:
            out.append((int(s), int(p)))
            s = v
        p = v
    out.append((int(s), int(p)))
    return out


def dilate(m, r=1):
    if r <= 0:
        return m.copy()
    pad = np.zeros((m.shape[0] + 2 * r, m.shape[1] + 2 * r), bool)
    pad[r:r + m.shape[0], r:r + m.shape[1]] = m
    out = np.zeros_like(m)
    for dy in range(2 * r + 1):
        for dx in range(2 * r + 1):
            out |= pad[dy:dy + m.shape[0], dx:dx + m.shape[1]]
    return out


def build_cores(char):
    """逐行 run 判定。返回 {name: core mask}（互斥）与 part 标签图。"""
    H, W = char.shape
    part = np.full((H, W), "", dtype=object)

    for y in range(H):
        rs = runs_of(char[y])
        if not rs:
            continue
        c = 0
        best = 1e9
        for i, (x0, x1) in enumerate(rs):
            d = 0 if x0 <= CX <= x1 else min(abs(x0 - CX), abs(x1 - CX))
            if d < best:
                best, c = d, i

        hw = hw_at(y)
        for i, (x0, x1) in enumerate(rs):
            if i == c:
                for x in range(x0, x1 + 1):
                    if abs(x - CX) <= hw:
                        if y <= HEAD_BOTTOM:
                            part[y, x] = "head"
                        elif y <= WAIST:
                            part[y, x] = "torso"
                        elif y < KNEE:
                            part[y, x] = "skirt_a"
                        else:
                            part[y, x] = "skirt_b"
                    elif y > HEAD_BOTTOM:
                        part[y, x] = "hair_b"
                    else:
                        part[y, x] = "head"
            elif i == c - 1 and ARM_TOP <= y < ARM_BOT:
                part[y, x0:x1 + 1] = "arm_l"
            elif i == c + 1 and ARM_TOP <= y < ARM_BOT:
                part[y, x0:x1 + 1] = "arm_r"
            else:
                part[y, x0:x1 + 1] = "head" if y <= HEAD_BOTTOM else "hair_b"

    cores = {nm: char & (part == nm) for nm in Z_ORDER}
    return cores, part


def build_paints(char, cores):
    """给每件做出接缝重叠区：沿 y 向上/下各扩 OVL 行的**同族**像素。

    纵向分段（head/torso/skirt_a/skirt_b）各自上下外扩；臂向下外扩进裙/躯干；
    hair_b 不扩（它 z=-1 垫底，扩了反而盖住袍子）。
    """
    H, W = char.shape
    ys = np.arange(H)[:, None]
    paints = {}

    # 纵向四段的 y 边界（core 的真实分界）
    bands = [
        ("head", -1, HEAD_BOTTOM),
        ("torso", HEAD_BOTTOM + 1, WAIST),
        ("skirt_a", WAIST + 1, KNEE - 1),
        ("skirt_b", KNEE, H),
    ]
    for nm, y0, y1 in bands:
        ext0 = max(0, y0 - OVL)
        ext1 = min(H - 1, y1 + OVL)
        cols = cores[nm].any(axis=0)
        sel = (ys >= ext0) & (ys <= ext1) & cols[None, :]
        paints[nm] = char & sel

    # 臂：只在原横向范围内，向下多带 OVL 行进相邻件（合成接缝）
    for nm, y0, y1 in (("arm_l", ARM_TOP, ARM_BOT - 1), ("arm_r", ARM_TOP, ARM_BOT - 1)):
        ext1 = min(H - 1, y1 + OVL)
        cols = cores[nm].any(axis=0)
        sel = (ys >= y0) & (ys <= ext1) & cols[None, :]
        paints[nm] = char & sel

    # hair_b 不扩
    paints["hair_b"] = cores["hair_b"].copy()

    # 脚：只在本槽内扩（不外扩进裙子，裙子已经在下摆让出缺口）
    xs = np.arange(W)[None, :]
    for nm, x0, x1 in (("leg_l", LEG_SLOT[0], LEG_SPLIT - 1),
                       ("leg_r", LEG_SPLIT, LEG_SLOT[1])):
        sel = (ys >= LEG_TOP) & (xs >= x0) & (xs <= x1)
        paints[nm] = (char & sel) | cores[nm]

    for nm in Z_ORDER:
        paints[nm] = (dilate(paints[nm], 1) & char) | cores[nm]
    return paints


def synth_toes(cores, logical):
    """原图无脚（长裙拖地）。在下摆边缘合成尖头青花瓷鞋尖。

    Q 版只露出「点地的那一点点」，所以做**上宽下窄的尖头**，只占最后 5 逻辑像素：
        y=TOE_TOP  宽 9  → 7 → 5 → 3 → 3（尖端）
    配色取青花瓷蓝白三阶（深靛描边 / 中蓝鞋面 / 白瓷高光），与裙上青花同一套语言。

    只覆盖鞋自己的像素，裙子保留缺口里其余部分（不能整块清空，否则漏切）。
    """
    H = logical.shape[0]
    dark = (42, 54, 100)
    body = (104, 132, 206)
    hi = (226, 234, 250)
    top = H - 5                     # TOE_TOP：最后 5 行
    widths = [9, 7, 5, 3, 3]

    for nm, cx in (("leg_l", LEG_SLOT[0] + 10), ("leg_r", LEG_SLOT[1] - 10)):
        for i, y in enumerate(range(top, H)):
            if i >= len(widths):
                break
            w = widths[i]
            x0 = cx - w // 2
            x1 = x0 + w - 1
            for x in range(x0, x1 + 1):
                logical[y, x, :3] = body
                logical[y, x, 3] = 255
                cores[nm][y, x] = True
                cores["skirt_b"][y, x] = False
            logical[y, x0, :3] = dark
            logical[y, x1, :3] = dark
            if i == 0:
                for x in range(x0 + 1, x1):
                    logical[y, x, :3] = dark
            if i == len(widths) - 1:
                for x in range(x0 + 1, x1):
                    logical[y, x, :3] = hi
    return cores


def to_canvas(mask, logical):
    """逻辑掩码 -> 192x256 整幅 RGBA（×SCALE 最近邻，硬 alpha）。"""
    out = np.zeros((LOG_H * SCALE, LOG_W * SCALE, 4), np.uint8)
    up = np.repeat(np.repeat(mask, SCALE, axis=0), SCALE, axis=1)
    rgbu = np.repeat(np.repeat(logical, SCALE, axis=0), SCALE, axis=1)
    out[up] = rgbu[up]
    out[up, 3] = 255
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=DEFAULT_SRC)
    args = ap.parse_args()
    if not os.path.exists(args.src):
        sys.exit("找不到输入：%s" % args.src)
    os.makedirs(PARTSDIR, exist_ok=True)

    logical = to_logical(args.src)
    char = logical[..., 3] > 0
    ys, xs = np.nonzero(char)
    print("[1] %s -> 逻辑 %dx%d，角色 bbox x[%d,%d] y[%d,%d]，%d px"
          % (os.path.basename(args.src), LOG_W, LOG_H, xs.min(), xs.max(),
             ys.min(), ys.max(), int(char.sum())))

    cores, part = build_cores(char)
    cores = synth_toes(cores, logical)

    # 覆盖自证：九件 core 必须正好铺满角色
    union = np.zeros_like(char)
    for nm in Z_ORDER:
        union |= cores[nm]
    cover = union & char
    ok = int(cover.sum()) == int(char.sum())
    print("[2] 覆盖自证：core 并集 %d / 角色 %d -> %s"
          % (int(cover.sum()), int(char.sum()), "OK" if ok else "FAIL 有漏切"))
    if not ok:
        miss = char & ~cover
        yy, xx = np.nonzero(miss)
        print("    漏切 %d px，样本：" % len(yy), list(zip(xx[:24].tolist(), yy[:24].tolist())))
    for nm in Z_ORDER:
        if cores[nm].sum() == 0:
            print("    警告：%s 为空件" % nm)

    # paint = core + 接缝重叠（相邻件重复一段同样像素，bob 时不会露缝）
    paints = build_paints(char, cores)
    print("[3] 接缝重叠 %d 逻辑 px（= %d canvas px）；各件 paint/core 比：%s"
          % (OVL, OVL * SCALE,
             " ".join("%s=%.2f" % (nm, paints[nm].sum() / max(1, cores[nm].sum()))
                      for nm in Z_ORDER)))

    for nm in Z_ORDER:
        Image.fromarray(to_canvas(paints[nm], logical)).save(
            os.path.join(PARTSDIR, nm + ".png"))
    cutout = to_canvas(char, logical)
    Image.fromarray(cutout).save(os.path.join(OUTDIR, "cutout.png"))

    # 按 z 叠回（逐像素自证）
    comp = np.zeros_like(cutout)
    for nm in Z_ORDER:
        m = to_canvas(paints[nm], logical)[..., 3] > 0
        comp[m] = cutout[m]
    Image.fromarray(comp).save(os.path.join(OUTDIR, "composite.png"))
    diff = int((np.abs(comp.astype(int) - cutout.astype(int)).sum(axis=2) > 6).sum())
    print("[3] composite vs cutout 差异像素 %d -> %s" % (diff, "OK" if diff == 0 else "注意"))

    # 调试图：各件染色 + 水平错开 12px
    dbg = np.zeros((CANVAS[1], CANVAS[0] + 12 * (len(Z_ORDER) - 1), 4), np.uint8)
    for i, nm in enumerate(Z_ORDER):
        m = to_canvas(paints[nm], logical)
        sel = m[..., 3] > 0
        off = i * 12
        sub = dbg[:, off:off + CANVAS[0]]
        sub[sel] = np.array(DEBUG_COLORS[nm] + (255,), np.uint8)
        dbg[:, off:off + CANVAS[0]] = sub
    Image.fromarray(dbg).save(os.path.join(OUTDIR, "parts-debug.png"))

    with open(os.path.join(OUTDIR, "rig.json"), "w", encoding="utf-8") as f:
        json.dump(RIG, f, ensure_ascii=False, indent=2)

    for nm in Z_ORDER:
        yy, xx = np.nonzero(paints[nm])
        if len(yy) == 0:
            print("    %-8s EMPTY" % nm)
            continue
        print("    %-8s pivot=%-12s z=%2d  bbox x[%3d,%3d] y[%3d,%3d]  %d canvas px"
              % (nm, RIG["parts"][nm]["pivot"], RIG["parts"][nm]["z"],
                 xx.min() * SCALE, xx.max() * SCALE, yy.min() * SCALE, yy.max() * SCALE,
                 len(yy) * SCALE * SCALE))
    print("[4] 输出目录 %s" % OUTDIR)


if __name__ == "__main__":
    main()
