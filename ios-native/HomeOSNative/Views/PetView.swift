import SwiftUI

struct PetView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var selectedPetID = "all"
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
                    litterSection
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
        HStack(alignment: .center, spacing: 12) {
            PageTitle(title: "宠物", subtitle: "用品、猫砂状态与护理事项")
            NavigationLink {
                PetEventEditorView()
            } label: {
                Label("添加事项", systemImage: "plus")
                    .font(HomeTypography.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: HomeMetrics.controlHeight)
                    .background(HomeTheme.blue, in: RoundedRectangle(cornerRadius: HomeMetrics.controlRadius, style: .continuous))
            }
            .buttonStyle(HomePressButtonStyle())
        }
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
                                    Text(prediction.shouldRefill ? "建议补充猫砂" : "预计 \(prediction.thresholdDate ?? "--") 达到 40%")
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
            HomeSectionHeader(title: "宠物事项时间轴")
            filters
            if groupedEvents.isEmpty {
                HomeCard {
                    EmptyState(icon: "calendar.badge.clock", title: "暂无符合条件的事项", message: "当前筛选条件会保留，可以添加事项或切换筛选。")
                }
            } else {
                ForEach(groupedEvents) { group in
                    eventGroup(group.date, events: group.events)
                }
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "全部宠物", id: "all", selection: $selectedPetID)
                    ForEach(store.activePets) { pet in
                        filterChip(title: pet.name, id: pet.id, selection: $selectedPetID)
                    }
                }
            }
            if store.activePetEventCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(title: "全部分类", id: "all", selection: $selectedCategoryID)
                        ForEach(store.activePetEventCategories) { category in
                            filterChip(title: category.name, id: category.id, selection: $selectedCategoryID)
                        }
                    }
                }
            }
        }
    }

    private func filterChip(title: String, id: String, selection: Binding<String>) -> some View {
        Button {
            selection.wrappedValue = id
            NativeHaptics.selection()
        } label: {
            HomeChip(title: title, selected: selection.wrappedValue == id)
        }
        .buttonStyle(.plain)
    }

    private var filteredEvents: [PetEvent] {
        store.data.petEvents.filter { event in
            let matchesPet = selectedPetID == "all" || event.petIDs.contains(selectedPetID)
            let matchesCategory = selectedCategoryID == "all" || event.categoryID == selectedCategoryID
            return matchesPet && matchesCategory
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
        return HomeCard(padding: 14) {
            VStack(spacing: 0) {
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
                        NavigationLink {
                            PetEventDetailView(eventID: event.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.name).font(HomeTypography.cardTitle)
                                    Spacer()
                                    Text(event.categoryNameSnapshot)
                                        .font(HomeTypography.supporting)
                                        .foregroundStyle(HomeTheme.blue)
                                }
                                Text(petNames(for: event))
                                    .font(HomeTypography.supporting)
                                    .foregroundStyle(HomeTheme.muted)
                                if let note = event.note, !note.isEmpty {
                                    Text(note).font(HomeTypography.body).foregroundStyle(HomeTheme.muted).lineLimit(1)
                                }
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func relativeDateTitle(_ value: String) -> String {
        guard let date = LitterPredictionService.parse(value) else { return value }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return value
    }

    private func petNames(for event: PetEvent) -> String {
        guard !event.petNameSnapshots.isEmpty else { return "全部宠物" }
        return event.petNameSnapshots.enumerated().map { index, name in
            guard event.petIDs.indices.contains(index) else { return name }
            return store.activePets.contains(where: { $0.id == event.petIDs[index] }) ? name : "\(name)（已删除）"
        }.joined(separator: "、")
    }
}

private struct PetEventDateGroup: Identifiable {
    let date: String
    let events: [PetEvent]
    var id: String { date }
}
