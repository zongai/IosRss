import Foundation

// MARK: - Google Translate (free unofficial endpoint)

enum GoogleTranslate {
    static func translate(text: String, targetLang: String = "zh") async throws -> String {
        let escaped = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let urlStr = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(targetLang)&dt=t&q=\(escaped)"
        guard let url = URL(string: urlStr) else { throw TranslationError.apiError("无效的URL") }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
              let first = json.first as? [[Any]] else {
            throw TranslationError.apiError("解析响应失败")
        }
        let result = first.compactMap { $0.first as? String }.joined()
        return result.isEmpty ? text : result
    }
}

// MARK: - Microsoft Translator

enum MicrosoftTranslate {
    static func translate(text: String, apiKey: String, targetLang: String = "zh-Hans") async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 Microsoft Translator API Key") }
        let url = URL(string: "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to=\(targetLang)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.httpBody = try? JSONEncoder().encode([["Text": text]])
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Response: Decodable {
            struct Translation: Decodable { let text: String; let to: String }
            let translations: [Translation]
        }
        if let results = try? JSONDecoder().decode([Response].self, from: data),
           let first = results.first?.translations.first {
            return first.text
        }
        throw TranslationError.apiError("Microsoft Translator 返回无效响应")
    }
}

// MARK: - AI Translation

enum AITranslate {
    static func translate(text: String, provider: AIProvider, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        let prompt = "请将以下内容翻译成中文，只输出译文，不要解释：\n\n\(text)"
        return try await callOpenAICompatible(prompt: prompt, provider: provider, apiKey: apiKey)
    }
}

// MARK: - AI Summary

enum AISummary {
    static func summarize(article: Article, provider: AIProvider, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        let content = article.content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let prompt = "请用3-5句话概括以下文章的核心内容，用中文回答，每句话用换行分隔：\n\n标题：\(article.title)\n\n内容：\(content.prefix(2000))"
        return try await callOpenAICompatible(prompt: prompt, provider: provider, apiKey: apiKey)
    }
}

// MARK: - OpenAI-Compatible API Call

func callOpenAICompatible(prompt: String, provider: AIProvider, apiKey: String) async throws -> String {
    let baseURL = provider.baseURL.hasSuffix("/") ? String(provider.baseURL.dropLast()) : provider.baseURL
    guard let url = URL(string: "\(baseURL)/chat/completions") else {
        throw TranslationError.apiError("无效的 Base URL")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    let body: [String: Any] = [
        "model": provider.model,
        "messages": [["role": "user", "content": prompt]],
        "max_tokens": 500
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw TranslationError.apiError("API 错误 \(http.statusCode): \(msg.prefix(200))")
    }
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    struct Resp: Decodable { let choices: [Choice] }
    guard let resp = try? JSONDecoder().decode(Resp.self, from: data),
          let content = resp.choices.first?.message.content else {
        throw TranslationError.apiError("解析 AI 响应失败")
    }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}
