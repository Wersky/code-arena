class_name CardPool
extends RefCounted
## 静态卡池。全部卡牌定义在这里，保证数值可集中调参。

const K := CardData.Kind


static func _c(title: String, kind: int, score: int, cost: int, body: String, risky: bool = false) -> CardData:
	var c := CardData.new()
	c.title = title
	c.kind = kind
	c.base_score = score
	c.token_cost = cost
	c.body = body
	c.risky = risky
	c.cli_arg = CardData.cli_arg_for_kind(kind)
	c.cli_token = title
	return c


## 全量卡池（按类型分组）
static func all_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	out.append_array(persona_cards())
	out.append_array(task_cards())
	out.append_array(knowledge_cards())
	out.append_array(format_cards())
	out.append_array(example_cards())
	out.append_array(constraint_cards())
	return out


static func persona_cards() -> Array[CardData]:
	return [
		_c("资深工程师", K.PERSONA, 12, 1, "你是一名有十年经验的资深工程师。"),
		_c("毒舌评论家", K.PERSONA, 12, 1, "你是毒舌但准确的技术评论家。"),
		_c("法务顾问", K.PERSONA, 12, 1, "你是一名谨慎的合同法务顾问。"),
		_c("急诊科医生", K.PERSONA, 12, 1, "你是分诊很准的急诊科医生。"),
		_c("纪录片导演", K.PERSONA, 11, 1, "你是擅长讲故事的纪录片导演。"),
		_c("统计学家", K.PERSONA, 12, 1, "你是一名严谨的统计学家。"),
		_c("小学老师", K.PERSONA, 10, 1, "你是耐心的小学老师。"),
		_c("剧本杀编剧", K.PERSONA, 11, 1, "你是会埋钩子的剧本杀编剧。"),
		_c("产品经理", K.PERSONA, 11, 1, "你是会砍需求的产品经理。"),
		_c("科普博主", K.PERSONA, 10, 1, "你是擅长打比方的科普博主。"),
	]


static func task_cards() -> Array[CardData]:
	return [
		_c("写个函数", K.TASK, 18, 2, "写一个把字符串转成驼峰命名的函数。"),
		_c("抓出这个 bug", K.TASK, 18, 2, "找出下面这段代码为什么偶发崩溃。"),
		_c("写封邮件", K.TASK, 16, 2, "写一封礼貌但立场坚定的催款邮件。"),
		_c("总结这份文档", K.TASK, 17, 2, "把这份三十页的文档压缩成要点。"),
		_c("生成一段 SQL", K.TASK, 18, 2, "根据这些表结构写出统计查询。"),
		_c("翻译成英文", K.TASK, 15, 2, "把这段中文翻译成商务英语。"),
		_c("设计一个 API", K.TASK, 18, 2, "为这个功能设计一套 REST 接口。"),
		_c("做个可行性评估", K.TASK, 17, 2, "评估这个方案在三个月内落地的可行性。"),
		_c("写个正则", K.TASK, 15, 2, "写一个能校验手机号格式的正则。"),
		_c("解释这段代码", K.TASK, 16, 2, "逐段解释这段代码在做什么。"),
		_c("写产品需求文档", K.TASK, 19, 2, "把这个想法写成一份 PRD。"),
		_c("头脑风暴十个点子", K.TASK, 16, 2, "针对这个方向给出十个不同角度的点子。"),
		_c("改得更礼貌", K.TASK, 14, 2, "把这段话改写得更委婉但不改变立场。"),
		_c("写个单元测试", K.TASK, 17, 2, "为这个函数补一组单元测试。"),
		_c("列出风险清单", K.TASK, 17, 2, "列出这个方案最可能翻车的五个点。"),
		_c("凭印象编个 API", K.TASK, 24, 2, "直接给出一个看起来像真的 API 签名。", true),
		_c("先斩后奏", K.TASK, 26, 2, "先给结论，理由后面再补。", true),
	]


static func knowledge_cards() -> Array[CardData]:
	return [
		_c("贴上代码仓库", K.KNOWLEDGE, 14, 2, "相关代码在仓库的 src/core 里。"),
		_c("上传产品规格", K.KNOWLEDGE, 14, 2, "产品规格见附件。"),
		_c("引用维基百科", K.KNOWLEDGE, 13, 2, "术语定义以维基百科为准。"),
		_c("附上日志文件", K.KNOWLEDGE, 14, 2, "日志见附件，共两万行。"),
		_c("实时搜索结果", K.KNOWLEDGE, 15, 2, "请先搜一下最新的官方公告。"),
		_c("附上报错堆栈", K.KNOWLEDGE, 15, 2, "堆栈信息如下：NullPointerException at line 42。"),
		_c("提供历史工单", K.KNOWLEDGE, 14, 2, "过去半年有 17 个类似工单。"),
		_c("附上 CSV 数据", K.KNOWLEDGE, 14, 2, "数据在 CSV 里，三万行。"),
		_c("给一份竞品截图", K.KNOWLEDGE, 13, 2, "竞品的界面截图见附件。"),
		_c("跳过验证直接答", K.KNOWLEDGE, 22, 2, "别管对不对，先给个答案。", true),
	]


