import SwiftUI

@main
struct HomeOSNativeApp: App {
    @StateObject private var store = HomeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .preferredColorScheme(.light)
                .task {
                    #if PLAYGROUND_PREVIEW
                    if !store.data.hasUserContent {
                        store.replace(with: PreviewFixtures.homeOS)
                    }
                    #endif
                }
        }
    }
}
