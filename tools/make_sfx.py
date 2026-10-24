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


def square(f: float, dur: float, vol=0.5, duty=0.5, decay=None) -> list:
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        ph += f / SR
        v = 1.0 if (ph % 1.0) < duty else -1.0
        out.append(v * vol * env(i / SR, dur, r=decay))
    return out


def tri(f: float, dur: float, vol=0.5, decay=None) -> list:
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        ph += f / SR
        p = ph % 1.0
        v = 4.0 * abs(p - 0.5) - 1.0
        out.append(v * vol * env(i / SR, dur, r=decay))
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


def save(name: str, samples: list, subdir: str = "sfx") -> None:
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
    """bgm_main：8 小节循环，C 大调，118 BPM。
    三角波贝斯（每拍）+ 方波主旋律 + 白噪打击（反拍 hat）。
    结尾对齐小节线，无缝循环。
    """
    bpm = 118.0
    beat = 60.0 / bpm                     # 一拍的秒数
    bar = beat * 4
    total_bars = 8
    total = int(SR * bar * total_bars)

    # 和弦进行：C  Am  F  G ｜ C  Am  F  G（卡牌游戏的"稳"）
    chords = [
        ["C3", "E3", "G3"],
        ["A2", "C3", "E3"],
        ["F2", "A2", "C3"],
        ["G2", "B2", "D3"],
    ] * 2

    # 主旋律（音名, 起拍, 时值拍数）——五声为主，避免难听的半音碰撞
    melody = [
        ("G4", 0.0, 0.5), ("C5", 0.5, 0.5), ("E5", 1.0, 1.0), ("D5", 2.0, 0.5),
        ("C5", 2.5, 0.5), ("G4", 3.0, 1.0),
        ("A4", 4.0, 0.5), ("C5", 4.5, 0.5), ("E5", 5.0, 1.0), ("A4", 6.0, 1.0),
        ("G4", 7.0, 1.0), ("E4", 8.0, 1.0),
        ("F4", 8.0, 0.5), ("A4", 8.5, 0.5), ("C5", 9.0, 1.0), ("A4", 10.0, 0.5),
        ("G4", 10.5, 0.5), ("F4", 11.0, 1.0),
        ("G4", 12.0, 0.5), ("B4", 12.5, 0.5), ("D5", 13.0, 1.0), ("B4", 14.0, 0.5),
        ("G4", 14.5, 0.5), ("C5", 15.0, 1.0),
        ("E5", 16.0, 0.5), ("G5", 16.5, 0.5), ("E5", 17.0, 1.0), ("C5", 18.0, 0.5),
        ("D5", 18.5, 0.5), ("E5", 19.0, 1.0),
        ("A4", 20.0, 1.0), ("C5", 21.0, 0.5), ("B4", 21.5, 0.5), ("A4", 22.0, 0.5),
        ("G4", 22.5, 0.5), ("E4", 23.0, 1.0),
        ("F4", 24.0, 0.5), ("A4", 24.5, 0.5), ("C5", 25.0, 1.0), ("D5", 26.0, 0.5),
        ("C5", 26.5, 0.5), ("A4", 27.0, 1.0),
        ("B4", 28.0, 0.5), ("D5", 28.5, 0.5), ("G5", 29.0, 1.0), ("E5", 30.0, 0.5),
        ("D5", 30.5, 0.5), ("C5", 31.0, 1.0),
    ]

    evs = []
    # 贝斯：每小节根音 ×4 拍（八分音符律动）
    for b in range(total_bars):
        root = chords[b % len(chords)][0]
        for e in range(8):
            t = b * bar + e * beat * 0.5
            f = note(root) * (2.0 if e % 4 == 3 else 1.0)
            evs.append((t, tri(f, beat * 0.42, vol=0.30)))

    # 和声垫：每小节三和弦整小节（音量很低）
    for b in range(total_bars):
        for nm in chords[b % len(chords)]:
            evs.append((b * bar, tri(note(nm) * 2.0, bar * 0.96, vol=0.08)))

    # 主旋律
    for nm, start_beat, dur_beats in melody:
        evs.append((start_beat * beat,
                    square(note(nm), dur_beats * beat * 0.9, vol=0.22, duty=0.35)))

    # 打击：每拍 kick（低频短三角）+ 反拍 hat（白噪）
    for b in range(total_bars):
        for q in range(4):
            t = b * bar + q * beat
            evs.append((t, tri(70.0, 0.09, vol=0.42)))
            evs.append((t + beat * 0.5, noise(0.03, vol=0.10)))

    save("bgm_main", seq(evs, total=total), subdir="music")


if __name__ == "__main__":
    random.seed(4242)
    build_sfx()
    build_music()
    print("\n全部输出到 assets/audio/{sfx,music}/")
