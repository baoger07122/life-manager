import SwiftUI

@main
struct HomeOSNativeApp: App {
    @StateObject private var store = HomeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
    }
}
