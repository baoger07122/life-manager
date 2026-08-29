import SwiftUI

struct CategoryManagementView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var module: ManagedCategoryModule
    @State private var expanded = Set<String>()
    @State private var editor: CategoryEditorTarget?

    init(initialModule: ManagedCategoryModule = .pet) {
        _module = State(initialValue: initialModule)
    }

    private var roots: [ManagedCategory] { store.categories(for: module) }

    var body: some View {
        List {
            Section {
                Picker("模块", selection: $module) {
                    ForEach(ManagedCategoryModule.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if roots.isEmpty {
                    EmptyState(icon: "folder.fill", title: "暂无分类", message: "点击右上角添加一级分类。")
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(roots.enumerated()), id: \.element.id) { index, root in
                        categoryGroup(root, index: index)
                    }
                }
            } footer: {
                Text("分类管理入口全局统一，但宠物、食品和菜谱的数据彼此独立。系统一级分类可改名和排序，不能删除。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(HomeTheme.background)
        .navigationTitle("分类管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editor = CategoryEditorTarget(module: module, parentID: nil, category: nil)
                    NativeHaptics.tap()
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("添加一级分类")
            }
        }
        .sheet(item: $editor) { target in
            CategoryEditorSheet(target: target)
        }
        .onChange(of: module) { _, _ in expanded.removeAll() }
        .alert("提示", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("知道了") { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
    }

    private func categoryGroup(_ root: ManagedCategory, index: Int) -> some View {
        let children = store.categories(for: module, parentID: root.id)
        return DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(root.id) },
            set: { value in
                if value { expanded.insert(root.id) } else { expanded.remove(root.id) }
                NativeHaptics.selection()
            }
        )) {
            if children.isEmpty {
                Text("暂无二级分类")
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
            }
            ForEach(Array(children.enumerated()), id: \.element.id) { childIndex, child in
                categoryRow(child, siblings: children, index: childIndex, indented: true)
            }
            Button {
                editor = CategoryEditorTarget(module: module, parentID: root.id, category: nil)
            } label: {
                Label("添加二级分类", systemImage: "plus.circle")
                    .font(HomeTypography.body)
                    .foregroundStyle(HomeTheme.blue)
            }
        } label: {
            categoryRow(root, siblings: roots, index: index, indented: false)
        }
        .tint(HomeTheme.muted)
    }

    private func categoryRow(_ category: ManagedCategory, siblings: [ManagedCategory], index: Int, indented: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.system(size: indented ? 15 : 18, weight: .medium))
                .foregroundStyle(indented ? HomeTheme.muted : HomeTheme.blue)
                .frame(width: 32, height: 32)
                .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(indented ? HomeTypography.body : HomeTypography.cardTitle)
                if category.isSystem {
                    Text("系统能力分类").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                }
            }
            Spacer()
            Menu {
                Button("编辑名称与图标", systemImage: "pencil") {
                    editor = CategoryEditorTarget(module: module, parentID: category.parentID, category: category)
                }
                Button("上移", systemImage: "arrow.up", action: { move(category, in: siblings, from: index, delta: -1) })
                    .disabled(index == 0)
                Button("下移", systemImage: "arrow.down", action: { move(category, in: siblings, from: index, delta: 1) })
                    .disabled(index == siblings.count - 1)
                Button("删除", systemImage: "trash", role: .destructive) {
                    _ = store.deleteManagedCategory(id: category.id)
                }
                .disabled(category.isSystem)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(HomeTheme.blue)
                    .frame(width: 44, height: 44)
            }
        }
        .contentShape(Rectangle())
    }

    private func move(_ category: ManagedCategory, in siblings: [ManagedCategory], from index: Int, delta: Int) {
        let destination = index + delta
        guard siblings.indices.contains(destination) else { return }
        var ids = siblings.map(\.id)
        ids.swapAt(index, destination)
        store.reorderManagedCategories(module: category.module, parentID: category.parentID, orderedIDs: ids)
    }
}

private struct CategoryEditorTarget: Identifiable {
    let id = UUID()
    let module: ManagedCategoryModule
    let parentID: String?
    let category: ManagedCategory?
}

private struct CategoryEditorSheet: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let target: CategoryEditorTarget
    @State private var name = ""
    @State private var icon = "tag.fill"

    private let icons = ["tag.fill", "takeoutbag.and.cup.and.straw.fill", "shippingbox.fill", "refrigerator.fill", "fork.knife", "leaf.fill", "heart.fill", "pawprint.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("分类信息") {
                    TextField("分类名称", text: $name).font(HomeTypography.body)
                    Picker("图标", selection: $icon) {
                        ForEach(icons, id: \.self) { value in
                            Label(value, systemImage: value).tag(value)
                        }
                    }
                }
                Section {
                    HStack {
                        Spacer()
                        Image(systemName: icon).font(.system(size: 28)).foregroundStyle(HomeTheme.blue)
                        Text(name.isEmpty ? "分类预览" : name).font(HomeTypography.sectionTitle)
                        Spacer()
                    }
                }
            }
            .navigationTitle(target.category == nil ? "新增分类" : "编辑分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let success: Bool
                        if let category = target.category {
                            success = store.renameManagedCategory(id: category.id, name: name)
                                && store.setManagedCategoryIcon(id: category.id, icon: icon)
                        } else {
                            success = store.addManagedCategory(module: target.module, parentID: target.parentID, name: name, icon: icon)
                        }
                        if success { dismiss() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                name = target.category?.name ?? ""
                icon = target.category?.icon ?? defaultIcon
            }
        }
        .presentationDetents([.medium])
    }

    private var defaultIcon: String {
        switch target.module {
        case .pet: "tag.fill"
        case .food: "refrigerator.fill"
        case .recipe: "list.bullet.clipboard.fill"
        }
    }
}
