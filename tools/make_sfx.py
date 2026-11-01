#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""合成整套芯片风音效 + 一段循环 BGM（纯 Python，无外部依赖）。

为什么是合成而不是找素材：
- 像素卡牌游戏的听感基准就是 8-bit 机型：方波/三角波/白噪声三件套
- 无版权风险、无网络依赖、参数可随时重调
- 22050 Hz 单声道——与画风一致的"低采样"质感，文件也小

输出：assets/audio/sfx/*.wav + assets/audio/music/bgm_main.wav
"""

import math
import os
import random
import struct
import wave

SR = 22050
TAU = math.pi * 2.0
HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
SFX_DIR = os.path.join(PROJ, "assets", "audio", "sfx")
MUS_DIR = os.path.join(PROJ, "assets", "audio", "music")


def note(n: str) -> float:
    """'C4' / 'A#3' → 频率"""
    names = "C C# D D# E F F# G G# A A# B".split()
    i = 0
    while i < len(n) and (n[i].isalpha() or n[i] == "#"):
        i += 1
    pitch, octv = n[:i], int(n[i:])
    semis = names.index(pitch) + (octv - 4) * 12 - 9
    return 440.0 * (2.0 ** (semis / 12.0))


def env(t: float, dur: float, a=0.005, r=None) -> float:
    """打击乐器式包络：快起 + 指数衰减到结尾。"""
    if r is None:
        r = dur
    if t < a:
        return t / a
    return math.exp(-(t - a) / max(r * 0.35, 1e-4))


def square(f: float, dur: float, vol=0.5, duty=0.5, decay=None,
           vib_hz=0.0, vib_rate=5.0) -> list:
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        fi = f + (vib_hz * math.sin(TAU * vib_rate * t) if vib_hz else 0.0)
        ph += fi / SR
        v = 1.0 if (ph % 1.0) < duty else -1.0
        out.append(v * vol * env(t, dur, r=decay))
    return out


def tri(f: float, dur: float, vol=0.5, decay=None,
          vib_hz=0.0, vib_rate=5.0) -> list:
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        fi = f + (vib_hz * math.sin(TAU * vib_rate * t) if vib_hz else 0.0)
        ph += fi / SR
        p = ph % 1.0
        v = 4.0 * abs(p - 0.5) - 1.0
        out.append(v * vol * env(t, dur, r=decay))
    return out


def noise(dur: float, vol=0.4, decay=None) -> list:
    n = int(SR * dur)
    return [random.uniform(-1, 1) * vol * env(i / SR, dur, a=0.001, r=decay)
            for i in range(n)]


def glide(f0: float, f1: float, dur: float, vol=0.5, duty=0.5) -> list:
    """频率滑动的方波（选牌/取消选牌那声"哔~"）"""
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        k = i / max(n - 1, 1)
        f = f0 + (f1 - f0) * k
        ph += f / SR
        v = 1.0 if (ph % 1.0) < duty else -1.0
        out.append(v * vol * env(i / SR, dur, a=0.003))
    return out


def mix(*tracks) -> list:
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    peak = max(1e-6, max(abs(v) for v in out))
    if peak > 0.92:
        out = [v * 0.92 / peak for v in out]
    return out


def seq(events, total=None) -> list:
    """events = [(delay_sec, samples), ...]，把多段采样按时间轴叠到一条轨道"""
    if total is None:
        total = max(int((d + len(s) / SR) * SR) for d, s in events)
    out = [0.0] * total
    for d, s in events:
        base = int(d * SR)
        for i, v in enumerate(s):
            if base + i < total:
                out[base + i] += v
    return out


def arp(names, nd=0.07, wave=square, vol=0.5) -> list:
    evs = []
    for k, nm in enumerate(names):
        evs.append((k * nd, wave(note(nm), nd * 1.9, vol=vol)))
    return seq(evs)


def normalize(samples: list, peak: float = 0.85) -> list:
    m = max(1e-6, max(abs(v) for v in samples))
    if m > peak:
        k = peak / m
        samples = [v * k for v in samples]
    return samples


def save(name: str, samples: list, subdir: str = "sfx") -> None:
    samples = normalize(samples)
    d = os.path.join(PROJ, "assets", "audio", subdir)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32000))
                          for v in samples)
        w.writeframes(frames)
    print("[ok] %-24s %.2fs" % (name, len(samples) / SR))


def build_sfx() -> None:
    # ── UI ──
    save("ui_click", square(note("B5"), 0.06, vol=0.4, duty=0.25))
    save("card_select", glide(660, 990, 0.10, vol=0.45))
    save("card_deselect", glide(880, 587, 0.10, vol=0.4))
    save("discard", mix(noise(0.16, vol=0.30), glide(500, 220, 0.16, vol=0.18)))
    save("deal", mix(noise(0.07, vol=0.25), seq([(0.02, square(note("E5"), 0.06, vol=0.3))])))

    # ── 结算 ──
    save("score_tick", square(note("D6"), 0.035, vol=0.28, duty=0.3))
    save("score_land", mix(tri(note("G3"), 0.10, vol=0.5),
                           seq([(0.02, square(note("B5"), 0.16, vol=0.4))])))
    save("hand_small", arp(["C5", "E5", "G5"]))
    save("hand_big", mix(arp(["C5", "E5", "G5", "C6", "E6"], nd=0.075),
                         seq([(0.42, arp(["C6"], nd=0.12, vol=0.2))])))

    # ── 胜负 ──
    save("win", seq([
        (0.00, arp(["C5", "E5", "G5", "C6"], nd=0.11, vol=0.5)),
        (0.50, mix(square(note("C5"), 0.5, vol=0.30),
                   square(note("E5"), 0.5, vol=0.30),
                   square(note("G5"), 0.5, vol=0.30),
                   square(note("C6"), 0.5, vol=0.30))),
    ]))
    save("lose", seq([
        (0.00, tri(note("E4"), 0.18, vol=0.45)),
        (0.16, tri(note("C4"), 0.18, vol=0.45)),
        (0.32, tri(note("A3"), 0.36, vol=0.45)),
    ]))


def build_music() -> None:
    """bgm_main：68 秒大循环 · 「赌博秘境」式催眠。

    设计思路（要的就是让人不想停）：
    · 安达卢西亚进行 Am-G-F-E——一级级往下坠再拉回来，天然的"再来一把"感
    · 32 小节 AABA+回转的结构：循环点藏在回转小节里，听不出接缝
    · 八分音符琶音垫（chip shimmer）从头铺到尾—— hypnotic 底座
    · B 段换和弦 Lift 一下，A' 段主旋律升八度——重复里有变化
    · swing：反拍全部后拖 10%，赌场 lounge 的慵懒
    · 主旋律带 5Hz 振颤——微微的"晕"，像喝了两杯
    """
    bpm = 112.0
    beat = 60.0 / bpm
    bar = beat * 4
    bars = 32
    total = int(SR * bar * bars)
    sw = 0.10 * beat               # swing：反拍后拖量

    CH = {
        "Am": ["A2", "A3", "C4", "E4"],
        "G":  ["G2", "G3", "B3", "D4"],
        "F":  ["F2", "F3", "A3", "C4"],
        "E":  ["E2", "E3", "G#3", "B3"],
    }
    # 32 小节和声：前奏 A A B A' 回转，全部走 Am-G-F-E
    prog = (["Am", "G", "F", "E"] * 8)

    def sec(b):        # 小节号 → 段落
        if b < 4:  return "intro"
        if b < 12: return "A"
        if b < 20: return "B"
        if b < 28: return "A2"
        return "out"

    evs = []

    # ── 贝斯：每拍根音，第 4 个八分跳八度（walking 感）──
    for b in range(bars):
        if sec(b) == "out":      # 回转段：四分音符一步步走下来
            evs.append((b * bar, tri(note(CH[prog[b]][0]), beat * 0.9, vol=0.34)))
            continue
        root = note(CH[prog[b]][0])
        for e in range(8):
            t = b * bar + e * beat * 0.5 + (sw if e % 2 else 0.0)
            f = root * (2.0 if e % 4 == 3 else 1.0)
            evs.append((t, tri(f, beat * 0.42, vol=0.30)))

    # ── 和声垫：整小节，音量极低 ──
    for b in range(bars):
        if sec(b) == "intro":
            continue
        for nm in CH[prog[b]][1:]:
            evs.append((b * bar, tri(note(nm), bar * 0.96, vol=0.07)))

    # ── 琶音垫（chip shimmer）：八分音符滚和弦，A / A' 段铺满 ──
    ARP = {"Am": ["A4","C5","E5","C5"], "G": ["G4","B4","D5","B4"],
           "F": ["F4","A4","C5","A4"],  "E": ["E4","G#4","B4","G#4"]}
    for b in range(bars):
        if sec(b) not in ("A", "A2"):
            continue
        for e in range(8):
            t = b * bar + e * beat * 0.5 + (sw if e % 2 else 0.0)
            nm = ARP[prog[b]][e % 4] if e % 2 == 0 else ARP[prog[b]][3 - e % 4]
            oct_up = 2.0 if (sec(b) == "A2" and e >= 4) else 1.0
            evs.append((t, square(note(nm) * oct_up, beat * 0.4,
                                  vol=0.13, duty=0.3)))

    # ── 主旋律（hook）：带振颤的方波 ──
    def lead(t_beats, nm, dur_beats, vol=0.24, oct_up=False):
        evs.append((t_beats * beat,
                    square(note(nm) * (2.0 if oct_up else 1.0),
                           dur_beats * beat * 0.92, vol=vol, duty=0.35,
                           vib_hz=5.0, vib_rate=5.5)))

    # A 段（小节 4-11）：两个小节一句，跟着和声下坠
    A_PHRASES = [
        [("C5",1),("B4",1),("A4",2), ("B4",1),("D5",1),("B4",2)],      # Am→G
        [("A4",1),("C5",1),("A4",2), ("G#4",2),("E4",2)],              # F→E
        [("E5",1),("D5",1),("C5",2), ("B4",1),("D5",1),("G4",2)],      # Am→G
        [("C5",1),("A4",1),("F4",2), ("E4",3),("rest",1)],             # F→E
    ]
    for pi, phr in enumerate(A_PHRASES):
        t0 = (4 + pi * 2) * 4          # 小节起点（拍）
        for nm, d in phr:
            if nm != "rest":
                lead(t0, nm, d)
            t0 += d

    # B 段（12-19）：旋律飞起来
    B_PHRASES = [
        [("A4",2),("G4",2)], [("B4",2),("A4",2)],
        [("C5",1),("D5",1),("E5",2)], [("E5",4)],
        [("F5",2),("E5",2)], [("D5",2),("B4",2)],
        [("G#4",2),("B4",2)], [("E5",3),("rest",1)],
    ]
    for bi, phr in enumerate(B_PHRASES):
        t0 = (12 + bi) * 4
        for nm, d in phr:
            if nm != "rest":
                lead(t0, nm, d, vol=0.26)
            t0 += d

    # A' 段（20-27）：同一句 hook 升八度（音量压一点，不刺）
    for pi, phr in enumerate(A_PHRASES):
        t0 = (20 + pi * 2) * 4
        for nm, d in phr:
            if nm != "rest":
                lead(t0, nm, d, vol=0.17, oct_up=True)
            t0 += d

    # 回转（28-31）：鼓抽掉，旋律一句向上的 tag 拉回循环点
    for nm, d, off in [("C5",1,0),("D5",1,1),("E5",2,2),
                        ("D5",1,4),("B4",1,5),("E4",2,6)]:
        lead(30 * 4 + off, nm, d, vol=0.22)

    # ── 打击 ──
    for b in range(bars):
        s_ = sec(b)
        # kick：1、3；B/A' 加"2 的反拍"推一把
        for q in [0, 2]:
            evs.append((b * bar + q * beat, tri(70.0, 0.09, vol=0.42)))
        if s_ in ("B", "A2"):
            evs.append((b * bar + 1.5 * beat + sw, tri(62.0, 0.08, vol=0.30)))
        if s_ == "out":
            continue
        # hat：全部八分，反拍带 swing 且加重
        for e in range(8):
            t = b * bar + e * beat * 0.5 + (sw if e % 2 else 0.0)
            evs.append((t, noise(0.028, vol=0.09 if e % 2 else 0.06)))
        # 赌场脉冲：2、4 拍的高音木鱼
        for q in [1, 3]:
            evs.append((b * bar + q * beat,
                        square(note("E6"), 0.03, vol=0.05, duty=0.2)))
        # B 段军噪
        if s_ == "B":
            for q in [1, 3]:
                evs.append((b * bar + q * beat, noise(0.07, vol=0.16)))

    save("bgm_main", seq(evs, total=total), subdir="music")


def build_battle_sfx() -> None:
    """战斗特效四音（2026-11-01 主人钦定）：斩击/格挡/吃饭/敌受击重音"""
    # 斩击：高频噪声扫落 + 方波下滑（唰——）
    slash = mix(
        noise(0.14, vol=0.5, decay=0.9),
        [0.0] * 2 + glide(1500, 240, 0.13, vol=0.42, duty=0.3),
    )
    save("fx_slash", normalize(slash))

    # 格挡：低方波"铛" + 高三角"叮"（金属盾面）
    block = mix(
        square(note("A3"), 0.09, vol=0.5, decay=0.85),
        seq([(0.0, tri(note("E6"), 0.07, vol=0.4)),
             (0.05, tri(note("B6"), 0.1, vol=0.34))]),
    )
    save("fx_block", normalize(block))

    # 吃饭：两声可爱的 nom-nom（三角双音上扬再落）
    eat = seq([
        (0.0, tri(660, 0.06, vol=0.5)),
        (0.09, tri(500, 0.06, vol=0.5)),
        (0.18, tri(680, 0.05, vol=0.4)),
        (0.26, tri(520, 0.05, vol=0.4)),
    ])
    save("fx_eat", normalize(eat))

    # 敌受击：低噪声"咚" + 方波下坠（重拳命中）
    ehit = mix(
        noise(0.1, vol=0.5, decay=0.8),
        glide(320, 70, 0.14, vol=0.55, duty=0.4),
    )
    save("fx_ehit", normalize(ehit))

    # 敌防御：双层方波"嗡——"（蓄力感）
    edef = mix(
        square(note("E3"), 0.16, vol=0.4, duty=0.35, decay=0.8),
        square(note("B3"), 0.16, vol=0.3, duty=0.35, decay=0.85),
    )
    save("fx_edef", normalize(edef))


if __name__ == "__main__":
    random.seed(4242)
    build_sfx()
    build_battle_sfx()
    build_music()
    print("\n全部输出到 assets/audio/{sfx,music}/")
