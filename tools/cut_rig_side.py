#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cut_rig_side.py — 把抠好的侧面立绘切成 ChibiRig 侧面部件（初版）。

部件方案（正面 rig 的 8 件在这里收敛成 3 件）：
  torso  = 头 + 身 + 裙 + 后发（裙摆线以上全部 + 右侧垂发）——吃 walk/run 的 bob 与 waddle
  leg_l  = 远侧腿（后脚）——吃 stride/lift 轨道
  leg_r  = 近侧腿（前脚）——同上
ChibiRig 对缺失部件静默跳过，所以 walk/run/idle/shake/attack 全部直接可用，引擎零改动。

坐标约定（都在 side-raw 的 241x625 原始坐标系里，此时角色面朝左）：
  裙摆分割线 y=573（白花边底 ~568 / 腿顶 ~572 之间取中）；
  腿区 x<=192，右侧是垂发与阴影；前后腿以 x=136 分界。

输出:  assets/art/rig/deepdeek-side/{rig.json, cutout.png, composite.png,
       parts-debug.png, parts/{torso,leg_l,leg_r}.png}   —— 画布 192x256，面朝右
"""
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RAW = os.path.join(ROOT, ".tmp", "siderig", "side-raw.png")
OUTDIR = os.path.join(ROOT, "assets", "art", "rig", "deepdeek-side")
PARTSDIR = os.path.join(OUTDIR, "parts")

CANVAS = (192, 256)
HEM_Y = 573          ## 裙摆线：以上 = torso，以下 = 腿/鞋/残影
LEG_X_MAX = 192      ## 腿区右界（再往右是垂发）
LEG_SPLIT_X = 136    ## 前/后腿分界（面朝左时的 x）
SCALE = 0.40         ## 241x625 → ~96x250，画布 192x256 内留边
## 手臂矩形（raw 坐标，面朝左）：泡泡袖顶 ~305 → 指尖 ~500，x 108..172。
## 从 torso 挖出做独立层（绕肩旋转 = 摆臂），挖洞用同行织物色修补。
ARM_RECT = (108, 305, 172, 500)
ARM_SHOULDER = (140, 318)   ## 肩关节（旋转轴心，raw 坐标）

os.makedirs(PARTSDIR, exist_ok=True)
raw = Image.open(RAW).convert("RGBA")
a = np.asarray(raw).copy()
rh, rw = a.shape[:2]
alpha = a[:, :, 3] > 0

# ── 残留阴影清理（只作用在裙摆线附近以下）：浅灰、低饱和、偏亮 ──
r, g, b = a[:, :, 0].astype(np.int16), a[:, :, 1].astype(np.int16), a[:, :, 2].astype(np.int16)
shadow_like = (r > 165) & (r < 236) & (np.abs(b - r) < 30) & (np.abs(g - r) < 30)
zone = np.zeros((rh, rw), dtype=bool)
zone[HEM_Y - 24:, :] = True
drop = shadow_like & zone
a[drop, 3] = 0
alpha = a[:, :, 3] > 0
print(f"阴影清理：剔除 {int(drop.sum())} px")

# ── 三块掩码（面朝左坐标系）──
m_torso = alpha.copy()
m_torso[HEM_Y:, :] = False                      # 上半身全要
extra = alpha & (np.arange(rh)[:, None] >= HEM_Y)
# 右侧垂发归 torso；垂发是饱和蓝（b-r 大），灰蓝残影（b-r 小）在这里一并滤掉
hair_right = extra & (np.arange(rw)[None, :] > LEG_X_MAX) & ((b - r) > 45)
m_torso |= hair_right
m_legs_zone = extra & ~hair_right
m_leg_near = m_legs_zone & (np.arange(rw)[None, :] < LEG_SPLIT_X)   # 前脚（左）
m_leg_far = m_legs_zone & (np.arange(rw)[None, :] >= LEG_SPLIT_X)   # 后脚（右）

# ── 手臂：从 torso 挖出矩形区，织物洞按「同行最近的不透明色」修补 ──
ax0, ay0, ax1, ay1 = ARM_RECT
arm_rect_mask = np.zeros((rh, rw), dtype=bool)
arm_rect_mask[ay0:ay1, ax0:ax1] = True
m_arm = alpha & arm_rect_mask
m_torso_noarm = m_torso & ~arm_rect_mask

def inpaint_hole(mask: np.ndarray, hole: np.ndarray) -> np.ndarray:
    """把 hole 里的洞按同行最近的非洞不透明像素的颜色填上（织物横向延展）。"""
    out_img = np.zeros((rh, rw, 4), dtype=np.uint8)
    out_img[:, :, :3] = a[:, :, :3]
    out_img[:, :, 3] = mask.astype(np.uint8) * 255
    ys = np.where(hole.any(axis=1))[0]
    for y in ys:
        xs = np.where(hole[y])[0]
        # 分段：每一段连续洞，取段前/段后最近的不透明像素平均色
        runs = np.split(xs, np.where(np.diff(xs) > 1)[0] + 1)
        for run in runs:
            lft = run[0] - 1
            rgt = run[-1] + 1
            cands = []
            if lft >= 0 and mask[y, lft]:
                cands.append(a[y, lft, :3])
            if rgt < rw and mask[y, rgt]:
                cands.append(a[y, rgt, :3])
            if not cands:
                continue
            col = np.mean(cands, axis=0).astype(np.uint8)
            out_img[y, run[0]:run[-1] + 1, :3] = col
            out_img[y, run[0]:run[-1] + 1, 3] = 255
    return out_img

# torso 修补：洞 = 手臂矩形内原本属于角色的像素
m_torso_hole = m_torso & arm_rect_mask
torso_patched = inpaint_hole(m_torso_noarm, m_torso_hole)

# ── 全局对齐：所有部件用同一张「整身」包围盒做坐标映射，保持相对位置 ──
m_all = m_torso | m_leg_near | m_leg_far
ys_all, xs_all = np.where(m_all)
gb = (int(xs_all.min()), int(ys_all.min()), int(xs_all.max()) + 1, int(ys_all.max()) + 1)

def to_canvas_rgba(rgba: np.ndarray) -> tuple[Image.Image, tuple[int, int, int, int]]:
    im = Image.fromarray(rgba).transpose(Image.FLIP_LEFT_RIGHT)
    # 全局包围盒（翻转后）：所有部件共用，保对齐
    gbb_f = (rw - gb[2], gb[1], rw - gb[0], gb[3])
    im = im.crop(gbb_f)
    nw, nh = max(1, round(im.width * SCALE)), max(1, round(im.height * SCALE))
    im = im.resize((nw, nh), Image.BOX)
    hard = im.getchannel("A").point(lambda v: 255 if v >= 110 else 0)
    im.putalpha(hard)
    ox = (CANVAS[0] - nw) // 2
    oy = CANVAS[1] - nh - 2          ## 脚底贴画布下沿（留 2px 给影子）
    full = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    full.paste(im, (ox, oy), im)
    return full, (ox, oy, ox + nw, oy + nh)

def mask_rgba(mask: np.ndarray) -> np.ndarray:
    img = np.zeros((rh, rw, 4), dtype=np.uint8)
    img[:, :, :3] = a[:, :, :3]
    img[:, :, 3] = mask.astype(np.uint8) * 255
    return img

def to_canvas(mask: np.ndarray) -> tuple[Image.Image, tuple[int, int, int, int]]:
    return to_canvas_rgba(mask_rgba(mask))

torso_img, torso_bb = to_canvas_rgba(torso_patched)
near_img, near_bb = to_canvas(m_leg_near)
far_img, far_bb = to_canvas(m_leg_far)
arm_img, arm_bb = to_canvas(m_arm)

def flipped_x(x: float) -> float:
    return rw - 1 - x

def cx(x_raw: float, bb) -> int:
    """原始 x → 画布 x（翻转 + 缩放 + 偏移）"""
    fx = flipped_x(x_raw)
    return int(round(bb[0] + (fx - 0) * SCALE))  # bb[0] 已含居中偏移，fx*SCALE 是相对裁剪框

# 上面 cx 的推导对裁剪框不严谨，直接用比例式：画布 x = bb.x0 + (翻转后 x - 翻转后 bbox 左) * SCALE
def to_canvas_x(x_raw: float, bb, raw_bb_x0: float, raw_bb_x1: float) -> int:
    fx = flipped_x(x_raw)
    fx0 = flipped_x(raw_bb_x1 - 1)
    return int(round(bb[0] + (fx - fx0) * SCALE))

# 各部件在 raw 坐标系的包围盒（用于对齐 pivot）
def raw_bbox(mask: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.where(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1

rb_torso = raw_bbox(m_torso)
rb_near = raw_bbox(m_leg_near)
rb_far = raw_bbox(m_leg_far)

# pivot：torso = 裙摆线处的身位中心（waddle 绕它摆）；腿没有旋转轨道，
# pivot 只当位置基准，取「腿顶 y + 画布中心 x」即可
torso_pivot = (int(round((torso_bb[0] + torso_bb[2]) / 2.0)),
               torso_bb[1] + int(round((HEM_Y - gb[1]) * SCALE)))
leg_top_y = torso_bb[1] + int(round((HEM_Y - gb[1]) * SCALE))
near_pivot = (CANVAS[0] // 2, leg_top_y)
far_pivot = (CANVAS[0] // 2, leg_top_y)
# 肩关节 → 画布坐标（全局对齐映射：翻转后 x = gb[2]-1-x_raw）
arm_pivot = (int(round(torso_bb[0] + (gb[2] - 1 - ARM_SHOULDER[0]) * SCALE)),
             int(round(torso_bb[1] + (ARM_SHOULDER[1] - gb[1]) * SCALE)))

rig = {
    "canvas": list(CANVAS),
    "parts": {
        "leg_l": {"pivot": list(far_pivot), "z": 1},    # 远侧腿（后脚）
        "leg_r": {"pivot": list(near_pivot), "z": 2},   # 近侧腿（前脚）
        "torso": {"pivot": list(torso_pivot), "z": 3},
        "arm_r": {"pivot": list(arm_pivot), "z": 4},    # 手臂（绕肩摆）
    },
}

for nm, img in (("torso", torso_img), ("leg_l", far_img), ("leg_r", near_img), ("arm_r", arm_img)):
    img.save(os.path.join(PARTSDIR, nm + ".png"))
with open(os.path.join(OUTDIR, "rig.json"), "w", encoding="utf-8") as f:
    json.dump(rig, f, ensure_ascii=False, indent=2)

# composite = 四件叠回（应等于整身侧视）
composite = Image.alpha_composite(
    Image.alpha_composite(Image.alpha_composite(far_img, near_img), torso_img), arm_img)
composite.save(os.path.join(OUTDIR, "composite.png"))

# cutout = 整身（未拆件）走同样管线，给对比用
cut_mask = m_torso | m_leg_near | m_leg_far
cut_img, _ = to_canvas(cut_mask)
cut_img.save(os.path.join(OUTDIR, "cutout.png"))

# parts-debug：四件各自染色错开
dbg = Image.new("RGBA", (CANVAS[0] * 4 + 60, CANVAS[1]), (30, 34, 46, 255))
tints = {"torso": (120, 255, 120, 110), "leg_l": (255, 120, 120, 130),
         "leg_r": (120, 160, 255, 130), "arm_r": (255, 220, 90, 130)}
for i, (nm, img) in enumerate((("torso", torso_img), ("leg_l", far_img),
                               ("leg_r", near_img), ("arm_r", arm_img))):
    tinted = img.copy()
    ov = Image.new("RGBA", CANVAS, tints[nm])
    tinted.alpha_composite(ov)
    dbg.paste(tinted, (i * (CANVAS[0] + 20), 0), tinted)
dbg.save(os.path.join(OUTDIR, "parts-debug.png"))

print("torso pivot:", torso_pivot, " leg_l(far) pivot:", far_pivot,
      " leg_r(near) pivot:", near_pivot, " arm_r pivot:", arm_pivot)
print(f"已输出 {OUTDIR}")
