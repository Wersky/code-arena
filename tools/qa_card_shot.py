# -*- coding: utf-8 -*-
"""隐藏桌面卡面视觉验收：--shot=card（正/背两排）+ --patch-demo --tab=1。"""
import os
import sys
import time

sys.path.insert(0, os.path.expanduser("~/.zcode/skills/virtual-desktop/scripts"))
from hidden_desktop import HiddenDesktop  # noqa: E402

GODOT = r"D:\zcode-work\godot\engine\Godot_v4.7.2-stable_win64_console.exe"
PROJ = r"D:\zcode-work\godot\projects\prompt-arena"
OUT = os.path.join(PROJ, ".tmp")

JOBS = [
    ("card", ["--shot=card"], "qa_card.png"),
    ("demo", ["--patch-demo", "--tab=1", "--shot=patchdemo"], "qa_demo.png"),
]


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    hd = HiddenDesktop(name="ZCodeCardQA")
    rc = 0
    try:
        for tag, user_args, fname in JOBS:
            out = os.path.join(OUT, fname)
            if os.path.exists(out):
                os.remove(out)
            args = [
                "--path", PROJ,
                "--audio-driver", "Dummy",
                "--resolution", "1600x1000",
                "--",
            ] + user_args + ["--shotout=" + out]
            hd.launch(GODOT, args)
            t0 = time.time()
            while not os.path.exists(out) and time.time() - t0 < 70:
                time.sleep(1.0)
            ok = os.path.exists(out)
            print("[%s] %s" % (tag, "OK -> " + out if ok else "TIMEOUT"))
            if not ok:
                rc = 1
            time.sleep(1.0)
    finally:
        hd.close()
    return rc


if __name__ == "__main__":
    sys.exit(main())
