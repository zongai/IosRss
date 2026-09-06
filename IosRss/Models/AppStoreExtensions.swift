import Foundation
import SwiftUI

extension AppStore {
    /// 依次尝试可用 AI Provider，全部失败再抛错
    func callAIWithFailover(
        preferredID: UUID?,
        probeText: String,
        maxTokens: Int = 500,
        buildPrompt: () -> String
    ) async throws -> (text: String, provider: AIProvider) {
        let providers = orderedAIProviders(preferredID: preferredID, forText: probeText)
        guard !providers.isEmpty else { throw TranslationError.noProvider }
        let prompt = buildPrompt()
        var lastError: Error = TranslationError.noProvider
        var triedAnyKey = false
        for provider in providers {
            let key = Keychain.load(key: "ai_key_\(provider.id)") ?? ""
            guard !key.isEmpty else { continue }
            triedAnyKey = true
            do {
                let raw = try await callAI(
                    prompt: prompt,
                    provider: provider,
                    apiKey: key,
                    maxTokens: maxTokens
                )
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty || Self.looksLikeAIErrorResponse(text) {
                    throw TranslationError.apiError(text.isEmpty ? "空响应" : text)
                }
                return (text, provider)
            } catch {
                lastError = error
                continue
            }
        }
        if !triedAnyKey { throw TranslationError.apiError("未配置任何可用的 API Key") }
        throw lastError
    }

    func orderedAIProviders(preferredID: UUID?, forText text: String) -> [AIProvider] {
        var ordered: [AIProvider] = []
        var seen = Set<UUID>()
        func append(_ p: AIProvider?) {
            guard let p, !seen.contains(p.id) else { return }
            seen.insert(p.id)
            ordered.append(p)
        }
        // blacklist may swap preferred
        append(resolveAIProvider(preferredID: preferredID, forText: text))
        if let preferredID {
            append(aiProviders.first(where: { $0.id == preferredID }))
        }
        append(aiProviders.first(where: { $0.id == defaultSummaryProviderID }))
        append(aiProviders.first(where: { $0.id == defaultTranslationProviderID }))
        append(aiProviders.first(where: { $0.id == defaultExplainProviderID }))
        for p in aiProviders { append(p) }
        return ordered
    }

    static func looksLikeAIErrorResponse(_ text: String) -> Bool {
        let t = text.lowercased()
        let markers = [
            "api key", "invalid_api_key", "incorrect api key",
            "rate limit", "quota", "insufficient_quota",
            "permission denied", "unauthorized", "authentication",
            "model not found", "does not exist", "overloaded"
        ]
        return markers.contains { t.contains($0) }
    }

    func renameFeed(_ feedID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        feeds[idx].title = trimmed
        for j in feeds[idx].articles.indices {
            feeds[idx].articles[j].feedTitle = trimmed
        }
        saveToStorage()
    }

    func setFeedFetchFullContent(_ feedID: UUID, enabled: Bool) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        feeds[idx].fetchFullContentEnabled = enabled
        saveToStorage()
    }

    func setFeedFetchComments(_ feedID: UUID, enabled: Bool) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        feeds[idx].fetchCommentsEnabled = enabled
        saveToStorage()
    }

    func isFullContentEnabled(for article: Article) -> Bool {
        feeds.first(where: { $0.id == article.feedID })?.fetchFullContentEnabled ?? true
    }

    func isCommentsEnabled(for article: Article) -> Bool {
        feeds.first(where: { $0.id == article.feedID })?.fetchCommentsEnabled ?? false
    }
}
