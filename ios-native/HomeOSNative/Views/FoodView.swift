import SwiftUI
import PhotosUI
import UIKit

private enum FoodSortMode: String, CaseIterable, Identifiable {
    case newest, expiry, quantity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: "最近添加"
        case .expiry: "临期优先"
        case .quantity: "库存从多到少"
        }
    }
}

private struct FoodScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct FoodView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var query = ""
    @State private var selectedLocation = ""
    @State private var selectedCategory = "全部"
    @State private var sortMode: FoodSortMode = .newest
    @State private var showEditor = false
    @State private var showSearch = false
    @State private var scrollOffset: CGFloat = 0
    @FocusState private var searchFocused: Bool

    private var categories: [String] {
        ["全部"] + store.categories(for: .food).map(\.name)
    }
    private var locations: [String] { store.foodLocations }
    private var foods: [FoodItem] {
        store.data.foods.filter { item in
            (selectedLocation.isEmpty || item.location == selectedLocation)
                && (selectedCategory == "全部" || item.category == selectedCategory)
                && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
                    || item.brand.localizedCaseInsensitiveContains(query)
                    || item.category.localizedCaseInsensitiveContains(query))
        }.sorted { left, right in
            switch sortMode {
            case .newest: (left.quickAddedAt ?? 0) > (right.quickAddedAt ?? 0)
            case .expiry: left.expiry < right.expiry
            case .quantity: left.quantity > right.quantity
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: FoodScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named("food-scroll")).minY
                    )
                }
                .frame(height: 0)
                VStack(spacing: HomeMetrics.sectionSpacing) {
                    header
                    locationCard
                    inventoryCard
                }
                .padding(.horizontal, HomeMetrics.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .coordinateSpace(name: "food-scroll")
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard scrollOffset > -8, value.translation.height > 28, !showSearch else { return }
                        withAnimation(.easeOut(duration: 0.18)) { showSearch = true }
                        NativeHaptics.selection()
                    }
            )
            .background(HomeTheme.background)
            .onPreferenceChange(FoodScrollOffsetPreferenceKey.self) { offset in
                scrollOffset = offset
                if offset > 44, !showSearch {
                    withAnimation(.easeOut(duration: 0.18)) { showSearch = true }
                    NativeHaptics.selection()
                } else if offset < -100, showSearch, query.isEmpty, !searchFocused {
                    withAnimation(.easeOut(duration: 0.16)) { showSearch = false }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showSearch {
                    foodSearchField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showEditor) { NavigationStack { FoodEditorView() } }
            .alert("提示", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
                Button("知道了") { store.lastError = nil }
            } message: { Text(store.lastError ?? "") }
        }
    }

    private var header: some View {
        PageTitle(title: "食品")
    }

    private var foodSearchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(HomeTheme.muted)
            TextField("搜索食品", text: $query)
                .font(HomeTypography.body)
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                    NativeHaptics.tap()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Button("收起") {
                query = ""
                searchFocused = false
                withAnimation(.easeOut(duration: 0.16)) { showSearch = false }
                NativeHaptics.tap()
            }
            .font(HomeTypography.supporting.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(HomeTheme.line, lineWidth: 0.7) }
        .padding(.horizontal, HomeMetrics.pageInset)
        .padding(.vertical, 6)
        .background(HomeTheme.background.opacity(0.96))
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("存放位置").font(HomeTypography.sectionTitle)
                Spacer()
                NavigationLink {
                    FoodLocationManagementView()
                } label: {
                    HStack(spacing: 3) {
                        Text("管理")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(HomeTypography.supporting.weight(.semibold))
                    .foregroundStyle(HomeTheme.blue)
                }
            }
            HomeCard(padding: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(locations, id: \.self) { location in
                            Button {
                                selectedLocation = location
                                selectedCategory = "全部"
                                NativeHaptics.selection()
                            } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: locationIcon(location))
                                        .font(.system(size: 18, weight: .medium))
                                    Text(location).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text("\(foodCount(at: location)) 项")
                                        .font(.system(size: 11)).opacity(0.72)
                                }
                                .foregroundStyle(selectedLocation == location ? HomeTheme.blue : HomeTheme.muted)
                                .frame(width: 82, height: 68)
                                .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear {
            if selectedLocation.isEmpty { selectedLocation = locations.first ?? "" }
        }
        .onChange(of: store.foodLocations) { _, available in
            if !available.contains(selectedLocation) {
                selectedLocation = available.first ?? ""
            }
        }
    }

    private func foodCount(at location: String) -> Int {
        store.data.foods.filter { $0.location == location }.count
    }

    private func locationIcon(_ location: String) -> String {
        if location.contains("冷冻") || location.contains("冰柜") { return "snowflake" }
        if location.contains("冷藏") || location.contains("冰箱") { return "refrigerator.fill" }
        return "cabinet.fill"
    }

    private var inventoryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HomeSectionHeader(title: "食品库存", actionTitle: "新增") {
                NativeHaptics.tap()
                showEditor = true
            }
            HomeCard(padding: 0) {
                VStack(spacing: 0) {
                    categorySelector
                    Divider()
                    if foods.isEmpty {
                        EmptyState(icon: "refrigerator.fill", title: "没有符合条件的食品", message: "可切换分类、位置或新增食品。")
                            .padding(.vertical, 16)
                    } else {
                        FoodInventoryRows(items: foods)
                    }
                }
            }
        }
    }

    private var categorySelector: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            selectedCategory = category; NativeHaptics.selection()
                        } label: {
                            HomeUnderlineTab(title: category, selected: selectedCategory == category, prominent: category == "全部")
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.leading, 14)
            }
            Menu {
                ForEach(FoodSortMode.allCases) { option in
                    Button {
                        sortMode = option
                        NativeHaptics.selection()
                    } label: {
                        if sortMode == option { Label(option.title, systemImage: "checkmark") }
                        else { Text(option.title) }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HomeTheme.muted)
                    .frame(width: 44, height: 44)
                    .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("当前排序：\(sortMode.title)")
            .padding(.trailing, 4)
        }
        .padding(.vertical, 8)
    }

}

