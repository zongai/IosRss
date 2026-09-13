import Foundation

/// AI 摘要 / 解释相关纯逻辑与多步流程编排（网络经 AIRuntime 注入）
enum AIService {
    protocol Runtime: AnyObject {
        var aiOutputLanguage: AppLanguage { get }
        var defaultSummaryProviderID: UUID? { get }
        var defaultExplainProviderID: UUID? { get }
        var modelRoutingShortLimit: Int { get }
        func resolvedSummaryPrompt(for article: Article) -> String
        func callAIWithFailover(
            preferredID: UUID?,
            probeText: String,
            maxTokens: Int,
            preferStrongModel: Bool,
            buildPrompt: () -> String
        ) async throws -> (text: String, provider: AIProvider)
    }

    static func cleanSummaryText(_ text: String) -> String {
        let patterns = [
            #"^(\d+[\.\)、:：]|[(（]\d+[)）])\s*"#,
            #"^[-•●▪◦]\s+"#
        ]
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line -> String in
                var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                for re in regexes {
                    s = re.stringByReplacingMatches(
                        in: s,
                        range: NSRange(s.startIndex..., in: s),
                        withTemplate: ""
                    )
                }
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    static func generateSummary(article: Article, runtime: Runtime) async throws -> (text: String, providerName: String) {
        let content = String(HTMLUtils.stripTags(article.content.isEmpty ? article.summary : article.content).prefix(2500))
        let probe = [article.title, article.summary, article.content]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let template = runtime.resolvedSummaryPrompt(for: article)
        var prompt = template
            .replacingOccurrences(of: "{{lang}}", with: runtime.aiOutputLanguage.promptLabel)
            .replacingOccurrences(of: "{{title}}", with: article.title)
            .replacingOccurrences(of: "{{content}}", with: content)
        if !template.contains("{{title}}") && !template.contains("{{content}}") {
            prompt += "\n\n标题：\(article.title)\n\n内容：\(content)"
        }
        let strong = content.count > runtime.modelRoutingShortLimit
        let (raw, provider) = try await runtime.callAIWithFailover(
            preferredID: runtime.defaultSummaryProviderID,
            probeText: probe,
            maxTokens: 600,
            preferStrongModel: strong,
            buildPrompt: { prompt }
        )
        let base = cleanSummaryText(raw)
        if let enriched = try? await enrichSummaryWithBackground(
            summary: base, article: article, content: content,
            preferredID: provider.id, runtime: runtime
        ), !enriched.isEmpty {
            return (enriched, provider.name)
        }
        return (base, provider.name)
    }

    static func scanBackgroundGaps(
        summary: String, article: Article, content: String, runtime: Runtime
    ) async throws -> String {
        let lang = runtime.aiOutputLanguage.promptLabel
        let prompt = """
请对以下新闻/博客摘要做背景补全检查（用\(lang)回答）：

1. 找出首次出现但未说明身份的人名、机构名、专有名词
2. 找出时间表述模糊、可能引起误解的地方（如「最近」「据悉」；若原文有具体日期应指出）
3. 判断是否需要补充「前情提要」（是否为连续报道的后续）
4. 对以上问题，给出简短（不超过一句话）的背景补充建议，并标注建议插入的原句位置
5. 如果某项背景信息你不确定是否为最新/准确，标注「需核实」而不要直接编写

约束：
- 高优先级：直接影响理解主干事实的「这是谁 / 何时发生」
- 低优先级可省略：读者可自行检索且不影响结论的细节
- 博客主观观点须归因，勿写成客观事实
- 涉及现任职位、公司现状等「当前状态」若无原文依据，一律「需核实」
- 不要输出与摘要无关的长篇百科

标题：\(article.title)

摘要：
\(summary)

原文摘录：
\(String(content.prefix(1600)))
"""
        let (raw, _) = try await runtime.callAIWithFailover(
            preferredID: runtime.defaultExplainProviderID ?? runtime.defaultSummaryProviderID,
            probeText: summary + content,
            maxTokens: 500,
            preferStrongModel: true,
            buildPrompt: { prompt }
        )
        return cleanSummaryText(raw)
    }

    static func enrichSummaryWithBackground(
        summary: String, article: Article, content: String,
        preferredID: UUID?, runtime: Runtime
    ) async throws -> String {
        let gaps = try await scanBackgroundGaps(
            summary: summary, article: article, content: content, runtime: runtime
        )
        if gaps.contains("无明显") || gaps.contains("无需补充") || gaps.count < 12 {
            return summary
        }
        let lang = runtime.aiOutputLanguage.promptLabel
        let prompt = """
你是新闻编辑。在保持原意与篇幅的前提下，把「背景补充建议」中的高优先级信息，用\(lang)以轻量方式嵌入摘要原句。

嵌入方式（优先）：
- 括号、同位语、定语从句
- 不要写成单独的「背景：……」大段
- 低优先级细节可省略
- 标注了「需核实」的条目：不要编造写入摘要，可在文末单独用一行「待核实：…」列出（最多 2 条）
- 博客观点保持归因
- 连续报道若需要，用一句极简「前情：…」放在摘要最前
- 输出完整修订后的摘要正文；不要解释你的修改过程

原摘要：
\(summary)

背景补充建议：
\(gaps)

原文摘录（仅供核对，勿扩写原文没有的事实）：
\(String(content.prefix(1200)))
"""
        let (raw, _) = try await runtime.callAIWithFailover(
            preferredID: preferredID ?? runtime.defaultSummaryProviderID,
            probeText: summary,
            maxTokens: 700,
            preferStrongModel: true,
            buildPrompt: { prompt }
        )
        let cleaned = cleanSummaryText(raw)
        return cleaned.isEmpty ? summary : cleaned
    }

    static func generateBackgroundNotes(article: Article, runtime: Runtime) async throws -> String {
        let content = String(HTMLUtils.stripTags(article.content.isEmpty ? article.summary : article.content).prefix(1800))
        let summary = article.aiSummary ?? String(HTMLUtils.stripTags(article.summary).prefix(400))
        let gaps = try await scanBackgroundGaps(
            summary: summary.isEmpty ? article.title : summary,
            article: article,
            content: content,
            runtime: runtime
        )
        let lines = gaps.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let important = lines.filter {
            $0.contains("需核实") || $0.contains("前情") || $0.contains("人名") || $0.contains("机构")
        }
        let picked = (important.isEmpty ? lines : important).prefix(5)
        let text = picked.joined(separator: "\n")
        return text.isEmpty ? gaps : text
    }

    static func explainText(_ text: String, promptTemplate: String, runtime: Runtime) async throws -> String {
        let prompt = promptTemplate
            .replacingOccurrences(of: "{{lang}}", with: runtime.aiOutputLanguage.promptLabel)
            .replacingOccurrences(of: "{{text}}", with: text)
        let (raw, _) = try await runtime.callAIWithFailover(
            preferredID: runtime.defaultExplainProviderID ?? runtime.defaultSummaryProviderID,
            probeText: text,
            maxTokens: 500,
            preferStrongModel: true,
            buildPrompt: { prompt }
        )
        return cleanSummaryText(raw)
    }
}
