import Foundation

// MARK: - DeepL

enum DeepLTranslate {
    /// DeepL Free API Key 通常以 ":fx" 结尾，会自动使用对应的免费端点
    static func translate(text: String, apiKey: String, targetLang: String = "ZH") async throws -> String {
        let all = try await translate(texts: [text], apiKey: apiKey, targetLang: targetLang)
        guard let first = all.first, !first.isEmpty else {
            throw TranslationError.apiError("解析 DeepL 响应失败")
        }
        return first
    }

    /// 一次请求翻译多段文本，顺序与输入一致
    static func translate(texts: [String], apiKey: String, targetLang: String = "ZH") async throws -> [String] {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 DeepL API Key") }
        guard !texts.isEmpty else { return [] }

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
            "text": texts,
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
              resp.translations.count == texts.count else {
            throw TranslationError.apiError("解析 DeepL 响应失败")
        }

        return resp.translations.map(\.text)
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
        let all = try await translate(texts: [text], apiKey: apiKey, targetLang: targetLang)
        guard let first = all.first, !first.isEmpty else {
            throw TranslationError.apiError("Microsoft Translator 返回无效响应")
        }
        return first
    }

    /// 一次请求翻译多段文本，顺序与输入一致
    static func translate(texts: [String], apiKey: String, targetLang: String = "zh-Hans") async throws -> [String] {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 Microsoft Translator API Key") }
        guard !texts.isEmpty else { return [] }
        let url = URL(string: "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to=\(targetLang)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.httpBody = try JSONEncoder().encode(texts.map { ["Text": $0] })
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranslationError.apiError("Microsoft Translator 错误 \(http.statusCode): \(msg.prefix(200))")
        }
        struct Response: Decodable {
            struct Translation: Decodable { let text: String; let to: String }
            let translations: [Translation]
        }
        guard let results = try? JSONDecoder().decode([Response].self, from: data),
              results.count == texts.count else {
            throw TranslationError.apiError("Microsoft Translator 返回无效响应")
        }
        return results.map { $0.translations.first?.text ?? "" }
    }
}

// MARK: - Unified AI Translation / Summary

enum AITranslate {
    static func translate(text: String, provider: AIProvider, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        let prompt = "请将以下内容翻译成中文，只输出译文，不要解释：\n\n\(text)"
        return try await callAI(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 2048)
    }
}

enum AISummary {
    static func summarize(article: Article, provider: AIProvider, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        let content = HTMLUtils.stripTags(article.content)
        let prompt = "请用3-5句话概括以下文章的核心内容，用中文回答，每句话用换行分隔：\n\n标题：\(article.title)\n\n内容：\(content.prefix(2500))"
        return try await callAI(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 600)
    }
}

/// 统一入口：根据 provider.kind 走 Gemini 或 OpenAI 兼容接口
func callAI(prompt: String, provider: AIProvider, apiKey: String, maxTokens: Int = 500) async throws -> String {
    if provider.kind == "gemini" || provider.name.lowercased().contains("gemini") {
        return try await callGemini(prompt: prompt, provider: provider, apiKey: apiKey)
    }
    return try await callOpenAICompatible(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: maxTokens)
}

func callOpenAICompatible(prompt: String, provider: AIProvider, apiKey: String, maxTokens: Int = 500) async throws -> String {
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
        "max_tokens": maxTokens
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

func callGemini(prompt: String, provider: AIProvider, apiKey: String) async throws -> String {
    let model = provider.model.isEmpty ? "gemini-2.0-flash" : provider.model
    let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
    guard let url = URL(string: urlStr) else {
        throw TranslationError.apiError("无效的 Gemini URL")
    }

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

// MARK: - HTML Utilities (entities + strip)

enum HTMLUtils {
    /// 解码常见 HTML 实体（含数字实体如 &#8216;）
    static func decodeEntities(_ html: String) -> String {
        var result = html
        // 命名实体
        let named: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&nbsp;", " "),
            ("&ldquo;", "\u{201C}"),
            ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"),
            ("&rsquo;", "\u{2019}"),
            ("&mdash;", "\u{2014}"),
            ("&ndash;", "\u{2013}"),
            ("&hellip;", "\u{2026}"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™"),
        ]
        for (entity, char) in named {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // 十进制数字实体 &#8216;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                let numRange = match.range(at: 1)
                if let range = Range(numRange, in: result),
                   let code = Int(result[range]),
                   let scalar = Unicode.Scalar(code) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }
        // 十六进制 &#x2018;
        if let regex = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);", options: []) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                let numRange = match.range(at: 1)
                if let range = Range(numRange, in: result),
                   let code = Int(result[range], radix: 16),
                   let scalar = Unicode.Scalar(code) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }
        return result
    }

    static func stripTags(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<![CDATA[", with: "")
        result = result.replacingOccurrences(of: "]]>", with: "")
        result = result.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"</p>|</div>|</li>|</h[1-6]>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = decodeEntities(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