struct FoodDetailView: View {
    @EnvironmentObject private var store: HomeStore
    let itemID: String
    @State private var showEditor = false
    private var item: FoodItem? { store.data.foods.first { $0.id == itemID } }

    var body: some View {
        ScrollView {
            if let item {
                VStack(spacing: 12) {
                    HomeCard {
                        HStack(spacing: 14) {
                            FoodItemThumbnail(item: item, size: 72)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name).font(HomeTypography.sectionTitle)
                                if !item.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(item.brand).font(.system(size: 12)).foregroundStyle(HomeTheme.muted)
                                }
                                Text([item.category, item.spec].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 13)).foregroundStyle(HomeTheme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(item.quantity.formatted(.number.precision(.fractionLength(0...2))))
                                    .font(HomeTypography.metric).foregroundStyle(HomeTheme.blue)
                                Text(item.unit).font(.system(size: 12)).foregroundStyle(HomeTheme.muted)
                            }
                        }
                    }
                    HomeCard {
                        VStack(spacing: 0) {
                            detailRow("存放位置", item.location)
                            Divider()
                            detailRow("生产日期", HomeDateText.display(item.productionDate))
                            Divider()
                            detailRow("保质期至", HomeDateText.display(item.expiry))
                        }
                    }
                    if let history = item.priceHistory, !history.isEmpty {
                        HomeCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("价格历史").font(HomeTypography.cardTitle)
                                ForEach(history.prefix(5)) { record in
                                    HStack {
                                        Text(HomeDateText.display(record.date)).font(.system(size: 12)).foregroundStyle(HomeTheme.muted)
                                        Spacer()
                                        Text("总价 ¥\(record.price.formatted(.number.precision(.fractionLength(2))))").font(.system(size: 12))
                                        Text("¥\((record.quantity > 0 ? record.price / record.quantity : 0).formatted(.number.precision(.fractionLength(2))))/\(record.unit)")
                                            .font(.system(size: 12)).foregroundStyle(HomeTheme.muted)
                                    }
                                }
                            }
                        }
                    }
                }.padding(HomeMetrics.pageInset)
            }
        }
        .background(HomeTheme.background)
        .navigationTitle(item?.name ?? "食品详情").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("编辑") { NativeHaptics.tap(); showEditor = true } } }
        .sheet(isPresented: $showEditor) { NavigationStack { FoodEditorView(itemID: itemID) } }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(.system(size: 14)).foregroundStyle(HomeTheme.muted); Spacer(); Text(value).font(.system(size: 14)) }
            .frame(minHeight: 42)
    }
}

