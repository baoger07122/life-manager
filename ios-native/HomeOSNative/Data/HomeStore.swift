import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class HomeStore: ObservableObject {
    @Published private(set) var data: HomeBackup = .empty
    @Published var lastError: String?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomeOSNative", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("home-os-v1.json")
        load()
    }

    func load() {
        guard let stored = try? Data(contentsOf: fileURL) else {
            data = .empty
            return
        }
        do {
            data = try decoder.decode(HomeBackup.self, from: stored)
        } catch {
            lastError = "本机数据读取失败：\(error.localizedDescription)"
            data = .empty
        }
    }

    func replace(with backup: HomeBackup) {
        data = backup
        save()
    }

    func clearAll() {
        data = .empty
        save()
        NativeHaptics.success()
    }

    func importBackup(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let imported = try decoder.decode(HomeBackup.self, from: Data(contentsOf: url))
            replace(with: imported)
            NativeHaptics.success()
        } catch {
            lastError = "备份导入失败：\(error.localizedDescription)"
            NativeHaptics.error()
        }
    }

    func encodedBackup() -> Data {
        (try? encoder.encode(data)) ?? Data("{}".utf8)
    }

    var dueFoods: [FoodItem] {
        guard data.settings.expiryReminderEnabled != false else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return data.foods.filter { item in
            guard let date = formatter.date(from: item.expiry),
                  let days = calendar.dateComponents([.day], from: start, to: date).day else { return false }
            return days <= data.settings.threshold
        }.sorted { $0.expiry < $1.expiry }
    }

    private func save() {
        do {
            try encoder.encode(data).write(to: fileURL, options: .atomic)
        } catch {
            lastError = "本机数据保存失败：\(error.localizedDescription)"
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
