import SwiftUI
import PhotosUI
import UIKit

struct PetEventEditorView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String?

    @State private var name = ""
    @State private var categoryID = ""
    @State private var occurrenceDate = Date()
    @State private var note = ""
    @State private var imageReferences: [String] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var originalFingerprint = ""
    @State private var loaded = false
    @State private var showDiscardDialog = false

    init(eventID: String? = nil) {
        self.eventID = eventID
    }

    var body: some View {
        Form {
            Section("事项") {
                if store.activePetEventCategories.isEmpty {
                    NavigationLink {
                        PetEventCategorySettingsView()
                    } label: {
                        Label("请先创建事项类型", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(HomeTheme.orange)
                    }
                } else {
                    Picker("事项类型", selection: $categoryID) {
                        Text("请选择").tag("")
                        ForEach(store.activePetEventCategories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                }

                HomeFieldLabel(title: "具体事项（选填）")
                TextField("例如：清洁饮水机；不填则显示事项类型", text: $name)
                    .font(HomeTypography.body)

                DatePicker("发生日期", selection: $occurrenceDate, displayedComponents: .date)
            }

            Section("备注") {
                TextEditor(text: $note)
                    .font(HomeTypography.body)
                    .frame(minHeight: 92)
            }

            Section("图片") {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                    Label("选择图片", systemImage: "photo.on.rectangle.angled")
                }
                if !imageReferences.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(imageReferences.enumerated()), id: \.offset) { index, reference in
                                ZStack(alignment: .topTrailing) {
                                    PetStoredImage(reference: reference)
                                        .frame(width: 92, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Button {
                                        imageReferences.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.black.opacity(0.55))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 5, y: -5)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(eventID == nil ? "新增事项" : "编辑事项")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    if hasUnsavedChanges { showDiscardDialog = true } else { dismiss() }
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(categoryID.isEmpty)
            }
        }
        .task { loadExistingIfNeeded() }
        .onChange(of: selectedPhotos) { _, items in
            Task { await loadPhotos(items) }
        }
        .confirmationDialog("有尚未保存的修改", isPresented: $showDiscardDialog, titleVisibility: .visible) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃修改", role: .destructive) { dismiss() }
        }
    }

    private var hasUnsavedChanges: Bool {
        loaded && fingerprint != originalFingerprint
    }

    private var fingerprint: String {
        [name, categoryID, LitterPredictionService.format(occurrenceDate), note, imageReferences.joined(separator: "|")].joined(separator: "¦")
    }

    private func loadExistingIfNeeded() {
        guard !loaded else { return }
        if let eventID, let event = store.data.petEvents.first(where: { $0.id == eventID }) {
            name = event.name.caseInsensitiveCompare(event.categoryNameSnapshot) == .orderedSame ? "" : event.name
            categoryID = event.categoryID
            occurrenceDate = LitterPredictionService.parse(event.occurrenceDate) ?? Date()
            note = event.note ?? ""
            imageReferences = event.imageReferences
        } else if categoryID.isEmpty {
            categoryID = store.activePetEventCategories.first?.id ?? ""
        }
        loaded = true
        originalFingerprint = fingerprint
    }

    private func save() {
        if store.saveManualPetEvent(
            id: eventID,
            name: name,
            categoryID: categoryID,
            petIDs: [],
            occurrenceDate: LitterPredictionService.format(occurrenceDate),
            note: note,
            imageReferences: imageReferences
        ) {
            originalFingerprint = fingerprint
            dismiss()
        }
    }

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var newReferences: [String] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                newReferences.append("data:image/jpeg;base64," + data.base64EncodedString())
            }
        }
        imageReferences.append(contentsOf: newReferences)
        selectedPhotos = []
    }
}

struct PetEventDetailView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let eventID: String
    @State private var showDelete = false

    private var event: PetEvent? {
        store.data.petEvents.first { $0.id == eventID }
    }

    var body: some View {
        ScrollView {
            if let event {
                LazyVStack(alignment: .leading, spacing: 16) {
                    PageTitle(title: event.name, subtitle: HomeDateText.display(event.occurrenceDate))
                    HomeCard {
                        VStack(alignment: .leading, spacing: 10) {
                            if event.name.caseInsensitiveCompare(event.categoryNameSnapshot) != .orderedSame {
                                detailRow("事项类型", event.categoryNameSnapshot)
                            }
                            detailRow("来源", sourceTitle(event.source))
                        }
                    }
                    if let note = event.note, !note.isEmpty {
                        HomeCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HomeSectionHeader(title: "备注")
                                Text(note).font(HomeTypography.body)
                            }
                        }
                    }
                    if !event.imageReferences.isEmpty {
                        HomeCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HomeSectionHeader(title: "图片")
                                ForEach(Array(event.imageReferences.enumerated()), id: \.offset) { _, reference in
                                    PetStoredImage(reference: reference)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                    }
                    if event.litterOperationID != nil {
                        Text("该事项由猫砂库存操作自动生成，不能单独删除。")
                            .font(HomeTypography.supporting)
                            .foregroundStyle(HomeTheme.orange)
                    }
                }
                .padding(HomeMetrics.pageInset)
            } else {
                EmptyState(icon: "exclamationmark.triangle.fill", title: "事项不存在", message: "该事项可能已被删除。")
                    .padding(HomeMetrics.pageInset)
            }
        }
        .background(HomeTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let event {
                ToolbarItemGroup(placement: .primaryAction) {
                    if event.litterOperationID == nil {
                        NavigationLink("编辑") { PetEventEditorView(eventID: event.id) }
                        Button(role: .destructive) { showDelete = true } label: { Image(systemName: "trash") }
                    }
                }
            }
        }
        .alert("删除这条事项？", isPresented: $showDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if store.deletePetEvent(id: eventID) { dismiss() }
            }
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
            Spacer()
            Text(value).font(HomeTypography.body.weight(.medium)).multilineTextAlignment(.trailing)
        }
    }

    private func sourceTitle(_ source: PetEventSource) -> String {
        switch source {
        case .manual: "手动新增"
        case .litterRefill: "补猫砂自动生成"
        case .litterReplace: "换猫砂自动生成"
        }
    }

}

struct PetStoredImage: View {
    let reference: String

    var body: some View {
        if let image = decodedImage {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                HomeTheme.background
                Image(systemName: "photo").foregroundStyle(HomeTheme.muted)
            }
        }
    }

    private var decodedImage: UIImage? {
        guard let comma = reference.firstIndex(of: ","),
              let data = Data(base64Encoded: String(reference[reference.index(after: comma)...])) else { return nil }
        return UIImage(data: data)
    }
}