private enum FoodExpiryInputMode: String, CaseIterable, Identifiable {
    case days, date
    var id: String { rawValue }
    var title: String { self == .days ? "保质天数" : "选择日期" }
}

struct FoodEditorView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    var itemID: String?
    @State private var name = ""
    @State private var brand = ""
    @State private var category = ""
    @State private var spec = ""
    @State private var quantityText = ""
    @State private var unit = "个"
    @State private var location = "冷藏区"
    @State private var expiry = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var productionDate = Date()
    @State private var expiryMode: FoodExpiryInputMode = .days
    @State private var shelfLifeDays = 7
    @State private var addToQuickManagement = false
    @State private var icon = "🥬"
    @State private var purchaseTotalText = ""
    @State private var imageReference: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loaded = false
    @State private var sheet: FoodEditorSheet?

    private var existing: FoodItem? { itemID.flatMap { id in store.data.foods.first { $0.id == id } } }
    private var categoryNames: [String] { store.categories(for: .food).map(\.name) }
    private let units = ["个", "袋", "盒", "瓶", "罐", "颗", "克", "千克"]
    private var locations: [String] { store.foodLocations.isEmpty ? ["冷藏区", "冷冻区", "常温区"] : store.foodLocations }
    private var purchaseTotal: Double? {
        let value = purchaseTotalText.replacingOccurrences(of: ",", with: ".")
        guard let total = Double(value), total > 0 else { return nil }
        return total
    }
    private var quantity: Double {
        let normalized = quantityText.replacingOccurrences(of: ",", with: ".")
        return max(Double(normalized) ?? 0, 0)
    }
    private var calculatedUnitPrice: Double? {
        guard let purchaseTotal, quantity > 0 else { return nil }
        return purchaseTotal / quantity
    }
    private var resolvedExpiry: Date {
        guard expiryMode == .days else { return expiry }
        return Calendar.current.date(byAdding: .day, value: max(0, shelfLifeDays), to: productionDate) ?? productionDate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: HomeMetrics.sectionSpacing) {
                imageCard

                Button { NativeHaptics.tap(); sheet = .category } label: {
                    HomeCard(padding: 0) {
                        HStack(spacing: 10) {
                            Text("分类").font(HomeTypography.cardTitle).foregroundStyle(HomeTheme.ink)
                            Spacer()
                            Text(category.isEmpty ? "请选择" : category).font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, HomeMetrics.cardPadding)
                        .frame(minHeight: 56)
                    }
                }
                .buttonStyle(.plain)

                HomeCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("基本信息").font(HomeTypography.sectionTitle).padding(.bottom, 8)
                        editorButtonRow(title: "品牌", value: brand.isEmpty ? "无品牌" : brand) {
                            NativeHaptics.tap()
                            sheet = .brand
                        }
                        divider
                        editorTextRow(title: "名称", placeholder: "请输入名称", text: $name)
                        divider
                        editorTextRow(title: "规格", placeholder: "例如950ml、12枚", text: $spec)
                        divider
                        menuRow(title: "库存单位", value: unit, values: units, selection: $unit)
                        divider
                        menuRow(title: "存放位置", value: location, values: locations, selection: $location)
                    }
                }

                HomeCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("日期信息").font(HomeTypography.sectionTitle).padding(.bottom, 8)
                        DatePicker("生产日期", selection: $productionDate, displayedComponents: .date)
                            .font(HomeTypography.body).frame(minHeight: HomeMetrics.controlHeight)
                        divider
                        Picker("保质期方式", selection: $expiryMode) {
                            ForEach(FoodExpiryInputMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 8)
                        if expiryMode == .days {
                            divider
                            editorWholeNumberRow(title: "保质天数", value: $shelfLifeDays)
                            divider
                            HStack {
                                Text("预计到期").font(HomeTypography.body)
                                Spacer()
                                Text(HomeDateText.display(storage(resolvedExpiry)))
                                    .font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                            }
                            .frame(minHeight: HomeMetrics.controlHeight)
                        } else {
                            divider
                            DatePicker("保质期至", selection: $expiry, displayedComponents: .date)
                                .font(HomeTypography.body).frame(minHeight: HomeMetrics.controlHeight)
                        }
                    }
                }

                HomeCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("库存设置").font(HomeTypography.sectionTitle).padding(.bottom, 8)
                        if itemID == nil {
                            editorTextRow(title: "初始库存", placeholder: "0", text: $quantityText, keyboard: .decimalPad)
                            divider
                            editorTextRow(title: "本次购入总额（选填）", placeholder: "¥0.00", text: $purchaseTotalText, keyboard: .decimalPad)
                            divider
                            HStack {
                                Text("折算单价").font(HomeTypography.body)
                                Spacer()
                                Text(calculatedUnitPrice.map { "¥\($0.formatted(.number.precision(.fractionLength(2))))/\(unit)" } ?? "自动计算")
                                    .font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                            }
                            .frame(minHeight: HomeMetrics.controlHeight)
                        } else {
                            Text("库存数量请通过入库、出库操作进行调整。")
                                .font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                HomeCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("首页快捷管理").font(HomeTypography.sectionTitle)
                        Toggle("添加到首页快捷管理", isOn: $addToQuickManagement)
                            .font(HomeTypography.body)
                            .tint(HomeTheme.blue)
                        Text("开启后可在首页直接查看相同信息，并快速进行入库和出库。")
                            .font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                    }
                }

                Button("保存", action: save)
                    .buttonStyle(HomePrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category.isEmpty || unit.isEmpty)
                    .padding(.horizontal, 42)

                if let itemID {
                    Button("删除食品", role: .destructive) {
                        store.deleteFood(id: itemID); dismiss()
                    }
                    .font(HomeTypography.body)
                    .frame(minHeight: HomeMetrics.minimumTapTarget)
                }
            }
            .padding(.horizontal, HomeMetrics.pageInset)
            .padding(.vertical, 16)
        }
        .background(HomeTheme.background)
        .navigationTitle(itemID == nil ? "新增食品" : "编辑食品").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task { load() }
        .onChange(of: selectedPhoto) { _, photo in
            Task {
                if let data = try? await photo?.loadTransferable(type: Data.self) {
                    imageReference = "data:image/jpeg;base64," + data.base64EncodedString()
                    NativeHaptics.selection()
                }
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .category: FoodCategorySelectionSheet(category: $category)
            case .brand: FoodBrandSelectionSheet(brand: $brand)
            }
        }
    }

    private var imageCard: some View {
        HomeCard {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Group {
                    if let imageReference {
                        PetStoredImage(reference: imageReference)
                            .frame(maxWidth: .infinity).frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "refrigerator.fill").font(.system(size: 34)).foregroundStyle(HomeTheme.muted)
                            Label("添加食品图片", systemImage: "photo").font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                        }
                        .frame(maxWidth: .infinity).frame(height: 180)
                    }
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { NativeHaptics.tap() })
        }
    }

    private var divider: some View { Divider().overlay(HomeTheme.line) }

    private func editorButtonRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(HomeTypography.body).foregroundStyle(HomeTheme.ink)
                Spacer()
                Text(value).font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }.frame(minHeight: HomeMetrics.controlHeight)
        }.buttonStyle(.plain)
    }

    private func editorTextRow(title: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Text(title).font(HomeTypography.body)
            Spacer()
            TextField(placeholder, text: text)
                .font(HomeTypography.body).keyboardType(keyboard).multilineTextAlignment(.trailing)
        }.frame(minHeight: HomeMetrics.controlHeight)
    }

    private func editorNumberRow(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(HomeTypography.body)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
                .font(HomeTypography.body).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }.frame(minHeight: HomeMetrics.controlHeight)
    }

    private func editorWholeNumberRow(title: String, value: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(HomeTypography.body)
            Spacer()
            TextField("0", value: value, format: .number)
                .font(HomeTypography.body).keyboardType(.numberPad).multilineTextAlignment(.trailing)
            Text("天").font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
        }.frame(minHeight: HomeMetrics.controlHeight)
    }

    private func menuRow(title: String, value: String, values: [String], selection: Binding<String>) -> some View {
        HStack {
            Text(title).font(HomeTypography.body)
            Spacer()
            Picker(title, selection: Binding(
                get: { selection.wrappedValue },
                set: { value in
                    selection.wrappedValue = value
                    NativeHaptics.selection()
                }
            )) { ForEach(values, id: \.self) { Text($0).tag($0) } }
                .pickerStyle(.menu).labelsHidden()
        }.frame(minHeight: HomeMetrics.controlHeight)
    }

    private func load() {
        guard !loaded else { return }; defer { loaded = true }
        if category.isEmpty { category = categoryNames.first ?? "其他" }
        if !locations.contains(location) { location = locations.first ?? "冷藏区" }
        guard let item = existing else { return }
        name = item.name; brand = item.brand; category = item.category; spec = item.spec
        quantityText = item.quantity.formatted(.number.precision(.fractionLength(0...2)))
        unit = item.unit; location = item.location; icon = item.icon
        imageReference = item.thumb; addToQuickManagement = item.quick; expiryMode = .date
        productionDate = parse(item.productionDate) ?? Date(); expiry = parse(item.expiry) ?? expiry
    }

    private func save() {
        let old = existing
        let item = FoodItem(
            id: old?.id ?? UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines), quantity: max(0, quantity),
            unit: unit, expiry: storage(resolvedExpiry), productionDate: storage(productionDate), location: location, category: category,
            tags: old?.tags ?? [], brand: brand.trimmingCharacters(in: .whitespacesAndNewlines), spec: spec.trimmingCharacters(in: .whitespacesAndNewlines),
            price: purchaseTotal ?? old?.price ?? 0, icon: icon.isEmpty ? "🥬" : icon, thumb: imageReference, quick: addToQuickManagement,
            quickAddedAt: addToQuickManagement ? (old?.quickAddedAt ?? Date().timeIntervalSince1970) : old?.quickAddedAt, quickReducePresets: old?.quickReducePresets ?? [1],
            purchases: initialPurchases(old), priceHistory: initialPriceHistory(old)
        )
        store.upsertFood(item); dismiss()
    }

    private func initialPurchases(_ old: FoodItem?) -> [PurchaseRecord]? {
        guard old == nil, let purchaseTotal, quantity > 0 else { return old?.purchases }
        return [PurchaseRecord(id: UUID().uuidString, date: storage(Date()), quantity: quantity, unit: unit, price: purchaseTotal, expiry: storage(resolvedExpiry))]
    }

    private func initialPriceHistory(_ old: FoodItem?) -> [PurchaseRecord]? {
        guard old == nil else { return old?.priceHistory }
        return initialPurchases(old)
    }

    private func storage(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    private func parse(_ text: String?) -> Date? {
        guard let text else { return nil }; let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy-MM-dd"; return f.date(from: text)
    }
}

