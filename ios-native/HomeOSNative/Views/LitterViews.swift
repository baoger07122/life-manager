import SwiftUI

struct LitterInitializeView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount = 0.0
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("猫砂盆当前总余量") {
                    HStack {
                        TextField("0", value: $amount, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .font(HomeTypography.body)
                        Text("kg").foregroundStyle(HomeTheme.muted)
                    }
                    DatePicker("初始化日期", selection: $date, displayedComponents: .date)
                }
                Section {
                    Text("初始化只建立猫砂盆状态，不扣减家庭猫砂库存。首次进度为 100%，预测暂显示数据不足。")
                        .font(HomeTypography.supporting)
                        .foregroundStyle(HomeTheme.muted)
                }
            }
            .navigationTitle("初始化猫砂余量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if store.initializeLitter(amount: amount, occurrenceDate: LitterPredictionService.format(date)) {
                            dismiss()
                        }
                    }
                    .disabled(amount <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct LitterOperationView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let type: LitterOperationType
    @State private var quantityTexts: [String: String] = [:]
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                if store.litterProducts.isEmpty {
                    Section {
                        EmptyState(icon: "circle.hexagongrid.fill", title: "没有可用猫砂库存", message: "请先在宠物物品中添加猫砂产品。")
                    }
                } else {
                    ForEach(groupedProducts) { group in
                        Section(group.type) {
                            ForEach(group.products) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name).font(HomeTypography.cardTitle)
                                            Text("库存 \(store.petInventory(for: item.id).formatted())\(item.unit)")
                                                .font(HomeTypography.supporting)
                                                .foregroundStyle(HomeTheme.muted)
                                        }
                                        Spacer()
                                        Button("全部") {
                                            quantityTexts[item.id] = store.petInventory(for: item.id)
                                                .formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
                                            NativeHaptics.selection()
                                        }
                                        .font(HomeTypography.supporting.weight(.semibold))
                                    }
                                    HStack {
                                        Text("加入数量").font(HomeTypography.body)
                                        Spacer()
                                        TextField("0.00", text: quantityBinding(for: item))
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .font(HomeTypography.body)
                                            .frame(maxWidth: 120)
                                        Text(item.unit).foregroundStyle(HomeTheme.muted)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    Section("发生日期") {
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                    }
                    Section("本次汇总") {
                        if selectedLines.isEmpty {
                            Text("尚未选择产品").foregroundStyle(HomeTheme.muted)
                        } else {
                            ForEach(selectedLines, id: \.self) { line in Text(line).font(HomeTypography.body) }
                        }
                    }
                }
            }
            .navigationTitle(type == .replace ? "换猫砂" : "补猫砂")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") {
                        if store.performLitterOperation(
                            type: type,
                            quantities: selectedQuantities,
                            occurrenceDate: LitterPredictionService.format(date)
                        ) {
                            dismiss()
                        }
                    }
                    .disabled(selectedLines.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var groupedProducts: [LitterProductGroup] {
        let groups = Dictionary(grouping: store.litterProducts, by: \.type)
        return groups.keys.sorted().map { LitterProductGroup(type: $0, products: groups[$0] ?? []) }
    }

    private var selectedLines: [String] {
        store.litterProducts.compactMap { item in
            let value = parsedQuantity(for: item)
            return value > 0 ? "\(item.name) · \(value.formatted())\(item.unit)" : nil
        }
    }

    private var selectedQuantities: [String: Double] {
        Dictionary(uniqueKeysWithValues: store.litterProducts.compactMap { item in
            let value = parsedQuantity(for: item)
            return value > 0 ? (item.id, value) : nil
        })
    }

    private func parsedQuantity(for item: PetItem) -> Double {
        let text = (quantityTexts[item.id] ?? "").replacingOccurrences(of: ",", with: ".")
        return min(max(Double(text) ?? 0, 0), store.petInventory(for: item.id))
    }

    private func quantityBinding(for item: PetItem) -> Binding<String> {
        Binding(
            get: { quantityTexts[item.id] ?? "" },
            set: { quantityTexts[item.id] = $0 }
        )
    }
}

private struct LitterProductGroup: Identifiable {
    let type: String
    let products: [PetItem]
    var id: String { type }
}
