import SwiftUI

struct PetLitterManagementView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var sheet: LitterSheet?

    private enum LitterSheet: String, Identifiable {
        case initialize, refill, replace
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeMetrics.sectionSpacing) {
                HomeSectionHeader(title: "猫砂余量")
                HomeCard {
                    if let state = store.data.litterBoxState, let prediction = store.litterPrediction {
                        VStack(spacing: 18) {
                            HStack(spacing: 18) {
                                progressRing(prediction)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(prediction.hasEnoughData ? "预计可用 \(prediction.daysRemaining ?? 0) 天" : "数据积累中")
                                        .font(HomeTypography.sectionTitle)
                                    Text(prediction.shouldRefill ? "建议补充猫砂" : "预计 \(prediction.thresholdDate ?? "--") 前补充")
                                        .font(HomeTypography.body)
                                        .foregroundStyle(prediction.shouldRefill ? HomeTheme.orange : HomeTheme.muted)
                                    Text("当前预计 \(prediction.currentAmount.formatted(.number.precision(.fractionLength(1)))) kg · 基准 \(state.baseAmount.formatted(.number.precision(.fractionLength(1)))) kg")
                                        .font(HomeTypography.supporting)
                                        .foregroundStyle(HomeTheme.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            HStack(spacing: 10) {
                                Button("补猫砂") { sheet = .refill; NativeHaptics.tap() }.buttonStyle(HomePrimaryButtonStyle())
                                Button("换猫砂") { sheet = .replace; NativeHaptics.warning() }.buttonStyle(HomeSecondaryButtonStyle())
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            EmptyState(icon: "gauge.with.dots.needle.33percent", title: "尚未初始化猫砂余量", message: "初始化后，首页会显示预计可用天数和补充提醒。")
                            Button("初始化猫砂余量") { sheet = .initialize }.buttonStyle(HomePrimaryButtonStyle())
                        }
                    }
                }
            }
            .padding(HomeMetrics.pageInset)
        }
        .background(HomeTheme.background)
        .navigationTitle("猫砂管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { value in
            switch value {
            case .initialize: LitterInitializeView()
            case .refill: LitterOperationView(type: .refill)
            case .replace: LitterOperationView(type: .replace)
            }
        }
    }

    private func progressRing(_ prediction: LitterPrediction) -> some View {
        ZStack {
            Circle().stroke(HomeTheme.line, lineWidth: 8)
            Circle()
                .trim(from: 0, to: prediction.progress)
                .stroke(prediction.shouldRefill ? HomeTheme.orange : HomeTheme.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((prediction.progress * 100).rounded()))%")
                .font(HomeTypography.cardTitle)
                .foregroundStyle(prediction.shouldRefill ? HomeTheme.orange : HomeTheme.blue)
        }
        .frame(width: 88, height: 88)
    }
}
