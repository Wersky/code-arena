# -*- coding: utf-8 -*-
"""为 Web 导出剥离 llm_config.gd 里的内置凭据。

用法：
    python tools/strip_builtin_keys.py strip   # 清空两个 const（原地改）
    python tools/strip_builtin_keys.py check   # 检查是否已清空
    python tools/strip_builtin_keys.py restore <备份文件>

为什么需要（2026-11-18 实测）：
    BUILTIN_KEY_OBF / BUILTIN_IMG_KEY_OBF 是 const，即使运行时走
    OS.has_feature("web") 的代理分支，它们仍会被编进 game.pck。
    Godot 4 的 pck 内部块是 zstd 压缩（不是 zlib），
    解压后配合 _MASK 即可还原出真实 key —— 浏览器能下载 pck，等于公开。
"""

import io
import re
import sys

CFG = "scripts/llm/llm_config.gd"

KEY_RE = re.compile(r'(const\s+BUILTIN_KEY_OBF\s*:=\s*)"[^"]*"')
IMG_RE = re.compile(r'(const\s+BUILTIN_IMG_KEY_OBF\s*:=\s*)"[^"]*"')
STRIPPED_MARK = 'const BUILTIN_KEY_OBF := ""'


def read(path):
    with io.open(path, encoding="utf-8", newline="") as f:
        return f.read()


def write(path, text):
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def cmd_strip(path):
    src = read(path)
    out, n1 = KEY_RE.subn(r'\1""', src)
    out, n2 = IMG_RE.subn(r'\1""', out)
    if n1 == 0 or n2 == 0:
        print(f"[FAIL] 只替换了 KEY={n1} IMG={n2} 处，模式不匹配，未改动文件")
        return 1
    if out == src:
        print("[SKIP] 已经是清空状态")
        return 0
    write(path, out)
    print(f"[OK] 已清空 {n1 + n2} 个内置凭据常量")
    return 0


def cmd_check(path):
    src = read(path)
    ok = STRIPPED_MARK in src
    empties = len(re.findall(r'const\s+BUILTIN_(?:IMG_)?KEY_OBF\s*:=\s*""', src))
    print(f"KEY_OBF 已清空: {ok}   （共 {empties}/2 个为空）")
    if not ok or empties < 2:
        leaked = KEY_RE.search(src) or IMG_RE.search(src)
        if leaked:
            print("[FAIL] 仍有未清空的凭据常量，不能导出 Web 版")
        return 1
    print("[PASS] 两个凭据常量均为空")
    return 0


def cmd_restore(path, bak):
    src = read(bak)
    write(path, src)
    print(f"[OK] 已从 {bak} 还原")
    return 0


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "check"
    target = sys.argv[2] if len(sys.argv) > 2 else CFG
    if action == "strip":
        sys.exit(cmd_strip(target))
    if action == "check":
        sys.exit(cmd_check(target))
    if action == "restore":
        # 用法：restore <备份文件> [目标文件]
        # 备份在前、目标在后（与 cp 一致）；目标省略时用默认 CFG
        if len(sys.argv) < 3:
            print("用法: strip_builtin_keys.py restore <备份> [目标]")
            sys.exit(1)
        bak = sys.argv[2]
        dst = sys.argv[3] if len(sys.argv) > 3 else CFG
        sys.exit(cmd_restore(dst, bak))
    print(__doc__)
    sys.exit(1)
