import SwiftUI

struct BrandManagementView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var query = ""
    @State private var sheet: BrandManagementSheet?
    @State private var pendingArchive: ManagedBrand?

    private var brands: [ManagedBrand] {
        let values = store.brands(for: .pet) + store.brands(for: .food)
        let unique = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        return unique
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            if brands.isEmpty {
                EmptyState(icon: "tag.fill", title: "暂无品牌", message: "点击右上角添加品牌。")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(brands) { brand in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(brand.name).font(HomeTypography.body.weight(.medium))
                            Text(scopeText(brand.modules) + " · 关联 \(usageCount(brand)) 件")
                                .font(HomeTypography.supporting)
                                .foregroundStyle(HomeTheme.muted)
                        }
                        Spacer()
                        Menu {
                            Button("编辑", systemImage: "pencil") { sheet = .edit(brand) }
                            Button("合并到其他品牌", systemImage: "arrow.triangle.merge") { sheet = .merge(brand) }
                            Button("停用", systemImage: "archivebox", role: .destructive) { pendingArchive = brand }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(HomeTheme.blue)
                                .frame(width: 44, height: 44)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索品牌")
        .navigationTitle("品牌管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = .add } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加品牌")
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .add:
                BrandEditorSheet(brand: nil)
            case .edit(let brand):
                BrandEditorSheet(brand: brand)
            case .merge(let brand):
                BrandMergeSheet(source: brand)
            }
        }
        .confirmationDialog("停用“\(pendingArchive?.name ?? "")”？", isPresented: Binding(
            get: { pendingArchive != nil },
            set: { if !$0 { pendingArchive = nil } }
        ), titleVisibility: .visible) {
            Button("停用品牌", role: .destructive) {
                if let pendingArchive { _ = store.archiveManagedBrand(id: pendingArchive.id) }
                pendingArchive = nil
            }
            Button("取消", role: .cancel) { pendingArchive = nil }
        } message: {
            Text("历史物品保留品牌名称，新建物品不再显示该品牌。")
        }
    }

    private func usageCount(_ brand: ManagedBrand) -> Int {
        Set(brand.modules).reduce(0) { $0 + store.brandUsageCount(named: brand.name, module: $1) }
    }

    private func scopeText(_ modules: [ManagedCategoryModule]) -> String {
        modules.map(brandModuleTitle).joined(separator: "、")
    }
}

private enum BrandManagementSheet: Identifiable {
    case add
    case edit(ManagedBrand)
    case merge(ManagedBrand)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let brand): "edit-\(brand.id)"
        case .merge(let brand): "merge-\(brand.id)"
        }
    }
}

private struct BrandEditorSheet: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let brand: ManagedBrand?
    @State private var name = ""
    @State private var modules: Set<ManagedCategoryModule> = [.pet]

    var body: some View {
        NavigationStack {
            Form {
                Section("品牌信息") {
                    TextField("品牌名称", text: $name).font(HomeTypography.body)
                }
                Section("适用范围") {
                    moduleToggle(.pet)
                    moduleToggle(.food)
                }
            }
            .navigationTitle(brand == nil ? "新增品牌" : "编辑品牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let values = Array(modules)
                        let success: Bool
                        if let brand {
                            success = store.renameManagedBrand(id: brand.id, name: name)
                                && store.setManagedBrandModules(id: brand.id, modules: values)
                        } else {
                            success = store.addManagedBrand(name: name, modules: values)
                        }
                        if success { dismiss() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || modules.isEmpty)
                }
            }
            .task {
                name = brand?.name ?? ""
                modules = Set(brand?.modules ?? [.pet])
            }
        }
        .presentationDetents([.medium])
    }

    private func moduleToggle(_ module: ManagedCategoryModule) -> some View {
        Toggle(brandModuleTitle(module), isOn: Binding(
            get: { modules.contains(module) },
            set: { enabled in
                if enabled { modules.insert(module) } else { modules.remove(module) }
            }
        ))
    }
}

private struct BrandMergeSheet: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let source: ManagedBrand
    @State private var destinationID = ""

    private var destinations: [ManagedBrand] {
        let values = store.brands(for: .pet) + store.brands(for: .food)
        return Array(Dictionary(values.filter { $0.id != source.id }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("待合并品牌", value: source.name)
                    Picker("目标品牌", selection: $destinationID) {
                        ForEach(destinations) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    Text("关联物品会改用目标品牌，原品牌随后停用。")
                }
            }
            .navigationTitle("合并品牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("合并") {
                        if store.mergeManagedBrand(sourceID: source.id, destinationID: destinationID) { dismiss() }
                    }
                    .disabled(destinationID.isEmpty)
                }
            }
            .task { destinationID = destinations.first?.id ?? "" }
        }
        .presentationDetents([.medium])
    }
}

private func brandModuleTitle(_ module: ManagedCategoryModule) -> String {
    switch module {
    case .pet: "宠物"
    case .food: "食品"
    case .recipe: "菜谱"
    }
}
