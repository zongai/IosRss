import Foundation

/// 翻译专用 URLSession：提高同主机并发连接，减少排队
enum TranslationHTTP {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 18
        cfg.timeoutIntervalForResource = 45
        cfg.httpMaximumConnectionsPerHost = 10
        cfg.waitsForConnectivity = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()
}

enum TranslationError: LocalizedError {
    case noProvider
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "未配置翻译引擎，请在设置中添加AI提供商"
        case .apiError(let msg):
            return msg
        }
    }
}

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

        let (data, response) = try await TranslationHTTP.session.data(for: request)

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
    /// 纯免费接口（无 Key）：
    /// GET https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=…&dt=t&q=…
    static func translate(text: String, targetLang: String = "zh-CN") async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let tl: String = {
            switch targetLang.lowercased() {
            case "zh", "zh-hans": return "zh-CN"
            case "zh-hant": return "zh-TW"
            default: return targetLang
            }
        }()
        // 短文本 GET；过长用 POST 避免 URL 限制
        if trimmed.utf8.count < 1800 {
            do {
                return try await request(text: trimmed, targetLang: tl, method: "GET")
            } catch {
                return try await request(text: trimmed, targetLang: tl, method: "POST")
            }
        }
        return try await request(text: trimmed, targetLang: tl, method: "POST")
    }

    private static func request(text: String, targetLang: String, method: String) async throws -> String {
        if method == "GET" {
            var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
            comps.queryItems = [
                URLQueryItem(name: "client", value: "gtx"),
                URLQueryItem(name: "sl", value: "auto"),
                URLQueryItem(name: "tl", value: targetLang),
                URLQueryItem(name: "dt", value: "t"),
                URLQueryItem(name: "q", value: text)
            ]
            guard let url = comps.url else { throw TranslationError.apiError("无效的 Google URL") }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "GET"
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return try await parse(request)
        } else {
            guard let url = URL(string: "https://translate.googleapis.com/translate_a/single") else {
                throw TranslationError.apiError("无效的URL")
            }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            var body = URLComponents()
            body.queryItems = [
                URLQueryItem(name: "client", value: "gtx"),
                URLQueryItem(name: "sl", value: "auto"),
                URLQueryItem(name: "tl", value: targetLang),
                URLQueryItem(name: "dt", value: "t"),
                URLQueryItem(name: "q", value: text)
            ]
            request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            return try await parse(request)
        }
    }

    private static func parse(_ request: URLRequest) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if http.statusCode == 429 {
                throw TranslationError.apiError("Google 限流 (429)，请稍后再试")
            }
            throw TranslationError.apiError("Google 翻译失败 (状态码 \(http.statusCode))")
        }
        if let raw = String(data: data, encoding: .utf8),
           raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<!") {
            throw TranslationError.apiError("Google 限流 (429)，请稍后再试")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let firstElement = json.first as? [Any] else {
            throw TranslationError.apiError("解析 Google 响应失败")
        }
        let result = firstElement.compactMap { segment -> String? in
            guard let segArray = segment as? [Any],
                  let text = segArray.first as? String else { return nil }
            return text
        }.joined()
        if result.isEmpty {
            throw TranslationError.apiError("Google 返回空译文")
        }
        return result
    }
}


// MARK: - MyMemory (free, no key; daily quota per IP)

enum MyMemoryTranslate {
    static func translate(text: String, targetLang: String = "zh-CN") async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // MyMemory 单次建议 < 500 字符
        let chunk = String(trimmed.prefix(450))
        var comps = URLComponents(string: "https://api.mymemory.translated.net/get")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: chunk),
            URLQueryItem(name: "langpair", value: "Autodetect|\(targetLang)")
        ]
        guard let url = comps.url else { throw TranslationError.apiError("MyMemory URL 无效") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.apiError("MyMemory 失败 (\(http.statusCode))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rd = json["responseData"] as? [String: Any],
              let translated = rd["translatedText"] as? String else {
            throw TranslationError.apiError("MyMemory 解析失败")
        }
        let out = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { throw TranslationError.apiError("MyMemory 返回空译文") }
        // 配额耗尽时接口可能原样返回原文或带 MYMEMORY WARNING
        if out.uppercased().contains("MYMEMORY WARNING") {
            throw TranslationError.apiError("MyMemory 额度可能已用尽")
        }
        return out
    }
}


