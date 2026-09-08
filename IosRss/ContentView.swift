import SwiftUI

struct ContentView: View {
    @State private var store = AppStore()
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        let resolvedTheme = AppColorTheme.resolved(
            selected: store.colorTheme,
            appearance: store.appearanceMode,
            systemScheme: systemColorScheme
        )
        let tokens = resolvedTheme.tokens
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
        .preferredColorScheme(store.appearanceMode.preferredColorScheme)
    }
}
