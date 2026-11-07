#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""真模型效果程序探测：用游戏里的 VISION_PROMPT 让模型写卡，收集原始输出。

用法：python -I tools/probe_programs.py [每模型请求数]
输出：tools/probe_out.jsonl（每行一条 {provider, model, prompt, latency_s, ok, content}）
随后用 tools/check_programs.gd 做本地编译校验。
"""
import json
import io
import os
import re
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG = os.path.expanduser("~/.zcode/v2/provider_config.json")
OUT = os.path.join(ROOT, "tools", "probe_out.jsonl")

PROMPTS = [
    "一只会喷火的机械猫",
    "一把能记住主人名字的旧钥匙",
    "会吞噬记忆的黑洞玩偶",
    "一只背着服务器机柜的乌龟",
    "能回溯三秒的怀表",
]


def load_prompt():
    p = os.path.join(ROOT, "scripts", "data", "wish_card_factory.gd")
    src = io.open(p, encoding="utf-8").read()
    m = re.search(r'const VISION_PROMPT := """(.*?)"""', src, re.S)
    if not m:
        raise SystemExit("VISION_PROMPT not found")
    return m.group(1)


def load_rules():
    d = json.load(io.open(CFG, encoding="utf-8"))
    pcr = d["config"]["providerConfigRules"]
    rules = pcr["providerRules"] if isinstance(pcr, dict) else pcr
    out = []
    for r in rules:
        c = r.get("config", {})
        if isinstance(c, str):
            c = json.loads(c)
        base = c.get("api", {}).get("baseUrl", "")
        key = c.get("access", {}).get("apiKey", "")
        mid = (c.get("personalModelIds") or [""])[0]
        if not base or not key or not mid:
            continue
        if "deepseek" in base or "dashscope" in base:
            out.append({"base": base.rstrip("/"), "key": key, "model": mid})
    return out


def call(rule, system, user, timeout=120):
    body = {
        "model": rule["model"],
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": "玩家描述：" + user},
        ],
        "temperature": 0.8,
        "max_tokens": 1200,
    }
    req = urllib.request.Request(
        rule["base"] + "/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json",
                 "Authorization": "Bearer " + rule["key"]},
        method="POST",
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            d = json.loads(r.read().decode("utf-8"))
        txt = d["choices"][0]["message"]["content"]
        return True, time.time() - t0, txt
    except Exception as e:
        return False, time.time() - t0, "ERR: %s" % e


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    system = load_prompt()
    rules = load_rules()
    print("providers:", [(r["model"], r["base"]) for r in rules])
    if not rules:
        raise SystemExit("no usable provider rule")
    with io.open(OUT, "w", encoding="utf-8") as f:
        for rule in rules:
            for i in range(n):
                user = PROMPTS[i % len(PROMPTS)]
                ok, dt, txt = call(rule, system, user)
                row = {"provider": rule["base"], "model": rule["model"],
                       "prompt": user, "latency_s": round(dt, 1),
                       "ok": ok, "content": txt}
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
                print("%-18s %-22s %5.1fs ok=%s len=%d" % (
                    rule["model"], user, dt, ok, len(txt)))
    print("saved:", OUT)


if __name__ == "__main__":
    main()