// MARK: - Lingva (REST v1 GET & POST, no key)

enum LingvaTranslate {
    /// 公共实例；可在设置中指定自定义根地址
    private static let defaultHosts = [
        "https://lingva.ml",
        "https://translate.plausibility.cloud",
        "https://lingva.lunar.icu",
        "https://translate.projectsegfau.lt",
        "https://lingva.garudalinux.org"
    ]

    static func resolveHosts(customBase: String?) -> [String] {
        var list: [String] = []
        if let c = customBase?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            let base = c.hasSuffix("/") ? String(c.dropLast()) : c
            list.append(base)
        }
        list.append(contentsOf: defaultHosts)
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    static func mapTarget(_ targetLang: String) -> String {
        switch targetLang.lowercased() {
        case "zh-cn", "zh-hans", "zh": return "zh"
        case "zh-tw", "zh-hant": return "zh_HANT"
        default:
            return targetLang.replacingOccurrences(of: "-", with: "_")
        }
    }

    /// REST v1：短文本优先 GET；较长文本用 POST JSON
    static func translate(text: String, targetLang: String = "zh", customBase: String? = nil) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let tl = mapTarget(targetLang)
        var lastError: Error = TranslationError.apiError("Lingva 暂不可用")
        for host in resolveHosts(customBase: customBase) {
            do {
                // 超过 ~300 字符用 POST，避免 URL 过长
                if trimmed.count > 300 {
                    return try await post(host: host, target: tl, query: trimmed)
                }
                do {
                    return try await get(host: host, target: tl, query: trimmed)
                } catch {
                    // GET 失败再试 POST
                    return try await post(host: host, target: tl, query: trimmed)
                }
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    /// GET /api/v1/:source/:target/:query
    private static func get(host: String, target: String, query: String) async throws -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        guard let url = URL(string: "\(host)/api/v1/auto/\(target)/\(encoded)") else {
            throw TranslationError.apiError("Lingva GET URL 无效")
        }
        var request = URLRequest(url: url, timeoutInterval: 16)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await parseResponse(request: request, host: host)
    }

    /// POST /api/v1/:source/:target  body: {"query":"..."}
    private static func post(host: String, target: String, query: String) async throws -> String {
        guard let url = URL(string: "\(host)/api/v1/auto/\(target)") else {
            throw TranslationError.apiError("Lingva POST URL 无效")
        }
        var request = URLRequest(url: url, timeoutInterval: 18)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
        return try await parseResponse(request: request, host: host)
    }

    private static func parseResponse(request: URLRequest, host: String) async throws -> String {
        let (data, response) = try await TranslationHTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.apiError("Lingva 无响应 (\(host))")
        }
        if !(200..<300).contains(http.statusCode) {
            throw TranslationError.apiError("Lingva HTTP \(http.statusCode) (\(host))")
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let translation = json["translation"] as? String, !translation.isEmpty {
                return translation
            }
            if let err = json["error"] as? String {
                throw TranslationError.apiError("Lingva: \(err)")
            }
        }
        throw TranslationError.apiError("Lingva 解析失败 (\(host))")
    }
}

// MARK: - Microsoft Translator

enum MicrosoftTranslate {
    static func translate(text: String, apiKey: String, region: String = "", targetLang: String = "zh-Hans") async throws -> String {
        let all = try await translate(texts: [text], apiKey: apiKey, region: region, targetLang: targetLang)
        guard let first = all.first, !first.isEmpty else {
            throw TranslationError.apiError("Microsoft Translator 返回无效响应")
        }
        return first
    }

