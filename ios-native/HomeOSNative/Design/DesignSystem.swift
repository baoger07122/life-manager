import SwiftUI
import UIKit

enum HomeTheme {
    static let background = Color(red: 0.965, green: 0.965, blue: 0.973)
    static let card = Color.white
    static let ink = Color(red: 0.075, green: 0.086, blue: 0.12)
    static let muted = Color(red: 0.47, green: 0.51, blue: 0.59)
    static let line = Color(red: 0.90, green: 0.91, blue: 0.93)
    static let blue = Color(red: 22 / 255, green: 119 / 255, blue: 1)
    static let success = Color(red: 0.12, green: 0.62, blue: 0.48)
    static let orange = Color(red: 1, green: 0.58, blue: 0.05)
    static let danger = Color(red: 0.88, green: 0.20, blue: 0.24)
}

enum HomeMetrics {
    static let pageInset: CGFloat = 18
    static let sectionSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14
    static let controlHeight: CGFloat = 44
    static let minimumTapTarget: CGFloat = 44
}

enum HomeTypography {
    static let pageTitle = Font.system(size: 24, weight: .semibold)
    static let sectionTitle = Font.system(size: 19, weight: .semibold)
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let supporting = Font.system(size: 12, weight: .regular)
    static let metric = Font.system(size: 28, weight: .bold, design: .rounded)
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
    var padding: CGFloat

    init(padding: CGFloat = HomeMetrics.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(HomeTheme.card, in: RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous)
                    .stroke(HomeTheme.line.opacity(0.9), lineWidth: 0.8)
            }
    }
}

struct HomeUnderlineTab: View {
    let title: String
    let selected: Bool
    var prominent = false

    var body: some View {
        VStack(spacing: prominent ? 8 : 5) {
            Text(title)
                .font(.system(size: prominent ? 17 : 14, weight: prominent ? .semibold : .regular))
                .foregroundStyle(selected ? HomeTheme.ink : HomeTheme.muted)
                .lineLimit(1)
            Capsule()
                .fill(selected ? HomeTheme.blue : Color.clear)
                .frame(width: prominent ? 28 : 20, height: 3)
        }
        .frame(minHeight: HomeMetrics.minimumTapTarget)
        .contentShape(Rectangle())
    }
}

struct PageTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(HomeTypography.pageTitle)
            if let subtitle { Text(subtitle).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomeSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(HomeTypography.sectionTitle)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(HomeTypography.supporting.weight(.semibold))
            }
        }
    }
}

struct HomeStatCard: View {
    let title: String
    let value: String
    var color: Color = HomeTheme.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(HomeTypography.metric).foregroundStyle(color)
            Text(title).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HomeTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct HomePropertyRow: View {
    let title: String
    let value: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(HomeTheme.blue)
                    .frame(width: 22)
                Text(title).font(HomeTypography.body.weight(.medium))
                Spacer()
                Text(value).font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: HomeMetrics.controlHeight)
            .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: HomeMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct HomeListRow: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(HomeTheme.blue)
                .frame(width: 36, height: 36)
                .background(HomeTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(HomeTypography.cardTitle)
                if let subtitle {
                    Text(subtitle).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                }
            }
            Spacer()
            if let trailing {
                Text(trailing).font(HomeTypography.body.weight(.semibold))
            }
        }
        .frame(minHeight: 48)
    }
}

struct HomeQuickAction: View {
    let title: String
    let icon: String
    var color: Color = HomeTheme.blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Text(title)
                    .font(HomeTypography.supporting.weight(.medium))
                    .foregroundStyle(HomeTheme.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressButtonStyle())
    }
}

struct HomeChip: View {
    let title: String
    var selected = false

    var body: some View {
        Text(title)
            .font(HomeTypography.supporting.weight(.semibold))
            .foregroundStyle(selected ? Color.white : HomeTheme.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(selected ? HomeTheme.blue : HomeTheme.background, in: Capsule())
    }
}

struct HomePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HomeTypography.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: HomeMetrics.controlHeight)
            .background(HomeTheme.blue.opacity(configuration.isPressed ? 0.76 : 1), in: RoundedRectangle(cornerRadius: HomeMetrics.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.38)
    }
}

struct HomeSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HomeTypography.body.weight(.semibold))
            .foregroundStyle(HomeTheme.blue)
            .frame(maxWidth: .infinity)
            .frame(height: HomeMetrics.controlHeight)
            .background(HomeTheme.blue.opacity(configuration.isPressed ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: HomeMetrics.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.38)
    }
}

struct HomeDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HomeTypography.body.weight(.semibold))
            .foregroundStyle(HomeTheme.danger)
            .frame(maxWidth: .infinity)
            .frame(height: HomeMetrics.controlHeight)
            .background(HomeTheme.danger.opacity(configuration.isPressed ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: HomeMetrics.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct HomePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct HomeIconButton: View {
    let icon: String
    var accessibilityLabel: String
    var color: Color = HomeTheme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: HomeMetrics.minimumTapTarget, height: HomeMetrics.minimumTapTarget)
                .background(HomeTheme.card, in: Circle())
        }
        .buttonStyle(HomePressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

struct HomeFloatingAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(HomeTheme.blue, in: Circle())
                .shadow(color: HomeTheme.blue.opacity(0.24), radius: 10, y: 5)
        }
        .buttonStyle(HomePressButtonStyle())
        .accessibilityLabel("新增")
    }
}

struct HomeTextFieldStyle: TextFieldStyle {
    var isError = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(HomeTypography.body)
            .padding(.horizontal, 12)
            .frame(height: HomeMetrics.controlHeight)
            .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: HomeMetrics.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomeMetrics.controlRadius, style: .continuous)
                    .stroke(isError ? HomeTheme.danger : HomeTheme.line, lineWidth: isError ? 1.2 : 0.6)
            }
    }
}

struct HomeFieldLabel: View {
    let title: String
    var required = false

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
            if required { Text("*").foregroundStyle(HomeTheme.danger) }
        }
        .font(HomeTypography.supporting.weight(.medium))
        .foregroundStyle(HomeTheme.muted)
    }
}

struct HomeToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(HomeTypography.body.weight(.medium))
                if let subtitle {
                    Text(subtitle).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                }
            }
        }
        .tint(HomeTheme.blue)
        .frame(minHeight: HomeMetrics.controlHeight)
    }
}

struct HomeToastView: View {
    let message: String
    var icon = "checkmark.circle.fill"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(HomeTheme.success)
            Text(message).font(HomeTypography.body.weight(.medium))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 42)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }
}

enum HomeStatusKind: Hashable {
    case empty, loading, error, success
}

struct HomeStatusView: View {
    let kind: HomeStatusKind
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            if kind == .loading {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(title).font(HomeTypography.cardTitle)
            Text(message)
                .font(HomeTypography.supporting)
                .foregroundStyle(HomeTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private var icon: String {
        switch kind {
        case .empty: "tray"
        case .loading: "arrow.triangle.2.circlepath"
        case .error: "exclamationmark.triangle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .empty, .loading: HomeTheme.muted
        case .error: HomeTheme.danger
        case .success: HomeTheme.success
        }
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
