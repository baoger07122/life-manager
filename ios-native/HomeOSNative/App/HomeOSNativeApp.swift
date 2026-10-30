import SwiftUI

@main
struct HomeOSNativeApp: App {
    @StateObject private var store = HomeStore()

    private var isPetListUITestPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-codex-pet-list-ui-preview")
        #else
        false
        #endif
    }

    private var expiryUITestPreviewItemID: String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-codex-expiry-ui-preview") else { return nil }
        return arguments.contains("-codex-expiry-ui-preview-multiple")
            ? "preview-pet-food-2"
            : "preview-pet-food-1"
        #else
        return nil
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if isPetListUITestPreview {
                    PetView()
                } else if let previewItemID = expiryUITestPreviewItemID {
                    NavigationStack {
                        PetItemDetailView(itemID: previewItemID)
                    }
                } else {
                    RootView()
                }
                #else
                RootView()
                #endif
            }
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .preferredColorScheme(.light)
                .task {
                    #if PLAYGROUND_PREVIEW
                    if !store.data.hasUserContent {
                        store.replace(with: PreviewFixtures.homeOS)
                    }
                    #endif
                    #if DEBUG
                    if isPetListUITestPreview {
                        store.replace(with: PreviewFixtures.petListUITest)
                    } else if expiryUITestPreviewItemID != nil {
                        store.replace(with: PreviewFixtures.expiryBalanceUITest)
                    }
                    #endif
                }
        }
    }
}
