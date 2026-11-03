import Foundation
import SwiftData

/// 資料位置：
///   Application Support/BillionairePlanner/Planner.store     ← v1（v2 永不寫入）
///   Application Support/BillionairePlanner/PlannerV2.store   ← v2
///   Application Support/BillionairePlanner/Backups/…         ← 遷移前備份（不自動刪除）
enum StoreLocation {
    static var directory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "BillionairePlanner", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var v1Store: URL { directory.appending(path: "Planner.store") }
    static var v2Store: URL { directory.appending(path: "PlannerV2.store") }
    static var backups: URL { directory.appending(path: "Backups", directoryHint: .isDirectory) }

    /// SQLite store 的整組檔案
    static func family(of store: URL) -> [URL] {
        ["", "-wal", "-shm"].map { URL(fileURLWithPath: store.path + $0) }
    }
}

enum PlannerContainer {
    static var schema: Schema { Schema(versionedSchema: PlannerSchemaV2.self) }

    static func make(url: URL = StoreLocation.v2Store) throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, migrationPlan: PlannerMigrationPlan.self, configurations: config)
    }

    static func inMemory() throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: PlannerMigrationPlan.self, configurations: config)
    }
}

extension ModelContext {
    func all<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? fetch(FetchDescriptor<T>())) ?? []
    }
}
