import SwiftUI

@main
struct IosRssApp: App {
    init() { Cloud.configure(appId: "hzj3sd6a92mn") }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
