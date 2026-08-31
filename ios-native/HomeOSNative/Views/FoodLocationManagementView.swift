import SwiftUI

struct FoodLocationManagementView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var editor: FoodLocationEditor?

    var body: some View {
        List {
            Section {
                ForEach(store.foodLocations, id: \.self) { location in
                    Button {
                        editor = .rename(location)
                        NativeHaptics.selection()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon(location))
                                .foregroundStyle(HomeTheme.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(location).font(HomeTypography.body).foregroundStyle(HomeTheme.ink)
                                Text("\(store.data.foods.filter { $0.location == location }.count) 项食品")
                                    .font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onMove { source, destination in
                    var values = store.foodLocations
                    values.move(fromOffsets: source, toOffset: destination)
                    store.reorderFoodLocations(values)
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) where store.foodLocations.indices.contains(index) {
                        _ = store.deleteFoodLocation(store.foodLocations[index])
                    }
                }
            } footer: {
                Text("正在使用的位置需要先把其中食品移动到其他位置，才能删除。")
            }
        }
        .navigationTitle("存放位置管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .primaryAction) {
                Button { editor = .add; NativeHaptics.tap() } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editor) { mode in FoodLocationEditorSheet(mode: mode) }
        .alert("提示", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("知道了") { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
    }

    private func icon(_ location: String) -> String {
        if location.contains("冷冻") || location.contains("冰柜") { return "snowflake" }
        if location.contains("冷藏") || location.contains("冰箱") { return "refrigerator.fill" }
        return "cabinet.fill"
    }
}

private enum FoodLocationEditor: Identifiable {
    case add
    case rename(String)

    var id: String {
        switch self {
        case .add: "add"
        case .rename(let name): "rename-\(name)"
        }
    }
}

private struct FoodLocationEditorSheet: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let mode: FoodLocationEditor
    @State private var name = ""
    private let presets = ["冷藏区", "冷冻区", "冰柜", "常温区", "厨房储物柜", "储物间"]
    private var availablePresets: [String] {
        presets.filter { preset in
            !store.foodLocations.contains { $0.caseInsensitiveCompare(preset) == .orderedSame }
        }
    }

    private var title: String {
        switch mode {
        case .add: "新增位置"
        case .rename: "重命名位置"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if case .add = mode, !availablePresets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("常用位置").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                        HomeTagFlowLayout(spacing: 8) {
                            ForEach(availablePresets, id: \.self) { preset in
                                Button {
                                    name = preset
                                    NativeHaptics.selection()
                                } label: {
                                    Text(preset)
                                        .font(HomeTypography.supporting.weight(.medium))
                                        .foregroundStyle(name == preset ? HomeTheme.blue : HomeTheme.ink)
                                        .padding(.horizontal, 14)
                                        .frame(height: 34)
                                        .background(name == preset ? HomeTheme.blue.opacity(0.10) : HomeTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                HomeCard {
                    HStack {
                        Text("位置名称").font(HomeTypography.body)
                        Spacer()
                        TextField("例如冰箱、冰柜", text: $name)
                            .font(HomeTypography.body)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(minHeight: HomeMetrics.controlHeight)
                }
                Button("保存") {
                    let success: Bool
                    switch mode {
                    case .add: success = store.addFoodLocation(name)
                    case .rename(let oldName): success = store.renameFoodLocation(oldName, to: name)
                    }
                    if success { dismiss() }
                }
                .buttonStyle(HomePrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            .padding(HomeMetrics.pageInset)
            .background(HomeTheme.background)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onAppear {
                if case .rename(let oldName) = mode { name = oldName }
            }
        }
        .presentationDetents([.height(410)])
        .presentationDragIndicator(.visible)
    }
}
