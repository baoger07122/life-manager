import SwiftUI

struct PetView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var selectedCategoryID = "all"
    @State private var selectedInventoryPrimaryID = "pet-root-food"
    @State private var litterSheet: LitterSheet?
    @State private var showMonthlyExpense = false
    @State private var statisticsPath: [StatisticsRoute] = []

    private enum StatisticsRoute: Hashable {
        case food
        case supply

        var capabilityKey: String {
            switch self {
            case .food: "petFood"
            case .supply: "petSupply"
            }
        }
    }

    private enum LitterSheet: String, Identifiable {
        case initialize, refill, replace
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $statisticsPath) {
            PetItemsListView(primaryID: $selectedInventoryPrimaryID) {
                header
            } statistics: {
                itemStatistics
            } footer: {
                timelineSection
            }
            .sheet(item: $litterSheet) { sheet in
                switch sheet {
                case .initialize: LitterInitializeView()
                case .refill: LitterOperationView(type: .refill)
                case .replace: LitterOperationView(type: .replace)
                }
            }
            .navigationDestination(isPresented: $showMonthlyExpense) {
                PetMonthlyExpenseView()
            }
            .navigationDestination(for: StatisticsRoute.self) { route in
                PetInventoryStatisticsView(capabilityKey: route.capabilityKey)
            }
        }
    }

    private var header: some View {
        PageTitle(title: "宠物")
    }

    private var itemStatistics: some View {
        return HomeCard(padding: 0) {
            HStack(spacing: 0) {
                Button {
                    statisticsPath.append(.food)
                    NativeHaptics.tap()
                } label: {
                    inventoryStatistic(title: "宠物食品", value: petInventoryTotal(capabilityKey: "petFood"), suffix: "件")
                }
                .buttonStyle(.plain)
                Divider().frame(height: 52)
                Button {
                    statisticsPath.append(.supply)
                    NativeHaptics.tap()
                } label: {
                    inventoryStatistic(title: "宠物用品", value: petInventoryTotal(capabilityKey: "petSupply"), suffix: "件")
                }
                .buttonStyle(.plain)
                Divider().frame(height: 52)
                Button {
                    showMonthlyExpense = true
                    NativeHaptics.tap()
                } label: {
                    inventoryStatistic(title: "本月开销", value: store.petMonthlyExpense(), suffix: "元", currency: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
        }
    }

    private func inventoryStatistic(title: String, value: Double, suffix: String, currency: Bool = false) -> some View {
        VStack(spacing: 5) {
            Text(title).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(currency
                    ? "¥\(value.formatted(.number.precision(.fractionLength(0...2))))"
                    : value.formatted(.number.precision(.fractionLength(0...2))))
                    .font(.system(size: currency ? 18 : 22, weight: .semibold))
                    .foregroundStyle(HomeTheme.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if !currency {
                    Text(suffix).font(HomeTypography.supporting).foregroundStyle(HomeTheme.blue)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func petInventoryTotal(capabilityKey: String) -> Double {
        guard let rootName = store.petRootCategory(capabilityKey: capabilityKey)?.name else { return 0 }
        return store.activePetItems
            .filter { $0.resolvedPrimaryCategory == rootName }
            .reduce(0) { $0 + store.petInventory(for: $1.id) }
    }

    private var litterSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HomeSectionHeader(title: "猫砂进度管理")
            HomeCard {
                if let state = store.data.litterBoxState, let prediction = store.litterPrediction {
                    VStack(spacing: 16) {
                        HStack(spacing: 18) {
                            ZStack {
                                Circle().stroke(HomeTheme.line, lineWidth: 9)
                                Circle()
                                    .trim(from: 0, to: prediction.progress)
                                    .stroke(
                                        prediction.shouldRefill ? HomeTheme.orange : HomeTheme.blue,
                                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 2) {
                                    Text("\(Int((prediction.progress * 100).rounded()))%")
                                        .font(HomeTypography.cardTitle)
                                    Text("预计").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                                }
                            }
                            .frame(width: 96, height: 96)

                            VStack(alignment: .leading, spacing: 7) {
                                Text("预计余量 \(prediction.currentAmount.formatted(.number.precision(.fractionLength(1)))) kg")
                                    .font(HomeTypography.sectionTitle)
                                if prediction.hasEnoughData {
                                    Text("预计可用 \(prediction.daysRemaining ?? 0) 天").font(HomeTypography.body)
                                    Text(prediction.shouldRefill ? "建议补充猫砂" : "预计 \(HomeDateText.display(prediction.thresholdDate)) 达到 40%")
                                        .font(HomeTypography.supporting.weight(.semibold))
                                        .foregroundStyle(prediction.shouldRefill ? HomeTheme.orange : HomeTheme.muted)
                                } else {
                                    Text("预计可用天数：数据不足").font(HomeTypography.body)
                                    Text("补砂日期：数据不足").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                                }
                                Text("当前基准 \(state.baseAmount.formatted(.number.precision(.fractionLength(1)))) kg")
                                    .font(HomeTypography.supporting)
                                    .foregroundStyle(HomeTheme.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 10) {
                            Button("补猫砂") { litterSheet = .refill; NativeHaptics.tap() }
                                .buttonStyle(HomePrimaryButtonStyle())
                            Button("换猫砂") { litterSheet = .replace; NativeHaptics.warning() }
                                .buttonStyle(HomeSecondaryButtonStyle())
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        EmptyState(icon: "gauge.with.dots.needle.33percent", title: "尚未初始化猫砂余量", message: "只填写猫砂盆当前总余量，不会扣减家庭库存。")
                        Button("初始化猫砂余量") { litterSheet = .initialize; NativeHaptics.tap() }
                            .buttonStyle(HomePrimaryButtonStyle())
                            .frame(maxWidth: 260)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("宠物事项").font(HomeTypography.sectionTitle)
            HomeCard(padding: 0) {
                VStack(spacing: 0) {
                    eventFilters
                    Divider()
                    if filteredEvents.isEmpty {
                        EmptyState(icon: "calendar.badge.clock", title: "暂无符合条件的事项", message: "可以添加事项或切换事项类型。")
                            .padding(.horizontal, 14)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredEvents.enumerated()), id: \.element.id) { index, event in
                                timelineRow(event, index: index, count: filteredEvents.count)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var eventFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        filterTab(title: "全部", id: "all", selection: $selectedCategoryID, prominent: true)
                        ForEach(store.activePetEventCategories) { category in
                            filterTab(title: category.name, id: category.id, selection: $selectedCategoryID, prominent: true)
                        }
                    }
                }
                NavigationLink { PetEventEditorView() } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(HomeTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(HomePressButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { NativeHaptics.tap() })
                .accessibilityLabel("添加宠物事项")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func filterTab(title: String, id: String, selection: Binding<String>, prominent: Bool = false) -> some View {
        Button {
            selection.wrappedValue = id
            NativeHaptics.selection()
        } label: {
            HomeUnderlineTab(title: title, selected: selection.wrappedValue == id, prominent: prominent)
        }
        .buttonStyle(.plain)
    }

    private var filteredEvents: [PetEvent] {
        store.data.petEvents.filter { event in
            selectedCategoryID == "all" || event.categoryID == selectedCategoryID
        }
        .sorted {
            if $0.occurrenceDate == $1.occurrenceDate { return $0.createdAt > $1.createdAt }
            return $0.occurrenceDate > $1.occurrenceDate
        }
    }

    private func timelineRow(_ event: PetEvent, index: Int, count: Int) -> some View {
        NavigationLink { PetEventDetailView(eventID: event.id) } label: {
            HStack(alignment: .center, spacing: 11) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(index == 0 ? Color.clear : HomeTheme.line)
                        .frame(width: 1.5, height: 24)
                    ZStack {
                        Circle()
                            .fill(index == 0 ? HomeTheme.blue : HomeTheme.line)
                            .frame(width: index == 0 ? 10 : 8, height: index == 0 ? 10 : 8)
                    }
                    .frame(width: 10, height: 10)
                    Rectangle()
                        .fill(index == count - 1 ? Color.clear : HomeTheme.line)
                        .frame(width: 1.5, height: 24)
                }
                .frame(width: 12)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(event.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(HomeTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if shouldShowType(for: event) {
                            Text(event.categoryNameSnapshot)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(HomeTheme.blue)
                                .lineLimit(1)
                        }
                    }
                    Text(eventSecondaryLine(event))
                        .font(.system(size: 12))
                        .foregroundStyle(HomeTheme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shouldShowType(for event: PetEvent) -> Bool {
        event.name.caseInsensitiveCompare(event.categoryNameSnapshot) != .orderedSame
    }

    private func eventSecondaryLine(_ event: PetEvent) -> String {
        let cleanNote = (event.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanNote.isEmpty
            ? HomeDateText.display(event.occurrenceDate)
            : "\(HomeDateText.display(event.occurrenceDate)) · \(cleanNote)"
    }
}

private struct PetMonthlyExpenseView: View {
    @EnvironmentObject private var store: HomeStore

    private var transactions: [PetInventoryTransaction] {
        store.petMonthlyOutboundTransactions()
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: HomeMetrics.sectionSpacing) {
                HomeCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本月开销").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                        Text("¥\(store.petMonthlyExpense().formatted(.number.precision(.fractionLength(2))))")
                            .font(HomeTypography.metric)
                            .foregroundStyle(HomeTheme.blue)
                        Text("按出库时的单价快照计算；旧记录缺少快照时使用当前最新单价。")
                            .font(HomeTypography.supporting)
                            .foregroundStyle(HomeTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HomeCard(padding: 0) {
                    if transactions.isEmpty {
                        EmptyState(icon: "cart", title: "本月暂无出库开销", message: "完成宠物物品出库后会自动记录。")
                            .padding(.vertical, 12)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(transactions) { transaction in
                                expenseRow(transaction)
                                if transaction.id != transactions.last?.id { Divider().padding(.leading, 52) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, HomeMetrics.pageInset)
            .padding(.vertical, 16)
        }
        .background(HomeTheme.background)
        .navigationTitle("本月开销")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func expenseRow(_ transaction: PetInventoryTransaction) -> some View {
        let item = store.data.petItems.first { $0.id == transaction.productID }
        let unitPrice = transaction.unitPrice ?? store.latestPetUnitPrice(for: transaction.productID) ?? 0
        let total = transaction.totalPrice ?? abs(transaction.quantityChange) * unitPrice
        return HStack(spacing: 11) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(HomeTheme.orange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(item?.displayTitle ?? "已删除物品")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(HomeTheme.ink)
                    .lineLimit(1)
                Text(unitPrice > 0
                    ? "\(HomeDateText.display(transaction.occurrenceDate)) · \(abs(transaction.quantityChange).formatted(.number.precision(.fractionLength(0...2))))\(transaction.unit) · ¥\(unitPrice.formatted(.number.precision(.fractionLength(2))))/\(transaction.unit)"
                    : "\(HomeDateText.display(transaction.occurrenceDate)) · \(abs(transaction.quantityChange).formatted(.number.precision(.fractionLength(0...2))))\(transaction.unit) · 待补价格")
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text("¥\(total.formatted(.number.precision(.fractionLength(2))))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HomeTheme.ink)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
    }
}