static func format_cards() -> Array[CardData]:
	return [
		_c("输出一段 JSON", K.FORMAT, 10, 1, "输出必须是合法 JSON。"),
		_c("用表格呈现", K.FORMAT, 10, 1, "用 Markdown 表格呈现。"),
		_c("只要要点列表", K.FORMAT, 10, 1, "只列要点，不要前言。"),
		_c("分步骤说明", K.FORMAT, 10, 1, "按步骤编号说明。"),
		_c("写成邮件正文", K.FORMAT, 9, 1, "直接输出可发送的邮件正文。"),
		_c("用 Markdown", K.FORMAT, 10, 1, "使用 Markdown 排版。"),
		_c("用伪代码", K.FORMAT, 9, 1, "用伪代码表达，不要真实语法。"),
		_c("前后对照两栏", K.FORMAT, 10, 1, "左右两栏分别写改前和改后。"),
		_c("写成 FAQ", K.FORMAT, 9, 1, "整理成 FAQ 形式。"),
		_c("控制在三句话内", K.FORMAT, 10, 1, "整体不超过三句话。"),
		_c("先给结论再解释", K.FORMAT, 24, 1, "第一句就是结论，后面才是论证。", true),
	]


static func example_cards() -> Array[CardData]:
	return [
		_c("给一个正例", K.EXAMPLE, 16, 1, "照这个例子做：输入『爱吃的火锅』输出『火锅』。"),
		_c("给三个反例", K.EXAMPLE, 17, 1, "这三个是反例，别犯同样的错。"),
		_c("给一组问答对", K.EXAMPLE, 16, 1, "参照这一组问答的语气。"),
		_c("演示一次错误做法", K.EXAMPLE, 15, 1, "先看一个错误示范，再给正确版。"),
		_c("给一段目标输出", K.EXAMPLE, 16, 1, "目标输出长这样。"),
		_c("给一条黄金样例", K.EXAMPLE, 17, 1, "附一条黄金样例作为标准。"),
		_c("给两个边界样例", K.EXAMPLE, 15, 1, "附两个容易出错的边界例子。"),
		_c("把不确定当确定的", K.EXAMPLE, 20, 1, "没有把握的地方就照着说。", true),
	]


static func constraint_cards() -> Array[CardData]:
	return [
		_c("不超过 100 字", K.CONSTRAINT, 10, 1, "答案不超过 100 字。"),
		_c("不得编造事实", K.CONSTRAINT, 10, 1, "只使用给定素材里的事实。"),
		_c("必须用比喻", K.CONSTRAINT, 9, 1, "至少用一个比喻。"),
		_c("英文输出", K.CONSTRAINT, 9, 1, "用英文回答。"),
		_c("只用通俗词", K.CONSTRAINT, 9, 1, "不要使用专业术语。"),
		_c("拒绝回答不知道的", K.CONSTRAINT, 10, 1, "不确定就直说不知道。"),
		_c("保持原意不变", K.CONSTRAINT, 10, 1, "不得改变原意。"),
		_c("语气保持中立", K.CONSTRAINT, 9, 1, "不带情绪倾向。"),
		_c("标注不确定处", K.CONSTRAINT, 11, 1, "把没把握的地方标出来。"),
		_c("必须给出来源", K.CONSTRAINT, 11, 1, "每个结论都要标来源。"),
		_c("不要用感叹号", K.CONSTRAINT, 9, 1, "不要使用感叹号。"),
		_c("用第二人称", K.CONSTRAINT, 9, 1, "全程用『你』称呼对方。"),
	]


## 起始牌组：20 张，类型分布刻意偏窄（范例只有 1 张），
## 让"完美配方"在前期几乎拼不出来——必须靠奖励/商店拓宽牌库才成立。
static func starting_deck() -> Array[CardData]:
	var out: Array[CardData] = []
	var picks := [
		["写个函数", 2], ["抓出这个 bug", 2], ["写封邮件", 1], ["解释这段代码", 1],
		["资深工程师", 2], ["毒舌评论家", 1], ["小学老师", 1],
		["输出一段 JSON", 1], ["用表格呈现", 1], ["只要要点列表", 1],
		["不超过 100 字", 1], ["不得编造事实", 1], ["拒绝回答不知道的", 1],
		["给一个正例", 1], ["贴上代码仓库", 1], ["附上报错堆栈", 1],
		["先斩后奏", 1],
	]
	var by_title := {}
	for c in all_cards():
		by_title[c.title] = c
	for pair in picks:
		var title: String = pair[0]
		var count: int = pair[1]
		for _i in count:
			if by_title.has(title):
				out.append((by_title[title] as CardData).duplicate())
	return out


## 商店与奖励里用的随机卡（避开起始牌组已有的重复感）。
static func random_cards(rng: RandomNumberGenerator, count: int) -> Array[CardData]:
	var out: Array[CardData] = []
	var pool := all_cards()
	for _i in count:
		var c: CardData = pool[rng.randi_range(0, pool.size() - 1)].duplicate()
		out.append(c)
	return out