private enum FoodEditorSheet: String, Identifiable {
    case category, brand
    var id: String { rawValue }
}

private struct FoodCategorySelectionSheet: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @Binding var category: String
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("食品分类").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                HomeTagFlowLayout(spacing: 8) {
                    ForEach(store.categories(for: .food)) { option in
                        Button {
                            draft = option.name; NativeHaptics.selection()
                        } label: {
                            Text(option.name).font(HomeTypography.body)
                                .foregroundStyle(draft == option.name ? HomeTheme.blue : HomeTheme.ink)
                                .padding(.horizontal, 18).frame(height: 40)
                                .background(draft == option.name ? HomeTheme.blue.opacity(0.10) : HomeTheme.background, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Button("完成") { category = draft; NativeHaptics.success(); dismiss() }
                    .buttonStyle(HomePrimaryButtonStyle()).disabled(draft.isEmpty)
            }
            .padding(.horizontal, HomeMetrics.pageInset).padding(.bottom, 16)
            .navigationTitle("选择分类").navigationBarTitleDisplayMode(.inline)
            .onAppear { draft = category }
        }
        .presentationDetents([.height(330)]).presentationDragIndicator(.visible)
    }
}

private struct FoodBrandSelectionSheet: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @Binding var brand: String
    @State private var query = ""
    @State private var draft = ""

    private var allBrands: [ManagedBrand] { store.brands(for: .food) }
    private var filtered: [ManagedBrand] { query.isEmpty ? allBrands : allBrands.filter { $0.name.localizedCaseInsensitiveContains(query) } }
    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool { !cleanQuery.isEmpty && !allBrands.contains { $0.name.caseInsensitiveCompare(cleanQuery) == .orderedSame } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(HomeTheme.muted)
                    TextField("搜索品牌", text: $query).font(HomeTypography.body)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) } }
                }
                .padding(.horizontal, 12).frame(height: HomeMetrics.controlHeight)
                .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: 12))

                Text(query.isEmpty ? "全部品牌" : "搜索结果").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                HomeTagFlowLayout(spacing: 8) {
                    brandChip("无品牌", storedValue: "")
                    ForEach(filtered) { option in brandChip(option.name, storedValue: option.name) }
                }
                if canAdd {
                    Button {
                        if store.addManagedBrand(name: cleanQuery, modules: [.food]) {
                            draft = cleanQuery
                            query = ""
                            NativeHaptics.success()
                        }
                    } label: { Label("新增品牌“\(cleanQuery)”", systemImage: "plus.circle.fill").font(HomeTypography.body) }
                }
                Spacer()
                Button("完成") { brand = draft; NativeHaptics.success(); dismiss() }.buttonStyle(HomePrimaryButtonStyle())
            }
            .padding(.horizontal, HomeMetrics.pageInset).padding(.bottom, 16)
            .navigationTitle("选择品牌").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .primaryAction) { NavigationLink("管理") { BrandManagementView() } } }
            .onAppear { draft = brand }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func brandChip(_ title: String, storedValue: String) -> some View {
        Button { draft = storedValue; NativeHaptics.selection() } label: {
            Text(title).font(HomeTypography.supporting.weight(.medium))
                .foregroundStyle(draft.caseInsensitiveCompare(storedValue) == .orderedSame ? HomeTheme.blue : HomeTheme.ink)
                .padding(.horizontal, 14).frame(height: 34)
                .background(draft.caseInsensitiveCompare(storedValue) == .orderedSame ? HomeTheme.blue.opacity(0.10) : HomeTheme.background, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}
