import Foundation

// MARK: - DeepL

enum DeepLTranslate {
    /// DeepL Free API Key 通常以 ":fx" 结尾，会自动使用对应的免费端点
    static func translate(text: String, apiKey: String, targetLang: String = "ZH") async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 DeepL API Key") }

        let isFreeKey = apiKey.hasSuffix(":fx")
        let baseURL = isFreeKey
            ? "https://api-free.deepl.com/v2/translate"
            : "https://api.deepl.com/v2/translate"

        guard let url = URL(string: baseURL) else {
            throw TranslationError.apiError("无效的 DeepL URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "text": [text],
            "target_lang": targetLang
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranslationError.apiError("DeepL API 错误 \(http.statusCode): \(msg.prefix(200))")
        }

        struct Translation: Decodable {
            let text: String
            let detected_source_language: String?
        }
        struct Resp: Decodable { let translations: [Translation] }

        guard let resp = try? JSONDecoder().decode(Resp.self, from: data),
              let first = resp.translations.first else {
            throw TranslationError.apiError("解析 DeepL 响应失败")
        }

        return first.text
    }
}

// MARK: - Google Translate (free unofficial endpoint)

enum GoogleTranslate {
    static func translate(text: String, targetLang: String = "zh") async throws -> String {
        let escaped = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let urlStr = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(targetLang)&dt=t&q=\(escaped)"
        guard let url = URL(string: urlStr) else {
            throw TranslationError.apiError("无效的URL")
        }

        var request = URLRequest(url: url)
        // 部分网络环境下没有 UA 会被拦截，加上常见浏览器 UA 更稳妥
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let raw = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw TranslationError.apiError("Google 翻译请求失败 (状态码 \(http.statusCode)): \(raw)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let firstElement = json.first as? [Any] else {
            let raw = String(data: data, encoding: .utf8)?.prefix(200) ?? "空响应"
            throw TranslationError.apiError("解析响应失败: \(raw)")
        }

        // 逐个元素安全解析，跳过 NSNull 或其他非数组项，避免因单个字段异常导致整体失败
        let result = firstElement.compactMap { segment -> String? in
            guard let segArray = segment as? [Any],
                  let text = segArray.first as? String else { return nil }
            return text
        }.joined()

        if result.isEmpty {
            let raw = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw TranslationError.apiError("解析响应失败，原始返回: \(raw)")
        }

        return result
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

// MARK: - Gemini

enum GeminiTranslate {
    static func translate(text: String, apiKey: String, targetLang: String = "中文", model: String = "gemini-2.0-flash") async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 Gemini API Key") }

        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlStr) else {
            throw TranslationError.apiError("无效的 Gemini URL")
        }

        let prompt = "请将以下内容翻译成\(targetLang)，只输出译文，不要解释，不要添加任何前缀或引号：\n\n\(text)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranslationError.apiError("Gemini API 错误 \(http.statusCode): \(msg.prefix(200))")
        }

        struct Part: Decodable { let text: String }
        struct Content: Decodable { let parts: [Part] }
        struct Candidate: Decodable { let content: Content }
        struct Resp: Decodable { let candidates: [Candidate] }

        guard let resp = try? JSONDecoder().decode(Resp.self, from: data),
              let text = resp.candidates.first?.content.parts.first?.text else {
            let raw = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw TranslationError.apiError("解析 Gemini 响应失败: \(raw)")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
