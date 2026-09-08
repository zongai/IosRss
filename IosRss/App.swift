import SwiftUI

@main
struct IosRssApp: App {
    init() {
        AppFontRegistration.register()
        Cloud.configure(appId: "hzj3sd6a92mn")
        // 扩大 URL 磁盘缓存，配合 OfflineCache 支持离线读正文/图片
        OfflineCache.configureURLCache()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
