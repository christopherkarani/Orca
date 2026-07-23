import Foundation
import CryptoKit

/// Seed content-hash helpers for residual few-shot store reseed.
///
/// Product law: reseed when the store is missing **or** the seed JSON hash
/// no longer matches the last-seeded sidecar. Fail-open is the caller's job.
public enum FewShotSeedBootstrap: Sendable {
    /// Sidecar path next to the `.wax` store (e.g. `ambig.wax.seedsha`).
    public static func seedHashSidecarURL(for storeURL: URL) -> URL {
        URL(fileURLWithPath: storeURL.path + ".seedsha")
    }

    /// SHA-256 hex of seed file bytes (content hash for reseed detection).
    public static func seedContentSHA256(of seedURL: URL) throws -> String {
        let data = try Data(contentsOf: seedURL)
        return sha256Hex(data)
    }

    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether the Wax store needs (re)seeding from `seedURL`.
    ///
    /// True when:
    /// - store file is missing, or
    /// - seed file is missing (caller should fail-open / error separately), or
    /// - sidecar hash is missing / unreadable, or
    /// - sidecar hash ≠ current seed content hash
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
        guard let current = try? seedContentSHA256(of: seedURL) else {
            return true
        }
        return recorded != current
    }

    /// Persist the seed hash after a successful seed into `storeURL`.
    public static func recordSeedHash(storeURL: URL, hash: String) throws {
        let sidecar = seedHashSidecarURL(for: storeURL)
        let dir = sidecar.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try hash.write(to: sidecar, atomically: true, encoding: .utf8)
    }

    /// Record hash of `seedURL` after successful seed.
    public static func recordSeedHash(storeURL: URL, seedURL: URL) throws {
        let hash = try seedContentSHA256(of: seedURL)
        try recordSeedHash(storeURL: storeURL, hash: hash)
    }
}
