import Foundation

struct WebComment: Identifiable, Hashable {
    let id: String
    let author: String
    let body: String
    let date: Date?
    let depth: Int
    var translatedBody: String?
}

enum CommentFetchError: LocalizedError {
    case unsupportedSite
    case postNotFound
    case noComments
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSite: return "暂不支持该站点的评论获取"
        case .postNotFound: return "无法解析文章信息"
        case .noComments: return "暂无评论"
        case .network(let s): return s
        }
    }
}

enum CommentFetcher {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 25
        c.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept": "application/json,text/html;q=0.9,*/*;q=0.8"
        ]
        return URLSession(configuration: c)
    }()

    /// 从文章链接抓取网页评论（Substack 公开 API + OpenWeb/Spot.IM SEO API）
    static func fetchComments(from articleURL: String) async throws -> [WebComment] {
        guard let url = NetworkURLPolicy.validate(articleURL), let host = url.host, !host.isEmpty else {
            throw CommentFetchError.postNotFound
        }

        if let comments = try await fetchSubstackComments(pageURL: url) {
            return comments
        }
        if let comments = try await fetchOpenWebComments(pageURL: url) {
            return comments
        }

        throw CommentFetchError.unsupportedSite
    }

    /// 添加/导入订阅时判断是否自动开启评论获取
    static func shouldAutoEnableComments(feedURL: String, sampleArticleLinks: [String] = []) -> Bool {
        let candidates = [feedURL] + sampleArticleLinks
        for raw in candidates {
            guard let url = NetworkURLPolicy.validate(raw), let host = url.host?.lowercased() else { continue }
            if host == "substack.com" || host.hasSuffix(".substack.com") {
                return true
            }
            if host == "engadget.com" || host.hasSuffix(".engadget.com") {
                return true
            }
            // 文章路径含 /p/{slug}（Substack 自定义域名常见形态）
            let parts = url.path.lowercased().split(separator: "/").map(String.init)
            if let idx = parts.firstIndex(of: "p"), idx + 1 < parts.count, !parts[idx + 1].isEmpty {
                return true
            }
        }
        return false
    }

    // MARK: - OpenWeb / Spot.IM（Engadget 等）

    /// 公开 SEO 接口，无需 API Key：`POST https://seo.spot.im/v2/comment/{spotId}/{postId}?json=true`
    private static func fetchOpenWebComments(pageURL: URL) async throws -> [WebComment]? {
        guard let ids = try await resolveOpenWebIDs(pageURL: pageURL) else { return nil }
        let (spotId, postId) = ids

        guard let apiURL = URL(string: "https://seo.spot.im/v2/comment/\(spotId)/\(postId)?json=true") else {
            return nil
        }
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(pageURL.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = Data()

        let data: Data
        do {
            let (d, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CommentFetchError.network("无效响应")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw CommentFetchError.network("OpenWeb 评论 HTTP \(http.statusCode)")
            }
            data = d
        } catch let e as CommentFetchError {
            throw e
        } catch {
            throw CommentFetchError.network(error.localizedDescription)
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CommentFetchError.noComments
        }

        // comment 可能是数组，或缺失表示 0
        let list = root["comment"] as? [[String: Any]] ?? []
        var result: [WebComment] = []
        result.reserveCapacity(list.count)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for (idx, node) in list.enumerated() {
            let author: String = {
                if let a = node["author"] as? [String: Any], let name = a["name"] as? String, !name.isEmpty {
                    return name.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return "匿名"
            }()
            let textRaw = (node["text"] as? String) ?? (node["reviewBody"] as? String) ?? ""
            let body = HTMLUtils.stripTags(HTMLUtils.decodeEntities(textRaw))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            var date: Date?
            if let ds = node["datePublished"] as? String {
                date = dateFormatter.date(from: String(ds.prefix(10)))
                    ?? ISO8601DateFormatter().date(from: ds)
            }
            let id: String
            if let s = node["@id"] as? String, !s.isEmpty { id = s }
            else { id = "\(spotId)_\(postId)_\(idx)" }
            result.append(WebComment(
                id: id,
                author: author,
                body: body,
                date: date,
                depth: 0,
                translatedBody: nil
            ))
        }

        if result.isEmpty {
            throw CommentFetchError.noComments
        }
        return result
    }

    /// 从文章页 HTML / URL 解析 OpenWeb spot_id 与 post_id
    private static func resolveOpenWebIDs(pageURL: URL) async throws -> (spotId: String, postId: String)? {
        // 1) 抓取页面
        let html: String
        do {
            let (data, response) = try await session.data(from: pageURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  !text.isEmpty else {
                return nil
            }
            html = text
        } catch {
            return nil
        }

        // 必须能识别 OpenWeb 嵌入，否则返回 nil 让上层尝试其它源
        let hasOpenWeb = html.localizedCaseInsensitiveContains("spot.im")
            || html.localizedCaseInsensitiveContains("openweb")
            || html.localizedCaseInsensitiveContains("data-spotim-module")
        guard hasOpenWeb else { return nil }

        // spot id: config['openWebID'] = 'sp_xxx' 或 launcher.spot.im/spot/sp_xxx
        var spotId: String?
        if let re = try? NSRegularExpression(pattern: #"openWebID['\"]?\s*=\s*['\"]?(sp_[A-Za-z0-9]+)"#, options: .caseInsensitive),
           let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           m.numberOfRanges >= 2,
           let r = Range(m.range(at: 1), in: html) {
            spotId = String(html[r])
        }
        if spotId == nil,
           let re = try? NSRegularExpression(pattern: #"launcher\.spot\.im/spot/(sp_[A-Za-z0-9]+)"#, options: .caseInsensitive),
           let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           m.numberOfRanges >= 2,
           let r = Range(m.range(at: 1), in: html) {
            spotId = String(html[r])
        }
        if spotId == nil,
           let re = try? NSRegularExpression(pattern: #"\b(sp_[A-Za-z0-9]{6,})\b"#, options: []),
           let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           m.numberOfRanges >= 2,
           let r = Range(m.range(at: 1), in: html) {
            spotId = String(html[r])
        }

        // post id: data-post-id / conversation 模块 / 路径数字段
        var postId: String?
        for pattern in [
            #"data-post-id=["'](\d+)["']"#,
            #"data-post_id=["'](\d+)["']"#,
            #""post_id"\s*:\s*(\d+)"#,
            #"post_id["']?\s*:\s*["']?(\d+)"#
        ] {
            if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: html) {
                postId = String(html[r])
                break
            }
        }
        if postId == nil {
            // Engadget: /{digits}/slug
            let parts = pageURL.path.split(separator: "/").map(String.init)
            if let first = parts.first, first.allSatisfy(\.isNumber), first.count >= 5 {
                postId = first
            }
        }

        guard let spotId, let postId, !spotId.isEmpty, !postId.isEmpty else {
            return nil
        }
        return (spotId, postId)
    }

    // MARK: - Substack

    private static func fetchSubstackComments(pageURL: URL) async throws -> [WebComment]? {
        guard let (origin, slug) = substackOriginAndSlug(from: pageURL) else { return nil }

        let postAPI = origin.appendingPathComponent("api/v1/posts/\(slug)")
        let postData: Data
        do {
            let (data, response) = try await session.data(from: postAPI)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            postData = data
        } catch {
            return nil
        }

        guard let postJSON = try? JSONSerialization.jsonObject(with: postData) as? [String: Any] else {
            return nil
        }
        let postID: Int
        if let n = postJSON["id"] as? Int {
            postID = n
        } else if let n = postJSON["id"] as? NSNumber {
            postID = n.intValue
        } else {
            return nil
        }

        var components = URLComponents(
            url: origin.appendingPathComponent("api/v1/post/\(postID)/comments"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "all_comments", value: "true")]
        guard let commentsURL = components.url else { throw CommentFetchError.postNotFound }

        let data: Data
        do {
            let (d, response) = try await session.data(from: commentsURL)
            guard let http = response as? HTTPURLResponse else {
                throw CommentFetchError.network("无效响应")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw CommentFetchError.network("评论接口 HTTP \(http.statusCode)")
            }
            data = d
        } catch let e as CommentFetchError {
            throw e
        } catch {
            throw CommentFetchError.network(error.localizedDescription)
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["comments"] as? [[String: Any]] else {
            throw CommentFetchError.noComments
        }

        var result: [WebComment] = []
        func walk(_ node: [String: Any], depth: Int) {
            let id: String
            if let n = node["id"] as? Int { id = String(n) }
            else if let n = node["id"] as? NSNumber { id = n.stringValue }
            else if let s = node["id"] as? String { id = s }
            else { id = UUID().uuidString }

            let authorObj = node["user"] as? [String: Any]
            let author = (authorObj?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyRaw = (node["body"] as? String) ?? ""
            let body = HTMLUtils.stripTags(HTMLUtils.decodeEntities(bodyRaw))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var date: Date?
            if let ds = node["date"] as? String {
                date = ISO8601DateFormatter().date(from: ds)
                    ?? ISO8601DateFormatter().date(from: ds.replacingOccurrences(of: "Z", with: "+00:00"))
            }
            if !body.isEmpty {
                result.append(WebComment(
                    id: id,
                    author: (author?.isEmpty == false) ? author! : "匿名",
                    body: body,
                    date: date,
                    depth: depth,
                    translatedBody: nil
                ))
            }
            if let children = node["children"] as? [[String: Any]] {
                for child in children { walk(child, depth: depth + 1) }
            }
        }
        for c in list { walk(c, depth: 0) }
        if result.isEmpty { throw CommentFetchError.noComments }
        return result
    }

    private static func substackOriginAndSlug(from url: URL) -> (URL, String)? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.fragment = nil
        components.query = nil
        guard let host = components.host, let scheme = components.scheme else { return nil }
        let path = components.path
        let parts = path.split(separator: "/").map(String.init)
        guard let pIdx = parts.firstIndex(of: "p"), pIdx + 1 < parts.count else {
            guard host.contains("substack.com"), let last = parts.last, !last.isEmpty else { return nil }
            var originComp = URLComponents()
            originComp.scheme = scheme
            originComp.host = host
            guard let origin = originComp.url else { return nil }
            return (origin, last)
        }
        let slug = parts[pIdx + 1]
        guard !slug.isEmpty else { return nil }
        var originComp = URLComponents()
        originComp.scheme = scheme
        originComp.host = host
        guard let origin = originComp.url else { return nil }
        return (origin, slug)
    }
}
