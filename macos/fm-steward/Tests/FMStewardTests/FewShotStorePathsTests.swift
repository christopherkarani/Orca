import Foundation
import Testing
@testable import FMSteward

@Suite("FewShotStorePaths")
struct FewShotStorePathsTests {
    @Test("product default store URL is under Application Support/Orca/fm-steward/ambig.wax")
    func productDefaultPath() {
        let url = FewShotStorePaths.productStoreURL()
        let path = url.path
        #expect(path.contains("Application Support"))
        #expect(path.contains("Orca/fm-steward"))
        #expect(path.hasSuffix("ambig.wax"))
        #expect(url.lastPathComponent == "ambig.wax")
    }

    @Test("explicit override URL wins over product default")
    func overrideWins() {
        let override = URL(fileURLWithPath: "/tmp/custom-test-store/ambig.wax")
        let resolved = FewShotStorePaths.storeURL(override: override)
        #expect(resolved == override)
        #expect(resolved.path == override.path)
        #expect(resolved != FewShotStorePaths.productStoreURL())
    }

    @Test("nil override falls back to product default")
    func nilOverrideUsesProductDefault() {
        let resolved = FewShotStorePaths.storeURL(override: nil)
        #expect(resolved == FewShotStorePaths.productStoreURL())
    }

    @Test("ensureParentDirectory creates missing parents")
    func ensureParentCreatesDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fm-steward-store-paths-\(UUID().uuidString)", isDirectory: true)
        let storeURL = root
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("ambig.wax")
        defer { try? FileManager.default.removeItem(at: root) }

        let parent = storeURL.deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: parent.path))

        try FewShotStorePaths.ensureParentDirectory(for: storeURL)

        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
        // Store file itself is not created — only the parent directory.
        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
    }
}
