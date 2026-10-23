# -*- coding: utf-8 -*-
"""把生图出的 UI 部件加工成游戏内可直接用的像素资产。

输入：D:/zcode-work/pictures/output/2026-10-23-ui-*.png（透明底，1000~1250 px 见方）
输出：assets/art/ui/*.png

加工四件事：
  1. 裁到 alpha 包围盒（阈值 8，避免 alpha 噪点把包围盒撑到整张图）
  2. 整数倍 NEAREST 降采样 —— 每个"美术像素"落在一个像素上，不做插值
  3. 面板 / 横条量出九宫格边距（金边厚度），打印出来供 GDScript 常量使用
  4. 图标图按 2×2 切成四张

尺寸约定（重要）：
  游戏画布 1600×900。所有 UI 美术资产按 **×2 整数放大** 显示，
  所以这里的目标是「显示尺寸 ÷2」= 资源内的像素数。整数倍保证不糊。

用法：
  python tools/make_ui_assets.py            # 全部重做
  python tools/make_ui_assets.py --dry      # 只打印尺寸与边距，不写文件
"""

import argparse
import os
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

SRC_DIR = r"D:/zcode-work/pictures/output"
ROOT = r"D:/zcode-work/godot/projects/prompt-arena"
DST_DIR = os.path.join(ROOT, "assets/art/ui")
PREVIEW_DIR = os.path.join(ROOT, "docs/shots")

DATE = "2026-10-23"
ALPHA_THR = 8
DISPLAY_SCALE = 2  # 游戏里统一 ×2 显示


def load_cropped(name, pad=2):
    p = os.path.join(SRC_DIR, f"{DATE}-{name}.png")
    if not os.path.exists(p):
        raise SystemExit(f"缺图：{p}")
    im = Image.open(p).convert("RGBA")
    mask = im.split()[3].point(lambda v: 255 if v > ALPHA_THR else 0)
    bb = mask.getbbox()
    if bb is None:
        raise SystemExit(f"整张透明，没内容：{p}")
    l, t, r, b = bb
    return im.crop((max(0, l - pad), max(0, t - pad),
                    min(im.width, r + pad), min(im.height, b + pad))), p


