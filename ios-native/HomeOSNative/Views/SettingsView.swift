import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmClear = false
    #if PLAYGROUND_PREVIEW
    @State private var confirmPreviewReset = false
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageTitle(title: "设置")
                    .padding(.horizontal, HomeMetrics.pageInset)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                List {
                Section {
                    LabeledContent("食品", value: "\(store.data.foods.count)")
                    LabeledContent("菜谱", value: "\(store.data.recipes.count)")
                    LabeledContent("宠物物品", value: "\(store.activePetItems.count)")
                } header: { settingsSectionTitle("数据概览") }
                Section {
                    Button("导出 JSON 备份") { exporting = true; NativeHaptics.tap() }
                    Button("导入 Web / 原生备份") { importing = true; NativeHaptics.tap() }
                    Button("清空应用数据", role: .destructive) { confirmClear = true; NativeHaptics.warning() }
                } header: { settingsSectionTitle("数据管理") }
                Section {
                    NavigationLink {
                        PetManagementView()
                    } label: {
                        Label("宠物管理", systemImage: "cat.fill")
                    }
                    NavigationLink {
                        PetEventCategorySettingsView()
                    } label: {
                        Label("宠物事项类型", systemImage: "tag.fill")
                    }
                    NavigationLink {
                        PetPreferenceSummaryView()
                    } label: {
                        Label("猫咪偏好", systemImage: "heart.fill")
                    }
                } header: { settingsSectionTitle("宠物设置") }
                Section {
                    NavigationLink {
                        FoodLocationManagementView()
                    } label: {
                        Label("存放位置管理", systemImage: "refrigerator.fill")
                    }
                    NavigationLink {
                        CategoryManagementView()
                    } label: {
                        Label("分类管理", systemImage: "folder.fill")
                    }
                    NavigationLink {
                        BrandManagementView()
                    } label: {
                        Label("品牌管理", systemImage: "tag.fill")
                    }
                } header: { settingsSectionTitle("食品、分类与品牌") }
                Section {
                    NavigationLink {
                        UIComponentLibraryView()
                    } label: {
                        Label("UI 组件库", systemImage: "square.grid.2x2.fill")
                    }
                } header: { settingsSectionTitle("开发与设计") }
                #if PLAYGROUND_PREVIEW
                Section {
                    Button("重新载入测试数据", role: .destructive) { confirmPreviewReset = true }
                } header: { settingsSectionTitle("Playground 预览") }
                #endif
                Section {
                    LabeledContent("原生版本", value: "0.1.22 (24)")
                    LabeledContent("Web 功能基线", value: "v8.25.1")
                    Text("当前为原生重写第一阶段，不包含 WebView。")
                        .font(.footnote).foregroundStyle(HomeTheme.muted)
                } header: { settingsSectionTitle("版本") }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(14)
                .environment(\.defaultMinListRowHeight, 48)
                .tint(HomeTheme.blue)
                .scrollContentBackground(.hidden)
            }
            .background(HomeTheme.background)
            .fileExporter(isPresented: $exporting, document: BackupDocument(data: store.encodedBackup()), contentType: .json, defaultFilename: "home-os-v1-backup") { result in
                if case .failure(let error) = result { store.lastError = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): store.importBackup(from: url)
                case .failure(let error): store.lastError = error.localizedDescription
                }
            }
            .confirmationDialog("确定清空当前原生 App 的全部数据？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空全部数据", role: .destructive) { store.clearAll() }
                Button("取消", role: .cancel) {}
            }
            #if PLAYGROUND_PREVIEW
            .confirmationDialog("重新载入测试数据？", isPresented: $confirmPreviewReset, titleVisibility: .visible) {
                Button("覆盖当前预览数据", role: .destructive) {
                    store.replace(with: PreviewFixtures.homeOS)
                    NativeHaptics.success()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只影响 Playground 预览沙盒，不影响正式 IPA 数据。")
            }
            #endif
            .alert("提示", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
                Button("知道了") { store.lastError = nil }
            } message: { Text(store.lastError ?? "") }
        }
    }

    private func settingsSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(HomeTypography.sectionTitle)
            .foregroundStyle(HomeTheme.ink)
            .textCase(nil)
    }
}
