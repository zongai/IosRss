import SwiftUI
#if canImport(Translation)
import Translation
#endif

#if canImport(Translation)
/// 官方模式：Configuration + translationTask + session.translate
@available(iOS 18.0, *)
struct SystemTranslationAnchor: View {
    @ObservedObject private var host = SystemTranslationHost.shared

    var body: some View {
        // 必须挂在可见视图树上；尺寸可为 0，但不能在 translationTask 触发前被移除
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .translationTask(host.configuration) { session in
                // 与参考资料一致：在闭包内 await session.translate
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
                // overlay 比 background 更不易被布局优化掉
                .overlay {
                    if #available(iOS 18.0, *) {
                        SystemTranslationAnchor()
                    }
                }
#endif
        }
    }
}
