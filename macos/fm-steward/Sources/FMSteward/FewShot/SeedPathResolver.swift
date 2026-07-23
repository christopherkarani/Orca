import Foundation

/// Resolve the residual few-shot seed JSON path for product / host attach.
///
/// # Resolution contract (Host attach / README)
///
/// Seed path selection is **existence-checked** and ordered:
///
/// 1. **Explicit** seed URL (CLI / host override) — if the file exists
/// 2. **App Support copy** — product seed under Application Support
///    (`Orca/fm-steward/seed.json`) when present (operator-installed or
///    mirrored copy; does not require the package tree)
/// 3. **Package fixture** — checked-in `Fixtures/ambig-fewshot/seed.json`
///    when the package root is available (dev / CLI adjacent layout)
/// 4. **`nil`** — no seed found; Runtime `.auto` fail-open → pure residual FM
///
/// This type is a pure path helper: it does **not** load seed JSON, reseed Wax,
/// or talk to `FewShotRuntime`. Callers pass concrete layer URLs (or use
/// `productAppSupportSeedURL()` for the App Support default).
///
/// Existence means a **regular file** (directories do not win).
public enum SeedPathResolver: Sendable {
    /// On-disk file name for the residual seed JSON (App Support copy).
    public static let seedFileName = "seed.json"

    /// Product App Support seed copy URL (same directory as `ambig.wax`).
    ///
    /// Path: Application Support / `Orca/fm-steward` / `seed.json`.
    /// Built from `FewShotStorePaths.productRelativeDirectory`.
    public static func productAppSupportSeedURL(fileManager: FileManager = .default) -> URL {
        FewShotStorePaths.productStoreURL(fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent(seedFileName, isDirectory: false)
    }

    /// Resolve seed path: explicit → App Support copy → package fixture → nil.
    ///
    /// - Parameters:
    ///   - explicit: Host/CLI override (e.g. `--seed`); skipped when nil or missing.
    ///   - appSupportSeed: Product App Support seed copy URL; skipped when nil/missing.
    ///   - packageSeed: Package `Fixtures/ambig-fewshot/seed.json`; skipped when nil/missing.
    ///   - fileManager: Inject for tests; defaults to `.default`.
    /// - Returns: First existing **file** URL in order, or `nil` if none exist.
    public static func resolve(
        explicit: URL?,
        appSupportSeed: URL?,
        packageSeed: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        if let explicit, isExistingFile(explicit, fileManager: fileManager) {
            return explicit
        }
        if let appSupportSeed, isExistingFile(appSupportSeed, fileManager: fileManager) {
            return appSupportSeed
        }
        if let packageSeed, isExistingFile(packageSeed, fileManager: fileManager) {
            return packageSeed
        }
        return nil
    }

    /// True when `url` exists on disk and is not a directory.
    private static func isExistingFile(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return false
        }
        return !isDir.boolValue
    }
}