def fit(im, disp_w, scale=DISPLAY_SCALE):
    """按"显示宽 disp_w、放大 scale 倍"反推整数降采样倍数"""
    native_w = max(1.0, disp_w / float(scale))
    f = max(1, int(round(im.width / native_w)))
    w = max(1, im.width // f)
    h = max(1, im.height // f)
    out = im.resize((w, h), Image.NEAREST)
    # alpha 二值化：像素风要硬边，半透明过渡边在放大后会变成毛边
    r, g, b, a = out.split()
    a = a.point(lambda v: 255 if v > 128 else 0)
    return Image.merge("RGBA", (r, g, b, a)), f


def tight(im):
    """把四周多余的透明边去掉。fit() 之后 alpha 二值化常常在边上留一圈透明，
    会让 measure_chamfer 把整行都当成切角。"""
    bb = im.split()[3].point(lambda v: 255 if v > 128 else 0).getbbox()
    return im.crop(bb) if bb else im


def up_preview(im, times, path):
    im.resize((im.width * times, im.height * times), Image.NEAREST).save(path)


def measure_chamfer(im, pad=6):
    """量四角「切角宽度」，给九宫格用。

    为什么必须量切角而不是"边框厚度"：九宫格拉伸时，四角的整块异形是原样贴过去的，
    只要角区装不下斜切角，一拉就变形。所以边距 = 切角宽度 + 少量留白。

    做法：在四个角各取一个 k×k 方框，找离角点最近的实体像素，取 dx+dy 的最小值。
    45° 斜切 c 像素时，最近的实体像素正好在 dx+dy = c 上。
    （不能用"从边缘往里数"——面板上下边常有凸起的小装饰，会把整条边都算成透明。）
    """
    w, h = im.size
    a = im.split()[3].load()
    k = max(8, min(w, h) // 3)

    def corner(bx, by, sx, sy):
        best = k
        for dy in range(k):
            for dx in range(k):
                if a[bx + dx * sx, by + dy * sy] > 128:
                    best = min(best, dx + dy)
                    break
        return best

    l = corner(0, 0, 1, 1)
    t = corner(w - 1, 0, -1, 1)
    r = corner(w - 1, h - 1, -1, -1)
    b = corner(0, h - 1, 1, -1)
    return (l + pad, t + pad, r + pad, b + pad)


def split_grid(im, cols, rows, gap_ratio=0.04):
    """按 alpha 空隙把整齐排布的图标图切成 cols×rows 小图"""
    w, h = im.size
    alpha = im.split()[3]

    def gaps(horiz):
        n = w if horiz else h
        runs, start = [], None
        for i in range(n):
            rng = range(h) if horiz else range(w)
            empty = all(alpha.getpixel((i, j) if horiz else (j, i)) <= ALPHA_THR for j in rng)
            if empty and start is None:
                start = i
            elif not empty and start is not None:
                runs.append((start, i))
                start = None
        if start is not None:
            runs.append((start, n))
        return [r for r in runs if (r[1] - r[0]) > n * gap_ratio]

    vg, hg = gaps(True), gaps(False)
    xcut = (vg[len(vg) // 2][0] + vg[len(vg) // 2][1]) // 2 if vg else w // 2
    ycut = (hg[len(hg) // 2][0] + hg[len(hg) // 2][1]) // 2 if hg else h // 2

    out = []
    for ry in range(rows):
        for rx in range(cols):
            cell = im.crop((0 if rx == 0 else xcut, 0 if ry == 0 else ycut,
                            xcut if rx == 0 else w, ycut if ry == 0 else h))
            bb = cell.split()[3].point(lambda v: 255 if v > ALPHA_THR else 0).getbbox()
            out.append(cell.crop(bb) if bb else cell)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()

    os.makedirs(DST_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    report = []

    # (源名, 输出名, 显示宽 px, 是否量九宫格)
    # 2026-10-23 第二版：主人要「更 AI 味」，整套换成霓虹控制台风格
    plans = [
        ("ai-plaque-v1", "plaque",   900, True),
        ("ai-panel-v1",  "panel",   1160, True),
        ("ai-btn-v1",    "btn",      580, False),
        ("ai-hud-v1",    "hudstrip",1180, True),
    ]

    for src, out, dw, measure in plans:
        im, _ = load_cropped(src)
        small, f = fit(im, dw)
        small = tight(small)
        line = (f"{out:9s} 源{im.size[0]:4d}×{im.size[1]:4d} ÷{f} → "
                f"{small.size[0]:4d}×{small.size[1]:3d}  ×{DISPLAY_SCALE} 显示 "
                f"{small.size[0]*DISPLAY_SCALE}×{small.size[1]*DISPLAY_SCALE}")
        if measure:
            l, t, r, b = measure_chamfer(small)
            line += (f"\n            切角 L{l} T{t} R{r} B{b} px → 九宫格 margin "
                     f"L{l*DISPLAY_SCALE} T{t*DISPLAY_SCALE} "
                     f"R{r*DISPLAY_SCALE} B{b*DISPLAY_SCALE}")
        report.append(line)
        if not a.dry:
            small.save(os.path.join(DST_DIR, f"ui-{out}.png"))
            up_preview(small, 3, os.path.join(PREVIEW_DIR, f"ui-check-{out}.png"))

    im, _ = load_cropped("ai-icons-v1")
    names = ["chip", "tokens", "reticle", "server"]
    for name, cell in zip(names, split_grid(im, 2, 2)):
        small, f = fit(cell, 64)
        small = tight(small)
        report.append(f"icon-{name:6s} 源{cell.size[0]:4d}×{cell.size[1]:4d} ÷{f} → "
                      f"{small.size[0]:3d}×{small.size[1]:3d}  ×{DISPLAY_SCALE} 显示 "
                      f"{small.size[0]*DISPLAY_SCALE}×{small.size[1]*DISPLAY_SCALE}")
        if not a.dry:
            small.save(os.path.join(DST_DIR, f"ui-icon-{name}.png"))
            up_preview(small, 3, os.path.join(PREVIEW_DIR, f"ui-check-icon-{name}.png"))

    # 3) 从面板图里裁四个角做成「角饰」
    #    为什么不用整张面板做九宫格：对局里的侧栏只有 300 px 宽，九宫格把 34 px 的粗金边
    #    缩进去会把内容挤没；而角饰**不随面板尺寸变化**，任何大小的面板都能用同一套角。
    panel_png = os.path.join(DST_DIR, "ui-panel.png")
    if os.path.exists(panel_png):
        pnl = Image.open(panel_png).convert("RGBA")
        cs = min(52, pnl.width // 3, pnl.height // 3)
        tl = pnl.crop((0, 0, cs, cs))
        corners = {
            "tl": tl,
            "tr": tl.transpose(Image.ROTATE_270),
            "br": tl.transpose(Image.ROTATE_180),
            "bl": tl.transpose(Image.ROTATE_90),
        }
        report.append(f"corner    从 ui-panel 裁 {cs}×{cs} 四角（旋转保证对称）")
        if not a.dry:
            for k, v in corners.items():
                v.save(os.path.join(DST_DIR, f"ui-corner-{k}.png"))
            up_preview(corners["tl"], 4, os.path.join(PREVIEW_DIR, "ui-check-corner-tl.png"))

    print("\n".join(report))
    print(f"\n{'（--dry：没有写文件）' if a.dry else '写入 ' + DST_DIR}")


if __name__ == "__main__":
    main()
