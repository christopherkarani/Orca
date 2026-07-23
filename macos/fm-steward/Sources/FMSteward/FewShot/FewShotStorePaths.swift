import Foundation

/// Product and override paths for the residual Wax few-shot store.
///
/// Default product location: Application Support / Orca / fm-steward / ambig.wax.
/// Sidecar reseed key lives at `ambig.wax.seedsha`
/// (`v{N}:<seed-sha256>:<store-sha256>`; see `FewShotSeedBootstrap`);
/// reseed lock at `ambig.wax.reseed.lock`.
/// This type only resolves store URLs and parent directories.
public enum FewShotStorePaths: Sendable {
    /// On-disk file name for the residual Wax store.
    public static let storeFileName = "ambig.wax"

    /// Relative directory under Application Support for product data.
    public static let productRelativeDirectory = "Orca/fm-steward"

    /// Product default store URL under Application Support.
    ///
    /// - Parameter fileManager: Inject for tests; defaults to `.default`.
    public static func productStoreURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent(productRelativeDirectory, isDirectory: true)
            .appendingPathComponent(storeFileName, isDirectory: false)
    }

    /// Resolve store URL: explicit override wins; otherwise product default.
    ///
    /// Intended for CLI `--wax-store` and test temp paths.
    public static func storeURL(override: URL?, fileManager: FileManager = .default) -> URL {
        if let override {
            return override
        }
        return productStoreURL(fileManager: fileManager)
    }

    /// Create parent directory of `storeURL` if missing (intermediate dirs ok).
    ///
    /// Does not create the store file itself. Throws on FileManager failures
    /// (callers that need fail-open should catch).
    public static func ensureParentDirectory(
        for storeURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let parent = storeURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    }
}
