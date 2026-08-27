import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                Section("数据概览") {
                    LabeledContent("食品", value: "\(store.data.foods.count)")
                    LabeledContent("菜谱", value: "\(store.data.recipes.count)")
                    LabeledContent("宠物用品", value: "\(store.data.petItems.count)")
                }
                Section("数据管理") {
                    Button("导出 JSON 备份") { exporting = true; NativeHaptics.tap() }
                    Button("导入 Web / 原生备份") { importing = true; NativeHaptics.tap() }
                    Button("清空应用数据", role: .destructive) { confirmClear = true; NativeHaptics.warning() }
                }
                Section("版本") {
                    LabeledContent("原生版本", value: "0.1.3 (4)")
                    LabeledContent("Web 功能基线", value: "v8.25.1")
                    Text("当前为原生重写第一阶段，不包含 WebView。")
                        .font(.footnote).foregroundStyle(HomeTheme.muted)
                }
            }
            .scrollContentBackground(.hidden).background(HomeTheme.background)
            .navigationTitle("设置")
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
            .alert("提示", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
                Button("知道了") { store.lastError = nil }
            } message: { Text(store.lastError ?? "") }
        }
    }
}
