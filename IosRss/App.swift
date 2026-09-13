import SwiftUI
#if canImport(Translation)
import Translation
#endif

#if canImport(Translation)
@available(iOS 18.0, *)
struct SystemTranslationAnchor: View {
    @ObservedObject private var host = SystemTranslationHost.shared

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .translationTask(host.configuration) { session in
                await SystemTranslationHost.shared.handle(session: session)
            }
            .onAppear {
                SystemTranslationHost.shared.markAnchored(true)
            }
            .onDisappear {
                SystemTranslationHost.shared.markAnchored(false)
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
#if canImport(Translation)
                .background {
                    if #available(iOS 18.0, *) {
                        SystemTranslationAnchor()
                    }
                }
#endif
        }
    }
}
