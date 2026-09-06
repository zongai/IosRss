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

    /// 从文章链接抓取网页评论（优先 Substack 公开 API）
    static func fetchComments(from articleURL: String) async throws -> [WebComment] {
        guard let url = URL(string: articleURL), let host = url.host, !host.isEmpty else {
            throw CommentFetchError.postNotFound
        }

        if let comments = try await fetchSubstackComments(pageURL: url) {
            return comments
        }

        throw CommentFetchError.unsupportedSite
    }

    /// 添加/导入订阅时判断是否自动开启评论获取（Substack 及同类出版平台）
    static func shouldAutoEnableComments(feedURL: String, sampleArticleLinks: [String] = []) -> Bool {
        let candidates = [feedURL] + sampleArticleLinks
        for raw in candidates {
            guard let url = URL(string: raw), let host = url.host?.lowercased() else { continue }
            if host == "substack.com" || host.hasSuffix(".substack.com") {
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

    // MARK: - Substack

    private static func fetchSubstackComments(pageURL: URL) async throws -> [WebComment]? {
        guard let (origin, slug) = substackOriginAndSlug(from: pageURL) else { return nil }

        // 1) 文章元数据 → post id
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

        // 2) 评论树
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

            if node["deleted"] as? Bool == true { /* still show children */ }
            let author = (node["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// 识别 Substack：`*.substack.com/p/slug` 或自定义域名 `/p/slug`
    private static func substackOriginAndSlug(from url: URL) -> (URL, String)? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.fragment = nil
        components.query = nil
        guard let host = components.host, let scheme = components.scheme else { return nil }
        let path = components.path
        // /p/{slug} 或 /p/{slug}/...
        let parts = path.split(separator: "/").map(String.init)
        guard let pIdx = parts.firstIndex(of: "p"), pIdx + 1 < parts.count else {
            // 非 /p/ 路径：仅当 host 含 substack.com 时再尝试最后一段
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
        // 自定义域名与 *.substack.com 均走同一 API
        return (origin, slug)
    }
}
