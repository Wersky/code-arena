#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""合成扑克卡样张（给主人目检用，不进游戏）。

游戏里卡牌是 150×226，由 Godot 的 CardView 绘制白底 + 小角色 + 四角点数。
本脚本用同一套像素规范做一张 4 倍大的样张，方便一眼看清效果。

用法：
    python tools/compose_card_preview.py --src <原图> --suit heart --rank 3
    python tools/compose_card_preview.py --src <原图> --suit spade --rank 7 --out docs/shots/card-sample.png
"""

import argparse
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

CARD = (150, 226)       # 游戏内卡面尺寸
SCALE = 4               # 样张放大倍数
FONT = r"D:\zcode-work\godot\projects\prompt-arena\assets\fonts\ark-pixel-12px.ttf"

SUIT_SYM = {"heart": "♥", "diamond": "♦", "spade": "♠", "club": "♣"}
SUIT_COLOR = {
    "heart": (245, 92, 102),
    "diamond": (250, 148, 77),
    "spade": (92, 118, 168),
    "club": (72, 160, 112),
}

PAPER = (255, 255, 255)     # 纯白纸面
INK = (24, 34, 62)          # 边框墨色（取自参照卡：(18,27,54)~(29,43,75)）


def crop_character(src: str) -> Image.Image:
    """裁出角色本体（去掉四周空白）。透明底的图先铺到白纸上。"""
    im = Image.open(src)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        paper = Image.new("RGBA", im.size, PAPER + (255,))
        paper.alpha_composite(im)
        im = paper
    im = im.convert("RGB")
    # 以近白像素为背景：找出非白区域
    w, h = im.size
    px = im.load()
    left, top, right, bottom = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if r < 244 or g < 244 or b < 240:
                if x < left:
                    left = x
                if x > right:
                    right = x
                if y < top:
                    top = y
                if y > bottom:
                    bottom = y
    if right <= left or bottom <= top:
        return im
    # 零留白：裁到墨迹边界，之后按这个框做严格居中
    return im.crop((left, top, right + 1, bottom + 1))


def fit(img: Image.Image, max_w: int, max_h: int) -> Image.Image:
    r = min(max_w / img.width, max_h / img.height)
    return img.resize((max(1, int(img.width * r)), max(1, int(img.height * r))),
                      Image.LANCZOS)


def unify_background(img: Image.Image, paper=PAPER) -> Image.Image:
    """把从边缘连通的近白背景换成纸面纯白，避免角色周围出现一块灰白方框。

    只改"能从边缘走到的近白像素"，角色身上的白色衣服（内部、被轮廓包住）不受影响。
    """
    w, h = img.size
    px = img.load()
    seen = [[False] * w for _ in range(h)]
    stack = []
    for x in range(w):
        stack.append((x, 0)); stack.append((x, h - 1))
    for y in range(h):
        stack.append((0, y)); stack.append((w - 1, y))

    def near_white(x, y):
        r, g, b = px[x, y][:3]
        return r >= 240 and g >= 240 and b >= 238 and (max(r, g, b) - min(r, g, b)) <= 12

    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y][x]:
            continue
        if not near_white(x, y):
            continue
        seen[y][x] = True
        px[x, y] = paper
        stack.append((x + 1, y)); stack.append((x - 1, y))
        stack.append((x, y + 1)); stack.append((x, y - 1))
    return img


def pixelize(img: Image.Image, colors: int = 28) -> Image.Image:
    """量化到限定调色板，保留原尺寸（角色图本身已经是像素风）。"""
    return img.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")


def glyph(ch: str, scale: int) -> Image.Image:
    """用像素字体渲染一个字符：12px 网格渲染 → 整数倍最近邻放大，保证硬边。"""
    f = ImageFont.truetype(FONT, 12)
    canvas = Image.new("RGBA", (64, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    d.text((0, 0), ch, font=f, fill=(0, 0, 0, 255))
    bbox = canvas.getbbox()
    if bbox is None:
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    canvas = canvas.crop(bbox)
    return canvas.resize((canvas.width * scale, canvas.height * scale), Image.NEAREST)


def tint(img: Image.Image, color) -> Image.Image:
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a > 0:
                px[x, y] = (color[0], color[1], color[2], a)
    return out


def draw_corner(card: Image.Image, suit: str, rank: int, top_left: bool) -> None:
    sym_color = SUIT_COLOR[suit]
    num = glyph(rank_label(rank), 4)   # 12px × 4 = 48px 网格
    sym = tint(glyph(SUIT_SYM[suit], 3), sym_color)   # 36px
    w = max(num.width, sym.width)
    block = Image.new("RGBA", (w, num.height + sym.height), (0, 0, 0, 0))
    nx = (w - num.width) // 2
    sx = (w - sym.width) // 2
    if top_left:
        block.alpha_composite(num, (nx, 0))
        block.alpha_composite(sym, (sx, num.height))
        card.alpha_composite(block, (20, 20))
    else:
        block.alpha_composite(sym, (sx, 0))
        block.alpha_composite(num, (nx, sym.height))
        card.alpha_composite(block, (card.width - 20 - w, card.height - 22 - block.height))


def rank_label(rank: int) -> str:
    return {1: "A", 11: "J", 12: "Q", 13: "K"}.get(rank, str(rank))


def build_pip_block(rank_label: str, suit: str = "spade") -> Image.Image:
    """拼一个角标块：点数在上、花色在下。

    A 直接用参照卡上的原件（主人认定的设计）；其余点数用像素字体的字 + 参照卡的花色。
    """
    art = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "assets", "art")
    ace = os.path.join(art, "ui-pip-%s-ref-ace.png" % ("ref" if suit == "spade" else suit))
    if rank_label.upper() == "A" and os.path.exists(ace):
        return Image.open(ace).convert("RGBA")

    label = rank_label.lower() if rank_label.isalpha() else rank_label
    num_path = os.path.join(art, "ui-pip-%s-%s.png" % (suit, label))
    suit_path = os.path.join(art, "ui-pip-%s-x-suit.png" % suit)
    num = Image.open(num_path).convert("RGBA")
    suit = Image.open(suit_path).convert("RGBA")
    gap = 12
    w = max(num.width, suit.width)
    h = num.height + gap + suit.height
    block = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    block.alpha_composite(num, ((w - num.width) // 2, 0))
    block.alpha_composite(suit, ((w - suit.width) // 2, num.height + gap))
    return block


def draw_pip_image(card: Image.Image, pip_path: str) -> None:
    """用现成的角标图（左上角那张）贴两侧：右下角旋转 180°。"""
    pip = Image.open(pip_path).convert("RGBA")
    # 按卡宽等比缩放：素材来自 1088 宽的参照卡，缩到本卡宽度
    k = card.width / 1088.0
    w = max(1, int(pip.width * k))
    h = max(1, int(pip.height * k))
    pip = pip.resize((w, h), Image.NEAREST)
    # 边距照抄参照卡：左上 (53,61)/1088×1446，右下 (53,78) 折算到本卡
    tl_x = int(53 / 1088.0 * card.width)
    tl_y = int(61 / 1446.0 * card.height)
    br_x = int(53 / 1088.0 * card.width)
    br_y = int(78 / 1446.0 * card.height)
    card.alpha_composite(pip, (tl_x, tl_y))
    card.alpha_composite(pip.rotate(180),
                         (card.width - br_x - w, card.height - br_y - h))


def compose(src: str, suit: str, rank: int, out_path: str, pip_path: str = "") -> None:
    W, H = CARD[0] * SCALE, CARD[1] * SCALE
    card = Image.new("RGBA", (W, H), PAPER + (255,))

    d = ImageDraw.Draw(card)
    # 边框照抄参照卡：细深蓝圆角线（参照 1088 宽下 2px、圆角 45px → 按卡宽折算）
    k = CARD[0] * SCALE / 1088.0
    bw = max(1, int(round(2 * k)))
    radius = max(1, int(round(45 * k)))
    inset = max(1, int(round(15 * k)))
    d.rounded_rectangle([inset, inset, W - 1 - inset, H - 1 - inset],
                        radius=radius, outline=INK + (255,), width=bw)

    # 角色：只占中间，不霸屏（宽 ≤ 62%，高 ≤ 52%）
    ch = crop_character(src)
    # 角色尺寸：54%→65%（+20%）→ 再 +10% = 71.28% 宽 / 58.08% 高
    ch = fit(ch, int(W * 0.7128), int(H * 0.5808))
    ch = pixelize(ch).convert("RGB")
    ch = unify_background(ch)
    ch = ch.convert("RGBA")
    px_x = (W - ch.width) // 2
    px_y = (H - ch.height) // 2

    # 细轮廓：白发白裙这类浅色角色在纯白纸面上会「飘走」，
    # 给剪影外扩 1~2px 描一圈极淡的紫灰线，把它从纸面上「切」出来（像素风的常规做法）。
    rgb = ch.convert("RGB")
    mask = Image.new("L", rgb.size, 0)
    mp = mask.load()
    rp = rgb.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            r, g, b = rp[x, y]
            if not (r >= 242 and g >= 242 and b >= 240):
                mp[x, y] = 255
    # 只对"整体偏亮"的角色加轮廓（白发白裙这类）；深色角色保持原样不动
    hist = mask.histogram()
    idx = [i for i, c in enumerate(hist) if c > 0]
    bright_sum = 0
    bright_n = 0
    for y in range(0, rgb.height, 2):
        for x in range(0, rgb.width, 2):
            if mp[x, y] > 0:
                r, g, b = rp[x, y]
                bright_sum += (r + g + b) / 3.0
                bright_n += 1
    avg_lum = (bright_sum / bright_n) if bright_n else 0
    if avg_lum > 190:
        grown = mask.filter(ImageFilter.MaxFilter(5))
        ring = Image.new("RGBA", rgb.size, (150, 146, 178, 255))
        ring.putalpha(grown.point(lambda v: int(v * 0.45)))
        card.alpha_composite(ring, (px_x, px_y))

    card.alpha_composite(ch, (px_x, px_y))
    print(f"    角色 {ch.width}x{ch.height} @ ({px_x},{px_y})  "
          f"左右留白={px_x}/{W - px_x - ch.width}  上下留白={px_y}/{H - px_y - ch.height}")

    # 四角点数：autopip = 按点数自动拼角标块
    if pip_path == "auto":
        block = build_pip_block(rank_label(rank), suit)
        block_path = os.path.join(os.path.dirname(out_path), "_pip_block.png")
        block.save(block_path)
        draw_pip_image(card, block_path)
    elif pip_path:
        draw_pip_image(card, pip_path)
    else:
        draw_corner(card, suit, rank, True)
        draw_corner(card, suit, rank, False)

    # 圆角裁切：卡外透明，放到深色背景上就是真正的圆角卡
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, W - 1 - inset, H - 1 - inset], radius=radius, fill=255)
    card = Image.composite(card, Image.new("RGBA", (W, H), (0, 0, 0, 0)), mask)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    card.save(out_path, "PNG")
    print(f"[ok] {out_path}  {W}x{H}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--suit", default="heart", choices=list(SUIT_SYM))
    ap.add_argument("--rank", type=int, default=3)
    ap.add_argument("--out", default=r"D:\zcode-work\godot\projects\prompt-arena\docs\shots\card-sample.png")
    ap.add_argument("--pip", default="", help="现成角标图（左上角），右下角自动旋转 180°")
    args = ap.parse_args()
    compose(args.src, args.suit, args.rank, args.out, args.pip)


if __name__ == "__main__":
    main()
