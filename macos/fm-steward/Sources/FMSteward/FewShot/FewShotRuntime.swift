import Foundation

/// Residual few-shot retrieval mode (rules path never uses this).
///
/// Product default is `.auto` (fail-open to null when seed/store is unavailable).
public enum FewShotMode: String, Sendable, Equatable {
    /// No few-shots (pure residual FM / explicit opt-out).
    case off
    /// Wax when seed available and seed/open succeeds; else Null (product default).
    case auto
    /// Require usable Wax store; missing seed / seed or open failure throws.
    case wax
}

/// Library factory for residual few-shot retrievers.
///
/// Product law:
/// - `.off` → `NullFewShotRetriever`
/// - `.auto` → fail-open to Null on missing seed, load throw, open/seed failure, or Wax unlinked
/// - `.wax` → throws on missing seed / load / open failure / Wax unlinked
/// - Default search mode is **text** (CI-safe; no embedder required)
///
/// Reseed when store is missing **or** seed content hash ≠ sidecar (`*.wax.seedsha`).
/// Callers supply resolved `seedURL` / `storeURL` (CLI/resolver owns path discovery).
public enum FewShotRuntime: Sendable {
    /// Product default search mode for residual few-shot (text-only, deterministic CI).
    public static let defaultSearchMode: WaxSearchMode = .text

    /// Errors for strict (`.wax`) factory failures. `.auto` never surfaces these — it returns Null.
    public enum Error: Swift.Error, CustomStringConvertible, Equatable {
        case waxNotLinked
        case seedNotFound(URL)
        case seedFailed(String)

        public var description: String {
            switch self {
            case .waxNotLinked:
                return "Wax not linked in this build"
            case .seedNotFound(let url):
                return "seed JSON not found at \(url.path)"
            case .seedFailed(let message):
                return "failed to seed Wax store: \(message)"
            }
        }
    }

    /// Build a residual few-shot retriever for the given mode and paths.
    ///
    /// - Parameters:
    ///   - mode: off / auto / wax product modes
    ///   - seedURL: curated seed JSON (caller resolves location)
    ///   - storeURL: Wax store file path (product App Support or test temp)
    ///   - searchMode: defaults to `.text` (`defaultSearchMode`) for product path
    public static func makeRetriever(
        mode: FewShotMode,
        seedURL: URL,
        storeURL: URL,
        searchMode: WaxSearchMode = .text
    ) async throws -> any FewShotRetriever {
        switch mode {
        case .off:
            return NullFewShotRetriever()

        case .auto, .wax:
            guard WaxFewShotStore.isWaxLinked else {
                if mode == .wax {
                    throw Error.waxNotLinked
                }
                return NullFewShotRetriever()
            }

            let seedExists = FileManager.default.fileExists(atPath: seedURL.path)
            if !seedExists {
                if mode == .wax {
                    throw Error.seedNotFound(seedURL)
                }
                // auto: no seed → pure residual FM
                return NullFewShotRetriever()
            }

            let store = WaxFewShotStore(storeURL: storeURL, searchMode: searchMode)
            let needsSeed = FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL)
            if needsSeed {
                do {
                    try await store.seed(fromSeedJSON: seedURL)
                    try FewShotSeedBootstrap.recordSeedHash(storeURL: storeURL, seedURL: seedURL)
                } catch {
                    if mode == .wax {
                        throw Error.seedFailed(String(describing: error))
                    }
                    // auto fail-open (load throw, open fail, etc.)
                    return NullFewShotRetriever()
                }
            }
            return store
        }
    }
}