    /// 一次请求翻译多段文本，顺序与输入一致
    /// - Parameter region: Azure 资源区域（如 eastasia、eastus、global）。多服务资源 Key 必须带区域，否则常返回 401。
    static func translate(texts: [String], apiKey: String, region: String = "", targetLang: String = "zh-Hans") async throws -> [String] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranslationError.apiError("未配置 Microsoft Translator API Key") }
        guard !texts.isEmpty else { return [] }
        let url = URL(string: "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to=\(targetLang)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let regionTrim = region.trimmingCharacters(in: .whitespacesAndNewlines)
        // 多服务 / 区域资源必须带 Region；未填时默认 global（全球资源）
        request.setValue(regionTrim.isEmpty ? "global" : regionTrim, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        request.httpBody = try JSONEncoder().encode(texts.map { ["Text": $0] })
        let (data, response) = try await TranslationHTTP.session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            if http.statusCode == 401 {
                throw TranslationError.apiError("Microsoft 401：Key 无效或区域不匹配。请在设置中填写 Azure 资源区域（如 eastasia / eastus / global），并确认 Key 来自 Translator 或多服务资源。")
            }
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
        try await translate(
            text: text,
            provider: provider,
            apiKey: apiKey,
            promptTemplate: AppStore.defaultTranslationPrompt
        )
    }

    static func translate(text: String, provider: AIProvider, apiKey: String, promptTemplate: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        let template = promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppStore.defaultTranslationPrompt
            : promptTemplate
        var prompt = template.replacingOccurrences(of: "{{text}}", with: text)
        if !template.contains("{{text}}") {
            prompt += "\n\n" + text
        }
        return try await callAI(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 2048)
    }
}

enum AISummary {
    static func summarize(article: Article, provider: AIProvider, apiKey: String) async throws -> String {
        try await summarize(
            article: article,
            provider: provider,
            apiKey: apiKey,
            promptTemplate: AppStore.defaultSummaryPrompt
        )
    }

    static func summarize(article: Article, provider: AIProvider, apiKey: String, promptTemplate: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        let content = String(HTMLUtils.stripTags(article.content).prefix(2500))
        let template = promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppStore.defaultSummaryPrompt
            : promptTemplate
        var prompt = template
            .replacingOccurrences(of: "{{title}}", with: article.title)
            .replacingOccurrences(of: "{{content}}", with: content)
        if !template.contains("{{title}}") && !template.contains("{{content}}") {
            prompt += "\n\n标题：\(article.title)\n\n内容：\(content)"
        }
        return try await callAI(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 600)
    }
}

/// 框选文字 AI 解释
enum AIExplain {
    static let defaultPrompt = """
    请用简洁的中文解释下面这段文字（词义、专有名词、语境或背景）。只输出解释，不要标题，不要复述整段原文：

    {{text}}
    """

