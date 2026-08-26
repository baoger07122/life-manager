import SwiftUI

struct PetView: View {
    @EnvironmentObject private var store: HomeStore

    var body: some View {
        NavigationStack {
            List {
                if store.data.petItems.isEmpty {
                    EmptyState(icon: "pawprint.fill", title: "还没有宠物用品", message: "猫砂、饮食补给和猫咪偏好将在宠物模块阶段完整实现。")
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    ForEach(store.data.petItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.body.weight(.semibold))
                                Text("\(item.type) · \(item.brand)").font(.caption).foregroundStyle(HomeTheme.muted)
                            }
                            Spacer()
                            Text("\(item.quantity.formatted())\(item.unit)").font(.subheadline.weight(.semibold))
                        }.padding(.vertical, 5)
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden).background(HomeTheme.background)
            .navigationTitle("宠物")
            .toolbar { Button(action: NativeHaptics.tap) { Image(systemName: "plus") } }
        }
    }
}
