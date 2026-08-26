import SwiftUI
import UIKit

enum HomeTheme {
    static let background = Color(red: 0.965, green: 0.965, blue: 0.973)
    static let card = Color.white
    static let ink = Color(red: 0.075, green: 0.086, blue: 0.12)
    static let muted = Color(red: 0.47, green: 0.51, blue: 0.59)
    static let line = Color(red: 0.90, green: 0.91, blue: 0.93)
    static let blue = Color(red: 22 / 255, green: 119 / 255, blue: 1)
    static let orange = Color(red: 1, green: 0.58, blue: 0.05)
}

enum NativeHaptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.72) }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

struct HomeCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(HomeTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct PageTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 29, weight: .bold, design: .rounded))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(HomeTheme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .medium)).foregroundStyle(HomeTheme.blue)
            Text(title).font(.headline)
            Text(message).font(.footnote).foregroundStyle(HomeTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