    static func explain(text: String, provider: AIProvider, apiKey: String, promptTemplate: String? = nil) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        let clipped = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(800))
        guard !clipped.isEmpty else { throw TranslationError.apiError("未选中有效文字") }
        let template = (promptTemplate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultPrompt
            : promptTemplate!
        var prompt = template.replacingOccurrences(of: "{{text}}", with: clipped)
        if !template.contains("{{text}}") {
            prompt += "\n\n\(clipped)"
        }
        return try await callAI(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 500)
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
    // 思考模型可能占用较多 completion token；略提高上限，最终只展示正文
    let body: [String: Any] = [
        "model": provider.model,
        "messages": [["role": "user", "content": prompt]],
        "max_tokens": max(maxTokens, 800)
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw TranslationError.apiError("API 错误 \(http.statusCode): \(msg.prefix(200))")
    }
    // 兼容：content / reasoning_content / reasoning；只取最终回答
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let choices = json["choices"] as? [[String: Any]],
       let message = choices.first?["message"] as? [String: Any] {
        let content = (message["content"] as? String) ?? ""
        // 忽略 reasoning_content / reasoning / reasoning_text 等思考字段
        let cleaned = AIResponseSanitizer.stripThinking(content)
        if !cleaned.isEmpty {
            return cleaned
        }
        // 少数接口把最终答案放在其它字段
        for key in ["output_text", "result", "answer"] {
            if let alt = message[key] as? String {
                let c = AIResponseSanitizer.stripThinking(alt)
                if !c.isEmpty { return c }
            }
        }
    }
    throw TranslationError.apiError("解析 AI 响应失败")
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

    // thought 类模型：请求不把思考过程混进可见文本（若接口支持）
    var body: [String: Any] = [
        "contents": [
            ["parts": [["text": prompt]]]
        ]
    ]
    // Gemini 2.5 thinking：generationConfig 可选
    body["generationConfig"] = [
        "maxOutputTokens": 2048
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw TranslationError.apiError("Gemini API 错误 \(http.statusCode): \(msg.prefix(200))")
    }

    // 解析 parts：跳过 thought / 仅拼接可见 text
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let candidates = json["candidates"] as? [[String: Any]],
       let content = candidates.first?["content"] as? [String: Any],
       let parts = content["parts"] as? [[String: Any]] {
        var texts: [String] = []
        for part in parts {
            // thought: true 的 part 为思考过程，跳过
            if let thought = part["thought"] as? Bool, thought { continue }
            if let text = part["text"] as? String, !text.isEmpty {
                texts.append(text)
            }
        }
        let joined = texts.joined()
        let cleaned = AIResponseSanitizer.stripThinking(joined)
        if !cleaned.isEmpty {
            return cleaned
        }
    }
    let raw = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
    throw TranslationError.apiError("解析 Gemini 响应失败: \(raw)")
}

