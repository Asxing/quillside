import Foundation

/// Read-only compatibility for the former six-field role format.
struct LegacyAgentProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var audience = ""
    var purpose = ""
    var perspective = ""
    var style = ""
    var quality = ""
    var instructions = ""
    var skillIDs: [String] = []
    var skillOperations: Set<AgentOperation> = [.rewrite, .revision, .summarize, .explain]
    var actionIDs: [UUID] = []
    var revision = 1
    var isLegacy = false

    static func presetsV1(skillIDs: [String] = []) -> [Self] {
        [Self(id: UUID(uuidString: "6247E980-18DE-4B89-8000-000000000001")!, name: "公众号",
              audience: "对该主题感兴趣、未必熟悉专业术语的目标读者", purpose: "让读者理解为什么值得读，并讲清观点、依据与边界。",
              perspective: "从读者的问题、已有认知与阅读体验组织材料，保留作者立场。",
              style: "自然、具体、克制；过渡顺畅，必要术语先解释；按内容决定结构，不强套模板。",
              quality: "读者能说清核心观点与依据；没有空泛夸大、标题党、伪造故事或未被要求的营销号召。", skillIDs: skillIDs),
         Self(id: UUID(uuidString: "6247E980-18DE-4B89-8000-000000000002")!, name: "个人笔记",
              audience: "现在以及以后回顾笔记的自己", purpose: "让记录容易理解、复习，并能继续思考。",
              perspective: "保留核心概念、机制、上下文和个人疑问；区分原记录、推断、待确认问题。",
              style: "清晰、紧凑，按需要梳理层次和因果；保持个人声音，不把随手记录改成正式文章。",
              quality: "关键信息可回顾，疑问和不确定性没有被抹去；不新增未经证实的结论。", skillIDs: skillIDs),
         Self(id: UUID(uuidString: "6247E980-18DE-4B89-8000-000000000003")!, name: "汇报",
              audience: "管理者、项目负责人和需要作决策的人", purpose: "让读者快速理解进展、影响、风险与需要作出的决策。",
              perspective: "从整体目标与优先级审视材料，用已有信息连接目标、结果、影响和待决策事项。",
              style: "专业、结论先行、具体简洁；指标口径清楚，不用大词代替信息，不机械填满栏目。",
              quality: "有事实依据，建议和待补充项明确标注；禁止编造战略目标、收益、完成率、风险评级、负责人和截止时间。", skillIDs: skillIDs)]
    }
    static func presets(skillIDs: [String] = []) -> [Self] {
        var profiles = presetsV1(skillIDs: skillIDs)
        profiles[0].style = "面向读者的短文：开头从材料中真实存在的变化或疑问切入，说明读者为什么值得关心；随后用具体证据解释，再自然引出限制与下一步。用完整句和自然转折串联，不使用‘观察：/边界：/待确认：’等笔记标签或复盘清单。不得虚构读者经历或新增故事。"
        profiles[0].quality = "即使固定段落数，也要重写开头与段内信息顺序，让陌生读者先理解问题与意义，再看到证据和限制；不能只删形容词或同义替换。不做标题党、不煽情、不虚构故事数据和引用；严守所有用户批注。"
        profiles[1].style = "供自己回顾的工作笔记：优先将信息整理为观察、依据、边界、待确认、下一步等适用类别；给每个已有段落加简短信息标签，用短句或分号压缩重复过渡。保留原有段落数量时把标签写在段首同一行，不另起标题行。只选材料实际支持的类别，不机械补空栏目。"
        profiles[1].quality = "扫一眼就能区分已知事实、判断依据、未知事项与待办；保留自己的疑问和‘不确定’。不要写成对外文章的引入、互动问句、铺垫或结尾升华；不能仅把原文换成更通顺的四段文章。"
        profiles[0].revision = 2; profiles[1].revision = 2
        return profiles
    }
    var rolePrompt: String {
        [("目标读者", audience), ("写作目的", purpose), ("判断视角", perspective),
         ("表达风格", style), ("质量标准", quality), ("补充规则", instructions)]
            .filter { !$0.1.isEmpty }.map { $0.0 + "：" + $0.1 }.joined(separator: "\n\n")
    }
    var migrated: AgentProfile {
        .init(id: id, name: name, prompt: rolePrompt, skillIDs: skillIDs,
              skillOperations: skillOperations, actionIDs: actionIDs, revision: revision, isLegacy: isLegacy)
    }
}
