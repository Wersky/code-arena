#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""画黑桃 2~10 / J / Q / K 的角标：点数用像素字体渲染后整数倍放大。

为什么不用手写点阵：5x7 手绘的 A 会看成 H。改用 Ark Pixel 12px 渲染（字形正确），
再最近邻放大，得到和参照卡同样「大像素」的观感。

花色符号来自参照卡：assets/art/ui-pip-spade-x-suit.png
A 直接用参照卡上的原件：assets/art/ui-pip-spade-a.png（由抠图脚本产出）
"""

import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
DST = os.path.join(PROJECT, "assets", "art")
FONT = os.path.join(PROJECT, "assets", "fonts", "ark-pixel-12px.ttf")
COLOR = (22, 32, 58)
SCALE = 15            # 统一放大倍数：所有字形同一笔画粗细

LABELS = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "j", "q", "k"]


def render(label):
    f = ImageFont.truetype(FONT, 12)
    text = label.upper() if label.isalpha() else label
    canvas = Image.new("L", (80, 24), 0)
    ImageDraw.Draw(canvas).text((0, 0), text, font=f, fill=255)
    bbox = canvas.getbbox()
    g = canvas.crop(bbox)
    g = g.resize((g.width * SCALE, g.height * SCALE), Image.NEAREST)
    out = Image.new("RGBA", g.size, (0, 0, 0, 0))
    px = out.load()
    sp = g.load()
    for y in range(g.height):
        for x in range(g.width):
            if sp[x, y] > 128:
                px[x, y] = COLOR + (255,)
    return out


def main():
    os.makedirs(DST, exist_ok=True)
    for label in LABELS:
        g = render(label)
        g.save(os.path.join(DST, "ui-pip-spade-%s.png" % label))
        print("[ok] ui-pip-spade-%s.png  %s" % (label, g.size))


if __name__ == "__main__":
    main()
