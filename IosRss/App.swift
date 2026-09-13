import SwiftUI
#if canImport(Translation)
import Translation
#endif

#if canImport(Translation)
@available(iOS 18.0, *)
struct SystemTranslationAnchor: View {
    private let host = SystemTranslationHost.shared

    var body: some View {
        let config = host.configuration
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .translationTask(config) { session in
                await SystemTranslationHost.shared.handle(session: session)
            }
    }
}
#endif


@main
struct IosRssApp: App {
    init() {
        // Cloud 后端未启用（stub），不在此初始化以免误导
        // 扩大 URL 磁盘缓存，配合 OfflineCache 支持离线读正文/图片
        OfflineCache.configureURLCache()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background {
#if canImport(Translation)
                    if #available(iOS 18.0, *) {
                        SystemTranslationAnchor()
                    }
#endif
                }
        }
    }
}
