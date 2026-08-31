import SwiftUI

struct FoodItemThumbnail: View {
    let item: FoodItem
    var size: CGFloat = 48

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(HomeTheme.background)
            .frame(width: size, height: size)
            .overlay {
                if let reference = item.thumb, !reference.isEmpty {
                    PetStoredImage(reference: reference)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
                } else {
                    Text(item.icon).font(.system(size: size * 0.52))
                }
            }
    }
}

struct FoodInventoryRows: View {
    @EnvironmentObject private var store: HomeStore
    let items: [FoodItem]
    @State private var expandedID: String?
    @State private var inbound = false
    @State private var quantity = 1.0
    @State private var totalPriceText = ""

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < items.count - 1 { Divider() }
            }
        }
    }

    private func row(_ item: FoodItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                NavigationLink { FoodDetailView(itemID: item.id) } label: {
                    HStack(spacing: 11) {
                        FoodItemThumbnail(item: item)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(productTitle(item))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(HomeTheme.ink)
                                .lineLimit(1)
                            Text("保质期 \(HomeDateText.display(item.expiry))")
                                .font(.system(size: 12))
                                .foregroundStyle(HomeTheme.muted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomePressButtonStyle())

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedID = expandedID == item.id ? nil : item.id
                        inbound = false
                        quantity = 1
                        totalPriceText = ""
                    }
                    NativeHaptics.selection()
                } label: {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(stockText(item))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HomeTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(item.location)
                            .font(.system(size: 12))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(1)
                    }
                    .frame(width: 124, alignment: .trailing)
                    .frame(minHeight: 48, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if expandedID == item.id {
                quickManager(item)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func productTitle(_ item: FoodItem) -> String {
        let brand = item.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return brand.isEmpty ? item.name : "\(brand) \(item.name)"
    }

    private func stockText(_ item: FoodItem) -> String {
        let stock = "\(item.quantity.formatted(.number.precision(.fractionLength(0...2))))\(item.unit)"
        let spec = item.spec.trimmingCharacters(in: .whitespacesAndNewlines)
        return spec.isEmpty ? stock : "\(spec) × \(stock)"
    }

    private func quickManager(_ item: FoodItem) -> some View {
        VStack(spacing: 8) {
            Picker("操作", selection: $inbound) {
                Text("出库").tag(false)
                Text("入库").tag(true)
            }
            .pickerStyle(.segmented)
            HStack(spacing: 7) {
                stepButton("minus") { quantity = max(1, quantity - 1) }
                TextField("数量", value: $quantity, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 58, height: 38)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                stepButton("plus") { quantity += 1 }
                Text(item.unit).font(.system(size: 12)).foregroundStyle(HomeTheme.muted)
                Spacer(minLength: 2)
                Button(inbound ? "确认入库" : "确认出库") {
                    let total = Double(totalPriceText.replacingOccurrences(of: ",", with: "."))
                    if store.adjustFoodInventory(id: item.id, quantityChange: inbound ? quantity : -quantity, totalPrice: total) {
                        expandedID = nil
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(HomeTheme.blue, in: RoundedRectangle(cornerRadius: 11))
            }
            if inbound {
                HStack {
                    Text("购入总价").font(.system(size: 12)).foregroundStyle(HomeTheme.muted)
                    TextField("0.00", text: $totalPriceText).keyboardType(.decimalPad).font(.system(size: 14))
                    Spacer()
                    if let total = Double(totalPriceText.replacingOccurrences(of: ",", with: ".")), quantity > 0 {
                        Text("单价 ¥\((total / quantity).formatted(.number.precision(.fractionLength(2))))")
                            .font(.system(size: 12)).foregroundStyle(HomeTheme.muted)
                    }
                }
                .frame(height: 32)
            }
        }
        .padding(9)
        .background(HomeTheme.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
    }

    private func stepButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            NativeHaptics.selection()
        } label: {
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct FoodExpiryListView: View {
    @EnvironmentObject private var store: HomeStore

    var body: some View {
        List(store.dueFoods) { item in
            NavigationLink { FoodDetailView(itemID: item.id) } label: {
                HStack(spacing: 11) {
                    FoodItemThumbnail(item: item, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(HomeTypography.cardTitle)
                        Text(HomeDateText.display(item.expiry)).font(HomeTypography.supporting).foregroundStyle(HomeTheme.orange)
                    }
                    Spacer()
                    Text(item.location).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                }
            }
        }
        .navigationTitle("临期食品")
        .navigationBarTitleDisplayMode(.inline)
    }
}
