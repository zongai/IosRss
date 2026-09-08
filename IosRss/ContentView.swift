import SwiftUI

struct ContentView: View {
    @State private var store = AppStore()

    var body: some View {
        let tokens = store.colorTheme.tokens
        TabView {
            Tab("订阅", systemImage: "newspaper") {
                FeedsListView()
            }
            Tab("收藏", systemImage: "star") {
                FavoritesListView()
            }
            Tab("设置", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(tokens.accent)
        .environment(store)
        .environment(\.theme, tokens)
        .preferredColorScheme(store.colorTheme.isDark ? .dark : .light)
    }
}
