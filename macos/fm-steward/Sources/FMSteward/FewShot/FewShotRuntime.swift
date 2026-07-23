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
/// - `.auto` → fail-open to Null on missing seed, load throw, open/seed failure,
///   reseed-lock contention, or Wax unlinked
/// - `.wax` → throws on missing seed / load / open failure / Wax unlinked / lock fail
/// - Default search mode is **text** (CI-safe; no embedder required)
///
/// Reseed when store is missing **or** seed/store content hash / format version ≠
/// sidecar (`*.wax.seedsha`, payload `v{N}:<seed-sha256>:<store-sha256>`).
///
/// **Lock policy (R6):** when `needsReseed` is false, open the store **without**
/// the exclusive reseed lock (fast path). When reseed is needed, take flock +
/// process-local lock, recheck under lock, then seed → recordSeedHash.
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

            // Fast path: store + sidecar fingerprint already valid — open without reseed lock.
            if !FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL) {
                return WaxFewShotStore(storeURL: storeURL, searchMode: searchMode)
            }

            // Slow path: exclusive ownership for needsReseed → seed → recordSeedHash.
            do {
                return try await FewShotSeedBootstrap.withReseedLock(storeURL: storeURL) {
                    try await openOrSeedStore(
                        mode: mode,
                        seedURL: seedURL,
                        storeURL: storeURL,
                        searchMode: searchMode
                    )
                }
            } catch let error as FewShotSeedBootstrap.LockError {
                if mode == .wax {
                    throw Error.seedFailed(error.description)
                }
                // auto: lock contention / open fail → fail-open Null
                return NullFewShotRetriever()
            } catch let error as FewShotRuntime.Error {
                // Strict .wax failures from openOrSeedStore (seedFailed / etc.)
                throw error
            } catch {
                if mode == .wax {
                    throw Error.seedFailed(String(describing: error))
                }
                return NullFewShotRetriever()
            }
        }
    }

    /// Under reseed lock: re-check hash, seed if needed, return live store or Null/throw.
    private static func openOrSeedStore(
        mode: FewShotMode,
        seedURL: URL,
        storeURL: URL,
        searchMode: WaxSearchMode
    ) async throws -> any FewShotRetriever {
        let store = WaxFewShotStore(storeURL: storeURL, searchMode: searchMode)
        // Re-check under lock (TOCTOU: another process/task may have finished seeding).
        let needsSeed = FewShotSeedBootstrap.needsReseed(storeURL: storeURL, seedURL: seedURL)
        if needsSeed {
            do {
                try await store.seed(fromSeedJSON: seedURL)
                // Hashes seed + store bytes on disk into sidecar.
                try FewShotSeedBootstrap.recordSeedHash(storeURL: storeURL, seedURL: seedURL)
            } catch {
                // Fail-open: never leave a half-open store referenced by auto callers.
                await store.close()
                if mode == .wax {
                    throw Error.seedFailed(String(describing: error))
                }
                return NullFewShotRetriever()
            }
        }
        return store
    }
}
