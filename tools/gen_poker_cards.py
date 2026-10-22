#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""批量生成德州扑克卡面：4 位 AI娘 × 4 种花色 = 16 张。

每张是竖版满幅卡图（AI娘居中、花色主题背景），点数与花色符号由游戏程序绘制。
输出到临时目录，再由 pixelize_poker_cards.py 后处理进项目。

用法：
    python gen_poker_cards.py                 # 全部 16 张，并发 4
    python gen_poker_cards.py --only heart    # 只生成某个花色
    python gen_poker_cards.py --only deepdeek # 只生成某位 AI娘
"""

import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

GEN = r"D:\zcode-work\pictures\gen.py"
GEN_OUT = r"D:\zcode-work\pictures\output"
ART = r"D:\zcode-work\godot\projects\prompt-arena\assets\art"
OUT = os.path.join(tempfile.gettempdir(), "poker_arena_raw")

# 4 位 AI娘：外观 + 主色（参考图走 i2i，保证同一角色跨花色不漂）
AIS = {
    "deepdeek": dict(
        ref="ai-deepdeek.png",
        look="a calm anime girl with long deep-blue hair, glowing cyan circuit traces in her hair, "
             "a navy high-collar jacket, cool and composed expression",
        accent="cyan and deep navy",
    ),
    "kweno": dict(
        ref="ai-kweno.png",
        look="a warm anime girl with golden-blonde hair tied in a loose bun, amber eyes, "
             "an ivory and gold embroidered top, gentle confident smile",
        accent="gold and warm cream",
    ),
    "chatppt": dict(
        ref="ai-chatppt.png",
        look="a friendly anime girl with pink twin-tail hair, magenta eyes, a rose-pink hoodie "
             "with a headset around her neck, bright cheerful expression",
        accent="rose pink and magenta",
    ),
    "grock": dict(
        ref="ai-grock.png",
        look="a sharp anime girl with short cropped green hair, jade eyes, a dark tactical jacket "
             "and a slim headset, smirking confident expression",
        accent="jade green and charcoal",
    ),
}

# 4 种花色：背景世界 + 光 + 色板
SUITS = {
    "heart": dict(
        name_cn="红心",
        env="a cathedral of rose petals, floating heart-shaped light motes, warm crimson drapery",
        light="warm rose rim light from below, soft red glow",
        pal="deep crimson, rose, and warm gold",
        prop="heart-shaped emblems and rose vines",
    ),
    "diamond": dict(
        name_cn="方块",
        env="a crystal cavern of ruby diamond shards, faceted orange gems floating",
        light="sharp amber side light with hard gem sparkles",
        pal="burnt orange, ruby, and amber",
        prop="diamond-shaped crystals and faceted shards",
    ),
    "spade": dict(
        name_cn="黑桃",
        env="a midnight sky over a silent city, cold silver spade emblems floating",
        light="cold moonlight from above, blue-black shadows",
        pal="midnight black, cold silver, and steel blue",
        prop="spade-shaped emblems and star charts",
    ),
    "club": dict(
        name_cn="梅花",
        env="an overgrown dark greenhouse, ivy and three-leaf clover emblems",
        light="dim emerald glow through leaves, deep shadows",
        pal="dark emerald, charcoal, and moss",
        prop="three-leaf club emblems and ivy vines",
    ),
}


def _newest_output(name: str) -> str:
    """在 gen.py 的输出目录里找 <日期>-<name>.png（取最新一张）。"""
    hits = sorted(glob.glob(os.path.join(GEN_OUT, f"*-{name}.png")),
                  key=os.path.getmtime, reverse=True)
    return hits[0] if hits else ""


def build_prompt(ai_key: str, suit_key: str) -> dict:
    ai = AIS[ai_key]
    su = SUITS[suit_key]
    return dict(
        subject=f"{ai['look']}, bust portrait, centered, facing the viewer",
        action=f"standing still and looking straight at the camera, shoulders squared",
        composition=("vertical trading-card illustration, one character centered in the middle of the frame, "
                     "full-bleed background covering every corner edge to edge, "
                     f"{su['prop']} arranged symmetrically behind her, "
                     "keep the top-left and bottom-right corners visually calm and darker "
                     "so card rank pips stay readable"),
        environment=su["env"],
        lighting=f"{su['light']}, strong rim light separating her from the background",
        materials=(f"crisp 16-bit pixel art, hard-edged pixel clusters, limited palette of {su['pal']}, "
                   f"{ai['accent']} accents, dithered shading, no text, no letters, no numbers, no border"),
    )


def run_one(ai_key: str, suit_key: str) -> tuple:
    p = build_prompt(ai_key, suit_key)
    name = f"{ai_key}-{suit_key}"
    cmd = [
        sys.executable, GEN,
        "--name", name,
        "--style", "pixel-art",
        "--model", "gpt-image-2.5-1k",
        "--ar", "2:3",
        "--ref", os.path.join(ART, AIS[ai_key]["ref"]),
        "--subject", p["subject"],
        "--action", p["action"],
        "--composition", p["composition"],
        "--environment", p["environment"],
        "--lighting", p["lighting"],
        "--materials", p["materials"],
    ]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                       timeout=900)
    ok = r.returncode == 0
    # gen.py 固定写到 pictures/output/<日期>-<name>.png，这里搬家到临时目录
    if ok:
        src = _newest_output(name)
        if src:
            shutil.move(src, os.path.join(OUT, f"{name}.png"))
        else:
            ok = False
            print(f"  ! 找不到 {name} 的输出文件")
    print(("[OK]   " if ok else "[FAIL] ") + name)
    if not ok:
        print((r.stdout or "")[-800:])
        print((r.stderr or "")[-800:])
    return (ai_key, suit_key, ok)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="只生成某个 ai 或花色")
    ap.add_argument("--workers", type=int, default=2)
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    jobs = []
    for ai_key in AIS:
        for suit_key in SUITS:
            if args.only and args.only not in (ai_key, suit_key):
                continue
            jobs.append((ai_key, suit_key))
    if not jobs:
        print("没有匹配的任务")
        return
    print(f"共 {len(jobs)} 张 → {OUT}（并发 {args.workers}）")
    fails = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        for ai_key, suit_key, ok in ex.map(lambda j: run_one(*j), jobs):
            if not ok:
                fails.append(f"{ai_key}-{suit_key}")
    print(f"\n完成 {len(jobs) - len(fails)}/{len(jobs)}")
    if fails:
        print("失败：" + ", ".join(fails))


if __name__ == "__main__":
    main()
