//! Test/module root for shell_engine-only gates.
//! Run: ./scripts/zig build test-shell-engine

pub const shell_engine = @import("shell_engine/mod.zig");

test {
    _ = shell_engine;
    _ = shell_engine.tokenize;
    _ = shell_engine.packs;
    _ = shell_engine.allowlist;
    _ = @import("shell_engine/corpus_test.zig");
}
