class_name ResponseGen
extends RefCounted
## 按你拼出的提示词，生成一段"像模像样的模型输出"。
##
## 纯表现层，不参与任何计分——但它是这个主题最直接的反馈：
## 你写的提示词，真的"回"了你一段东西。

const K := CardData.Kind

const OPENERS := [
	"好的，按你的要求：",
	"明白了，这是结果：",
	"根据你给的约束，我这样回答：",
	"收到，输出如下：",
]

const TASK_ANSWERS := {
	"写个函数": "```gdscript\nfunc to_camel(text: String) -> String:\n\tvar parts := text.split(\" \")\n\tvar out := parts[0]\n\tfor p in parts.slice(1):\n\t\tout += p.capitalize()\n\treturn out\n```",
	"抓出这个 bug": "问题出在第 42 行：你在判空前就解引用了 `result.data`。当 `data` 为 null 时会直接抛 NPE。\n修法是先取一次局部变量再判空。",
	"写封邮件": "主题：关于近期回款周期的说明\n\n您好：\n\n近期的到账延迟主要来自支付渠道的结算批次调整，我们已与渠道方确认，预计本周内完成全部补发。给您带来的不便，我们深表歉意。",
	"生成一段 SQL": "```sql\nSELECT u.id, COUNT(o.id) AS order_count, SUM(o.amount) AS total\nFROM users u\nJOIN orders o ON o.user_id = u.id\nWHERE o.created_at >= '2026-01-01'\nGROUP BY u.id\nHAVING SUM(o.amount) > 1000\nORDER BY total DESC;\n```",
	"写产品需求文档": "## 目标\n让用户在三次点击内完成一次配置。\n\n## 范围\n- 本期只做表单化配置，暂不支持导入\n- 不做版本回滚（放到二期）\n\n## 验收标准\n1. 新用户 5 分钟内完成首次配置\n2. 配置项错误率 < 2%",
	"列出风险清单": "1. 需求边界模糊，验收时大概率返工\n2. 依赖的下游接口没有 SLA\n3. 历史数据里有一半不符合新规则\n4. 迁移脚本没有回滚路径\n5. 上线窗口正好撞上季度结算",
	"解释这段代码": "这段代码做了三件事：读取配置 → 逐条做归一化 → 写回。\n其中归一化那步是幂等的，重复跑不会脏数据；写回那步没有加锁，并发调用会互相覆盖。",
	"设计一个 API": "```\nGET  /v1/orders/{id}      获取单个订单\nPOST /v1/orders          创建订单（需 Idempotency-Key）\nPATCH /v1/orders/{id}    部分更新\n```\n所有错误统一返回 `{code, message, trace_id}`，HTTP 状态码仍然保持语义化。",
	"翻译成英文": "Thank you for reaching out — we're sorry for the wait. Your refund has been issued and should land within 3–5 business days.",
	"写个正则": "```regex\n/^1[3-9]\\d{9}$/\n```",
	"做个可行性评估": "三个月内落地是可行的，但要接受两个前提：\n\n1. 范围必须砍到只做核心链路\n2. 底层存储的迁移脚本要提前两周开工\n\n不满足这两条，时间会翻倍。",
	"写封客服邮件": "已收到您的反馈，核实后确实存在结算延迟。我们已加急处理，预计 24 小时内到账，届时会有短信通知。",
	"总结这份文档": "1. 系统分三层：接入层 / 计算层 / 存储层\n2. 计算层是性能瓶颈，扩容手段只有加机器\n3. 存储层的数据有一致性问题，文档未给出修复方案",
	"头脑风暴十个点子": "1. 把评测结果做成时间轴\n2. 允许玩家上传自己的题库\n3. 每周一次「最难 prompt」挑战\n4. 失败案例自动归档成提示词模板\n5. 给道具加「组合发现」动画\n6. 双人协作解同一关\n7. 关卡按真实业务线命名\n8. 加入「提示词预算」限时玩法\n9. 结算画面做成终端打字机\n10. 开放自定义关卡编辑器",
	"写个单元测试": "```gdscript\nfunc test_camel():\n\tassert_eq(to_camel(\"hello world\"), \"helloWorld\")\n\tassert_eq(to_camel(\"a\"), \"a\")\n```",
	"改得更礼貌": "我们理解并尊重您这边的顾虑。这个方案目前确实还有一些细节需要对齐，方便的话我们约个时间细聊一下？",
}


static func compose(cards: Array[CardData], score: int, combos: Array[Dictionary]) -> String:
	if cards.is_empty():
		return "（没有提交任何提示词，模型在等你说话。）"

	var lines: Array[String] = []
	lines.append(OPENERS[randi() % OPENERS.size()])

	# 任务卡决定回答主体
	var body := ""
	for c in cards:
		if c.kind == K.TASK and TASK_ANSWERS.has(c.title):
			body = TASK_ANSWERS[c.title]
			break
	if body == "":
		body = _generic_body(cards)
	lines.append(body)

	# 格式卡决定呈现方式
	var as_json := false
	var as_table := false
	for c in cards:
		if c.kind == K.FORMAT:
			if c.title.contains("JSON"):
				as_json = true
			elif c.title.contains("表格"):
				as_table = true
	if as_json:
		lines.append("\n```json\n{ \"status\": \"ok\", \"score\": %d, \"confidence\": 0.86 }\n```" % score)
	elif as_table:
		lines.append("\n| 项 | 值 |\n| --- | --- |\n| 本次得分 | %d |" % score)

	# 约束卡决定尾注
	for c in cards:
		if c.kind == K.CONSTRAINT:
			match c.title:
				"标注不确定处":
					lines.append("\n（标注：涉及具体数字的部分我没有把握，仅按素材推断。）")
				"必须给出来源":
					lines.append("\n（来源：你提供的素材，未做外部检索。）")
				"不得编造事实":
					lines.append("\n（以上只使用了给定素材中的信息。）")
				"不超过 100 字":
					lines = lines.slice(0, 1)
				"只用通俗词":
					lines.append("\n（已尽量避免专业术语。）")
			break

	# 风险卡给出"翻车感"
	for c in cards:
		if c.risky:
			lines.append("\n※ 注意：这段回答里有我没能核实的内容，如果要对外用，请再确认一遍。")
			break

	if not combos.is_empty():
		var names: Array[String] = []
		for combo in combos:
			names.append(str(combo["name"]))
		lines.append("\n[命中牌型：%s]" % " · ".join(names))
	return "\n".join(lines)


static func _generic_body(cards: Array[CardData]) -> String:
	var kind_names: Array[String] = []
	for c in cards:
		kind_names.append(c.title)
	var persona := "按常规方式"
	for c in cards:
		if c.kind == K.PERSONA:
			persona = "以「%s」的身份" % c.title
			break
	return "%s处理了这件事，涉及的要素包括：%s。\n整体思路是先确认输入边界，再按既定格式输出，最后做一次自查。" % [
		persona, "、".join(kind_names)
	]
