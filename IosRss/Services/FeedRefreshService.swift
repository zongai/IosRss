import Foundation

/// 订阅源网络拉取（与 AppStore UI 状态解耦）
enum FeedRefreshService {
    enum HTTP {
        static let session: URLSession = {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 12
            cfg.timeoutIntervalForResource = 18
            cfg.httpMaximumConnectionsPerHost = 6
            cfg.waitsForConnectivity = false
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: cfg)
        }()
        /// 全量刷新时的并行源数量
        static let refreshConcurrency = 8
    }

    static func fetchFeedData(from url: URL) async throws -> Data {
        if RSSHubSupport.isRSSHubURL(url) {
            let (data, _) = try await FeedDiscovery.fetchRSSHubFeed(from: url)
            return data
        }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await HTTP.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        if RSSHubSupport.looksLikeCloudflareOrHTMLGate(data) {
            throw URLError(.noPermissionsToReadFile)
        }
        return data
    }
}
