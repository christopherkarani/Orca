import Foundation
import CryptoKit
import Darwin

/// Seed content-hash helpers for residual few-shot store reseed.
///
/// Product law: reseed when the store is missing **or** the seed JSON hash
/// no longer matches the last-seeded sidecar **or** the store content hash
/// no longer matches **or** the store format version bumps. Fail-open is the
/// caller's job.
///
/// # Integrity policy (assist only)
///
/// The sidecar fingerprint (`v{N}:<seed-sha256>:<store-sha256>`) is **assist
/// integrity** for residual few-shot quality: it detects same-user App Support
/// drift (replaced `ambig.wax` with a matching seedsha) and forces reseed.
/// It is **not** a multi-user security boundary, not a Zig hard-fence substitute,
/// and not a signed package pin.
public enum FewShotSeedBootstrap: Sendable {
    /// Bump when document/store layout or seed→wax mapping changes so product
    /// stores reseed even if seed JSON bytes are unchanged.
    public static let storeFormatVersion: Int = 1

    /// Sidecar path next to the `.wax` store (e.g. `ambig.wax.seedsha`).
    public static func seedHashSidecarURL(for storeURL: URL) -> URL {
        URL(fileURLWithPath: storeURL.path + ".seedsha")
    }

    /// Exclusive reseed lock file next to the store (e.g. `ambig.wax.reseed.lock`).
    public static func reseedLockURL(for storeURL: URL) -> URL {
        URL(fileURLWithPath: storeURL.path + ".reseed.lock")
    }

    /// Default max wait while contending for the reseed lock (product multi-process).
    public static let reseedLockWaitMs: Int = 500

    /// Poll interval while waiting for the reseed lock.
    public static let reseedLockPollMs: Int = 25

