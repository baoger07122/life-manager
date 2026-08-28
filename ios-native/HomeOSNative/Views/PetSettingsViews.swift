import SwiftUI
import PhotosUI

struct PetManagementView: View {
    @EnvironmentObject private var store: HomeStore

    var body: some View {
        List {
            if store.activePets.isEmpty {
                EmptyState(icon: "cat.fill", title: "还没有宠物档案", message: "创建宠物后，可在事项和适口性记录中关联。")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(store.activePets) { pet in
                    NavigationLink {
                        PetProfileEditorView(petID: pet.id)
                    } label: {
                        HStack(spacing: 12) {
                            petAvatar(pet)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pet.name).font(HomeTypography.cardTitle)
                                Text([pet.breed, pet.birthDate].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HomeTheme.background)
        .navigationTitle("宠物管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink { PetProfileEditorView() } label: { Image(systemName: "plus") }
        }
    }

    @ViewBuilder
    private func petAvatar(_ pet: PetProfile) -> some View {
        if let image = pet.image, !image.isEmpty {
            PetStoredImage(reference: image).frame(width: 44, height: 44).clipShape(Circle())
        } else {
            Image(systemName: "cat.fill")
                .foregroundStyle(HomeTheme.blue)
                .frame(width: 44, height: 44)
                .background(HomeTheme.blue.opacity(0.10), in: Circle())
        }
    }
}

struct PetProfileEditorView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let petID: String?
    @State private var name = ""
    @State private var breed = ""
    @State private var birthDate = Date()
    @State private var imageReference: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loaded = false
    @State private var showDelete = false

    init(petID: String? = nil) { self.petID = petID }

    var body: some View {
        Form {
            Section("宠物档案") {
                TextField("名称", text: $name).font(HomeTypography.body)
                TextField("品种", text: $breed).font(HomeTypography.body)
                DatePicker("出生日期", selection: $birthDate, in: ...Date(), displayedComponents: .date)
            }
            Section("图片") {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(imageReference == nil ? "选择图片" : "更换图片", systemImage: "photo")
                }
                if let imageReference {
                    PetStoredImage(reference: imageReference)
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button("删除图片", role: .destructive) { self.imageReference = nil }
                }
            }
            if petID != nil {
                Section {
                    Button("删除宠物档案", role: .destructive) { showDelete = true }
                } footer: {
                    Text("历史事项保留名称快照并标记为已删除宠物；宠物用品不会被删除。")
                }
            }
        }
        .navigationTitle(petID == nil ? "新增宠物" : "编辑宠物")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task { loadExisting() }
        .onChange(of: selectedPhoto) { _, photo in
            Task {
                if let data = try? await photo?.loadTransferable(type: Data.self) {
                    imageReference = "data:image/jpeg;base64," + data.base64EncodedString()
                }
            }
        }
        .alert("删除这个宠物档案？", isPresented: $showDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let petID { store.deletePet(id: petID) }
                dismiss()
            }
        }
    }

    private func loadExisting() {
        guard !loaded else { return }
        defer { loaded = true }
        guard let petID, let pet = store.data.pets.first(where: { $0.id == petID }) else { return }
        name = pet.name
        breed = pet.breed
        birthDate = LitterPredictionService.parse(pet.birthDate) ?? Date()
        imageReference = pet.image
    }

    private func save() {
        let existing = petID.flatMap { id in store.data.pets.first { $0.id == id } }
        let now = Date().timeIntervalSince1970
        let pet = PetProfile(
            id: existing?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            image: imageReference,
            breed: breed.trimmingCharacters(in: .whitespacesAndNewlines),
            birthDate: LitterPredictionService.format(birthDate),
            isDeleted: false,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        store.upsertPet(pet)
        NativeHaptics.success()
        dismiss()
    }
}

struct PetEventCategorySettingsView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var draftName = ""
    @State private var editingID: String?
    @State private var showEditor = false
    @State private var deleteID: String?

    var body: some View {
        List {
            if store.activePetEventCategories.isEmpty {
                EmptyState(icon: "tag.fill", title: "还没有事项分类", message: "新增事项必须选择分类，请先创建分类。")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(store.activePetEventCategories) { category in
                    HStack {
                        Text(category.name).font(HomeTypography.body)
                        Spacer()
                        Text("\(eventCount(category.id)) 项").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) { deleteID = category.id }
                        Button("改名") {
                            editingID = category.id
                            draftName = category.name
                            showEditor = true
                        }
                        .tint(HomeTheme.blue)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HomeTheme.background)
        .navigationTitle("宠物事项设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                editingID = nil
                draftName = ""
                showEditor = true
            } label: { Image(systemName: "plus") }
        }
        .alert(editingID == nil ? "新增事项分类" : "修改分类名称", isPresented: $showEditor) {
            TextField("分类名称", text: $draftName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let editingID {
                    _ = store.renamePetEventCategory(id: editingID, name: draftName)
                } else {
                    _ = store.addPetEventCategory(name: draftName)
                }
            }
        }
        .alert("删除这个分类？", isPresented: Binding(
            get: { deleteID != nil },
            set: { if !$0 { deleteID = nil } }
        )) {
            Button("取消", role: .cancel) { deleteID = nil }
            Button("删除", role: .destructive) {
                if let deleteID { store.deletePetEventCategory(id: deleteID) }
                self.deleteID = nil
            }
        } message: {
            Text("历史事项仍保留当前分类名称，新事项不再显示此分类。")
        }
    }

    private func eventCount(_ categoryID: String) -> Int {
        store.data.petEvents.filter { $0.categoryID == categoryID }.count
    }
}