/// 过滤思考模型输出中的推理过程，只保留最终回答
enum AIResponseSanitizer {
    static func stripThinking(_ text: String) -> String {
        var result = text

        // 常见标签块：<think> <thinking> <reasoning> <reflection> <thought>
        let tagPatterns = [
            #"<think>[\s\S]*?</think>"#,
            #"<thinking>[\s\S]*?</thinking>"#,
            #"<reasoning>[\s\S]*?</reasoning>"#,
            #"<reflection>[\s\S]*?</reflection>"#,
            #"<thought>[\s\S]*?</thought>"#,
            #"<redacted_reasoning>[\s\S]*?</redacted_reasoning>"#,
        ]
        for pattern in tagPatterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        // 未闭合的 <think>… 直接截到标签前
        if let re = try? NSRegularExpression(pattern: #"<think>[\s\S]*"#, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // 中文标记
        let cnPatterns = [
            #"【思考】[\s\S]*?【/思考】"#,
            #"【推理】[\s\S]*?【/推理】"#,
            #"（思考过程：[\s\S]*?）"#,
        ]
        for pattern in cnPatterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        // 去掉开头的 “Thinking / 思考过程” 段落（到空行或文末）
        if let re = try? NSRegularExpression(
            pattern: #"(?im)^#{1,3}\s*(thinking|reasoning|thought process|思考过程|推理过程)\s*$[\s\S]*?(?=^#{1,3}\s|\Z)"#,
            options: []
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - HTML Utilities (entities + strip)

enum HTMLUtils {
    /// 解码常见 HTML 实体（含数字实体如 &#8216;）
    /// 解码正文中残留的百分号编码片段（如 %e8%ae%ae → 议）
    static func decodePercentEncodings(_ text: String) -> String {
        var result = text
        // 连续 %XX 序列
        if let regex = try? NSRegularExpression(pattern: #"(?:%[0-9A-Fa-f]{2}){2,}"#, options: []) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                guard let range = Range(match.range, in: result) else { continue }
                let encoded = String(result[range])
                if let decoded = encoded.removingPercentEncoding, decoded != encoded {
                    result.replaceSubrange(range, with: decoded)
                }
            }
        }
        // 单个 %XX 若为可打印字符也尝试
        if let regex = try? NSRegularExpression(pattern: #"%[0-9A-Fa-f]{2}"#, options: []) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                guard let range = Range(match.range, in: result) else { continue }
                let encoded = String(result[range])
                if let decoded = encoded.removingPercentEncoding, decoded != encoded,
                   decoded.unicodeScalars.allSatisfy({ !$0.properties.isNoncharacterCodePoint }) {
                    result.replaceSubrange(range, with: decoded)
                }
            }
        }
        return result
    }

    static func decodeEntities(_ html: String) -> String {
        var result = html
        // 命名实体
        // 用拼接避免源文件中出现完整 HTML 实体字面量（部分同步路径会错误解码）
        let named: [(String, String)] = [
            ("&" + "amp;", "&"),
            ("&" + "lt;", "<"),
            ("&" + "gt;", ">"),
            ("&" + "quot;", "\""),
            ("&" + "apos;", "'"),
            ("&" + "#39;", "'"),
            ("&" + "nbsp;", " "),
            ("&" + "ldquo;", "\u{201C}"),
            ("&" + "rdquo;", "\u{201D}"),
            ("&" + "lsquo;", "\u{2018}"),
            ("&" + "rsquo;", "\u{2019}"),
            ("&" + "mdash;", "\u{2014}"),
            ("&" + "ndash;", "\u{2013}"),
            ("&" + "hellip;", "\u{2026}"),
            ("&" + "copy;", "©"),
            ("&" + "reg;", "®"),
            ("&" + "trade;", "™"),
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
        return decodePercentEncodings(result)
    }

    static func stripTags(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<![CDATA[", with: "")
        result = result.replacingOccurrences(of: "]]>", with: "")
        if let re = try? NSRegularExpression(pattern: "<!--([\\s\\S]*?)-->", options: []) {
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        if let re = try? NSRegularExpression(pattern: "<script[\\s\\S]*?</script>", options: .caseInsensitive) {
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        if let re = try? NSRegularExpression(pattern: "<style[\\s\\S]*?</style>", options: .caseInsensitive) {
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        result = result.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"</p>|</div>|</li>|</tr>|</h[1-6]>"#, with: "\n", options: .regularExpression)
        if let re = try? NSRegularExpression(pattern: "<[^>]+>", options: [.dotMatchesLineSeparators]) {
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // 半截未闭合标签（如裸露的 <div class=）
        if let re = try? NSRegularExpression(pattern: "</?[A-Za-z][^<>\\n]{0,80}", options: []) {
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        result = decodeEntities(result)
        result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 列表/标题用：去标签并压缩空白
    static func plainText(_ html: String) -> String {
        stripTags(html)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 提取 img 标签，用占位符替换，便于翻译纯文本后再还原图片
    static func extractImagesForTranslation(_ html: String) -> (text: String, images: [String]) {
        var working = html
        var images: [String] = []
        let imgPattern = #"<img\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) else {
            return (stripTags(html), [])
        }
        let ns = working as NSString
        let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
        // 从后往前替换，保持 range 有效
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: working) else { continue }
            let tag = String(working[fullRange])
            images.insert(tag, at: 0)
            let placeholder = "\n\n[[IMG_\(images.count - 1)]]\n\n"
            working.replaceSubrange(fullRange, with: placeholder)
        }
        // 去掉其余标签，保留占位符与段落结构
        working = working.replacingOccurrences(of: "<![CDATA[", with: "")
        working = working.replacingOccurrences(of: "]]>", with: "")
        working = working.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        working = working.replacingOccurrences(of: #"</p>|</div>|</li>|</h[1-6]>"#, with: "\n\n", options: .regularExpression)
        working = working.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        working = decodeEntities(working)
        return (working.trimmingCharacters(in: .whitespacesAndNewlines), images)
    }

    /// 将翻译结果中的 [[IMG_n]] 占位还原为原始 img 标签
    static func restoreImagesAfterTranslation(_ text: String, images: [String]) -> String {
        guard !images.isEmpty else { return text }
        var result = text
        for (i, tag) in images.enumerated() {
            let patterns = [
                "[[IMG_\(i)]]",
                "【IMG_\(i)】",
                "[IMG_\(i)]",
                "IMG_\(i)"
            ]
            for p in patterns {
                if result.contains(p) {
                    result = result.replacingOccurrences(of: p, with: "\n\n\(tag)\n\n")
                    break
                }
            }
        }
        return result
    }
}
