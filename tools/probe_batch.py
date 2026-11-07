#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批量真模型探测：30 条多样化题材，验证扩展后 DSL 的表达力与合法率。"""
import json, io, os, re, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG = os.path.expanduser("~/.zcode/v2/provider_config.json")
OUT = os.path.join(ROOT, "tools", "probe_out_batch.jsonl")

PROMPTS = [
    "越打越猛还会让敌人变弱的战锤", "抽牌越多伤害越高的账本", "击杀后回血并抽牌的吸血鬼",
    "每回合开始加格挡的城墙", "受伤后反击并治疗自己的刺猬", "复制下一张牌并抽牌的复印机",
    "让敌人降智并中毒的毒雾", "残血时爆发并回血的狂战士", "弃牌越多越强的碎纸机",
    "每次受伤就变强的护甲", "序列结束时结算利息的银行", "受到伤害就叠加护甲的乌龟壳",
    "造成伤害后偷取算力的黑客", "回合开始时抽两张牌的闹钟", "杀敌后召唤分身的镜像",
    "手牌越多防御越厚的保险柜", "血量越低伤害越高的赌徒", "抽到时随机弃两张的盲盒",
    "下一张牌翻三倍的赌场轮盘", "回合结束时毒杀敌人的瘟疫", "连击三次后爆炸的连枷",
    "被打三次就反弹一切的镜子", "回复生命时也加攻击的圣水", "抽牌时给敌人挂易伤的乌鸦",
    "序列越长收尾越痛的长矛", "每回合开始自我修复的机器人", "击杀时偷取敌人护甲的食腐兽",
    "让敌人下次行动软弱的催眠师", "手牌越少伤害越高的孤勇者", "受到伤害就抽牌的受虐狂",
]


def load_prompt():
    p = os.path.join(ROOT, "scripts", "data", "wish_card_factory.gd")
    src = io.open(p, encoding="utf-8").read()
    m = re.search(r'const VISION_PROMPT := """(.*?)"""', src, re.S)
    return m.group(1)


def load_rule():
    d = json.load(io.open(CFG, encoding="utf-8"))
    rules = d["config"]["providerConfigRules"]["providerRules"]
    for r in rules:
        c = r.get("config", {})
        if isinstance(c, str):
            c = json.loads(c)
        base = c.get("api", {}).get("baseUrl", "")
        if "kuaipao" in base and c.get("personalModelIds"):
            return {"model": c["personalModelIds"][0],
                    "base": base.rstrip("/"), "key": c["access"]["apiKey"]}
    raise SystemExit("no kuaipao rule")


def main():
    system = load_prompt()
    rule = load_rule()
    print("model:", rule["model"], flush=True)
    f = io.open(OUT, "w", encoding="utf-8")
    done = 0
    for p in PROMPTS:
        body = {"model": rule["model"],
                "messages": [{"role": "system", "content": system},
                             {"role": "user", "content": "玩家描述：" + p}],
                "max_tokens": 4000, "temperature": 0.8}
        req = urllib.request.Request(
            rule["base"] + "/chat/completions", data=json.dumps(body).encode("utf-8"),
            headers={"Content-Type": "application/json",
                     "Authorization": "Bearer " + rule["key"]}, method="POST")
        t0 = time.time()
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                dd = json.loads(r.read().decode("utf-8"))
            txt = dd["choices"][0]["message"].get("content") or ""
            ok = True
        except Exception as e:
            txt, ok = "ERR: %s" % e, False
        dt = time.time() - t0
        f.write(json.dumps({"model": rule["model"], "provider": rule["base"],
                            "prompt": p, "ok": ok, "latency_s": round(dt, 1),
                            "content": txt}, ensure_ascii=False) + "\n")
        f.flush()
        done += 1
        print("[%d/%d] %-24s %5.1fs ok=%s" % (done, len(PROMPTS), p, dt, ok), flush=True)
    f.close()
    print("BATCH DONE", flush=True)


if __name__ == "__main__":
    main()
