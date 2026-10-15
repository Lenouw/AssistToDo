import XCTest
import SwiftData
@testable import AssistToDoKit

/// Filet de la base : sauvegarde avant mise à jour, mise de côté (jamais d'effacement) si la
/// migration échoue, et ouverture d'une VRAIE base à l'ancien schéma (via MIGRATION_SOURCE).
@MainActor
final class StoreMigrationSafetyTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("migr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private func defaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testSnapshotOncePerBuild() throws {
        let store = dir.appendingPathComponent("default.store")
        try Data("base".utf8).write(to: store)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: store.path + "-wal"))
        let d = defaults()
        let first = StoreBackup.snapshotIfAppUpdated(store: store, defaults: d, build: "1.2.1 (2)")
        XCTAssertNotNil(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first!.appendingPathComponent("default.store").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first!.appendingPathComponent("default.store-wal").path))
        XCTAssertNil(StoreBackup.snapshotIfAppUpdated(store: store, defaults: d, build: "1.2.1 (2)"),
                     "pas de seconde sauvegarde pour la même version")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path), "la base d'origine reste en place")
    }

    func testNoSnapshotOnFirstLaunch() {
        let store = dir.appendingPathComponent("absent.store")
        XCTAssertNil(StoreBackup.snapshotIfAppUpdated(store: store, defaults: defaults(), build: "1"))
    }

    func testQuarantineMovesInsteadOfDeleting() throws {
        let store = dir.appendingPathComponent("default.store")
        try Data("illisible".utf8).write(to: store)
        let q = try XCTUnwrap(StoreBackup.quarantine(store: store))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        XCTAssertEqual(try String(contentsOf: q.appendingPathComponent("default.store"), encoding: .utf8), "illisible")
    }

    /// Une base corrompue ne fait plus perdre les données : elle est mise de côté, l'app redémarre vide.
    func testCorruptStoreIsQuarantinedNotDeleted() throws {
        let store = dir.appendingPathComponent("default.store")
        try Data(repeating: 0x42, count: 4096).write(to: store)
        _ = TaskStore(inMemory: false, url: store)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Sauvegardes").path)
        XCTAssertTrue(backups.contains { $0.hasSuffix("-echec-migration") })
    }

    /// Ouvre une COPIE d'une vraie base à l'ancien schéma (sans projectName) avec le schéma actuel.
    /// Lancement : MIGRATION_SOURCE=/chemin/old.store swift test --filter testOpenOldSchemaStore
    func testOpenOldSchemaStore() throws {
        guard let src = ProcessInfo.processInfo.environment["MIGRATION_SOURCE"] else {
            throw XCTSkip("MIGRATION_SOURCE non fourni")
        }
        let copy = dir.appendingPathComponent("copie.store")
        for suffix in ["", "-shm", "-wal"] where FileManager.default.fileExists(atPath: src + suffix) {
            try FileManager.default.copyItem(atPath: src + suffix, toPath: copy.path + suffix)
        }
        let store = TaskStore(inMemory: false, url: copy)
        let ctx = ModelContext(store.container)
        let tasks = try ctx.fetchCount(FetchDescriptor<TaskEntity>())
        let captures = try ctx.fetchCount(FetchDescriptor<CaptureRecord>())
        let withProject = try ctx.fetchCount(FetchDescriptor<TaskEntity>(predicate: #Predicate { $0.projectName != nil }))
        print("MIGRATION_RESULT tasks=\(tasks) captures=\(captures) withProject=\(withProject)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Sauvegardes").path),
                       "aucune mise en quarantaine : la migration a réussi")
        XCTAssertEqual(tasks, Int(ProcessInfo.processInfo.environment["EXPECT_TASKS"] ?? "") ?? tasks)
        XCTAssertEqual(captures, Int(ProcessInfo.processInfo.environment["EXPECT_CAPTURES"] ?? "") ?? captures)
        XCTAssertEqual(withProject, 0)
    }
}
