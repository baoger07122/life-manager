import SwiftUI

struct PetView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var selectedCategoryID = "all"
    @State private var litterSheet: LitterSheet?

    private enum LitterSheet: String, Identifiable {
        case initialize, refill, replace
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HomeMetrics.sectionSpacing) {
                    header
                    PetItemsListView()
                    PetRatingsListView()
                    timelineSection
                }
                .padding(.horizontal, HomeMetrics.pageInset)
                .padding(.vertical, 18)
            }
            .background(HomeTheme.background)
            .scrollIndicators(.hidden)
            .sheet(item: $litterSheet) { sheet in
                switch sheet {
                case .initialize: LitterInitializeView()
                case .refill: LitterOperationView(type: .refill)
                case .replace: LitterOperationView(type: .replace)
                }
            }
        }
    }

    private var header: some View {
        PageTitle(title: "宠物")
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
                    if groupedEvents.isEmpty {
                    EmptyState(icon: "calendar.badge.clock", title: "暂无符合条件的事项", message: "当前筛选条件会保留，可以添加事项或切换筛选。")
                            .padding(.horizontal, 14)
                    } else {
                        ForEach(Array(groupedEvents.enumerated()), id: \.element.id) { index, group in
                            eventGroup(group.date, events: group.events)
                                .padding(.horizontal, 14)
                            if index < groupedEvents.count - 1 { Divider() }
                        }
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

    private var groupedEvents: [PetEventDateGroup] {
        let groups = Dictionary(grouping: filteredEvents, by: \.occurrenceDate)
        return groups.keys.sorted(by: >).map { PetEventDateGroup(date: $0, events: groups[$0] ?? []) }
    }

    private func eventGroup(_ date: String, events: [PetEvent]) -> some View {
        let collapsed = store.data.settings.petEventCollapsedDateGroups?[date] == true
        return VStack(spacing: 0) {
                Button {
                    store.setPetDateGroup(date, collapsed: !collapsed)
                    NativeHaptics.selection()
                } label: {
                    HStack {
                        Text(relativeDateTitle(date)).font(HomeTypography.cardTitle)
                        Spacer()
                        Text("\(events.count) 项").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                            .font(.caption.weight(.semibold)).foregroundStyle(HomeTheme.muted)
                    }
                    .frame(minHeight: 36)
                }
                .buttonStyle(.plain)

                if !collapsed {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Divider() }
                        NavigationLink { PetEventDetailView(eventID: event.id) } label: {
                            HStack(alignment: .top, spacing: 11) {
                                VStack(spacing: 0) {
                                    Circle().fill(HomeTheme.blue).frame(width: 9, height: 9)
                                    if index < events.count - 1 {
                                        Rectangle().fill(HomeTheme.line).frame(width: 1.5).frame(minHeight: 44)
                                    }
                                }
                                .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(event.name).font(HomeTypography.cardTitle)
                                        Spacer()
                                        Text(event.categoryNameSnapshot)
                                            .font(HomeTypography.supporting)
                                            .foregroundStyle(HomeTheme.blue)
                                    }
                                    if let note = event.note, !note.isEmpty {
                                        Text(note).font(HomeTypography.body).foregroundStyle(HomeTheme.muted).lineLimit(2)
                                    }
                                }
                                .padding(.bottom, 10)
                            }
                            .padding(.top, 9)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
    }

    private func relativeDateTitle(_ value: String) -> String {
        return HomeDateText.display(value)
    }
}

private struct PetEventDateGroup: Identifiable {
    let date: String
    let events: [PetEvent]
    var id: String { date }
}