    /// Process-local gate: Darwin `flock` is process-owned (same-PID threads do
    /// not contend). Actor isolation serializes reseed critical sections without
    /// holding a blocking `NSLock` across `await` (thread-pool safe).
    private actor ProcessLocalReseedGate {
        static let shared = ProcessLocalReseedGate()

        func run<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
            try await body()
        }
    }

    /// SHA-256 hex of seed file bytes (content hash for reseed detection).
    ///
    /// Rejects seeds larger than `FewShotSeedLoader.maxSeedFileBytes` (1 MiB)
    /// before reading, matching seed-load size policy.
    public static func seedContentSHA256(of seedURL: URL) throws -> String {
        try FewShotSeedLoader.enforceSeedFileSize(at: seedURL)
        let data = try Data(contentsOf: seedURL)
        if data.count > FewShotSeedLoader.maxSeedFileBytes {
            throw FewShotSeedLoader.SeedError.seedTooLarge(
                data.count,
                max: FewShotSeedLoader.maxSeedFileBytes
            )
        }
        return sha256Hex(data)
    }

    /// SHA-256 hex of the on-disk Wax store file bytes (assist integrity fingerprint).
    public static func storeContentSHA256(of storeURL: URL) throws -> String {
        let data = try Data(contentsOf: storeURL)
        return sha256Hex(data)
    }

    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Encode sidecar payload: `v{storeFormatVersion}:<seed-sha256>:<store-sha256>`.
    public static func encodeSidecarValue(
        seedHash: String,
        storeHash: String,
        version: Int = storeFormatVersion
    ) -> String {
        "v\(version):\(seedHash):\(storeHash)"
    }

    /// Parsed sidecar fields. `storeHash` is nil for legacy `vN:<seed-sha256>` (two fields).
    public struct SidecarPayload: Equatable, Sendable {
        public let version: Int
        public let seedHash: String
        /// Present for current format `vN:seed:store`; nil for legacy `vN:seed`.
        public let storeHash: String?

        public init(version: Int, seedHash: String, storeHash: String?) {
            self.version = version
            self.seedHash = seedHash
            self.storeHash = storeHash
        }
    }

    /// Parse sidecar payload.
    ///
    /// Accepts:
    /// - current: `vN:<seed-sha256>:<store-sha256>`
    /// - legacy: `vN:<seed-sha256>` (missing store field → needsReseed when store exists)
    ///
    /// Bare hashes (no `vN:`) return nil (force reseed).
    public static func parseSidecarValue(_ recorded: String) -> SidecarPayload? {
        let trimmed = recorded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("v") else { return nil }
        guard let firstColon = trimmed.firstIndex(of: ":") else { return nil }
        let versionPart = trimmed[trimmed.index(after: trimmed.startIndex)..<firstColon]
        guard let version = Int(versionPart), version > 0 else { return nil }
        let rest = String(trimmed[trimmed.index(after: firstColon)...])
        guard !rest.isEmpty else { return nil }

        // Current: seedHash:storeHash  |  legacy: seedHash only
        if let secondColon = rest.firstIndex(of: ":") {
            let seedHash = String(rest[..<secondColon])
            let storeHash = String(rest[rest.index(after: secondColon)...])
            guard !seedHash.isEmpty, !storeHash.isEmpty else { return nil }
            // Reject accidental extra colons as corrupt (store hex has none).
            guard !storeHash.contains(":") else { return nil }
            return SidecarPayload(version: version, seedHash: seedHash, storeHash: storeHash)
        }
        return SidecarPayload(version: version, seedHash: rest, storeHash: nil)
    }

    /// Whether the Wax store needs (re)seeding from `seedURL`.
    ///
    /// True when:
    /// - store file is missing, or
    /// - seed file is missing (caller should fail-open / error separately), or
    /// - sidecar is missing / unreadable / unparseable, or
    /// - sidecar format version ≠ `storeFormatVersion`, or
    /// - sidecar seed hash ≠ current seed content hash, or
    /// - sidecar store hash field missing (legacy `vN:seed`) while store exists, or
    /// - sidecar store hash ≠ current store content hash on disk
    ///
    /// Assist integrity only — not multi-user security.
    public static func needsReseed(storeURL: URL, seedURL: URL) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storeURL.path) {
            return true
        }
        guard fm.fileExists(atPath: seedURL.path) else {
            return true
        }
        let sidecar = seedHashSidecarURL(for: storeURL)
        guard let recorded = try? String(contentsOf: sidecar, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !recorded.isEmpty
        else {
            return true
        }
        guard let parsed = parseSidecarValue(recorded) else {
            // Bare-hash or corrupt sidecar → force reseed under current format.
            return true
        }
        if parsed.version != storeFormatVersion {
            return true
        }
        guard let currentSeed = try? seedContentSHA256(of: seedURL) else {
            return true
        }
        if parsed.seedHash != currentSeed {
            return true
        }
        // Legacy two-field payload: treat as missing store fingerprint → reseed.
        guard let recordedStoreHash = parsed.storeHash else {
            return true
        }
        guard let currentStore = try? storeContentSHA256(of: storeURL) else {
            return true
        }
        return recordedStoreHash != currentStore
    }

    /// Persist seed + store content hashes after a successful seed into `storeURL`.
    ///
    /// Writes `v{storeFormatVersion}:<seedHash>:<storeHash>` where `storeHash` is
    /// the SHA-256 of the store file currently on disk.
    public static func recordSeedHash(storeURL: URL, seedHash: String) throws {
        let storeHash = try storeContentSHA256(of: storeURL)
        let sidecar = seedHashSidecarURL(for: storeURL)
        let dir = sidecar.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = encodeSidecarValue(seedHash: seedHash, storeHash: storeHash)
        try payload.write(to: sidecar, atomically: true, encoding: .utf8)
    }

    /// Record hash of `seedURL` and on-disk store after successful seed.
    public static func recordSeedHash(storeURL: URL, seedURL: URL) throws {
        let seedHash = try seedContentSHA256(of: seedURL)
        try recordSeedHash(storeURL: storeURL, seedHash: seedHash)
    }

    // MARK: - First-run App Support seed bootstrap (P2)

    /// Copy package (or other source) seed into App Support when the destination
    /// is missing. No-op when destination already exists as a regular file.
    ///
    /// Product first-run: hosts / CLI call this when package seed exists but
    /// Application Support `seed.json` does not, so subsequent resolves can use
    /// the App Support copy (when it still matches package content hash).
    ///
    /// - Returns: `true` when a copy was performed; `false` when skipped
    ///   (dest already present, source missing, or source is not a file).
    /// - Throws: FileManager errors (create directory / copy).
    @discardableResult
    public static func bootstrapAppSupportSeedIfNeeded(
        from packageSeedURL: URL,
        to appSupportSeedURL: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        var destIsDir: ObjCBool = false
        if fileManager.fileExists(atPath: appSupportSeedURL.path, isDirectory: &destIsDir),
           !destIsDir.boolValue
        {
            return false
        }
        var srcIsDir: ObjCBool = false
        guard fileManager.fileExists(atPath: packageSeedURL.path, isDirectory: &srcIsDir),
              !srcIsDir.boolValue
        else {
            return false
        }
        let parent = appSupportSeedURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        // If a directory wrongly sits at the dest path, remove it then copy.
        if destIsDir.boolValue {
            try fileManager.removeItem(at: appSupportSeedURL)
        }
        try fileManager.copyItem(at: packageSeedURL, to: appSupportSeedURL)
        return true
    }

    // MARK: - Exclusive reseed ownership

    /// Errors for reseed lock acquisition.
    public enum LockError: Error, CustomStringConvertible, Equatable {
        case openFailed(String)
        case contentionTimeout

        public var description: String {
            switch self {
            case .openFailed(let message):
                return "reseed lock open failed: \(message)"
            case .contentionTimeout:
                return "reseed lock contention timeout"
            }
        }
    }

    /// Run `body` while holding an exclusive flock on the store's reseed lock file
    /// **and** a process-local actor gate (Darwin flock does not serialize same-PID
    /// threads; a blocking `NSLock` across `await` is unsafe on the cooperative pool).
    ///
    /// Multi-process safe (`flock` LOCK_EX). Polls up to `waitMs` when the lock is
    /// held elsewhere. Callers map `LockError.contentionTimeout` to `.auto` Null
    /// fail-open or `.wax` throw. Never hangs forever.
    public static func withReseedLock<T: Sendable>(
        storeURL: URL,
        waitMs: Int = reseedLockWaitMs,
        body: @Sendable () async throws -> T
    ) async throws -> T {
        // Same-process serialization before open/flock (flock is process-owned on Darwin).
        try await ProcessLocalReseedGate.shared.run {
            try await withReseedLockCrossProcess(
                storeURL: storeURL,
                waitMs: waitMs,
                body: body
            )
        }
    }

    /// Cross-process flock portion (called under process-local gate).
    private static func withReseedLockCrossProcess<T: Sendable>(
        storeURL: URL,
        waitMs: Int,
        body: @Sendable () async throws -> T
    ) async throws -> T {
        let lockURL = reseedLockURL(for: storeURL)
        let parent = lockURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let path = lockURL.path
        // O_CLOEXEC: do not leak the lock fd across exec of child processes.
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            let err = String(cString: strerror(errno))
            throw LockError.openFailed(err)
        }
        defer { close(fd) }

        let deadline = ContinuousClock.now + .milliseconds(max(0, waitMs))
        var acquired = false
        while true {
            let rc = flock(fd, LOCK_EX | LOCK_NB)
            if rc == 0 {
                acquired = true
                break
            }
            let err = errno
            if err == EINTR {
                // Interrupted system call — retry without consuming wait budget heavily.
                continue
            }
            if err != EWOULDBLOCK && err != EAGAIN {
                let msg = String(cString: strerror(err))
                throw LockError.openFailed(msg)
            }
            if ContinuousClock.now >= deadline {
                break
            }
            try await Task.sleep(for: .milliseconds(reseedLockPollMs))
        }
        guard acquired else {
            throw LockError.contentionTimeout
        }
        defer {
            // Best-effort unlock; retry EINTR.
            while flock(fd, LOCK_UN) != 0 {
                if errno != EINTR { break }
            }
        }

        return try await body()
    }
}
